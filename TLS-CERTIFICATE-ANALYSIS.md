# TLS Certificate Requirements Analysis
## SPIRE Server ↔ Keylime Verifier Integration

**Date:** 2026-02-10
**Focus:** Understanding why TLS handshake fails between SPIRE plugin and Keylime verifier

---

## Problem Statement

SPIRE server plugin successfully:
- ✅ Contacts Keylime agent on remote hosts via HTTP
- ✅ Retrieves agent UUID and attestation data
- ✅ Initiates attestation request to SPIRE server

But SPIRE server plugin fails when:
- ❌ Connecting to Keylime verifier at `https://127.0.0.1:8881`
- ❌ Error: `remote error: tls: unknown certificate authority`

**Key Detail:** Error is "remote error" - the verifier is rejecting the client, not the other way around.

---

## TLS Handshake Flow

### Standard TLS with Client Certificates

```
1. Client Hello (SPIRE plugin)
   └─> Supported cipher suites, TLS version

2. Server Hello (Keylime verifier)
   ├─> Selected cipher suite
   ├─> Server Certificate (verifier.crt)
   └─> Request Client Certificate (optional)

3. Client Certificate (SPIRE plugin)
   ├─> Client certificate (if requested)
   └─> Certificate Verify (signed with client private key)

4. Finished
   └─> Encrypted application data
```

### Current Behavior

```
1. SPIRE plugin → Keylime verifier: Client Hello ✅

2. Keylime verifier → SPIRE plugin:
   ├─> Server Certificate ✅
   └─> Request Client Certificate ✅

3. SPIRE plugin → Keylime verifier:
   ├─> Client certificate: ??? ❓
   └─> Certificate Verify: ??? ❓

4. Keylime verifier response:
   └─> "remote error: tls: unknown certificate authority" ❌
```

**Analysis:** Verifier is rejecting the client certificate (or lack thereof)

---

## What We Know Works

### Test 1: openssl s_client with CA Bundle ✅

```bash
openssl s_client -connect 127.0.0.1:8881 \
  -CAfile /etc/keylime/certs/ca-complete-chain.crt < /dev/null

Result: Verify return code: 0 (ok)
```

**Conclusion:** Server certificate verification works with complete CA chain.

### Test 2: curl with Client Certificate ✅

```bash
sudo curl \
  --cacert /etc/keylime/certs/ca-complete-chain.crt \
  --cert /etc/keylime/certs/verifier.crt \
  --key /etc/keylime/certs/verifier.key \
  https://127.0.0.1:8881/v2.2/agents/cfb94005...

Result: {"code": 404, "status": "agent id not found", "results": {}}
```

**Conclusion:** TLS handshake succeeds with proper client certificate. HTTP 404 is expected (agent not registered with verifier yet).

### Test 3: curl without Client Certificate ✅

```bash
curl --cacert /etc/keylime/certs/ca-complete-chain.crt \
  https://127.0.0.1:8881/v2.2/agents/test

Result: {"errors": [{"status": "403", "title": "Forbidden", "detail": "Action read_agent requires authentication"}]}
```

**Conclusion:** Connection succeeds but requires authentication. Verifier does NOT reject based on missing client cert.

---

## Keylime Verifier Configuration

### Current Settings (`/etc/keylime/verifier.conf`)

```ini
[general]
tls_dir = /etc/keylime/certs
enable_agent_mtls = False
server_cert = verifier.crt
trusted_server_ca = ["ca.crt"]
client_cert = verifier.crt
#trusted_client_ca = ["ca.crt"]  # Currently commented out
```

### Configuration Analysis

| Setting | Value | Effect |
|---------|-------|--------|
| `enable_agent_mtls` | False | Agents don't need client certificates |
| `server_cert` | verifier.crt | Verifier's server certificate |
| `trusted_server_ca` | ca.crt | CA to trust when verifier acts as client |
| `client_cert` | verifier.crt | Cert to use when verifier acts as client |
| `trusted_client_ca` | [commented out] | CA to trust for client certificates |

**Key Question:** Does commenting out `trusted_client_ca` actually disable client cert validation, or does it make validation fail for all clients?

### TLS Request Behavior

From curl verbose output:
```
* TLSv1.3 (IN), TLS handshake, Request CERT (13):
```

**Finding:** Verifier IS requesting client certificates, even with `enable_agent_mtls = False`.

**Hypothesis:** The `enable_agent_mtls` setting only affects agent-to-verifier connections, not verifier's TLS configuration for all connections.

---

## SPIRE Server Plugin Configuration

### Current Settings (`/etc/spire/server.conf`)

```hcl
NodeAttestor "keylime" {
  plugin_cmd = "/opt/spire/plugins/keylime-attestor-server"
  plugin_checksum = "f2559cfeaee68c9dc591a9520e6a0f76a009d66023cb680160b4758d0ee948a6"
  plugin_data {
    keylime_verifier_host = "127.0.0.1"
    keylime_verifier_port = "8881"
    keylime_tls_ca_cert_file = "/etc/keylime/certs/ca-complete-chain.crt"
    keylime_tls_client_cert_file = "/etc/keylime/certs/verifier.crt"
    keylime_tls_client_key_file = "/etc/keylime/certs/verifier.key"
  }
}
```

### Configuration Analysis

**Documented Parameters:**
- `keylime_verifier_host` - ✅ Documented, working
- `keylime_verifier_port` - ✅ Documented, working
- `keylime_tls_ca_cert_file` - ⚠️ Appears to be documented, added during debugging

**Undocumented Parameters (added during debugging):**
- `keylime_tls_client_cert_file` - ❓ Unknown if supported
- `keylime_tls_client_key_file` - ❓ Unknown if supported

**No errors about unknown configuration parameters** - but that doesn't mean they're being used.

---

## Certificate Chain Verification

### Complete CA Chain (`ca-complete-chain.crt`)

```
Certificate 1: Book of Omens (Intermediate CA)
  Subject: C=US, O=Funlab.Casa, OU=Tower of Omens, CN=Book of Omens
  Issuer: CN=Eye of Thundera
  Not Before: Feb 11 01:31:31 2026 GMT
  Not After: Feb  9 01:31:31 2036 GMT

Certificate 2: Eye of Thundera (Root CA)
  Subject: CN=Eye of Thundera
  Issuer: CN=Eye of Thundera (self-signed)
  Not Before: [date]
  Not After: [date]
```

### Verifier Certificate Chain

```
Server Certificate: verifier.keylime.funlab.casa
  Subject: CN=verifier.keylime.funlab.casa
  Issuer: C=US, O=Funlab.Casa, OU=Tower of Omens, CN=Book of Omens

Presented Chain (in TLS handshake):
  1. verifier.keylime.funlab.casa (leaf)
  2. Book of Omens (intermediate)
  [Eye of Thundera root not included - expected]
```

**Verification:** openssl successfully verifies this chain when provided with `ca-complete-chain.crt` containing both intermediate and root.

---

## Possible Root Causes

### 1. SPIRE Plugin Doesn't Support Client Certificates ⭐ MOST LIKELY

**Evidence:**
- No documentation for client cert parameters in SPIRE plugin
- Adding client cert config produced no errors but no change in behavior
- Plugin may be designed for agent-side only (not verifier-side mTLS)

**Test:**
```bash
# Check if plugin even attempts to read cert files
strace -e openat -f /opt/spire/bin/spire-server run -config /etc/spire/server.conf 2>&1 | grep verifier.crt
```

**Resolution:** May require plugin source code modification or different plugin.

### 2. Verifier Requires Specific Client Certificate Attributes

**Possible Requirements:**
- Client certificates must have specific Extended Key Usage (EKU)
- Client certificates must be issued by specific CA
- Client certificates must have specific Subject Alternative Names

**Test:**
```bash
# Check verifier certificate EKU
openssl x509 -in /etc/keylime/certs/verifier.crt -noout -text | grep -A5 "Extended Key Usage"
```

**Resolution:** Issue new certificate with correct EKU for client authentication.

### 3. Verifier Configuration Still Requires Client Certificates

**Issue:** Commenting out `trusted_client_ca` doesn't disable client cert validation, it causes all clients to fail validation.

**Test:**
```python
# Check Keylime source code
# keylime/verifier.py or keylime/tls.py
# Look for how trusted_client_ca is used
```

**Resolution:** Need to fully disable client certificate requirement in verifier, not just comment out CA list.

### 4. Plugin Using Wrong CA Certificate

**Issue:** Plugin might not be reading `ca-complete-chain.crt` or is reading it incorrectly.

**Test:**
```bash
# Verify file permissions
ls -la /etc/keylime/certs/ca-complete-chain.crt

# Verify SPIRE server process can read it
sudo -u spire cat /etc/keylime/certs/ca-complete-chain.crt > /dev/null && echo "Readable"
```

**Resolution:** Fix permissions or move certificate to accessible location.

### 5. Certificate Presented by Plugin is Untrusted

**Issue:** If plugin IS presenting a client certificate, it might not be trusted by verifier.

**Verifier's Perspective:**
```
1. Request client certificate
2. Receive client certificate from SPIRE plugin
3. Check if issuer is in trusted_client_ca list
4. List is empty (commented out)
5. Reject with "unknown certificate authority"
```

**Resolution:** Either:
- Option A: Uncomment and populate `trusted_client_ca` with correct CA
- Option B: Disable client certificate requirement entirely
- Option C: Configure plugin to not send client certificate

---

## Required Testing

### Test 1: Verify Plugin Client Certificate Behavior

**Method:** Use `strace` or network capture to see what plugin sends

```bash
# Terminal 1: Start tcpdump
sudo tcpdump -i lo -w /tmp/spire-keylime.pcap 'port 8881'

# Terminal 2: Trigger attestation
ssh ca "sudo systemctl restart spire-agent"

# Terminal 3: Analyze capture
wireshark /tmp/spire-keylime.pcap
# Look for TLS ClientHello, Certificate messages
```

**Expected Findings:**
- Does plugin send a client certificate?
- If yes, which certificate?
- If no, is that why verifier rejects?

### Test 2: Verify Verifier Client Certificate Requirements

**Method:** Test different verifier configurations

```bash
# Test A: Fully disable client certs (if possible)
# Edit verifier.conf to completely remove client cert validation
# Restart verifier, test SPIRE connection

# Test B: Enable client certs with proper CA
trusted_client_ca = ["ca.crt"]  # Uncomment
# Restart verifier, test SPIRE connection

# Test C: Try different verifier TLS settings
# Check if there's a "require_client_cert = false" option
```

### Test 3: Check Plugin Certificate File Access

```bash
# Use audit or strace
sudo auditctl -w /etc/keylime/certs/verifier.crt -p r
sudo auditctl -w /etc/keylime/certs/verifier.key -p r

# Restart SPIRE server
sudo systemctl restart spire-server

# Check audit log
sudo ausearch -f /etc/keylime/certs/verifier.crt
```

### Test 4: Verify Certificate EKU

```bash
# Check if client certificates need specific EKU
openssl x509 -in /etc/keylime/certs/verifier.crt -noout -text | grep -A10 "Extended Key Usage"

# Expected for client auth:
#   TLS Web Client Authentication
```

---

## Recommended Resolution Path

### Phase 1: Understand Current Behavior (15-20 minutes)

1. **Capture TLS Handshake:**
   ```bash
   sudo tcpdump -i lo -s 0 -w /tmp/tls-capture.pcap 'port 8881' &
   # Trigger SPIRE attestation
   sudo systemctl restart spire-agent
   # Stop capture after 30 seconds
   sudo pkill tcpdump
   # Analyze: tshark -r /tmp/tls-capture.pcap -V | grep -A20 "Certificate"
   ```

2. **Check Plugin File Access:**
   ```bash
   # Monitor what files plugin actually opens
   sudo strace -e openat,open -f $(pgrep keylime-attestor-server) 2>&1 | grep -E '(verifier|ca-)'
   ```

3. **Examine Verifier Logs:**
   ```bash
   # Enable debug logging if possible
   # Check verifier logs during failed connection
   ```

### Phase 2: Test Certificate Configuration (20-30 minutes)

1. **Test verifier without client cert requirement:**
   - Research Keylime documentation for disabling client certs completely
   - Try alternative configuration approaches
   - Test if connection succeeds

2. **If client certs are required:**
   - Check certificate EKU
   - Issue new certificate with client authentication EKU if needed
   - Update verifier configuration with correct trusted CA

3. **If plugin doesn't support client certs:**
   - Research SPIRE community/documentation
   - Check if there's an updated plugin
   - Consider alternative integration approach

### Phase 3: Alternative Approaches (if needed)

1. **Option A: Custom TLS Proxy**
   - Run local proxy that handles mTLS
   - SPIRE plugin connects to proxy without TLS
   - Proxy connects to verifier with proper mTLS

2. **Option B: Python Keylime Agent**
   - Test if Python agent has different SPIRE integration
   - May have more mature plugin support

3. **Option C: Direct Integration**
   - Modify SPIRE plugin source to add proper client cert support
   - Submit patch upstream

---

## Quick Wins to Try First

### 1. Check Verifier Certificate EKU (2 minutes)

```bash
ssh spire "openssl x509 -in /etc/keylime/certs/verifier.crt -noout -text | grep -A5 'Extended Key Usage'"
```

If missing "TLS Web Client Authentication", issue new certificate:

```bash
# Via OpenBao with client auth EKU
ssh spire "sudo bao write -format=json pki_int/issue/keylime-services \
  common_name='verifier.keylime.funlab.casa' \
  alt_names='verifier.funlab.casa' \
  ttl='87600h' \
  ext_key_usage='serverAuth,clientAuth'"
```

### 2. Restore trusted_client_ca in Verifier (3 minutes)

```bash
# Edit verifier config
ssh spire "sudo sed -i 's/#trusted_client_ca/trusted_client_ca/' /etc/keylime/verifier.conf"

# Restart verifier
ssh spire "sudo pkill -f keylime_verifier && sudo keylime_verifier &"

# Test SPIRE attestation
```

### 3. Verify Plugin Reads Certificate Files (5 minutes)

```bash
# Check file permissions
ssh spire "ls -la /etc/keylime/certs/verifier.{crt,key}"

# Make files readable by SPIRE server user
ssh spire "sudo chmod 644 /etc/keylime/certs/verifier.crt"
ssh spire "sudo chgrp spire /etc/keylime/certs/verifier.key"
ssh spire "sudo chmod 640 /etc/keylime/certs/verifier.key"

# Restart SPIRE server
ssh spire "sudo systemctl restart spire-server"
```

---

## Documentation Gaps

**Questions Needing Answers:**

1. Does SPIRE Keylime plugin support client certificate configuration?
   - Check: SPIRE plugin documentation
   - Check: Plugin source code on GitHub

2. What are Keylime verifier's actual client certificate requirements?
   - Check: Keylime documentation
   - Check: Verifier source code

3. Is `enable_agent_mtls = False` the correct way to disable client certs?
   - Check: Keylime configuration documentation
   - Check: Whether separate setting exists for disabling client cert requests

---

## Success Criteria

**Phase 3 Complete When:**

1. ✅ ca.funlab.casa Keylime agent operational with unique UUID
2. ✅ Agent registered with Keylime registrar
3. ❌ SPIRE agent on ca successfully attests using Keylime
4. ❌ ca agent appears in SPIRE server agent list with attestation_type: keylime
5. ❌ Workload SVIDs issued to ca based on Keylime attestation

**Minimum Acceptable:**
- Items 1-2 complete (current state)
- Document TLS issue as known problem
- Proceed to Phase 4 with plan to revisit

**Ideal:**
- All 5 items complete
- Clean TLS connection without errors
- Full SPIRE-Keylime integration working

---

**Analysis Status:** 🟡 DIAGNOSTIC READY
**Next Action:** Execute Quick Wins, then systematic testing if needed
**Estimated Time:** 15-45 minutes depending on findings
**Last Updated:** 2026-02-10 22:10 EST
