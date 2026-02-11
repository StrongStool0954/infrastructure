# 1Password Service Account Setup - Verified Process

**Date:** 2026-02-11
**Status:** ✅ VERIFIED WORKING (Ca vault) / ❌ NEEDS RECREATION (OpenBao vault)

---

## Working Configuration (Reference)

### ca.funlab.casa - ✅ WORKING
```
Service Account: Funlab.Casa.Ca vault access
Integration ID: SAMUBQSWYRDGNCSRZJ6FXUGZYI
Token Location: /etc/1password/service-account-token
Permissions: 640 root:onepassword
Status: AUTHENTICATED SUCCESSFULLY
```

### spire.funlab.casa - ❌ FAILING (OpenBao vault)
```
Service Account: Funlab.Casa.Openbao vault access (token invalid)
Error: "Signin credentials are not compatible with the provided user auth from server"
Status: NEEDS RECREATION
```

---

## Setup Process (Official 1Password Documentation)

### Step 1: Create Service Account in 1Password

**Via 1Password Web Interface:**

1. Sign in to 1Password.com
2. Navigate to: **Developer** → **Directory**
3. Select **Other** under Infrastructure Secrets Management
4. Select **Create a Service Account**

5. **Configure the service account:**
   - **Name**: Descriptive name (e.g., "Funlab Casa OpenBao Vault Access")
   - **Can create vaults**: No (usually)
   - **Vault access**: Select **specific vaults** only
     - For OpenBao: Grant access to `Funlab.Casa.Openbao` vault ONLY
   - **Vault permissions**: Read or Read/Write as needed
     - ⚠️ **CRITICAL**: Permissions CANNOT be changed later!
   - Click **Create Account**

6. **Save the token IMMEDIATELY:**
   - The wizard shows the token **ONLY ONCE**
   - Click **Save in 1Password**
   - Name: "Service Account Token - OpenBao Vault"
   - Choose a secure vault to store it
   - ⚠️ **DO NOT** store in plaintext anywhere

---

### Step 2: Install on Linux Host

**File Structure:**
```
/etc/1password/
├── service-account-token          (640, root:onepassword)
└── load-service-account.sh        (755, root:root)

/usr/local/bin/
└── op-with-service-account        (755, root:root)
```

**Installation Commands:**

```bash
# 1. Create onepassword group
sudo groupadd onepassword

# 2. Add users to group
sudo usermod -aG onepassword tygra
sudo usermod -aG onepassword <other-users>

# 3. Create directory
sudo mkdir -p /etc/1password

# 4. Store token
echo 'ops_<your-token-here>' | sudo tee /etc/1password/service-account-token > /dev/null

# 5. Set permissions
sudo chmod 640 /etc/1password/service-account-token
sudo chown root:onepassword /etc/1password/service-account-token

# 6. Create wrapper script
sudo tee /usr/local/bin/op-with-service-account > /dev/null << 'EOF'
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

sudo chmod +x /usr/local/bin/op-with-service-account
```

---

### Step 3: Verify Configuration

**Check for conflicting variables:**
```bash
env | grep -i OP_

# Should return nothing or only OP_SERVICE_ACCOUNT_TOKEN
# If you see OP_CONNECT_HOST or OP_CONNECT_TOKEN, unset them:
unset OP_CONNECT_HOST
unset OP_CONNECT_TOKEN
```

**Test authentication:**
```bash
sudo /usr/local/bin/op-with-service-account whoami

# Expected output:
# URL:               https://my.1password.com
# Integration ID:    <26-character-string>
# User Type:         SERVICE_ACCOUNT
```

**List accessible vaults:**
```bash
sudo /usr/local/bin/op-with-service-account vault list

# Should show only the vaults granted during service account creation
```

**List items in vault:**
```bash
sudo /usr/local/bin/op-with-service-account item list --vault "Vault-Name"
```

---

## Troubleshooting

### Error: "Signin credentials are not compatible with the provided user auth from server"

**Root Cause:**
- Service account token is invalid or was not created properly
- Token format incompatible with current OP CLI version
- Service account permissions incorrectly configured

**Solution:**
1. **Delete** the existing service account in 1Password web interface
2. **Create NEW** service account following Step 1 exactly
3. **Test immediately** after creation
4. If still fails, contact 1Password support

### Error: "no account found for filter"

**Cause:** No token configured or token file not readable

**Solution:**
```bash
# Check token file exists and is readable
ls -la /etc/1password/service-account-token

# Should show: -rw-r----- 1 root onepassword 853 <date>

# Check you're in onepassword group
groups

# Add yourself if needed
sudo usermod -aG onepassword $(whoami)
newgrp onepassword
```

### Error: "Cannot read /etc/1password/service-account-token"

**Cause:** User not in onepassword group or wrong permissions

**Solution:**
```bash
# Check permissions
ls -la /etc/1password/service-account-token

# Fix permissions
sudo chmod 640 /etc/1password/service-account-token
sudo chown root:onepassword /etc/1password/service-account-token

# Add user to group
sudo usermod -aG onepassword <username>

# Apply group membership (logout/login or use newgrp)
newgrp onepassword
```

---

## Working vs Non-Working Token Comparison

### Working Token (Ca vault)
```
✅ Integration ID visible in `op whoami`
✅ Vault list shows accessible vaults
✅ Item list works
✅ Authentication succeeds on all hosts
```

### Non-Working Token (OpenBao vault)
```
❌ Authentication fails immediately
❌ Error: "Signin credentials are not compatible"
❌ Fails on multiple hosts (not host-specific)
❌ Fails with clean config (not cache issue)
```

**Conclusion:** Token itself is invalid, not a configuration problem.

---

## Security Best Practices

### Token Storage
- ✅ **DO**: Store in `/etc/1password/service-account-token` with 640 permissions
- ✅ **DO**: Use `onepassword` group for access control
- ✅ **DO**: Keep token in 1Password vault as backup
- ❌ **DON'T**: Store in plaintext in scripts
- ❌ **DON'T**: Commit to git repositories
- ❌ **DON'T**: Share via email or chat

### Permissions
- **Service account**: Grant MINIMUM necessary vault access
- **File permissions**: 640 (rw-r-----)
- **Directory permissions**: 755 (rwxr-xr-x)
- **Group membership**: Only necessary users

### Rotation
- **Regular rotation**: Rotate tokens every 90 days
- **Compromise**: Immediately revoke and recreate if compromised
- **Audit logs**: Monitor usage in 1Password console

---

## Using IDs vs Names

### Why Use IDs
- **Stability**: IDs don't change (names can)
- **Uniqueness**: Avoids conflicts with duplicate names
- **Reliability**: IDs only change when item moves to different account

### Getting IDs

**Vault ID:**
```bash
op vault list
# Output includes 26-character vault IDs
```

**Item ID:**
```bash
op item list --vault "Vault-Name"
# Output includes 26-character item IDs
```

**Accessing by ID:**
```bash
op item get <item-id> --vault <vault-id>
```

---

## Secret Reference Syntax

For programmatic access to specific fields:

```
op://vault-name/item-name/section-name/field-name
```

**Example:**
```bash
# Get password field from OpenBao item
op read "op://Funlab.Casa.Openbao/OpenBao-Unseal-Keys/unseal-keys/key-1"
```

---

## Current Status

### spire.funlab.casa
```
✅ 1Password CLI installed: v2.32.1
✅ Group structure: onepassword (tygra)
✅ Directory structure: /etc/1password/
✅ Wrapper script: /usr/local/bin/op-with-service-account
❌ OpenBao vault token: INVALID - needs recreation
✅ Ca vault token: WORKING (copied from ca.funlab.casa)
```

### ca.funlab.casa
```
✅ 1Password CLI installed: v2.32.1
✅ Service account working: Funlab.Casa.Ca vault
✅ All scripts and structure in place
✅ Reference implementation for other hosts
```

---

## Recommended Actions

### Immediate (OpenBao Vault Access)
1. **Delete** existing OpenBao service account in 1Password
2. **Create NEW** service account following official process
3. **Grant access** to `Funlab.Casa.Openbao` vault ONLY
4. **Set permissions**: Read (or Read/Write if needed)
5. **Save token** in 1Password immediately
6. **Test** with `op whoami` before deploying

### Alternative (Unblock Auto-Unseal)
1. **Manual retrieval**: Get OpenBao unseal keys from 1Password UI
2. **Implement auto-unseal**: Encrypt keys with TPM, configure Keylime
3. **Fix 1Password later**: Recreate service account as separate task

---

## Documentation References

- **1Password Service Accounts**: https://developer.1password.com/docs/service-accounts/get-started/
- **CLI with Service Accounts**: https://developer.1password.com/docs/service-accounts/use-with-1password-cli/
- **CLI Reference**: https://developer.1password.com/docs/cli/reference/
- **Secret Reference Syntax**: https://developer.1password.com/docs/cli/secret-reference-syntax/

---

**Status:** Ca vault working, OpenBao vault needs service account recreation
**Prepared By:** Claude Code Assistant
**Date:** 2026-02-11
