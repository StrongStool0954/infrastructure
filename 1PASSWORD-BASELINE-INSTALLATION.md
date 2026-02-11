# 1Password CLI Baseline Installation - Verified Working

**Date:** 2026-02-11
**Test Environment:** Fresh LXC container (ID 999) on pm01.funlab.casa
**Status:** ✅ VERIFIED WORKING

---

## Purpose

This document provides a **verified baseline** installation procedure for 1Password CLI with service account authentication. This procedure was tested in a completely clean Debian 12 LXC container and confirmed working.

---

## Test Environment Details

```
Container: LXC 999 (op-test)
OS: Debian GNU/Linux 12 (bookworm)
Template: debian-12-standard_12.12-1_amd64.tar.zst
1Password CLI: 2.32.1
Service Account: Funlab.Casa.Ca vault access
Status: ✅ AUTHENTICATION SUCCESSFUL
```

---

## Installation Procedure (Verified)

### Step 1: Install Prerequisites

```bash
apt update
apt install -y curl gpg
```

**Verified:** curl and gpg installed successfully

---

### Step 2: Add 1Password Repository

```bash
# Add GPG key
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

# Add repository
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] \
  https://downloads.1password.com/linux/debian/amd64 stable main" > \
  /etc/apt/sources.list.d/1password.list

# Add debsig policy and keyrings
mkdir -p /etc/debsig/policies/AC2D62742012EA22/
curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol > \
  /etc/debsig/policies/AC2D62742012EA22/1password.pol

mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22
curl -sS https://downloads.1password.com/linux/keys/1password.asc > \
  /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
```

**Verified:** Repository added successfully

---

### Step 3: Install 1Password CLI

```bash
apt update
apt install -y 1password-cli
```

**Output:**
```
Get:1 https://downloads.1password.com/linux/debian/amd64 stable/main amd64 1password-cli amd64 2.32.1-1 [10.0 MB]
Setting up 1password-cli (2.32.1-1) ...
```

**Verification:**
```bash
op --version
# Output: 2.32.1
```

**Verified:** 1Password CLI 2.32.1 installed

---

### Step 4: Create Group Structure

```bash
groupadd onepassword
mkdir -p /etc/1password
chmod 755 /etc/1password
```

**Verified:** Group and directory created

---

### Step 5: Install Service Account Token

**CRITICAL: Token must be copied byte-for-byte without modification**

```bash
# Create token file
cat > /etc/1password/service-account-token << 'EOF'
ops_eyJ... [FULL TOKEN HERE]
EOF

# Set permissions
chmod 640 /etc/1password/service-account-token
chown root:onepassword /etc/1password/service-account-token
```

**Verification:**
```bash
ls -la /etc/1password/service-account-token
# Output: -rw-r----- 1 root onepassword 853 Feb 11 20:11 /etc/1password/service-account-token
```

**Important:** Token file size for Ca vault token: 853 bytes

**Verified:** Token installed with correct permissions

---

### Step 6: Create Wrapper Script

```bash
cat > /usr/local/bin/op-with-service-account << 'EOF'
#!/bin/bash
TOKEN_FILE="/etc/1password/service-account-token"

if [ ! -r "$TOKEN_FILE" ]; then
    echo "ERROR: Cannot read $TOKEN_FILE" >&2
    echo "You must be root or a member of the 'onepassword' group" >&2
    exit 1
fi

export OP_SERVICE_ACCOUNT_TOKEN=$(cat "$TOKEN_FILE")
exec /usr/bin/op "$@"
EOF

chmod +x /usr/local/bin/op-with-service-account
```

**Verified:** Wrapper script created

---

### Step 7: Test Authentication

```bash
/usr/local/bin/op-with-service-account whoami
```

**Expected Output:**
```
URL:               https://my.1password.com
Integration ID:    SAMUBQSWYRDGNCSRZJ6FXUGZYI
User Type:         SERVICE_ACCOUNT
```

**Verified:** ✅ Authentication successful

---

### Step 8: Verify Vault Access

```bash
/usr/local/bin/op-with-service-account vault list
```

**Expected Output:**
```
ID                            NAME
vrvhn7gi3baw2lkuhrhztjbw7a    Funlab.Casa.Ca
```

**Verified:** ✅ Can access Ca vault

---

### Step 9: List Items

```bash
/usr/local/bin/op-with-service-account item list --vault Funlab.Casa.Ca
```

**Expected Output:**
```
ID                            TITLE                                               VAULT
dmg4gpcpniesnt6ivnod5ju6ue    Eye of Thundera - Root CA Certificate               Funlab.Casa.Ca
zqsitjp2v5vs2on5r5azbiyuqa    YubiKey NEO - ca.funlab.casa (SN: 5497305)          Funlab.Casa.Ca
...
```

**Verified:** ✅ Can list items in vault

---

## Key Findings

### What Works ✅

1. **Clean Debian 12 installation**
2. **1Password CLI 2.32.1**
3. **Ca vault service account token** (copied byte-for-byte from ca.funlab.casa)
4. **Group-based permissions** (640 root:onepassword)
5. **Wrapper script** for token management
6. **Full vault access** (list vaults, list items)

### Critical Success Factors

1. **Token must be copied exactly** - Special characters like `@` must not be escaped
2. **Permissions must be 640** - Too open or too restrictive will fail
3. **Group ownership** - Must be `root:onepassword`
4. **Token file size** - Ca vault token is exactly 853 bytes
5. **No conflicting environment variables** - Clean environment required

---

## Comparison: Working vs Non-Working

### Working Configuration (Ca Vault)

```
Service Account: Funlab.Casa.Ca vault access
Integration ID: SAMUBQSWYRDGNCSRZJ6FXUGZYI
Token Size: 853 bytes
Installation: Copied from ca.funlab.casa byte-for-byte
Result: ✅ Authentication successful
```

### Non-Working Configuration (OpenBao Vault)

```
Service Account: Funlab.Casa.Openbao vault access
Integration ID: Unknown (authentication fails before retrieval)
Token Size: 853 bytes (same size)
Installation: Multiple attempts with various tokens
Result: ❌ "Signin credentials are not compatible with the provided user auth from server"
```

---

## Next Steps for Troubleshooting

### Test OpenBao Token in Clean Container

Now that we have a verified baseline, we should test an OpenBao vault service account token in this **same clean container** to determine if:

1. **Token is invalid** - If it fails in clean container, token itself is bad
2. **Environment issue** - If it works in clean container, something wrong on spire.funlab.casa
3. **Service account creation** - If all OpenBao tokens fail, service account created incorrectly

### Test Procedure

```bash
# In test container (999)
# Replace Ca vault token with OpenBao vault token
cat > /etc/1password/service-account-token << 'EOF'
[OPENBAO VAULT TOKEN HERE]
EOF

# Test authentication
/usr/local/bin/op-with-service-account whoami

# Expected outcomes:
# - If SUCCESS: Issue is with spire.funlab.casa environment
# - If FAIL: Issue is with OpenBao vault service account tokens themselves
```

---

## Installation Checklist

Use this checklist when installing 1Password CLI with service account:

- [ ] Install prerequisites (curl, gpg)
- [ ] Add 1Password repository and keys
- [ ] Install 1password-cli package
- [ ] Verify version: `op --version` → 2.32.1
- [ ] Create onepassword group: `groupadd onepassword`
- [ ] Create /etc/1password/ directory
- [ ] Copy token byte-for-byte (check @ symbols, etc.)
- [ ] Set permissions: `chmod 640` and `chown root:onepassword`
- [ ] Verify token file size (853 bytes for our tokens)
- [ ] Create wrapper script at /usr/local/bin/op-with-service-account
- [ ] Make wrapper executable: `chmod +x`
- [ ] Test authentication: `op-with-service-account whoami`
- [ ] Verify Integration ID appears
- [ ] Test vault access: `op-with-service-account vault list`
- [ ] Test item listing: `op-with-service-account item list --vault <name>`

---

## File Locations

```
/etc/1password/
├── service-account-token           (640, root:onepassword, 853 bytes)

/usr/local/bin/
└── op-with-service-account         (755, root:root)

/usr/bin/
└── op                              (1Password CLI binary)
```

---

## Expected Authentication Flow

1. **Wrapper script executed** → Reads token from file
2. **Token exported** → Sets OP_SERVICE_ACCOUNT_TOKEN environment variable
3. **OP CLI called** → Uses token for authentication
4. **Token decoded** → Extracts email, credentials, encryption keys
5. **Authentication** → Connects to my.1password.com using SRPG-4096
6. **Success** → Returns Integration ID and grants vault access

---

## Token Format (Reference)

Valid 1Password service account tokens have this structure:

```
ops_eyJ...
│   └─ Base64-encoded JSON containing:
│      ├─ signInAddress: "my.1password.com"
│      ├─ userAuth: {method: "SRPG-4096", ...}
│      ├─ email: "<uuid>@1passwordserviceaccounts.com"
│      ├─ srpX: "<hex-encoded-value>"
│      ├─ muk: {encryption key}
│      ├─ secretKey: "A3-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"
│      ├─ throttleSecret: {seed, uuid}
│      └─ deviceUuid: "<uuid>"
```

**Size:** Typically 850-860 bytes
**Format:** `ops_` prefix followed by base64-encoded JSON

---

## Common Mistakes to Avoid

1. **❌ Escaping @ symbols** - Will cause "isn't an email address" error
2. **❌ Wrong permissions** - 600 or 644 will work but not best practice
3. **❌ Missing group** - Token won't be accessible to service users
4. **❌ Conflicting env vars** - OP_CONNECT_HOST can interfere
5. **❌ Cached config** - Old ~/.config/op/ can cause issues
6. **❌ Version mismatch** - Ensure 2.32.1 on all systems
7. **❌ Truncated token** - Must be complete (check byte count)

---

## Test Container Details

### Container Configuration

```
VMID: 999
Hostname: op-test
OS: Debian 12 (bookworm)
Memory: 512MB
Storage: 8GB (local-lvm)
Network: vmbr0 (DHCP)
Type: Unprivileged LXC
Features: nesting=1
```

### Container Management

```bash
# On pm01.funlab.casa
sudo /usr/sbin/pct start 999      # Start container
sudo /usr/sbin/pct stop 999       # Stop container
sudo /usr/sbin/pct status 999     # Check status
sudo /usr/sbin/pct exec 999 -- <command>  # Execute command
```

### Container Cleanup (When Done Testing)

```bash
# Stop and destroy test container
sudo /usr/sbin/pct stop 999
sudo /usr/sbin/pct destroy 999
```

---

## Conclusion

This baseline installation procedure is **verified working** in a completely clean environment. The Ca vault service account token authenticates successfully and provides full vault access.

**Success criteria met:**
- ✅ Clean installation from scratch
- ✅ Authentication successful
- ✅ Vault access working
- ✅ Item listing working
- ✅ All steps documented
- ✅ All commands verified

**Use this document as the reference implementation** for 1Password CLI with service account authentication.

---

**Status:** ✅ BASELINE VERIFIED
**Test Date:** 2026-02-11 20:12 EST
**Test Container:** LXC 999 (op-test) on pm01.funlab.casa
**Tested By:** Infrastructure Team
