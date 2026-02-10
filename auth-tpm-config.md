# auth.funlab.casa - TPM Auto-Unlock Configuration

**Date Configured:** 2026-02-09
**Hostname:** auth.funlab.casa
**IP Address:** 10.10.2.70

## TPM Configuration

**TPM Device:** /dev/tpm0, /dev/tpmrm0
**TPM Version:** 2.0

## LUKS Configuration

**Device:** /dev/nvme0n1p3
**UUID:** 7a14ee4d-70e1-4e73-a71f-7e3926f0ad6b
**Mapping:** nvme0n1p3_crypt

**Key Slots:**
- Slot 0: Passphrase (fallback)
- Slot 1: TPM2 binding (auto-unlock)
- Slot 2: TPM2 binding (duplicate)

## Clevis Binding

**PCR Bank:** sha256
**PCR IDs:** 0,2,4,7
**Tokens:** 0, 1 (clevis)

## PCR Baseline Values

```
sha256:
  0: 0xD6D9977D8E94288B8576444B867B83C43FF6641F2F744E973DFB0DBC511B29E1
  2: 0x3D458CFE55CC03EA1F443F1562BEEC8DF51C75E14A9FCF9A7234A13F198E7969
  4: 0xBA30D30E7F367071B92485E5AA2777A8A996FCD121D3284D85C53FD5CA7002FB
  7: 0xA6871ACA73988E87BD2C927389F9C92EBEDB5A6CB8EB2D64B1F1EA921DA66074
```

## Status

✅ TPM auto-unlock: WORKING
✅ Boot test: PASSED
✅ SSH access: CONFIGURED (tygra@auth.funlab.casa)
✅ Fallback passphrase: AVAILABLE

## Maintenance Notes

### After BIOS/firmware updates (changes PCR 0):

```bash
# Boot with passphrase, then:
sudo clevis luks unbind -d /dev/nvme0n1p3 -s 1
sudo clevis luks bind -d /dev/nvme0n1p3 tpm2 '{"pcr_bank":"sha256","pcr_ids":"0,2,4,7"}'
sudo update-initramfs -u -k all
sudo reboot
```

### After kernel updates (usually no re-bind needed with PCRs 0,2,7):

```bash
sudo update-initramfs -u -k all
```

## Security Model

✅ **Protects against:**
- Stolen drive attacks
- Unauthorized boot attempts
- Drive reading on different system

✅ **Detects:**
- BIOS/UEFI tampering (PCR 0)
- Boot loader changes (PCR 4)
- Secure Boot state changes (PCR 7)

❌ **Does NOT protect against:**
- Physical access to running system
- Evil maid attacks (requires additional hardening)
- Cold boot attacks

## Related Documentation

- [Tower of Omens Onboarding Guide](tower-of-omens-onboarding.md)
- [spire.funlab.casa TPM Config](spire-tpm-config.md)
