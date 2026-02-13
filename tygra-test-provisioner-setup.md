# tygra-test Provisioner Setup

**Date:** 2026-02-13  
**Status:** ✅ Deployed and Operational

---

## Overview

Created a new JWK provisioner `tygra-test` for testing SSH certificate signing on the step-ca SSH CA infrastructure.

## Provisioner Details

- **Name:** `tygra-test`
- **Type:** JWK (JSON Web Key)
- **Password:** `TygraTest2026!`
- **KID:** `nWkjB6bJuPl91O6CAh0Cz1mdhie4CnRpTKX4_S4JZmU`
- **Algorithm:** ECDSA P-256 (ES256)
- **SSH CA:** Enabled (`enableSSHCA: true`)

## Deployment Locations

The provisioner has been added to both step-ca instances on ca.funlab.casa:

### 1. Main CA (ca.funlab.casa:443/8443)
- **Config:** `/etc/step-ca/config/ca.json`
- **Service:** `step-ca.service`
- **Purpose:** TLS/X.509 certificates
- **Provisioners:** tower-of-omens, acme, tpm-devid, **tygra-test**

### 2. SSH CA (tygra.funlab.casa:8444)
- **Config:** `/etc/step-ca-ssh/config/ca.json`
- **Service:** `step-ca-ssh.service`
- **Purpose:** SSH certificates (user & host)
- **Provisioners:** tygra-admin, **tygra-test**
- **SSH Host CA:** `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAntL2ChmQQR6cUqmCAG3jVGW/8dyWLoqHTOMUg+vKIm`
- **SSH User CA:** `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDxiwMjSnVSwS4qMHDM27BkXdbpN9EDjvwtM3jfd1sTA`

---

## Configuration

### Provisioner JSON

```json
{
  "type": "JWK",
  "name": "tygra-test",
  "key": {
    "use": "sig",
    "kty": "EC",
    "kid": "nWkjB6bJuPl91O6CAh0Cz1mdhie4CnRpTKX4_S4JZmU",
    "crv": "P-256",
    "alg": "ES256",
    "x": "Ih2YIf-a46CPnIbLczy3uoy4bJaSMYyrVzg3DvmW1O8",
    "y": "tDdUwoK5Fe26VEZRUQgNITB1j1iRYJUy-sFtk1eEy7o"
  },
  "encryptedKey": "eyJhbGciOiJQQkVTMi1IUzI1NitBMTI4S1ciLCJjdHkiOiJqd2sranNvbiIsImVuYyI6IkEyNTZHQ00iLCJwMmMiOjYwMDAwMCwicDJzIjoiV3NVaVdFRW1uV1dTdWl0eENGaVExUSJ9.PhTI5prH72AsMjj8JGu9TvkjTZxXgK5e3GTKoyR9AcpuVxXX7Mrr_w.o6PxoD8JN3cUsmEs.GWC0bTSbtl0D0oGtieoU-tByo3qNLggAcOK-L_pSTIEopcwoQOz2C5TyKiPCqPaSQheDMQFJoUnVD7ola_SWxLuyMGzIjvwUgNhnyy1jK8WRFENgzuPMiCVTHDJ982QpYYOS9cQbc5oT5mHwXaNAM2GM4UpTAh0fgm4IGfyh-ytqUJgcZUAlbZOqyakTES7rcCXX_K1ZBARE2zPHHL-QAkOngRQnsMj7asGspjE9G1rGq5kzzpH9Rj70w3joL5kMHzaPT4FIHdx9kqfn1gGgmVp_BWke55_M83BTcZgBk84RyU7gRGMbUTddWvgz9QNKFAPLvdVjpXbxIJm0RO0.viTw8uOPu2CyZOjlni7Vcg",
  "claims": {
    "enableSSHCA": true
  }
}
```

### Key Files Created

**Local (bullwinkle@bullwinkle):**
- `/tmp/tygra-test-pub.jwk` - Public JWK
- `/tmp/tygra-test-priv.jwk` - Private JWK (encrypted)
- `/tmp/provisioner-password.txt` - Password file
- `/tmp/new-provisioner-config.json` - Provisioner configuration
- `/tmp/new-provisioner-ssh-fixed.json` - Final SSH-enabled configuration

**Remote (ca.funlab.casa):**
- Configuration backups created automatically with timestamps

---

## Usage

### SSH Certificate Signing

#### Sign User SSH Certificate

```bash
step ssh certificate <username> <public-key-path> \
  --provisioner tygra-test \
  --ca-url https://tygra.funlab.casa:8444 \
  --root <(curl -sk https://tygra.funlab.casa:8444/roots.pem) \
  --password-file <(echo "TygraTest2026!") \
  --principal <username> \
  --not-after 1h \
  --force
```

**Example:**
```bash
step ssh certificate bullwinkle ~/.ssh/id_ed25519.pub \
  --provisioner tygra-test \
  --ca-url https://tygra.funlab.casa:8444 \
  --root <(curl -sk https://tygra.funlab.casa:8444/roots.pem) \
  --password-file <(echo "TygraTest2026!") \
  --principal bullwinkle \
  --principal root \
  --not-after 1h \
  --force
```

#### Sign Host SSH Certificate

```bash
step ssh certificate <hostname> /etc/ssh/ssh_host_ed25519_key.pub \
  --provisioner tygra-test \
  --ca-url https://tygra.funlab.casa:8444 \
  --root <(curl -sk https://tygra.funlab.casa:8444/roots.pem) \
  --password-file <(echo "TygraTest2026!") \
  --host \
  --principal <hostname> \
  --not-after 24h \
  --force
```

#### Get OTT (One-Time Token)

```bash
step ca token <subject> \
  --provisioner tygra-test \
  --ca-url https://tygra.funlab.casa:8444 \
  --root <(curl -sk https://tygra.funlab.casa:8444/roots.pem) \
  --password-file <(echo "TygraTest2026!") \
  --ssh
```

### Verify Certificate

```bash
ssh-keygen -L -f <certificate-file>
```

---

## Verification

### Check Provisioner is Available

```bash
curl -k https://tygra.funlab.casa:8444/1.0/provisioners | jq '.provisioners[] | select(.name=="tygra-test")'
```

**Expected Output:**
```json
{
  "name": "tygra-test",
  "type": "JWK",
  "kid": "nWkjB6bJuPl91O6CAh0Cz1mdhie4CnRpTKX4_S4JZmU"
}
```

### Check SSH CA Keys

```bash
curl -k https://tygra.funlab.casa:8444/ssh/roots
```

**Expected Output:**
```json
{
  "userKey": ["AAAAC3NzaC1lZDI1NTE5AAAAIDxiwMjSnVSwS4qMHDM27BkXdbpN9EDjvwtM3jfd1sTA"],
  "hostKey": ["AAAAC3NzaC1lZDI1NTE5AAAAIAntL2ChmQQR6cUqmCAG3jVGW/8dyWLoqHTOMUg+vKIm"]
}
```

### Service Status

**On ca.funlab.casa:**
```bash
# Main CA
systemctl status step-ca

# SSH CA
systemctl status step-ca-ssh
```

---

## Deployment History

### 2026-02-13 - Initial Deployment

1. Generated new JWK key pair with password `TygraTest2026!`
2. Added provisioner to `/etc/step-ca/config/ca.json` (main CA)
3. Added provisioner to `/etc/step-ca-ssh/config/ca.json` (SSH CA)
4. Initially deployed without `enableSSHCA` - **FAILED**
   - Error: `sshCA is disabled for jwk provisioner 'tygra-test'`
5. Added `claims.enableSSHCA: true` - **SUCCESS**
6. Restarted both services
7. Verified provisioner availability via API
8. Tested token generation - **SUCCESS**

### Configuration Backups

Backups created on ca.funlab.casa:
- `/etc/step-ca/config/ca.json.backup-<timestamp>`
- `/etc/step-ca-ssh/config/ca.json.backup-<timestamp>`

---

## Security Notes

⚠️ **Important Security Considerations:**

1. **Test Provisioner:** This is a **test provisioner** with a known password
2. **Password Storage:** Password is `TygraTest2026!` - stored in documentation for testing
3. **Production Use:** For production:
   - Generate a strong, unique password
   - Store password in 1Password or secure vault
   - Rotate provisioner keys periodically
   - Monitor provisioner usage
4. **Certificate Lifetimes:**
   - User certificates: 1-8 hours recommended
   - Host certificates: 24 hours - 7 days recommended
5. **Principal Management:** Only grant necessary principals to users

---

## Troubleshooting

### Provisioner Not Found

```bash
# List all provisioners
curl -k https://tygra.funlab.casa:8444/1.0/provisioners | jq '.provisioners[].name'

# Check configuration
ssh ca.funlab.casa 'sudo jq ".authority.provisioners[].name" /etc/step-ca-ssh/config/ca.json'
```

### SSH CA Disabled Error

If you see: `sshCA is disabled for jwk provisioner`

**Solution:** Ensure provisioner has `claims.enableSSHCA: true`:
```json
{
  "name": "tygra-test",
  "claims": {
    "enableSSHCA": true
  }
}
```

### Service Failed to Start

```bash
# Check logs
ssh ca.funlab.casa 'sudo journalctl -u step-ca-ssh -n 50 --no-pager'

# Validate configuration
ssh ca.funlab.casa 'sudo jq "." /etc/step-ca-ssh/config/ca.json'
```

### Token Generation Fails

```bash
# Verify password is correct
echo "TygraTest2026!" > /tmp/test-password.txt

# Test token generation
step ca token testuser \
  --provisioner tygra-test \
  --ca-url https://tygra.funlab.casa:8444 \
  --root <(curl -sk https://tygra.funlab.casa:8444/roots.pem) \
  --password-file /tmp/test-password.txt \
  --ssh
```

---

## Related Documentation

- [step-ca-deployment-summary.md](/tmp/step-ca-deployment-summary.md) - Main CA deployment
- [certificate-management-plan.md](/tmp/certificate-management-plan.md) - Short-lived certificate strategy
- [PROVISIONER-SETUP-INSTRUCTIONS.md](/tmp/PROVISIONER-SETUP-INSTRUCTIONS.md) - Generic provisioner setup guide

---

## Next Steps

1. ✅ Provisioner created and deployed
2. ✅ Token generation verified
3. 🔲 Complete end-to-end SSH certificate signing test (requires TTY)
4. 🔲 Integrate with SSH client configurations
5. 🔲 Set up automated certificate rotation
6. 🔲 Configure monitoring for certificate expiration
7. 🔲 Document SSH CA trust distribution

---

**Deployment Status:** ✅ **OPERATIONAL**  
**Last Updated:** 2026-02-13 03:15 EST  
**Deployed By:** Claude Sonnet 4.5 + bullwinkle@bullwinkle
