# Tower of Omens Infrastructure - Deployment Summary

**Deployment Date:** February 9-10, 2026
**Status:** ✅ COMPLETE
**Hosts Deployed:** spire.funlab.casa, auth.funlab.casa, ca.funlab.casa

---

## Overview

Successfully deployed three secure infrastructure hosts (Tower of Omens) with hardware-based TPM auto-unlock and 1Password SSH key management.

---

## Deployed Hosts

### 1. spire.funlab.casa
- **IP:** 10.10.2.62
- **Purpose:** SPIRE Server / OpenBao Server
- **TPM:** ✅ Working (auto-unlock)
- **SSH:** ✅ tygra@spire (1Password key)
- **LUKS Device:** /dev/nvme0n1p3
- **Config:** [spire-tpm-config.md](spire-tpm-config.md)

### 2. auth.funlab.casa
- **IP:** 10.10.2.70
- **Purpose:** Authentication/Authorization Server
- **TPM:** ✅ Working (auto-unlock)
- **SSH:** ✅ tygra@auth (1Password key)
- **LUKS Device:** /dev/nvme0n1p3
- **Config:** [auth-tpm-config.md](auth-tpm-config.md)

### 3. ca.funlab.casa
- **IP:** 10.10.2.60
- **Purpose:** Certificate Authority (step-ca)
- **TPM:** ✅ Working (auto-unlock)
- **SSH:** ✅ tygra@ca (1Password key)
- **LUKS Device:** /dev/nvme0n1p3
- **Config:** [ca-tpm-config.md](ca-tpm-config.md)

---

## Network Configuration

**Topology:**
```
Pica8 P3922 Switch (10.10.2.100)
   |
   ├─ Port 48 (te-1/1/48) - VLAN Trunk
   |     |
   |     └─ Secondary Switch
   |           ├─ spire.funlab.casa (10.10.2.62)
   |           ├─ auth.funlab.casa (10.10.2.70)
   |           └─ ca.funlab.casa (10.10.2.60)
```

**VLAN Configuration:**
- Port 48: Trunk mode
- Tagged VLANs: 100, 200, 300, 400, 500
- Native VLAN: 1 (10.10.2.x)
- All hosts on VLAN 1 (untagged)

**Documentation:** [network-redesign-pica8.md](network-redesign-pica8.md)

---

## Security Configuration

### TPM Auto-Unlock

All three hosts use TPM 2.0 with Clevis for automatic LUKS disk encryption unlock:

**Configuration:**
- **PCR Bank:** sha256
- **PCRs:** 0 (BIOS), 2 (UEFI drivers), 4 (Bootloader), 7 (Secure Boot)
- **Fallback:** Passphrase still works if TPM unsealing fails

**Security Features:**
- ✅ Detects BIOS tampering
- ✅ Detects bootloader changes
- ✅ Detects Secure Boot modifications
- ✅ Stolen drive protection
- ✅ Passphrase fallback

### SSH Access

**1Password SSH Agent:**
- Dedicated vault per host (Funlab.Casa.Spire, Funlab.Casa.Auth, Funlab.Casa.Ca)
- ED25519 keys stored in 1Password
- Passwordless SSH via `ssh spire`, `ssh auth`, `ssh ca`
- Keys exported to `~/.ssh/[host]_1password`

**SSH Config:** `~/.ssh/config`

**Admin User:** tygra (on all hosts)
- Member of sudo group
- Password-based sudo authentication
- Root SSH disabled for security

---

## Deployment Process

### Phase 1: Network Setup
- ✅ Configured Pica8 port 48 as VLAN trunk
- ✅ Connected secondary switch to port 48
- ✅ Verified network connectivity for all hosts

### Phase 2: SSH Access Setup
- ✅ Created tygra admin user on all hosts
- ✅ Exported SSH keys from 1Password
- ✅ Configured authorized_keys
- ✅ Updated SSH config
- ✅ Tested passwordless SSH login
- ✅ Disabled root SSH

### Phase 3: TPM Auto-Unlock
- ✅ Verified TPM 2.0 hardware on all hosts
- ✅ Installed tpm2-tools, clevis, clevis-luks
- ✅ Identified LUKS devices
- ✅ Bound LUKS keys to TPM (PCRs 0,2,4,7)
- ✅ Updated initramfs
- ✅ Saved PCR baselines
- ✅ Tested reboot - auto-unlock working!

---

## Testing & Verification

### SSH Access Test
```bash
ssh spire exit && echo "✅ spire"
ssh auth exit && echo "✅ auth"
ssh ca exit && echo "✅ ca"
```

**Result:** ✅ All hosts accessible

### TPM Auto-Unlock Test
```bash
# Rebooted all hosts
ssh spire uptime  # ✅ 1:29 uptime
ssh auth uptime   # ✅ 30 min uptime
ssh ca uptime     # ✅ 3 min uptime
```

**Result:** ✅ All hosts auto-unlock without password prompt

---

## Documentation Created

### Configuration Docs
- [spire-tpm-config.md](spire-tpm-config.md) - spire TPM configuration
- [auth-tpm-config.md](auth-tpm-config.md) - auth TPM configuration
- [ca-tpm-config.md](ca-tpm-config.md) - ca TPM configuration
- [spire-server-config.md](spire-server-config.md) - SPIRE Server configuration

### Process Docs
- [tower-of-omens-onboarding.md](tower-of-omens-onboarding.md) - Complete onboarding procedure
- [scripts/onboard-tower-host.sh](scripts/onboard-tower-host.sh) - Automation script
- [network-redesign-pica8.md](network-redesign-pica8.md) - Network configuration

---

## Maintenance

### Regular Tasks

**Monthly:**
- Verify PCR values haven't changed unexpectedly
- Check TPM auto-unlock still working
- Review SSH access logs

**After BIOS Updates:**
```bash
# On each host:
sudo clevis luks unbind -d /dev/nvme0n1p3 -s 1
sudo clevis luks bind -d /dev/nvme0n1p3 tpm2 '{"pcr_bank":"sha256","pcr_ids":"0,2,4,7"}'
sudo update-initramfs -u -k all
sudo reboot
```

**After Kernel Updates:**
```bash
# Usually no re-bind needed, just:
sudo update-initramfs -u -k all
```

---

## Services Deployed

### spire.funlab.casa
- ✅ **SPIRE Server 1.14.1:** Running and healthy
  - Trust Domain: funlab.casa
  - Listening on port 8081
  - Configuration: [spire-server-config.md](spire-server-config.md)

## Next Steps (Future)

### Planned Deployments
- [x] SPIRE Server on spire.funlab.casa ✅ **COMPLETE**
- [ ] OpenBao Server on spire.funlab.casa
- [ ] step-ca integration with SPIRE/OpenBao
- [ ] SPIRE Agents on other infrastructure hosts
- [ ] Workload identity for services

### Documentation References
- [SPIRE-OPENBAO-PREDEPLOYMENT.md](../projects/funlab-docs/docs/infrastructure/migrations/SPIRE-OPENBAO-PREDEPLOYMENT.md)
- [tower-of-omens-tpm2-auto-unlock.md](../projects/funlab-docs/docs/tower-of-omens-tpm2-auto-unlock.md)

---

## Troubleshooting

### SSH Key Not Working

**Symptoms:** Password prompt instead of key authentication

**Solutions:**
1. Check `.ssh` directory ownership: `ls -la /home/tygra/.ssh/`
   - Should be: `drwx------ tygra tygra`
2. Check authorized_keys: `ls -la /home/tygra/.ssh/authorized_keys`
   - Should be: `-rw------- tygra tygra`
3. Fix ownership: `sudo chown -R tygra:tygra /home/tygra/.ssh`

### TPM Auto-Unlock Fails

**Symptoms:** Password prompt at boot

**Solutions:**
1. Boot with passphrase (fallback still works)
2. Check PCR values: `sudo tpm2_pcrread sha256:0,2,4,7`
3. Compare to baseline in `~/[host]-pcr-baseline.txt`
4. If changed due to BIOS update, re-bind (see Maintenance section)

### sudo Not Working

**Symptoms:** "command not found" or "permission denied"

**Solutions:**
1. Install sudo: `apt install -y sudo` (as root)
2. Add user to sudo group: `usermod -aG sudo tygra` (as root)
3. Verify: `groups tygra` should show "sudo"

---

## Success Metrics

✅ **All hosts deployed:** 3/3 (spire, auth, ca)
✅ **SSH access working:** 3/3 hosts
✅ **TPM auto-unlock working:** 3/3 hosts
✅ **Documentation complete:** 100%
✅ **Security hardened:** Root SSH disabled, TPM-based encryption
✅ **Zero downtime incidents:** 0

**Total deployment time:** ~4 hours
**Reboot tests passed:** 3/3

---

## Team Knowledge

### Key Contacts
- **Primary Admin:** bullwinkle@snarf (via tygra user)
- **1Password Vaults:** Funlab.Casa.Spire, Funlab.Casa.Auth, Funlab.Casa.Ca

### Access Methods
```bash
# SSH to any host
ssh spire
ssh auth
ssh ca

# Become root (with tygra password)
sudo -i

# Check TPM status
sudo tpm2_pcrread

# Check LUKS binding
sudo cryptsetup luksDump /dev/nvme0n1p3 | grep clevis
```

---

**Deployment Status:** ✅ PRODUCTION READY
**Last Updated:** 2026-02-10
**Next Review:** Monthly PCR verification
