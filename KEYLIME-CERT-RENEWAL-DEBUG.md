# Keylime Certificate Renewal Failure - Root Cause Analysis

**Date:** 2026-02-12
**Issue:** Agent certificate on auth.funlab.casa expired without renewal
**Status:** ✅ **RESOLVED**

---

## Executive Summary

The automated Keylime certificate renewal failed on auth.funlab.casa because the renewal script used `BAO_ADDR` environment variable, but the `bao` CLI binary on that host was actually Vault v1.18.3, which only recognizes `VAULT_ADDR`.

**Root Cause:** Environment variable mismatch between renewal script and CLI tool
**Impact:** Agent certificate expired, breaking attestation
**Resolution:** Updated renewal script to use `VAULT_ADDR` instead of `BAO_ADDR`
**Time to Resolve:** ~30 minutes of investigation

---

## Timeline of Events

### February 11, 2026
- **01:42:30** - Initial certificates issued for all Keylime components (24-hour TTL)
- **01:42:31** - Agent, Registrar, and Verifier certificates all valid

### February 12, 2026
- **00:58:35** - First renewal attempt on auth host **FAILED**
  - Error: `dial tcp 127.0.0.1:8200: connect: connection refused`
  - Script tried to connect to localhost instead of spire.funlab.casa

- **02:12:04** - Agent certificate **EXPIRED**
  - Certificate no longer valid
  - Keylime attestation broken for auth host

- **02:27:40** - Second renewal attempt on auth host **FAILED**
  - Same error: connection refused to localhost
  - No certificate renewal

- **07:41:39** - Verifier and Registrar certificates on spire host **RENEWED SUCCESSFULLY**
  - Why did spire succeed but auth fail?

- **14:19:11** - Agent certificate **RENEWED SUCCESSFULLY** (after fix)
  - Script updated to use `VAULT_ADDR`
  - Certificate valid for 24 hours

---

## Root Cause Analysis

### The Problem

The renewal script `/usr/local/bin/renew-keylime-certs.sh` uses these environment variables:

```bash
export BAO_ADDR=https://spire.funlab.casa:8200
export BAO_SKIP_VERIFY=true
export BAO_TOKEN=${BAO_TOKEN:-$(cat /root/.openbao-token 2>/dev/null || echo "")}
```

However, the `bao` CLI tool behavior differs between hosts:

### Host Comparison

| Host | `bao` Binary | Version | Recognizes |
|------|--------------|---------|------------|
| **spire.funlab.casa** | OpenBao | v2.5.0 | `BAO_ADDR` ✅ |
| **auth.funlab.casa** | Vault | v1.18.3 | `VAULT_ADDR` only ❌ |
| **ca.funlab.casa** | Vault | v1.18.3 | `VAULT_ADDR` only ❌ |

### Why spire Succeeded

The spire host renewal worked because:
1. **OpenBao binary:** Recognizes `BAO_ADDR` environment variable
2. **Local connection:** Connects to `https://127.0.0.1:8200` (OpenBao runs locally)
3. **Root token:** Has full access to PKI

```bash
# spire script configuration (WORKS)
export BAO_ADDR=https://127.0.0.1:8200  # OpenBao running locally
```

### Why auth Failed

The auth host renewal failed because:
1. **Vault binary:** Only recognizes `VAULT_ADDR`, ignores `BAO_ADDR`
2. **Remote connection:** Needs to connect to spire host (OpenBao is remote)
3. **Environment variable ignored:** Falls back to default `127.0.0.1:8200`
4. **Connection refused:** No OpenBao running locally on auth

```bash
# auth script configuration (BROKEN)
export BAO_ADDR=https://spire.funlab.casa:8200  # Ignored by Vault binary!
# Falls back to default: 127.0.0.1:8200 (connection refused)
```

### Evidence

**Logs from auth host (failed renewal):**
```
Feb 12 02:27:40 auth renew-keylime-certs.sh[195710]: Renewing: agent.keylime.funlab.casa
Feb 12 02:27:40 auth renew-keylime-certs.sh[195719]: Error writing data to pki_int/issue/keylime-services:
  Put "https://127.0.0.1:8200/v1/pki_int/issue/keylime-services":
  dial tcp 127.0.0.1:8200: connect: connection refused
```

**Manual testing confirmed:**
```bash
# Test with BAO_ADDR (FAILS)
$ export BAO_ADDR=https://spire.funlab.casa:8200
$ bao status
Error: dial tcp 127.0.0.1:8200: connect: connection refused

# Test with VAULT_ADDR (WORKS)
$ export VAULT_ADDR=https://spire.funlab.casa:8200
$ bao status
Seal Type       shamir
Initialized     true
Sealed          false
```

---

## The Fix

### Changes Made

Updated renewal script on auth.funlab.casa:

```bash
# BEFORE (broken)
export BAO_ADDR=https://spire.funlab.casa:8200
export BAO_SKIP_VERIFY=true
export BAO_TOKEN=${BAO_TOKEN:-$(cat /root/.openbao-token 2>/dev/null || echo "")}

# AFTER (fixed)
export VAULT_ADDR=https://spire.funlab.casa:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN=${VAULT_TOKEN:-$(cat /root/.openbao-token 2>/dev/null || echo "")}
```

**Change:** `BAO_*` → `VAULT_*` for all environment variables

### Verification

```bash
# Manual test of fixed script
$ sudo /usr/local/bin/renew-keylime-certs.sh

=== Keylime Certificate Renewal ===
Host: auth
Date: Thu Feb 12 02:19:11 PM EST 2026

1. Renewing Agent certificate...
Renewing: agent.keylime.funlab.casa
✅ Certificate renewed: agent.crt

2. Reloading Keylime agent...
✅ Agent reloaded

=== Renewal Complete ===
```

**New certificate:**
```
Subject: CN=agent.keylime.funlab.casa
Valid From: 2026-02-12 19:18:41 GMT
Valid Until: 2026-02-13 19:19:11 GMT (24 hours)
```

---

## Lessons Learned

### 1. Binary Compatibility Matters

**Lesson:** Don't assume CLI tools from the same family use the same environment variables.

- OpenBao forked from Vault but kept `BAO_*` prefixes
- Vault uses `VAULT_*` prefixes
- Both binaries may be named `bao` but behave differently

**Best Practice:** Always verify which binary is installed and what environment variables it expects.

### 2. Test on All Hosts

**Lesson:** A script that works on one host may fail on another due to subtle differences.

**What we missed:**
- spire has OpenBao binary → Uses `BAO_ADDR` ✅
- auth/ca have Vault binary → Use `VAULT_ADDR` ✅
- Same script deployed to all hosts ❌

**Best Practice:** Test deployment scripts on a representative sample of target hosts.

### 3. Fail Fast and Loud

**Lesson:** The renewal script silently failed for 12+ hours before we noticed.

**Improvements needed:**
- ✅ systemd logging (already present)
- ❌ Alert on renewal failures (not implemented)
- ❌ Certificate expiration monitoring (not implemented)
- ❌ Pre-expiration warnings (not implemented)

**Best Practice:**
- Alert when renewals fail
- Monitor certificate expiration
- Send warnings 6+ hours before expiration

### 4. Document Binary Versions

**Lesson:** We didn't document which `bao` binary was deployed to which host.

**Improvement:**
- Document binary versions in deployment guides
- Create inventory of what's installed where
- Version consistency checks

---

## Remaining Work

### Immediate (Today)

- [x] Fix auth host script ✅ COMPLETE
- [ ] Fix ca host script (same issue expected)
- [ ] Update spire host script for consistency (even though it works)
- [ ] Document binary deployment strategy

### Short-term (This Week)

- [ ] Set up certificate expiration monitoring
- [ ] Add alerting for renewal failures
- [ ] Create runbook for manual certificate renewal
- [ ] Test renewal on all hosts

### Long-term (Next Month)

- [ ] Standardize on one binary (OpenBao or Vault)
- [ ] Consider using SPIRE SVIDs for OpenBao authentication instead of root token
- [ ] Implement pre-expiration warnings (6 hours before expiry)
- [ ] Add health checks to verify all certs are valid

---

## Recommended Actions

### For Other Hosts

1. **Check ca.funlab.casa:**
   - Same issue expected (Vault binary, not OpenBao)
   - Update script before next renewal

2. **Update spire.funlab.casa:**
   - Currently works with `BAO_ADDR`
   - Update to `VAULT_ADDR` for consistency
   - Or: Ensure OpenBao binary is used

### For Monitoring

1. **Add Prometheus metrics:**
   - Certificate expiration time (gauge)
   - Last renewal attempt (timestamp)
   - Renewal success/failure (counter)

2. **Add alerts:**
   - Certificate expires in < 6 hours
   - Renewal failed (immediate)
   - No renewal in 24 hours (warning)

### For Documentation

1. **Update deployment docs:**
   - Document binary versions required
   - List environment variables per binary
   - Include verification steps

2. **Create runbook:**
   - Manual certificate renewal procedure
   - Troubleshooting guide
   - Emergency contact info

---

## Commands for Reference

### Check Binary Version
```bash
bao version
# OpenBao: "OpenBao v2.5.0"
# Vault:   "Vault v1.18.3"
```

### Test Connection
```bash
# For OpenBao binary
export BAO_ADDR=https://spire.funlab.casa:8200
bao status

# For Vault binary
export VAULT_ADDR=https://spire.funlab.casa:8200
bao status
```

### Manual Certificate Renewal
```bash
# Run renewal script
sudo /usr/local/bin/renew-keylime-certs.sh

# Verify new certificate
openssl x509 -in /etc/keylime/certs/agent.crt -noout -dates
```

### Check Renewal Timer Status
```bash
systemctl status renew-keylime-certs.timer
systemctl list-timers renew-keylime-certs.timer
```

### View Renewal Logs
```bash
sudo journalctl -u renew-keylime-certs.service --since today
```

---

## Related Documentation

- **Initial mTLS Deployment:** `keylime-mtls-deployment.md`
- **Book of Omens PKI:** `book-of-omens-pki-deployment.md`
- **Sprint 3 Tracker:** `NEXT-STEPS.md`

---

**Analysis By:** Claude Code
**Date:** 2026-02-12
**Time to Debug:** 30 minutes
**Status:** ✅ Resolved and Documented
