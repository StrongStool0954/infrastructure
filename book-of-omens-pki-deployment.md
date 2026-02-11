# Book of Omens - OpenBao PKI Deployment Complete

**Date:** 2026-02-10
**Status:** ✅ COMPLETE
**Intermediate CA:** Book of Omens
**Root CA:** Eye of Thundera
**Purpose:** Short-lived certificates for Tower of Omens infrastructure

---

## Executive Summary

Successfully deployed **Book of Omens** as an intermediate CA in OpenBao PKI, signed by the **Eye of Thundera** root CA. This provides centralized, automated issuance of short-lived certificates for all Tower of Omens infrastructure hosts and services.

**Key Achievement:** Unified PKI infrastructure for Keylime, SPIRE, OpenBao, and all infrastructure hosts.

---

## PKI Hierarchy

```
Eye of Thundera (Root CA)
├── Validity: 100 years (2026-2126)
├── Key: RSA 4096
├── Storage: 1Password vault "Funlab.Casa.Ca"
├── Usage: Signing intermediate CAs only
└── Intermediate CAs:
    ├── Sword of Omens (step-ca)
    │   ├── Purpose: ACME, DevID certificates
    │   ├── Validity: 10 years
    │   └── Backend: YubiKey NEO (hardware-backed)
    │
    └── Book of Omens (OpenBao) ✅ NEW!
        ├── Purpose: Infrastructure host certificates
        ├── Validity: 10 years (2026-2036)
        ├── Backend: OpenBao PKI engine
        └── Key: RSA 4096
```

---

## What Was Deployed

### 1. Book of Omens Intermediate CA ✅

**Certificate Details:**
```
Subject: C=US, O=Funlab.Casa, OU=Tower of Omens, CN=Book of Omens
Issuer: CN=Eye of Thundera
Valid From: 2026-02-11 01:31:31 GMT
Valid Until: 2036-02-09 01:31:31 GMT (10 years)
Key Type: RSA 4096-bit
Serial: 2b:f6:62:ca:b5:3f:48:62:ce:22:14:bd:15:f6:37:c4:12:77:24:a9
```

**OpenBao Mount Point:** `pki_int/`

**Issuing Certificates URL:** https://spire.funlab.casa:8200/v1/pki_int/ca
**CRL Distribution:** https://spire.funlab.casa:8200/v1/pki_int/crl

---

### 2. PKI Roles Created ✅

Four specialized roles for different use cases:

#### Role 1: `tower-infrastructure`
**Purpose:** Infrastructure hosts (spire, auth, ca)

**Configuration:**
- **Domains:** funlab.casa, spire.funlab.casa, auth.funlab.casa, ca.funlab.casa
- **TTL:** 7 days (168h)
- **Max TTL:** 30 days (720h)
- **Key Type:** RSA 2048
- **Flags:** Server + Client
- **IP SANs:** Allowed
- **URI SANs:** spiffe://funlab.casa/*

**Use Cases:**
- TLS certificates for host services
- mTLS between infrastructure hosts
- HTTPS endpoints
- General purpose infrastructure certs

---

#### Role 2: `keylime-services`
**Purpose:** Keylime components (agent, verifier, registrar)

**Configuration:**
- **Domains:** funlab.casa, keylime.funlab.casa, *.keylime.funlab.casa
- **TTL:** 24 hours
- **Max TTL:** 7 days (168h)
- **Key Type:** EC P-256
- **Flags:** Server + Client
- **Subdomains:** Allowed

**Use Cases:**
- Keylime mTLS communication
- Agent ↔ Verifier TLS
- Agent ↔ Registrar TLS
- Short-lived, frequently rotated

---

#### Role 3: `spire-agents`
**Purpose:** SPIRE Agent certificates

**Configuration:**
- **Domains:** funlab.casa (with subdomains)
- **TTL:** 7 days (168h)
- **Max TTL:** 30 days (720h)
- **Key Type:** EC P-256
- **Flags:** Server + Client
- **URI SANs:** spiffe://funlab.casa/*

**Use Cases:**
- SPIRE Agent TLS certificates
- Bundle endpoint certificates
- Federation trust bundles

---

#### Role 4: `openbao-server`
**Purpose:** OpenBao server TLS certificate

**Configuration:**
- **Domains:** spire.funlab.casa, 10.10.2.62
- **TTL:** 30 days (720h)
- **Max TTL:** 90 days (2160h)
- **Key Type:** RSA 2048
- **Flags:** Server + Client
- **IP SANs:** 10.10.2.62, 127.0.0.1

**Use Cases:**
- OpenBao HTTPS API
- Self-renewal capability
- Longer TTL for stability

---

## How to Issue Certificates

### Method 1: OpenBao CLI (Direct)

```bash
# Set environment
export BAO_ADDR=https://spire.funlab.casa:8200
export BAO_TOKEN=<your-token>
export BAO_SKIP_VERIFY=true  # or use proper CA cert

# Issue certificate for infrastructure host
bao write pki_int/issue/tower-infrastructure \
    common_name="auth.funlab.casa" \
    alt_names="auth.funlab.casa,localhost" \
    ip_sans="10.10.2.70,127.0.0.1" \
    ttl="168h" \
    format=pem

# Output: certificate, private_key, ca_chain, issuing_ca
```

### Method 2: OpenBao API (Automated)

```bash
# Issue certificate via REST API
curl -X POST \
    -H "X-Vault-Token: $BAO_TOKEN" \
    -d '{
        "common_name": "spire.funlab.casa",
        "alt_names": "spire.funlab.casa,localhost",
        "ip_sans": "10.10.2.62,127.0.0.1",
        "ttl": "168h"
    }' \
    https://spire.funlab.casa:8200/v1/pki_int/issue/tower-infrastructure
```

### Method 3: SPIRE Workload Identity (Recommended)

```bash
# Configure OpenBao policy for SPIRE workloads
bao policy write pki-issue-policy - <<EOF
path "pki_int/issue/tower-infrastructure" {
  capabilities = ["create", "update"]
}
EOF

# Workloads can authenticate with JWT-SVID and issue certs
# (Already configured via Sprint 2 JWT auth integration)
```

---

## Certificate Examples

### Example 1: Issue Certificate for auth.funlab.casa

```bash
ssh spire.funlab.casa "sudo -E bash -c '
export BAO_ADDR=https://127.0.0.1:8200
export BAO_SKIP_VERIFY=true
export BAO_TOKEN=s.eNHhmKyqvqW7Q93yVfswqFtx

# Issue 7-day certificate
bao write -format=json pki_int/issue/tower-infrastructure \
    common_name=\"auth.funlab.casa\" \
    alt_names=\"auth.funlab.casa,auth,localhost\" \
    ip_sans=\"10.10.2.70,127.0.0.1\" \
    ttl=\"168h\" \
    | jq -r \".data.certificate\" > /tmp/auth.crt

# Extract private key
jq -r \".data.private_key\" > /tmp/auth.key

# Extract CA chain
jq -r \".data.ca_chain[]\" > /tmp/ca-chain.crt
'"
```

### Example 2: Issue Keylime Certificate

```bash
# Issue 24-hour certificate for Keylime agent
bao write pki_int/issue/keylime-services \
    common_name="keylime-agent.auth.funlab.casa" \
    alt_names="keylime-agent,localhost" \
    ip_sans="10.10.2.70,127.0.0.1" \
    ttl="24h"
```

### Example 3: Renew OpenBao's Own Certificate

```bash
# OpenBao can renew its own certificate
bao write pki_int/issue/openbao-server \
    common_name="spire.funlab.casa" \
    alt_names="spire,localhost" \
    ip_sans="10.10.2.62,127.0.0.1" \
    ttl="720h"

# Install new certificate
# (requires OpenBao restart or reload)
```

---

## Verification & Testing

### Verify CA Chain

```bash
# Download CA certificate
curl -k https://spire.funlab.casa:8200/v1/pki_int/ca/pem > book-of-omens.crt

# Verify it's signed by Eye of Thundera
openssl verify -CAfile eye-of-thundera.crt book-of-omens.crt
# Output: book-of-omens.crt: OK

# Check certificate details
openssl x509 -in book-of-omens.crt -noout -text
```

### Test Certificate Issuance

```bash
# Issue test certificate
bao write pki_int/issue/tower-infrastructure \
    common_name="test.funlab.casa" \
    ttl="1h"

# Verify issued certificate
openssl x509 -in <certificate> -noout -issuer -subject
# Issuer: C=US, O=Funlab.Casa, OU=Tower of Omens, CN=Book of Omens
# Subject: CN=test.funlab.casa
```

### List All Certificates

```bash
# List all issued certificates
bao list pki_int/certs

# Read specific certificate
bao read pki_int/cert/<serial-number>
```

---

## Integration with Services

### 1. Keylime mTLS Setup

**Goal:** Enable mTLS between Keylime components using Book of Omens certificates

**Steps:**
1. Issue certificates for verifier, registrar, and agents
2. Update Keylime configs to use Book of Omens CA
3. Enable mTLS in keylime.conf
4. Implement automatic renewal (24-hour TTL)

**Configuration:**
```ini
# /etc/keylime/agent.conf
[cloud_agent]
enable_agent_mtls = True
mtls_cert = /etc/keylime/certs/agent.crt
mtls_private_key = /etc/keylime/certs/agent.key
trusted_server_ca = /etc/keylime/certs/book-of-omens-ca.crt
```

---

### 2. SPIRE Bundle Endpoint TLS

**Goal:** Use Book of Omens certificates for SPIRE federation bundle endpoint

**Current:** Self-signed certificate via nginx proxy
**Future:** Book of Omens signed certificate with auto-renewal

**Benefits:**
- Trusted by all infrastructure hosts
- Automatic rotation
- No manual cert management

---

### 3. OpenBao Self-Renewal

**Goal:** OpenBao issues its own TLS certificate

**Current:** Manual certificate (from step-ca)
**Future:** Self-issued via `openbao-server` role

**Implementation:**
```bash
# Create renewal script
cat > /usr/local/bin/renew-openbao-cert.sh <<'EOF'
#!/bin/bash
export BAO_ADDR=https://127.0.0.1:8200
export BAO_SKIP_VERIFY=true
export BAO_TOKEN=$(cat /root/.openbao-token)

# Issue new certificate
bao write -format=json pki_int/issue/openbao-server \
    common_name="spire.funlab.casa" \
    ip_sans="10.10.2.62,127.0.0.1" \
    ttl="720h" | jq -r '.data.certificate' > /opt/openbao/tls/tls.crt.new

# Reload OpenBao
systemctl reload openbao
EOF

# Schedule renewal (25 days = 5 days before expiration)
echo "0 2 */25 * * /usr/local/bin/renew-openbao-cert.sh" | crontab -
```

---

### 4. SSH Certificates (Future)

**Goal:** Use OpenBao for SSH certificate authentication

**Implementation:**
```bash
# Create SSH CA role
bao secrets enable -path=ssh-client-signer ssh

# Configure for Tower of Omens hosts
bao write ssh-client-signer/config/ca \
    generate_signing_key=true

# Allow signing for infrastructure hosts
bao write ssh-client-signer/roles/tower-omens \
    allow_user_certificates=true \
    allowed_users="tygra,root" \
    default_extensions="permit-pty,permit-port-forwarding" \
    ttl="8h" \
    max_ttl="24h"
```

---

## Operational Procedures

### Certificate Renewal Automation

**Recommended Approach:** Use cron jobs or systemd timers

```bash
# Example systemd timer for auth host
cat > /etc/systemd/system/renew-host-cert.service <<'EOF'
[Unit]
Description=Renew auth.funlab.casa certificate
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/renew-host-cert.sh
User=root
EOF

cat > /etc/systemd/system/renew-host-cert.timer <<'EOF'
[Unit]
Description=Renew host certificate weekly

[Timer]
OnCalendar=weekly
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl enable --now renew-host-cert.timer
```

### Monitoring Certificate Expiration

```bash
# Check certificate expiration
check_cert_expiry() {
    local cert_path=$1
    local expiry_date=$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local current_epoch=$(date +%s)
    local days_remaining=$(( ($expiry_epoch - $current_epoch) / 86400 ))

    if [ $days_remaining -lt 7 ]; then
        echo "WARNING: Certificate expires in $days_remaining days!"
    fi
}
```

### Revoking Certificates

```bash
# Revoke compromised certificate
bao write pki_int/revoke \
    serial_number="57:d5:83:25:3f:1c:04:7b:79:16:02:fd:40:10:89:24:aa:c3:c3:54"

# Update CRL
bao read pki_int/crl

# Verify revocation
curl -k https://spire.funlab.casa:8200/v1/pki_int/crl | \
    openssl crl -inform DER -text -noout
```

---

## Security Considerations

### Private Key Protection

**Root CA (Eye of Thundera):**
- ✅ Stored in 1Password vault
- ✅ Never exposed on infrastructure hosts
- ✅ Only used for signing intermediate CAs
- ✅ Offline usage only

**Intermediate CA (Book of Omens):**
- ✅ Generated within OpenBao
- ✅ Never exported
- ✅ Protected by OpenBao's encryption
- ✅ Requires unseal keys to access

**Leaf Certificates:**
- ⚠️ Private keys generated on requesting host
- ⚠️ Should be stored with appropriate permissions (600)
- ⚠️ Should be rotated regularly (use short TTLs)
- ✅ Can be revoked if compromised

### Access Control

**OpenBao PKI Access:**
```bash
# Create policy for certificate issuance
bao policy write pki-tower-infrastructure - <<EOF
# Allow issuing certificates
path "pki_int/issue/tower-infrastructure" {
  capabilities = ["create", "update"]
}

# Allow reading CA certificate
path "pki_int/cert/ca" {
  capabilities = ["read"]
}

# Allow reading CRL
path "pki_int/crl" {
  capabilities = ["read"]
}
EOF

# Assign to SPIRE workload
bao write auth/jwt/role/spire-workload \
    role_type="jwt" \
    bound_audiences="spire.funlab.casa" \
    user_claim="sub" \
    policies="pki-tower-infrastructure" \
    ttl="1h"
```

---

## Troubleshooting

### Issue: Certificate validation fails

**Symptoms:** `x509: certificate signed by unknown authority`

**Solution:**
```bash
# Ensure full certificate chain is provided
# Chain should be: [leaf cert] -> [Book of Omens] -> [Eye of Thundera]

# Download full chain
curl -k https://spire.funlab.casa:8200/v1/pki_int/ca_chain > ca-chain.pem

# Verify chain
openssl verify -CAfile ca-chain.pem leaf-cert.crt
```

### Issue: OpenBao PKI not accessible

**Symptoms:** `permission denied` or `404 not found`

**Solution:**
```bash
# Verify PKI mount exists
bao secrets list | grep pki_int

# Check authentication
bao token lookup

# Verify policy permissions
bao token capabilities pki_int/issue/tower-infrastructure
```

### Issue: Certificate issuance fails

**Symptoms:** `error: invalid common_name`

**Solution:**
```bash
# Check role configuration
bao read pki_int/roles/tower-infrastructure

# Verify domain is allowed
# common_name must match allowed_domains

# Check TTL limits
# requested TTL must be <= max_ttl
```

---

## Next Steps

### Short-Term (This Week)

1. **Deploy Certificates to Hosts**
   - Issue certificates for spire, auth, ca
   - Install in appropriate locations
   - Update service configurations

2. **Enable Keylime mTLS**
   - Issue Keylime certificates (24h TTL)
   - Configure mTLS in Keylime
   - Test agent ↔ verifier communication

3. **Implement Auto-Renewal**
   - Create renewal scripts for each host
   - Set up systemd timers
   - Test renewal process

### Medium-Term (Next Week)

4. **Migrate SPIRE Bundle Endpoint**
   - Replace nginx self-signed cert
   - Use Book of Omens certificate
   - Update nginx configuration

5. **OpenBao Self-Renewal**
   - Implement OpenBao cert auto-renewal
   - Test reload without downtime
   - Schedule via cron/timer

6. **Monitoring & Alerting**
   - Set up cert expiration monitoring
   - Alert on expiration < 7 days
   - Dashboard for certificate status

### Long-Term (Future Sprints)

7. **SSH Certificates**
   - Enable SSH CA in OpenBao
   - Configure SSH to trust OpenBao CA
   - Implement SSH cert authentication

8. **Certificate Transparency**
   - Log all issued certificates
   - Implement CT monitoring
   - Alerting on unexpected issuance

9. **Policy Enforcement**
   - Require certificates for all services
   - Disable self-signed certificates
   - Enforce mTLS everywhere

---

## Summary

### What We Built

✅ **Book of Omens Intermediate CA**
- 10-year validity
- Signed by Eye of Thundera root CA
- RSA 4096-bit key
- Deployed in OpenBao PKI

✅ **Four PKI Roles**
- tower-infrastructure (7-day TTL)
- keylime-services (24-hour TTL)
- spire-agents (7-day TTL)
- openbao-server (30-day TTL)

✅ **Certificate Issuance**
- Tested and verified
- API and CLI access
- JWT-SVID integration ready

### Benefits Achieved

1. **Centralized PKI:** Single source of truth for all infrastructure certificates
2. **Short-Lived Certificates:** Automatic expiration reduces compromise window
3. **Automated Issuance:** No manual CSR generation or signing
4. **Integration Ready:** Works with SPIRE, Keylime, OpenBao
5. **Scalable:** Easy to add new hosts and services

### Infrastructure Status

```
Tower of Omens PKI
==================

Root CA: Eye of Thundera ✅
├── Storage: 1Password (Funlab.Casa.Ca)
├── Validity: 100 years (2026-2126)
└── Intermediates:
    ├── Sword of Omens (step-ca) ✅
    │   └── Purpose: ACME, DevID, public-facing
    └── Book of Omens (OpenBao) ✅ NEW!
        └── Purpose: Infrastructure, internal services

OpenBao PKI Engine: pki_int/ ✅
├── Issuer: book-of-omens
├── Roles: 4 configured
├── Status: Operational
└── Access: Root token + JWT-SVID

Certificate Issuance: TESTED ✅
├── tower-infrastructure: Working
├── keylime-services: Ready
├── spire-agents: Ready
└── openbao-server: Ready
```

---

## Quick Reference

### OpenBao PKI Paths

```
pki_int/ca                           # CA certificate
pki_int/ca_chain                     # Full certificate chain
pki_int/crl                          # Certificate Revocation List
pki_int/issue/<role>                 # Issue certificate
pki_int/sign/<role>                  # Sign CSR
pki_int/revoke                       # Revoke certificate
pki_int/roles/<role>                 # Role configuration
pki_int/certs                        # List all certificates
pki_int/cert/<serial>                # Read specific certificate
```

### Environment Setup

```bash
# OpenBao CLI environment
export BAO_ADDR=https://spire.funlab.casa:8200
export BAO_TOKEN=<your-token>
export BAO_SKIP_VERIFY=true  # or provide CA cert

# For localhost access (on spire host)
export BAO_ADDR=https://127.0.0.1:8200
export BAO_SKIP_VERIFY=true
export BAO_TOKEN=s.eNHhmKyqvqW7Q93yVfswqFtx
```

### Common Commands

```bash
# List PKI roles
bao list pki_int/roles

# Read role configuration
bao read pki_int/roles/tower-infrastructure

# Issue certificate
bao write pki_int/issue/tower-infrastructure \
    common_name="host.funlab.casa" \
    ttl="168h"

# Revoke certificate
bao write pki_int/revoke serial_number="<serial>"

# Download CA certificate
curl -k https://spire.funlab.casa:8200/v1/pki_int/ca/pem
```

---

**Deployment Status:** ✅ COMPLETE
**Next Action:** Deploy certificates to infrastructure hosts
**Priority:** Enable Keylime mTLS with short-lived certificates
**Last Updated:** 2026-02-10 20:45 EST
