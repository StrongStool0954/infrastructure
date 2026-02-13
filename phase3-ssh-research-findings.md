# Phase 3: SSH Certificate Research Findings

**Date:** 2026-02-12
**Task:** Research step-ca + PKCS11 + SSH configuration
**Status:** Research Complete - Alternative Solution Required

---

## Problem Statement

Attempted to enable SSH certificate issuance in step-ca (ca.funlab.casa) which uses PKCS11 (YubiKey NEO) for the intermediate CA private key. Configuration failed with "scheme is missing" and "scheme not expected" errors.

---

## Research Findings

### Step-CA SSH Configuration with KMS

According to [Smallstep documentation](https://smallstep.com/docs/step-ca/cryptographic-protection/), when using PKCS11 KMS, SSH CA keys must ALSO use PKCS11 format:

**Correct Configuration Format:**
```json
{
  "kms": {
    "type": "pkcs11",
    "uri": "pkcs11:module-path=/path/to/libpkcs11.so;token=YubiKey..."
  },
  "ssh": {
    "hostKey": "pkcs11:id=7333;object=ssh-host-ca",
    "userKey": "pkcs11:id=7334;object=ssh-user-ca"
  }
}
```

**Key Creation:**
```bash
step kms create --kms "$PKCS_URI" "pkcs11:id=7333;object=ssh-host-ca"
step kms create --kms "$PKCS_URI" "pkcs11:id=7334;object=ssh-user-ca"
```

### Why This Doesn't Work for Us

1. **Missing Plugin**: `step kms create` requires the [step-kms-plugin](https://github.com/smallstep/step-kms-plugin) which is not installed

2. **Limited YubiKey Slots**: YubiKey NEO has limited PIV slots:
   - Slot 9c: Intermediate CA (Sword of Omens) - **IN USE**
   - Slot 9d: Intermediate CA backup - **IN USE**
   - Slot 9a: Authentication (typically reserved)
   - Slot 9e: Card authentication (typically reserved)

3. **Incompatible Key Storage**: When KMS is configured globally, step-ca parses ALL key paths through the KMS system:
   - File paths: `/etc/step-ca/ssh_host_ca_key` → Error: "scheme is missing"
   - File URIs: `file:///etc/step-ca/ssh_host_ca_key` → Error: "scheme not expected"
   - SoftKMS: `softkms:path=/etc/step-ca/ssh_host_ca_key` → Error: "scheme not expected"

### Supported Key Storage Formats

From [step-ca configuration documentation](https://smallstep.com/docs/step-ca/configuration/):

1. **Local Files**: `/path/to/ssh_host_ca_key` (only works WITHOUT global KMS config)
2. **PKCS#11**: `pkcs11:id=7333;object=ssh-host-ca`
3. **Google Cloud KMS**: `projects/PROJECT/locations/LOCATION/keyRings/RING/cryptoKeys/KEY/cryptoKeyVersions/1`
4. **AWS KMS**: `awskms:key-id=UUID`
5. **YubiKey**: `yubikey:slot-id=84`

---

## Attempted Solutions

### Attempt 1: Unencrypted File-Based Keys
```bash
step crypto keypair ssh_host_ca_key.pub ssh_host_ca_key --kty RSA --size 2048 --no-password --insecure
```
**Configuration:**
```json
"ssh": {
  "hostKey": "/etc/step-ca/ssh_host_ca_key",
  "userKey": "/etc/step-ca/ssh_user_ca_key"
}
```
**Result:** ❌ Error: "scheme is missing"

### Attempt 2: Encrypted File-Based Keys
```bash
step crypto keypair ssh_host_ca_key.pub ssh_host_ca_key --kty RSA --size 2048 --password-file .ssh-ca-password
```
**Configuration:** Same as Attempt 1
**Result:** ❌ Error: "scheme is missing"

### Attempt 3: File URI Scheme
**Configuration:**
```json
"ssh": {
  "hostKey": "file:///etc/step-ca/ssh_host_ca_key",
  "userKey": "file:///etc/step-ca/ssh_user_ca_key"
}
```
**Result:** ❌ Error: "scheme not expected"

### Attempt 4: SoftKMS Scheme
**Configuration:**
```json
"ssh": {
  "hostKey": "softkms:path=/etc/step-ca/ssh_host_ca_key",
  "userKey": "softkms:path=/etc/step-ca/ssh_user_ca_key"
}
```
**Result:** ❌ Error: "scheme not expected"

---

## Root Cause Analysis

When step-ca has a global `kms` configuration block, the KMS URI parser is invoked for ALL cryptographic keys, including SSH CA keys. The parser expects:

1. A recognized scheme (pkcs11:, awskms:, gcpkms:, yubikey:, etc.)
2. The scheme-specific URI format

File paths (with or without `file://` prefix) are not valid KMS URIs, causing the errors.

**Code Flow:**
```
ca.json loaded → KMS config detected → All key paths parsed as KMS URIs →
File path doesn't match KMS URI format → Error
```

---

## Alternative Solutions

### Option A: Install step-kms-plugin + Use Additional YubiKey Slots

**Requirements:**
1. Install step-kms-plugin: https://github.com/smallstep/step-kms-plugin
2. Identify free YubiKey slots (may need slot 82-95 range if available on NEO)
3. Generate SSH CA keys in YubiKey using `step kms create`

**Pros:**
- ✅ Consistent with existing PKCS11 architecture
- ✅ SSH CA keys hardware-protected
- ✅ Follows Smallstep best practices

**Cons:**
- ❌ YubiKey NEO may not have enough free slots
- ❌ Additional dependency (step-kms-plugin)
- ❌ Complexity of managing multiple keys in hardware

**Effort:** Medium (2-4 hours)

### Option B: Native OpenSSH CA (Without step-ca)

**Architecture:**
```
┌─────────────────────────────────┐
│ OpenSSH CA (ca.funlab.casa)     │
│                                  │
│ /etc/ssh/ca_keys/                │
│   ├── ssh_host_ca_key           │
│   └── ssh_user_ca_key           │
│                                  │
│ ssh-keygen -s ca_key ...         │
└─────────────────────────────────┘
```

**Implementation:**
```bash
# Generate CA keys
ssh-keygen -t ed25519 -f /etc/ssh/ca_keys/ssh_user_ca_key -C "SSH User CA"
ssh-keygen -t ed25519 -f /etc/ssh/ca_keys/ssh_host_ca_key -C "SSH Host CA"

# Sign host certificate
ssh-keygen -s /etc/ssh/ca_keys/ssh_host_ca_key \
  -I "spire.funlab.casa" \
  -h \
  -n spire.funlab.casa,spire \
  -V +365d \
  /etc/ssh/ssh_host_ed25519_key.pub

# Sign user certificate
ssh-keygen -s /etc/ssh/ca_keys/ssh_user_ca_key \
  -I "root@ca" \
  -n root \
  -V +8h \
  ~/.ssh/id_ed25519.pub
```

**Pros:**
- ✅ Simple, native OpenSSH functionality
- ✅ No additional dependencies
- ✅ Well-documented and widely used
- ✅ Works independently of step-ca issues
- ✅ Easier to automate certificate renewal

**Cons:**
- ❌ Not integrated with step-ca
- ❌ Manual certificate management
- ❌ No web UI for certificate requests

**Effort:** Low (1-2 hours)

### Option C: Separate step-ca Instance for SSH Only

**Architecture:**
```
┌──────────────────────────────────┐     ┌──────────────────────────────┐
│ step-ca-x509 (ca.funlab.casa)   │     │ step-ca-ssh (spire)          │
│ Port: 443                         │     │ Port: 8443                   │
│ PKCS11 (YubiKey)                  │     │ File-based keys              │
│ X.509 certificates only           │     │ SSH certificates only        │
└──────────────────────────────────┘     └──────────────────────────────┘
```

**Pros:**
- ✅ Separate concerns (X.509 vs SSH)
- ✅ SSH instance uses simple file-based keys
- ✅ Both use step-ca tooling
- ✅ Scalable architecture

**Cons:**
- ❌ Runs another CA instance
- ❌ Additional resource usage
- ❌ More complex configuration management

**Effort:** Medium (3-5 hours)

### Option D: Hybrid Approach

Use native OpenSSH CA for automation scripts, keep step-ca for X.509:

**Automation SSH Certs:**
- Trust bundle updates: OpenSSH CA
- Keylime cert distribution: OpenSSH CA
- Monitoring scripts: OpenSSH CA

**User SSH Certs (Future):**
- Interactive logins: step-ca SSH (when implemented properly)
- OIDC integration: step-ca SSH

**Pros:**
- ✅ Unblocks Phase 3 immediately
- ✅ Simple for automation use cases
- ✅ Allows future step-ca SSH integration
- ✅ Best of both worlds

**Cons:**
- ❌ Two different SSH CA systems
- ❌ Some complexity in certificate management

**Effort:** Low (1-2 hours for OpenSSH part)

---

## Recommendation

**Proceed with Option B: Native OpenSSH CA**

**Rationale:**
1. **Immediate Value**: Unblocks Phase 3 goals (short-lived SSH certs for automation)
2. **Simplicity**: Well-understood, native OpenSSH functionality
3. **Security**: Achieves core security goal (replace static keys with certificates)
4. **Pragmatic**: Solves the actual problem (automated SSH for scripts)
5. **Reversible**: Can migrate to step-ca SSH later if needed

**Phase 3 Revised Plan:**
1. ✅ Audit SSH usage (COMPLETED - Task #28)
2. Generate OpenSSH CA keypairs
3. Configure SSH hosts to trust CA (TrustedUserCAKeys)
4. Create certificate signing wrapper script
5. Update automation scripts to use certificates
6. Test all automated SSH flows
7. Remove static SSH private keys
8. Document and monitor

---

## Implementation Steps for Option B

### 1. Generate SSH CA Keys

```bash
# On ca.funlab.casa
sudo mkdir -p /etc/ssh/ca_keys
sudo chmod 700 /etc/ssh/ca_keys

# User CA (for automation accounts like root)
sudo ssh-keygen -t ed25519 \
  -f /etc/ssh/ca_keys/ssh_user_ca_key \
  -C "Funlab SSH User CA" \
  -N ""

# Host CA (for server host keys)
sudo ssh-keygen -t ed25519 \
  -f /etc/ssh/ca_keys/ssh_host_ca_key \
  -C "Funlab SSH Host CA" \
  -N ""

sudo chmod 600 /etc/ssh/ca_keys/*_ca_key
sudo chmod 644 /etc/ssh/ca_keys/*_ca_key.pub
```

### 2. Configure SSH Hosts

```bash
# On all hosts (ca, auth, spire)
sudo mkdir -p /etc/ssh/ca_certs
sudo scp ca.funlab.casa:/etc/ssh/ca_keys/ssh_user_ca_key.pub /etc/ssh/ca_certs/
sudo scp ca.funlab.casa:/etc/ssh/ca_keys/ssh_host_ca_key.pub /etc/ssh/ca_certs/

# Add to /etc/ssh/sshd_config
echo "TrustedUserCAKeys /etc/ssh/ca_certs/ssh_user_ca_key.pub" | sudo tee -a /etc/ssh/sshd_config
sudo systemctl reload sshd
```

### 3. Sign Host Certificates

```bash
# On ca.funlab.casa
for host in ca auth spire; do
  ssh ${host}.funlab.casa "sudo cat /etc/ssh/ssh_host_ed25519_key.pub" > /tmp/${host}_host_key.pub

  sudo ssh-keygen -s /etc/ssh/ca_keys/ssh_host_ca_key \
    -I "${host}.funlab.casa" \
    -h \
    -n ${host}.funlab.casa,${host} \
    -V +365d \
    /tmp/${host}_host_key.pub

  scp /tmp/${host}_host_key-cert.pub ${host}.funlab.casa:/tmp/
  ssh ${host}.funlab.casa "sudo mv /tmp/${host}_host_key-cert.pub /etc/ssh/ssh_host_ed25519_key-cert.pub"
done
```

### 4. Create Certificate Request Script

```bash
# /usr/local/bin/request-ssh-cert
#!/bin/bash
# Request SSH user certificate from CA

KEY_PATH="${1:-$HOME/.ssh/id_ed25519}"
VALIDITY="${2:-8h}"
USER=$(whoami)

if [ ! -f "$KEY_PATH" ]; then
    echo "Error: Key not found at $KEY_PATH"
    exit 1
fi

# Sign certificate on CA
ssh ca.funlab.casa "sudo ssh-keygen -s /etc/ssh/ca_keys/ssh_user_ca_key \
  -I '$USER@$(hostname)' \
  -n $USER \
  -V +$VALIDITY \
  -z $(date +%s) \
  /tmp/$(basename $KEY_PATH).pub" < "${KEY_PATH}.pub"

# Fetch signed certificate
scp ca.funlab.casa:/tmp/$(basename $KEY_PATH)-cert.pub "${KEY_PATH}-cert.pub"

echo "Certificate issued: ${KEY_PATH}-cert.pub (valid for $VALIDITY)"
```

### 5. Automated Certificate Renewal

```bash
# /etc/cron.hourly/renew-ssh-cert
#!/bin/bash
# Auto-renew SSH certificates before expiration

CERT_FILE="/root/.ssh/id_ed25519-cert.pub"

# Check if certificate exists and expiration
if [ -f "$CERT_FILE" ]; then
    EXPIRY=$(ssh-keygen -L -f "$CERT_FILE" | grep "Valid:" | awk '{print $5}')
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    HOURS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 3600 ))

    # Renew if less than 2 hours remaining
    if [ $HOURS_LEFT -lt 2 ]; then
        /usr/local/bin/request-ssh-cert /root/.ssh/id_ed25519 8h
    fi
else
    # No certificate, request one
    /usr/local/bin/request-ssh-cert /root/.ssh/id_ed25519 8h
fi
```

---

## Security Considerations

### SSH CA Key Protection

**Current Plan:** File-based keys in `/etc/ssh/ca_keys/`
- Permissions: 600 (root only)
- Location: Encrypted filesystem
- Backup: Store in 1Password (offline)

**Future Enhancement:** Move to YubiKey when step-kms-plugin is available

### Certificate Policies

**User Certificates:**
- Validity: 8 hours (automation scripts)
- Principals: Specific username (root, service accounts)
- Extensions: None required for basic auth

**Host Certificates:**
- Validity: 365 days
- Principals: FQDN + short hostname
- Renewal: Annual (can be automated)

### Audit Trail

- Certificate serial numbers: Unix timestamp
- Signed certificate logs: Journal via wrapper script
- SSH authentication logs: /var/log/auth.log

---

## Lessons Learned

1. **KMS Scope**: When step-ca has a global KMS configuration, it applies to ALL cryptographic operations
2. **YubiKey Limits**: Hardware tokens have finite key storage slots
3. **Documentation Gaps**: Step-ca + PKCS11 + SSH configuration not well documented for YubiKey scenarios
4. **Pragmatism**: Native solutions (OpenSSH CA) can be better than forcing tool integration
5. **Reversibility**: Choose solutions that don't prevent future improvements

---

## Sources

- [How to use step-ca with Hardware Security Modules (HSMs)](https://smallstep.com/blog/step-ca-supports-pkcs-11-cloudhsm/)
- [Secure Cryptographic Key Protection Methods | Smallstep](https://smallstep.com/docs/step-ca/cryptographic-protection/)
- [Configuring open source step-ca | Smallstep](https://smallstep.com/docs/step-ca/configuration/)
- [How to add SSH support to an existing step-ca? | GitHub Discussion #400](https://github.com/smallstep/certificates/discussions/400)
- [Run an SSH CA and connect to hosts using SSH certificates | Smallstep](https://smallstep.com/docs/tutorials/ssh-certificate-login/)
- [GitHub - smallstep/step-kms-plugin](https://github.com/smallstep/step-kms-plugin)

---

**Document Version:** 1.0
**Last Updated:** 2026-02-13 00:05 EST
**Status:** Research Complete
**Recommendation:** Proceed with Option B (Native OpenSSH CA)
