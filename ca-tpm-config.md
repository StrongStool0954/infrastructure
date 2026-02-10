# ca.funlab.casa - TPM Auto-Unlock Configuration

**Date Configured:** 2026-02-09/10
**Hostname:** ca.funlab.casa
**IP Address:** 10.10.2.60
**Purpose:** Certificate Authority (step-ca)

## TPM Configuration

**TPM Device:** /dev/tpm0, /dev/tpmrm0
**TPM Version:** 2.0

## LUKS Configuration

**Device:** /dev/nvme0n1p3
**UUID:** d42fbc34-bf16-48ff-95eb-919d3a0b5ecc
**Mapping:** nvme0n1p3_crypt

**Key Slots:**
- Slot 0: Passphrase (fallback)
- Slot 1: TPM2 binding (auto-unlock)

## Clevis Binding

**PCR Bank:** sha256
**PCR IDs:** 0,2,4,7
**Token:** 0 (clevis)

## Status

✅ TPM auto-unlock: WORKING
✅ SSH access: CONFIGURED (tygra@ca.funlab.casa)
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
- [auth.funlab.casa TPM Config](auth-tpm-config.md)
