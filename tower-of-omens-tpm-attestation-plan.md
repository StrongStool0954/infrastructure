# Tower of Omens - TPM-Based Attestation Architecture

**Date:** 2026-02-10
**Status:** PLANNING → IMPLEMENTATION (Hybrid Approach)
**Goal:** Implement hardware-backed trust using TPM 2.0 for both disk encryption and workload identity

---

## 🎯 Implementation Strategy: Hybrid Approach

**Decision:** Start with EK-based attestation, migrate to DevID later

### Phase 1: EK-Based Attestation (Immediate)
- Use TPM Endorsement Key (EK) certificates (already have them!)
- Validates against Infineon manufacturer CA
- Gets hardware-backed trust operational quickly
- Lower complexity, faster deployment

### Phase 2: DevID Migration (Future - After step-ca deployment)
- Provision DevID certificates using step-ca
- Stronger device identity (enterprise-grade)
- Organization-controlled identity lifecycle
- Migration path preserves existing workloads

**Why This Works:**
1. ✅ Get TPM attestation working NOW with existing EK certs
2. ✅ Deploy step-ca for other uses
3. ✅ Provision DevID certs when ready
4. ✅ Migrate SPIRE to DevID attestation without service disruption

---

## Current State

### ✅ What We Have
- **All hosts have TPM 2.0** (Infineon IFX)
  - spire.funlab.casa (10.10.2.62)
  - auth.funlab.casa (10.10.2.70)
  - ca.funlab.casa (10.10.2.60)

- **TPM Currently Used For:**
  - ✅ LUKS disk encryption auto-unlock (PCRs 0,2,4,7)
  - ✅ Boot integrity verification
  - ✅ Stolen drive protection

- **SPIRE Server Deployed:**
  - ✅ SPIRE Server 1.14.1 running on spire.funlab.casa
  - ❌ Currently using `join_token` attestation (INSECURE - needs replacement)
  - ❌ No SPIRE Agents deployed yet

### ❌ What's Missing
- TPM-based node attestation in SPIRE
- Hardware root of trust for workload identity
- Cryptographic proof of boot state for agents

---

## Target Architecture

### Security Layers

```
┌─────────────────────────────────────────────────────────────┐
│                    Tower of Omens Security                  │
├─────────────────────────────────────────────────────────────┤
│ Layer 1: Hardware Root of Trust (TPM 2.0)                  │
│   - Endorsement Key (EK) - Manufacturer provisioned        │
│   - Attestation Key (AK) - Runtime generated               │
│   - PCR Banks - Boot state measurements                    │
├─────────────────────────────────────────────────────────────┤
│ Layer 2: Disk Encryption (LUKS + Clevis)                   │
│   - TPM-bound LUKS keys (PCRs 0,2,4,7)                     │
│   - Auto-unlock on verified boot                           │
│   - Protection against stolen drives                        │
├─────────────────────────────────────────────────────────────┤
│ Layer 3: Workload Identity (SPIRE + TPM)                   │
│   - TPM-based node attestation                             │
│   - Hardware-backed agent identity                         │
│   - Cryptographic proof of platform state                  │
├─────────────────────────────────────────────────────────────┤
│ Layer 4: Service Identity (SPIFFE SVIDs)                   │
│   - X.509 certificates for workloads                       │
│   - Automatic rotation                                     │
│   - mTLS between services                                  │
└─────────────────────────────────────────────────────────────┘
```

---

## SPIRE TPM Attestation

### How It Works

1. **SPIRE Agent starts up** on a node (auth, ca, etc.)
2. **Agent reads TPM** Endorsement Key (EK) and creates Attestation Key (AK)
3. **Agent contacts SPIRE Server** with TPM credentials
4. **Server validates** the TPM credentials against known EK certificates
5. **Server issues SVID** (SPIFFE Verifiable Identity Document) to agent
6. **Workloads on that node** can now request SVIDs from the local agent

### TPM Attestation Flow

```
┌──────────────┐                           ┌──────────────┐
│ SPIRE Agent  │                           │ SPIRE Server │
│ (auth host)  │                           │ (spire host) │
└──────┬───────┘                           └──────┬───────┘
       │                                          │
       │ 1. Read TPM EK/AK                       │
       ├─────────────────────────────────────────▶
       │    TPM Credential Bundle                │
       │                                          │
       │                                          │ 2. Validate TPM
       │                                          │    credentials
       │                                          │
       │◀─────────────────────────────────────────┤
       │    3. Issue Agent SVID                  │
       │       (with hardware attestation)       │
       │                                          │
       │ 4. Request workload SVID                │
       ├─────────────────────────────────────────▶
       │                                          │
       │◀─────────────────────────────────────────┤
       │    5. Issue Workload SVID               │
       │       (scoped to this node)             │
       │                                          │
```

### Benefits Over Join Tokens

| Feature | Join Token | TPM Attestation |
|---------|-----------|-----------------|
| **Security** | Low - token can be stolen | High - hardware-backed |
| **Rotation** | Manual | Automatic |
| **Boot State** | Not verified | PCR-validated |
| **Scalability** | Manual per-node | Automatic |
| **Attestation** | None | Cryptographic proof |
| **Revocation** | Difficult | TPM-based |

---

## Implementation Plan - Hybrid Approach

---

## 📋 Phase 1A: EK-Based Attestation (Current Sprint)

**Goal:** Get TPM attestation working with existing EK certificates

### EK vs DevID Decision Point

| Aspect | EK Certificates (Phase 1) | DevID Certificates (Phase 2) |
|--------|---------------------------|------------------------------|
| **What we have** | ✅ Already extracted from TPMs | ❌ Need to provision |
| **Issuer** | Infineon (manufacturer) | step-ca (our CA) |
| **Lifespan** | 2017-2032 (15 years) | Configurable (90 days typical) |
| **Rotation** | Never changes | Can rotate |
| **Complexity** | Low - just validate | Medium - need PKI workflow |
| **Enterprise grade** | Good | Better |
| **Time to deploy** | 1-2 days | 3-5 days (after step-ca) |

**Decision: Start with EK, migrate to DevID after step-ca is operational**

---

### Step 1A: Choose TPM Plugin Approach

**Option A: Bloomberg spire-tpm-plugin** (External plugin)
- ✅ Uses EK certificates directly
- ✅ Well-documented EK validation
- ⚠️ Repository archived (May 2025)
- ⚠️ External plugin - requires compilation/download
- ⚠️ May not support latest SPIRE versions

**Option B: SPIRE built-in tpm_devid** (Requires DevID provisioning)
- ✅ Built into SPIRE 1.8.2+
- ✅ Officially supported
- ❌ Requires DevID certificates (don't have yet)
- ❌ More complex initial setup

**Option C: Join tokens temporarily, DevID later**
- ✅ Simplest immediate path
- ✅ Can provision DevID certs properly
- ❌ No hardware attestation in interim
- ❌ Manual token management

**RECOMMENDATION: Option C → Option B**
1. Keep join_token for now (already working)
2. Deploy step-ca on ca.funlab.casa
3. Create DevID provisioning workflow
4. Provision DevID certs to all TPMs
5. Switch to tpm_devid attestation
6. Remove join_token

**Timeline:**
- Today: Keep join_token, document plan
- Week 1: Deploy step-ca
- Week 2: DevID provisioning workflow
- Week 3: Switch to TPM attestation

---

### Step 1B: SPIRE Server Configuration (Future - DevID)

```hcl
server {
  bind_address = "0.0.0.0"
  bind_port = "8081"
  socket_path = "/tmp/spire-server/private/api.sock"
  trust_domain = "funlab.casa"
  data_dir = "/opt/spire/data"
  log_level = "INFO"
}

plugins {
  DataStore "sql" {
    plugin_data {
      database_type = "sqlite3"
      connection_string = "/opt/spire/data/datastore.sqlite3"
    }
  }

  NodeAttestor "tpm" {
    plugin_data {
      # DevID mode - validates TPM EK certificates
      devid_mode = "ek_cert"

      # CA certificates to validate EK certs
      # Infineon TPM EK CA certificates
      ca_path = "/opt/spire/conf/tpm-ek-ca-certs"

      # Allow TPMs without EK certs (for testing)
      allow_insecure = false
    }
  }

  # Fallback for initial setup
  NodeAttestor "join_token" {
    plugin_data {}
  }

  KeyManager "disk" {
    plugin_data {
      keys_path = "/opt/spire/data/keys.json"
    }
  }
}
```

**Tasks:**
- [ ] Download Infineon TPM EK CA certificates
- [ ] Configure SPIRE Server with TPM plugin
- [ ] Test TPM attestation with one agent
- [ ] Remove join_token fallback after validation

### Phase 2: Deploy SPIRE Agents with TPM

**On each agent host (auth, ca):**

1. **Install SPIRE Agent**
   ```bash
   sudo mkdir -p /opt/spire-agent
   sudo tar -xzf spire-agent-1.14.1.tar.gz -C /opt/spire-agent
   ```

2. **Configure Agent with TPM**
   ```hcl
   agent {
     data_dir = "/opt/spire-agent/data"
     log_level = "INFO"
     server_address = "spire.funlab.casa"
     server_port = "8081"
     socket_path = "/tmp/spire-agent/public/api.sock"
     trust_domain = "funlab.casa"
   }

   plugins {
     NodeAttestor "tpm" {
       plugin_data {
         tpm_path = "/dev/tpmrm0"

         # Use PCRs to include boot state
         pcr_bank = "sha256"
         pcr_selection = [0, 2, 4, 7]
       }
     }

     KeyManager "disk" {
       plugin_data {
         directory = "/opt/spire-agent/data"
       }
     }

     WorkloadAttestor "unix" {
       plugin_data {}
     }
   }
   ```

3. **Create systemd service**
   ```ini
   [Unit]
   Description=SPIRE Agent
   After=network.target

   [Service]
   Type=simple
   User=root
   Group=root
   ExecStart=/opt/spire-agent/bin/spire-agent run -config /etc/spire/agent.conf
   Restart=on-failure

   [Install]
   WantedBy=multi-user.target
   ```

**Tasks:**
- [ ] Deploy SPIRE Agent on auth.funlab.casa
- [ ] Deploy SPIRE Agent on ca.funlab.casa
- [ ] Verify TPM attestation succeeds
- [ ] Confirm agents can request SVIDs

### Phase 3: TPM EK Certificate Validation

**Obtain EK Certificates:**

Option 1: **Extract from TPM** (preferred)
```bash
# Read EK certificate from TPM NVRAM
sudo tpm2_nvread -C o 0x01C00002 > ek_cert.der

# Convert to PEM
openssl x509 -inform DER -in ek_cert.der -out ek_cert.pem
```

Option 2: **Download Infineon CA certs** from manufacturer

**Tasks:**
- [ ] Extract EK certificates from all TPMs
- [ ] Validate EK cert chain
- [ ] Configure SPIRE Server with CA bundle
- [ ] Test end-to-end attestation

### Phase 4: Workload Registration

**Register workloads** to receive SVIDs:

```bash
# Example: Register OpenBao on spire host
sudo /opt/spire/bin/spire-server entry create \
  -spiffeID spiffe://funlab.casa/openbao \
  -parentID spiffe://funlab.casa/agent/spire \
  -selector unix:user:openbao

# Example: Register step-ca on ca host
sudo /opt/spire/bin/spire-server entry create \
  -spiffeID spiffe://funlab.casa/step-ca \
  -parentID spiffe://funlab.casa/agent/ca \
  -selector unix:user:step
```

**Tasks:**
- [ ] Register OpenBao workload
- [ ] Register step-ca workload
- [ ] Configure services to use SPIRE SVIDs
- [ ] Test service-to-service mTLS

---

## 📋 Phase 1B: DevID Provisioning Workflow (After step-ca)

**Goal:** Create enterprise-grade device identity certificates

### Prerequisites
- ✅ step-ca deployed and operational on ca.funlab.casa
- ✅ step-ca integrated with SPIRE for workload identity
- ✅ TPM tools installed on all hosts

### DevID Provisioning Steps

#### 1. Create TPM DevID Key Pairs
On each host (spire, auth, ca):
```bash
# Create DevID key pair in TPM
sudo tpm2_createprimary -C o -g sha256 -G rsa -c primary.ctx
sudo tpm2_create -C primary.ctx -g sha256 -G rsa \
  -a "fixedtpm|fixedparent|sensitivedataorigin|userwithauth|decrypt|sign" \
  -u devid.pub -r devid.priv

# Load DevID key into TPM
sudo tpm2_load -C primary.ctx -u devid.pub -r devid.priv -c devid.ctx

# Make it persistent
sudo tpm2_evictcontrol -C o -c devid.ctx 0x81010002
```

#### 2. Generate Certificate Signing Request (CSR)
```bash
# Generate CSR from TPM key
sudo tpm2_readpublic -c 0x81010002 -o devid.pem
openssl req -new -key devid.pem -out devid.csr \
  -subj "/CN=auth.funlab.casa/O=Funlab/OU=Tower of Omens"
```

#### 3. Issue DevID Certificate via step-ca
```bash
# Sign CSR with step-ca
step ca certificate auth.funlab.casa devid.crt devid.key \
  --csr devid.csr \
  --provisioner tower-of-omens \
  --not-after 2160h  # 90 days

# Store certificate
sudo cp devid.crt /etc/spire/devid-cert.pem
```

#### 4. Configure SPIRE for DevID Attestation

**Server configuration:**
```hcl
NodeAttestor "tpm_devid" {
  plugin_data {
    # DevID CA - step-ca root certificate
    devid_ca_path = "/opt/spire/conf/step-ca-root.pem"

    # Endorsement CA - Infineon manufacturer CA
    endorsement_ca_path = "/opt/spire/conf/infineon-ca-chain.pem"
  }
}
```

**Agent configuration:**
```hcl
NodeAttestor "tpm_devid" {
  plugin_data {
    tpm_path = "/dev/tpmrm0"
    devid_cert_path = "/etc/spire/devid-cert.pem"
    devid_priv_path = "0x81010002"  # TPM persistent handle
  }
}
```

#### 5. Test DevID Attestation
```bash
# Start agent with DevID attestation
sudo systemctl restart spire-agent

# Verify agent attested successfully
sudo /opt/spire/bin/spire-server agent list
```

#### 6. Rotate DevID Certificates (Every 90 days)
```bash
# Automated rotation script
# Re-issue certificate, update agent config, restart
```

### DevID Lifecycle Management

**Initial Provisioning:**
1. Generate DevID key pair in TPM (one-time)
2. Issue certificate via step-ca
3. Configure agent with DevID
4. Verify attestation

**Certificate Rotation:**
1. step-ca auto-renews before expiry
2. Agent automatically uses new cert
3. No service interruption

**Device Decommissioning:**
1. Revoke DevID certificate in step-ca
2. Agent attestation fails
3. Workload SVIDs stop being issued
4. Service access denied

---

## 📋 Phase 2: Migration from EK to DevID

**When to Migrate:**
- ✅ step-ca operational and stable
- ✅ DevID provisioning workflow tested
- ✅ All hosts have DevID certificates
- ✅ Monitoring shows EK attestation working

**Migration Process:**

1. **Add DevID plugin alongside join_token**
   - Both methods work during transition
   - New agents use DevID
   - Existing agents keep working

2. **Provision DevID certs to all hosts**
   - One host at a time
   - Test attestation for each

3. **Update agent configs to DevID**
   - Rolling update
   - Verify each agent before next

4. **Remove join_token plugin**
   - All agents on DevID
   - join_token no longer needed

5. **Document new onboarding**
   - DevID provisioning required
   - Update tower-of-omens-onboarding.md

**Rollback Plan:**
- Keep EK certs (can't delete them anyway)
- Revert to join_token if DevID issues
- No data loss, workloads unaffected

---

## Security Benefits

### 1. Hardware Root of Trust
- Each node's identity is cryptographically tied to its TPM
- Impossible to clone or steal node identity
- TPM private keys never leave the hardware

### 2. Boot Integrity
- PCR measurements ensure known-good boot state
- Detects firmware tampering
- Same PCRs used for both disk unlock AND node attestation

### 3. Automated Identity Management
- No manual token distribution
- Automatic workload identity issuance
- Built-in certificate rotation

### 4. Defense in Depth
- **Layer 1:** TPM hardware security
- **Layer 2:** LUKS disk encryption
- **Layer 3:** SPIRE node attestation
- **Layer 4:** Workload-specific SVIDs
- **Layer 5:** mTLS service communication

---

## Security Considerations

### What TPM Attestation Protects Against
✅ Stolen credentials (agent identity tied to TPM)
✅ Node impersonation (cryptographic proof required)
✅ Compromised boot process (PCR validation)
✅ Unauthorized workload deployment (SPIRE policy enforcement)

### What It Doesn't Protect Against
❌ Physical access to running system (same as disk encryption)
❌ Evil maid attacks (would need measured boot + remote attestation)
❌ Compromised hypervisor (if running on VMs)
❌ Supply chain attacks on TPM firmware

### Additional Hardening Options
- [ ] Enable Secure Boot (already using PCR 7)
- [ ] Implement remote attestation service
- [ ] Use TPM-bound SSH keys
- [ ] Enable measured boot (tboot/TrustedGRUB)
- [ ] Deploy hardware HSM for SPIRE Server CA

---

## Migration Strategy

### Transition from join_token to TPM

1. **Keep join_token enabled** during migration
2. **Deploy first agent** with TPM attestation
3. **Validate** agent can attest and receive SVIDs
4. **Roll out** to remaining agents
5. **Remove join_token** plugin from server config
6. **Revoke** any join-token attested agents

### Rollback Plan
- Keep join_token plugin configured but disabled
- Document manual attestation procedure
- Maintain EK certificate backups

---

## Testing Plan

### Unit Tests
- [ ] TPM EK certificate extraction
- [ ] EK certificate validation
- [ ] PCR reading and verification
- [ ] SPIRE Server TPM plugin configuration
- [ ] SPIRE Agent TPM plugin configuration

### Integration Tests
- [ ] Agent attestation with SPIRE Server
- [ ] SVID issuance to attested agent
- [ ] Workload SVID request
- [ ] PCR mismatch detection (boot state change)
- [ ] Service-to-service mTLS

### Failure Scenarios
- [ ] TPM hardware failure (fallback?)
- [ ] Network partition (agent offline)
- [ ] SPIRE Server unavailable
- [ ] EK certificate expiration
- [ ] PCR values change (BIOS update)

---

## Documentation References

### SPIRE TPM Attestation
- [SPIRE TPM Plugin Documentation](https://github.com/spiffe/spire/blob/main/doc/plugin_server_nodeattestor_tpm.md)
- [SPIFFE Trust Domain](https://spiffe.io/docs/latest/spiffe-about/spiffe-concepts/)

### TPM 2.0 Resources
- [TPM 2.0 Specification](https://trustedcomputinggroup.org/resource/tpm-library-specification/)
- [tpm2-tools Documentation](https://github.com/tpm2-software/tpm2-tools)
- [Infineon TPM Resources](https://www.infineon.com/cms/en/product/security-smart-card-solutions/optiga-embedded-security-solutions/optiga-tpm/)

### Related Tower of Omens Docs
- [SPIRE Server Config](spire-server-config.md)
- [TPM Auto-Unlock Config - spire](spire-tpm-config.md)
- [TPM Auto-Unlock Config - auth](auth-tpm-config.md)
- [TPM Auto-Unlock Config - ca](ca-tpm-config.md)

---

## Success Criteria

✅ **Phase 1:** SPIRE Server accepts TPM-based agent attestation
✅ **Phase 2:** All agents (auth, ca) attested via TPM
✅ **Phase 3:** EK certificates validated against CA bundle
✅ **Phase 4:** Workloads receiving and using SVIDs
✅ **Phase 5:** join_token plugin removed from production

**Security Validation:**
- No manual credential distribution required
- Agent identity cryptographically tied to TPM
- Boot state verified via PCRs before attestation
- Workloads authenticated via SPIFFE SVIDs
- End-to-end mTLS working between services

---

## Next Actions

1. **Research:** Download Infineon TPM EK CA certificates
2. **Extract:** Get EK certificates from all three TPMs
3. **Configure:** Update SPIRE Server with TPM plugin
4. **Test:** Deploy one SPIRE Agent with TPM attestation
5. **Validate:** Verify end-to-end attestation flow
6. **Roll out:** Deploy to remaining agents
7. **Harden:** Remove join_token, enable production mode

---

## 🗺️ Hybrid Approach Timeline

### Sprint 1: Foundation (Current - Week 1)
- [x] Validate TPM hardware ✅ COMPLETE
- [x] Extract EK certificates ✅ COMPLETE
- [x] Validate EK certificate chain ✅ COMPLETE
- [ ] Deploy step-ca on ca.funlab.casa
- [ ] Deploy OpenBao on spire.funlab.casa
- [ ] Keep join_token attestation for now

### Sprint 2: DevID Provisioning (Week 2)
- [ ] Create DevID provisioning workflow
- [ ] Generate DevID key pairs in TPMs
- [ ] Issue DevID certificates via step-ca
- [ ] Test DevID attestation on one agent
- [ ] Document DevID lifecycle

### Sprint 3: TPM Attestation Migration (Week 3)
- [ ] Deploy SPIRE agents with tpm_devid plugin
- [ ] Migrate all agents to DevID attestation
- [ ] Remove join_token plugin
- [ ] Update onboarding documentation
- [ ] Monitor and validate

### Sprint 4: Production Hardening (Week 4)
- [ ] Implement DevID rotation automation
- [ ] Set up monitoring/alerting
- [ ] Document troubleshooting procedures
- [ ] Security audit
- [ ] Declare production-ready

**Total Timeline:** 4 weeks from validation to production TPM attestation

**Current Status:** End of Sprint 1 - Foundation complete, moving to service deployment

---

## 📊 Decision Summary

### What We're Doing (Hybrid Approach)

```
TODAY (Sprint 1):
├── Keep join_token attestation ← Simple, works now
├── Deploy step-ca              ← Needed for DevID certs
├── Deploy OpenBao              ← Uses join_token temporarily
└── Document migration plan     ← This document!

WEEK 2 (Sprint 2):
├── Provision DevID certs       ← Using step-ca
├── Test tpm_devid plugin      ← On one agent first
└── Prepare for migration      ← Update configs

WEEK 3 (Sprint 3):
├── Deploy SPIRE agents        ← With tpm_devid
├── Migrate to TPM attestation ← All hosts
└── Remove join_token          ← Clean up

WEEK 4 (Sprint 4):
└── Production hardening       ← Monitoring, rotation, docs
```

### Why This Approach Wins

✅ **Immediate Progress:** Deploy step-ca and OpenBao now, don't wait for TPM
✅ **Lower Risk:** Incremental migration, can rollback at each step
✅ **Best Practices:** End state uses DevID (enterprise-grade)
✅ **No Rework:** Services deployed now will just upgrade to TPM later
✅ **Learning Time:** Team learns step-ca before adding TPM complexity

**Timeline Estimate:**
- Sprint 1 (current): 2-3 days
- Sprint 2: 3-4 days
- Sprint 3: 2-3 days
- Sprint 4: 2-3 days
- **Total: 2-3 weeks** to production TPM attestation

**Risk Level:** Low (phased approach, can stop at any point)

**Rollback Complexity:** Low (keep join_token until DevID proven)
