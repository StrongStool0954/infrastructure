# 1Password Service Account Token Troubleshooting

**Date:** 2026-02-10
**Host:** ca.funlab.casa
**Issue:** Service account tokens failing to authenticate

---

## Problem Summary

All three service account tokens provided fail to authenticate on ca.funlab.casa with various errors:

### Token 1 & 2:
```
[ERROR] Signin credentials are not compatible with the provided user auth from server
```

### Token 3 (reportedly "worked in the past"):
```
[ERROR] failed to session.DecodeSACredentials: failed to DecodeSACredentials: invalid credentials provided
```

---

## Root Cause Analysis

### Token Structure Issue

All three tokens contain SRPG-4096 authentication method when decoded:

```json
{
  "signInAddress": "my.1password.com",
  "userAuth": {
    "method": "SRPG-4096",        ← THIS IS THE PROBLEM
    "alg": "PBES2g-HS256",
    "iterations": 650000,
    "salt": "..."
  },
  "email": "...@1passwordserviceaccounts.com",
  "userId": "...",
  "secretKey": "A3-...",
  "accountKeyUuid": "...",
  "accountUuid": "..."
}
```

### Why This is Wrong

**SRPG-4096** is a Secure Remote Password Group authentication method used for **user accounts** that require password-based authentication.

**Service account tokens** should be **bearer tokens** without password authentication data embedded.

### Token 3 Additional Finding

The third token (mpzggaclpv3mk@...) gives a different error: "invalid credentials provided". This suggests:
- The token format might be more correct than tokens 1 & 2
- BUT the token is expired, revoked, or otherwise invalid
- The secretKey "A3-T4VTB7-K5ZWO7-QG6T9-TTPYW-7278C" doesn't work with `op account add`

---

## Environment Verification

✅ **1Password CLI Version:** 2.32.1 (meets minimum requirement of 2.18.0)
✅ **No Conflicting Variables:** No OP_CONNECT_* variables set
✅ **Local Machine (snarf):** Uses regular user account (jon@jonathanloor.com), not service account

---

## Possible Causes

### 1. Wrong Value Copied (Most Likely)
The user may be copying something other than the actual service account bearer token from 1Password.

**Where to find the real token:**
1. Sign in to 1Password web interface
2. Go to **Settings** → **Developer** → **Service Accounts**
3. Find the service account
4. The bearer token is shown **ONCE** at creation time
5. If the token was never saved, it must be **regenerated**

### 2. Token Expired or Revoked
Token 3's "invalid credentials" error suggests it may have been valid but is now expired or revoked.

### 3. Wrong Token Type Created
The tokens may have been created as something other than service accounts (perhaps Connect tokens or session tokens).

---

## Recommended Solutions

### Option A: Verify Service Account Token Source (Recommended)

**Steps:**
1. Log into 1Password web interface (my.1password.com)
2. Navigate to Settings → Developer → Service Accounts
3. Locate the service account for "Funlab.casa.ca" vault
4. Check if a bearer token exists or needs to be generated
5. **If no token shown:** Click to generate a new service account token
6. **Copy the token immediately** (shown only once)
7. Test the new token on ca.funlab.casa

### Option B: Work from Local Machine

Since the local machine (snarf) has working 1Password authentication:

```bash
# On snarf (local machine)
# Generate new Root CA key
# Save to 1Password
# Transfer to ca.funlab.casa via scp

# Then on ca.funlab.casa
# Import key to Yubikey
```

**Pros:**
- Bypasses token authentication issue
- Uses already-working 1Password setup

**Cons:**
- Less automated
- Manual transfer required

### Option C: Regenerate Service Account

If the tokens are truly invalid/expired:

1. Go to 1Password service accounts settings
2. **Revoke** the existing service account (if it exists)
3. **Create a new service account** from scratch
4. Grant it access to the "Funlab.casa.ca" vault
5. **Immediately copy** the bearer token when shown
6. Test on ca.funlab.casa

---

## Testing Procedure

Once you have what you believe is a valid service account token:

```bash
# On ca.funlab.casa
export OP_SERVICE_ACCOUNT_TOKEN="ops_..."

# Test with simple command
op whoami

# Expected output (if successful):
# URL:           my.1password.com
# Email:         ...@1passwordserviceaccounts.com
# User ID:       ...
# Account ID:    ...

# If successful, test vault access
op vault list

# Test reading from Funlab.casa.ca vault
op item list --vault "Funlab.casa.ca"
```

---

## Next Steps After Authentication Works

Once we have working 1Password CLI access on ca.funlab.casa:

1. **Generate Root CA key pair in 1Password** (or generate locally and immediately save)
2. **Export encrypted key** to USB drive (/mnt/usb/)
3. **Import key to Yubikey** on ca.funlab.casa
4. **Configure step-ca** to use Yubikey-backed Root CA
5. **Issue first certificate** to validate setup

---

## Current Status

- ❌ Service account authentication on ca.funlab.casa: **BLOCKED**
- ✅ 1Password authentication on snarf: **WORKING**
- ✅ Yubikey hardware on ca.funlab.casa: **READY**
- ✅ USB drive with CA files: **MOUNTED**
- ⏳ New Root CA generation: **PENDING** (waiting for 1Password access)

---

## Decision Required

**User needs to:**

1. **Choose approach:** Work from local machine (Option B) OR fix service account token (Option A)?
2. **If Option A:** Where in 1Password are you getting these tokens? Can you regenerate?
3. **If Option B:** Proceed with key generation on snarf, manual transfer to ca?

**My Recommendation:** Option B (work from local machine) is faster and unblocks progress. We can fix the service account token issue later as a separate task.

---

## Technical Reference

### Valid Service Account Token Format

A proper service account bearer token should NOT contain SRPG-4096 authentication data. Example structure:

```
ops_<base64-encoded-credentials>
```

When decoded, it should contain authentication credentials but NOT the `userAuth.method: "SRPG-4096"` field.

### 1Password CLI Documentation
- Service Accounts: https://developer.1password.com/docs/service-accounts/
- CLI with Service Accounts: https://developer.1password.com/docs/service-accounts/use-with-1password-cli/

---

**Status:** BLOCKED on authentication
**Blocker:** Invalid service account tokens
**Recommended Next Action:** Option B - Generate keys on snarf, transfer to ca
**Prepared By:** Claude Code Assistant
**Date:** 2026-02-10
