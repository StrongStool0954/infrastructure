# SPIRE + Keylime Host Registration Guide

Complete guide for registering new hosts with SPIRE and Keylime attestation using mTLS with PKCS#8 certificates.

**Date:** 2026-02-14
**Architecture:** SPIRE with Keylime node attestor, all connections using mTLS
**Certificate Authority:** Book of Omens (Intermediate CA, backed by Eye of Thundera root)
**Working Example:** wilykit.funlab.casa

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Certificate Issuance](#certificate-issuance)
3. [Keylime Agent Setup](#keylime-agent-setup)
4. [SPIRE Agent Installation](#spire-agent-installation)
5. [Registration with Keylime](#registration-with-keylime)
6. [SPIRE Agent Attestation](#spire-agent-attestation)
7. [Verification](#verification)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Infrastructure

- **SPIRE Server:** spire.funlab.casa:8081 (SPIFFE mTLS)
- **Keylime Registrar:** registrar.keylime.funlab.casa:443 (mTLS via nginx)
- **Keylime Verifier:** verifier.keylime.funlab.casa:443 (mTLS via nginx)
- **Certificate Authority:** Book of Omens at spire.funlab.casa:8200

### Required on New Host

- TPM 2.0 device at `/dev/tpmrm0`
- Network connectivity to SPIRE server and Keylime services
- Python 3 (for Keylime agent)
- Go 1.21+ (for building SPIRE plugins, if needed)

### Required Files/Access

- Root token for OpenBao (from 1Password: "OpenBao Root Token")
- SPIRE trust bundle from server
- Keylime CA certificate chain
- SPIRE Keylime plugin binaries

---

## Certificate Issuance

### Step 1: Issue Certificate from Book of Omens

On the new host, generate a certificate for Keylime agent:

```bash
export NEW_HOST="newhostname"
export BAO_ADDR='https://openbao.funlab.casa:8088'
export BAO_TOKEN='<root-token-from-1password>'

# Issue certificate with both server and client auth
bao write pki_int/issue/keylime-services \
  common_name="agent.keylime.${NEW_HOST}.funlab.casa" \
  alt_names="localhost" \
  ip_sans="127.0.0.1,<HOST_IP>" \
  ttl=168h \
  format=pem > /tmp/keylime-cert.json

# Extract certificate and key
cat /tmp/keylime-cert.json | jq -r '.data.certificate' > /tmp/agent.crt
cat /tmp/keylime-cert.json | jq -r '.data.private_key' > /tmp/agent-pkcs8.key
cat /tmp/keylime-cert.json | jq -r '.data.ca_chain[]' > /tmp/ca-complete-chain.crt
```

**CRITICAL:** Verify key format is PKCS#8:
```bash
head -1 /tmp/agent-pkcs8.key
# Should show: -----BEGIN PRIVATE KEY-----
# NOT: -----BEGIN EC PRIVATE KEY-----
```

### Step 2: Install Certificates on New Host

```bash
# Create Keylime cert directory
ssh ${NEW_HOST} "sudo mkdir -p /etc/keylime/certs && sudo chown -R keylime:keylime /etc/keylime"

# Copy certificates
scp /tmp/agent.crt ${NEW_HOST}:/tmp/
scp /tmp/agent-pkcs8.key ${NEW_HOST}:/tmp/
scp /tmp/ca-complete-chain.crt ${NEW_HOST}:/tmp/

# Install with correct permissions
ssh ${NEW_HOST} "
  sudo mv /tmp/agent.crt /etc/keylime/certs/
  sudo mv /tmp/agent-pkcs8.key /etc/keylime/certs/
  sudo mv /tmp/ca-complete-chain.crt /etc/keylime/certs/
  sudo chown keylime:tss /etc/keylime/certs/agent-pkcs8.key
  sudo chmod 640 /etc/keylime/certs/agent-pkcs8.key
  sudo chown keylime:keylime /etc/keylime/certs/agent.crt
  sudo chmod 644 /etc/keylime/certs/agent.crt
  sudo chmod 644 /etc/keylime/certs/ca-complete-chain.crt
"
```

### Step 3: Verify Certificate Details

```bash
ssh ${NEW_HOST} "
  openssl x509 -in /etc/keylime/certs/agent.crt -noout -text | grep -A2 'Subject:\|Issuer:\|X509v3 Extended Key Usage'
"
```

Expected output:
```
Issuer: CN=Book of Omens, OU=Tower of Omens, O=Funlab.Casa, C=US
Subject: CN=agent.keylime.newhostname.funlab.casa
X509v3 Extended Key Usage:
    TLS Web Server Authentication, TLS Web Client Authentication
```

---

## Keylime Agent Setup

### Step 1: Install Keylime Agent

```bash
ssh ${NEW_HOST} "
  # Install from package or follow Keylime installation guide
  sudo apt install keylime-agent  # Debian/Ubuntu
  # OR
  sudo dnf install keylime-agent  # Fedora/RHEL
"
```

### Step 2: Configure Keylime Agent

Edit `/etc/keylime/agent.conf` on the new host:

```ini
[agent]
# Agent contact information
cloudagent_ip = <HOST_IP>
cloudagent_port = 9002

# Registrar connection (mTLS)
registrar_ip = registrar.keylime.funlab.casa
registrar_port = 443
registrar_tls_dir = /etc/keylime/certs

# Enable mTLS
enable_agent_mtls = true
mtls_cert = /etc/keylime/certs/agent.crt
mtls_private_key = /etc/keylime/certs/agent-pkcs8.key
mtls_ca_cert = /etc/keylime/certs/ca-complete-chain.crt

# TPM configuration
tpm_ownerpassword = ""
```

### Step 3: Start Keylime Agent

```bash
ssh ${NEW_HOST} "
  sudo systemctl enable keylime_agent
  sudo systemctl start keylime_agent
  sudo systemctl status keylime_agent
"
```

### Step 4: Verify Agent is Running

```bash
ssh ${NEW_HOST} "
  # Check agent is responding
  curl -k https://127.0.0.1:9002/v2.2/agent/info \
    --cert /etc/keylime/certs/agent.crt \
    --key /etc/keylime/certs/agent-pkcs8.key \
    2>/dev/null | python3 -m json.tool
"
```

Expected output should include:
```json
{
  "code": 200,
  "status": "Success",
  "results": {
    "agent_uuid": "<some-uuid>",
    "tpm_hash_alg": "sha256"
  }
}
```

**Save the agent_uuid** - you'll need it for verification later.

---

## SPIRE Agent Installation

### Step 1: Install SPIRE Agent Binary

```bash
# On SPIRE server, copy agent binary to new host
scp /opt/spire/bin/spire-agent ${NEW_HOST}:/tmp/

ssh ${NEW_HOST} "
  sudo mkdir -p /opt/spire/bin /opt/spire/plugins
  sudo mv /tmp/spire-agent /opt/spire/bin/
  sudo chmod 755 /opt/spire/bin/spire-agent
"
```

### Step 2: Install Keylime Attestor Plugin

```bash
# Copy plugin from SPIRE server
scp /opt/spire/plugins/keylime-attestor-agent ${NEW_HOST}:/tmp/

ssh ${NEW_HOST} "
  sudo mv /tmp/keylime-attestor-agent /opt/spire/plugins/
  sudo chmod 755 /opt/spire/plugins/keylime-attestor-agent
"
```

### Step 3: Get SPIRE Trust Bundle (Secure Bootstrap)

```bash
# On SPIRE server, export trust bundle
ssh spire.funlab.casa "sudo /opt/spire/bin/spire-server bundle show -format pem" > /tmp/spire-bundle.pem

# Copy to new host
scp /tmp/spire-bundle.pem ${NEW_HOST}:/tmp/

ssh ${NEW_HOST} "
  sudo mkdir -p /etc/spire/bootstrap
  sudo mv /tmp/spire-bundle.pem /etc/spire/bootstrap/bundle.pem
  sudo chmod 644 /etc/spire/bootstrap/bundle.pem
"
```

### Step 4: Configure SPIRE Agent

Create `/etc/spire/agent.conf` on the new host:

```hcl
agent {
  data_dir = "/var/lib/spire/agent"
  log_level = "INFO"
  server_address = "spire.funlab.casa"
  server_port = "8081"
  socket_path = "/tmp/spire-agent/public/api.sock"
  trust_domain = "funlab.casa"

  # Secure bootstrap - NO insecure connections
  trust_bundle_path = "/etc/spire/bootstrap/bundle.pem"
  insecure_bootstrap = false
}

plugins {
  NodeAttestor "keylime" {
    plugin_cmd = "/opt/spire/plugins/keylime-attestor-agent"
    plugin_checksum = ""  # Leave empty or add checksum for production
    plugin_data {
      tpm_path = "/dev/tpmrm0"

      # Keylime agent connection with mTLS
      keylime_agent_use_tls = true
      keylime_agent_ca_cert = "/etc/keylime/certs/ca-complete-chain.crt"
      keylime_agent_client_cert = "/etc/keylime/certs/agent.crt"
      keylime_agent_client_key = "/etc/keylime/certs/agent-pkcs8.key"
    }
  }

  KeyManager "disk" {
    plugin_data {
      directory = "/var/lib/spire/agent"
    }
  }

  WorkloadAttestor "unix" {
    plugin_data {}
  }
}
```

### Step 5: Create SPIRE Agent Service

Create `/etc/systemd/system/spire-agent.service`:

```ini
[Unit]
Description=SPIRE Agent
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/opt/spire/bin/spire-agent run -config /etc/spire/agent.conf
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Step 6: Create Data Directory

```bash
ssh ${NEW_HOST} "
  sudo mkdir -p /var/lib/spire/agent
  sudo mkdir -p /tmp/spire-agent/public
  sudo chmod 755 /var/lib/spire/agent
"
```

---

## Registration with Keylime

**IMPORTANT:** The SPIRE plugin will automatically register the agent with the Keylime verifier when attestation starts. However, the agent must already be registered in the Keylime registrar.

### Verify Registrar Registration

The Keylime agent should automatically register with the registrar when it starts. Verify:

```bash
# Get agent UUID from earlier step
AGENT_UUID="<uuid-from-agent-info>"

# Check registrar registration (from any host with certs)
curl -k https://registrar.keylime.funlab.casa:443/v2.2/agents/${AGENT_UUID} \
  --cert /etc/keylime/certs/agent.crt \
  --key /etc/keylime/certs/agent-pkcs8.key \
  --cacert /etc/keylime/certs/ca-complete-chain.crt \
  2>/dev/null | python3 -m json.tool
```

Expected output:
```json
{
  "code": 200,
  "status": "Success",
  "results": {
    "agent_id": "<uuid>",
    "aik_tpm": "<base64-encoded-key>",
    "mtls_cert": "-----BEGIN CERTIFICATE-----\n...",
    "ip": "<HOST_IP>",
    "port": 9002
  }
}
```

If not registered, check Keylime agent logs:
```bash
ssh ${NEW_HOST} "sudo journalctl -u keylime_agent -n 50"
```

---

## SPIRE Agent Attestation

### Step 1: Start SPIRE Agent

```bash
ssh ${NEW_HOST} "
  sudo systemctl enable spire-agent
  sudo systemctl start spire-agent
"
```

### Step 2: Monitor Attestation

Watch the logs in real-time:

```bash
ssh ${NEW_HOST} "sudo journalctl -u spire-agent -f"
```

**Successful attestation will show:**
```
level=info msg="Configuring Keylime node attestor (agent-side)" attestor_type=keylime
level=info msg="Keylime node attestor configured successfully" keylime_agent="127.0.0.1:9002" tls_enabled=true
level=info msg="SVID is not found. Starting node attestation"
level=info msg="Keylime Attestation response sent"
level=info msg="Node attestation was successful" spiffe_id="spiffe://funlab.casa/spire/agent/keylime/<uuid>"
level=info msg="Starting Workload and SDS APIs"
```

### Step 3: Check SPIRE Agent Status

```bash
ssh ${NEW_HOST} "sudo systemctl status spire-agent --no-pager -l"
```

Should show: `Active: active (running)`

---

## Verification

### 1. Verify Keylime Verifier Registration

From SPIRE server or any host with Keylime certificates:

```bash
AGENT_UUID="<uuid-from-earlier>"

curl -k https://verifier.keylime.funlab.casa:443/v2.2/agents/${AGENT_UUID} \
  --cert /etc/keylime/certs/agent.crt \
  --key /etc/keylime/certs/agent-pkcs8.key \
  --cacert /etc/keylime/certs/ca-complete-chain.crt \
  2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('Operational State:', data['results']['operational_state'])
print('Attestation Status:', data['results']['attestation_status'])
print('Attestation Count:', data['results']['attestation_count'])
print('V field:', data['results']['v'])
"
```

**Expected output:**
```
Operational State: 3  (or 4 - both are good)
Attestation Status: PASS
Attestation Count: 5 (or higher)
V field: None
```

**Operational States:**
- `3` = Get Quote (actively attesting)
- `4` = Provide V (crypto exchange)
- `7` = Failed (indicates error)

### 2. Verify SPIRE Agent SVID

```bash
ssh ${NEW_HOST} "
  sudo /opt/spire/bin/spire-agent api fetch x509 -socketPath /tmp/spire-agent/public/api.sock
"
```

Should show the agent's SPIFFE ID and X.509 SVID.

### 3. Check mTLS Certificate Chain

```bash
# Verify certificate issuer
openssl x509 -in /etc/keylime/certs/agent.crt -noout -issuer -subject

# Should show:
# issuer=CN=Book of Omens, OU=Tower of Omens, O=Funlab.Casa, C=US
# subject=CN=agent.keylime.<hostname>.funlab.casa
```

### 4. Verify Full Chain

```bash
# Verify certificate validates against CA
openssl verify -CAfile /etc/keylime/certs/ca-complete-chain.crt \
  /etc/keylime/certs/agent.crt

# Should show: /etc/keylime/certs/agent.crt: OK
```

---

## Troubleshooting

### Issue: SPIRE Agent Crashes with "ak_tpm not found"

**Symptom:**
```
level=error msg="Agent crashed" error="nodeattestor(keylime): unable to add agent to verifier: ak_tpm not found in registrar response"
```

**Cause:** Plugin looking for wrong field name in registrar response.

**Solution:** Ensure you're using the fixed plugin (commit 8cd8cb9 or later) that looks for `aik_tpm` instead of `ak_tpm`.

```bash
# Verify plugin version on SPIRE server
ssh spire.funlab.casa "sha256sum /opt/spire/plugins/keylime-attestor-server"
# Should match: 5e8f91bf8a13d6eab33ab969a6011cc8175b479d972bece64285d01cf52b1d58
```

---

### Issue: "No required SSL certificate was sent" (HTTP 400)

**Symptom:**
```
level=error msg="unable to contact Keylime verifier: HTTP 400"
```

**Causes:**
1. Wrong certificate file paths in SPIRE config
2. Certificate doesn't have `clientAuth` Extended Key Usage
3. Configuration variable names don't match HCL struct tags

**Solution:**

**Step 1:** Verify certificate has correct EKU:
```bash
openssl x509 -in /etc/keylime/certs/agent.crt -noout -text | grep -A1 "Extended Key Usage"
# Should show: TLS Web Server Authentication, TLS Web Client Authentication
```

**Step 2:** Check SPIRE server config uses correct variable names:
```hcl
# CORRECT (matches HCL struct tags):
keylime_tls_cert_file = "/etc/keylime/certs/agent.crt"
keylime_tls_key_file = "/etc/keylime/certs/agent-pkcs8.key"

# WRONG (will be ignored):
keylime_tls_client_cert_file = "/etc/keylime/certs/agent.crt"
keylime_tls_client_key_file = "/etc/keylime/certs/agent-pkcs8.key"
```

**Step 3:** Check SPIRE server logs for certificate loading:
```bash
sudo journalctl -u spire-server -n 100 | grep "TLS DEBUG: Loaded client certificate"
```

Should show certificate details with correct issuer (Book of Omens).

---

### Issue: "metadata not found" (HTTP 400)

**Symptom:**
```
KeyError: 'metadata'
Traceback: cloud_verifier_tornado.py, line 696
```

**Cause:** Plugin not sending all required Keylime v2.5 API fields.

**Solution:** Ensure plugin struct includes all required fields:
```go
type KeylimeAddAgentRequest struct {
    // ... existing fields ...
    Metadata                string   `json:"metadata"`
    MBRefstate              string   `json:"mb_refstate"`
    MBPolicyName            string   `json:"mb_policy_name"`
    MBPolicy                string   `json:"mb_policy"`
    IMASignVerificationKeys string   `json:"ima_sign_verification_keys"`
    RevocationKey           string   `json:"revocation_key"`
}
```

Update to plugin version 5e8f91bf or later.

---

### Issue: "Polling thread error" / "binascii.Error: Incorrect padding"

**Symptom:**
```
ERROR:keylime.verifier:Polling thread error for agent ID <uuid>
binascii.Error: Incorrect padding
```

**Cause:** Plugin incorrectly sets V field to "2.5" (API version) instead of leaving it null.

**Root Cause:** The V field in the database should be null initially. Keylime generates the cryptographic V value during the attestation protocol.

**Solution:**

**Step 1:** Ensure plugin does NOT set V field:
```go
// CORRECT:
addReq := KeylimeAddAgentRequest{
    AgentID: agentID,  // V field omitted
    // ... other fields
}

// WRONG:
addReq := KeylimeAddAgentRequest{
    V: "2.5",  // DO NOT SET THIS
}
```

**Step 2:** Delete and re-register agent:
```bash
# Delete from verifier
curl -X DELETE -k https://verifier.keylime.funlab.casa:443/v2.2/agents/${AGENT_UUID} \
  --cert /etc/keylime/certs/agent.crt \
  --key /etc/keylime/certs/agent-pkcs8.key

# Restart SPIRE agent to trigger re-registration
sudo systemctl restart spire-agent
```

**Step 3:** Verify V field is null after registration:
```bash
curl -k https://verifier.keylime.funlab.casa:443/v2.2/agents/${AGENT_UUID} \
  --cert /etc/keylime/certs/agent.crt \
  --key /etc/keylime/certs/agent-pkcs8.key \
  2>/dev/null | python3 -c "
import sys, json
print('V field:', json.load(sys.stdin)['results']['v'])
"
# Should show: V field: None
```

---

### Issue: "Agent already exists" (HTTP 409)

**Symptom:**
```
level=error error="verifier returned error 409: Agent of uuid <uuid> already exists"
```

**Cause:** Agent already registered in verifier from previous attempt.

**Solution:**

**Option 1:** Delete and re-register (if registration is incomplete):
```bash
curl -X DELETE -k https://verifier.keylime.funlab.casa:443/v2.2/agents/${AGENT_UUID} \
  --cert /etc/keylime/certs/agent.crt \
  --key /etc/keylime/certs/agent-pkcs8.key

sudo systemctl restart spire-agent
```

**Option 2:** If agent is properly registered and attesting, this is expected behavior - check verifier status instead.

---

### Issue: "could not find node attestor type 'tpm'"

**Symptom:**
```
level=error error="could not find node attestor type 'tpm'"
```

**Cause:** SPIRE agent config specifies wrong attestor type.

**Solution:** Ensure agent config uses `NodeAttestor "keylime"`:
```hcl
# CORRECT:
NodeAttestor "keylime" {
    plugin_cmd = "/opt/spire/plugins/keylime-attestor-agent"
}

# WRONG:
NodeAttestor "tpm" {
    plugin_cmd = "/opt/spire/plugins/keylime-attestor-agent"
}
```

---

### Issue: Certificate/Key Format Issues

**Symptom:**
```
unable to set private key file: 'agent-pkcs8.key' type PEM
```

**Cause:** Key is not in PKCS#8 format or has incorrect permissions.

**Verification:**
```bash
# Check key header
head -1 /etc/keylime/certs/agent-pkcs8.key

# CORRECT: -----BEGIN PRIVATE KEY-----
# WRONG:   -----BEGIN EC PRIVATE KEY-----
# WRONG:   -----BEGIN RSA PRIVATE KEY-----
```

**Solution:** Re-issue certificate from OpenBao, which provides PKCS#8 by default.

**If you need to convert an existing key:**
```bash
# Convert EC key to PKCS#8
openssl pkcs8 -topk8 -nocrypt \
  -in old-ec-key.pem \
  -out agent-pkcs8.key
```

---

### Issue: "trust_bundle_path or trust_bundle_url must be configured"

**Symptom:**
```
level=error error="trust_bundle_path or trust_bundle_url must be configured"
```

**Cause:** Agent configured with `insecure_bootstrap = false` but no trust bundle provided.

**Solution:**

**Step 1:** Get trust bundle from SPIRE server:
```bash
ssh spire.funlab.casa "sudo /opt/spire/bin/spire-server bundle show -format pem" > spire-bundle.pem
```

**Step 2:** Copy to agent:
```bash
scp spire-bundle.pem ${NEW_HOST}:/etc/spire/bootstrap/bundle.pem
```

**Step 3:** Update agent config:
```hcl
agent {
    trust_bundle_path = "/etc/spire/bootstrap/bundle.pem"
    insecure_bootstrap = false
}
```

---

### Debugging Tips

#### 1. Check SPIRE Server Logs

```bash
ssh spire.funlab.casa "sudo journalctl -u spire-server -f"
```

Look for:
- `"Configuring Keylime node attestor (server-side)"` - Plugin loading
- `"TLS DEBUG: Server requested client certificate"` - mTLS working
- `"Successfully added agent to verifier"` - Registration complete
- `"Keylime Attestation Successful"` - Attestation passed

#### 2. Check Keylime Verifier Logs

```bash
ssh spire.funlab.casa "sudo journalctl -u keylime_verifier -f"
```

Look for:
- `Authorization GRANTED` - mTLS authentication working
- `POST returning 200 response for adding agent` - Agent added successfully
- `PCR(s) 16 from bank 'sha256' found` - TPM quote received
- `No remaining PCRs in quote to check` - All checks passed

#### 3. Check Keylime Agent Logs

```bash
ssh ${NEW_HOST} "sudo journalctl -u keylime_agent -f"
```

Look for:
- `GET /v2.2/agent/info` - Agent responding to requests
- `keylime_agent::agent_handler > GET info returning 200` - Successful responses

#### 4. Test mTLS Connection Manually

```bash
# Test connection to verifier with certificates
python3 << 'EOF'
import http.client, ssl, json

ctx = ssl.create_default_context()
ctx.load_cert_chain('/etc/keylime/certs/agent.crt',
                    '/etc/keylime/certs/agent-pkcs8.key')
ctx.load_verify_locations('/etc/keylime/certs/ca-complete-chain.crt')

conn = http.client.HTTPSConnection('verifier.keylime.funlab.casa', 443, context=ctx)
conn.request('GET', '/v2.2/agents/')
response = conn.getresponse()
print(f'Status: {response.status}')
print(response.read().decode())
EOF
```

Expected: `Status: 200` with JSON response.

#### 5. Verify Certificate Trust Chain

```bash
# Full chain validation
openssl verify -CAfile /etc/keylime/certs/ca-complete-chain.crt \
  -untrusted /etc/keylime/certs/ca-complete-chain.crt \
  /etc/keylime/certs/agent.crt
```

---

## Configuration Reference

### Complete SPIRE Server NodeAttestor Config

```hcl
NodeAttestor "keylime" {
  plugin_cmd = "/opt/spire/plugins/keylime-attestor-server"
  plugin_checksum = "5e8f91bf8a13d6eab33ab969a6011cc8175b479d972bece64285d01cf52b1d58"
  plugin_data {
    keylime_verifier_host = "verifier.keylime.funlab.casa"
    keylime_verifier_port = "443"
    keylime_registrar_host = "registrar.keylime.funlab.casa"
    keylime_registrar_port = "443"
    keylime_tls_ca_cert_file = "/etc/keylime/certs/ca-complete-chain.crt"
    keylime_tls_cert_file = "/etc/keylime/certs/agent.crt"
    keylime_tls_key_file = "/etc/keylime/certs/agent-pkcs8.key"
  }
}
```

### Complete SPIRE Agent NodeAttestor Config

```hcl
NodeAttestor "keylime" {
  plugin_cmd = "/opt/spire/plugins/keylime-attestor-agent"
  plugin_checksum = ""  # Optional
  plugin_data {
    tpm_path = "/dev/tpmrm0"
    keylime_agent_use_tls = true
    keylime_agent_ca_cert = "/etc/keylime/certs/ca-complete-chain.crt"
    keylime_agent_client_cert = "/etc/keylime/certs/agent.crt"
    keylime_agent_client_key = "/etc/keylime/certs/agent-pkcs8.key"
  }
}
```

---

## Success Criteria Checklist

- [ ] Certificate issued from Book of Omens with `clientAuth` and `serverAuth` EKU
- [ ] Certificate in PKCS#8 format (`-----BEGIN PRIVATE KEY-----`)
- [ ] Keylime agent running and responding at port 9002
- [ ] Agent registered in Keylime registrar (check via API)
- [ ] SPIRE agent config uses `NodeAttestor "keylime"` (not "tpm")
- [ ] SPIRE server config uses correct variable names (`keylime_tls_cert_file`, not `keylime_tls_client_cert_file`)
- [ ] Trust bundle configured for secure bootstrap
- [ ] SPIRE agent starts successfully
- [ ] Attestation completes: `"Node attestation was successful"`
- [ ] SPIFFE ID assigned: `spiffe://funlab.casa/spire/agent/keylime/<uuid>`
- [ ] Keylime verifier shows `operational_state: 3` or `4`
- [ ] Keylime verifier shows `attestation_status: PASS`
- [ ] V field in verifier is `null` (not "2.5")

---

## Next Steps After Successful Registration

1. **Create workload entries** for services on this host
2. **Configure workload attestation** (unix, docker, k8s, etc.)
3. **Set up automatic SVID rotation** for workloads
4. **Monitor attestation health** via Keylime verifier
5. **Update monitoring/alerting** to track attestation status

---

## Reference Information

### Network Topology

```
New Host (wilykit)
├── Keylime Agent :9002 (mTLS, PKCS#8)
│   ├── → Keylime Registrar :443 (mTLS registration)
│   └── ← Keylime Verifier :443 (mTLS polling)
│
└── SPIRE Agent
    ├── → Keylime Agent :9002 (mTLS, gets UUID/quotes)
    ├── → SPIRE Server :8081 (SPIFFE mTLS, attestation)
    └── Workload API socket (Unix socket)

SPIRE Server (spire.funlab.casa)
├── → Keylime Registrar :443 (mTLS, query agent data)
├── → Keylime Verifier :443 (mTLS, add agent, check status)
└── ← SPIRE Agents :8081 (SPIFFE mTLS)
```

### Certificate Hierarchy

```
Eye of Thundera (Root CA)
└── Book of Omens (Intermediate CA, YubiKey-backed)
    ├── agent.keylime.funlab.casa (SPIRE server uses)
    ├── agent.keylime.wilykit.funlab.casa (wilykit uses)
    └── agent.keylime.<hostname>.funlab.casa (new hosts)
```

### Ports and Protocols

| Service | Port | Protocol | Authentication |
|---------|------|----------|----------------|
| SPIRE Server | 8081 | gRPC/HTTP2 | SPIFFE mTLS |
| Keylime Registrar | 443 | HTTPS | mTLS (Book of Omens) |
| Keylime Verifier | 443 | HTTPS | mTLS (Book of Omens) |
| Keylime Agent | 9002 | HTTPS | mTLS (Book of Omens) |

### Plugin Versions

| Component | Version | Checksum |
|-----------|---------|----------|
| keylime-attestor-server | 2026-02-14 (8cd8cb9) | 5e8f91bf8a13d6eab33ab969a6011cc8175b479d972bece64285d01cf52b1d58 |
| keylime-attestor-agent | 2026-02-14 (8cd8cb9) | 6773fc5f933582946de8da8e95fb6aadb222311b1eaad712d2d2dff845a3c8c0 |

---

**Document Version:** 1.0
**Last Updated:** 2026-02-14
**Tested With:** wilykit.funlab.casa
**Maintainer:** Infrastructure Team

