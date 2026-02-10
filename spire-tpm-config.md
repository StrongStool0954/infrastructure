# spire.funlab.casa - TPM Auto-Unlock Configuration

**Date Configured:** 2026-02-09
**Hostname:** spire.funlab.casa
**IP Address:** 10.10.2.62

## TPM Configuration

**TPM Device:** /dev/tpm0, /dev/tpmrm0
**TPM Version:** 2.0

## LUKS Configuration

**Device:** /dev/nvme0n1p3
**UUID:** 4df2edcd-0aa1-4eec-a71f-92599e9eb4f6
**Mapping:** nvme0n1p3_crypt

**Key Slots:**
- Slot 0: Passphrase (fallback)
- Slot 1: TPM2 binding (auto-unlock)

## Clevis Binding

**PCR Bank:** sha256
**PCR IDs:** 0,2,4,7
**Token:** 0 (clevis → keyslot 1)

## PCR Baseline Values

```
sha256:
  0: 0xD6D9977D8E94288B8576444B867B83C43FF6641F2F744E973DFB0DBC511B29E1
  2: 0x3D458CFE55CC03EA1F443F1562BEEC8DF51C75E14A9FCF9A7234A13F198E7969
  4: 0xBA30D30E7F367071B92485E5AA2777A8A996FCD121D3284D85C53FD5CA7002FB
  7: 0xE7BEF0B9AD0FF358A7CE64E5F9F2972730302B90CE55FFB34BE48770450C4475
```

## Status

✅ TPM auto-unlock: WORKING
✅ Boot test: PASSED
✅ SSH access: CONFIGURED (tygra@spire.funlab.casa)
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

- [Tower of Omens TPM Auto-Unlock Guide](../projects/funlab-docs/docs/tower-of-omens-tpm2-auto-unlock.md)
- [SPIRE + OpenBao Pre-Deployment](../projects/funlab-docs/docs/infrastructure/migrations/SPIRE-OPENBAO-PREDEPLOYMENT.md)
