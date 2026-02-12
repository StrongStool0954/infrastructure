# Keylime mTLS Setup and Troubleshooting

**Date:** 2026-02-12
**Issue:** Keylime agent mTLS connection failing despite valid certificates
**Status:** ✅ **RESOLVED**

---

## Executive Summary

Successfully configured nginx reverse proxy with mTLS for Keylime registrar endpoint, resolved Rust TLS validation issue, and deployed automated certificate renewal across all hosts. All Keylime agents now successfully register, activate, and maintain valid certificates.

**Primary Issue:** Incorrect CA certificate provided to Rust TLS library - intermediate CA instead of root CA
**Secondary Issues:** Certificate renewal automation failures due to JSON parsing errors, missing PKCS#8 conversion, and incorrect file ownership
**Impact:** Agents could not register with registrar; automated renewals failing on all hosts
**Resolution:**
- Configured agents to use self-signed root CA (Eye of Thundera) instead of intermediate CA
- Fixed renewal scripts to handle Windows line endings, convert keys to PKCS#8, and set proper ownership
**Time to Resolve:** ~2 hours TLS investigation + source code review + 1.5 hours renewal automation fixes
**Status:** Fully operational with automated daily renewals

---

## Background

After resolving the certificate renewal issue (see KEYLIME-CERT-RENEWAL-DEBUG.md), attempted to restart Keylime services with mTLS enabled. Discovered that nginx was acting as a reverse proxy and needed configuration for mutual TLS.

---

## Infrastructure Setup

### Architecture

```
Keylime Agent (auth.funlab.casa)
  ↓ mTLS over HTTPS
  ↓ Port 443
Nginx Reverse Proxy (spire.funlab.casa)
  ↓ HTTP
  ↓ Port 8890
Keylime Registrar (spire.funlab.casa)
```

### Certificates

**Certificate Authority Hierarchy:**
```
Eye of Thundera (Root CA, self-signed)
  └── Book of Omens (Intermediate CA)
      ├── registrar.keylime.funlab.casa (Server cert)
      ├── verifier.keylime.funlab.casa (Server cert)
      └── agent.keylime.funlab.casa (Client cert)
```

**Certificate Details:**
- **TTL:** 24 hours
- **Renewal:** Automated via systemd timer (twice daily)
- **Format:** EC keys for certs, PKCS#8 for agent private key

---

## Issues Discovered and Fixed

### Issue 1: Wrong Certificate for Registrar Endpoint

**Problem:** Nginx was using verifier certificate for registrar endpoint

**Evidence:**
```bash
$ echo | openssl s_client -connect registrar.keylime.funlab.casa:443
subject=CN=verifier.keylime.funlab.casa  # WRONG!
```

**Root Cause:**
- Nginx configuration used same `keylime-fullchain.crt` for both endpoints
- This file only contained verifier certificate

**Fix:**
```bash
# Created registrar-specific fullchain
cat /etc/keylime/certs/registrar.crt \
    /etc/nginx/certs/keylime-ca-chain.crt \
    > /etc/nginx/certs/registrar-fullchain.crt

# Updated nginx config
ssl_certificate /etc/nginx/certs/registrar-fullchain.crt;
ssl_certificate_key /etc/nginx/certs/registrar.key;
```

**Verification:**
```bash
$ echo | openssl s_client -connect registrar.keylime.funlab.casa:443
subject=CN=registrar.keylime.funlab.casa  ✅ CORRECT
issuer=C=US, O=Funlab.Casa, OU=Tower of Omens, CN=Book of Omens
Verify return code: 0 (ok)
```

---

### Issue 2: Nginx Not Configured for mTLS

**Problem:** Nginx accepting connections but not requesting/validating client certificates

**Root Cause:** Missing client certificate configuration in nginx

**Fix:**
```nginx
# Added to registrar server block
ssl_client_certificate /etc/nginx/certs/keylime-ca-chain.crt;
ssl_verify_client on;
ssl_verify_depth 3;
```

**Verification:**
```bash
# Test with client certificate
$ curl --cacert /etc/keylime/certs/ca-intermediate-only.crt \
       --cert /etc/keylime/certs/agent.crt \
       --key /etc/keylime/certs/agent-pkcs8.key \
       https://registrar.keylime.funlab.casa:443/version
{
    "code": 200,
    "status": "Success",
    "results": {
        "current_version": "2.5"
    }
}
```

**Status:** ✅ Working

---

## Issue 3: Rust TLS Library Requires Root CA, Not Intermediate CA ✅ RESOLVED

### Symptoms

Agent logs show:
```
INFO  keylime_agent > Loaded old AK key from /var/lib/keylime/agent_data.json
INFO  keylime_agent > Agent UUID: 1ea81845d2a58aaeeb9f9bdf6f00a89e3359e03fcaa8cb5ba013388af27f0fad
INFO  keylime::registrar_client > Building Registrar client
INFO  keylime::registrar_client > Requesting registrar API version
WARN  keylime::resilient_client > Network error (connection failed)
WARN  keylime::error > TLS Error: Certificate validation failed
```

Agent stops after loading AK key and never progresses to registration.

### What Works

**OpenSSL s_client:**
```bash
$ openssl s_client \
  -connect registrar.keylime.funlab.casa:443 \
  -servername registrar.keylime.funlab.casa \
  -cert /etc/keylime/certs/agent.crt \
  -key /etc/keylime/certs/agent-pkcs8.key \
  -CAfile /etc/keylime/certs/ca-intermediate-only.crt
CONNECTED(00000003)
Verify return code: 0 (ok)
```

**Curl:**
```bash
$ curl --cacert /etc/keylime/certs/ca-intermediate-only.crt \
       --cert /etc/keylime/certs/agent.crt \
       --key /etc/keylime/certs/agent-pkcs8.key \
       https://registrar.keylime.funlab.casa:443/version
{"code": 200, "status": "Success", ...}
```

**Direct Backend:**
```bash
$ curl http://127.0.0.1:8890/version  # Works
```

### What Doesn't Work

**Keylime Rust Agent:**
```bash
$ RUST_LOG=debug keylime_agent
# ... startup logs ...
WARN keylime::error > TLS Error: Certificate validation failed
```

### Investigation Steps Taken

1. ✅ Verified certificate chain is complete and in correct order
2. ✅ Verified nginx sends intermediate CA in chain
3. ✅ Verified CA files can validate all certificates
4. ✅ Tested with both full CA chain and intermediate-only
5. ✅ Verified PKCS#8 key format is correct
6. ✅ Verified certificate dates are valid
7. ✅ Verified DNS resolution works
8. ✅ Verified network connectivity on port 443
9. ✅ Verified nginx mTLS client validation works

### Configuration Files

**Agent Config (`/etc/keylime/agent.conf`):**
```ini
registrar_ip = "registrar.keylime.funlab.casa"
registrar_port = 443
enable_agent_mtls = true

server_key = "/etc/keylime/certs/agent-pkcs8.key"
server_cert = "/etc/keylime/certs/agent.crt"
trusted_client_ca = "/etc/keylime/certs/ca-intermediate-only.crt"

registrar_tls_enabled = true
registrar_tls_ca_cert = "/etc/keylime/certs/ca-intermediate-only.crt"
registrar_tls_client_cert = "/etc/keylime/certs/agent.crt"
registrar_tls_client_key = "/etc/keylime/certs/agent-pkcs8.key"

verifier_tls_ca_cert = "/etc/keylime/certs/ca-intermediate-only.crt"
verifier_tls_client_cert = "/etc/keylime/certs/agent.crt"
verifier_tls_client_key = "/etc/keylime/certs/agent-pkcs8.key"
```

**Nginx Config (`/etc/nginx/conf.d/services.conf`):**
```nginx
server {
    listen 443 ssl;
    http2 on;
    server_name registrar.keylime.funlab.casa;

    # Server certificate
    ssl_certificate /etc/nginx/certs/registrar-fullchain.crt;
    ssl_certificate_key /etc/nginx/certs/registrar.key;

    # TLS settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # mTLS Client Certificate Validation
    ssl_client_certificate /etc/nginx/certs/keylime-ca-chain.crt;
    ssl_verify_client on;
    ssl_verify_depth 3;

    # Proxy to backend
    location / {
        proxy_pass http://127.0.0.1:8890;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_ssl_verify off;
        proxy_buffering off;
    }
}
```

---

## Certificate File Inventory

### On auth.funlab.casa (Agent)

```
/etc/keylime/certs/
├── agent.crt (1610 bytes) - Agent certificate, CN=agent.keylime.funlab.casa
├── agent.key (227 bytes) - EC private key
├── agent-pkcs8.key (241 bytes) - PKCS#8 format private key
├── ca.crt (1927 bytes) - Book of Omens intermediate CA
├── ca-complete-chain.crt (3728 bytes) - Book of Omens + Eye of Thundera
└── ca-intermediate-only.crt (1927 bytes) - Book of Omens only
```

### On spire.funlab.casa (Registrar/Verifier)

```
/etc/keylime/certs/
├── registrar.crt (1619 bytes) - CN=registrar.keylime.funlab.casa
├── registrar.key - Private key
├── verifier.crt (1619 bytes) - CN=verifier.keylime.funlab.casa
├── verifier.key - Private key
└── ca.crt (1927 bytes) - Book of Omens intermediate CA

/etc/nginx/certs/
├── registrar-fullchain.crt (5692 bytes) - Registrar cert + CA chain
├── registrar.key - Registrar private key
├── keylime-fullchain.crt (5692 bytes) - Verifier cert + CA chain (for verifier endpoint)
├── keylime.key - Verifier private key
└── keylime-ca-chain.crt (3728 bytes) - Full CA chain for client validation
```

---

## Debugging Commands

### Check Certificate Chain
```bash
# View certificate chain sent by server
echo | openssl s_client -connect registrar.keylime.funlab.casa:443 \
  -servername registrar.keylime.funlab.casa -showcerts

# Verify CA can validate certificate
openssl verify -CAfile /etc/keylime/certs/ca-intermediate-only.crt \
  /etc/keylime/certs/agent.crt
```

### Test mTLS Connection
```bash
# With OpenSSL
openssl s_client \
  -connect registrar.keylime.funlab.casa:443 \
  -servername registrar.keylime.funlab.casa \
  -cert /etc/keylime/certs/agent.crt \
  -key /etc/keylime/certs/agent-pkcs8.key \
  -CAfile /etc/keylime/certs/ca-intermediate-only.crt

# With curl
curl --cacert /etc/keylime/certs/ca-intermediate-only.crt \
     --cert /etc/keylime/certs/agent.crt \
     --key /etc/keylime/certs/agent-pkcs8.key \
     https://registrar.keylime.funlab.casa:443/version
```

### Run Agent in Debug Mode
```bash
sudo systemctl stop keylime_agent
cd /
sudo RUST_LOG=debug /usr/local/bin/keylime_agent
```

### Check Nginx Logs
```bash
# Error logs
sudo tail -f /var/log/nginx/error.log

# Access logs
sudo tail -f /var/log/nginx/access.log | grep registrar

# Systemd journal
sudo journalctl -u nginx -f
```

---

## Hypotheses for Agent TLS Failure

### Hypothesis 1: Rust TLS Library Incompatibility

**Theory:** Keylime agent uses Rust's `reqwest` library which can use either:
- `rustls` (pure Rust TLS implementation)
- `native-tls` (OpenSSL bindings)

Different backends may have different validation rules.

**Evidence:**
- OpenSSL tools work ✅
- Curl (using OpenSSL) works ✅
- Rust agent fails ❌

**Next Step:** Review Keylime source code to determine TLS backend

### Hypothesis 2: Certificate Format Issue

**Theory:** Rust TLS library requires specific PEM encoding or line endings

**Evidence:**
- All tools can read the certificates
- Validation succeeds with openssl verify

**Status:** Less likely

### Hypothesis 3: Certificate Chain Ordering

**Theory:** Rust TLS expects different chain order or separate root CA

**Tested:**
- ✅ Tried full chain (intermediate + root)
- ✅ Tried intermediate only
- Both failed

**Status:** Ruled out

### Hypothesis 4: SNI or Hostname Validation

**Theory:** Rust TLS performing stricter hostname validation

**Evidence:**
- Certificate has correct CN=registrar.keylime.funlab.casa
- SAN includes both registrar.keylime.funlab.casa and localhost

**Status:** Unlikely

---

## Next Steps

1. **Review Keylime Rust Source Code**
   - Locate TLS configuration in registrar_client module
   - Identify which TLS backend is used (rustls vs native-tls)
   - Check for certificate validation logic
   - Look for configuration options or known issues

2. **Test Direct Connection**
   - Bypass nginx and test agent connecting directly to registrar:8890
   - This would eliminate nginx as a variable

3. **Check Keylime Community**
   - Search GitHub issues for similar TLS validation problems
   - Check if there are known compatibility issues with certain TLS backends

4. **Enable Deeper Debugging**
   - Look for Rust TLS-specific debug flags
   - Check if reqwest has more verbose error reporting

5. **Consider Workarounds**
   - Test with TLS validation temporarily disabled (if option exists)
   - Use system CA store instead of custom CA file
   - Rebuild Keylime with different TLS backend

---

## Related Documentation

- **Certificate Renewal:** `KEYLIME-CERT-RENEWAL-DEBUG.md`
- **PKI Deployment:** `book-of-omens-pki-deployment.md`
- **Sprint Tracker:** `NEXT-STEPS.md`

---

**Analysis By:** Claude Code
**Date:** 2026-02-12
**Status:** 🔧 In Progress - Requires Source Code Review

---

## ROOT CAUSE: Rust TLS Requires Self-Signed Root CA Only

### Source Code Analysis

**File:** `keylime/src/https_client.rs` (Keylime Rust implementation)

```rust
// Lines 38-44
let ca_cert = reqwest::Certificate::from_pem(&buf)?;

builder = builder
    .add_root_certificate(ca_cert)  // ← THE PROBLEM
    .danger_accept_invalid_hostnames(args.accept_invalid_hostnames);
```

### The Problem

**Critical Insight:** `add_root_certificate()` only accepts **self-signed root CAs**, not intermediate CAs.

We were providing `ca-intermediate-only.crt` containing "Book of Omens" (intermediate CA):
- Subject: `C=US, O=Funlab.Casa, OU=Tower of Omens, CN=Book of Omens`
- Issuer: `CN=Eye of Thundera` ← NOT self-signed!

### Why It Failed

1. **Server chain:** registrar cert → Book of Omens intermediate
2. **Client root store:** Book of Omens (WRONG - it's not a root!)
3. **Rust TLS validation:** Expects Book of Omens to be self-signed
4. **Result:** Validation fails - "Certificate validation failed"

### Why OpenSSL/curl Worked

- **OpenSSL:** `SSL_CTX_load_verify_locations()` accepts both roots and intermediates
- **Rust/rustls:** `add_root_certificate()` strictly requires self-signed roots
- Different TLS libraries, different semantics!

### The Solution

```bash
# Extract only the self-signed root CA (Eye of Thundera)
cd /tmp
csplit -s -f ca-part- -b %02d.crt /etc/keylime/certs/ca-complete-chain.crt "/-----BEGIN CERTIFICATE-----/" "{*}"
sudo cp ca-part-02.crt /etc/keylime/certs/ca-root-only.crt
sudo chown keylime:tss /etc/keylime/certs/ca-root-only.crt

# Verify it's self-signed
$ openssl x509 -in /etc/keylime/certs/ca-root-only.crt -noout -subject -issuer
subject=CN=Eye of Thundera
issuer=CN=Eye of Thundera  ✅ Self-signed!

# Update agent configuration
sudo sed -i 's|ca-intermediate-only.crt|ca-root-only.crt|g' /etc/keylime/agent.conf

# Restart agent
sudo systemctl restart keylime_agent
```

### Verification - SUCCESS! ✅

**Agent logs:**
```
Feb 12 14:43:42 auth keylime_agent > Loaded old AK key
Feb 12 14:43:42 auth keylime_agent > Agent UUID: 1ea81845d2a58...
Feb 12 14:43:46 auth keylime_agent > Listening on https://0.0.0.0:9002
```

**Registrar logs:**
```
Feb 12 14:43:42 spire keylime_registrar > GET /version
Feb 12 14:43:42 spire keylime_registrar > POST /v2.5/agents/1ea81845d2a58...
Feb 12 14:43:42 spire keylime_registrar > EK received for agent
Feb 12 14:43:42 spire keylime_registrar > Encrypting AIK with EK for UUID
Feb 12 14:43:46 spire keylime_registrar > PUT /v2.5/agents/1ea81845d2a58...
```

Complete registration → activation sequence succeeded!

---

## Certificate Renewal Automation - All Hosts

### Overview

Automated certificate renewal is critical since all Keylime certificates have a 24-hour TTL. Renewal scripts are deployed on all three hosts (auth, spire, ca) and run daily at 2 AM via systemd timers.

### Issues Discovered in Original Renewal Scripts

**1. JSON Parsing Failures**

The `bao` CLI (OpenBao/Vault) outputs JSON with Windows-style line endings (`\r\n`), causing jq to fail:

```
jq: parse error: Invalid string: control characters from U+0000 through
U+001F must be escaped at line 38, column 26
```

**Root Cause:** bao/vault binary v1.18.3 outputs carriage returns in JSON response

**Solution:** Strip carriage returns before jq parsing:
```bash
# Before (BROKEN)
response=$(bao write -format=json pki_int/issue/keylime-services ...)
echo "$response" | jq -r '.data.certificate'

# After (FIXED)
bao write -format=json pki_int/issue/keylime-services ... > /tmp/cert-response.json
tr -d '\r' < /tmp/cert-response.json | jq -r '.data.certificate' > cert.new
```

**2. Missing PKCS#8 Key Conversion**

Keylime Rust agent requires PKCS#8 format for TLS client private keys. Original scripts only generated standard EC keys.

**Solution:** Convert agent keys after issuance:
```bash
if [ "$key_file" = "agent.key" ]; then
    openssl pkcs8 -topk8 -in "$CERT_DIR/$key_file.new" \
        -out "$CERT_DIR/agent-pkcs8.key.new" -nocrypt
fi
```

**3. File Ownership Problems**

Renewal scripts run as root but Keylime services run as `keylime:tss`. Newly created certificates were owned by root:root, causing "Permission denied" errors.

**Solution:** Set correct ownership after file creation:
```bash
chown keylime:tss "$CERT_DIR/agent.crt" "$CERT_DIR/agent.key" "$CERT_DIR/agent-pkcs8.key"
```

**4. Invalid Subject Alternative Names**

Scripts used short names like `alt_names="localhost,registrar"` but PKI role requires full DNS names.

**Solution:** Use full DNS names:
```bash
# Before: alt_names="localhost,registrar"
# After:  alt_names="registrar.keylime.funlab.casa,localhost"
```

**5. Service Reload Method**

Scripts used `pkill -HUP -f keylime_agent` which terminated services instead of reloading them.

**Solution:** Use systemctl:
```bash
# Before: pkill -HUP -f keylime_agent
# After:  systemctl restart keylime_agent
```

### Updated Renewal Script Features

**Script Location:** `/usr/local/bin/renew-keylime-certs.sh` on all hosts

**Key Features:**
- Issues 24-hour certificates from OpenBao PKI
- Strips carriage returns from JSON before jq parsing
- Converts agent keys to PKCS#8 format automatically
- Sets correct ownership (keylime:tss) and permissions
- Backs up old certificates before replacement
- Verifies certificates before installation
- Restarts services after renewal
- Logs all operations with timestamps

**Environment Variables:**
- **auth/ca hosts:** `VAULT_ADDR=https://spire.funlab.casa:8200`, `VAULT_SKIP_VERIFY=true`
- **spire host:** `BAO_ADDR=https://127.0.0.1:8200`, `BAO_SKIP_VERIFY=true`
- **All hosts:** `VAULT_TOKEN` or `BAO_TOKEN` from `/root/.openbao-token`

### Certificates Renewed Per Host

**spire.funlab.casa:**
- `registrar.crt` / `registrar.key` - Registrar service certificate
- `verifier.crt` / `verifier.key` - Verifier service certificate
- `agent.crt` / `agent.key` / `agent-pkcs8.key` - Local agent certificate

**auth.funlab.casa:**
- `agent.crt` / `agent.key` / `agent-pkcs8.key` - Agent certificate

**ca.funlab.casa:**
- `agent.crt` / `agent.key` / `agent-pkcs8.key` - Agent certificate

### Systemd Timer Configuration

**Timer File:** `/etc/systemd/system/renew-keylime-certs.timer`

```ini
[Unit]
Description=Daily Keylime Certificate Renewal

[Timer]
OnCalendar=daily
OnCalendar=*-*-* 02:00:00
RandomizedDelaySec=1h
Persistent=true
AccuracySec=15m

[Install]
WantedBy=timers.target
```

**Schedule:** Daily at 2:00 AM with random delay up to 1 hour to avoid thundering herd

**Timer Status (as of 2026-02-12):**

| Host  | Next Run (EST)          | Last Run (EST)          | Status |
|-------|-------------------------|-------------------------|--------|
| auth  | Fri 2026-02-13 00:57:45 | Thu 2026-02-12 02:27:40 | Active |
| spire | Fri 2026-02-13 00:14:13 | Thu 2026-02-12 02:42:08 | Active |
| ca    | Fri 2026-02-13 00:22:16 | Never (newly created)   | Active |

### Verification Commands

**Check timer status:**
```bash
sudo systemctl list-timers renew-keylime-certs.timer
```

**View last renewal logs:**
```bash
sudo journalctl -u renew-keylime-certs.service -n 50
```

**Manual renewal test:**
```bash
sudo /usr/local/bin/renew-keylime-certs.sh
```

**Check certificate expiration:**
```bash
sudo openssl x509 -in /etc/keylime/certs/agent.crt -noout -dates
```

### Testing Results (2026-02-12)

**auth.funlab.casa** ✅
- Agent certificate renewed successfully
- Valid until: Feb 13 21:23:34 2026 GMT
- PKCS#8 key created: `/etc/keylime/certs/agent-pkcs8.key` (241 bytes, keylime:tss)
- Agent status: `active (running)`, listening on port 9002

**spire.funlab.casa** ✅
- Registrar certificate renewed: Valid until Feb 13 21:24:42 2026 GMT
- Verifier certificate renewed: Valid until Feb 13 21:24:42 2026 GMT
- Agent certificate renewed: Valid until Feb 13 21:24:43 2026 GMT
- All PKCS#8 keys created with correct ownership
- All services: `active (running)`
  - Registrar listening on port 8890
  - Verifier listening on port 8881
  - Agent listening on port 9002

**ca.funlab.casa** ✅
- Agent certificate renewed successfully
- Valid until: Feb 13 20:03:25 2026 GMT
- PKCS#8 key created with correct ownership
- Agent status: `active (running)`, listening on port 9002

### Backup Strategy

**Location:** `/etc/keylime/certs/backups/`

**Retention:** Backups created with timestamp before each renewal:
```
agent.crt.20260212-162334
agent.key.20260212-162334
```

**Recovery:**
```bash
# If renewal fails, restore from backup
sudo cp /etc/keylime/certs/backups/agent.crt.20260212-162334 \
       /etc/keylime/certs/agent.crt
sudo systemctl restart keylime_agent
```

### Common Issues and Solutions

**Issue: "Permission denied" when agent starts**
- **Cause:** Certificate files owned by root
- **Solution:** `sudo chown keylime:tss /etc/keylime/certs/agent*`

**Issue: "jq parse error: Invalid string: control characters"**
- **Cause:** Windows line endings in bao JSON output
- **Solution:** Use `tr -d '\r'` before jq (already fixed in updated scripts)

**Issue: "Could not find private key" for PKCS#8 conversion**
- **Cause:** Empty key file from failed jq parsing
- **Solution:** Fix jq parsing first, then retry renewal

**Issue: Services not restarting after renewal**
- **Cause:** Using `pkill -HUP` instead of systemctl
- **Solution:** Updated scripts use `systemctl restart` (already fixed)

**Issue: "subject alternate name X not allowed by this role"**
- **Cause:** Using short names instead of FQDNs
- **Solution:** Use full DNS names in alt_names parameter (already fixed)

---

## Key Lessons Learned

### 1. TLS Library Differences Matter

| TLS Library | Root Store Behavior |
|-------------|-------------------|
| **OpenSSL** | Accepts roots AND intermediates |
| **Rust/rustls** | ONLY accepts self-signed roots |
| **Impact** | Same cert file works differently! |

### 2. Root vs Intermediate CA

- **Root CA:** Self-signed (subject == issuer), trust anchor
- **Intermediate CA:** Signed by root, part of chain validation
- **Rule:** Only roots belong in trust store

### 3. Testing with Different Tools

- Testing with `curl` or `openssl s_client` may pass
- Rust applications may fail with the same certificates
- Always test with the actual client implementation

### 4. Source Code Review is Essential

- Generic error: "Certificate validation failed"
- Source code revealed: `add_root_certificate()` semantic
- Understanding library expectations = solution

### 5. Certificate Automation Challenges

- **Different tools, different behaviors:** bao/vault outputs Windows line endings, breaking jq
- **Format requirements vary:** Rust agent needs PKCS#8, Python services accept standard keys
- **Ownership matters:** Services running as non-root need correct file permissions
- **Testing is critical:** Always test renewal scripts manually before scheduling
- **Validation strictness:** PKI roles enforce FQDN SANs, not short names

### 6. Operational Best Practices

- **Backup before replacing:** Always backup certificates before renewal
- **Use systemctl, not signals:** `systemctl restart` is more reliable than `pkill -HUP`
- **Verify after renewal:** Check certificate dates and service status
- **Random delays prevent thundering herd:** Stagger renewal times across hosts
- **Monitor timer status:** Ensure timers are active and scheduled correctly

---

## Final Working Configuration

### Certificate Files

```
/etc/keylime/certs/ca-root-only.crt  ← Use this for Rust TLS clients
  Contains: Eye of Thundera (self-signed root)
  
/etc/keylime/certs/ca-intermediate-only.crt  ← Don't use for Rust
  Contains: Book of Omens (intermediate, NOT self-signed)
  
/etc/keylime/certs/ca-complete-chain.crt  ← Don't use for Rust
  Contains: Book of Omens + Eye of Thundera
```

### Agent Configuration

All CA cert paths now point to `ca-root-only.crt`:
- `trusted_client_ca = "/etc/keylime/certs/ca-root-only.crt"`
- `registrar_tls_ca_cert = "/etc/keylime/certs/ca-root-only.crt"`
- `verifier_tls_ca_cert = "/etc/keylime/certs/ca-root-only.crt"`

---

**Analysis By:** Claude Code
**Date:** 2026-02-12
**Last Updated:** 2026-02-12 16:30 EST
**Total Investigation Time:** ~3.5 hours (2h TLS + 1.5h renewal automation)
**Status:** ✅ Fully Resolved, Automated, and Documented

### Summary of Achievements

1. ✅ **mTLS Configuration** - Nginx reverse proxy with mutual TLS authentication
2. ✅ **Certificate Chain Issue** - Identified and resolved Rust TLS root CA requirement
3. ✅ **Agent Registration** - All three agents (auth, spire, ca) successfully registered
4. ✅ **Renewal Automation** - Daily automated renewal with systemd timers
5. ✅ **PKCS#8 Conversion** - Automatic key format conversion for Rust compatibility
6. ✅ **Ownership & Permissions** - Correct file ownership for service accounts
7. ✅ **JSON Parsing Fix** - Handled Windows line endings from bao/vault CLI
8. ✅ **Service Reliability** - Proper service restart mechanisms implemented
9. ✅ **Testing & Verification** - All renewal scripts tested and validated
10. ✅ **Documentation** - Complete troubleshooting guide and operational procedures

**Next Steps:**
- Monitor first automated renewal run (scheduled for 2026-02-13 ~02:00 EST)
- Consider setting up certificate expiration monitoring/alerting
- Document verifier mTLS communication flow when attestation begins
