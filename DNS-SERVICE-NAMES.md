# Service-Specific DNS Names - Implementation Guide

**Date:** 2026-02-10  
**Purpose:** Migrate from single hostname to service-specific DNS names  
**Status:** Planning / Ready to Implement

---

## Recommendation: YES - Use Service-Specific DNS Names ✅

### Benefits

1. **Service Portability** - Move services to different hosts transparently
2. **Better Certificates** - Each service gets proper CN and SANs
3. **Clear Architecture** - Self-documenting service URLs
4. **Load Balancing Ready** - Can add multiple backends later
5. **Standard Ports** - Can use 443 with reverse proxy

---

## Current State vs. Proposed

### Current Architecture
```
spire.funlab.casa (10.10.2.62)
├── https://spire.funlab.casa:8200  → OpenBao
├── spire.funlab.casa:8081          → SPIRE Server  
├── spire.funlab.casa:8881          → Keylime Verifier
└── spire.funlab.casa:8891          → Keylime Registrar
```

### Proposed Architecture
```
10.10.2.62 (Physical Host)
├── https://openbao.funlab.casa:8200  → OpenBao PKI
├── https://keylime.funlab.casa:8881  → Keylime Verifier
├── https://keylime.funlab.casa:8891  → Keylime Registrar
└── spire.funlab.casa:8081            → SPIRE Server
```

---

## Implementation Plan

### Phase 1: DNS Configuration

#### Option A: DNS Server (Recommended)
Add to your DNS server:
```dns
openbao.funlab.casa.    IN  A   10.10.2.62
keylime.funlab.casa.    IN  A   10.10.2.62
```

#### Option B: /etc/hosts (Quick for Lab)
Add to each host:
```bash
10.10.2.62  openbao.funlab.casa openbao
10.10.2.62  keylime.funlab.casa keylime
```

---

### Phase 2: Update OpenBao

#### 1. Issue New Certificate
```bash
export BAO_ADDR=https://spire.funlab.casa:8200
export BAO_SKIP_VERIFY=true
export BAO_TOKEN=s.eNHhmKyqvqW7Q93yVfswqFtx

# Issue with both old and new names (for transition)
bao write -format=json pki_int/issue/openbao-server \
    common_name='openbao.funlab.casa' \
    alt_names='spire.funlab.casa,openbao,spire,localhost' \
    ip_sans='10.10.2.62,127.0.0.1' \
    ttl='720h' > /tmp/openbao-cert.json
```

#### 2. Install Certificate
```bash
sudo jq -r '.data.certificate' /tmp/openbao-cert.json > /tmp/tls.crt
sudo jq -r '.data.private_key' /tmp/openbao-cert.json > /tmp/tls.key

sudo cp /opt/openbao/tls/tls.crt /opt/openbao/tls/tls.crt.backup
sudo cp /tmp/tls.crt /opt/openbao/tls/tls.crt
sudo cp /tmp/tls.key /opt/openbao/tls/tls.key
sudo chown openbao:openbao /opt/openbao/tls/tls.*
sudo chmod 640 /opt/openbao/tls/tls.key
```

#### 3. Update Configuration
```bash
sudo sed -i 's|spire.funlab.casa:8200|openbao.funlab.casa:8200|' /etc/openbao/openbao.hcl
sudo systemctl restart openbao
```

---

### Phase 3: Update Keylime Agents

Update all three hosts (auth, ca, spire):

```bash
# Update agent configuration
sudo sed -i 's|registrar_ip = "spire.funlab.casa"|registrar_ip = "keylime.funlab.casa"|' /etc/keylime/agent.conf
sudo sed -i 's|verifier_ip = "spire.funlab.casa"|verifier_ip = "keylime.funlab.casa"|' /etc/keylime/agent.conf

# Restart agent
sudo systemctl restart keylime_agent
```

---

### Phase 4: Verify Everything Works

```bash
# Test DNS
dig +short openbao.funlab.casa
dig +short keylime.funlab.casa

# Test OpenBao
curl -k https://openbao.funlab.casa:8200/v1/sys/health

# Test Keylime
curl -k https://keylime.funlab.casa:8881/version

# Verify Keylime agents
sudo keylime_tenant -c status -u <uuid>
```

---

## Service Name Mapping

| Service | DNS Name | IP | Port | Protocol |
|---------|----------|-----|------|----------|
| OpenBao PKI | openbao.funlab.casa | 10.10.2.62 | 8200 | HTTPS |
| Keylime Verifier | keylime.funlab.casa | 10.10.2.62 | 8881 | HTTPS |
| Keylime Registrar | keylime.funlab.casa | 10.10.2.62 | 8891 | TLS |
| SPIRE Server | spire.funlab.casa | 10.10.2.62 | 8081 | gRPC |

---

## Migration Strategy

### Low-Risk Approach (Recommended)

1. ✅ Add DNS entries (both old and new work)
2. ✅ Issue certificates with both names in SANs
3. ✅ Test new names alongside old
4. ✅ Update configurations one service at a time
5. ✅ Verify each service before moving to next
6. ⏸️ Keep old names for backward compatibility

### Certificate Transition Period
```bash
# Certificate SANs include both:
CN=openbao.funlab.casa
SAN: openbao.funlab.casa, spire.funlab.casa, localhost, 10.10.2.62

# Both URLs work during transition:
https://spire.funlab.casa:8200    ✅ (old, deprecated)
https://openbao.funlab.casa:8200  ✅ (new, preferred)
```

---

## Optional: Reverse Proxy for Standard Ports

Use nginx to provide standard HTTPS port 443:

```nginx
# OpenBao on standard port
server {
    listen 443 ssl http2;
    server_name openbao.funlab.casa;
    
    ssl_certificate /etc/nginx/certs/openbao.crt;
    ssl_certificate_key /etc/nginx/certs/openbao.key;
    
    location / {
        proxy_pass https://127.0.0.1:8200;
        proxy_set_header Host $host;
    }
}
```

Then access via:
```bash
https://openbao.funlab.casa  # No port needed!
```

---

## Rollback Plan

If issues occur:

```bash
# 1. Restore old OpenBao config
sudo cp /etc/openbao/openbao.hcl.backup /etc/openbao/openbao.hcl
sudo systemctl restart openbao

# 2. Restore Keylime agent configs
sudo sed -i 's|keylime.funlab.casa|spire.funlab.casa|g' /etc/keylime/agent.conf
sudo systemctl restart keylime_agent

# 3. Everything still works with old names
```

---

## Testing Checklist

- [ ] DNS resolves correctly for all service names
- [ ] OpenBao accessible via openbao.funlab.casa
- [ ] OpenBao certificate has correct SANs
- [ ] Keylime agents connect to keylime.funlab.casa
- [ ] All agents show PASS attestation status
- [ ] SPIRE agents can still attest
- [ ] Old URLs still work (during transition)

---

## Timeline Estimate

- **DNS Setup**: 15 minutes
- **OpenBao Certificate**: 30 minutes
- **Update Configurations**: 30 minutes
- **Testing**: 30 minutes
- **Total**: ~2 hours

---

## Conclusion

**Recommendation: Implement service-specific DNS names** ✅

This is a best practice that:
- Improves architecture clarity
- Enables future scaling
- Better aligns with industry standards
- Minimal risk with proper transition plan
- Can be done incrementally

The infrastructure is stable enough to support this change safely.
