# Keylime Agent Source Code Fix

**Date:** 2026-02-11  
**Status:** ✅ SUCCESSFUL  
**Purpose:** Enable Keylime agent to use HTTPS for registrar connections through nginx reverse proxy

---

## Problem Summary

The rust-keylime agent was hardcoded to use HTTP (not HTTPS) for registrar connections, even when TLS certificates were configured. This prevented agents from connecting through the nginx reverse proxy on standard HTTPS port 443.

**Root Causes:**
1. **registrar_client.rs** - TLS logic required ALL three certificates (CA, client cert, client key) to enable HTTPS
2. **main.rs** - AgentRegistrationConfig hardcoded TLS fields to `None`, ignoring config file values
3. **Certificate format** - Agent required PKCS#8 format private keys, but standard PEM keys were provided

---

## Source Code Changes

### Change 1: registrar_client.rs (Lines 227-234)

**File:** `~/rust-keylime/keylime/src/registrar_client.rs`

**Original Code:**
```rust
// Determine if TLS should be used
// TLS is used if all TLS parameters are provided and insecure is not true
let use_tls = self.ca_certificate.is_some()
    && self.certificate.is_some()
    && self.key.is_some()
    && !self.insecure.unwrap_or(false);

let scheme = if use_tls { "https" } else { "http" };
```

**Modified Code:**
```rust
// Determine if TLS should be used
// TLS is used if CA certificate is provided (for server verification)
// OR if all TLS parameters are provided (for full mTLS)
let use_tls = (self.ca_certificate.is_some()
    && self.certificate.is_some()
    && self.key.is_some()
    || self.ca_certificate.is_some())
    && !self.insecure.unwrap_or(false);

let scheme = if use_tls { "https" } else { "http" };
```

**Change:** Now enables HTTPS if just CA cert is present OR if all three certificates are present.

---

### Change 2: main.rs (Lines 635-650)

**File:** `~/rust-keylime/keylime-agent/src/main.rs`

**Original Code:**
```rust
        // Pull model agent does not use TLS for registrar communication
        registrar_ca_cert: None,
        registrar_client_cert: None,
        registrar_client_key: None,
        registrar_insecure: None,
```

**Modified Code:**
```rust
        // Use TLS for registrar communication if configured
        registrar_ca_cert: if config.registrar_tls_enabled && !config.registrar_tls_ca_cert.is_empty() {
            Some(config.registrar_tls_ca_cert.clone())
        } else {
            None
        },
        registrar_client_cert: if config.registrar_tls_enabled && !config.registrar_tls_client_cert.is_empty() {
            Some(config.registrar_tls_client_cert.clone())
        } else {
            None
        },
        registrar_client_key: if config.registrar_tls_enabled && !config.registrar_tls_client_key.is_empty() {
            Some(config.registrar_tls_client_key.clone())
        } else {
            None
        },
        registrar_insecure: None,
```

**Change:** Now reads TLS configuration from config file instead of hardcoding to `None`.

---

## Configuration Changes

### Agent Configuration (/etc/keylime/agent.conf)

**Added fields:**
```ini
registrar_ip = "registrar.keylime.funlab.casa"
registrar_port = 443

registrar_tls_enabled = true
registrar_tls_ca_cert = "/etc/keylime/certs/ca-complete-chain.crt"
registrar_tls_client_cert = "/etc/keylime/certs/agent.crt"
registrar_tls_client_key = "/etc/keylime/certs/agent-pkcs8.key"
```

**Note:** The `registrar_tls_client_key` must point to a PKCS#8 format private key.

### Certificate Format Conversion

The agent requires PKCS#8 format private keys. Convert standard PEM keys:

```bash
sudo openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt \
    -in /etc/keylime/certs/agent.key \
    -out /etc/keylime/certs/agent-pkcs8.key
    
sudo chown keylime:tss /etc/keylime/certs/agent-pkcs8.key
sudo chmod 600 /etc/keylime/certs/agent-pkcs8.key
```

---

## Compilation Instructions

### Prerequisites

Install Rust toolchain:
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
rustup default stable
```

### Build Process

```bash
# Clone repository (if not already cloned)
cd ~
git clone https://github.com/keylime/rust-keylime.git
cd rust-keylime

# Apply source code changes (see above)

# Compile agent
cargo build --release --bin keylime_agent

# Binary location
ls -lh ~/rust-keylime/target/release/keylime_agent
```

**Compilation time:** ~10-15 seconds (after initial dependency download)  
**Binary size:** ~12MB

---

## Installation

```bash
# Backup original agent
sudo cp /usr/local/bin/keylime_agent /usr/local/bin/keylime_agent.original

# Install new agent
sudo cp ~/rust-keylime/target/release/keylime_agent /usr/local/bin/keylime_agent

# Verify installation
/usr/local/bin/keylime_agent --version
```

---

## Verification

### Test Agent Registration

```bash
sudo RUST_LOG=info /usr/local/bin/keylime_agent 2>&1 | tee /tmp/agent_test.log
```

**Expected output:**
```
INFO  keylime::registrar_client > Building Registrar client: scheme=https, registrar=registrar.keylime.funlab.casa:443, TLS=true
INFO  keylime::registrar_client > Requesting registrar API version to https://registrar.keylime.funlab.casa:443/version
INFO  keylime::agent_registration > SUCCESS: Agent <uuid> registered
INFO  keylime::agent_registration > SUCCESS: Agent <uuid> activated
INFO  keylime_agent > Listening on https://0.0.0.0:9002
```

### Key Success Indicators

✅ **scheme=https** (not http)  
✅ **TLS=true** (not false)  
✅ **registrar=registrar.keylime.funlab.casa:443** (nginx proxy)  
✅ **SUCCESS: Agent registered**  
✅ **SUCCESS: Agent activated**

---

## Deployment to Multiple Hosts

### ca.funlab.casa (✅ Complete)
- Source code modified and compiled
- Agent installed and tested
- Successfully registering through nginx proxy

### auth.funlab.casa (⏸️ Pending)
Steps needed:
1. Clone rust-keylime repository
2. Apply source code changes
3. Compile agent
4. Convert private key to PKCS#8
5. Update agent config
6. Install and test

### spire.funlab.casa (⏸️ Pending)
Same steps as auth.funlab.casa

---

## Benefits Achieved

✅ **HTTPS Communication** - Agent now uses HTTPS for registrar connections  
✅ **Standard Port** - Agents connect through port 443 instead of port 8890  
✅ **Nginx Proxy** - All traffic goes through reverse proxy for consistency  
✅ **Service-Specific DNS** - Clean URLs like registrar.keylime.funlab.casa  
✅ **TLS Termination** - Nginx handles TLS, simplifies certificate management  
✅ **Configurable** - TLS can be enabled/disabled via config file

---

## Files Modified

### Source Code
- `~/rust-keylime/keylime/src/registrar_client.rs` - TLS detection logic
- `~/rust-keylime/keylime-agent/src/main.rs` - Config field mapping

### Configuration
- `/etc/keylime/agent.conf` - Added registrar_tls_* fields
- `/etc/keylime/certs/agent-pkcs8.key` - Created PKCS#8 format key

### Binary
- `/usr/local/bin/keylime_agent` - Replaced with modified version
- `/usr/local/bin/keylime_agent.original` - Backup of original

---

## Troubleshooting

### Agent shows TLS=false

**Cause:** Config fields not being read  
**Fix:** Ensure main.rs reads from config.registrar_tls_* fields

### Failed to add client identity error

**Cause:** Private key not in PKCS#8 format  
**Fix:** Convert key using `openssl pkcs8 -topk8` command

### AllAPIVersionsRejected error

**Cause:** Agent sending HTTP to HTTPS port  
**Fix:** Ensure use_tls logic in registrar_client.rs allows HTTPS

### Connection refused

**Cause:** Port mismatch  
**Fix:** Ensure agent config uses port 443 (nginx) not 8890

---

## Next Steps

1. ✅ Apply fix to ca.funlab.casa (COMPLETE)
2. ⏸️ Apply fix to auth.funlab.casa
3. ⏸️ Apply fix to spire.funlab.casa
4. ⏸️ Update TASK-7-ANALYSIS.md status to ✅ Complete
5. ⏸️ Update NGINX-REVERSE-PROXY-COMPLETE.md
6. ⏸️ Commit all changes to infrastructure repository

---

**Status:** Source code fix validated and working on ca.funlab.casa! 🎉
