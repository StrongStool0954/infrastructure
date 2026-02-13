# Tygra SSH CA Setup - Summary

## ✅ Completed

### Infrastructure Setup
- **SSH CA Instance**: tygra.funlab.casa running on ca.funlab.casa:8444
- **Nginx Reverse Proxy**: Both CAs proxied through nginx on port 443
  - ca.funlab.casa:443 → localhost:8443 (Main TLS CA)
  - tygra.funlab.casa:443 → localhost:8444 (SSH CA)
- **DNS**: tygra.funlab.casa resolves to 10.10.2.60 ✅
- **Services Running**:
  - `step-ca.service` (main CA) - Active
  - `step-ca-ssh.service` (SSH CA) - Active
  - `nginx.service` - Active

### SSH CA Configuration  
- **Location**: `/etc/step-ca-ssh/`
- **Config**: `/etc/step-ca-ssh/config/ca.json`
- **SSH CA Keys**: `/etc/step-ca-ssh/secrets/`
  - Host CA: `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAntL2ChmQQR6cUqmCAG3jVGW/8dyWLoqHTOMUg+vKIm`
  - User CA: `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDxiwMjSnVSwS4qMHDM27BkXdbpN9EDjvwtM3jfd1sTA`
- **Provisioner**: tygra-admin (JWK, no password)
- **Root Fingerprint**: `af7f85bc6dddf5f29e7fa3f63d0eace6f3366201c758bae80ba4197907604526`

### API Verification
- Health endpoint: `curl -k https://tygra.funlab.casa/health` → `{"status":"ok"}` ✅
- SSH sign endpoint responds correctly (requires OTT authentication) ✅

## ⚠️ Known Issue

### TLS Certificate for Nginx
The nginx reverse proxy is currently using a self-signed certificate which causes TLS verification failures with step CLI:
```
client GET https://tygra.funlab.casa/provisioners failed: 
tls: failed to verify certificate: x509: certificate signed by unknown authority
```

**Workarounds**:
1. Use `--insecure` flag (not working with current step CLI version for HTTPS to CA)
2. Test directly on port 8444 (bypasses nginx)  
3. Use curl with `-k` flag for API testing

**Proper Solutions** (TODO):
1. Issue nginx TLS certificates from the main step-ca CA using ACME
2. Or use Let's Encrypt for tygra.funlab.casa
3. Or configure step CLI to trust the self-signed nginx certificate

## 📋 Next Steps

1. **Fix nginx TLS certificates** - Use main CA to issue proper certs
2. **Test SSH certificate issuance end-to-end** with step CLI
3. **Configure SSH hosts to trust the CA** (Task #31)
4. **Update automation scripts** (Task #30)
5. **Remove static SSH keys** (Task #32)

## Manual Testing (Current Workaround)

Since step CLI has TLS verification issues, test via curl:

```bash
# Generate a test SSH key
ssh-keygen -t ed25519 -f /tmp/testkey -N ""

# Get the base64 part of the public key
PUBKEY_B64=$(awk '{print $2}' /tmp/testkey.pub)

# Create signing request (requires OTT - one-time token)
# Note: Token generation requires provisioner authentication
curl -k https://tygra.funlab.casa/ssh/sign \
  -H "Content-Type: application/json" \
  -d "{
    \"ott\": \"<TOKEN_HERE>\",
    \"publicKey\": \"$PUBKEY_B64\",
    \"principals\": [\"username\"],
    \"certType\": \"user\"
  }"
```

## Files Created

- `/etc/step-ca-ssh/` - SSH CA instance directory
- `/etc/nginx/ssl/tygra.funlab.casa.{crt,key}` - Nginx TLS certificates (self-signed)
- `/etc/nginx/sites-available/tygra.funlab.casa` - Nginx vhost config
- `/etc/systemd/system/step-ca-ssh.service` - Systemd service file
- `/home/bullwinkle/infrastructure/tygra-ssh-ca-keys.md` - SSH CA public keys reference
