# step-ca Deployment - Complete! ✅

**Date:** 2026-02-10  
**Host:** ca.funlab.casa (10.10.2.60)  
**Status:** ✅ OPERATIONAL

---

## Certificate Hierarchy

```
Eye of Thundera (Root CA)
├── Type: RSA 4096-bit
├── Validity: 2026-02-10 to 2126-01-17 (100 years)
├── Storage: 1Password (Funlab.Casa.Ca vault)
└── Self-signed

    └── Sword of Omens (Intermediate CA)
        ├── Type: RSA 2048-bit
        ├── Validity: 2026-02-10 to 2036-02-08 (10 years)
        ├── Storage: File-based (/etc/step-ca/secrets/intermediate_ca_key)
        ├── Backup: 1Password (Funlab.Casa.Ca vault)
        └── Signed by: Eye of Thundera
```

---

## What's Deployed

### step-ca Service
- **Version:** Smallstep CA/0000000-dev (custom build)
- **Status:** Active and running
- **Listening on:** 443 (HTTPS)
- **URL:** https://ca.funlab.casa:443
- **Root Fingerprint:** f8a287ad4d1bf1fba7f289b6fbd43ea93ea5a695239f7a93c2ad96e03d2f4e50

### Provisioners
- **tower-of-omens** (JWK type) - For Tower of Omens infrastructure

---

## Security Configuration

### File Permissions
- **Root CA cert:** `/etc/step-ca/certs/root_ca.crt` (owned by step:step, mode 644)
- **Intermediate CA cert:** `/etc/step-ca/certs/intermediate_ca.crt` (owned by step:step, mode 644)
- **Intermediate CA key:** `/etc/step-ca/secrets/intermediate_ca_key` (owned by step:step, mode 600)

### 1Password Backup (Funlab.Casa.Ca vault)
- ✅ Eye of Thundera - Root CA Certificate
- ✅ Eye of Thundera - Root CA Private Key
- ✅ Sword of Omens - Intermediate CA Certificate (Current)
- ✅ Sword of Omens - Intermediate CA Private Key
- ✅ YubiKey NEO - ca.funlab.casa (SN: 5497305) - PIN, PUK, Management Key

### Access Control
- **polkit rules:** step user authorized for PC/SC access (`/etc/polkit-1/rules.d/10-pcscd-step-ca.rules`)
- **Service user:** step (uid=999, gid=989)
- **Systemd service:** step-ca.service (enabled, active)

---

## YubiKey Status

**Note:** YubiKey NEO (firmware 3.4.9) had limitations with private key storage. After troubleshooting, we switched to file-based key storage for reliability.

- **YubiKey Model:** YubiKey NEO (SN: 5497305)
- **Firmware:** 3.4.9
- **PIN:** S1iNIv2g (stored in 1Password)
- **PUK:** XZSwlSSR (stored in 1Password)
- **Management Key:** de0836a40794ff047e9dc1658a98a3471af2b63a309ce111 (stored in 1Password)
- **Slot 9c:** Currently has certificate but key storage had issues
- **Status:** Available for future use or other purposes

---

## Verification

### Health Check
```bash
curl -k https://ca.funlab.casa:443/health
# Returns: {"status":"ok"}
```

### Root CA Download
```bash
curl -k https://ca.funlab.casa:443/roots.pem
# Returns: Eye of Thundera root CA certificate
```

### TLS Certificate Chain
```
Client → ca.funlab.casa:443
    └── TLS Cert: CN=Step Online CA
        └── Issued by: CN=Sword of Omens (Intermediate CA)
            └── Issued by: CN=Eye of Thundera (Root CA)
```

---

## Next Steps

### Immediate
- [ ] Configure DNS to point ca.funlab.casa to 10.10.2.60
- [ ] Add provisioners for specific services
- [ ] Configure ACME provisioner for automated certificate issuance
- [ ] Set up certificate renewal automation

### Integration
- [ ] Deploy SPIRE Agents using join_token
- [ ] Migrate to TPM DevID attestation (Sprint 2)
- [ ] Configure OpenBao to use step-ca for secrets
- [ ] Integrate with Authentik for service certificates

### Monitoring
- [ ] Set up Prometheus metrics for step-ca
- [ ] Configure Grafana dashboards
- [ ] Set up alerts for certificate expiration

---

## Troubleshooting

### step-ca Not Starting
```bash
# Check logs
sudo journalctl -u step-ca -n 50 --no-pager

# Check config
sudo jq '.' /etc/step-ca/config/ca.json

# Verify files
ls -la /etc/step-ca/certs/ /etc/step-ca/secrets/
```

### PIN Issues (if using YubiKey)
```bash
# Check PIN tries remaining
sudo ykman piv info | grep "PIN tries"

# Unblock PIN with PUK
sudo yubico-piv-tool -a unblock-pin -P XZSwlSSR -N S1iNIv2g
```

### Certificate Renewal
Intermediate CA expires in 10 years (2036-02-08). To renew:
1. Generate new CSR from current key
2. Sign with Root CA (from 1Password)
3. Import new certificate
4. Restart step-ca

---

## Documentation References

- [NEXT-STEPS.md](NEXT-STEPS.md) - Overall Tower of Omens deployment plan
- [tower-of-omens-deployment-summary.md](tower-of-omens-deployment-summary.md) - Infrastructure overview
- [ca-tpm-config.md](ca-tpm-config.md) - ca.funlab.casa TPM configuration

---

**Deployment Status:** ✅ COMPLETE  
**Last Updated:** 2026-02-10 15:11 EST  
**Deployed By:** Claude Sonnet 4.5 + tygra@bullwinkle
