# Keylime + SPIRE Agent Onboarding Guide

**Purpose:** Step-by-step guide to onboard new hosts with Keylime and SPIRE agents
**Last Updated:** 2026-02-14
**Status:** ✅ PRODUCTION READY - Tested on auth, spire, ca hosts

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Step 1: Generate Certificates](#step-1-generate-certificates)
4. [Step 2: Install and Configure SPIRE Agent](#step-2-install-and-configure-spire-agent)
5. [Step 3: Install and Configure Keylime Agent](#step-3-install-and-configure-keylime-agent)
6. [Step 4: Register with Keylime Verifier](#step-4-register-with-keylime-verifier)
7. [Step 5: Verification](#step-5-verification)
8. [Troubleshooting](#troubleshooting)
9. [Quick Reference](#quick-reference)

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

### 2.3: Create SPIRE Agent systemd Service

```bash
sudo tee /etc/systemd/system/spire-agent.service > /dev/null <<EOF
[Unit]
Description=SPIRE Agent
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/spire-agent run -config /etc/spire/agent/agent.conf
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
sudo systemctl daemon-reload
```

### 2.4: Register SPIRE Agent with Server

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
  -c status | grep -E 'attestation_status|attestation_count'

# Expected:
# "attestation_status": "PASS"
# "attestation_count": <number > 0>

# Watch verifier logs for attestation activity
sudo journalctl -u keylime_verifier -f | grep ${AGENT_UUID}
```

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
```

**Diagnosis:**
```bash
# Check verifier logs
sudo journalctl -u keylime_verifier -f | grep ${AGENT_UUID}
```

**Common Causes:**
1. **TPM PCR values changed:** System updates or reboots
2. **Policy mismatch:** TPM policy doesn't match measured state
3. **Network connectivity:** Agent can't reach verifier

**Solution:**
Check specific error in verifier logs and adjust TPM policy or re-register agent.

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

### Essential Commands

```bash
# Check agent status
sudo systemctl status keylime_agent
sudo systemctl status spire-agent

# View agent UUID
sudo journalctl -u keylime_agent | grep "Agent UUID"

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
```

### Checklist for New Host

- [ ] Generated certificate with `private_key_format=pkcs8`
- [ ] Agent certificate contains 2 certs (leaf + intermediate)
- [ ] Root CA certificate has complete DN (O, OU, C fields)
- [ ] ca-complete-chain.crt contains 2 certs (intermediate + root)
- [ ] Certificate chain validation passes (`openssl verify` returns OK)
- [ ] Certificate files have correct permissions (644 for .crt, 600 for .key)
- [ ] Certificate files owned by keylime:tss
- [ ] SPIRE agent running and registered
- [ ] Keylime agent running and listening on port 9002
- [ ] mTLS handshake succeeds (verify return code: 0)
- [ ] Agent registered with verifier
- [ ] Attestation status: PASS
- [ ] Attestation count increasing

---

## Example: Complete Onboarding for pm01.funlab.casa

```bash
#!/bin/bash
# Complete onboarding script for pm01.funlab.casa

set -e

# Configuration
HOSTNAME="pm01.funlab.casa"
SHORT_NAME="pm01"
IP_ADDRESS="10.10.2.101"  # Adjust to actual IP

echo "=== Onboarding ${HOSTNAME} ==="

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

---

**Document Status:** ✅ PRODUCTION READY
**Tested On:** auth.funlab.casa, spire.funlab.casa, ca.funlab.casa, pm01.funlab.casa
**Last Updated:** 2026-02-14 10:00 EST
**Known Issues:** Upstream reqwest 0.13 breaks TLS - use custom fork

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
