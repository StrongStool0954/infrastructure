# OpenBao Deployment Summary - spire.funlab.casa

**Date:** 2026-02-10
**Status:** ✅ OPERATIONAL
**Version:** OpenBao v2.5.0

---

## Deployment Overview

Successfully deployed OpenBao (open-source Vault fork) on spire.funlab.casa with Integrated Storage (Raft) and basic SPIRE JWT authentication.

---

## System Information

**Host:** spire.funlab.casa (10.10.2.62)
**OS:** Debian 13 (trixie) x86_64
**Co-located Services:**
- SPIRE Server (port 8081) ✅
- OpenBao (port 8200) ✅

---

## Installation Details

### OpenBao Version
- **Version:** v2.5.0
- **Build Date:** 2026-02-04T16:19:33Z
- **Binary:** `/usr/bin/bao`
- **Installation Method:** Debian package

### Directories
```
/etc/openbao/               - Configuration files
/var/lib/openbao/data/      - Raft storage data
/opt/openbao/tls/           - Auto-generated TLS certificates
```

### User & Permissions
- **User:** openbao (uid: 999)
- **Group:** openbao (gid: 989)

---

## Configuration

### Storage Backend: Integrated Storage (Raft)

**Benefits:**
- ✅ No external dependencies (no Consul required)
- ✅ Built-in HA capabilities
- ✅ Consistent performance
- ✅ Automatic snapshots

**Configuration:**
```hcl
storage "raft" {
  path    = "/var/lib/openbao/data"
  node_id = "spire-node-1"
  performance_multiplier = 1
}
```

### Network Configuration

**API Endpoint:** `https://spire.funlab.casa:8200`
**Cluster Address:** `https://spire.funlab.casa:8201`

**Listener:**
```hcl
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/opt/openbao/tls/tls.crt"
  tls_key_file  = "/opt/openbao/tls/tls.key"
  tls_min_version = "tls12"
}
```

**Note:** Using self-signed certificates (auto-generated). Future enhancement: Use step-ca issued certificates.

---

## Initialization & Unsealing

### Shamir Secret Sharing

**Configuration:**
- **Total Key Shares:** 5
- **Threshold:** 3 keys required to unseal
- **Seal Type:** shamir

**Unseal Keys Location:** 1Password (`Funlab.Casa.Spire` vault)
**Item:** "OpenBao Initial Credentials - spire.funlab.casa"

### Current State
- **Initialized:** Yes ✅
- **Sealed:** No ✅
- **HA Mode:** Active ✅
- **Cluster:** vault-cluster-3cc9cba9

### Unseal Process

**Manual Unseal:**
```bash
export BAO_ADDR='https://127.0.0.1:8200'
export BAO_SKIP_VERIFY=1

# Unseal with 3 of 5 keys
bao operator unseal <key1>
bao operator unseal <key2>
bao operator unseal <key3>
```

**Future Enhancement:** TPM auto-unseal using spire's TPM 2.0

---

## Authentication & Authorization

### Root Token

**Location:** 1Password (`Funlab.Casa.Spire` vault)
**Token:** `s.eNHhmKyqvqW7Q93yVfswqFtx`

**⚠️ Security Note:** Root token provides full administrative access. Use only for initial setup and emergency access. Create limited-privilege tokens for normal operations.

### JWT Authentication (SPIRE Integration)

**Status:** Configured for future SPIRE workload authentication

**Auth Method:** jwt (enabled)
**Role:** spire-workload

**Configuration:**
```hcl
Path: auth/jwt/role/spire-workload
- role_type: jwt
- bound_audiences: openbao
- user_claim: sub
- policies: default
- ttl: 1h
```

**Future Work:**
- Configure SPIRE Server with JWT-SVID issuer
- Update OpenBao JWT config with SPIRE OIDC discovery URL
- Create workload-specific policies
- Test end-to-end SPIRE → OpenBao authentication

---

## Secrets Engines

### KV Version 2 (Key-Value)

**Path:** `secret/`
**Status:** Enabled ✅

**Usage:**
```bash
# Write secret
bao kv put secret/path/to/secret key=value

# Read secret
bao kv get secret/path/to/secret

# Delete secret
bao kv delete secret/path/to/secret
```

**Features:**
- Versioning (previous versions retained)
- Check-and-Set for concurrency control
- Metadata tracking
- Soft delete with recovery

---

## Systemd Service

**Service File:** `/etc/systemd/system/openbao.service`

**Key Features:**
- Type: notify (proper startup detection)
- User: openbao (least privilege)
- Security hardening enabled
- Auto-restart on failure

**Management:**
```bash
# Status
sudo systemctl status openbao

# Restart
sudo systemctl restart openbao

# Logs
sudo journalctl -u openbao -f

# Enable at boot
sudo systemctl enable openbao
```

---

## Environment Configuration

**Global Environment:** `/etc/profile.d/openbao.sh`

```bash
export BAO_ADDR='https://127.0.0.1:8200'
export BAO_SKIP_VERIFY=1  # Using self-signed cert
```

**Usage:**
```bash
# After login, environment is set automatically
bao status

# Or export manually in scripts
source /etc/profile.d/openbao.sh
```

---

## Testing & Verification

### Health Check
```bash
ssh spire "export BAO_ADDR='https://127.0.0.1:8200' && export BAO_SKIP_VERIFY=1 && bao status"
```

**Expected Output:**
```
Sealed: false
HA Mode: active
```

### Secret Storage Test
```bash
# Write test secret
bao kv put secret/test password=my-secret-password

# Read test secret
bao kv get secret/test

# Verify output contains password
```

✅ **Test Result:** Passed - secret stored and retrieved successfully

---

## Security Considerations

### Current Security Posture

✅ **Implemented:**
- Systemd security hardening (ProtectSystem, PrivateDevices, etc.)
- TLS encryption for API (HTTPS only)
- Shamir secret sharing (5 keys, threshold 3)
- Least-privilege service user
- Credentials stored in 1Password

⏳ **Planned Enhancements:**
- Replace self-signed cert with step-ca issued certificate
- Enable TPM auto-unseal
- Configure audit logging
- Implement SPIRE JWT authentication
- Create least-privilege policies
- Enable Prometheus metrics with authentication

### Credentials in 1Password

**Vault:** `Funlab.Casa.Spire`
**Item:** "OpenBao Initial Credentials - spire.funlab.casa"

**Contains:**
- 5 unseal keys (need 3 to unseal)
- Root token (administrative access)

**Access Control:**
- Read-only for automation
- Full access for administrators only

---

## Integration Points

### SPIRE Server

**Status:** Co-located on spire.funlab.casa
**Port:** 8081
**Integration:** JWT authentication configured (OIDC discovery pending)

**Future Integration:**
- Workloads with SPIRE SVIDs can authenticate to OpenBao
- Secrets delivered via SPIRE workload API
- Automatic credential rotation

### step-ca

**Status:** Deployed on ca.funlab.casa
**Integration Opportunities:**
- Issue proper TLS certificates for OpenBao
- Store step-ca credentials in OpenBao
- Automate certificate lifecycle

---

## Operations

### Daily Operations

**No manual intervention required** - OpenBao runs autonomously once unsealed.

### Reboot Procedure

**After reboot:**
1. OpenBao service starts automatically
2. **Vault is SEALED** (manual unseal required)
3. Unseal with 3 of 5 keys from 1Password
4. Verify status: `bao status`

**Automation Opportunity:** Implement TPM auto-unseal to eliminate manual step

### Backup & Recovery

**Raft Snapshots:**
```bash
# Create snapshot
bao operator raft snapshot save backup.snap

# Restore snapshot
bao operator raft snapshot restore backup.snap
```

**Backup Strategy (Recommended):**
- Daily automated snapshots
- Store in separate secure location (not on same host)
- Test restoration quarterly

---

## Troubleshooting

### OpenBao Won't Start

**Check logs:**
```bash
sudo journalctl -u openbao -n 50
```

**Common causes:**
- Configuration syntax error in `/etc/openbao/openbao.hcl`
- Port 8200 already in use
- Data directory permissions incorrect

### OpenBao is Sealed After Reboot

**Expected behavior** - manual unseal required for security.

**Unseal:**
```bash
# Get unseal keys from 1Password
op document get "OpenBao Initial Credentials - spire.funlab.casa" --vault "Funlab.Casa.Spire"

# Unseal with 3 keys
bao operator unseal <key1>
bao operator unseal <key2>
bao operator unseal <key3>
```

### Cannot Connect to OpenBao

**Check service:**
```bash
sudo systemctl status openbao
```

**Check listener:**
```bash
sudo ss -tlnp | grep 8200
```

**Test locally:**
```bash
curl -k https://localhost:8200/v1/sys/health
```

---

## Next Steps

### Sprint 1 Completion (Immediate)
- [ ] Deploy SPIRE Agents on auth.funlab.casa and ca.funlab.casa
- [ ] Register initial workloads with SPIRE
- [ ] Test secret retrieval from workloads

### Sprint 2: Enhanced Integration
- [ ] Configure SPIRE Server with JWT-SVID issuer
- [ ] Complete SPIRE → OpenBao JWT authentication
- [ ] Create workload-specific OpenBao policies
- [ ] Store step-ca credentials in OpenBao
- [ ] Test end-to-end workload secret access

### Sprint 3: Production Hardening
- [ ] Replace self-signed cert with step-ca certificate
- [ ] Implement TPM auto-unseal
- [ ] Enable audit logging
- [ ] Set up automated Raft snapshots
- [ ] Configure Prometheus metrics
- [ ] Create runbooks for operations

---

## Reference

### Quick Commands

```bash
# Check status
bao status

# List secrets engines
bao secrets list

# List auth methods
bao auth list

# List policies
bao policy list

# Read policy
bao policy read default

# View token capabilities
bao token capabilities <token> <path>
```

### Useful Links

- **OpenBao Docs:** https://openbao.org/docs/
- **SPIRE Integration:** https://openbao.org/docs/auth/jwt/
- **Raft Storage:** https://openbao.org/docs/configuration/storage/raft/

---

## Success Metrics

✅ **All Deployment Goals Met:**
- [x] OpenBao v2.5.0 installed and running
- [x] Integrated Storage (Raft) configured
- [x] Initialized and unsealed
- [x] Credentials stored securely in 1Password
- [x] KV v2 secrets engine enabled
- [x] JWT auth method configured
- [x] Basic testing completed
- [x] Documentation created

**Deployment Time:** ~1.5 hours
**Services Running:** 2/2 (SPIRE + OpenBao)
**Incidents:** 0

---

**Deployment Status:** ✅ OPERATIONAL
**Last Updated:** 2026-02-10 16:47 EST
**Next Review:** After SPIRE Agent deployment
