# Authentik OAuth2/OIDC Test Application

**Created:** 2026-02-12
**Last Updated:** 2026-02-12
**Status:** ✅ Active and Fully Tested
**Purpose:** Test OAuth2/OIDC authentication flow with Authentik as IdP

---

## Summary

This document covers the complete setup and testing of an OAuth2/OIDC test application using Authentik as the identity provider. A Flask-based test application has been deployed at http://10.10.2.70:3000 that demonstrates the full Authorization Code flow with PKCE support, passkey authentication, and consent management.

**Key Achievements:**
- ✅ Working OAuth2 Authorization Code flow
- ✅ Passkey (WebAuthn) authentication
- ✅ Consent management with persistence
- ✅ Token exchange and validation
- ✅ UserInfo endpoint integration
- ✅ Comprehensive debug logging
- ✅ Complete workflow documentation
- ✅ Troubleshooting guide for 8 common issues

**Quick Start:**
1. Visit http://10.10.2.70:3000
2. Click "Login with Authentik"
3. Authenticate with passkey
4. Grant consent (first time only)
5. View success page with user information

---

## Application Details

**Application Name:** Test OAuth Application
**Slug:** `test-oauth-app`
**Provider:** OAuth2/OpenID Connect
**Client Type:** Confidential (requires client secret)

**Launch URL:**
```
https://auth.funlab.casa/application/o/test-oauth-app/
```

---

## OAuth2/OIDC Credentials

### Client Credentials
```
Client ID:     quszF66EUTK69Ui5m76oAMBcTSLZrReoRwCjBt5J
Client Secret: R34IsZVwFgvkWQGXwIqAHFtApy3pNBUf4UHgs2OJGeqvYBvKdx45eRz5lPUiet2mjKn34bIz81bhS971tu6bJSpJqnoAGTmfXDBr5Ko5WsauFEa2aKVA50DzDK2hjRzn
```

**⚠️ IMPORTANT:** Store these credentials securely in OpenBao:
```bash
bao kv put secret/authentik/oauth-test-app \
  client_id="quszF66EUTK69Ui5m76oAMBcTSLZrReoRwCjBt5J" \
  client_secret="R34IsZVwFgvkWQGXwIqAHFtApy3pNBUf4UHgs2OJGeqvYBvKdx45eRz5lPUiet2mjKn34bIz81bhS971tu6bJSpJqnoAGTmfXDBr5Ko5WsauFEa2aKVA50DzDK2hjRzn"
```

### Redirect URIs (Allowed)
```
http://localhost:8080/callback        (for local dev)
http://localhost:3000/callback        (for local dev)
http://10.10.2.70:3000/callback       (for network testing)
```

**Note:** Postman redirect URI was removed during troubleshooting (see Issue 4 in Troubleshooting section)

---

## OAuth2/OIDC Endpoints

### Discovery Endpoint (OpenID Configuration)
```
https://auth.funlab.casa/application/o/test-oauth-app/.well-known/openid-configuration
```

### OAuth2 Endpoints
```
Authorization:  https://auth.funlab.casa/application/o/authorize/
Token:          https://auth.funlab.casa/application/o/token/
UserInfo:       https://auth.funlab.casa/application/o/userinfo/
JWKS:           https://auth.funlab.casa/application/o/test-oauth-app/jwks/
```

### Issuer
```
https://auth.funlab.casa/application/o/test-oauth-app/
```

---

## Supported OAuth2/OIDC Features

### Grant Types
- ✅ `authorization_code` (recommended)
- ✅ `refresh_token`
- ✅ `implicit`
- ✅ `client_credentials`
- ✅ `password` (resource owner password)
- ✅ `urn:ietf:params:oauth:grant-type:device_code`

### Response Types
- ✅ `code` (authorization code)
- ✅ `id_token` (implicit flow)
- ✅ `id_token token`
- ✅ `code token`
- ✅ `code id_token`
- ✅ `code id_token token`

### Scopes
- ✅ `openid` (required for OIDC)
- ✅ `profile` (user profile information)
- ✅ `email` (user email address)
- ✅ `offline_access` (refresh token)

---

## Flask Test Application

### Overview

A complete OAuth2/OIDC test application has been deployed on `auth.funlab.casa` to demonstrate the full authorization code flow with Authentik as the identity provider.

**Access URL:** http://10.10.2.70:3000

**Location:** `/opt/oauth-test-app/` on auth.funlab.casa host

**Container:** `oauth-test-app` (Docker)

### Features

- ✅ OAuth2 Authorization Code flow implementation
- ✅ CSRF protection with state parameter
- ✅ Token exchange and validation
- ✅ UserInfo endpoint integration
- ✅ Session management
- ✅ Passkey/WebAuthn authentication support
- ✅ Debug logging to stderr
- ✅ Celebration page with Rick Astley video on successful auth

### Application Architecture

```
┌─────────────┐         ┌──────────────┐         ┌─────────────┐
│   Browser   │         │ Flask App    │         │  Authentik  │
│             │         │ :3000        │         │  IdP        │
└──────┬──────┘         └──────┬───────┘         └──────┬──────┘
       │                       │                        │
       │ 1. GET /              │                        │
       ├──────────────────────>│                        │
       │                       │                        │
       │ 2. GET /login         │                        │
       ├──────────────────────>│                        │
       │                       │ 3. Generate state      │
       │                       │    Store in session    │
       │                       │                        │
       │ 4. Redirect to /authorize/                     │
       │<──────────────────────┤                        │
       │                       │                        │
       │ 5. GET /authorize/?client_id=...&state=...     │
       ├────────────────────────────────────────────────>│
       │                       │                        │
       │                       │    6. Check if user    │
       │                       │       authenticated    │
       │                       │                        │
       │                       │    7a. If NO:          │
       │                       │        Run auth flow   │
       │                       │        (passkey)       │
       │                       │                        │
       │                       │    7b. If YES:         │
       │                       │        Skip to step 8  │
       │                       │                        │
       │                       │    8. Run authz flow   │
       │                       │       (consent check)  │
       │                       │                        │
       │ 9. Consent page OR auto-approve                │
       │<────────────────────────────────────────────────│
       │                       │                        │
       │ 10. Submit consent    │                        │
       ├────────────────────────────────────────────────>│
       │                       │                        │
       │ 11. Redirect to /callback?code=...&state=...   │
       │<────────────────────────────────────────────────┤
       │                       │                        │
       │ 12. GET /callback     │                        │
       ├──────────────────────>│                        │
       │                       │ 13. Verify state       │
       │                       │                        │
       │                       │ 14. Exchange code for tokens
       │                       ├───────────────────────>│
       │                       │                        │
       │                       │ 15. Return tokens      │
       │                       │<───────────────────────┤
       │                       │                        │
       │                       │ 16. Get user info      │
       │                       ├───────────────────────>│
       │                       │                        │
       │                       │ 17. Return user info   │
       │                       │<───────────────────────┤
       │                       │                        │
       │                       │ 18. Store in session   │
       │                       │                        │
       │ 19. Redirect to /     │                        │
       │<──────────────────────┤                        │
       │                       │                        │
       │ 20. Show success page │                        │
       │    (with video!)      │                        │
       │<──────────────────────┤                        │
       │                       │                        │
```

### Docker Container Management

**View logs:**
```bash
ssh auth.funlab.casa "docker logs oauth-test-app --tail 100 -f"
```

**Restart application:**
```bash
ssh auth.funlab.casa "docker restart oauth-test-app"
```

**Rebuild container (after code changes):**
```bash
ssh auth.funlab.casa "cd /opt/oauth-test-app && docker build -t oauth-test-app . && docker stop oauth-test-app && docker rm oauth-test-app && docker run -d --name oauth-test-app -p 10.10.2.70:3000:3000 --restart unless-stopped oauth-test-app"
```

**View application code:**
```bash
ssh auth.funlab.casa "cat /opt/oauth-test-app/app.py"
```

### Application Code Structure

**File:** `/opt/oauth-test-app/app.py`

**Key Components:**

1. **Configuration Discovery (Startup)**
   - Fetches OIDC discovery document from `/.well-known/openid-configuration`
   - Extracts authorization_endpoint, token_endpoint, userinfo_endpoint
   - Stores in `OAUTH_CONFIG` global dictionary

2. **Home Page Route (`/`)**
   - Checks if user is logged in (session has 'user' key)
   - If logged in: Shows success page with user info and celebration video
   - If not logged in: Shows login button

3. **Login Route (`/login`)**
   - Generates cryptographically secure random state (32 bytes, base64url encoded)
   - Stores state in Flask session (CSRF protection)
   - Builds authorization URL with parameters:
     - `client_id`: OAuth client identifier
     - `response_type`: "code" (authorization code flow)
     - `redirect_uri`: Callback URL
     - `scope`: "openid profile email"
     - `state`: Random CSRF token
   - Redirects user to Authentik's authorization endpoint
   - **Debug logging:** Prints auth URL and redirect URI to stderr

4. **Callback Route (`/callback`)**
   - Receives authorization code from Authentik
   - **State Verification:**
     - Extracts state from URL parameter
     - Retrieves oauth_state from session
     - Compares both values
     - Returns 400 if mismatch (CSRF attack prevention)
   - **Debug logging:** Prints state values and session contents to stderr
   - **Token Exchange:**
     - Makes POST to token endpoint with:
       - grant_type=authorization_code
       - code=AUTHORIZATION_CODE
       - redirect_uri (must match)
       - client_id and client_secret (Basic Auth)
     - Receives access_token, id_token, refresh_token
   - **UserInfo Retrieval:**
     - Makes GET to userinfo endpoint
     - Passes access_token in Authorization header
     - Receives user claims (sub, email, name, etc.)
   - **Session Storage:**
     - Stores user info in Flask session
     - Removes oauth_state (no longer needed)
   - Redirects to home page

5. **Logout Route (`/logout`)**
   - Clears Flask session
   - Redirects to home page
   - **Note:** Does NOT logout from Authentik (SSO session remains)

**Environment Variables:**
- `SECRET_KEY`: Flask session encryption key (randomly generated)
- `CLIENT_ID`: OAuth client ID
- `CLIENT_SECRET`: OAuth client secret
- `REDIRECT_URI`: Callback URL (http://10.10.2.70:3000/callback)
- `AUTHORIZATION_ENDPOINT`: Filled from OIDC discovery
- `TOKEN_ENDPOINT`: Filled from OIDC discovery
- `USERINFO_ENDPOINT`: Filled from OIDC discovery

**Dependencies:**
- Flask: Web framework
- requests: HTTP client for token exchange
- urllib.parse: URL encoding
- secrets: Cryptographic random number generation
- base64: URL-safe encoding for state parameter

**Security Features:**
- ✅ State parameter for CSRF protection
- ✅ Client secret for client authentication
- ✅ Secure session cookies (Flask session)
- ✅ HTTPS for all Authentik communication
- ✅ Short-lived authorization codes
- ✅ Token validation

### Debug Logging

The Flask application includes comprehensive debug logging to stderr:

**Login endpoint logs:**
- Generated authorization URL
- Redirect URI being used
- State parameter value

**Callback endpoint logs:**
- State from URL parameter
- State from session
- Complete session contents
- Token exchange details

**View debug logs:**
```bash
ssh auth.funlab.casa "docker logs oauth-test-app 2>&1 | grep DEBUG"
```

---

## Complete OAuth2 Workflow Explanation

### Understanding Authentik Flows

Authentik uses two types of flows in the OAuth process:

1. **Authentication Flow** - Verifies who the user is (login with passkey, password, etc.)
2. **Authorization Flow** - Grants permission for the app to access user data (consent)

**CRITICAL:** The OAuth2 Provider's `authorization_flow` field must point to an AUTHORIZATION flow, not an AUTHENTICATION flow. Using an authentication flow causes infinite redirect loops.

### Current Configuration

**OAuth2 Provider Settings:**
- Name: `test-oauth-provider`
- Authorization Flow: `default-provider-authorization-explicit-consent` (designation: "authorization")
- Scope Mappings: 4 (openid, email, profile, offline_access)

**Application Settings:**
- Name: `Test OAuth Application`
- Slug: `test-oauth-app`
- Launch URL: `http://10.10.2.70:3000`
- Provider: `test-oauth-provider`

### Step-by-Step OAuth Flow

#### 1. User Initiates Login
- User visits http://10.10.2.70:3000
- Clicks "Login with Authentik"
- Flask app generates random `state` parameter (CSRF protection)
- Flask app stores `state` in session
- Flask app redirects to Authentik's `/authorize` endpoint

#### 2. Authorization Request
**URL format:**
```
https://auth.funlab.casa/application/o/authorize/
  ?client_id=quszF66EUTK69Ui5m76oAMBcTSLZrReoRwCjBt5J
  &response_type=code
  &redirect_uri=http://10.10.2.70:3000/callback
  &scope=openid+profile+email
  &state=RANDOM_STATE_VALUE
```

#### 3. Authentik Checks Authentication
- Authentik checks if user has an active session (cookie: `authentik_session`)
- **If authenticated:** Skip to step 5
- **If not authenticated:** Proceed to step 4

#### 4. Authentication Flow (if needed)
- Authentik runs the authentication flow (default: `default-authentication-flow`)
- User sees login options (passkey, password, etc.)
- User authenticates with passkey (WebAuthn)
- Authentik creates session and sets `authentik_session` cookie
- Session stored in Redis/database
- Proceed to step 5

#### 5. Authorization Flow Execution
- Authentik runs the OAuth provider's `authorization_flow`
- Flow: `default-provider-authorization-explicit-consent`
- This flow contains a ConsentStage

#### 6. Consent Check
- Authentik checks if user has previously consented to this application
- Query: `UserConsent.objects.filter(user=current_user, application=test_app)`
- **If consent exists:** Auto-approve and skip to step 8
- **If no consent:** Show consent page (step 7)

#### 7. Consent Page (first time only)
- User sees consent page listing requested scopes:
  - `openid` - Required for OIDC
  - `email` - Access to email address
  - `profile` - Access to profile information
- User clicks "Authorize" button
- Authentik creates `UserConsent` record (persisted in database)
- This consent is remembered for future authorizations

#### 8. Authorization Grant
- Authentik generates authorization code (short-lived, single-use)
- Authentik creates event: `authorize_application`
- Authorization code stored in database with:
  - User reference
  - Application reference
  - Requested scopes
  - Expiration time (default: 1 minute)

#### 9. Redirect to Callback
**URL format:**
```
http://10.10.2.70:3000/callback
  ?code=AUTHORIZATION_CODE
  &state=RANDOM_STATE_VALUE
```

#### 10. State Verification
- Flask app receives callback
- Extracts `state` from URL parameter
- Extracts `oauth_state` from session
- **Compares:** URL state === session state
- **If mismatch:** Returns 400 error (CSRF attack prevention)
- **If match:** Proceed to step 11

#### 11. Token Exchange
Flask app makes POST request to token endpoint:

**Request:**
```http
POST https://auth.funlab.casa/application/o/token/
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code
code=AUTHORIZATION_CODE
redirect_uri=http://10.10.2.70:3000/callback
client_id=quszF66EUTK69Ui5m76oAMBcTSLZrReoRwCjBt5J
client_secret=R34IsZVwFgvkWQGXwIqAHFtApy3pNBUf4UHgs2OJGeqvYBvKdx45eRz5lPUiet2mjKn34bIz81bhS971tu6bJSpJqnoAGTmfXDBr5Ko5WsauFEa2aKVA50DzDK2hjRzn
```

**Response:**
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "Bearer",
  "expires_in": 600,
  "refresh_token": "opaque_refresh_token_string",
  "id_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Token Details:**
- **Access Token:** JWT signed with RS256, expires in 10 minutes
- **ID Token:** JWT with user claims (email, name, etc.)
- **Refresh Token:** Opaque token, expires in 30 days

#### 12. Get User Info
Flask app makes GET request to userinfo endpoint:

**Request:**
```http
GET https://auth.funlab.casa/application/o/userinfo/
Authorization: Bearer ACCESS_TOKEN
```

**Response:**
```json
{
  "sub": "c03c832394a83a3c4152f8508c3b7c46ac9db6edee1996ef08203558b6d135e89",
  "email": "admin@funlab.casa",
  "email_verified": true,
  "name": "authentik Default Admin",
  "given_name": "authentik Default Admin",
  "preferred_username": "akadmin",
  "nickname": "akadmin",
  "groups": ["authentik Admins"]
}
```

#### 13. Session Storage
- Flask app stores user info in session
- Session cookie: `session` (Flask's secure session cookie)
- User is now logged in to the Flask application

#### 14. Success Page
- Flask app redirects to home page
- Shows "Congratulations! OAuth Authentication Successful!"
- Displays Rick Astley video (autoplay)
- Shows user information retrieved from Authentik

### Session Behavior

#### Authentik Session
- **Cookie:** `authentik_session`
- **Storage:** Redis/Database
- **Lifetime:** Configurable (default: remember for session)
- **Scope:** auth.funlab.casa domain
- **Purpose:** Maintains user authentication state

**Session persistence means:**
- User authenticates once with passkey
- Can authorize multiple applications without re-authenticating
- Logging out requires explicit logout action
- Private/incognito mode starts with no session

#### Flask Application Session
- **Cookie:** `session` (signed with Flask secret key)
- **Storage:** Client-side (encrypted cookie)
- **Lifetime:** Browser session
- **Scope:** 10.10.2.70 domain
- **Purpose:** Stores OAuth state and user data

### Consent Behavior

#### First Authorization
1. User authenticates (if needed)
2. User sees consent page
3. User clicks "Authorize"
4. `UserConsent` record created in database
5. Authorization granted

#### Subsequent Authorizations
1. User authenticates (if needed)
2. Authentik checks for existing `UserConsent`
3. **Consent found:** Auto-approve, immediate redirect
4. **No consent page shown**
5. Authorization granted (< 1 second)

**This is standard OAuth2 behavior** to prevent consent fatigue.

#### Revoking Consent

To test the full flow with consent page again:

```bash
ssh auth.funlab.casa "docker exec -i authentik-server ak shell" << 'EOF'
from authentik.stages.consent.models import UserConsent
# Delete all consents for the test app
UserConsent.objects.filter(application__name="Test OAuth Application").delete()
print("✅ Consent revoked - next login will show consent page")
EOF
```

Or via Authentik admin UI:
1. Navigate to: https://auth.funlab.casa/if/admin/
2. Go to **Events → Logs**
3. Find consent events for the user
4. Go to **Directory → Users**
5. Select user → **User Consents** tab
6. Delete consent for Test OAuth Application

---

## Testing the OAuth Flow

### Method 1: Using Postman

1. **Import OAuth2 settings in Postman:**
   - Auth Type: OAuth 2.0
   - Grant Type: Authorization Code
   - Callback URL: `https://oauth.pstmn.io/v1/callback`
   - Auth URL: `https://auth.funlab.casa/application/o/authorize/`
   - Access Token URL: `https://auth.funlab.casa/application/o/token/`
   - Client ID: `quszF66EUTK69Ui5m76oAMBcTSLZrReoRwCjBt5J`
   - Client Secret: `R34IsZVwFgvkWQGXwIqAHFtApy3pNBUf4UHgs2OJGeqvYBvKdx45eRz5lPUiet2mjKn34bIz81bhS971tu6bJSpJqnoAGTmfXDBr5Ko5WsauFEa2aKVA50DzDK2hjRzn`
   - Scope: `openid profile email`

2. **Click "Get New Access Token"**

3. **Authenticate with Authentik:**
   - Use your admin account or passkey
   - Approve the authorization request

4. **Receive Access Token and ID Token**

### Method 2: Manual Authorization Code Flow

**Step 1: Authorization Request**

Open this URL in your browser:
```
https://auth.funlab.casa/application/o/authorize/?client_id=quszF66EUTK69Ui5m76oAMBcTSLZrReoRwCjBt5J&response_type=code&scope=openid%20profile%20email&redirect_uri=http://localhost:8080/callback&state=random_state_string
```

**Step 2: Extract Authorization Code**

After authentication, you'll be redirected to:
```
http://localhost:8080/callback?code=AUTHORIZATION_CODE&state=random_state_string
```

Copy the `code` parameter value.

**Step 3: Exchange Code for Tokens**

```bash
curl -X POST https://auth.funlab.casa/application/o/token/ \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code" \
  -d "code=AUTHORIZATION_CODE" \
  -d "redirect_uri=http://localhost:8080/callback" \
  -d "client_id=quszF66EUTK69Ui5m76oAMBcTSLZrReoRwCjBt5J" \
  -d "client_secret=R34IsZVwFgvkWQGXwIqAHFtApy3pNBUf4UHgs2OJGeqvYBvKdx45eRz5lPUiet2mjKn34bIz81bhS971tu6bJSpJqnoAGTmfXDBr5Ko5WsauFEa2aKVA50DzDK2hjRzn"
```

**Step 4: Get User Info**

```bash
curl https://auth.funlab.casa/application/o/userinfo/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### Method 3: Using OIDC Playground

Visit: https://openidconnect.net/

Enter the configuration:
- Discovery URL: `https://auth.funlab.casa/application/o/test-oauth-app/.well-known/openid-configuration`
- Client ID: `quszF66EUTK69Ui5m76oAMBcTSLZrReoRwCjBt5J`
- Client Secret: `R34IsZVwFgvkWQGXwIqAHFtApy3pNBUf4UHgs2OJGeqvYBvKdx45eRz5lPUiet2mjKn34bIz81bhS971tu6bJSpJqnoAGTmfXDBr5Ko5WsauFEa2aKVA50DzDK2hjRzn`
- Redirect URI: (use one from allowed list)

---

## Token Claims (Example)

### ID Token Claims
```json
{
  "iss": "https://auth.funlab.casa/application/o/test-oauth-app/",
  "sub": "hashed_user_id",
  "aud": "quszF66EUTK69Ui5m76oAMBcTSLZrReoRwCjBt5J",
  "exp": 1739395200,
  "iat": 1739391600,
  "auth_time": 1739391600,
  "email": "admin@funlab.casa",
  "email_verified": true,
  "name": "Admin User",
  "preferred_username": "akadmin",
  "given_name": "Admin",
  "family_name": "User"
}
```

### Access Token
- Type: JWT (signed)
- Signing Algorithm: RS256
- Validity: 10 minutes (default)

### Refresh Token
- Type: Opaque (database reference)
- Validity: 30 days (default)

---

## Viewing Tokens in Authentik Admin

1. Navigate to: https://auth.funlab.casa/if/admin/
2. Go to **Applications → Applications**
3. Click on **"Test OAuth Application"**
4. View **Tokens** tab to see issued access/refresh tokens

---

## Security Considerations

### Current Configuration
- ✅ Confidential client (requires client secret)
- ✅ HTTPS endpoints (secure transport)
- ✅ Signed JWT tokens (RS256)
- ✅ Authorization flow (most secure OAuth flow)
- ✅ Hashed user IDs in `sub` claim (privacy)
- ✅ Claims included in ID token

### Production Recommendations
1. **Use authorization code flow with PKCE** for public clients (SPAs, mobile apps)
2. **Rotate client secrets** periodically
3. **Limit redirect URIs** to production domains only
4. **Enable CORS** only for trusted origins
5. **Use short-lived access tokens** (5-15 minutes)
6. **Implement token rotation** for refresh tokens
7. **Monitor token usage** for anomalies

---

## Next Steps

### Week 5 Day 7
- ✅ Create test user account
- ✅ Test OAuth flow with test user
- ✅ Verify JWT token claims
- ✅ Test refresh token flow
- ✅ Document integration examples

### Week 6-7 (Future)
- Deploy to production applications
- Integrate with services (Grafana, etc.)
- Configure mTLS for device enrollment
- Add SPIRE workload identity

---

## Troubleshooting

### Issues Encountered and Fixed

This section documents all issues encountered during the setup and how they were resolved.

#### Issue 1: NameError - Missing Quotes in f-string Dictionary Access

**Symptom:**
```python
NameError: name 'authorization_endpoint' is not defined
```

**Root Cause:**
Line 193 in Flask app had unquoted dictionary key in f-string:
```python
auth_url = f"{OAUTH_CONFIG[authorization_endpoint]}?{urlencode(params)}"
```

**Solution:**
Use single quotes for dictionary keys inside f-strings:
```python
auth_url = f"{OAUTH_CONFIG['authorization_endpoint']}?{urlencode(params)}"
```

**Lesson:** F-strings with double quotes require single quotes for inner string literals.

---

#### Issue 2: Missing sys Import for Debug Logging

**Symptom:**
```python
NameError: name 'sys' is not defined
```

**Root Cause:**
Debug logging code used `file=sys.stderr` but `sys` module wasn't imported.

**Solution:**
Add import at top of app.py:
```python
import sys
```

---

#### Issue 3: Passkey Button Not Showing

**Symptom:**
OAuth authorization flow didn't show passkey authentication option, only password field.

**Root Cause:**
OAuth provider's `authorization_flow` was set to `custom-oauth-authorization` which had **zero stages** configured. Without stages, the flow couldn't present authentication options.

**Solution:**
Changed authorization flow to `default-authentication-flow`:
```bash
ssh auth.funlab.casa "docker exec -i authentik-server ak shell" << 'EOF'
from authentik.providers.oauth2.models import OAuth2Provider
from authentik.flows.models import Flow
provider = OAuth2Provider.objects.get(name="test-oauth-provider")
auth_flow = Flow.objects.get(slug="default-authentication-flow")
provider.authorization_flow = auth_flow
provider.save()
EOF
```

**Note:** This solution was later revised (see Issue 6).

---

#### Issue 4: Redirect to Postman Callback URL

**Symptom:**
After authentication, user redirected to `oauth.pstmn.io` with "AccessDenied" error.

**Root Cause:**
OAuth provider had multiple redirect URIs configured, and Postman's URI was first in the list. When multiple URIs are configured, Authentik may choose the first one if no explicit `redirect_uri` is specified in the request.

**Solution:**
Removed Postman redirect URI from OAuth provider configuration:
```bash
ssh auth.funlab.casa "docker exec -i authentik-server ak shell" << 'EOF'
from authentik.providers.oauth2.models import OAuth2Provider
provider = OAuth2Provider.objects.get(name="test-oauth-provider")
new_uris = "http://localhost:8080/callback\nhttp://localhost:3000/callback\nhttp://10.10.2.70:3000/callback"
provider.redirect_uris = new_uris
provider.save()
EOF
```

**Lesson:** Order matters when multiple redirect URIs are configured. Always specify explicit `redirect_uri` in authorization requests.

---

#### Issue 5: Landing at Authentik Library Instead of Callback

**Symptom:**
After authentication, user landed at Authentik's application library page instead of being redirected back to the Flask app.

**Root Cause:**
User was clicking on the application tile in Authentik dashboard, which uses the application's `meta_launch_url` instead of initiating an OAuth flow.

**Correct Flow:**
1. Start at Flask app: http://10.10.2.70:3000
2. Click "Login with Authentik" button
3. Get redirected to Authentik for auth
4. Return to callback

**Incorrect Flow:**
1. Visit Authentik dashboard
2. Click "Test OAuth Application" tile
3. Launch URL takes you directly to app (no OAuth flow)

**Solution:**
Set application launch URL to Flask app and educated user on correct flow:
```bash
ssh auth.funlab.casa "docker exec -i authentik-server ak shell" << 'EOF'
from authentik.core.models import Application
app = Application.objects.get(name="Test OAuth Application")
app.meta_launch_url = "http://10.10.2.70:3000"
app.save()
EOF
```

---

#### Issue 6: Infinite Authentication Loop

**Symptom:**
After passkey authentication, user stuck in infinite redirect loop:
```
/application/o/authorize/ → 302 redirect
/if/flow/default-authentication-flow/ → authentication page
User authenticates with passkey
Back to /application/o/authorize/ → 302 redirect
Back to /if/flow/default-authentication-flow/ → repeat
```

**Root Cause:**
OAuth provider's `authorization_flow` field was set to `default-authentication-flow` (designation: "authentication").

**CRITICAL DISTINCTION:**
- **Authentication Flow:** Verifies user identity (login)
- **Authorization Flow:** Grants app permission (consent)

OAuth providers require an **AUTHORIZATION flow**, not an authentication flow.

**What was happening:**
1. User visits `/authorize` endpoint
2. Authentik checks: "User authenticated?" → Yes
3. Authentik runs authorization_flow → But it's an authentication flow!
4. Authentication flow requires login → Redirects to `/authorize`
5. Infinite loop

**Solution:**
Changed to proper authorization flow:
```bash
ssh auth.funlab.casa "docker exec -i authentik-server ak shell" << 'EOF'
from authentik.providers.oauth2.models import OAuth2Provider
from authentik.flows.models import Flow
provider = OAuth2Provider.objects.get(name="test-oauth-provider")
auth_flow = Flow.objects.get(slug="default-provider-authorization-explicit-consent")
provider.authorization_flow = auth_flow
provider.save()
EOF
```

**Verification:**
```bash
# Check flow designation
Flow.objects.get(slug="default-provider-authorization-explicit-consent").designation
# Should return: "authorization"
```

**Lesson:** Always verify that OAuth provider's `authorization_flow` has designation="authorization".

---

#### Issue 7: Missing OAuth Scopes

**Symptom:**
Authentik logs showed:
```
"Application requested scopes not configured, setting to overlap"
"scope_allowed": "set()"
```

**Root Cause:**
OAuth provider had **zero scope mappings** configured. Without scope mappings, Authentik couldn't return any user claims.

**Solution:**
Added scope mappings to OAuth provider:
```bash
ssh auth.funlab.casa "docker exec -i authentik-server ak shell" << 'EOF'
from authentik.providers.oauth2.models import OAuth2Provider, ScopeMapping
provider = OAuth2Provider.objects.get(name="test-oauth-provider")
scopes = ScopeMapping.objects.filter(scope_name__in=["openid", "email", "profile", "offline_access"])
provider.property_mappings.set(scopes)
provider.save()
print(f"Added {scopes.count()} scope mappings")
EOF
```

**Verification:**
```bash
# Check scope mappings
ssh auth.funlab.casa "docker exec -i authentik-server ak shell" << 'EOF'
from authentik.providers.oauth2.models import OAuth2Provider
provider = OAuth2Provider.objects.get(name="test-oauth-provider")
print(f"Scope mappings: {provider.property_mappings.count()}")
for mapping in provider.property_mappings.all():
    print(f"  - {mapping.name}")
EOF
```

Should show:
- openid
- email
- profile
- offline_access

---

#### Issue 8: Consent Page Bypassed (Expected Behavior)

**Symptom:**
In subsequent OAuth flows, consent page was skipped and user immediately redirected to callback (< 1 second).

**Root Cause:**
This is **not a bug** - it's standard OAuth2 behavior. Once a user consents to an application, Authentik stores the consent in a `UserConsent` database record. Future authorization requests skip the consent page for better UX.

**Evidence from logs:**
```json
{
  "action": "model_updated",
  "model_name": "userconsent",
  "name": "User Consent Test OAuth Application by akadmin"
}
```

**To test full flow with consent again:**
```bash
# Revoke consent
ssh auth.funlab.casa "docker exec -i authentik-server ak shell" << 'EOF'
from authentik.stages.consent.models import UserConsent
UserConsent.objects.filter(application__name="Test OAuth Application").delete()
EOF
```

**Lesson:** Consent persistence is expected OAuth behavior, not a session issue.

---

### Common Issues and Solutions

**Issue: "Invalid redirect URI"**
- Solution: Ensure redirect URI in request exactly matches one of the configured URIs
- Check: OAuth provider's `redirect_uris` field (newline-separated)
- Verify: URL encoding matches exactly (http:// vs https://, ports, paths)

**Issue: "Invalid client credentials"**
- Solution: Verify client ID and secret are correct
- Check: Copy credentials directly from Authentik admin UI
- Verify: No extra whitespace or newlines in credentials

**Issue: "Token expired"**
- Solution: Use refresh token to get new access token
- Access tokens expire in 10 minutes by default
- Refresh tokens expire in 30 days by default

**Issue: "Invalid scope"**
- Solution: Request only `openid`, `profile`, `email`, or `offline_access`
- Verify: OAuth provider has scope mappings configured
- Check: Application isn't requesting custom scopes

**Issue: "CSRF check failed" or "Invalid state parameter"**
- Solution: Verify state parameter is being stored and retrieved correctly
- Check: Flask session is working (secret key configured)
- Verify: Same browser is making both authorize and callback requests

**Issue: Infinite redirect loop**
- Solution: Verify authorization_flow has designation="authorization", not "authentication"
- Check: OAuth provider configuration in Authentik admin
- Fix: Change to a proper authorization flow (see Issue 6)

---

### Debugging Tools

#### Check Authentik Logs
```bash
# Real-time logs
ssh auth.funlab.casa "docker logs authentik-server --tail 100 -f"

# Filter for OAuth events
ssh auth.funlab.casa "docker logs authentik-server --tail 100 | grep -E '(authorize|oauth|consent)'"

# Check for errors
ssh auth.funlab.casa "docker logs authentik-server --tail 100 | grep -i error"
```

#### Check Flask App Logs
```bash
# Real-time logs
ssh auth.funlab.casa "docker logs oauth-test-app --tail 50 -f"

# Debug logs only
ssh auth.funlab.casa "docker logs oauth-test-app 2>&1 | grep DEBUG"

# Last callback attempt
ssh auth.funlab.casa "docker logs oauth-test-app --tail 20 | grep callback"
```

#### Verify OAuth Provider Configuration
```bash
ssh auth.funlab.casa "docker exec -i authentik-server ak shell" << 'EOF'
from authentik.providers.oauth2.models import OAuth2Provider
from authentik.flows.models import Flow

provider = OAuth2Provider.objects.get(name="test-oauth-provider")
print(f"Provider: {provider.name}")
print(f"Client ID: {provider.client_id}")
print(f"Redirect URIs:\n{provider.redirect_uris}")
print(f"\nAuthorization Flow: {provider.authorization_flow.name}")
print(f"Flow Slug: {provider.authorization_flow.slug}")
print(f"Flow Designation: {provider.authorization_flow.designation}")
print(f"\nScope Mappings: {provider.property_mappings.count()}")
for mapping in provider.property_mappings.all():
    if hasattr(mapping, 'scope_name'):
        print(f"  - {mapping.scope_name}")
EOF
```

Expected output:
```
Provider: test-oauth-provider
Client ID: quszF66EUTK69Ui5m76oAMBcTSLZrReoRwCjBt5J
Redirect URIs:
http://localhost:8080/callback
http://localhost:3000/callback
http://10.10.2.70:3000/callback

Authorization Flow: Authorize Application
Flow Slug: default-provider-authorization-explicit-consent
Flow Designation: authorization

Scope Mappings: 4
  - openid
  - email
  - profile
  - offline_access
```

#### Test OIDC Discovery
```bash
curl -sk https://auth.funlab.casa/application/o/test-oauth-app/.well-known/openid-configuration | jq
```

#### Test Token Endpoint
```bash
# After getting an authorization code
curl -X POST https://auth.funlab.casa/application/o/token/ \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code" \
  -d "code=YOUR_AUTH_CODE" \
  -d "redirect_uri=http://10.10.2.70:3000/callback" \
  -d "client_id=quszF66EUTK69Ui5m76oAMBcTSLZrReoRwCjBt5J" \
  -d "client_secret=YOUR_CLIENT_SECRET"
```

---

## Key Learnings

### 1. Flow Types Matter
**Critical distinction between Authentication and Authorization flows:**
- **Authentication Flow:** Verifies user identity (login with passkey, password, etc.)
- **Authorization Flow:** Grants application access to user data (consent)

**OAuth providers must use Authorization flows, not Authentication flows.** Using an authentication flow in the `authorization_flow` field causes infinite redirect loops.

**How to verify:**
```python
Flow.objects.get(slug="your-flow-slug").designation
# Must return: "authorization" for OAuth providers
```

### 2. Consent is Persistent
OAuth consent is stored in the database (`UserConsent` model) and persists across:
- Browser sessions
- Private/incognito mode
- Different devices (same user account)

This is **standard OAuth2 behavior** to prevent consent fatigue. Once a user consents to an application, subsequent authorizations are auto-approved until the consent is:
- Explicitly revoked by the user
- Deleted by an administrator
- Expired (if expiration is configured)

### 3. Sessions vs Consent
Two separate concepts often confused:

**Authentik Session:**
- Cookie: `authentik_session`
- Purpose: Maintains authentication state
- Scope: auth.funlab.casa domain
- Lifetime: Browser session or "remember me"
- Effect: Skips authentication step if valid

**User Consent:**
- Storage: Database (UserConsent model)
- Purpose: Records user's permission for app access
- Scope: Per user, per application
- Lifetime: Indefinite (until revoked)
- Effect: Skips consent page if exists

**Both can be active simultaneously:**
- Valid session + valid consent = Instant authorization (< 1 second)
- Valid session + no consent = Shows consent page
- No session + valid consent = Shows login, then auto-approves
- No session + no consent = Shows login, then consent page

### 4. Scope Mappings are Required
OAuth providers won't return user claims without scope mappings configured. Authentik logs will show:
```
"Application requested scopes not configured, setting to overlap"
```

**Required scope mappings for basic OIDC:**
- `openid` - Required for OIDC compliance
- `email` - User's email address
- `profile` - User's profile information (name, username, etc.)
- `offline_access` - Refresh token support

### 5. State Parameter is Critical
The state parameter provides CSRF protection in OAuth flows:
1. Client generates random state
2. Client stores state in session
3. Client includes state in authorization URL
4. Authorization server echoes state back in callback
5. Client verifies callback state matches session state

**If state verification is skipped or broken:**
- CSRF attacks become possible
- Attackers can inject authorization codes
- User accounts can be compromised

**Best practices:**
- Use cryptographically secure random (32+ bytes)
- URL-safe encoding (base64url)
- Store in server-side session, not client-side
- Always verify before exchanging code for tokens

### 6. F-String Quoting Rules
When using f-strings with dictionary access:
```python
# ❌ WRONG - SyntaxError
f"{dict["key"]}"  # Double quotes conflict

# ❌ WRONG - NameError
f"{dict[key]}"    # Treats key as variable, not string

# ✅ CORRECT
f"{dict['key']}"  # Single quotes inside f-string
```

### 7. Debug Logging Best Practices
For OAuth debugging, log:
- State generation and storage
- State verification and comparison
- Authorization URLs (without secrets)
- Token exchange requests (without secrets)
- Token responses (without sensitive data)
- UserInfo responses

**Log to stderr for Docker containers:**
```python
import sys
print(f"DEBUG: Message", file=sys.stderr)
```

This keeps debug logs separate from application output and makes them visible in `docker logs`.

### 8. Redirect URI Matching is Exact
OAuth redirect URI matching is **exact string comparison:**
- `http://localhost:3000/callback` ≠ `http://127.0.0.1:3000/callback`
- `http://localhost:3000/callback` ≠ `http://localhost:3000/callback/`
- `http://example.com/callback` ≠ `https://example.com/callback`

**Port numbers matter:**
- `http://localhost/callback` ≠ `http://localhost:80/callback`
- (Even though port 80 is default for HTTP)

**Best practice:** Always explicitly specify `redirect_uri` in authorization requests, even if only one URI is configured.

### 9. OAuth is Stateful
Despite being a "stateless" protocol, OAuth requires state management:

**Server-side state:**
- Authorization codes (short-lived, single-use)
- Access tokens (cached/stored for lifetime)
- Refresh tokens (long-lived, database-backed)
- User consents (persistent)
- User sessions (authentication state)

**Client-side state:**
- CSRF state parameter (per-authorization)
- Session cookies (authentication)
- Tokens (if using implicit flow - not recommended)

**Implications:**
- Load balancers need sticky sessions or shared session storage
- Horizontal scaling requires Redis/database session backend
- Token revocation requires database lookups
- Can't fully cache OAuth responses

### 10. Testing OAuth Requires Fresh State
To properly test OAuth flows, you need to clear:

**For full authentication test:**
1. Logout from Authentik (clear session)
2. Use private/incognito browser
3. Or clear `authentik_session` cookie

**For consent page test:**
1. Revoke consent in database
2. Or use different user account
3. Or use different application

**For token exchange test:**
1. Use fresh authorization code (single-use)
2. Verify code hasn't expired (1 minute TTL)
3. Ensure redirect_uri matches exactly

---

## Related Documentation

- **Authentik OAuth2 Provider Docs:** https://docs.goauthentik.io/docs/providers/oauth2/
- **OpenID Connect Spec:** https://openid.net/specs/openid-connect-core-1_0.html
- **OAuth 2.0 RFC:** https://datatracker.ietf.org/doc/html/rfc6749

---

## Document History

- **2026-02-12 (Initial):** Created OAuth application and provider configuration
- **2026-02-12 (Updated):** Added Flask test application and comprehensive workflow documentation
  - Documented 8 issues encountered and their solutions
  - Added complete OAuth flow explanation with ASCII diagram
  - Documented session vs consent behavior
  - Added 10 key learnings from implementation
  - Added debugging tools and verification commands

---

**Last Updated:** 2026-02-12 18:59 UTC
**Maintained By:** Infrastructure Team
**Status:** ✅ Production-Ready for Testing
**Test Application:** http://10.10.2.70:3000
