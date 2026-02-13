# Phase 3: SSH Certificate Authentication - Audit Report

**Date:** 2026-02-12
**Task:** #28 - Audit current SSH key usage across hosts

---

## SSH Private Keys Inventory

### ca.funlab.casa
```
-rw------- 1 root root  399 Feb 12 20:25 /root/.ssh/id_ed25519
-rw-r--r-- 1 root root   89 Feb 12 20:25 /root/.ssh/id_ed25519.pub
```
**Type:** ED25519 (modern, secure)
**Size:** 399 bytes

### auth.funlab.casa
```
-rw------- 1 root root  399 Feb 12 20:25 /root/.ssh/id_ed25519
-rw-r--r-- 1 root root   91 Feb 12 20:25 /root/.ssh/id_ed25519.pub
```
**Type:** ED25519 (modern, secure)
**Size:** 399 bytes

### spire.funlab.casa
```
No private keys found - only authorized_keys
```
**Note:** Spire receives SSH connections but doesn't initiate them (except to itself locally)

---

## SSH Usage by Script

### 1. update-spire-trust-bundle.sh
**Location:** `/usr/local/bin/update-spire-trust-bundle.sh`
**Hosts:** ca, auth, spire
**SSH Pattern:**
```bash
ssh -o ConnectTimeout=5 -o BatchMode=yes spire.funlab.casa \
    'sudo /opt/spire/bin/spire-server bundle show'
```
**Purpose:** Fetch SPIRE trust bundle from server for local use
**Authentication:** SSH key (BatchMode requires non-interactive)
**Frequency:** Cron job (likely hourly or daily)

### 2. renew-all-keylime-certs.sh
**Location:** `/usr/local/bin/renew-all-keylime-certs.sh`
**Host:** spire (runs centralized renewal)
**SSH Patterns:**
```bash
# Copy certificates
scp -q /tmp/auth-agent.crt auth.funlab.casa:/tmp/agent.crt.new
scp -q /tmp/auth-agent.key auth.funlab.casa:/tmp/agent.key.new
scp -q /tmp/auth-ca.crt auth.funlab.casa:/tmp/ca.crt.new

# Install certificates
ssh auth.funlab.casa "sudo mv /tmp/agent.crt.new /etc/keylime/certs/agent.crt && ..."
```
**Purpose:** Distribute renewed Keylime certificates to agents
**Authentication:** SSH key
**Frequency:** Daily (24-hour certificate TTL)

### 3. cert-monitor.sh
**Location:** `/usr/local/bin/cert-monitor.sh`
**Hosts:** ca, auth, spire
**SSH Pattern:**
```bash
ssh -o ConnectTimeout=5 $host "sudo openssl x509 -in '$cert_path' -noout -enddate"
```
**Purpose:** Monitor certificate expiration across all hosts
**Authentication:** SSH key (BatchMode implied by ConnectTimeout)
**Frequency:** Likely hourly or daily monitoring

### 4. fetch-openbao-credentials.sh
**Location:** `/opt/authentik/fetch-openbao-credentials.sh` (auth)
**Host:** auth
**SSH Pattern:**
```bash
ssh -o StrictHostKeyChecking=no spire.funlab.casa \
    "sudo bash -c 'BAO_ADDR=https://openbao.funlab.casa BAO_TOKEN=\$(cat /root/.openbao-token) bao read -format=json database/creds/authentik'"
```
**Purpose:** Fetch dynamic database credentials from OpenBao
**Authentication:** SSH key
**Frequency:** On service startup

**Similar script:** `/opt/npm/fetch-openbao-credentials.sh`

---

## SSH Authentication Flow

### Current (Key-Based)

```
┌──────────────────┐
│ ca.funlab.casa   │
│ /root/.ssh/      │──┐
│   id_ed25519     │  │
└──────────────────┘  │
                      │
┌──────────────────┐  │  SSH with key
│ auth.funlab.casa │  ├─────────────►  ┌────────────────────┐
│ /root/.ssh/      │  │                │ spire.funlab.casa  │
│   id_ed25519     │──┘                │ /root/.ssh/        │
└──────────────────┘                   │   authorized_keys  │
                                        └────────────────────┘

Issues:
❌ Long-lived keys (no expiration)
❌ Manual rotation required
❌ If compromised, no automatic revocation
❌ Keys stored on disk indefinitely
```

### Target (Certificate-Based)

```
┌────────────────────────────────┐
│ step-ca (ca.funlab.casa)       │
│ SSH Certificate Authority      │
│                                 │
│ Issues certificates:            │
│ - User certs: 8h TTL           │
│ - Host certs: 24h TTL          │
└────────────────────────────────┘
                │
                │ Request cert
                │ (short-lived)
                ▼
┌──────────────────┐              ┌────────────────────┐
│ ca.funlab.casa   │  SSH with    │ spire.funlab.casa  │
│ /root/.ssh/      │  certificate │ /etc/ssh/          │
│   id_ed25519-cert├─────────────►│   ca.pub           │
│   (8h expiry)    │              │ (TrustedUserCAKeys)│
└──────────────────┘              └────────────────────┘

┌──────────────────┐
│ auth.funlab.casa │  SSH with
│ /root/.ssh/      │  certificate
│   id_ed25519-cert├──────────────┘
│   (8h expiry)    │
└──────────────────┘

Benefits:
✅ Short-lived certificates (8-24 hours)
✅ Automatic expiration
✅ Centralized issuance via step-ca
✅ Easy revocation (don't renew)
✅ No long-lived keys on disk
```

---

## SSH Connection Matrix

| Source Host | Destination Host | Purpose | Script |
|-------------|-----------------|---------|--------|
| ca | spire | Fetch SPIRE trust bundle | update-spire-trust-bundle.sh |
| ca | auth | Monitor certificates | cert-monitor.sh |
| ca | spire | Monitor certificates | cert-monitor.sh |
| auth | spire | Fetch SPIRE trust bundle | update-spire-trust-bundle.sh |
| auth | spire | Fetch OpenBao credentials | fetch-openbao-credentials.sh |
| auth | ca | Monitor certificates | cert-monitor.sh |
| auth | spire | Monitor certificates | cert-monitor.sh |
| spire | auth | Distribute Keylime certs | renew-all-keylime-certs.sh |
| spire | ca | Distribute Keylime certs (if needed) | renew-all-keylime-certs.sh |
| spire | auth | Monitor certificates | cert-monitor.sh |
| spire | ca | Monitor certificates | cert-monitor.sh |

**Total SSH Connections:** 11 automated SSH flows
**Authentication Method:** SSH keys (ed25519)
**All connections:** Non-interactive (BatchMode)

---

## Migration Strategy

### Phase 3A: Configure step-ca
1. Enable SSH certificate provisioner in step-ca
2. Configure user certificate templates (8h TTL)
3. Configure host certificate templates (24h TTL)
4. Generate SSH CA keypair

### Phase 3B: Configure SSH Hosts
1. Add step-ca SSH CA public key to all hosts
2. Configure /etc/ssh/sshd_config with TrustedUserCAKeys
3. Test certificate-based authentication
4. Verify all automated scripts work

### Phase 3C: Migrate Scripts
1. Create certificate request wrapper
2. Implement automatic certificate renewal
3. Update scripts to use certificates
4. Test all automation flows

### Phase 3D: Remove Keys
1. Verify all automation working with certificates
2. Backup SSH private keys
3. Remove keys from /root/.ssh/
4. Monitor for 24 hours
5. Delete backups after successful validation

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Automation breaks during migration | Medium | High | Test each script individually, keep keys during testing |
| Certificate renewal fails | Low | Critical | Implement monitoring alerts, emergency key restore procedure |
| SSH CA compromise | Low | Critical | Secure CA private key in YubiKey, require PIN |
| Scripts can't auto-renew certs | Medium | Medium | Implement renewal wrapper, extend TTLs during testing |

---

## Next Steps

1. ✅ Complete SSH audit (Task #28)
2. Configure step-ca for SSH certificates (Task #27)
3. Configure SSH hosts to trust step-ca (Task #31)
4. Test SSH certificate authentication (Task #29)
5. Update automation scripts (Task #30)
6. Remove static SSH keys (Task #32)
7. Document Phase 3 completion (Task #33)

---

**Document Version:** 1.0
**Last Updated:** 2026-02-12 23:25 EST
**Status:** Audit Complete - Ready for step-ca configuration
