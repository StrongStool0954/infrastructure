# 1Password Inventory - ca.funlab.casa

**Vault:** `Funlab.Casa.Ca`
**Purpose:** Secure storage of all sensitive data for ca.funlab.casa Certificate Authority
**Date:** 2026-02-10

---

## Complete Reinstallation Data

This vault contains ALL data required to rebuild ca.funlab.casa from scratch, including:
- YubiKey credentials
- CA private keys and certificates
- API keys for automated services

---

## Items Inventory

### 1. YubiKey NEO - ca.funlab.casa (SN: 5497305)

**Type:** Document
**Contains:**
```
PIN: S1iNIv2g
PUK: XZSwlSSR
Management Key: de0836a40794ff047e9dc1658a98a3471af2b63a309ce111
```

**Usage:**
- **PIN:** Required for YubiKey signing operations (retrieved dynamically on step-ca startup)
- **PUK:** Emergency PIN unblock (8 retries before permanent lock)
- **Management Key:** Required for importing keys/certificates to YubiKey

**Retrieval:**
```bash
# Get PIN
op document get "YubiKey NEO - ca.funlab.casa (SN: 5497305)" \
  --vault "Funlab.Casa.Ca" | grep "^PIN:" | cut -d: -f2 | tr -d ' '

# Get Management Key
op document get "YubiKey NEO - ca.funlab.casa (SN: 5497305)" \
  --vault "Funlab.Casa.Ca" | grep "^Management Key:" | cut -d: -f2 | tr -d ' '
```

---

### 2. Sword of Omens - Intermediate CA Private Key

**Type:** Document
**Format:** PEM-encoded RSA 2048-bit private key

**Details:**
- Used by: step-ca for signing certificates
- Primary Storage: YubiKey NEO slot 9d (hardware-backed)
- Backup Purpose: Disaster recovery if YubiKey lost/destroyed

**Usage:**
```bash
# Retrieve for YubiKey import
op document get "Sword of Omens - Intermediate CA Private Key" \
  --vault "Funlab.Casa.Ca" > /tmp/intermediate_key.pem
chmod 600 /tmp/intermediate_key.pem
```

**Security:** This key should NEVER be stored unencrypted on disk permanently. Only retrieve for YubiKey import operations.

---

### 3. Sword of Omens - Intermediate CA Certificate

**Type:** Document
**Format:** PEM-encoded X.509 certificate

**Details:**
- Subject: CN=Sword of Omens
- Issuer: CN=Eye of Thundera (Root CA)
- Valid: 2026-02-10 to 2036-02-08 (10 years)
- Algorithm: RSA 2048 with SHA-256

**Usage:**
```bash
# Retrieve for YubiKey import
op document get "Sword of Omens - Intermediate CA Certificate" \
  --vault "Funlab.Casa.Ca" > /tmp/intermediate_cert.pem

# Import to YubiKey slot 9d
yubico-piv-tool -s 9d -a import-certificate \
  -k <management-key> -i /tmp/intermediate_cert.pem
```

---

### 4. Eye of Thundera - Root CA Private Key

**Type:** Document
**Format:** PEM-encoded RSA 4096-bit private key

**Details:**
- Self-signed root CA
- Valid: 2026-02-10 to 2126-02-10 (100 years)
- **CRITICAL:** Store offline, use only for signing intermediate CAs

**Usage:**
```bash
# Retrieve for signing new intermediate CA (rare operation)
op document get "Eye of Thundera - Root CA Private Key" \
  --vault "Funlab.Casa.Ca" > /tmp/root_key.pem
chmod 600 /tmp/root_key.pem

# Sign intermediate CA certificate
step certificate sign intermediate_csr.pem root_ca.crt root_key.pem \
  --profile intermediate-ca --not-after 87600h
```

**Security:** Only retrieve when creating or renewing intermediate CA certificates.

---

### 5. Eye of Thundera - Root CA Certificate

**Type:** Document
**Format:** PEM-encoded X.509 certificate

**Details:**
- Subject: CN=Eye of Thundera
- Issuer: CN=Eye of Thundera (self-signed)
- Valid: 2026-02-10 to 2126-02-10 (100 years)

**Usage:**
```bash
# Retrieve for step-ca configuration
op document get "Eye of Thundera - Root CA Certificate" \
  --vault "Funlab.Casa.Ca" > /etc/step-ca/certs/root_ca.crt

# Install in system trust store
sudo cp /etc/step-ca/certs/root_ca.crt \
  /usr/local/share/ca-certificates/eye-of-thundera.crt
sudo update-ca-certificates
```

---

### 6. Bunny DNS API Key

**Type:** Login/API Credential
**Field:** `credential` (concealed)

**Details:**
- API Key: `b07f787e-d065-463c-86b0-05d1f3ebd639bf69179f-8679-401c-a14c-182710328487`
- Purpose: Automated DNS-01 challenge validation for ACME
- Permissions: DNS zone management for funlab.casa

**Usage:**
```bash
# Retrieve for ACME operations
BUNNY_API_KEY=$(op item get "Bunny DNS API Key" \
  --vault "Funlab.Casa.Ca" --fields credential --reveal)
export BUNNY_API_KEY

# Used automatically by /usr/local/bin/acme-with-bunny wrapper
```

**Security:** Retrieved dynamically, never stored in config files.

---

## Disaster Recovery Procedure

### Scenario: Complete System Loss

**Prerequisites:**
- 1Password access to `Funlab.Casa.Ca` vault
- YubiKey NEO (Serial: 5497305) - if available
- If YubiKey lost: Order replacement YubiKey

### Recovery Steps

#### 1. Install step-ca
```bash
wget https://dl.smallstep.com/cli/docs-ca-install/latest/step-ca_amd64.deb
sudo dpkg -i step-ca_amd64.deb
```

#### 2. Retrieve Certificates
```bash
# Root CA
op document get "Eye of Thundera - Root CA Certificate" \
  --vault "Funlab.Casa.Ca" > /etc/step-ca/certs/root_ca.crt

# Intermediate CA certificate
op document get "Sword of Omens - Intermediate CA Certificate" \
  --vault "Funlab.Casa.Ca" > /etc/step-ca/certs/intermediate_ca.crt
```

#### 3. Import Key to YubiKey
```bash
# Get management key and private key
MGMT_KEY=$(op document get "YubiKey NEO - ca.funlab.casa (SN: 5497305)" \
  --vault "Funlab.Casa.Ca" | grep "^Management Key:" | cut -d: -f2 | tr -d ' ')

op document get "Sword of Omens - Intermediate CA Private Key" \
  --vault "Funlab.Casa.Ca" > /tmp/intermediate_key.pem

# Import to slot 9d (NOT 9c!)
cat <<EOF | yubico-piv-tool -s 9d -a import-key -k - -i /tmp/intermediate_key.pem
$MGMT_KEY
EOF

# Import certificate
cat <<EOF | yubico-piv-tool -s 9d -a import-certificate -k - -i /etc/step-ca/certs/intermediate_ca.crt
$MGMT_KEY
EOF

# Secure cleanup
rm -f /tmp/intermediate_key.pem
```

#### 4. Configure step-ca
```bash
# Use sanitized config as template
# Update PKCS11 URI to use slot 9d (id=%03)
# Configure pin-source=file:///run/step-ca/yubikey-pin
```

#### 5. Install PIN Retrieval Script
```bash
# Copy from repository or recreate
sudo cp setup-yubikey-pin-for-step-ca /usr/local/bin/
sudo chmod +x /usr/local/bin/setup-yubikey-pin-for-step-ca
```

#### 6. Install systemd Service
```bash
sudo cp step-ca.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable step-ca
sudo systemctl start step-ca
```

#### 7. Install ACME Wrapper
```bash
sudo cp acme-with-bunny /usr/local/bin/
sudo chmod +x /usr/local/bin/acme-with-bunny
```

#### 8. Test Certificate Issuance
```bash
sudo acme-with-bunny --issue -d recovery-test.funlab.casa --dns dns_bunny
```

---

## Access Control

### Required Service Accounts

1. **1Password Service Account** (`step` user on ca.funlab.casa)
   - Access to: `Funlab.Casa.Ca` vault
   - Permissions: Read-only
   - Config: `/var/lib/step-ca/tmp/.config/op/`

### Vault Permissions

**Read Access Required For:**
- step-ca service (for PIN retrieval)
- System administrators (for disaster recovery)
- Automated backup systems

**No Write Access:** Vault contents should only be modified manually by administrators.

---

## Security Notes

1. **Never log secrets:**
   - Ensure scripts don't echo PINs, keys, or API tokens
   - Check systemd logs for accidental secret exposure

2. **Temporary file cleanup:**
   - Always `rm -f` after using private keys
   - Use `/tmp` with proper permissions (mode 600)

3. **YubiKey backup:**
   - Private key stored in 1Password is the ONLY backup
   - If YubiKey destroyed and backup lost, must generate new intermediate CA

4. **Root CA protection:**
   - Retrieve root CA private key ONLY for signing intermediate CAs
   - Consider storing root CA offline (e.g., encrypted USB in safe)

5. **API key rotation:**
   - Rotate Bunny API key annually
   - Update 1Password item
   - No configuration changes needed (retrieved dynamically)

---

**Last Updated:** 2026-02-10 16:30 EST
**Maintained By:** Infrastructure Team
**Review Schedule:** Quarterly
