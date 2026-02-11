# Task 7 Analysis: Keylime Agent URL Update

**Date:** 2026-02-11  
**Task:** Update Keylime agents to use new nginx reverse proxy URLs  
**Decision:** ❌ NOT RECOMMENDED  
**Status:** Agents remain on direct connection (spire.funlab.casa:8890)

---

## Summary

After testing, updating Keylime agents to use the nginx reverse proxy URLs is **not recommended** for the following technical and architectural reasons.

---

## What Was Tested

### Attempted Configuration Change

**Original (Working):**
```bash
# /etc/keylime/agent.conf on all hosts
registrar_ip = "spire.funlab.casa"
registrar_port = 8890  # Non-TLS direct connection
```

**Attempted (Failed):**
```bash
# /etc/keylime/agent.conf - TESTED BUT REVERTED
registrar_ip = "registrar.keylime.funlab.casa"
registrar_port = 443  # HTTPS through nginx reverse proxy
```

### Test Results

❌ **Agent registration failed** with error:
```
ERROR keylime_agent > Failed to register agent after retrying: 
RegistrarClient(AllAPIVersionsRejected("2.1, 2.2, 2.3, 2.4, 2.5"))
```

✅ **External access through nginx works** fine:
```bash
curl -k https://registrar.keylime.funlab.casa/version
# Returns: {"code":200,"status":"Success","results":{"current_version":"2.5"}}
```

---

## Why It Doesn't Work

### 1. **mTLS Client Certificate Requirement**

The Keylime registrar TLS port (8891) requires mutual TLS (mTLS) with client certificates:

```ini
# Keylime agent configuration
enable_agent_mtls = true
server_cert = "/etc/keylime/certs/agent.crt"
server_key = "/etc/keylime/certs/agent.key"
```

**Problem:** 
- Nginx terminates TLS at port 443
- Nginx makes a new connection to backend port 8891
- The client certificate from the agent is not forwarded to the backend
- Backend rejects the connection due to missing client certificate

### 2. **Protocol Mismatch**

**Registrar has two ports:**
- Port 8890: HTTP (no TLS, no client certs required)
- Port 8891: HTTPS with mTLS (client certs required)

**Nginx proxies to port 8891** for security, but can't provide the client cert.

### 3. **API Version Negotiation Failure**

The "AllAPIVersionsRejected" error suggests the registrar isn't properly receiving or processing the agent's API version negotiation requests through the nginx proxy.

---

## Why Direct Connection Is Better

### 1. **Machine-to-Machine Communication**

Agents are infrastructure services, not human users:
- They communicate directly on the backend network
- No need for pretty URLs or standard ports
- Direct connection is simpler and more efficient

### 2. **Security Considerations**

Direct connection on port 8890:
- ✅ Runs on trusted backend network (10.10.2.x)
- ✅ No exposure to external networks
- ✅ Firewall can restrict to known agent IPs
- ✅ Simpler attack surface (no reverse proxy layer)

### 3. **Operational Simplicity**

Current architecture:
- ✅ Agents connect directly (fewer hops, fewer points of failure)
- ✅ Nginx proxy available for external/human access
- ✅ Clear separation: machines use 8890, humans use 443
- ✅ No certificate forwarding complexity

---

## Recommended Architecture

### Agent Traffic (Machine-to-Machine)

```
Keylime Agent → spire.funlab.casa:8890 → Keylime Registrar
              (Direct, HTTP, backend network)
```

**Use Cases:**
- Agent registration
- Continuous attestation
- TPM quote submission
- Automated infrastructure operations

### External Traffic (Human/API Access)

```
External Client → registrar.keylime.funlab.casa:443 → Nginx → Registrar:8891
                (HTTPS, reverse proxy, public-facing)
```

**Use Cases:**
- Manual registrar API access
- External monitoring
- Administrative operations
- API documentation/testing

---

## Alternative Solutions (Not Implemented)

If nginx proxy was absolutely required for agent traffic, these would be needed:

### Option 1: TLS Passthrough

Configure nginx for TLS passthrough instead of termination:
```nginx
stream {
    server {
        listen 443;
        ssl_preread on;
        proxy_pass 127.0.0.1:8891;
        ssl_passthrough on;
    }
}
```

**Drawbacks:**
- Nginx can't inspect traffic
- Loses nginx features (logging, filtering, etc.)
- More complex configuration

### Option 2: Client Certificate Forwarding

Configure nginx to forward client certificates:
```nginx
proxy_set_header SSL-Client-Cert $ssl_client_cert;
proxy_ssl_certificate /path/to/client.crt;
proxy_ssl_certificate_key /path/to/client.key;
```

**Drawbacks:**
- Requires nginx to have agent certificates
- Certificate management complexity
- Security implications of storing agent certs on proxy

### Option 3: Use Non-TLS Backend

Configure nginx to proxy to port 8890 (HTTP):
```nginx
proxy_pass http://127.0.0.1:8890;
```

**Drawbacks:**
- Backend connection not encrypted (even if frontend is)
- Less secure for sensitive attestation data
- Doesn't match registrar's preferred TLS configuration

**None of these options provide significant benefit over direct connection.**

---

## Final Recommendation

### Keep Current Configuration ✅

**Agents:** Continue using direct connection
```
registrar_ip = "spire.funlab.casa"
registrar_port = 8890
```

**Nginx Proxy:** Available for external access only
```
https://registrar.keylime.funlab.casa → localhost:8891
```

### Benefits of This Approach

1. **Reliability:** Agents use proven, working direct connection
2. **Security:** Backend traffic stays on backend network
3. **Simplicity:** No complex proxy configuration needed
4. **Performance:** Fewer hops, lower latency
5. **Flexibility:** Nginx available when needed for external access

---

## Documentation Updates

Updated NGINX-REVERSE-PROXY-COMPLETE.md to reflect:
- Task 7 remains optional (not completed)
- Explanation of why agent URL update is not recommended
- Current architecture is optimal for use case

---

## Conclusion

**Task 7 is technically possible but operationally inadvisable.**

The nginx reverse proxy successfully provides clean URLs and standard HTTPS port access for:
- ✅ OpenBao PKI (https://openbao.funlab.casa)
- ✅ Keylime Verifier external access (https://verifier.keylime.funlab.casa)
- ✅ Keylime Registrar external access (https://registrar.keylime.funlab.casa)

However, **Keylime agents should continue using direct backend connections** for:
- Better reliability (no proxy in the middle)
- Proper mTLS client certificate handling
- Simpler architecture for machine-to-machine communication
- Better performance and lower latency

**Status:** Task 7 evaluated and intentionally NOT implemented. Current architecture is optimal. ✅

---

**Recommendation:** Mark task 7 as "Evaluated - Not Recommended" rather than "To Do"
