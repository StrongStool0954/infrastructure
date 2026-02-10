# Tower of Omens - TPM Validation Results

**Date:** 2026-02-10
**Status:** ✅ VALIDATED - Ready for TPM Attestation Implementation

---

## Executive Summary

Successfully validated TPM 2.0 hardware and extracted Endorsement Key (EK) certificates from all three Tower of Omens hosts. All TPMs are from Infineon Technologies with valid EK certificates issued by trusted manufacturing CAs. The infrastructure is ready for hardware-backed SPIRE attestation.

---

## TPM Hardware Inventory

### spire.funlab.casa (10.10.2.62)
- **TPM Device:** /dev/tpm0, /dev/tpmrm0
- **Manufacturer:** Infineon (IFX)
- **TPM Version:** 2.0
- **EK Cert Serial:** 0x396f1744
- **EK Cert Valid:** 2017-09-29 to 2032-09-29 ✅
- **EK Cert Status:** VERIFIED against Infineon CA ✅

### auth.funlab.casa (10.10.2.70)
- **TPM Device:** /dev/tpm0, /dev/tpmrm0
- **Manufacturer:** Infineon (IFX)
- **TPM Version:** 2.0
- **EK Cert Serial:** 0x543fa7ac
- **EK Cert Valid:** 2017-09-29 to 2032-09-29 ✅
- **EK Cert Status:** VERIFIED against Infineon CA ✅

### ca.funlab.casa (10.10.2.60)
- **TPM Device:** /dev/tpm0, /dev/tpmrm0
- **Manufacturer:** Infineon (IFX)
- **TPM Version:** 2.0
- **EK Cert Serial:** 0x7cc20e22
- **EK Cert Valid:** 2017-09-29 to 2032-09-29 ✅
- **EK Cert Status:** VERIFIED against Infineon CA ✅

---

## Certificate Chain Validation

### Infineon TPM CA Hierarchy

```
Infineon OPTIGA(TM) RSA Root CA
   |
   ├─ Infineon OPTIGA(TM) RSA Manufacturing CA 034
   |     |
   |     ├─ spire TPM EK Certificate (Serial: 0x396f1744)
   |     ├─ auth TPM EK Certificate (Serial: 0x543fa7ac)
   |     └─ ca TPM EK Certificate (Serial: 0x7cc20e22)
```

### CA Certificate Details

**Root CA:**
- Subject: CN=Infineon OPTIGA(TM) RSA Root CA
- Valid: 2023-02-08 to 2043-02-08
- Downloaded from: http://pki.infineon.com/OptigaRsaRootCA/OptigaRsaRootCA.crt

**Manufacturing CA 034:**
- Subject: CN=Infineon OPTIGA(TM) RSA Manufacturing CA 034
- Issuer: Infineon OPTIGA(TM) RSA Root CA
- Valid: 2023-02-08 to 2043-02-08
- Downloaded from: http://pki.infineon.com/OptigaRsaMfrCA034/OptigaRsaMfrCA034.crt

**Verification Result:**
```bash
openssl verify -CAfile infineon-ca-chain.pem spire-ek-cert.pem
# Output: /tmp/spire-ek-cert.pem: OK ✅
```

---

## TPM Capabilities

### PCR Banks Available
All three hosts support:
- SHA-1 PCR bank
- **SHA-256 PCR bank** ✅ (recommended for SPIRE)

### PCRs Currently Used (LUKS Encryption)
- **PCR 0:** BIOS/UEFI firmware
- **PCR 2:** UEFI drivers
- **PCR 4:** Boot loader
- **PCR 7:** Secure Boot state

### Additional PCRs Available for SPIRE
- PCR 1: Platform configuration
- PCR 3: UEFI drivers and configuration
- PCR 5: GPT/Partition table
- PCR 8-15: Available for custom use

---

## Current vs. Target State

### Current State (Disk Encryption Only)
```
┌─────────────────────────────────────────┐
│          Tower of Omens Host            │
├─────────────────────────────────────────┤
│ TPM 2.0 (Infineon)                     │
│   └─ PCRs 0,2,4,7 → LUKS auto-unlock  │
│                                         │
│ LUKS Encrypted Disk                    │
│   └─ Auto-unlock via TPM               │
│                                         │
│ Services (no workload identity)        │
└─────────────────────────────────────────┘
```

### Target State (TPM Attestation + Disk Encryption)
```
┌─────────────────────────────────────────┐
│          Tower of Omens Host            │
├─────────────────────────────────────────┤
│ TPM 2.0 (Infineon)                     │
│   ├─ PCRs 0,2,4,7 → LUKS auto-unlock  │
│   └─ EK/AK → SPIRE attestation         │
│                                         │
│ SPIRE Agent                            │
│   ├─ Attested via TPM (hardware-backed)│
│   └─ Issues SVIDs to workloads         │
│                                         │
│ Services                               │
│   └─ Receive SPIFFE SVIDs              │
│       └─ mTLS service-to-service       │
└─────────────────────────────────────────┘
```

---

## Security Benefits of TPM Attestation

### Hardware Root of Trust
✅ **Node identity tied to TPM hardware**
- Each TPM has unique EK burned in at manufacturing
- Private keys never leave TPM
- Impossible to clone node identity

✅ **Cryptographic attestation**
- SPIRE Server validates TPM credentials
- Proof of platform state via PCR measurements
- Automatic detection of boot state changes

✅ **No manual credential distribution**
- No join tokens to manage
- No pre-shared keys
- Automatic workload identity issuance

### Defense in Depth
| Layer | Protection | Status |
|-------|-----------|--------|
| **Hardware** | TPM 2.0 | ✅ Validated |
| **Boot Integrity** | PCR measurements | ✅ Active (disk) |
| **Disk Encryption** | LUKS + TPM | ✅ Deployed |
| **Node Identity** | TPM attestation | ⏳ Ready to deploy |
| **Workload Identity** | SPIFFE SVIDs | ⏳ Ready to deploy |
| **Service Auth** | mTLS | ⏳ Ready to deploy |

---

## Implementation Readiness

### ✅ Prerequisites Met
- [x] All hosts have TPM 2.0 hardware
- [x] TPMs are from trusted manufacturer (Infineon)
- [x] EK certificates extracted and validated
- [x] CA certificate chain downloaded and verified
- [x] SPIRE Server deployed and running
- [x] PCR banks (SHA-256) available
- [x] tpm2-tools installed on all hosts

### 📋 Next Steps (Implementation)

1. **Configure SPIRE Server for TPM Attestation**
   - Add TPM NodeAttestor plugin
   - Configure CA certificate bundle
   - Test with one agent

2. **Deploy SPIRE Agents with TPM Plugin**
   - Install SPIRE Agent on auth.funlab.casa
   - Configure TPM attestation (EK mode)
   - Verify successful attestation

3. **Roll Out to All Agents**
   - Deploy to ca.funlab.casa
   - Validate all agents attested via TPM
   - Remove join_token fallback

4. **Register Workloads**
   - Register OpenBao on spire
   - Register step-ca on ca
   - Test SVID issuance

---

## TPM Attestation Configuration

### SPIRE Server Plugin Config

```hcl
NodeAttestor "tpm" {
  plugin_data {
    # Use EK certificate validation mode
    devid_mode = "ek_cert"

    # Path to Infineon CA certificate bundle
    ca_path = "/opt/spire/conf/infineon-ca-chain.pem"

    # Require valid EK certificates (no insecure mode)
    allow_insecure = false
  }
}
```

### SPIRE Agent Plugin Config

```hcl
NodeAttestor "tpm" {
  plugin_data {
    # TPM device path
    tpm_path = "/dev/tpmrm0"

    # Include PCR measurements in attestation
    pcr_bank = "sha256"
    pcr_selection = [0, 2, 4, 7]
  }
}
```

### Benefits of PCR-based Attestation
- **PCR 0:** Detects BIOS tampering
- **PCR 2:** Detects UEFI driver changes
- **PCR 4:** Detects bootloader modifications
- **PCR 7:** Detects Secure Boot changes

Same PCRs used for both disk encryption AND node attestation!

---

## Files and Locations

### Extracted Certificates (on hosts)
```
spire: /tmp/spire-ek-cert.pem
auth:  /tmp/auth-ek-cert.pem
ca:    /tmp/ca-ek-cert.pem
```

### CA Certificates (local)
```
/tmp/infineon-root-ca.pem       - Root CA certificate
/tmp/infineon-ca-034.pem        - Manufacturing CA certificate
/tmp/infineon-ca-chain.pem      - Full chain bundle
```

### Required for SPIRE Server
```
/opt/spire/conf/infineon-ca-chain.pem   - CA bundle for EK validation
```

---

## Testing Validation

### EK Certificate Extraction
```bash
# Extract from TPM NVRAM
sudo tpm2_nvread -C o 0x1c00002 -o /tmp/ek_cert.der

# Convert to PEM
openssl x509 -inform DER -in /tmp/ek_cert.der -out /tmp/ek_cert.pem

# View certificate details
openssl x509 -in /tmp/ek_cert.pem -text -noout
```

### Certificate Chain Validation
```bash
# Download CA certificates
curl -o infineon-ca-034.crt \
  http://pki.infineon.com/OptigaRsaMfrCA034/OptigaRsaMfrCA034.crt

curl -o infineon-root-ca.crt \
  http://pki.infineon.com/OptigaRsaRootCA/OptigaRsaRootCA.crt

# Create chain bundle
cat infineon-ca-034.pem infineon-root-ca.pem > infineon-ca-chain.pem

# Verify EK certificate
openssl verify -CAfile infineon-ca-chain.pem spire-ek-cert.pem
# Expected: spire-ek-cert.pem: OK
```

### TPM PCR Reading
```bash
# Read PCR values used for disk encryption
sudo tpm2_pcrread sha256:0,2,4,7

# Compare with baseline
diff <(sudo tpm2_pcrread sha256:0,2,4,7) ~/spire-pcr-baseline.txt
```

---

## Risk Assessment

### Low Risk ✅
- TPM hardware is proven and trusted
- EK certificates are manufacturer-issued
- CA chain is publicly verifiable
- Fallback to passphrase still available
- Can revert to join_token if needed

### Medium Risk ⚠️
- New technology for the team
- Requires understanding of TPM concepts
- PCR changes after BIOS updates require re-attestation

### Mitigations
- Extensive testing before production
- Keep join_token plugin as fallback initially
- Document PCR baseline values
- Maintain EK certificate backups

---

## Success Criteria

✅ **Phase 1 - Validation:** COMPLETE
- [x] TPM hardware identified
- [x] EK certificates extracted
- [x] CA chain validated
- [x] PCR banks verified

⏳ **Phase 2 - Server Configuration:** PENDING
- [ ] SPIRE Server updated with TPM plugin
- [ ] CA bundle deployed to /opt/spire/conf
- [ ] Configuration tested

⏳ **Phase 3 - Agent Deployment:** PENDING
- [ ] SPIRE Agent deployed on auth with TPM plugin
- [ ] Attestation successful
- [ ] SVID issuance verified

⏳ **Phase 4 - Production Rollout:** PENDING
- [ ] All agents attested via TPM
- [ ] Workloads registered
- [ ] join_token plugin removed
- [ ] Service-to-service mTLS working

---

## Documentation References

### Planning Docs
- [TPM Attestation Architecture Plan](tower-of-omens-tpm-attestation-plan.md)
- [SPIRE Server Configuration](spire-server-config.md)
- [Tower of Omens Deployment Summary](tower-of-omens-deployment-summary.md)

### TPM Configs
- [spire TPM Config (Disk)](spire-tpm-config.md)
- [auth TPM Config (Disk)](auth-tpm-config.md)
- [ca TPM Config (Disk)](ca-tpm-config.md)

### External Resources
- [SPIRE TPM Plugin Docs](https://github.com/spiffe/spire/blob/main/doc/plugin_server_nodeattestor_tpm.md)
- [Infineon TPM Resources](https://www.infineon.com/cms/en/product/security-smart-card-solutions/optiga-embedded-security-solutions/optiga-tpm/)
- [TPM 2.0 Spec](https://trustedcomputinggroup.org/resource/tpm-library-specification/)

---

## Conclusion

All three Tower of Omens hosts have validated TPM 2.0 hardware with legitimate Infineon EK certificates. The infrastructure is ready to implement hardware-backed workload identity using SPIRE TPM attestation.

**Recommendation:** Proceed with Phase 2 (SPIRE Server TPM configuration) and Phase 3 (deploy first SPIRE Agent with TPM attestation on auth.funlab.casa).

**Timeline:** 1-2 days for complete implementation and testing.

**Risk Level:** Low - Can fallback to join_token if issues arise.

---

**Status:** ✅ READY FOR IMPLEMENTATION
**Next Action:** Configure SPIRE Server with TPM NodeAttestor plugin
**Validated By:** Claude Code Assistant
**Date:** 2026-02-10
