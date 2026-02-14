# Authentik OIDC Integration Guide

## Overview

This guide covers the Authentik OIDC integration with OpenBao and step-ca, enabling centralized authentication and certificate issuance.

**Last Updated:** 2026-02-14
**Status:** Production Ready

---

## Architecture

```
User Authentication Flow:
┌─────────┐         ┌───────────┐         ┌──────────┐
│ Browser │ ──1──> │ OpenBao/  │ ──2──> │ Authentik│
│         │         │ step-ca   │         │   OIDC   │
└─────────┘         └───────────┘         └──────────┘
     ^                                          │
     │                                          │
     └──────────────5─────────────────4─────────┘
           (Token/Certificate)      (Auth)
```

**Components:**
- **Authentik**: Identity provider (OIDC/OAuth2)
- **OpenBao**: Secrets management with OIDC auth backend
- **step-ca**: Certificate Authority with OIDC provisioner
- **Groups**: Role-based access control via Authentik groups

---

## Access Levels

| Group | OpenBao Access | step-ca Access | Token/Cert Duration |
|-------|---------------|----------------|---------------------|
| `openbao-admins` | Full PKI management | N/A | 1h token (max 4h) |
| `openbao-cert-users` | Certificate issuance only | N/A | 15m token (max 1h) |
| `step-ca-users` | N/A | Certificate requests | 24h cert (max 168h) |
| Default (no groups) | Read-only CA cert | N/A | 15m token |

---

## OpenBao Access

### Web UI Authentication

1. Navigate to: `https://openbao.funlab.casa:8088/ui/`
2. Select **"OIDC"** from Method dropdown
3. Choose your role:
   - `admin` - Full PKI management (requires `openbao-admins` group)
   - `cert-user` - Certificate issuance only (requires `openbao-cert-users` group)
   - `default` - Read-only access
4. Click **"Sign in with OIDC Provider"**
5. Authenticate with your Authentik credentials
6. Authorize the application if prompted

**After Login:**
- Your token policies will be displayed
- Token TTL varies by role (15m - 1h)
- Navigate to **Secrets → pki_int** to manage certificates

### CLI Authentication

**Prerequisites:**
- `bao` CLI installed
- Network access to openbao.funlab.casa

**Setup:**
```bash
export BAO_ADDR='https://openbao.funlab.casa:8088'

# Optional: Configure CA trust or skip verification
export BAO_SKIP_VERIFY=true  # Development only
# OR
export BAO_CACERT=/path/to/root_ca.crt  # Production
```

**Login:**
```bash
# Login with OIDC (opens browser)
bao login -method=oidc role=cert-user

# Verify login
bao token lookup
```

**Expected Output:**
```
Key                  Value
---                  -----
policies             [default pki-issue]
ttl                  14m30s
```

### Issue Certificates via OpenBao

**Via Web UI:**
1. Navigate to: **Secrets → pki_int → Roles**
2. Select role (e.g., `keylime-services`)
3. Click **"Generate certificate"**
4. Enter details:
   - Common Name: `service.funlab.casa`
   - TTL: `24h`
   - IP SANs / DNS SANs: (optional)
5. Click **"Generate"**
6. Download certificate and private key

**Via CLI:**
```bash
# Issue certificate
bao write pki_int/issue/keylime-services \
  common_name="myservice.funlab.casa" \
  ttl=24h \
  ip_sans="10.10.2.100" \
  format=pem

# Save to files
bao write -format=json pki_int/issue/keylime-services \
  common_name="myservice.funlab.casa" \
  ttl=24h | \
  jq -r '.data.certificate' > service.crt

bao write -format=json pki_int/issue/keylime-services \
  common_name="myservice.funlab.casa" \
  ttl=24h | \
  jq -r '.data.private_key' > service.key
```

**Available Roles:**
- `keylime-services` - Keylime infrastructure services
- `nginx-services` - Nginx reverse proxy certificates
- Check OpenBao UI for complete list

---

## step-ca Certificate Issuance

### Prerequisites

**Install step CLI:**
```bash
# Check version (must be >= 0.24.0 for OIDC support)
step version

# Install if needed
wget https://dl.smallstep.com/cli/docs-cli-install/latest/step-cli_amd64.deb
sudo dpkg -i step-cli_amd64.deb
```

**Bootstrap Trust (One-Time Setup):**
```bash
# Get intermediate CA fingerprint
FINGERPRINT=$(ssh ca.funlab.casa "step certificate fingerprint /etc/step-ca/certs/intermediate_ca.crt")

# Bootstrap and install root CA
step ca bootstrap \
  --ca-url https://ca.funlab.casa:8443 \
  --fingerprint "$FINGERPRINT" \
  --install
```

**Verify Bootstrap:**
```bash
# Check root CA is installed
step certificate inspect ~/.step/certs/root_ca.crt
```

### Request Certificate via OIDC

**Basic Request:**
```bash
step ca certificate <common-name> <cert-file> <key-file> \
  --provisioner authentik \
  --force

# Example:
step ca certificate myuser@funlab.casa myuser.crt myuser.key \
  --provisioner authentik \
  --force
```

**What Happens:**
1. Browser opens automatically
2. Redirects to Authentik login
3. Enter your credentials
4. Authorize step-ca access
5. Certificate is issued and saved locally

**With Additional SANs:**
```bash
step ca certificate myservice.funlab.casa service.crt service.key \
  --provisioner authentik \
  --san service.internal.funlab.casa \
  --san 10.10.2.50 \
  --force
```

**Custom Duration:**
```bash
# Request certificate with specific duration (max 168h)
step ca certificate user@funlab.casa user.crt user.key \
  --provisioner authentik \
  --not-after 72h \
  --force
```

### Certificate Properties

Certificates issued via OIDC provisioner have:
- **Organization:** Funlab.Casa
- **Organizational Unit:** OIDC Users
- **Email:** (from your Authentik profile)
- **Key Usage:** Digital Signature, Key Encipherment
- **Extended Key Usage:**
  - TLS Web Client Authentication
  - E-mail Protection
  - ❌ **NOT** TLS Web Server Authentication (use other provisioners for servers)

### Inspect Certificate

```bash
# View certificate details
step certificate inspect service.crt

# View specific fields
openssl x509 -in service.crt -noout -subject -issuer -dates

# Verify certificate chain
step certificate verify service.crt \
  --roots ~/.step/certs/root_ca.crt
```

**Expected Output:**
```
subject: CN=user@funlab.casa, OU=OIDC Users, O=Funlab.Casa
issuer: CN=Sword of Omens Intermediate CA
Not Before: Feb 14 04:00:00 2026 GMT
Not After : Feb 15 04:00:00 2026 GMT (24h default)
```

### Certificate Renewal

**Note:** OIDC certificates have `disableRenewal: false`, but renewal still requires re-authentication.

```bash
# Renew certificate (will prompt for OIDC auth again)
step ca renew service.crt service.key \
  --force
```

---

## Troubleshooting

### OpenBao Login Issues

**Error: "No required SSL certificate was sent"**
- **Cause:** Trying to access OIDC endpoint with mTLS client
- **Solution:** Use browser or CLI tools that handle redirects correctly

**Error: "OIDC role not found"**
- **Cause:** Incorrect role name
- **Solution:** Valid roles are: `admin`, `cert-user`, `default`

**Error: "Permission denied"**
- **Cause:** User not in required Authentik group
- **Solution:** Contact admin to add you to appropriate group

**Token Expired:**
- **Cause:** Token TTL reached (15m - 1h depending on role)
- **Solution:** Re-authenticate with `bao login -method=oidc role=<role>`

### step-ca Certificate Issues

**Error: "provisioner not found"**
- **Cause:** Wrong provisioner name
- **Solution:** Use `--provisioner authentik` (lowercase)

**Error: "certificate validation failed"**
- **Cause:** Root CA not trusted
- **Solution:** Re-run bootstrap with `--install` flag

**Browser Doesn't Open:**
- **Cause:** No default browser configured
- **Solution:** Manually navigate to URL shown in terminal

**Error: "CSR validation failed"**
- **Cause:** Requested duration exceeds max (168h)
- **Solution:** Request shorter duration or contact admin

### Authentik Login Issues

**Error: "Invalid credentials"**
- **Cause:** Wrong username/password
- **Solution:** Reset password via Authentik admin

**User Not in Required Group:**
- **Cause:** Missing group membership
- **Solution:** Admin must add user to group via Authentik UI

**Consent Screen Appears Every Time:**
- **Cause:** Normal behavior for explicit consent flow
- **Solution:** Click "Authorize" each time (no persistent consent)

---

## Security Best Practices

### For Users

1. **Protect Your Credentials:**
   - Use strong, unique passwords
   - Enable MFA if available
   - Never share passwords

2. **Token/Certificate Management:**
   - Treat tokens as passwords - never commit to git
   - Store certificates securely (mode 600)
   - Delete expired certificates
   - Re-authenticate when tokens expire (don't use root token)

3. **Certificate Usage:**
   - Only use certificates for intended purpose
   - Don't use client certificates for server authentication
   - Request minimum necessary duration
   - Revoke compromised certificates immediately

### For Administrators

1. **Regular Audits:**
   - Review group memberships monthly
   - Audit certificate issuance logs
   - Monitor for unusual authentication patterns

2. **Credential Rotation:**
   - Rotate OIDC client secrets quarterly
   - Update Authentik database credentials regularly (1h TTL currently)
   - Review and revoke old certificates

3. **Monitoring:**
   - Watch Authentik logs for failed logins
   - Monitor OpenBao audit logs
   - Track certificate issuance patterns in step-ca

---

## Configuration Reference

### OIDC Endpoints

**OpenBao Provider:**
- Discovery URL: `https://auth.funlab.casa/application/o/openbao/.well-known/openid-configuration`
- Client ID: `openbao-client-2026`

**step-ca Provider:**
- Discovery URL: `https://auth.funlab.casa/application/o/step-ca/.well-known/openid-configuration`
- Client ID: `step-ca-client-2026`

### Service Endpoints

- **Authentik:** `https://auth.funlab.casa`
- **OpenBao:** `https://openbao.funlab.casa:8088`
- **step-ca:** `https://ca.funlab.casa:8443`

### Certificate Authority Chain

```
Eye of Thundera (Root CA)
└── Sword of Omens (Intermediate CA, YubiKey-backed)
    └── Issued Certificates
```

---

## Advanced Topics

### Creating Custom OpenBao Roles

**Admin Only:**

```bash
bao write auth/oidc/role/custom-role \
  bound_audiences="openbao-client-2026" \
  allowed_redirect_uris="https://openbao.funlab.casa:8088/ui/vault/auth/oidc/oidc/callback" \
  user_claim="sub" \
  groups_claim="groups" \
  bound_claims='{"groups": ["my-custom-group"]}' \
  token_policies="my-custom-policy" \
  token_ttl=30m
```

### Checking Token Policies

```bash
# After OIDC login
bao token lookup

# View policy contents
bao policy read pki-issue
```

### Certificate Revocation

**OpenBao Certificates:**
```bash
# Revoke by serial number
bao write pki_int/revoke \
  serial_number="39:dd:2e..."
```

**step-ca Certificates:**
```bash
step ca revoke <serial-number> \
  --provisioner authentik \
  --reason "key-compromise"
```

---

## Emergency Access

### OpenBao Root Token

**Location:** 1Password vault - "OpenBao Root Token"

**Usage:**
```bash
export BAO_TOKEN="<root-token-from-1password>"
bao auth list  # Verify access
```

**⚠️ Use Only For:**
- OIDC authentication broken
- Emergency policy updates
- Disaster recovery

### step-ca YubiKey PIN

**Location:** 1Password - stored as `S1iNIv2g`

**Access:** Required for step-ca configuration changes

### Authentik Recovery

**Admin Access:** Via direct PostgreSQL if web UI unavailable

**Database Credentials:** Stored in OpenBao at `secret/authentik/postgres`

---

## Support & Contacts

**Issues:**
- OpenBao not responding: Check unsealed status
- step-ca certificate errors: Check YubiKey is accessible
- Authentik login issues: Check database credentials (1h TTL)

**Documentation:**
- OpenBao OIDC: https://openbao.org/docs/auth/oidc/
- step-ca Provisioners: https://smallstep.com/docs/step-ca/provisioners/
- Authentik OIDC: https://goauthentik.io/docs/providers/oauth2/

**Infrastructure Docs:**
- Implementation Plan: `/home/bullwinkle/infrastructure/imperative-gliding-creek.md`
- mTLS Setup: `/home/bullwinkle/infrastructure/MTLS-WEB-SERVICE-PLAN.md`
- Authentik Deployment: `/home/bullwinkle/infrastructure/AUTHENTIK-WEEK5-DEPLOYMENT-GUIDE.md`

---

## Appendix: Test Credentials

**Test User (Development/Testing Only):**
- Username: `testuser1`
- Password: `Tkp28TfOdKa9RbaTdXnn7g`
- Email: `testuser1@funlab.casa`
- Groups: `openbao-cert-users`, `step-ca-users`

**⚠️ Security Note:** Change or delete test user in production environments.
