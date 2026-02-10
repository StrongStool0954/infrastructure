# SPIRE TPM Attestation Migration Plan

**Migration:** join_token → tpm_devid
**Target Date:** Sprint 3 (Week 3)
**Status:** Planned
**Risk Level:** Medium

---

## Executive Summary

This document outlines the migration from temporary `join_token` attestation to production-ready `tpm_devid` attestation for all SPIRE agents in the Tower of Omens infrastructure.

**Current State:**
- 3 SPIRE agents using `join_token` attestation (temporary)
- TPM DevID certificates provisioned on all hosts
- Infrastructure operational with workload identity

**Target State:**
- 3 SPIRE agents using `tpm_devid` attestation (hardware-backed)
- Zero reliance on join tokens
- Production-ready TPM-based trust

**Benefits:**
- Hardware-backed agent attestation
- Automatic agent re-attestation
- Stronger security posture
- Elimination of join token management

---

## Prerequisites

### Infrastructure Requirements

✅ **Completed:**
- [x] TPM 2.0 hardware on all hosts (Infineon)
- [x] TPM DevID keys generated (handle 0x81010002)
- [x] DevID certificates issued via step-ca
- [x] SPIRE Server v1.14.1 operational
- [x] SPIRE Agents v1.14.1 on all 3 hosts
- [x] Workloads registered and functioning

⏳ **Required for Migration:**
- [ ] SPIRE Server configured with tpm_devid plugin
- [ ] step-ca root CA certificate distributed to all hosts
- [ ] TPM attestation testing on one agent (pilot)
- [ ] Rollback procedure documented and tested

---

## Migration Architecture

### Current Architecture (join_token)

```
┌─────────────────────────────────────────────────────────────┐
│ SPIRE Server (spire.funlab.casa)                           │
│                                                             │
│  Plugins:                                                   │
│  ├── NodeAttestor: join_token (temporary)                  │
│  └── DataStore: sqlite3                                    │
└─────────────────────────────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ SPIRE Agent  │  │ SPIRE Agent  │  │ SPIRE Agent  │
│ (auth)       │  │ (ca)         │  │ (spire)      │
│              │  │              │  │              │
│ join_token   │  │ join_token   │  │ join_token   │
│ ❌ Temporary │  │ ❌ Temporary │  │ ❌ Temporary │
└──────────────┘  └──────────────┘  └──────────────┘
```

**Limitations:**
- Join tokens expire (need regeneration)
- No automatic re-attestation
- Tokens can be compromised
- Not production-ready

---

### Target Architecture (tpm_devid)

```
┌─────────────────────────────────────────────────────────────┐
│ SPIRE Server (spire.funlab.casa)                           │
│                                                             │
│  Plugins:                                                   │
│  ├── NodeAttestor: tpm_devid (production)                  │
│  │   ├── DevID CA Bundle: /opt/spire/conf/devid-ca.pem    │
│  │   └── Validates: DevID certificates from step-ca       │
│  └── DataStore: sqlite3                                    │
└─────────────────────────────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ SPIRE Agent  │  │ SPIRE Agent  │  │ SPIRE Agent  │
│ (auth)       │  │ (ca)         │  │ (spire)      │
│              │  │              │  │              │
│ tpm_devid    │  │ tpm_devid    │  │ tpm_devid    │
│ ✅ Hardware  │  │ ✅ Hardware  │  │ ✅ Hardware  │
│    Backed    │  │    Backed    │  │    Backed    │
│              │  │              │  │              │
│ TPM Key:     │  │ TPM Key:     │  │ TPM Key:     │
│ 0x81010002   │  │ 0x81010002   │  │ 0x81010002   │
│              │  │              │  │              │
│ DevID Cert:  │  │ DevID Cert:  │  │ DevID Cert:  │
│ step-ca      │  │ step-ca      │  │ step-ca      │
└──────────────┘  └──────────────┘  └──────────────┘
```

**Benefits:**
- Hardware-backed attestation
- Automatic re-attestation
- Certificate-based trust
- Production-ready

---

## Migration Strategy

### Approach: Rolling Migration with Dual Plugin Support

**Strategy:** Run both `join_token` and `tpm_devid` plugins simultaneously during migration, then remove `join_token` after all agents migrated.

**Phases:**
1. **Preparation** - Configure SPIRE Server with dual plugins
2. **Pilot** - Migrate one agent (auth) and validate
3. **Rollout** - Migrate remaining agents (ca, spire)
4. **Validation** - Verify all workloads functioning
5. **Cleanup** - Remove join_token plugin

**Timeline:** 1 day (with testing)
**Rollback Window:** 24 hours per phase

---

## Detailed Migration Steps

### Phase 1: Preparation (1-2 hours)

#### Step 1.1: Prepare DevID CA Bundle

**On ca.funlab.casa:**

```bash
# Create CA bundle for SPIRE Server validation
sudo cat /etc/step-ca/certs/root_ca.crt \
    /etc/step-ca/certs/intermediate_ca.crt \
    > /tmp/devid-ca-bundle.pem

# Verify bundle
sudo openssl crl2pkcs7 -nocrl -certfile /tmp/devid-ca-bundle.pem | \
    openssl pkcs7 -print_certs -noout
```

**Expected Output:** Shows both root and intermediate CA details

---

#### Step 1.2: Copy CA Bundle to SPIRE Server

**From workstation:**

```bash
# Copy bundle to SPIRE Server
scp ca:/tmp/devid-ca-bundle.pem /tmp/
scp /tmp/devid-ca-bundle.pem spire:/tmp/

# Install on SPIRE Server
ssh spire "sudo mkdir -p /opt/spire/conf && \
    sudo cp /tmp/devid-ca-bundle.pem /opt/spire/conf/devid-ca.pem && \
    sudo chown spire-server:spire-server /opt/spire/conf/devid-ca.pem && \
    sudo chmod 644 /opt/spire/conf/devid-ca.pem"
```

---

#### Step 1.3: Update SPIRE Server Configuration

**Backup current configuration:**

```bash
ssh spire "sudo cp /etc/spire/server.conf /etc/spire/server.conf.backup-$(date +%Y%m%d)"
```

**Add tpm_devid plugin to server configuration:**

**File:** `/etc/spire/server.conf`

```hcl
server {
  bind_address = "0.0.0.0"
  bind_port = "8081"
  socket_path = "/tmp/spire-server/private/api.sock"
  trust_domain = "funlab.casa"
  data_dir = "/opt/spire/data"
  log_level = "INFO"

  # JWT-SVID configuration
  jwt_issuer = "https://spire.funlab.casa:8081"

  # Federation bundle endpoint
  federation {
    bundle_endpoint {
      address = "0.0.0.0"
      port = 8443
    }
  }
}

plugins {
  DataStore "sql" {
    plugin_data {
      database_type = "sqlite3"
      connection_string = "/opt/spire/data/datastore.sqlite3"
    }
  }

  # PRODUCTION: TPM DevID attestation
  NodeAttestor "tpm_devid" {
    plugin_data {
      # CA bundle for validating DevID certificates
      devid_ca_path = "/opt/spire/conf/devid-ca.pem"

      # Endorsement certificate validation (optional, more secure)
      endorsement_ca_path = "/opt/spire/conf/tpm-ek-ca-certs"
    }
  }

  # TEMPORARY: Keep join_token during migration
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

**Key Changes:**
- Added `NodeAttestor "tpm_devid"` with DevID CA bundle
- Kept `NodeAttestor "join_token"` for backward compatibility
- Both plugins active during migration

---

#### Step 1.4: Restart SPIRE Server

```bash
# Validate configuration
ssh spire "sudo /opt/spire/bin/spire-server run -config /etc/spire/server.conf -dryRun"

# If validation passes, restart
ssh spire "sudo systemctl restart spire-server && sleep 5 && sudo systemctl status spire-server"

# Verify server health
ssh spire "curl -s http://127.0.0.1:8081/health"
```

**Expected Output:**
- Server starts successfully
- Health check returns healthy
- Both join_token and tpm_devid plugins loaded

---

### Phase 2: Pilot Migration (auth.funlab.casa) (1-2 hours)

#### Step 2.1: Backup auth Agent Configuration

```bash
ssh auth "sudo cp /etc/spire/agent.conf /etc/spire/agent.conf.backup-$(date +%Y%m%d)"
```

---

#### Step 2.2: Update auth Agent Configuration

**File:** `/etc/spire/agent.conf` (on auth.funlab.casa)

```hcl
agent {
  data_dir = "/var/lib/spire/agent"
  log_level = "INFO"
  server_address = "spire.funlab.casa"
  server_port = "8081"
  socket_path = "/run/spire/sockets/agent.sock"
  trust_domain = "funlab.casa"

  # Remove insecure_bootstrap - not needed for TPM attestation
  # insecure_bootstrap = true
}

plugins {
  # PRODUCTION: TPM DevID attestation
  NodeAttestor "tpm_devid" {
    plugin_data {
      # Path to TPM device
      tpm_path = "/dev/tpmrm0"

      # TPM DevID key handle
      devid_priv_path = "0x81010002"

      # DevID certificate
      devid_cert_path = "/var/lib/tpm2-devid/devid.crt"
    }
  }

  KeyManager "disk" {
    plugin_data {
      directory = "/var/lib/spire/agent"
    }
  }

  WorkloadAttestor "unix" {
    plugin_data {}
  }
}

health_checks {
  listener_enabled = true
  bind_address = "127.0.0.1"
  bind_port = "8088"
  live_path = "/live"
  ready_path = "/ready"
}
```

**Key Changes:**
- Replaced `NodeAttestor "join_token"` with `NodeAttestor "tpm_devid"`
- Removed `insecure_bootstrap = true`
- Added TPM configuration (device path, key handle, certificate)

---

#### Step 2.3: Evict Old Agent Registration

```bash
# Get current auth agent ID
AUTH_AGENT_ID=$(ssh spire "sudo /opt/spire/bin/spire-server agent list | grep auth | awk '{print \$2}'")

# Evict old join_token agent
ssh spire "sudo /opt/spire/bin/spire-server agent evict -spiffeID $AUTH_AGENT_ID"
```

---

#### Step 2.4: Restart auth Agent with TPM Attestation

```bash
# Stop agent
ssh auth "sudo systemctl stop spire-agent"

# Clear old agent data
ssh auth "sudo rm -rf /var/lib/spire/agent/*"

# Start agent with new TPM configuration
ssh auth "sudo systemctl start spire-agent && sleep 5"

# Check agent status
ssh auth "sudo systemctl status spire-agent"

# Verify health
ssh auth "curl -s http://127.0.0.1:8088/ready"
```

**Expected Output:**
- Agent starts successfully
- Health check returns `{"agent":{}}`
- No errors in logs

---

#### Step 2.5: Verify TPM Attestation

```bash
# Check agent list on SPIRE Server
ssh spire "sudo /opt/spire/bin/spire-server agent list"

# Look for auth agent with tpm_devid attestation
# Expected SPIFFE ID format: spiffe://funlab.casa/spire/agent/tpm_devid/<hash>
```

**Expected Output:**
```
Found 3 attested agents:

SPIFFE ID         : spiffe://funlab.casa/spire/agent/tpm_devid/auth...
Attestation type  : tpm_devid
Expiration time   : <90 days from now>
Serial number     : <certificate serial>

SPIFFE ID         : spiffe://funlab.casa/spire/agent/join_token/...
Attestation type  : join_token
...
```

---

#### Step 2.6: Verify Workload SVID Issuance

```bash
# Test SVID retrieval for test workload
ssh auth "sudo -u root /opt/spire/bin/spire-agent api fetch x509 \
    -socketPath /run/spire/sockets/agent.sock"
```

**Expected Output:**
```
Received 1 svid after <X>ms

SPIFFE ID:        spiffe://funlab.casa/workload/test-workload
SVID Valid After: <timestamp>
SVID Valid Until: <timestamp>
...
```

**Success Criteria:**
- ✅ Agent attested via tpm_devid
- ✅ SVID issuance working
- ✅ Performance acceptable (<100ms)
- ✅ No errors in agent logs

---

#### Step 2.7: Pilot Validation Period

**Duration:** 4-8 hours

**Monitoring:**
- Check agent health every hour
- Monitor SVID issuance
- Watch for TPM errors
- Verify workload functionality

**Validation Commands:**
```bash
# Continuous monitoring
watch -n 300 'ssh auth "curl -s http://127.0.0.1:8088/ready && \
    sudo /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock"'
```

**Go/No-Go Decision:**
- ✅ Go: Proceed to Phase 3 (migrate ca and spire)
- ❌ No-Go: Rollback auth to join_token

---

### Phase 3: Rollout (ca and spire) (2-3 hours)

Repeat Steps 2.1-2.6 for each remaining host:

#### Step 3.1: Migrate ca.funlab.casa

```bash
# Update agent configuration
ssh ca "sudo cp /etc/spire/agent.conf /etc/spire/agent.conf.backup-$(date +%Y%m%d)"

# Edit /etc/spire/agent.conf with tpm_devid configuration
# ... (same as auth configuration)

# Evict old agent
CA_AGENT_ID=$(ssh spire "sudo /opt/spire/bin/spire-server agent list | grep ca | awk '{print \$2}'")
ssh spire "sudo /opt/spire/bin/spire-server agent evict -spiffeID $CA_AGENT_ID"

# Restart with TPM attestation
ssh ca "sudo systemctl stop spire-agent && \
    sudo rm -rf /var/lib/spire/agent/* && \
    sudo systemctl start spire-agent"

# Verify
ssh ca "curl -s http://127.0.0.1:8088/ready"
ssh ca "sudo -u step /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock"
```

**Validation:** Verify step-ca workload can retrieve SVIDs

---

#### Step 3.2: Migrate spire.funlab.casa

```bash
# Update agent configuration
ssh spire "sudo cp /etc/spire/agent.conf /etc/spire/agent.conf.backup-$(date +%Y%m%d)"

# Edit /etc/spire/agent.conf with tpm_devid configuration
# ... (same as auth configuration)

# Evict old agent
SPIRE_AGENT_ID=$(ssh spire "sudo /opt/spire/bin/spire-server agent list | grep 'spire.*join_token' | awk '{print \$2}'")
ssh spire "sudo /opt/spire/bin/spire-server agent evict -spiffeID $SPIRE_AGENT_ID"

# Restart with TPM attestation
ssh spire "sudo systemctl stop spire-agent && \
    sudo rm -rf /var/lib/spire/agent/* && \
    sudo systemctl start spire-agent"

# Verify
ssh spire "curl -s http://127.0.0.1:8088/ready"
ssh spire "sudo -u openbao /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock"
```

**Validation:** Verify OpenBao workload can retrieve SVIDs

---

### Phase 4: Validation (2-3 hours)

#### Step 4.1: Verify All Agents

```bash
# List all agents
ssh spire "sudo /opt/spire/bin/spire-server agent list"
```

**Expected Output:**
```
Found 3 attested agents:

SPIFFE ID         : spiffe://funlab.casa/spire/agent/tpm_devid/auth...
Attestation type  : tpm_devid
✅

SPIFFE ID         : spiffe://funlab.casa/spire/agent/tpm_devid/ca...
Attestation type  : tpm_devid
✅

SPIFFE ID         : spiffe://funlab.casa/spire/agent/tpm_devid/spire...
Attestation type  : tpm_devid
✅
```

**Success Criteria:**
- All 3 agents using tpm_devid
- No join_token agents remaining
- All agents healthy

---

#### Step 4.2: Verify Workload SVID Issuance

```bash
# Test SVID issuance on all hosts
for host in auth ca spire; do
    echo "=== Testing $host ==="
    ssh $host "sudo /opt/spire/bin/spire-agent api fetch x509 \
        -socketPath /run/spire/sockets/agent.sock | head -5"
    echo
done
```

**Expected Output:** All workloads successfully retrieve SVIDs

---

#### Step 4.3: Test JWT-SVID Authentication (OpenBao)

```bash
# Test complete JWT auth flow
ssh ca "sudo -u step /opt/spire/bin/spire-agent api fetch jwt \
    -socketPath /run/spire/sockets/agent.sock \
    -audience openbao" | head -3
```

**Expected Output:** JWT-SVID issued successfully

---

#### Step 4.4: End-to-End Integration Test

```bash
# Full integration test: step-ca → JWT-SVID → OpenBao → Secret
ssh ca "sudo -u step /opt/spire/bin/spire-agent api fetch jwt \
    -socketPath /run/spire/sockets/agent.sock \
    -audience openbao | head -1 | awk '{print \$2}'" > /tmp/jwt-token

# Use JWT to authenticate to OpenBao
ssh spire "curl -s --request POST \
    --data '{\"jwt\": \"$(cat /tmp/jwt-token)\", \"role\": \"spire-workload\"}' \
    http://127.0.0.1:8200/v1/auth/jwt/login"
```

**Expected Output:** OpenBao returns client token

---

### Phase 5: Cleanup (30 minutes)

#### Step 5.1: Remove join_token Plugin from SPIRE Server

**Edit:** `/etc/spire/server.conf`

Remove the join_token plugin:

```hcl
  # REMOVE THIS BLOCK:
  # NodeAttestor "join_token" {
  #   plugin_data {}
  # }
```

---

#### Step 5.2: Restart SPIRE Server

```bash
# Validate configuration
ssh spire "sudo /opt/spire/bin/spire-server run -config /etc/spire/server.conf -dryRun"

# Restart
ssh spire "sudo systemctl restart spire-server && sleep 5"

# Verify health
ssh spire "curl -s http://127.0.0.1:8081/health"
```

---

#### Step 5.3: Verify Migration Complete

```bash
# Check server plugins
ssh spire "sudo /opt/spire/bin/spire-server healthcheck"

# Verify only tpm_devid agents present
ssh spire "sudo /opt/spire/bin/spire-server agent list | grep -c tpm_devid"
# Expected: 3

ssh spire "sudo /opt/spire/bin/spire-server agent list | grep -c join_token"
# Expected: 0
```

---

#### Step 5.4: Update Documentation

- [ ] Update tower-of-omens-onboarding.md (remove join_token steps)
- [ ] Update spire-server-config.md (reflect tpm_devid configuration)
- [ ] Document migration completion date
- [ ] Archive join_token configuration backups

---

## Rollback Procedures

### Rollback Trigger Conditions

**Initiate rollback if:**
- Agent attestation fails for >5 minutes
- SVID issuance fails consistently
- TPM errors in agent logs
- Workload functionality impacted
- Performance degradation >50%

---

### Rollback: Single Agent (e.g., auth)

```bash
# Stop agent
ssh auth "sudo systemctl stop spire-agent"

# Restore configuration backup
ssh auth "sudo cp /etc/spire/agent.conf.backup-<date> /etc/spire/agent.conf"

# Clear agent data
ssh auth "sudo rm -rf /var/lib/spire/agent/*"

# Generate new join token
JOIN_TOKEN=$(ssh spire "sudo /opt/spire/bin/spire-server token generate -spiffeID spiffe://funlab.casa/agent/auth")

# Start agent with join token
ssh auth "sudo /opt/spire/bin/spire-agent run -config /etc/spire/agent.conf \
    -joinToken $JOIN_TOKEN &"

# Enable service
ssh auth "sudo systemctl start spire-agent"

# Verify
ssh auth "curl -s http://127.0.0.1:8088/ready"
```

---

### Rollback: Complete Migration

```bash
# 1. Restore SPIRE Server configuration
ssh spire "sudo cp /etc/spire/server.conf.backup-<date> /etc/spire/server.conf && \
    sudo systemctl restart spire-server"

# 2. Restore all agent configurations
for host in auth ca spire; do
    ssh $host "sudo cp /etc/spire/agent.conf.backup-<date> /etc/spire/agent.conf"
done

# 3. Re-attest all agents with join tokens
for host in auth ca spire; do
    JOIN_TOKEN=$(ssh spire "sudo /opt/spire/bin/spire-server token generate \
        -spiffeID spiffe://funlab.casa/agent/$host")

    ssh $host "sudo systemctl stop spire-agent && \
        sudo rm -rf /var/lib/spire/agent/* && \
        sudo /opt/spire/bin/spire-agent run -config /etc/spire/agent.conf \
        -joinToken $JOIN_TOKEN &"

    ssh $host "sudo systemctl start spire-agent"
done

# 4. Verify all agents
ssh spire "sudo /opt/spire/bin/spire-server agent list"
```

**Rollback Time:** 15-30 minutes

---

## Testing Plan

### Pre-Migration Testing

**Test 1: DevID Certificate Validation**

```bash
# On each host
for host in auth ca spire; do
    echo "=== Testing $host ==="
    ssh $host "sudo openssl verify \
        -CAfile /etc/step-ca/certs/root_ca.crt \
        -untrusted /etc/step-ca/certs/intermediate_ca.crt \
        /var/lib/tpm2-devid/devid.crt"
done
```

**Expected:** All certificates verify OK

---

**Test 2: TPM Key Access**

```bash
# On each host
for host in auth ca spire; do
    echo "=== Testing $host ==="
    ssh $host "sudo tpm2_readpublic -c 0x81010002"
done
```

**Expected:** All TPM keys accessible

---

**Test 3: CA Bundle Availability**

```bash
# On SPIRE Server
ssh spire "sudo cat /opt/spire/conf/devid-ca.pem | \
    openssl crl2pkcs7 -nocrl -certfile /dev/stdin | \
    openssl pkcs7 -print_certs -noout"
```

**Expected:** Shows root and intermediate CA

---

### Post-Migration Testing

**Test 1: Agent Attestation**

```bash
# Verify all agents attested via tpm_devid
ssh spire "sudo /opt/spire/bin/spire-server agent list | grep tpm_devid | wc -l"
# Expected: 3
```

---

**Test 2: Workload SVID Issuance**

```bash
# Test SVID issuance latency
for i in {1..10}; do
    ssh auth "sudo /opt/spire/bin/spire-agent api fetch x509 \
        -socketPath /run/spire/sockets/agent.sock" | grep "after"
done
```

**Expected:** Consistent sub-10ms performance

---

**Test 3: JWT-SVID Authentication**

```bash
# Full end-to-end test
ssh ca "sudo -u step /opt/spire/bin/spire-agent api fetch jwt \
    -socketPath /run/spire/sockets/agent.sock \
    -audience openbao"
```

**Expected:** JWT-SVID issued successfully

---

**Test 4: Agent Re-attestation**

```bash
# Restart agent and verify re-attestation
ssh auth "sudo systemctl restart spire-agent && sleep 10 && \
    curl -s http://127.0.0.1:8088/ready"
```

**Expected:** Agent re-attests automatically without join token

---

## Success Criteria

Migration considered successful when:

- [ ] All 3 agents using tpm_devid attestation
- [ ] Zero join_token agents remaining
- [ ] All agents healthy and passing health checks
- [ ] All workloads can retrieve X509-SVIDs
- [ ] JWT-SVID authentication working
- [ ] OpenBao integration functional
- [ ] SVID issuance performance acceptable (<100ms)
- [ ] No errors in SPIRE Server/Agent logs
- [ ] Agent re-attestation working after restart
- [ ] join_token plugin removed from SPIRE Server
- [ ] Documentation updated
- [ ] Rollback tested and documented

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| TPM key inaccessible | Low | High | Pre-verify TPM keys before migration |
| DevID cert invalid | Low | High | Validate certificates before migration |
| Agent fails to attest | Medium | High | Rolling migration with pilot phase |
| Workload SVIDs fail | Low | Critical | Test on pilot before rollout |
| Performance degradation | Low | Medium | Baseline performance metrics |
| Configuration error | Medium | Medium | Configuration validation, backups |
| Rollback required | Low | Medium | Tested rollback procedures |

---

## Post-Migration Operations

### Monitoring

**Key Metrics:**
- Agent attestation success rate
- SVID issuance latency
- TPM operation errors
- Certificate expiry (90 days)

**Alerts:**
- Agent health check failures
- TPM errors in logs
- DevID certificate expiry (<30 days)
- SPIRE Server plugin errors

---

### Maintenance

**Monthly:**
- Review agent attestation logs
- Check TPM key accessibility
- Verify DevID certificate validity

**Before Certificate Expiry (~75 days):**
- Renew DevID certificates using renewal procedure
- Test certificate renewal on one host first
- Roll out to all hosts

**Quarterly:**
- Review and update migration documentation
- Test rollback procedures
- Audit TPM security posture

---

## References

- [SPIRE TPM Plugin Documentation](https://github.com/spiffe/spire/tree/main/doc/plugin_agent_nodeattestor_tpm_devid.md)
- [TPM DevID Provisioning](sprint-2-phase-3-complete.md)
- [DevID Certificate Renewal](devid-renewal-procedure.md)
- [Tower of Omens TPM Attestation Plan](tower-of-omens-tpm-attestation-plan.md)

---

**Document Version:** 1.0
**Last Updated:** 2026-02-10
**Migration Status:** Planned (Sprint 3)
**Estimated Effort:** 1 day (8-10 hours with testing)
