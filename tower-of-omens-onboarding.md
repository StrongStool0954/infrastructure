# Tower of Omens Host Onboarding Procedure

**Purpose:** Standardized setup for auth.funlab.casa and ca.funlab.casa
**Date Created:** 2026-02-09
**Based on:** Successful spire.funlab.casa deployment

---

## Prerequisites

- [ ] Host is physically connected to secondary switch on Pica8 port 48
- [ ] Host has IP address on VLAN 1 (10.10.2.x)
- [ ] DNS record exists (auth.funlab.casa = 10.10.2.70, ca.funlab.casa = 10.10.2.60)
- [ ] SSH Key created in 1Password vault for this host
- [ ] Root password or initial access available

---

## Phase 1: Initial Access Setup

### Step 1.1: Verify Network Connectivity

From your workstation:

```bash
# Ping the host
ping auth.funlab.casa  # or ca.funlab.casa

# Check if SSH is accessible
ssh-keyscan auth.funlab.casa  # or ca.funlab.casa
```

### Step 1.2: Enable Root SSH Access (Temporary)

SSH to the host with initial credentials and run:

```bash
# Edit SSH config
sudo nano /etc/ssh/sshd_config

# Change this line:
PermitRootLogin yes

# Restart SSH
sudo systemctl restart sshd
```

### Step 1.3: Create tygra Admin User

As root on the target host:

```bash
# Create user with home directory
useradd -m -s /bin/bash tygra

# Set password
passwd tygra

# Add to sudo group
usermod -aG sudo tygra

# Create SSH directory
mkdir -p /home/tygra/.ssh
chmod 700 /home/tygra/.ssh
chown tygra:tygra /home/tygra/.ssh

# Verify user was created
id tygra
ls -la /home/tygra
```

---

## Phase 2: 1Password SSH Key Setup

### Step 2.1: Export SSH Keys from 1Password

On your **local workstation** (snarf):

```bash
cd ~/.ssh

# For auth.funlab.casa:
op read "op://Funlab.Casa.Auth/SSH Key - Funlab.Casa.Auth/private key" > auth_1password
op read "op://Funlab.Casa.Auth/SSH Key - Funlab.Casa.Auth/public key" > auth_1password.pub

# OR for ca.funlab.casa:
op read "op://Funlab.Casa.Ca/SSH Key - Funlab.casa.Ca/private key" > ca_1password
op read "op://Funlab.Casa.Ca/SSH Key - Funlab.casa.Ca/public key" > ca_1password.pub

# Set permissions (replace HOST with 'auth' or 'ca')
HOST=auth  # or ca
chmod 600 ${HOST}_1password
chmod 644 ${HOST}_1password.pub

# Verify key is valid
ssh-keygen -y -f ${HOST}_1password
```

**Note:** Using `op read` is more reliable than `op item get` for SSH keys.

### Step 2.2: Add Public Key to Target Host

**Method 1: Using SCP (Recommended)**

```bash
# Replace HOST with 'auth' or 'ca'
HOST=auth  # or ca

# Copy public key to /tmp on target host
scp -o PreferredAuthentications=password ~/.ssh/${HOST}_1password.pub root@${HOST}.funlab.casa:/tmp/

# SSH to target host
ssh -o PreferredAuthentications=password root@${HOST}.funlab.casa
```

Once logged in as root on the target host:

```bash
# Install the key
cat /tmp/auth_1password.pub >> /home/tygra/.ssh/authorized_keys  # or ca_1password.pub
chmod 600 /home/tygra/.ssh/authorized_keys
chown tygra:tygra /home/tygra/.ssh/authorized_keys
rm /tmp/auth_1password.pub  # or ca_1password.pub
exit
```

**Method 2: Single Command (if your terminal doesn't break lines)**

```bash
HOST=auth  # or ca
cat ~/.ssh/${HOST}_1password.pub | ssh -o PreferredAuthentications=password root@${HOST}.funlab.casa "cat >> /home/tygra/.ssh/authorized_keys && chmod 600 /home/tygra/.ssh/authorized_keys && chown tygra:tygra /home/tygra/.ssh/authorized_keys"
```

**Important:** Make sure the command is on a single line. Terminal line wrapping can break it.

### Step 2.3: Update SSH Config

On your **local workstation**, the config should already include entries from previous setup.

Verify in `~/.ssh/config`:

```
Host auth auth.funlab.casa
    HostName auth.funlab.casa
    User tygra
    IdentityFile ~/.ssh/auth_1password
    IdentitiesOnly yes

Host ca ca.funlab.casa
    HostName ca.funlab.casa
    User tygra
    IdentityFile ~/.ssh/ca_1password
    IdentitiesOnly yes
```

### Step 2.4: Test SSH Connection

```bash
# Test connection (replace with correct host)
ssh auth exit && echo "✅ SSH working!"
ssh ca exit && echo "✅ SSH working!"
```

### Step 2.5: Disable Root SSH (Security)

Once tygra SSH works, disable root SSH:

```bash
# On target host as root:
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd
```

---

## Phase 3: Install Prerequisites

### Step 3.1: Install sudo (if needed)

```bash
ssh HOST  # Replace with auth or ca

# Check if sudo exists
which sudo || sudo apt update && sudo apt install -y sudo
```

### Step 3.2: Remove 1Password Repository (if present)

```bash
# If 1Password repo causes issues:
sudo rm -f /etc/apt/sources.list.d/1password.list
sudo apt update
```

---

## Phase 4: TPM/LUKS Auto-Unlock Setup

### Step 4.1: Verify TPM Hardware

```bash
# Check TPM device exists
ls -l /dev/tpm*

# Should see: /dev/tpm0 and /dev/tpmrm0
```

### Step 4.2: Install TPM and Clevis Packages

```bash
sudo apt update
sudo apt install -y tpm2-tools clevis clevis-tpm2 clevis-luks clevis-initramfs cryptsetup-bin
```

### Step 4.3: Verify TPM Functionality

```bash
sudo tpm2_pcrread

# Should display PCR values in sha1 and sha256
```

### Step 4.4: Identify LUKS Device

```bash
# List block devices
lsblk

# Find LUKS devices
sudo blkid | grep crypto_LUKS
```

**Document the device path** (e.g., `/dev/sda2` or `/dev/nvme0n1p3`)

### Step 4.5: Bind LUKS to TPM

```bash
# Replace DEVICE with your actual LUKS device path
DEVICE=/dev/sda2  # or /dev/nvme0n1p3, etc.

# Bind to TPM (you'll be prompted for LUKS passphrase)
sudo clevis luks bind -d $DEVICE tpm2 '{"pcr_bank":"sha256","pcr_ids":"0,2,4,7"}'
```

**Enter the LUKS passphrase when prompted.**

### Step 4.6: Verify Binding

```bash
# Check LUKS dump
sudo cryptsetup luksDump $DEVICE | grep -E "Keyslots|Tokens|clevis"

# Should show:
# - Keyslot 0: Original passphrase
# - Keyslot 1: TPM binding
# - Token 0: clevis
```

### Step 4.7: Update Initramfs

```bash
sudo update-initramfs -u -k all
```

### Step 4.8: Save PCR Baseline

```bash
# Save current PCR values for reference
sudo tpm2_pcrread sha256:0,2,4,7 > ~/pcr-baseline.txt
cat ~/pcr-baseline.txt
```

### Step 4.9: Test Auto-Unlock

```bash
# Reboot the system
sudo reboot
```

**Expected behavior:**
- System boots without password prompt
- LUKS unlocks automatically via TPM
- System reaches login prompt

**If it prompts for password:**
- Enter LUKS passphrase (fallback still works)
- Log in and troubleshoot (check logs: `journalctl -b 0 | grep clevis`)

---

## Phase 5: Documentation

### Step 5.1: Create Host Configuration File

```bash
# On local workstation, create config file:
cat > ~/infrastructure/HOST-tpm-config.md << 'EOF'
# HOST.funlab.casa - TPM Auto-Unlock Configuration

**Date Configured:** $(date)
**Hostname:** HOST.funlab.casa
**IP Address:** 10.10.2.XX

## TPM Configuration
- Device: /dev/tpm0, /dev/tpmrm0
- Version: 2.0

## LUKS Configuration
- Device: /dev/DEVICE
- UUID: (from blkid)
- Keyslot 0: Passphrase (fallback)
- Keyslot 1: TPM2 binding

## PCR Configuration
- Bank: sha256
- PCRs: 0,2,4,7

## Status
✅ TPM auto-unlock: WORKING
✅ SSH access: CONFIGURED (tygra@HOST.funlab.casa)
EOF
```

### Step 5.2: Update Main Documentation

Add entry to `~/infrastructure/tower-of-omens-hosts.md` or similar.

---

## Phase 6: Verification Checklist

After completing all steps, verify:

- [ ] Host boots without password prompt (TPM auto-unlock working)
- [ ] SSH access via tygra user works (passwordless with 1Password key)
- [ ] Root SSH disabled (security hardening)
- [ ] sudo works for tygra user
- [ ] PCR baseline documented
- [ ] LUKS passphrase fallback still works (tested once)
- [ ] Configuration documented in infrastructure repo

---

## Troubleshooting

### "chown: invalid user: 'tygra:tygra'" Error

**Cause:** The tygra user wasn't created on the target host.

**Solution:**
```bash
# On target host as root:
useradd -m -s /bin/bash tygra
passwd tygra
usermod -aG sudo tygra
mkdir -p /home/tygra/.ssh
chmod 700 /home/tygra/.ssh
chown tygra:tygra /home/tygra/.ssh
```

**Prevention:** Always complete Phase 1 (create tygra user) BEFORE Phase 2 (add SSH keys).

### SSH Key "Invalid Format" Error

```bash
# Remove leading newline
sed -i '1{/^$/d}' ~/.ssh/HOST_1password

# Test key validity
ssh-keygen -y -f ~/.ssh/HOST_1password
```

### TPM Auto-Unlock Fails After BIOS Update

PCR 0 changed due to firmware update. Re-bind:

```bash
# Boot with passphrase, then:
sudo clevis luks unbind -d /dev/DEVICE -s 1
sudo clevis luks bind -d /dev/DEVICE tpm2 '{"pcr_bank":"sha256","pcr_ids":"0,2,4,7"}'
sudo update-initramfs -u -k all
sudo reboot
```

### "sudo: command not found"

```bash
# Become root via su
su - root

# Install sudo
apt update && apt install -y sudo

# Add tygra to sudoers
usermod -aG sudo tygra
```

---

## Quick Reference Commands

```bash
# Test SSH
ssh HOST exit

# Check TPM
ssh HOST "sudo tpm2_pcrread"

# Check LUKS binding
ssh HOST "sudo cryptsetup luksDump /dev/DEVICE | grep -A 5 Tokens"

# Reboot for TPM test
ssh HOST "sudo reboot"

# Check uptime after reboot
ssh HOST "uptime"
```

---

## Rollback Plan

If TPM setup fails and you need to remove it:

```bash
# List key slots
sudo cryptsetup luksDump /dev/DEVICE

# Remove Clevis binding (keyslot 1)
sudo clevis luks unbind -d /dev/DEVICE -s 1

# Or directly kill the key slot
sudo cryptsetup luksKillSlot /dev/DEVICE 1

# Update initramfs
sudo update-initramfs -u -k all
```

Original passphrase in slot 0 is never touched and always works.

---

## Host-Specific Information

### auth.funlab.casa
- **IP:** 10.10.2.70
- **1Password Vault:** Funlab.Casa.Auth
- **SSH Key ID:** asz276u27akbcy4ravbqvn3hau
- **Purpose:** Authentication/authorization server

### ca.funlab.casa
- **IP:** 10.10.2.60
- **1Password Vault:** Funlab.Casa.Ca
- **SSH Key ID:** 75k2dsbok2iqqogmdrbp4dadza
- **Purpose:** Certificate authority (step-ca)

---

**Document Status:** Ready for deployment
**Last Updated:** 2026-02-09
**Tested On:** spire.funlab.casa (successful)
**Next Hosts:** auth.funlab.casa, ca.funlab.casa
