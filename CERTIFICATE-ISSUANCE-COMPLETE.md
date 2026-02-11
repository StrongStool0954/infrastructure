# Certificate Issuance Complete - spire.funlab.casa

**Date:** 2026-02-10 23:38 EST
**Status:** ✅ COMPLETE
**Host:** spire.funlab.casa
**Purpose:** Replace temporary certificates with proper OpenBao PKI certificates

---

## Summary

Successfully issued and installed proper certificates for spire.funlab.casa Keylime agent, replacing the temporary certificates that were copied from ca.funlab.casa during initial migration.

---

## Certificate Details

### Issued Certificate

**Subject:** `CN=agent.keylime.funlab.casa`  
**Issuer:** `C=US, O=Funlab.Casa, OU=Tower of Omens, CN=Book of Omens`  
**Serial:** `05DD164E2C0D26039A8EFE1746F4BD4FED2BABB6`  
**Valid From:** Feb 11 04:37:28 2026 GMT  
**Valid Until:** Feb 18 04:37:58 2026 GMT (7 days)  
**Key Type:** EC P-256  

**Subject Alternative Names:**
- DNS: agent.keylime.funlab.casa
- DNS: localhost
- IP: 10.10.2.62
- IP: 127.0.0.1

**PKI Role:** `keylime-services`  
**TTL:** 168 hours (7 days)  
**Max TTL:** 168 hours (7 days)

---

## What Was Done

### 1. OpenBao Authentication ✅

Authenticated with OpenBao using root token:
```bash
export BAO_ADDR=https://spire.funlab.casa:8200
export BAO_SKIP_VERIFY=true
export BAO_TOKEN=s.eNHhmKyqvqW7Q93yVfswqFtx
```

### 2. Certificate Issuance ✅

Issued certificate via OpenBao PKI:
```bash
bao write -format=json pki_int/issue/keylime-services \
    common_name='agent.keylime.funlab.casa' \
    alt_names='localhost' \
    ip_sans='10.10.2.62,127.0.0.1' \
    ttl='168h'
```

### 3. Certificate Installation ✅

Installed certificates in `/etc/keylime/certs/`:
- `agent.crt` - EC P-256 certificate (644 permissions)
- `agent.key` - Private key (640 permissions, keylime:spire ownership)
- `ca-complete-chain.crt` - Full CA chain (644 permissions)

### 4. Service Restart ✅

Restarted both services:
- Keylime agent: ✅ Running, listening on https://0.0.0.0:9002
- SPIRE agent: ✅ Running, attestation working

### 5. Verification ✅

- Keylime agent UUID: `d884d34059618008b785b7cc83a50f671f5f3ff4b4522214d999a1a69222fb37`
- Attestation status: **PASS**
- Attestation count: 87+ (continuous attestation working)
- SPIRE SVID: `spiffe://funlab.casa/spire/agent/keylime/d884d34059618008b785b7cc83a50f671f5f3ff4b4522214d999a1a69222fb37`

---

## Before vs After

| Aspect | Before (Temporary) | After (Proper) |
|--------|-------------------|----------------|
| **Source** | Copied from ca.funlab.casa | Issued via OpenBao PKI |
| **Serial** | fbb7fe3f715d5e9272fda29e920255e1b6d260f5 | 05DD164E2C0D26039A8EFE1746F4BD4FED2BABB6 |
| **Valid Until** | Feb 12 02:12:04 (1 day) | Feb 18 04:37:58 (7 days) |
| **IP SANs** | 10.10.2.60 (ca's IP) | 10.10.2.62 (spire's IP) |
| **Ownership** | Proper certificates for ca | Proper certificates for spire |
| **Status** | Working but improper | ✅ Proper and working |

---

## Certificate Renewal Process

### Automated Renewal (Recommended)

Certificates should be renewed before expiration (7-day TTL). Renewal can be automated via:

1. **Cron job** - Run daily to check and renew
2. **Systemd timer** - Systemd-based renewal service
3. **cert-manager** - Kubernetes-style certificate management
4. **Custom script** - Using OpenBao API

### Manual Renewal

```bash
# Authenticate with OpenBao
export BAO_ADDR=https://spire.funlab.casa:8200
export BAO_SKIP_VERIFY=true
export BAO_TOKEN=<token>

# Issue new certificate
bao write -format=json pki_int/issue/keylime-services \
    common_name='agent.keylime.funlab.casa' \
    alt_names='localhost' \
    ip_sans='10.10.2.62,127.0.0.1' \
    ttl='168h' > /tmp/cert-output.json

# Extract and install
sudo jq -r '.data.certificate' /tmp/cert-output.json > /tmp/agent.crt
sudo jq -r '.data.private_key' /tmp/cert-output.json > /tmp/agent.key
sudo jq -r '.data.ca_chain[]' /tmp/cert-output.json > /tmp/ca-complete-chain.crt

sudo cp /tmp/agent.crt /etc/keylime/certs/agent.crt
sudo cp /tmp/agent.key /etc/keylime/certs/agent.key
sudo cp /tmp/ca-complete-chain.crt /etc/keylime/certs/ca-complete-chain.crt

# Set permissions
sudo chown keylime:keylime /etc/keylime/certs/agent.* /etc/keylime/certs/ca-complete-chain.crt
sudo chown keylime:spire /etc/keylime/certs/agent.key
sudo chmod 640 /etc/keylime/certs/agent.key
sudo chmod 644 /etc/keylime/certs/agent.crt /etc/keylime/certs/ca-complete-chain.crt

# Restart services
sudo systemctl restart keylime_agent
sudo systemctl restart spire-agent
```

---

## Infrastructure Status

All three hosts now have proper OpenBao PKI certificates:

| Host | Certificate Source | Status | Expires |
|------|-------------------|--------|---------|
| auth.funlab.casa | OpenBao PKI | ✅ Proper | Variable |
| ca.funlab.casa | OpenBao PKI | ✅ Proper | Variable |
| spire.funlab.casa | OpenBao PKI | ✅ Proper | Feb 18 2026 |

**All hosts:** Using HTTPS/mTLS for Keylime communication with certificates from Book of Omens PKI.

---

## Next Steps

1. **Set up automated certificate renewal** for all three hosts
2. **Monitor certificate expiration** (7-day TTL requires regular renewal)
3. **Consider longer TTL** if appropriate (would require role modification)
4. **Document renewal procedures** in operational runbooks

---

**Migration Complete:** All infrastructure hosts using proper PKI certificates! 🎉
