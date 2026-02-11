# 1Password Service Account Token - Clean Container Test Results

**Date:** 2026-02-11
**Purpose:** Isolate whether OpenBao vault authentication failure is due to token or environment
**Result:** ✅ **DEFINITIVE: Issue is with the OpenBao vault service account tokens themselves**

---

## Executive Summary

We created **two identical clean LXC containers** and tested both service account tokens using the **exact same installation procedure**. Results:

- **Ca vault token:** ✅ **AUTHENTICATION SUCCESSFUL**
- **OpenBao vault token:** ❌ **AUTHENTICATION FAILED** (same error as before)

This **definitively proves** the issue is with the OpenBao vault service account tokens, not the installation method, environment, or configuration.

---

## Test Environment

### Container 999: Ca Vault Token Test ✅

```
Host: pm01.funlab.casa
Container: LXC 999 (op-test)
OS: Debian 12 (bookworm) - fresh install
Template: debian-12-standard_12.12-1_amd64.tar.zst
1Password CLI: 2.32.1 (installed from official repo)
Token: Funlab.Casa.Ca service account
Token Size: 853 bytes
Environment: Clean (no OP_ variables, no cache)
Result: ✅ AUTHENTICATION SUCCESSFUL
```

### Container 998: OpenBao Vault Token Test ❌

```
Host: pm01.funlab.casa
Container: LXC 998 (op-test-openbao)
OS: Debian 12 (bookworm) - fresh install
Template: debian-12-standard_12.12-1_amd64.tar.zst (IDENTICAL)
1Password CLI: 2.32.1 (installed from official repo)
Token: Funlab.Casa.Openbao service account
Token Size: 853 bytes (SAME SIZE)
Environment: Clean (no OP_ variables, no cache)
Result: ❌ AUTHENTICATION FAILED
```

---

## Test Procedure (Identical for Both)

Both containers followed the **exact same installation steps**:

### 1. Create Fresh Container
```bash
sudo /usr/sbin/pct create [ID] \
  /var/lib/vz/template/cache/debian-12-standard_12.12-1_amd64.tar.zst \
  --hostname [name] \
  --memory 512 \
  --swap 512 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --rootfs local-lvm:8 \
  --unprivileged 1 \
  --features nesting=1
```

### 2. Install Prerequisites & 1Password CLI
```bash
apt update && apt install -y curl gpg
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] \
  https://downloads.1password.com/linux/debian/amd64 stable main" > \
  /etc/apt/sources.list.d/1password.list
mkdir -p /etc/debsig/policies/AC2D62742012EA22/
curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol > \
  /etc/debsig/policies/AC2D62742012EA22/1password.pol
mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22
curl -sS https://downloads.1password.com/linux/keys/1password.asc > \
  /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
apt update && apt install -y 1password-cli
```

### 3. Create Group Structure
```bash
groupadd onepassword
mkdir -p /etc/1password
chmod 755 /etc/1password
```

### 4. Install Token
```bash
cat > /etc/1password/service-account-token << 'EOF'
[TOKEN HERE]
EOF
chmod 640 /etc/1password/service-account-token
chown root:onepassword /etc/1password/service-account-token
```

### 5. Test Authentication
```bash
export OP_SERVICE_ACCOUNT_TOKEN=$(cat /etc/1password/service-account-token)
op whoami
```

---

## Test Results

### Container 999: Ca Vault Token ✅

**Authentication Command:**
```bash
export OP_SERVICE_ACCOUNT_TOKEN=$(cat /etc/1password/service-account-token)
op whoami
```

**Output:**
```
URL:               https://my.1password.com
Integration ID:    SAMUBQSWYRDGNCSRZJ6FXUGZYI
User Type:         SERVICE_ACCOUNT
```

**Vault Access:**
```bash
op vault list
```
```
ID                            NAME
vrvhn7gi3baw2lkuhrhztjbw7a    Funlab.Casa.Ca
```

**Item Listing:**
```bash
op item list --vault Funlab.Casa.Ca
```
```
ID                            TITLE                                               VAULT
dmg4gpcpniesnt6ivnod5ju6ue    Eye of Thundera - Root CA Certificate               Funlab.Casa.Ca
zqsitjp2v5vs2on5r5azbiyuqa    YubiKey NEO - ca.funlab.casa (SN: 5497305)          Funlab.Casa.Ca
[...9 items total...]
```

**Result:** ✅ **FULL SUCCESS** - Authentication, vault access, and item listing all working

---

### Container 998: OpenBao Vault Token ❌

**Authentication Command:**
```bash
# Test 1: With cache cleared
rm -rf ~/.config/op/
export OP_SERVICE_ACCOUNT_TOKEN=$(cat /etc/1password/service-account-token)
op whoami
```

**Output:**
```
[ERROR] 2026/02/11 20:17:28 Signin credentials are not compatible with the provided user auth from server
```

**Test 2: Verify no conflicting environment variables**
```bash
printenv | grep "^OP_"
# Output: ✅ No OP_ variables
```

**Test 3: Clear cache and retry**
```bash
rm -rf ~/.config/op/
export OP_SERVICE_ACCOUNT_TOKEN=$(cat /etc/1password/service-account-token)
op whoami
```

**Output:**
```
[ERROR] 2026/02/11 20:20:41 Signin credentials are not compatible with the provided user auth from server
```

**Result:** ❌ **AUTHENTICATION FAILED** - Same error in completely clean environment

---

## What We Ruled Out

Based on this clean container test, we have **definitively ruled out** the following as root causes:

### ❌ Environment Variable Conflicts
- **Tested:** No `OP_CONNECT_HOST` or `OP_CONNECT_TOKEN` set
- **Verified:** `printenv | grep "^OP_"` returned nothing
- **Conclusion:** Not the cause

### ❌ Cached Authentication
- **Tested:** Brand new container, no previous authentication
- **Verified:** Deleted `~/.config/op/` and retested
- **Conclusion:** Not the cause

### ❌ Multiple Authentication Methods
- **Tested:** Clean container, never signed in to 1Password app
- **Verified:** No existing sessions or accounts
- **Conclusion:** Not the cause

### ❌ Installation Method
- **Tested:** Exact same installation steps for both tokens
- **Verified:** Ca vault token works, OpenBao vault token fails
- **Conclusion:** Installation method is correct

### ❌ 1Password CLI Version
- **Tested:** Both containers using 2.32.1
- **Verified:** `op --version` returns same version
- **Conclusion:** Not the cause

### ❌ Token Format
- **Tested:** Both tokens are 853 bytes, start with `ops_`
- **Verified:** Byte-for-byte copy, no truncation
- **Conclusion:** Token format is correct

### ❌ Permissions/Group Structure
- **Tested:** Both tokens have 640 root:onepassword
- **Verified:** `ls -la` shows identical permissions
- **Conclusion:** Not the cause

### ❌ Host Environment
- **Tested:** Both containers on same Proxmox host
- **Verified:** Identical hardware, network, OS
- **Conclusion:** Not the cause

---

## Root Cause Analysis

### What IS the Cause? ✅

The **only remaining explanation** is that the **OpenBao vault service account token itself is invalid or incompatible**.

**Evidence:**
1. Same error across **6+ different OpenBao vault tokens** (rotated, regenerated, new)
2. Same error on **3+ different hosts** (ca, spire, clean containers)
3. Same error with **clean environments** (no cache, no conflicts)
4. Same error with **same installation method** that works for Ca vault

**Conclusion:** The OpenBao vault service account was likely **created incorrectly** in the 1Password web interface.

### Possible Issues with OpenBao Service Account Creation

Per 1Password documentation, the following **cannot be changed after creation**:

1. **Vault permissions** (Read vs Read/Write)
2. **Vault access list** (which vaults the account can access)
3. **Service account type** (standard vs custom)

**Hypothesis:** The OpenBao vault service account was created with:
- Incorrect authentication settings
- Incompatible vault permissions
- Malformed credentials during creation
- Or a bug in 1Password service account creation at the time

---

## Token Comparison

### Ca Vault Token (Working) ✅

**Decoded Token Contents:**
```json
{
  "signInAddress": "my.1password.com",
  "userAuth": {
    "method": "SRPG-4096",
    "alg": "PBES2g-HS256",
    "iterations": 650000,
    "salt": "fmDFKdFFP3tOI0ma0QqvTA"
  },
  "email": "joyrdf7lwkqaa@1passwordserviceaccounts.com",
  "srpX": "190258bb2d70dcaebd2a16964945d48d8334f5c07f46ec95bb8e60674f00a0a3",
  "muk": {...},
  "secretKey": "A3-GVJMX2-JB865R-G896Z-VYGL4-J9F3F-LNRFT",
  "throttleSecret": {...},
  "deviceUuid": "z4puvtuigqzsuo5pf5p6jz5fjy"
}
```

**Size:** 853 bytes
**Status:** ✅ Authenticates successfully

### OpenBao Vault Token (Not Working) ❌

**Decoded Token Contents:**
```json
{
  "signInAddress": "my.1password.com",
  "userAuth": {
    "method": "SRPG-4096",
    "alg": "PBES2g-HS256",
    "iterations": 650000,
    "salt": "1OD-iaXKAOgwz99Uaq2uFg"
  },
  "email": "3p4osubb3b5gc@1passwordserviceaccounts.com",
  "srpX": "f5bc8b36704d1d099d738f2b99d3accc9fd6bd92831fdd31324a2c8492e693eb",
  "muk": {...},
  "secretKey": "A3-E8YP22-6MGH6A-R7STQ-6DKHQ-FTFXM-TLMW4",
  "throttleSecret": {...},
  "deviceUuid": "ioqkyn5s6rxa6gjkf46btendqy"
}
```

**Size:** 853 bytes (same size)
**Status:** ❌ "Signin credentials are not compatible with the provided user auth from server"

**Structural Differences:** None - both have identical JSON structure
**Field Differences:** Only the unique values (email, srpX, secrets, UUIDs) differ as expected

---

## Recommended Solution

### Option A: Recreate OpenBao Service Account (Recommended)

**Steps:**

1. **Access 1Password Web Interface**
   - Go to https://my.1password.com
   - Navigate to: Developer → Directory

2. **Delete Existing OpenBao Service Account**
   - Find: "Funlab.Casa.Openbao vault access" (or similar name)
   - Click: Delete service account
   - Confirm deletion

3. **Create NEW Service Account Following Official Wizard EXACTLY**
   - Click: "Create a Service Account"
   - Name: "Funlab.Casa.Openbao vault access"
   - Can create vaults: **No**
   - Vault access: Select **Funlab.Casa.Openbao** ONLY
   - Vault permissions: **Read** (or Read/Write if needed)
   - ⚠️ **CRITICAL**: These settings **cannot be changed later**!
   - Click: "Create Account"

4. **Save Token IMMEDIATELY**
   - Token shown **ONLY ONCE**
   - Click: "Save in 1Password"
   - Store in secure vault as backup
   - **DO NOT close the window until saved**

5. **Test Immediately**
   ```bash
   export OP_SERVICE_ACCOUNT_TOKEN="ops_eyJ..."
   op whoami
   # Should show Integration ID immediately
   ```

6. **If Success, Deploy to Production**
   ```bash
   # On spire.funlab.casa
   echo 'ops_eyJ...' | sudo tee /etc/1password/service-account-token > /dev/null
   sudo chmod 640 /etc/1password/service-account-token
   sudo chown root:onepassword /etc/1password/service-account-token
   sudo /usr/local/bin/op-with-service-account whoami
   ```

---

### Option B: Manual Retrieval + Fix Later (Alternative)

If you need to unblock the OpenBao auto-unseal implementation immediately:

1. **Access 1Password Web UI**
   - Go to https://my.1password.com
   - Navigate to Funlab.Casa.Openbao vault
   - Find: "OpenBao Unseal Keys" (or similar item)

2. **Manually Copy All 5 Unseal Keys**
   - Copy each of the 5 Shamir shares
   - Store securely for auto-unseal implementation

3. **Proceed with Auto-Unseal Implementation**
   - Use manually retrieved keys
   - Implement TPM + Keylime as planned
   - Test reboot survival

4. **Fix 1Password Service Account Later**
   - Recreate service account when time permits
   - Update automation to use new token
   - Keep manual retrieval as fallback

---

## Conclusion

**Definitive Finding:** The OpenBao vault service account tokens are **inherently invalid or incompatible**, as proven by testing in **two isolated clean environments** with **identical installation procedures**.

**What Works:**
- ✅ Installation method (verified with Ca vault token)
- ✅ 1Password CLI 2.32.1 (working correctly)
- ✅ Group and permissions structure (correct)
- ✅ Clean environment (no conflicts or cache issues)

**What Doesn't Work:**
- ❌ All OpenBao vault service account tokens tested (6+ tokens)
- ❌ Across all environments (ca, spire, clean containers)
- ❌ With all troubleshooting steps applied

**Recommended Action:** Delete and recreate the OpenBao vault service account in 1Password web interface following the official creation wizard exactly.

**Alternative Action:** Manually retrieve unseal keys from 1Password UI to unblock auto-unseal implementation, fix service account later.

---

## Clean Container Management

### Keep for Reference
```bash
# Container 999 (Ca vault - working baseline)
sudo /usr/sbin/pct stop 999      # Keep for reference
```

### Clean Up Test Container
```bash
# Container 998 (OpenBao vault - test complete)
sudo /usr/sbin/pct stop 998
sudo /usr/sbin/pct destroy 998   # Can destroy after testing
```

---

**Test Status:** ✅ COMPLETE
**Finding:** DEFINITIVE - Token is invalid
**Next Action:** Recreate OpenBao service account in 1Password
**Blocking:** Cannot access OpenBao vault until service account recreated
