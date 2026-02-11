# Nginx Reverse Proxy - Implementation Complete

**Date:** 2026-02-11
**Status:** ✅ OPERATIONAL
**Purpose:** Service-specific DNS with standard HTTPS ports

---

## Summary

Successfully implemented nginx reverse proxy for all infrastructure services with service-specific subdomains, eliminating the need to remember port numbers.

---

## What Was Implemented

### ✅ OpenBao PKI - WORKING
**Old URL:** `https://spire.funlab.casa:8200`
**New URL:** `https://openbao.funlab.casa` (port 443)

**Configuration:**
- Nginx reverse proxy on port 443
- Proxies to localhost:8200
- Certificate issued by Book of Omens PKI
- SANs: openbao.funlab.casa, spire.funlab.casa, keylime.funlab.casa

**Test:**
```bash
curl -k https://openbao.funlab.casa/v1/sys/health
# Returns: {"initialized":true,"sealed":false,"version":"2.5.0"}
```

---

### ✅ Keylime Verifier - WORKING
**Old URL:** `https://spire.funlab.casa:8881`
**New URL:** `https://verifier.keylime.funlab.casa` (port 443)

**Configuration:**
- Nginx reverse proxy on port 443
- Proxies to localhost:8881
- Certificate issued by Book of Omens PKI
- SANs: verifier.keylime.funlab.casa, registrar.keylime.funlab.casa, keylime.funlab.casa

**Test:**
```bash
curl -k https://verifier.keylime.funlab.casa/version
# Returns: {"code":200,"status":"Success","results":{"current_version":"2.5"}}
```

---

### ✅ Keylime Registrar - WORKING
**Old URL:** `https://spire.funlab.casa:8891`
**New URL:** `https://registrar.keylime.funlab.casa` (port 443)

**Configuration:**
- Nginx reverse proxy on port 443
- Proxies to localhost:8891
- Certificate issued by Book of Omens PKI
- SANs: verifier.keylime.funlab.casa, registrar.keylime.funlab.casa, keylime.funlab.casa

**Test:**
```bash
curl -k https://registrar.keylime.funlab.casa/version
# Returns: {"code":200,"status":"Success","results":{"current_version":"2.5"}}
```

---

## Service URLs

| Service | New URL | Old URL | Status |
|---------|---------|---------|--------|
| OpenBao PKI | https://openbao.funlab.casa | https://spire.funlab.casa:8200 | ✅ Working |
| Keylime Verifier | https://verifier.keylime.funlab.casa | https://spire.funlab.casa:8881 | ✅ Working |
| Keylime Registrar | https://registrar.keylime.funlab.casa | https://spire.funlab.casa:8891 | ✅ Working |
| SPIRE Server | https://spire.funlab.casa | spire.funlab.casa:8081 (gRPC) | ℹ️  Info page |

---

## Nginx Configuration

**Location:** `/etc/nginx/conf.d/services.conf`

### OpenBao Certificate
- Certificate: `/etc/nginx/certs/services.crt`
- Private Key: `/etc/nginx/certs/services.key`
- CA Chain: `/etc/nginx/certs/ca-chain.crt`
- Issuer: Book of Omens (OpenBao PKI)
- Validity: 30 days
- SANs: openbao.funlab.casa, spire.funlab.casa, keylime.funlab.casa, localhost, 10.10.2.62

### Keylime Certificate
- Certificate: `/etc/nginx/certs/keylime.crt`
- Private Key: `/etc/nginx/certs/keylime.key`
- CA Chain: `/etc/nginx/certs/keylime-ca-chain.crt`
- Issuer: Book of Omens (OpenBao PKI)
- Validity: 30 days
- SANs: verifier.keylime.funlab.casa, registrar.keylime.funlab.casa, keylime.funlab.casa, localhost, 10.10.2.62

**Virtual Hosts:**
1. openbao.funlab.casa:443 → localhost:8200 (OpenBao)
2. verifier.keylime.funlab.casa:443 → localhost:8881 (Keylime Verifier)
3. registrar.keylime.funlab.casa:443 → localhost:8891 (Keylime Registrar)
4. spire.funlab.casa:443 → Info page (SPIRE uses gRPC)

---

## DNS Configuration

All services resolve to **10.10.2.62** (spire.funlab.casa):

```dns
openbao.funlab.casa.                 IN  A   10.10.2.62
keylime.funlab.casa.                 IN  A   10.10.2.62
verifier.keylime.funlab.casa.        IN  A   10.10.2.62
registrar.keylime.funlab.casa.       IN  A   10.10.2.62
spire.funlab.casa.                   IN  A   10.10.2.62
```

---

## Benefits Achieved

✅ **No Port Numbers** - Standard HTTPS port 443
✅ **Service-Specific DNS** - Clear, self-documenting URLs
✅ **Better Certificates** - Proper CN and SANs for each service
✅ **Separate Subdomains** - Keylime services have dedicated subdomains
✅ **TLS Termination** - Nginx handles SSL/TLS
✅ **Future Ready** - Can add load balancing easily

---

## Usage Examples

### OpenBao Operations

**Old way (still works):**
```bash
export BAO_ADDR=https://spire.funlab.casa:8200
export BAO_SKIP_VERIFY=true
bao status
```

**New way (preferred):**
```bash
export BAO_ADDR=https://openbao.funlab.casa
export BAO_SKIP_VERIFY=true
bao status
```

### Keylime API Access

**Old way (with port numbers):**
```bash
curl -k https://spire.funlab.casa:8881/version
curl -k https://spire.funlab.casa:8891/version
```

**New way (preferred):**
```bash
curl -k https://verifier.keylime.funlab.casa/version
curl -k https://registrar.keylime.funlab.casa/version
```

### Certificate Issuance

```bash
# OpenBao certificate
bao write -format=json pki_int/issue/openbao-server \
    common_name='openbao.funlab.casa' \
    alt_names='spire.funlab.casa,keylime.funlab.casa,localhost' \
    ip_sans='10.10.2.62,127.0.0.1' \
    ttl='720h'

# Keylime certificate
bao write -format=json pki_int/issue/openbao-server \
    common_name='verifier.keylime.funlab.casa' \
    alt_names='registrar.keylime.funlab.casa,keylime.funlab.casa,localhost' \
    ip_sans='10.10.2.62,127.0.0.1' \
    ttl='720h'
```

---

## Notes

### Keylime Services
Both Keylime verifier and registrar are now running as systemd services and accessible via nginx reverse proxy. Services automatically start on boot and restart on failure.

**Systemd service units created:**
- `/etc/systemd/system/keylime_verifier.service` ✅
- `/etc/systemd/system/keylime_registrar.service` ✅

**Service management:**
```bash
# Check status
sudo systemctl status keylime_verifier
sudo systemctl status keylime_registrar

# View logs
sudo journalctl -u keylime_verifier -f
sudo journalctl -u keylime_registrar -f
```

See `KEYLIME-SYSTEMD-SERVICES.md` for complete service documentation.

### Certificate Renewal

Certificates expire in 30 days and should be renewed via OpenBao:

**OpenBao Certificate:**
```bash
export BAO_ADDR=https://openbao.funlab.casa
export BAO_TOKEN=<token>

# Renew certificate
bao write -format=json pki_int/issue/openbao-server \
    common_name='openbao.funlab.casa' \
    alt_names='spire.funlab.casa,keylime.funlab.casa,localhost' \
    ip_sans='10.10.2.62,127.0.0.1' \
    ttl='720h' > /tmp/nginx-cert.json

# Install new certificate
sudo jq -r '.data.certificate' /tmp/nginx-cert.json > /tmp/nginx.crt
sudo jq -r '.data.private_key' /tmp/nginx-cert.json > /tmp/nginx.key
sudo cp /tmp/nginx.crt /etc/nginx/certs/services.crt
sudo cp /tmp/nginx.key /etc/nginx/certs/services.key
sudo systemctl reload nginx
```

**Keylime Certificate:**
```bash
export BAO_ADDR=https://openbao.funlab.casa
export BAO_TOKEN=<token>

# Renew certificate
bao write -format=json pki_int/issue/openbao-server \
    common_name='verifier.keylime.funlab.casa' \
    alt_names='registrar.keylime.funlab.casa,keylime.funlab.casa,localhost' \
    ip_sans='10.10.2.62,127.0.0.1' \
    ttl='720h' > /tmp/keylime-nginx-cert.json

# Install new certificate
sudo jq -r '.data.certificate' /tmp/keylime-nginx-cert.json > /tmp/keylime.crt
sudo jq -r '.data.private_key' /tmp/keylime-nginx-cert.json > /tmp/keylime.key
sudo cp /tmp/keylime.crt /etc/nginx/certs/keylime.crt
sudo cp /tmp/keylime.key /etc/nginx/certs/keylime.key
sudo systemctl reload nginx
```

---

## Testing

### Verify DNS
```bash
dig +short openbao.funlab.casa
dig +short verifier.keylime.funlab.casa
dig +short registrar.keylime.funlab.casa
# All should return: 10.10.2.62
```

### Test Services
```bash
# OpenBao
curl -k https://openbao.funlab.casa/v1/sys/health
# Should return JSON with initialized=true

# Keylime Verifier
curl -k https://verifier.keylime.funlab.casa/version
# Should return JSON with current_version

# Keylime Registrar
curl -k https://registrar.keylime.funlab.casa/version
# Should return JSON with current_version
```

### Verify Certificates
```bash
# OpenBao certificate
echo | openssl s_client -connect openbao.funlab.casa:443 \
    -servername openbao.funlab.casa 2>/dev/null | \
    openssl x509 -noout -subject -issuer -ext subjectAltName

# Keylime certificate
echo | openssl s_client -connect verifier.keylime.funlab.casa:443 \
    -servername verifier.keylime.funlab.casa 2>/dev/null | \
    openssl x509 -noout -subject -issuer -ext subjectAltName
```

---

## Files Modified

- `/etc/nginx/conf.d/services.conf` - Nginx virtual host configuration
- `/etc/nginx/certs/services.crt` - OpenBao SSL certificate
- `/etc/nginx/certs/services.key` - OpenBao SSL private key
- `/etc/nginx/certs/ca-chain.crt` - OpenBao CA certificate chain
- `/etc/nginx/certs/keylime.crt` - Keylime SSL certificate
- `/etc/nginx/certs/keylime.key` - Keylime SSL private key
- `/etc/nginx/certs/keylime-ca-chain.crt` - Keylime CA certificate chain

---

## Architecture

```
Internet/Network
        │
        ▼
   Port 443 (HTTPS)
        │
        ▼
   Nginx Reverse Proxy
        │
        ├─► openbao.funlab.casa:443 ──────────► localhost:8200 (OpenBao)
        ├─► verifier.keylime.funlab.casa:443 ─► localhost:8881 (Keylime Verifier)
        ├─► registrar.keylime.funlab.casa:443 ► localhost:8891 (Keylime Registrar)
        └─► spire.funlab.casa:443 ────────────► Info page (SPIRE gRPC)
```

---

## Next Steps (Optional)

1. ✅ Update OpenBao configuration to advertise new URL
2. ✅ Start Keylime verifier service
3. ✅ Add nginx proxy for Keylime services with separate subdomains
4. ✅ Create systemd service units for Keylime verifier and registrar
5. ✅ Set up automated certificate renewal (weekly, Sundays at 3 AM)
6. ✅ Add monitoring for nginx service (every 5 minutes with auto-recovery)
7. ❌ Update Keylime agents to use new URLs - **Evaluated, Not Recommended**

See `NGINX-AUTOMATION.md` for automation documentation.
See `TASK-7-ANALYSIS.md` for why agent URL update is not recommended.

---

**Status:** Production ready! All services accessible via standard HTTPS port 443 with service-specific subdomains! 🎉
