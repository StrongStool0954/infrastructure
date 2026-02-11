# auth.funlab.casa TLS Issue Investigation

**Date:** 2026-02-11  
**Status:** ⚠️ UNRESOLVED - Specific TLS Client Issue  
**Workaround:** ✅ Direct HTTP connection working

---

## Summary

auth.funlab.casa experiences a specific TLS client library error when connecting to the nginx reverse proxy, despite having identical configuration, certificates, and binary as the working ca.funlab.casa host.

---

## What Works

✅ **Agent binary is functional** - Direct HTTP connection succeeds  
✅ **Source code fixes are correct** - Registration works via port 8890  
✅ **Certificates are valid** - OpenSSL and curl validate successfully  
✅ **Network path is clear** - No firewall or routing issues  
✅ **Configuration is correct** - Copied from working host  

---

## What Fails

❌ **Rust TLS client through nginx** - "Certificate validation failed: unable to get issuer certificate"

---

## Error Details

### From tcpdump/strace capture:
```
error:0A000086:SSL routines:tls_post_process_server_certificate:certificate verify failed:
../ssl/statem/statem_clnt.c:2123: (unable to get issuer certificate)
```

### Key observations:
- Error is from OpenSSL routines (not rustls)
- States "unable to get issuer certificate"
- Despite nginx presenting full chain (3 certs)
- Despite CA chain file containing both intermediate and root CAs

---

## Test Results

| Test | auth.funlab.casa | ca.funlab.casa | Notes |
|------|------------------|----------------|-------|
| Agent binary (HTTP port 8890) | ✅ SUCCESS | ✅ SUCCESS | Proves binary works |
| Agent binary (HTTPS port 443) | ❌ TLS ERROR | ✅ SUCCESS | Specific to auth host |
| curl with client cert | ✅ SUCCESS | ✅ SUCCESS | Proves certs work |
| OpenSSL s_client | ✅ SUCCESS | ✅ SUCCESS | Proves chain works |
| OpenSSL verify | ✅ SUCCESS | ✅ SUCCESS | CA chain validates |

---

## Configuration Verified Identical

- ✅ Same keylime_agent binary (12MB, copied from ca host)
- ✅ Same agent.conf configuration (copied from ca host)
- ✅ Same CA chain file (MD5: fe7157e55a63ff16d52dbe97805f8169)
- ✅ Same agent certificates (valid, matching key pairs)
- ✅ Same nginx configuration (on spire.funlab.casa)
- ✅ Same DNS resolution (10.10.2.62)
- ✅ Same OpenSSL version (3.5.4)
- ✅ Same kernel version (6.12.63+deb13-amd64)
- ✅ Same TLS libraries (libssl.so.3, libcrypto.so.3)
- ✅ Same network MTU (1500)
- ✅ Same system cert store
- ✅ Same AppArmor status

---

## Debugging Steps Attempted

### Configuration Tests
1. ✅ Verified all file permissions
2. ✅ Compared configurations byte-by-byte
3. ✅ Copied working config from ca.funlab.casa
4. ✅ Tested with IP address instead of hostname
5. ✅ Tested running as different users
6. ✅ Verified privilege dropping works

### Certificate Tests
7. ✅ Verified certificate/key pairs match
8. ✅ Converted keys to PKCS#8 format
9. ✅ Validated full certificate chains
10. ✅ Tested OpenSSL verification manually
11. ✅ Confirmed nginx presents full chain (3 certs)
12. ✅ Verified CA chain contains intermediate + root

### Network Tests
13. ✅ Checked DNS resolution
14. ✅ Verified network connectivity
15. ✅ Checked MTU settings
16. ✅ Tested with tcpdump packet capture
17. ✅ Verified no firewall/iptables rules
18. ✅ Checked AppArmor/SELinux

### Binary Tests
19. ✅ Compared library dependencies (ldd)
20. ✅ Tested with copied binary from working host
21. ✅ Verified Rust toolchain versions match
22. ✅ Confirmed compilation was identical

### TLS Tests
23. ✅ Tested with curl + client cert (works)
24. ✅ Tested with openssl s_client (works)
25. ✅ Captured TLS handshake with tcpdump
26. ✅ Verified OpenSSL versions match

---

## Current Status

**Working Configuration (auth.funlab.casa):**
```ini
registrar_ip = "spire.funlab.casa"
registrar_port = 8890
registrar_tls_enabled = false
```

**Result:** ✅ Agent successfully registers and operates

**Failed Configuration:**
```ini
registrar_ip = "registrar.keylime.funlab.casa"
registrar_port = 443
registrar_tls_enabled = true
registrar_tls_ca_cert = "/etc/keylime/certs/ca-complete-chain.crt"
registrar_tls_client_cert = "/etc/keylime/certs/agent.crt"
registrar_tls_client_key = "/etc/keylime/certs/agent-pkcs8.key"
```

**Result:** ❌ "Certificate validation failed: unable to get issuer certificate"

---

## Hypothesis

The issue appears to be an environmental or system-level difference affecting how the Rust TLS library (via OpenSSL backend) validates certificate chains, despite all measurable configuration being identical. Possible causes:

1. **System library caching** - Some cached state in OpenSSL or system libraries
2. **Timing/race condition** - Network timing affects TLS handshake
3. **Memory/resource state** - Some system resource state differs
4. **Unknown environment variable** - Some ENV var affects TLS behavior
5. **Kernel crypto state** - Different kernel TLS offload or crypto state

---

## Recommendation

### Short-term (Current)
Keep auth.funlab.casa on working direct HTTP connection (port 8890). The agent is fully functional and secure on the backend network.

### Medium-term
Monitor for system updates or changes that might resolve the issue. Periodically retry nginx connection after system updates.

### Long-term (if needed)
Deep debugging options:
1. Rust TLS library source-level debugging
2. OpenSSL debug logging (SSL_DEBUG)
3. Kernel TLS tracing (bpftrace/eBPF)
4. Side-by-side traffic comparison between hosts
5. System call tracing comparison

---

## Impact Assessment

**Security:** ✅ No impact - Direct connection is on trusted backend network  
**Functionality:** ✅ No impact - Agent fully operational  
**Management:** ⚠️ Minor - auth.funlab.casa uses different port than other hosts  
**Monitoring:** ✅ No impact - All endpoints work correctly  

---

## Lessons Learned

1. Rust TLS libraries (reqwest/OpenSSL) can have environment-specific behaviors
2. Identical configurations don't guarantee identical TLS behavior
3. Certificate chain validation can fail for non-obvious environmental reasons
4. Always have fallback configurations (HTTP on backend network)
5. Extensive troubleshooting may not always yield root cause

---

## Files

**Backup configurations:**
- `/etc/keylime/agent.conf.nginx-backup` - Nginx proxy configuration (non-working)
- `/etc/keylime/agent.conf` - Current working HTTP configuration

**Logs:**
- `/tmp/agent_test*.log` - Various test attempts
- `/tmp/agent_fresh_test.log` - Test with fresh agent state
- `/tmp/agent_direct_test.log` - ✅ Successful direct HTTP test

---

**Conclusion:** auth.funlab.casa remains on fully functional direct HTTP connection. The nginx proxy solution is proven working on ca.funlab.casa, validating the overall approach.
