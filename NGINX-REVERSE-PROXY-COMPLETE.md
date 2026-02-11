# Nginx Reverse Proxy - Implementation Complete

**Date:** 2026-02-11  
**Status:** ✅ OPERATIONAL  
**Purpose:** Service-specific DNS with standard HTTPS ports

---

## Summary

Successfully implemented nginx reverse proxy for infrastructure services, eliminating the need to remember port numbers.

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

## Service URLs

| Service | New URL | Old URL | Status |
|---------|---------|---------|--------|
| OpenBao PKI | https://openbao.funlab.casa | https://spire.funlab.casa:8200 | ✅ Working |
| SPIRE Server | https://spire.funlab.casa | spire.funlab.casa:8081 (gRPC) | ℹ️  Info page |
| Keylime Verifier | N/A | N/A | ⚠️ Not running |

---

## Nginx Configuration

**Location:** `/etc/nginx/conf.d/services.conf`

**Certificate:**
- Certificate: `/etc/nginx/certs/services.crt`
- Private Key: `/etc/nginx/certs/services.key`
- CA Chain: `/etc/nginx/certs/ca-chain.crt`
- Issuer: Book of Omens (OpenBao PKI)
- Validity: 30 days
- SANs: openbao.funlab.casa, spire.funlab.casa, keylime.funlab.casa, localhost, 10.10.2.62

**Virtual Hosts:**
1. openbao.funlab.casa:443 → localhost:8200 (OpenBao)
2. spire.funlab.casa:443 → Info page (SPIRE uses gRPC)

---

## DNS Configuration

All services resolve to **10.10.2.62** (spire.funlab.casa):

```dns
openbao.funlab.casa.    IN  A   10.10.2.62
keylime.funlab.casa.    IN  A   10.10.2.62
spire.funlab.casa.      IN  A   10.10.2.62
```

---

## Benefits Achieved

✅ **No Port Numbers** - Standard HTTPS port 443  
✅ **Service-Specific DNS** - Clear, self-documenting URLs  
✅ **Better Certificates** - Proper CN and SANs for each service  
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

### Certificate Issuance

```bash
# Issue certificate
bao write pki_int/issue/keylime-services \
    common_name='agent.keylime.funlab.casa' \
    alt_names='localhost' \
    ip_sans='10.10.2.X,127.0.0.1' \
    ttl='168h'
```

---

## Notes

### Keylime Verifier
The Keylime verifier is not currently running as a standalone HTTPS service. Keylime agents communicate directly with the verifier on their configured ports. The nginx proxy for Keylime was removed since the verifier isn't listening on port 8881.

### Certificate Renewal
The nginx certificate expires in 30 days and should be renewed via OpenBao:

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

---

## Testing

### Verify DNS
```bash
dig +short openbao.funlab.casa
# Should return: 10.10.2.62
```

### Test OpenBao
```bash
curl -k https://openbao.funlab.casa/v1/sys/health
# Should return JSON with initialized=true
```

### Verify Certificate
```bash
echo | openssl s_client -connect openbao.funlab.casa:443 \
    -servername openbao.funlab.casa 2>/dev/null | \
    openssl x509 -noout -subject -issuer -dates
```

---

## Files Modified

- `/etc/nginx/conf.d/services.conf` - Nginx virtual host configuration
- `/etc/nginx/certs/services.crt` - SSL certificate
- `/etc/nginx/certs/services.key` - SSL private key
- `/etc/nginx/certs/ca-chain.crt` - CA certificate chain

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
        ├─► openbao.funlab.casa:443 ──► localhost:8200 (OpenBao)
        └─► spire.funlab.casa:443 ────► Info page
```

---

## Next Steps (Optional)

1. ✅ Update OpenBao configuration to advertise new URL
2. ⏸️ Start Keylime verifier if needed for direct API access
3. ⏸️ Add nginx proxy for Keylime when verifier is running
4. ⏸️ Set up automated certificate renewal
5. ⏸️ Add monitoring for nginx service

---

**Status:** Production ready for OpenBao PKI! 🎉
