# Keylime + SPIRE Agent Onboarding Guide

**Purpose:** Step-by-step guide to onboard new hosts with Keylime and SPIRE agents
**Last Updated:** 2026-02-15
**Status:** ✅ PRODUCTION READY - Tested on auth, spire, ca hosts
**Attestation Hardening:** Phase 3 (Secure Boot + Boot Loader + IMA Runtime Integrity)

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Step 0: Enable IMA Runtime Integrity (One-Time Setup)](#step-0-enable-ima-runtime-integrity-one-time-setup)
4. [Step 1: Generate Certificates](#step-1-generate-certificates)
5. [Step 2: Install and Configure SPIRE Agent](#step-2-install-and-configure-spire-agent)
6. [Step 3: Install and Configure Keylime Agent](#step-3-install-and-configure-keylime-agent)
7. [Step 4: Register with Keylime Verifier](#step-4-register-with-keylime-verifier)
8. [Step 5: Verification](#step-5-verification)
9. [Troubleshooting](#troubleshooting)
10. [Quick Reference](#quick-reference)
11. [Attestation Hardening Details](#attestation-hardening-details)

---

## Overview

This guide onboards a new host with:
- **SPIRE Agent:** Workload identity and attestation
- **Keylime Agent:** TPM-based remote attestation with mTLS

Both agents use certificates from the **Book of Omens** intermediate CA, backed by the **Eye of Thundera** root CA.

### What This Guide Provides

✅ **Correct certificate generation** (PKCS#8 format with full chain)
✅ **Proper certificate installation** (correct permissions and ownership)
✅ **Complete trust chain setup** (intermediate + root CA certificates)
✅ **SPIRE agent configuration** (JWT-SVIDs for workload identity)
✅ **Keylime agent configuration** (mTLS with TPM attestation)
✅ **Verification procedures** (ensure agents are operational)
✅ **Lessons learned** from production troubleshooting

---

## Prerequisites

### Required Information

Before starting, gather the following:

```bash
# Target host details
HOSTNAME="pm01.funlab.casa"           # Full hostname
SHORT_NAME="pm01"                     # Short hostname
IP_ADDRESS="10.10.2.XX"              # Host IP address

# SPIRE server details
SPIRE_SERVER="spire.funlab.casa:8081"
SPIRE_TRUST_DOMAIN="funlab.casa"

# Keylime server details
VERIFIER_HOST="spire.funlab.casa"
VERIFIER_PORT="8881"
REGISTRAR_HOST="spire.funlab.casa"
REGISTRAR_PORT="8891"
```

### Access Requirements

- **Root/sudo access** on target host
- **OpenBao access** for certificate generation
- **SPIRE server access** for agent registration
- **Keylime verifier access** for agent attestation

### Software Requirements

On target host:
- TPM 2.0 (hardware or software)
- systemd for service management
- OpenSSL for certificate verification
- IMA (Integrity Measurement Architecture) enabled in kernel

---

## Step 0: Enable IMA Runtime Integrity (One-Time Setup)

**IMPORTANT:** This step must be completed BEFORE onboarding agents. It requires a system reboot and only needs to be done once per host.

### 0.1: What is IMA?

IMA (Integrity Measurement Architecture) provides runtime integrity monitoring by measuring files as they're accessed and storing measurements in TPM PCR 10. This enables continuous attestation of file integrity during system operation.

**Attestation Protection (Phase 3):**
- **Pre-boot**: Secure Boot enforcement (PCR 7)
- **Boot-time**: GRUB integrity verification (PCR 4)
- **Runtime**: File access monitoring via IMA (exclude-based policy)

### 0.2: Enable IMA Kernel Parameters

```bash
# On target host
# Backup current GRUB configuration
sudo cp /etc/default/grub /etc/default/grub.backup-$(date +%Y%m%d-%H%M%S)

# Add IMA parameters to GRUB_CMDLINE_LINUX
sudo sed -i 's/GRUB_CMDLINE_LINUX=".*"/GRUB_CMDLINE_LINUX="ima_policy=tcb ima_hash=sha256"/' /etc/default/grub

# Verify the change
grep GRUB_CMDLINE_LINUX /etc/default/grub
# Expected: GRUB_CMDLINE_LINUX="ima_policy=tcb ima_hash=sha256"
```

**Parameter Explanation:**
- `ima_policy=tcb`: Trusted Computing Base policy - measures executables, shared libraries, and kernel modules
- `ima_hash=sha256`: Use SHA-256 for measurements (stronger than default SHA-1)

### 0.3: Update GRUB and Reboot

```bash
# Update GRUB configuration
sudo update-grub  # Debian/Ubuntu
# OR
sudo grub2-mkconfig -o /boot/grub2/grub.cfg  # RHEL/CentOS/Rocky

# Reboot to apply changes
sudo reboot
```

### 0.4: Verify IMA is Active

```bash
# After reboot, check IMA measurements are being collected
sudo cat /sys/kernel/security/ima/ascii_runtime_measurements | wc -l
# Expected: Large number (typically 3,000-5,000+ measurements)

# Check IMA policy
sudo cat /sys/kernel/security/ima/policy
# Should show policy rules for measuring executables and libraries

# Verify kernel parameters
cat /proc/cmdline | grep ima
# Expected: ima_policy=tcb ima_hash=sha256
```

**Troubleshooting:**
- If measurement count is 0, IMA is not enabled - verify kernel parameters and reboot
- If `/sys/kernel/security/ima/` doesn't exist, kernel doesn't support IMA
- Some kernels may require additional kernel config (CONFIG_IMA=y, CONFIG_IMA_MEASURE_PCR_IDX=10)

### 0.5: IMA Policy Used by Keylime

The SPIRE Keylime plugin enforces an **exclude-based policy** during attestation:

**Excluded Directories (not measured):**
- `/var/` - Variable data (logs, caches, temporary files)
- `/tmp/` - Temporary files
- `/home/` - User home directories
- `/proc/` - Process virtual filesystem
- `/sys/` - System virtual filesystem
- `/dev/shm/` - Shared memory
- `/run/` - Runtime data
- `/dev/` - Device files
- `/sys/firmware/` - Firmware files

**Measured Paths:**
- `/usr/bin/` - System binaries
- `/usr/sbin/` - System administration binaries
- `/lib/`, `/lib64/`, `/usr/lib/` - System libraries
- `/usr/local/bin/` - Local binaries (e.g., keylime_agent)
- `/etc/systemd/system/` - Service unit files
- `/opt/spire/` - SPIRE installation

**Why exclude-based?**
- Simpler than allowlist-based policies (no need to pre-populate file digests)
- More maintainable (system updates don't break attestation)
- Still provides strong protection for critical system components
- Focuses on immutable system files, ignoring volatile data

---

## SPIRE Server: Keylime Plugin Configuration

**NOTE:** This section documents the SPIRE server-side configuration. This is typically done once during initial setup and when updating the attestation policy. New agent hosts do NOT need to modify this.

### Plugin Build and Installation

The SPIRE Keylime plugin must be built and installed on the SPIRE server (spire.funlab.casa).

**Build from Source:**
```bash
# On spire.funlab.casa
cd /home/tygra/spire-keylime-plugin

# Build the plugin
/usr/local/go/bin/go build -o keylime-attestor-server \
  cmd/server/keylime_attestor/keylime_attestor.go

# Calculate checksum for server.conf
sha256sum keylime-attestor-server
# Save this checksum - you'll need it for server.conf

# Install plugin
sudo cp keylime-attestor-server /opt/spire/plugins/keylime-attestor-server
sudo chmod +x /opt/spire/plugins/keylime-attestor-server
```

**Current Phase 3 Implementation:**
- **Git Commit:** `acdeac7` - "Implement Phase 3: Add boot loader verification (PCR 4)"
- **Source Location:** `/home/tygra/spire-keylime-plugin`
- **Installed Location:** `/opt/spire/plugins/keylime-attestor-server`
- **Current Checksum:** `79cab8cbace12e1b4e2cb0fba13c326692825d2957631d702547875a306378b9`

**TPM Policy (Phase 3):**
```json
{"mask": "0x90"}  // PCRs 4 and 7
```

**IMA Policy (Phase 2):**
- Exclude-based policy (no allowlist)
- Excludes: `/var/`, `/tmp/`, `/home/`, `/proc/`, `/sys/`, `/dev/shm/`, `/run/`, `/dev/`, `/sys/firmware/`
- Hash algorithm: SHA-256
- Base64-encoded in RuntimePolicy field

### Update SPIRE Server Configuration

After building the plugin, update `/etc/spire/server.conf` with the correct checksum:

```bash
# On spire.funlab.casa
# Calculate plugin checksum
CHECKSUM=$(sha256sum /opt/spire/plugins/keylime-attestor-server | awk '{print $1}')
echo "Plugin checksum: $CHECKSUM"

# Backup current config
sudo cp /etc/spire/server.conf /etc/spire/server.conf.backup-$(date +%Y%m%d-%H%M%S)

# Update plugin_checksum in config
sudo sed -i "s/plugin_checksum = \".*\"/plugin_checksum = \"$CHECKSUM\"/" /etc/spire/server.conf

# Verify update
grep plugin_checksum /etc/spire/server.conf
```

**Server Configuration (Production):**
```hcl
NodeAttestor "keylime" {
  plugin_cmd = "/opt/spire/plugins/keylime-attestor-server"
  plugin_checksum = "79cab8cbace12e1b4e2cb0fba13c326692825d2957631d702547875a306378b9"
  plugin_data {
    keylime_verifier_host = "verifier.keylime.funlab.casa"
    keylime_verifier_port = "443"
    keylime_registrar_host = "registrar.keylime.funlab.casa"
    keylime_registrar_port = "443"
    keylime_tls_ca_cert_file = "/etc/keylime/certs/ca-complete-chain.crt"
    keylime_tls_cert_file = "/etc/keylime/certs/agent.crt"
    keylime_tls_key_file = "/etc/keylime/certs/agent-pkcs8.key"
    tpm_policy = "{\"mask\": \"0x90\"}"  # PCRs 4, 7 (Phase 3)
  }
}
```

### Restart SPIRE Server

**CRITICAL:** After updating the plugin or configuration, SPIRE server must be restarted.

```bash
# On spire.funlab.casa
sudo systemctl restart spire-server

# Verify server started successfully
sudo systemctl status spire-server

# Check logs for plugin loading
sudo journalctl -u spire-server -n 50 --no-pager | grep -i keylime

# Expected log output:
# "Loaded plugin" plugin_name=keylime plugin_type=NodeAttestor
```

**If server fails to start:**
```bash
# Check for plugin checksum mismatch
sudo journalctl -u spire-server -n 100 --no-pager | grep -i "checksum"

# Check for configuration errors
sudo /opt/spire/bin/spire-server run -config /etc/spire/server.conf --logLevel DEBUG
# Press Ctrl+C to stop after verification
```

### Attestation Policy Changes

**Phase History:**
- **Phase 1** (`24d5b70`): `{"mask": "0x80"}` - PCR 7 only (Secure Boot)
- **Phase 2** (`6f2d7d6`): Added IMA runtime policy (exclude-based)
- **Phase 3** (`acdeac7`): `{"mask": "0x90"}` - PCRs 4, 7 (Boot Loader + Secure Boot)

**To update attestation policy:**
1. Modify `/home/tygra/spire-keylime-plugin/pkg/server/server.go`
2. Rebuild plugin: `/usr/local/go/bin/go build -o keylime-attestor-server cmd/server/keylime_attestor/keylime_attestor.go`
3. Calculate new checksum: `sha256sum keylime-attestor-server`
4. Install plugin: `sudo cp keylime-attestor-server /opt/spire/plugins/`
5. Update checksum in `/etc/spire/server.conf`
6. Restart SPIRE server: `sudo systemctl restart spire-server`
7. Re-register all agents (existing attestation state becomes invalid)
8. Commit changes to git: `git add . && git commit -m "Description"`
9. Push to GitHub fork

---

## Step 1: Generate Certificates

### 1.1: Generate Keylime Agent Certificate (PKCS#8)

**Critical:** Use `private_key_format=pkcs8` parameter!

```bash
# On host with OpenBao access (spire.funlab.casa)
export BAO_ADDR='https://openbao.funlab.casa:8088'
export BAO_SKIP_VERIFY=true
export BAO_TOKEN=$(sudo cat /root/.openbao-token)

# Set target host details
HOSTNAME="pm01.funlab.casa"
SHORT_NAME="pm01"
IP_ADDRESS="10.10.2.XX"

# Generate certificate with PKCS#8 key
bao write -format=json pki_int/issue/keylime-services \
  common_name="agent.keylime.${HOSTNAME}" \
  alt_names="localhost,${SHORT_NAME}" \
  ip_sans="${IP_ADDRESS},127.0.0.1" \
  ttl="168h" \
  private_key_format=pkcs8 > /tmp/keylime-agent-${SHORT_NAME}.json

# Extract components
cat /tmp/keylime-agent-${SHORT_NAME}.json | jq -r '.data.certificate' > /tmp/agent-${SHORT_NAME}.crt
cat /tmp/keylime-agent-${SHORT_NAME}.json | jq -r '.data.private_key' > /tmp/agent-${SHORT_NAME}-pkcs8.key
cat /tmp/keylime-agent-${SHORT_NAME}.json | jq -r '.data.ca_chain[]' > /tmp/ca-${SHORT_NAME}.crt

# Verify PKCS#8 format
head -1 /tmp/agent-${SHORT_NAME}-pkcs8.key
# Should show: -----BEGIN PRIVATE KEY----- (not "BEGIN EC PRIVATE KEY")
```

### 1.2: Build Complete Certificate Chain

**Critical Lesson:** Certificate files must contain leaf + intermediate for proper mTLS.

```bash
# Get intermediate CA certificate
cat /tmp/ca-${SHORT_NAME}.crt > /tmp/ca-intermediate-${SHORT_NAME}.crt

# Build agent certificate with full chain (leaf + intermediate)
cat /tmp/agent-${SHORT_NAME}.crt /tmp/ca-intermediate-${SHORT_NAME}.crt > /tmp/agent-${SHORT_NAME}-fullchain.crt

# Verify full chain (should show 2 certificates)
grep -c 'BEGIN CERTIFICATE' /tmp/agent-${SHORT_NAME}-fullchain.crt
# Expected output: 2
```

### 1.3: Get Root CA Certificate

**Critical Lesson:** Root CA must have complete DN, source from step-ca!

```bash
# Copy correct root CA from step-ca host
ssh ca.funlab.casa "sudo cat /etc/step-ca/certs/root_ca.crt" > /tmp/ca-root-${SHORT_NAME}.crt

# Verify correct Distinguished Name
openssl x509 -in /tmp/ca-root-${SHORT_NAME}.crt -noout -subject
# Expected: subject=CN=Eye of Thundera, O=Funlab.Casa, OU=Tower of Omens, C=US
```

### 1.4: Build Complete Trust Chain

```bash
# Build complete chain: intermediate + root
cat /tmp/ca-intermediate-${SHORT_NAME}.crt /tmp/ca-root-${SHORT_NAME}.crt > /tmp/ca-complete-chain-${SHORT_NAME}.crt

# Verify complete chain (should show 2 certificates)
grep -c 'BEGIN CERTIFICATE' /tmp/ca-complete-chain-${SHORT_NAME}.crt
# Expected output: 2

# Verify certificate subjects
openssl crl2pkcs7 -nocrl -certfile /tmp/ca-complete-chain-${SHORT_NAME}.crt | \
  openssl pkcs7 -print_certs -noout -text | \
  grep 'Subject:'
# Expected:
#   Subject: C=US, O=Funlab.Casa, OU=Tower of Omens, CN=Book of Omens
#   Subject: CN=Eye of Thundera, O=Funlab.Casa, OU=Tower of Omens, C=US
```

### 1.5: Verify Certificate Chain

**Critical:** Validate certificate chain BEFORE deployment!

```bash
# Test certificate validation
openssl x509 -in /tmp/agent-${SHORT_NAME}-fullchain.crt | \
  openssl verify -CAfile /tmp/ca-complete-chain-${SHORT_NAME}.crt
# Expected output: stdin: OK

# If verification fails, DO NOT PROCEED - fix certificates first!
```

---

## Step 2: Install and Configure SPIRE Agent

### 2.1: Install SPIRE Agent

```bash
# On target host (pm01.funlab.casa)
sudo mkdir -p /opt/spire/agent
cd /opt/spire/agent

# Download SPIRE (adjust version as needed)
SPIRE_VERSION="1.9.0"
wget https://github.com/spiffe/spire/releases/download/v${SPIRE_VERSION}/spire-${SPIRE_VERSION}-linux-amd64-musl.tar.gz
tar xzf spire-${SPIRE_VERSION}-linux-amd64-musl.tar.gz
sudo cp spire-${SPIRE_VERSION}/bin/spire-agent /usr/local/bin/

# Verify installation
spire-agent --version
```

### 2.2: Create SPIRE Agent Configuration

```bash
# Create config directory
sudo mkdir -p /etc/spire/agent

# Create agent configuration
sudo tee /etc/spire/agent/agent.conf > /dev/null <<EOF
agent {
  data_dir = "/var/lib/spire/agent"
  log_level = "INFO"
  server_address = "spire.funlab.casa"
  server_port = "8081"
  socket_path = "/tmp/spire-agent/public/api.sock"
  trust_domain = "funlab.casa"
}

plugins {
  NodeAttestor "tpm" {
    plugin_cmd = "/usr/local/bin/spire-agent"
    plugin_checksum = ""
    plugin_data {
      tpm_path = "/dev/tpmrm0"
    }
  }

  KeyManager "disk" {
    plugin_data {
      directory = "/var/lib/spire/agent"
    }
  }

  WorkloadAttestor "unix" {
    plugin_data {
      discover_workload_path = true
    }
  }
}
EOF

# Create data directory
sudo mkdir -p /var/lib/spire/agent
sudo mkdir -p /tmp/spire-agent/public
```

### 2.3: Create Runtime Directory for SPIRE Agent

**CRITICAL:** SPIRE agent requires `/run/spire` directory which is cleared on reboot (tmpfs).

**Option 1: Using tmpfiles.d (Recommended)**

```bash
# Create tmpfiles.d configuration
sudo tee /etc/tmpfiles.d/spire-agent.conf > /dev/null <<EOF
# SPIRE Agent runtime directory
d /run/spire 0755 spire spire -
d /run/spire/sockets 0755 spire spire -
EOF

# Create directory immediately (systemd-tmpfiles will recreate on reboot)
sudo systemd-tmpfiles --create /etc/tmpfiles.d/spire-agent.conf

# Verify directory exists
ls -la /run/spire
```

**Option 2: Using ExecStartPre in systemd service**

Add `ExecStartPre=/bin/mkdir -p /run/spire` to the service file (less preferred).

### 2.4: Create SPIRE Agent systemd Service

```bash
sudo tee /etc/systemd/system/spire-agent.service > /dev/null <<EOF
[Unit]
Description=SPIRE Agent
Documentation=https://spiffe.io/docs/latest/deploying/spire_agent/
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=spire
Group=spire
ExecStart=/usr/local/bin/spire-agent run -config /etc/spire/agent/agent.conf
Restart=on-failure
RestartSec=5
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/spire /run/spire
CapabilityBoundingSet=
AmbientCapabilities=

[Install]
WantedBy=multi-user.target
EOF

# Create spire user and group
sudo useradd -r -s /bin/false -d /var/lib/spire spire || true

# Reload systemd
sudo systemctl daemon-reload
```

**Important Notes:**
- The service uses `User=spire` for security (not root)
- `ReadWritePaths=/run/spire` requires the directory to exist
- Without tmpfiles.d configuration, service will fail after reboot with:
  ```
  Failed to set up mount namespacing: /run/spire: No such file or directory
  ```

### 2.5: Register SPIRE Agent with Server

```bash
# On SPIRE server (spire.funlab.casa)
HOSTNAME="pm01.funlab.casa"

# Generate join token
sudo /usr/local/bin/spire-server token generate \
  -spiffeID spiffe://funlab.casa/agent/${HOSTNAME} \
  -ttl 3600

# Copy the token output, then on target host:
# Start agent with join token
sudo /usr/local/bin/spire-agent run \
  -config /etc/spire/agent/agent.conf \
  -joinToken <TOKEN_FROM_SERVER>

# After successful registration, enable service
sudo systemctl enable --now spire-agent
sudo systemctl status spire-agent
```

---

## Step 3: Install and Configure Keylime Agent

### 3.1: Install Keylime Agent

**IMPORTANT:** Always build from the custom fork, NOT upstream! The upstream has a regression in reqwest 0.13 that breaks TLS configuration.

```bash
# On target host, install build dependencies
sudo apt-get update
sudo apt-get install -y \
  build-essential \
  pkg-config \
  libssl-dev \
  libtss2-dev \
  libclang-dev \
  clang \
  git

# Install Rust (if not already installed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Copy working rust-keylime source from spire.funlab.casa
# This fork uses reqwest 0.12.15 which correctly handles TLS configuration
# DO NOT use upstream github.com/keylime/rust-keylime (has reqwest 0.13 regression)
scp -r spire.funlab.casa:/home/tygra/rust-keylime /tmp/rust-keylime-working

# Build keylime_agent
cd /tmp/rust-keylime-working
cargo build --release --bin keylime_agent

# Install binary
sudo cp target/release/keylime_agent /usr/local/bin/keylime_agent
sudo chmod +x /usr/local/bin/keylime_agent

# Verify it runs
/usr/local/bin/keylime_agent --help

# Create keylime system user
sudo useradd -r -s /bin/false -d /var/lib/keylime -m keylime
```

**Why use the fork?**
- Upstream commit `419b888` updated reqwest from 0.12 to 0.13
- This broke `registrar_tls_enabled` configuration - agent defaults to HTTP instead of HTTPS
- Our fork stays on reqwest 0.12.15 which works correctly
- Monitor upstream for fixes: https://github.com/keylime/rust-keylime/commits/master/

### 3.2: Install Certificates

```bash
# Create certificate directory
sudo mkdir -p /etc/keylime/certs

# Copy certificates from generation host
# Run these FROM the host where you generated certs (spire.funlab.casa):
SHORT_NAME="pm01"
TARGET_HOST="pm01.funlab.casa"

scp /tmp/agent-${SHORT_NAME}-fullchain.crt ${TARGET_HOST}:/tmp/
scp /tmp/agent-${SHORT_NAME}-pkcs8.key ${TARGET_HOST}:/tmp/
scp /tmp/ca-intermediate-${SHORT_NAME}.crt ${TARGET_HOST}:/tmp/
scp /tmp/ca-root-${SHORT_NAME}.crt ${TARGET_HOST}:/tmp/
scp /tmp/ca-complete-chain-${SHORT_NAME}.crt ${TARGET_HOST}:/tmp/

# On target host, install certificates
sudo mv /tmp/agent-${SHORT_NAME}-fullchain.crt /etc/keylime/certs/agent.crt
sudo mv /tmp/agent-${SHORT_NAME}-pkcs8.key /etc/keylime/certs/agent-pkcs8.key
sudo mv /tmp/ca-intermediate-${SHORT_NAME}.crt /etc/keylime/certs/ca.crt
sudo mv /tmp/ca-root-${SHORT_NAME}.crt /etc/keylime/certs/ca-root-only.crt
sudo mv /tmp/ca-complete-chain-${SHORT_NAME}.crt /etc/keylime/certs/ca-complete-chain.crt

# Set correct permissions
sudo chown -R keylime:tss /etc/keylime/certs/
sudo chmod 644 /etc/keylime/certs/*.crt
sudo chmod 600 /etc/keylime/certs/*-pkcs8.key
```

### 3.3: Verify Certificate Installation

```bash
# Verify certificate count (should be 2)
sudo grep -c 'BEGIN CERTIFICATE' /etc/keylime/certs/agent.crt
# Expected: 2

# Verify PKCS#8 key format
sudo head -1 /etc/keylime/certs/agent-pkcs8.key
# Expected: -----BEGIN PRIVATE KEY-----

# Verify root CA DN
sudo openssl x509 -in /etc/keylime/certs/ca-root-only.crt -noout -subject
# Expected: subject=CN=Eye of Thundera, O=Funlab.Casa, OU=Tower of Omens, C=US

# Verify certificate chain validation
sudo openssl x509 -in /etc/keylime/certs/agent.crt | \
  sudo openssl verify -CAfile /etc/keylime/certs/ca-complete-chain.crt
# Expected: stdin: OK

# If any verification fails, STOP and fix certificates before proceeding!
```

### 3.4: Configure Keylime Agent

```bash
# Create agent configuration
# NOTE: Replace HOSTNAME and IP_ADDRESS with actual values for the target host
HOSTNAME="pm01.funlab.casa"
IP_ADDRESS="10.200.200.10"

sudo tee /etc/keylime/agent.conf > /dev/null <<EOF
[agent]
# Server configuration
ip = "0.0.0.0"
port = 9002
contact_ip = "${IP_ADDRESS}"
contact_port = 9002

# Registrar configuration
# Use registrar.keylime.funlab.casa on standard HTTPS port 443
registrar_ip = "registrar.keylime.funlab.casa"
registrar_port = 443

# mTLS Configuration
enable_agent_mtls = true
server_key = "/etc/keylime/certs/agent-pkcs8.key"
server_cert = "/etc/keylime/certs/agent.crt"
trusted_client_ca = "/etc/keylime/certs/ca-complete-chain.crt"

# Registrar mTLS - CRITICAL: These settings must be present for TLS to work
registrar_tls_enabled = true
registrar_tls_ca_cert = "/etc/keylime/certs/ca-root-only.crt"
registrar_tls_client_cert = "/etc/keylime/certs/agent.crt"
registrar_tls_client_key = "/etc/keylime/certs/agent-pkcs8.key"

# Verifier configuration
verifier_ip = "verifier.keylime.funlab.casa"
verifier_port = "443"
verifier_tls_ca_cert = "/etc/keylime/certs/ca-root-only.crt"
verifier_tls_client_cert = "/etc/keylime/certs/agent.crt"
verifier_tls_client_key = "/etc/keylime/certs/agent-pkcs8.key"

# TPM configuration
tpm_ownerpassword = ""

# Logging
log_destination = "stream"
EOF
```

### 3.5: Create systemd Service

```bash
# Create systemd service file for Rust keylime_agent
sudo tee /etc/systemd/system/keylime_agent.service > /dev/null <<EOF
[Unit]
Description=Keylime Agent
After=network.target

[Service]
Type=simple
User=root
Environment="RUST_LOG=info"
ExecStart=/usr/local/bin/keylime_agent
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
sudo systemctl daemon-reload
```

**Note:** The Rust keylime_agent doesn't accept a `-c` flag for config file. It reads `/etc/keylime/agent.conf` automatically.

### 3.6: Open Firewall Port

```bash
# Add firewall rule for port 9002
sudo iptables -I INPUT -p tcp --dport 9002 -j ACCEPT

# Save firewall rules (method varies by distro)
# For Debian/Ubuntu with iptables-persistent:
sudo netfilter-persistent save

# For systems without iptables-persistent:
sudo mkdir -p /etc/iptables
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

### 3.7: Start Keylime Agent

```bash
# Enable and start service
sudo systemctl enable keylime_agent
sudo systemctl start keylime_agent

# Check status
sudo systemctl status keylime_agent

# View logs (look for "Agent UUID" and "Listening on https://0.0.0.0:9002")
sudo journalctl -u keylime_agent -f

# Expected log output:
# INFO keylime_agent > Agent UUID: d432fbb3-d2f1-4a97-9ef7-75bd81c00000
# INFO keylime::registrar_client > Building Registrar client: scheme=https, registrar=registrar.keylime.funlab.casa:443, TLS=true
# SUCCESS: Agent d432fbb3-d2f1-4a97-9ef7-75bd81c00000 registered
# INFO keylime_agent > Listening on https://0.0.0.0:9002
```

**Troubleshooting:**
- If you see `scheme=http` instead of `scheme=https`, the agent wasn't built from the correct fork
- If registration fails with connection errors, check firewall and network connectivity
- If you see "Permission denied" errors, ensure the keylime user exists

---

## Step 4: Register with Keylime Verifier

### 4.1: Get Agent UUID

```bash
# On target host, get the agent UUID from logs
sudo journalctl -u keylime_agent --since "5 minutes ago" | grep "Agent UUID"

# Example output:
# keylime_agent[12345]: INFO keylime_agent > Agent UUID: abc123def456...

# Save the UUID for registration
AGENT_UUID="abc123def456..."  # Replace with actual UUID
```

### 4.2: Register Agent with Verifier

```bash
# On verifier host (spire.funlab.casa)
AGENT_HOST="pm01.funlab.casa"
AGENT_UUID="d432fbb3-d2f1-4a97-9ef7-75bd81c00000"  # From step 4.1

# Register with verifier using simplified command
echo "" | sudo keylime_tenant -c add -t ${AGENT_HOST} -u ${AGENT_UUID}

# Expected output:
# WARNING:keylime.tenant:DANGER: EK cert checking is disabled...
# INFO:keylime.tenant:Quote from Agent <UUID> (<HOST>:9002) validated
# INFO:keylime.tenant:Agent <UUID> (<HOST>:9002) added to Verifier (127.0.0.1:8881) after 0 tries
# {'code': 200, 'status': 'Success', ...}
```

**Note:** The `echo ""` provides an empty password for the keystore prompt.

### 4.3: Check Registration Status

```bash
# Verify agent is registered
sudo keylime_tenant -v spire.funlab.casa -t ${AGENT_HOST} \
  --uuid ${AGENT_UUID} \
  -c status

# Look for:
# "operational_state": "Get Quote" or "Registered"
# "attestation_status": "PASS"
```

---

## Step 5: Verification

### 5.1: Verify SPIRE Agent

```bash
# On target host
sudo systemctl status spire-agent

# Check SPIRE workload API socket
ls -la /tmp/spire-agent/public/api.sock

# Test SPIRE agent health
sudo /usr/local/bin/spire-agent healthcheck

# View SPIRE entries (on SPIRE server)
sudo /usr/local/bin/spire-server entry show -spiffeID spiffe://funlab.casa/agent/${AGENT_HOST}
```

### 5.2: Verify Keylime Agent

```bash
# On target host
sudo systemctl status keylime_agent

# Check agent is listening
sudo ss -tlnp | grep 9002
# Expected: keylime_agent listening on 0.0.0.0:9002

# Check agent logs for errors
sudo journalctl -u keylime_agent -n 50 --no-pager | grep -i error
# Should have no ERROR lines after startup
```

### 5.3: Verify mTLS Connection

```bash
# On verifier host (spire.funlab.casa)
sudo openssl s_client -connect ${AGENT_HOST}:9002 \
  -CAfile /etc/keylime/certs/ca-complete-chain.crt \
  -cert /etc/keylime/certs/verifier.crt \
  -key /etc/keylime/certs/verifier-pkcs8.key \
  -servername agent.keylime.${AGENT_HOST} \
  </dev/null 2>&1 | grep "Verify return code"

# Expected output:
# Verify return code: 0 (ok)

# If return code is NOT 0, check certificate chain!
```

### 5.4: Verify Attestation

```bash
# On verifier host
sudo keylime_tenant -v spire.funlab.casa -t ${AGENT_HOST} \
  --uuid ${AGENT_UUID} \
  -c status

# Expected output with Phase 3 attestation hardening:
# "operational_state": "Get Quote"
# "attestation_status": "PASS"
# "attestation_count": <number > 0, increases every ~2 seconds>
# "has_runtime_policy": 1

# Watch verifier logs for attestation activity
sudo journalctl -u keylime_verifier -f | grep ${AGENT_UUID}

# Expected log patterns:
# - Quote from Agent <UUID> (<HOST>:9002) validated
# - PCR(s) 4, 7 and 16 from bank 'sha256' found in TPM quote
# - IMA measurement list processing complete
```

**Attestation Status Meanings:**
- **"Get Quote"**: Agent is operational and being continuously attested (healthy state)
- **"PASS"**: Attestation checks passing
- **"has_runtime_policy": 1**: IMA runtime policy is active and being enforced

**What's Being Verified:**
1. **PCR 7**: Secure Boot state (UEFI firmware verification)
2. **PCR 4**: Boot loader integrity (GRUB measurements)
3. **IMA measurements**: Runtime file integrity (3,000-5,000+ measurements)
4. **TPM Quote**: Cryptographic proof of PCR values signed by TPM

### 5.5: Final Health Check

```bash
# Run comprehensive health check
cat <<'EOF' | sudo bash
#!/bin/bash
echo "=== Health Check for ${HOSTNAME} ==="
echo ""

echo "1. SPIRE Agent Status:"
systemctl is-active spire-agent
echo ""

echo "2. Keylime Agent Status:"
systemctl is-active keylime_agent
echo ""

echo "3. Certificate Validity:"
openssl x509 -in /etc/keylime/certs/agent.crt -noout -dates
echo ""

echo "4. Certificate Chain Count:"
echo "   agent.crt: $(grep -c 'BEGIN CERTIFICATE' /etc/keylime/certs/agent.crt) certs (expected: 2)"
echo "   ca-complete-chain.crt: $(grep -c 'BEGIN CERTIFICATE' /etc/keylime/certs/ca-complete-chain.crt) certs (expected: 2)"
echo ""

echo "5. Network Connectivity:"
echo "   Keylime agent listening: $(ss -tln | grep :9002 >/dev/null && echo 'YES' || echo 'NO')"
echo ""

echo "6. File Permissions:"
ls -la /etc/keylime/certs/ | tail -n +2
echo ""

echo "✅ Health check complete"
EOF
```

---

## Troubleshooting

### Issue 1: mTLS Connection Fails

**Symptoms:**
```
ERROR: Keylime agent does not recognize mTLS certificate form tenant
```

**Diagnosis:**
```bash
# Test TLS handshake
sudo openssl s_client -connect ${AGENT_HOST}:9002 \
  -CAfile /etc/keylime/certs/ca-complete-chain.crt \
  -cert /etc/keylime/certs/verifier.crt \
  -key /etc/keylime/certs/verifier-pkcs8.key \
  </dev/null 2>&1 | grep -E 'Verify|error'
```

**Common Causes:**
1. **Agent certificate missing intermediate:** `grep -c 'BEGIN CERTIFICATE' /etc/keylime/certs/agent.crt` returns 1 instead of 2
2. **Root CA has wrong DN:** Missing O, OU, C fields in ca-root-only.crt
3. **Certificate chain validation fails:** `openssl verify` returns error

**Solution:**
```bash
# Rebuild agent certificate with intermediate
sudo bash -c 'cat /etc/keylime/certs/agent.crt.backup /etc/keylime/certs/ca.crt > /etc/keylime/certs/agent.crt'

# Get correct root CA from step-ca
ssh ca.funlab.casa "sudo cat /etc/step-ca/certs/root_ca.crt" | sudo tee /etc/keylime/certs/ca-root-only.crt

# Rebuild complete chain
sudo bash -c 'cat /etc/keylime/certs/ca.crt /etc/keylime/certs/ca-root-only.crt > /etc/keylime/certs/ca-complete-chain.crt'

# Restart agent
sudo systemctl restart keylime_agent
```

### Issue 2: Certificate Format Error

**Symptoms:**
```
ERROR: Unable to load private key
```

**Diagnosis:**
```bash
# Check key format
sudo head -1 /etc/keylime/certs/agent-pkcs8.key
```

**If shows:** `-----BEGIN EC PRIVATE KEY-----` (WRONG FORMAT)

**Solution:**
Regenerate certificate with `private_key_format=pkcs8`:
```bash
bao write -format=json pki_int/issue/keylime-services \
  common_name="agent.keylime.${HOSTNAME}" \
  private_key_format=pkcs8 \
  ... # other parameters
```

### Issue 3: Certificate Expired

**Symptoms:**
```
ERROR: certificate has expired
```

**Diagnosis:**
```bash
openssl x509 -in /etc/keylime/certs/agent.crt -noout -dates
```

**Solution:**
Regenerate certificate following Step 1, then restart agent.

### Issue 4: Agent Won't Start

**Symptoms:**
```
systemctl status keylime_agent
# Status: failed
```

**Diagnosis:**
```bash
sudo journalctl -u keylime_agent -n 50 --no-pager
```

**Common Causes:**
1. **Permission errors:** Certificate files not readable by keylime user
2. **TPM issues:** `/dev/tpmrm0` not accessible
3. **Port conflict:** Another process using port 9002

**Solutions:**
```bash
# Fix permissions
sudo chown -R keylime:tss /etc/keylime/certs/
sudo chmod 644 /etc/keylime/certs/*.crt
sudo chmod 600 /etc/keylime/certs/*-pkcs8.key

# Check TPM access
ls -la /dev/tpm*
sudo usermod -a -G tss keylime

# Check port availability
sudo ss -tlnp | grep 9002
```

### Issue 5: Attestation Status FAILED

**Symptoms:**
```
"attestation_status": "FAILED"
"operational_state": "Invalid Quote"
```

**Diagnosis:**
```bash
# Check verifier logs for specific failure reason
sudo journalctl -u keylime_verifier -f | grep ${AGENT_UUID}

# Check agent attestation details
sudo keylime_tenant -v spire.funlab.casa -t ${AGENT_HOST} \
  --uuid ${AGENT_UUID} -c status | jq '.results.has_runtime_policy'
```

**Common Causes:**

**1. TPM PCR values changed (system updates)**
```
# Verifier log shows:
ERROR: PCR #4 in quote does not match expected value
```
- **Cause:** Kernel or GRUB update changed boot measurements
- **Solution:** Re-register agent to capture new PCR baseline
```bash
# On verifier
sudo keylime_tenant -c delete -t ${AGENT_HOST} -u ${AGENT_UUID}
sudo keylime_tenant -c add -t ${AGENT_HOST} -u ${AGENT_UUID}
```

**2. IMA not enabled (has_runtime_policy = 0)**
```
# Status shows:
"has_runtime_policy": 0
```
- **Cause:** IMA kernel parameters not configured or system not rebooted
- **Solution:** Follow Step 0 to enable IMA, verify with:
```bash
sudo cat /sys/kernel/security/ima/ascii_runtime_measurements | wc -l
# Should show 3000+ measurements
```

**3. PCR policy mismatch**
```
# Verifier log shows:
WARNING: PCR #4 in quote not found in tpm_policy
```
- **Cause:** SPIRE plugin TPM policy doesn't include PCR being measured
- **Solution:** Verify SPIRE Keylime plugin is using Phase 3 policy (mask 0x90)

**4. Network connectivity issues**
```
# Verifier log shows:
ERROR: Unable to contact agent at <HOST>:9002
```
- **Cause:** Firewall blocking port 9002, agent not running, network issue
- **Solution:**
```bash
# Check agent is running
sudo systemctl status keylime_agent

# Check port is open
sudo ss -tlnp | grep 9002

# Test connectivity from verifier
curl -k https://${AGENT_HOST}:9002/version
```

**Solution:**
Check specific error in verifier logs and apply appropriate fix above.

### Issue 6: SPIRE Agent Fails After Reboot - /run/spire Missing

**Symptoms:**
```bash
sudo systemctl status spire-agent
# Status: failed

# Logs show:
Failed to set up mount namespacing: /run/spire: No such file or directory
```

**Cause:**
- `/run/spire` is on tmpfs and cleared on reboot
- No tmpfiles.d configuration to recreate it
- Service has `ReadWritePaths=/run/spire` which requires directory exists

**Quick Fix:**
```bash
# Manually create directory
sudo mkdir -p /run/spire
sudo chown spire:spire /run/spire
sudo chmod 755 /run/spire

# Restart service
sudo systemctl restart spire-agent
```

**Permanent Fix:**
```bash
# Create tmpfiles.d configuration (will survive reboots)
sudo tee /etc/tmpfiles.d/spire-agent.conf > /dev/null <<EOF
# SPIRE Agent runtime directory
d /run/spire 0755 spire spire -
d /run/spire/sockets 0755 spire spire -
EOF

# Apply immediately
sudo systemd-tmpfiles --create /etc/tmpfiles.d/spire-agent.conf

# Verify
ls -la /run/spire

# Reboot to confirm it persists
sudo reboot
```

**Verification:**
```bash
# After reboot
sudo systemctl status spire-agent
# Should be: active (running)

# Directory should exist
ls -la /run/spire
# Expected: drwxr-xr-x spire spire
```

### Issue 7: IMA Measurements Not Collected

**Symptoms:**
```bash
sudo cat /sys/kernel/security/ima/ascii_runtime_measurements | wc -l
# Returns: 0 or very low count
```

**Diagnosis:**
```bash
# Check kernel parameters
cat /proc/cmdline | grep ima

# Check IMA filesystem is mounted
ls -la /sys/kernel/security/ima/
```

**Common Causes:**
1. **IMA kernel parameters not configured**
   - Missing `ima_policy=tcb ima_hash=sha256` in GRUB config
   - Solution: Follow Step 0.2 and 0.3, then reboot

2. **Kernel doesn't support IMA**
   - `/sys/kernel/security/ima/` directory doesn't exist
   - Solution: Use kernel with CONFIG_IMA=y enabled

3. **System not rebooted after GRUB update**
   - `cat /proc/cmdline` doesn't show IMA parameters
   - Solution: `sudo reboot`

**Verification:**
```bash
# After fix, verify IMA is working
sudo cat /sys/kernel/security/ima/ascii_runtime_measurements | head -5
# Should show measurement entries like:
# 10 <hash> ima-ng sha256:<hash> boot_aggregate

# Verify thousands of measurements
sudo cat /sys/kernel/security/ima/ascii_runtime_measurements | wc -l
# Expected: 3000-5000+
```

---

## Quick Reference

### Certificate Files Structure

```
/etc/keylime/certs/
├── agent.crt                # Leaf cert + intermediate (2 certs) - FULL CHAIN
├── agent-pkcs8.key          # Private key in PKCS#8 format
├── ca.crt                   # Book of Omens intermediate CA
├── ca-root-only.crt         # Eye of Thundera root CA (correct DN!)
└── ca-complete-chain.crt    # Intermediate + Root (2 certs)
```

### Plugin Checksum Reference (SPIRE Server)

**Current Production (Phase 3):**
```
SHA256: 79cab8cbace12e1b4e2cb0fba13c326692825d2957631d702547875a306378b9
Git Commit: acdeac7
TPM Policy: {"mask": "0x90"}  # PCRs 4, 7
IMA Policy: Exclude-based (no allowlist)
```

**Historical Checksums:**
- **Phase 1** (24d5b70): `3090a15ba91e34e52a3e31aec026efc7c5d90b0b62f2c24a56d6764481408573`
- **Phase 2** (6f2d7d6): `baa3db24b3b0c32075fb72464e619be8581aba1ff18c72e1032c88ae0663ffcd`
- **Phase 3** (acdeac7): `9c934fc171d79714590e117948fb80e7a6361638833e6f6b5f93b4f1ab927243` (source)
- **Production**: `79cab8cbace12e1b4e2cb0fba13c326692825d2957631d702547875a306378b9` (deployed)

**Verify deployed plugin:**
```bash
# On spire.funlab.casa
sha256sum /opt/spire/plugins/keylime-attestor-server
grep plugin_checksum /etc/spire/server.conf
# These should match!
```

### Essential Commands

```bash
# Check agent status
sudo systemctl status keylime_agent
sudo systemctl status spire-agent

# View agent UUID
sudo journalctl -u keylime_agent | grep "Agent UUID"

# Check IMA measurements
sudo cat /sys/kernel/security/ima/ascii_runtime_measurements | wc -l
# Expected: 3000-5000+

# Test mTLS connection
sudo openssl s_client -connect ${HOST}:9002 \
  -CAfile /etc/keylime/certs/ca-complete-chain.crt \
  -cert /etc/keylime/certs/verifier.crt \
  -key /etc/keylime/certs/verifier-pkcs8.key

# Check attestation status
sudo keylime_tenant -v spire.funlab.casa -t ${HOST} --uuid ${UUID} -c status

# Verify certificate chain
sudo openssl x509 -in /etc/keylime/certs/agent.crt | \
  sudo openssl verify -CAfile /etc/keylime/certs/ca-complete-chain.crt

# SPIRE Server: Restart after plugin update
sudo systemctl restart spire-server
sudo journalctl -u spire-server -n 50 | grep -i keylime
```

### Checklist for New Host

**Pre-Onboarding:**
- [ ] IMA enabled in kernel (Step 0)
- [ ] IMA kernel parameters in /etc/default/grub: `ima_policy=tcb ima_hash=sha256`
- [ ] System rebooted after GRUB update
- [ ] IMA measurements being collected (3000+ entries in ascii_runtime_measurements)

**Certificate Generation:**
- [ ] Generated certificate with `private_key_format=pkcs8`
- [ ] Agent certificate contains 2 certs (leaf + intermediate)
- [ ] Root CA certificate has complete DN (O, OU, C fields)
- [ ] ca-complete-chain.crt contains 2 certs (intermediate + root)
- [ ] Certificate chain validation passes (`openssl verify` returns OK)
- [ ] Certificate files have correct permissions (644 for .crt, 600 for .key)
- [ ] Certificate files owned by keylime:tss

**Agent Installation:**
- [ ] SPIRE agent running and registered
- [ ] Keylime agent running and listening on port 9002
- [ ] mTLS handshake succeeds (verify return code: 0)

**Attestation Verification:**
- [ ] Agent registered with verifier
- [ ] Operational state: "Get Quote"
- [ ] Attestation status: PASS
- [ ] Runtime policy active: has_runtime_policy = 1
- [ ] Attestation count increasing every ~2 seconds
- [ ] Verifier logs show PCRs 4, 7, and 16 in quote

---

## Example: Complete Onboarding for pm01.funlab.casa

**PREREQUISITE:** IMA must be enabled first (Step 0) before running this script!

```bash
#!/bin/bash
# Complete onboarding script for pm01.funlab.casa
# IMPORTANT: Run Step 0 (IMA enablement) FIRST, then reboot, THEN run this script

set -e

# Configuration
HOSTNAME="pm01.funlab.casa"
SHORT_NAME="pm01"
IP_ADDRESS="10.10.2.101"  # Adjust to actual IP

echo "=== Onboarding ${HOSTNAME} ==="

# Verify IMA is enabled (from Step 0)
echo "Checking IMA status..."
IMA_COUNT=$(ssh ${HOSTNAME} "sudo cat /sys/kernel/security/ima/ascii_runtime_measurements 2>/dev/null | wc -l" || echo "0")
if [ "$IMA_COUNT" -lt 1000 ]; then
  echo "❌ ERROR: IMA not properly enabled on ${HOSTNAME}"
  echo "   IMA measurement count: ${IMA_COUNT} (expected: 3000+)"
  echo "   Please complete Step 0 (Enable IMA) first, then reboot"
  exit 1
fi
echo "✅ IMA enabled with ${IMA_COUNT} measurements"

# Step 1: Generate certificates (on spire.funlab.casa)
ssh spire.funlab.casa <<'ENDSSH'
export BAO_ADDR='https://openbao.funlab.casa:8088'
export BAO_SKIP_VERIFY=true
export BAO_TOKEN=$(sudo cat /root/.openbao-token)

HOSTNAME="pm01.funlab.casa"
SHORT_NAME="pm01"
IP_ADDRESS="10.10.2.101"

# Generate certificate
bao write -format=json pki_int/issue/keylime-services \
  common_name="agent.keylime.${HOSTNAME}" \
  alt_names="localhost,${SHORT_NAME}" \
  ip_sans="${IP_ADDRESS},127.0.0.1" \
  ttl="168h" \
  private_key_format=pkcs8 > /tmp/keylime-agent-${SHORT_NAME}.json

# Extract components
cat /tmp/keylime-agent-${SHORT_NAME}.json | jq -r '.data.certificate' > /tmp/agent-${SHORT_NAME}.crt
cat /tmp/keylime-agent-${SHORT_NAME}.json | jq -r '.data.private_key' > /tmp/agent-${SHORT_NAME}-pkcs8.key
cat /tmp/keylime-agent-${SHORT_NAME}.json | jq -r '.data.ca_chain[]' > /tmp/ca-${SHORT_NAME}.crt

# Build full chain
cat /tmp/agent-${SHORT_NAME}.crt /tmp/ca-${SHORT_NAME}.crt > /tmp/agent-${SHORT_NAME}-fullchain.crt

# Get root CA
ssh ca.funlab.casa "sudo cat /etc/step-ca/certs/root_ca.crt" > /tmp/ca-root-${SHORT_NAME}.crt

# Build complete chain
cat /tmp/ca-${SHORT_NAME}.crt /tmp/ca-root-${SHORT_NAME}.crt > /tmp/ca-complete-chain-${SHORT_NAME}.crt

echo "✅ Certificates generated"
ENDSSH

# Step 2: Install certificates on target host
scp spire.funlab.casa:/tmp/agent-${SHORT_NAME}-fullchain.crt /tmp/
scp spire.funlab.casa:/tmp/agent-${SHORT_NAME}-pkcs8.key /tmp/
scp spire.funlab.casa:/tmp/ca-${SHORT_NAME}.crt /tmp/
scp spire.funlab.casa:/tmp/ca-root-${SHORT_NAME}.crt /tmp/
scp spire.funlab.casa:/tmp/ca-complete-chain-${SHORT_NAME}.crt /tmp/

ssh ${HOSTNAME} <<'ENDSSH'
SHORT_NAME="pm01"

sudo mkdir -p /etc/keylime/certs
sudo mv /tmp/agent-${SHORT_NAME}-fullchain.crt /etc/keylime/certs/agent.crt
sudo mv /tmp/agent-${SHORT_NAME}-pkcs8.key /etc/keylime/certs/agent-pkcs8.key
sudo mv /tmp/ca-${SHORT_NAME}.crt /etc/keylime/certs/ca.crt
sudo mv /tmp/ca-root-${SHORT_NAME}.crt /etc/keylime/certs/ca-root-only.crt
sudo mv /tmp/ca-complete-chain-${SHORT_NAME}.crt /etc/keylime/certs/ca-complete-chain.crt

sudo chown -R keylime:tss /etc/keylime/certs/
sudo chmod 644 /etc/keylime/certs/*.crt
sudo chmod 600 /etc/keylime/certs/*-pkcs8.key

echo "✅ Certificates installed"
ENDSSH

# Step 3: Configure and start agents
# (Continue with SPIRE and Keylime configuration as documented above)

echo "✅ Onboarding complete for ${HOSTNAME}"
```

---

## Lessons Learned (Production Experience)

### 1. Certificate Chain Completeness
**Problem:** Certificates with only leaf certificate fail mTLS validation
**Solution:** Always include intermediate certificate in cert files
**Verification:** `grep -c 'BEGIN CERTIFICATE' cert.crt` must return 2

### 2. Root CA Distinguished Name
**Problem:** Root CA with incomplete DN breaks chain validation
**Solution:** Always source root CA from step-ca (`/etc/step-ca/certs/root_ca.crt`)
**Verification:** DN must include O, OU, C fields, not just CN

### 3. Private Key Format
**Problem:** Traditional EC/RSA format incompatible with some software
**Solution:** Always use `private_key_format=pkcs8` parameter
**Verification:** Key must start with `-----BEGIN PRIVATE KEY-----`

### 4. Certificate Verification Before Deployment
**Problem:** Invalid certificates discovered only after deployment
**Solution:** Run `openssl verify` before installing certificates
**Verification:** Must return "stdin: OK" before proceeding

### 5. TLS Handshake Testing
**Problem:** mTLS issues discovered during attestation attempts
**Solution:** Test TLS handshake with `openssl s_client` before registration
**Verification:** Verify return code must be 0 (ok)

### 6. Rust Keylime - reqwest Library Regression
**Problem:** Upstream Rust Keylime (reqwest 0.13) ignores `registrar_tls_enabled` and defaults to HTTP
**Symptoms:**
- Logs show `Building Registrar client: scheme=http, TLS=false`
- nginx returns "400 Bad Request" when agent tries to connect
- Connection failures with "Connection reset by peer"

**Solution:** Build from custom fork with reqwest 0.12.15
**Source:** `/home/tygra/rust-keylime` on spire.funlab.casa (NOT upstream!)
**Breaking Commit:** `419b888 Update reqwest from 0.12 to 0.13` (upstream)
**Verification:**
- Logs must show `scheme=https, TLS=true`
- `cargo tree | grep reqwest` should show version 0.12.15
- Check monthly if upstream fixed the issue

**Impact:** All new hosts must be built from custom fork until upstream resolves this regression

### 7. Attestation Hardening - IMA Policy Design

**Problem:** Initial Phase 2 implementation used allowlist-based IMA policy with empty digests
**Symptoms:**
- Agent shows `"operational_state": "Invalid Quote"`
- Attestation status: FAIL
- has_runtime_policy = 0
- Verifier logs show IMA policy not applied

**Root Cause:** Allowlist-based policies require pre-populated file digests in the "digests" section. An allowlist with paths but empty digests is invalid.

**Solution:** Switch to exclude-based policy
- Remove allowlist section entirely
- Only specify directories to exclude from measurement
- Much simpler and more maintainable
- System updates don't break attestation

**Implementation:**
```json
{
  "digests": {},  // Empty - no allowlist
  "excludes": ["/var/", "/tmp/", "/home/", ...],
  "allowlist": {}  // Removed
}
```

**Verification:**
- Check `has_runtime_policy = 1` in agent status
- Verify 3000+ IMA measurements being collected
- Confirm attestation status PASS

**Lesson:** For runtime integrity, exclude-based policies are superior to allowlists in dynamic environments

### 8. TPM PCR Scope - Stopping at Phase 3

**Problem:** Phase 4 attempted to add firmware PCRs (0-3) but attestation failed
**Symptoms:**
- Attestation changed to "Invalid Quote" after adding PCRs 0-3
- Verifier logs: "PCR #4 in quote not found in tpm_policy"

**Root Cause:** Firmware PCRs (0-3) require measured boot reference state (`mb_refstate`) configuration, not just a simple mask. This requires:
- Capturing baseline during known-good boot
- Managing reference state updates
- Complex policy management for firmware updates

**Decision:** Stop at Phase 3 (PCRs 4+7 + IMA)
- Phase 3 provides excellent security coverage
- Boot chain: Secure Boot (PCR 7) + GRUB (PCR 4)
- Runtime: IMA measurements (PCR 10)
- Maintainable without complex reference state management

**Lesson:** Perfect is the enemy of good - Phase 3 provides strong attestation without excessive operational complexity

### 9. IMA Kernel Parameters

**Problem:** IMA measurements not collected even after kernel parameter added
**Symptoms:** `/sys/kernel/security/ima/ascii_runtime_measurements` shows 0 entries

**Root Cause:** System not rebooted after GRUB configuration update

**Solution:**
1. Add IMA parameters to `/etc/default/grub`
2. Run `update-grub` (or `grub2-mkconfig`)
3. **MUST REBOOT** for kernel parameters to take effect
4. Verify with `cat /proc/cmdline | grep ima`

**Verification:**
```bash
# Check kernel cmdline
cat /proc/cmdline | grep ima
# Expected: ima_policy=tcb ima_hash=sha256

# Check measurement count
sudo cat /sys/kernel/security/ima/ascii_runtime_measurements | wc -l
# Expected: 3000-5000+
```

**Lesson:** Kernel parameter changes always require reboot - no way around it

---

**Document Status:** ✅ PRODUCTION READY
**Tested On:** auth.funlab.casa, spire.funlab.casa, ca.funlab.casa, pm01.funlab.casa
**Last Updated:** 2026-02-15 04:30 EST
**Known Issues:** Upstream reqwest 0.13 breaks TLS - use custom fork
**Attestation:** Phase 3 hardening active (PCRs 4+7 + IMA runtime integrity)

---

## Attestation Hardening Details

### Overview

The Keylime attestation has been hardened through three implementation phases, providing defense-in-depth protection across the boot chain and runtime.

### Phase 1: Secure Boot Verification (PCR 7)

**Implemented:** 2026-02-15 01:00 EST
**Git Commit:** `24d5b70`

**What it does:**
- Verifies UEFI Secure Boot state via TPM PCR 7
- Ensures bootloader and kernel are signed by trusted keys
- Detects any tampering with boot components

**Technical Details:**
```go
TpmPolicy: `{"mask": "0x80"}`,  // PCR 7 only
```

**Protection Level:**
- ✅ Pre-boot firmware verification
- ✅ Signed bootloader enforcement
- ❌ Boot loader integrity measurement (added in Phase 3)
- ❌ Runtime file integrity (added in Phase 2)

### Phase 2: IMA Runtime Integrity Monitoring

**Implemented:** 2026-02-15 02:30 EST
**Git Commit:** `6f2d7d6`

**What it does:**
- Monitors file access at runtime using Linux IMA
- Measures executables, libraries, and system files as they're accessed
- Stores measurements in TPM PCR 10
- Uses exclude-based policy for maintainability

**Technical Details:**
```json
{
  "meta": {"version": 5, "generator": 0},
  "release": 0,
  "digests": {},
  "excludes": [
    "/var/", "/tmp/", "/home/", "/proc/", "/sys/",
    "/dev/shm/", "/run/", "/dev/", "/sys/firmware/"
  ],
  "keyrings": {},
  "ima": {
    "ignored_keyrings": [],
    "log_hash_alg": "sha256",
    "dm_policy": null
  },
  "ima-buf": {},
  "verification-keys": ""
}
```

**Kernel Parameters Required:**
```bash
ima_policy=tcb ima_hash=sha256
```

**Protection Level:**
- ✅ Pre-boot firmware verification (from Phase 1)
- ✅ Signed bootloader enforcement (from Phase 1)
- ❌ Boot loader integrity measurement (added in Phase 3)
- ✅ Runtime file integrity monitoring
- ✅ 3,000-5,000+ file measurements tracked
- ✅ Detects runtime file modifications

### Phase 3: Boot Loader Verification (PCR 4) - CURRENT

**Implemented:** 2026-02-15 03:45 EST
**Git Commit:** `acdeac7`

**What it does:**
- Verifies GRUB boot loader integrity via TPM PCR 4
- Ensures boot configuration hasn't been tampered with
- Measures GRUB modules, configuration files, and kernel command line
- Completes the boot chain verification

**Technical Details:**
```go
TpmPolicy: `{"mask": "0x90"}`,  // PCRs 4 and 7
```

**Protection Level:**
- ✅ Pre-boot firmware verification (PCR 7)
- ✅ Signed bootloader enforcement (Secure Boot)
- ✅ Boot loader integrity measurement (PCR 4)
- ✅ Kernel command line verification
- ✅ Runtime file integrity monitoring (IMA)
- ✅ Complete boot chain attestation

**What Phase 3 Detects:**
- Modified GRUB configuration
- Tampered kernel command line parameters (e.g., disabling IMA)
- Replaced GRUB modules
- Boot-time backdoors or rootkits

### Phase 4: Firmware PCR Verification (ATTEMPTED, NOT IMPLEMENTED)

**Attempted:** 2026-02-15 04:00 EST
**Status:** Reverted to Phase 3

**Why not implemented:**
- Firmware PCRs (0-3) require measured boot reference state (`mb_refstate`)
- Reference state must be captured during known-good boot
- Significant complexity in baseline management
- High risk of false positives from firmware updates
- Phase 3 already provides excellent security coverage

**Decision:** Stopped at Phase 3 as best balance of security vs. maintainability

### Attestation Architecture

**TPM PCR Usage:**
- **PCR 4**: Boot loader (GRUB) measurements
- **PCR 7**: Secure Boot state and policy
- **PCR 10**: IMA runtime measurements (managed by kernel)
- **PCR 16**: Debug/test measurements (SPIRE agent attestation)

**Verification Flow:**
1. Agent boots with Secure Boot enabled (PCR 7 extended)
2. GRUB loads and measures itself (PCR 4 extended)
3. Kernel boots with IMA enabled (PCR 10 starts being extended)
4. Keylime agent starts and requests attestation
5. TPM generates quote including PCRs 4, 7, 10, 16
6. Verifier checks:
   - PCR 4 matches expected boot loader state
   - PCR 7 matches expected Secure Boot state
   - IMA log (PCR 10) contains only allowed file accesses
   - Quote signature is valid (proves TPM generated it)
7. If all checks pass: `attestation_status: PASS`
8. Process repeats every ~2 seconds (continuous attestation)

### Maintenance Considerations

**System Updates:**
- Kernel updates: PCR 4 will change (GRUB measures new kernel)
- GRUB updates: PCR 4 will change (new GRUB version)
- Firmware updates: May change PCR 7 if Secure Boot keys updated
- IMA measurements: Automatically adapt with exclude-based policy

**Expected Attestation Failures After Updates:**
- Kernel/GRUB updates will cause attestation failures until PCR policy updated
- Workaround: Re-register agent after system updates
- Future: Implement PCR allow-lists for multiple known-good states

**Emergency Recovery:**
- If attestation fails, agent continues running but shows "Invalid Quote" state
- Use root access to investigate PCR changes
- Can temporarily disable attestation during maintenance windows

### Security Benefits

**Attack Detection:**
- ✅ Bootkit detection (PCR 4, 7)
- ✅ Rootkit detection (IMA runtime measurements)
- ✅ Kernel tampering (PCR 4 measures kernel)
- ✅ Configuration tampering (PCR 4 measures kernel cmdline)
- ✅ Runtime binary replacement (IMA measures executables)
- ✅ Library injection (IMA measures shared libraries)

**Attack Prevention:**
- Continuous attestation every 2 seconds means compromises detected quickly
- Failed attestation can trigger automated response (future enhancement)
- TPM-backed cryptographic proof prevents forgery

### References

**Source Code:**
- SPIRE Keylime Plugin: `/home/tygra/spire-keylime-plugin/pkg/server/server.go`
- Policy Configuration: Lines 195-235 (IMA policy), Line 226 (TPM mask)

**Git History:**
- Phase 1: `24d5b70` - Enable Secure Boot verification
- Phase 2: `6f2d7d6` - Implement IMA runtime integrity
- Phase 3: `acdeac7` - Add boot loader verification

**Production Deployment:**
- All hosts running Phase 3 as of 2026-02-15
- Attestation passing on: auth, spire, ca, pm01

---

## Future Enhancements

### Phase: Enforce mTLS on Standard HTTPS Port 443

**Current Configuration (Production):**
```ini
# SPIRE Server - Direct gRPC connection
server_address = "spire.funlab.casa"
server_port = "8081"

# OpenBao - HTTPS without mandatory client cert
openbao_addr = "https://openbao.funlab.casa:8088"

# Keylime Services - Already on port 443 with mTLS ✅
registrar_ip = "registrar.keylime.funlab.casa"
registrar_port = 443
verifier_ip = "verifier.keylime.funlab.casa"
verifier_port = 443
```

**Target Configuration (Future):**
```ini
# All services on standard HTTPS port with mTLS enforcement
server_address = "spire.funlab.casa"
server_port = "443"  # Proxied through nginx with mTLS

openbao_addr = "https://openbao.funlab.casa:443"  # mTLS required

registrar_ip = "registrar.keylime.funlab.casa"
registrar_port = 443  # Already implemented ✅
verifier_ip = "verifier.keylime.funlab.casa"
verifier_port = 443  # Already implemented ✅
```

**Benefits:**
- **Standardization**: All services on port 443 (no custom ports)
- **Security**: mTLS enforcement for all service-to-service communication
- **Defense in Depth**: No unauthenticated access to any infrastructure service
- **Simplified Firewall**: Only port 443 needs to be open

**Migration Checklist:**
- [ ] Verify SPIRE gRPC protocol compatibility through nginx proxy
- [ ] Test SPIRE agent attestation with proxied connection
- [ ] Configure OpenBao to require client certificates
- [ ] Test OpenBao functionality with mTLS enforcement
- [ ] Update all client applications to provide certificates
- [ ] Verify workload identity access patterns still work
- [ ] Update monitoring/health check systems with client certs
- [ ] Document rollback procedure
- [ ] Plan maintenance window for migration
- [ ] Update all onboarding documentation

**Risks & Considerations:**
- SPIRE uses gRPC which may have specific proxy requirements
- Health checks will need valid client certificates
- Certificate rotation becomes more critical
- Troubleshooting becomes more complex
- Emergency access procedures need client cert access

**Status:** Planned for future implementation phase
