# Authentik Device Enrollment Flow - mTLS Client Certificates

**Date:** 2026-02-11
**Purpose:** Detailed guide for implementing device enrollment via Authentik with step-ca integration
**Status:** 📋 Design Complete, Ready for Implementation

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Implementation Steps](#implementation-steps)
5. [User Experience Flow](#user-experience-flow)
6. [Technical Details](#technical-details)
7. [Testing](#testing)
8. [Troubleshooting](#troubleshooting)

---

## Overview

### What This Enables

Users can self-service enroll their devices to receive client certificates for seamless zero-click authentication to services protected by auth.funlab.casa.

**User Benefits:**
- **Seamless Access:** Enrolled devices authenticate automatically (no login prompts)
- **Self-Service:** Users enroll their own devices without admin intervention
- **Multi-Device:** Can enroll multiple devices (phone, laptop, tablet)
- **Secure:** Hardware-backed certificates, proper revocation

**Technical Benefits:**
- **Zero-Trust:** Device identity separate from user identity
- **TPM-Backed:** Certificates issued by step-ca with TPM root
- **Integrated:** Works with existing Tower of Omens infrastructure
- **Audited:** Complete enrollment and usage audit trail

---

## Architecture

### Component Integration

```
┌─────────────────────────────────────────────────────────────┐
│ USER ENROLLMENT FLOW                                         │
└─────────────────────────────────────────────────────────────┘

1. User authenticates to auth.funlab.casa
   └─ Passkey login (Face ID / Touch ID)

2. User navigates to "My Devices" page
   └─ Sees list of enrolled devices
   └─ Clicks "Enroll This Device"

3. Authentik generates device identity
   └─ Device Name (auto-detected or user-provided)
   └─ Browser fingerprint
   └─ User identifier

4. Authentik generates CSR (Certificate Signing Request)
   └─ Subject: CN=device-name.user.funlab.casa
   └─ Key Usage: Digital Signature, Key Encipherment
   └─ Extended Key Usage: Client Authentication

5. Authentik calls step-ca API
   └─ Authenticates using SPIRE SVID
   └─ Submits CSR for signing
   └─ Receives signed certificate

6. Authentik packages certificate
   └─ Creates PKCS#12 bundle (.p12)
   └─ Includes: client cert + private key + CA chain
   └─ Password-protects bundle

7. User downloads certificate
   └─ Downloads device-name.p12 file
   └─ Receives installation instructions

8. User installs certificate on device
   └─ Platform-specific installation
   └─ Certificate stored in device keystore

9. User visits protected service
   └─ Browser automatically presents certificate
   └─ NPM validates certificate
   └─ User gets instant access (no login prompt!)
```

### System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ auth.funlab.casa (Authentik)                                │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Device Enrollment Flow                                  │ │
│ │ ├─ Authentication Stage (passkey login)                │ │
│ │ ├─ Device Information Stage (name, browser)            │ │
│ │ ├─ CSR Generation Stage (private key + CSR)            │ │
│ │ ├─ Certificate Issuance Stage (call step-ca API)       │ │
│ │ ├─ PKCS#12 Packaging Stage (bundle creation)           │ │
│ │ └─ Download Stage (deliver .p12 to user)               │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                              │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ My Devices Page                                         │ │
│ │ ├─ List of enrolled devices                             │ │
│ │ ├─ Enrollment button                                    │ │
│ │ ├─ Revocation capability                                │ │
│ │ └─ Certificate renewal reminder                         │ │
│ └─────────────────────────────────────────────────────────┘ │
└────────────────────────────┬────────────────────────────────┘
                             │
                             │ API Call (authenticated via SPIRE SVID)
                             ▼
┌─────────────────────────────────────────────────────────────┐
│ step-ca (ca.funlab.casa)                                    │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Client Certificate Provisioner                          │ │
│ │ ├─ Validates caller (SPIRE SVID from Authentik)        │ │
│ │ ├─ Validates CSR attributes                             │ │
│ │ ├─ Signs certificate (TPM-backed CA)                    │ │
│ │ ├─ Sets validity (90 days)                              │ │
│ │ └─ Returns signed certificate                           │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### Infrastructure Requirements

**Must Be Deployed:**
- ✅ **step-ca** - TPM-backed certificate authority operational
- ✅ **OpenBao** - Secrets storage (for Authentik ↔ step-ca credentials)
- ✅ **SPIRE** - Workload identity (Authentik authenticates to step-ca via SVID)
- ✅ **Authentik** - OAuth/OIDC provider with passkey authentication

**Must Be Configured:**
- ✅ **step-ca provisioner** - Client certificate issuance enabled
- ✅ **SPIRE workload registration** - Authentik has SPIFFE ID
- ✅ **OpenBao policy** - Authentik can retrieve step-ca credentials
- ✅ **Authentik passkeys** - Users can authenticate

### Network Requirements

- ✅ Authentik can reach step-ca API (HTTPS)
- ✅ DNS resolution: ca.funlab.casa → step-ca IP
- ✅ Firewall allows Authentik → step-ca (port 443)

### Certificate Template Requirements

**Client Certificate Attributes:**
```
Subject:
  CN: {device-name}.{username}.funlab.casa
  O: Funlab.Casa
  OU: User Devices

Key Usage:
  - Digital Signature
  - Key Encipherment

Extended Key Usage:
  - TLS Web Client Authentication (1.3.6.1.5.5.7.3.2)

Validity: 90 days
Key Type: RSA 2048 or ECDSA P-256
```

---

## Implementation Steps

### Step 1: Configure step-ca Provisioner

**Create client certificate provisioner:**

```bash
# SSH to ca.funlab.casa (step-ca host)
ssh ca.funlab.casa

# Create provisioner for client certificates
step ca provisioner add client-certs \
  --type JWK \
  --create

# Get provisioner key ID
PROVISIONER_KID=$(step ca provisioner list | jq -r '.[] | select(.name=="client-certs") | .key.kid')

# Create provisioner template
cat > /etc/step-ca/templates/client-cert.tpl << 'EOF'
{
  "subject": {
    "commonName": {{ toJson .Subject.CommonName }},
    "organization": "Funlab.Casa",
    "organizationalUnit": "User Devices"
  },
  "keyUsage": ["digitalSignature", "keyEncipherment"],
  "extKeyUsage": ["clientAuth"],
  "basicConstraints": {
    "isCA": false,
    "maxPathLen": 0
  }
}
EOF

# Update provisioner to use template
step ca provisioner update client-certs \
  --x509-template /etc/step-ca/templates/client-cert.tpl
```

**Test provisioner:**

```bash
# Generate test certificate
step ca certificate \
  test-device.testuser.funlab.casa \
  test.crt test.key \
  --provisioner client-certs \
  --not-after 2160h

# Verify certificate attributes
openssl x509 -in test.crt -noout -text | grep -A 5 "X509v3 extensions"

# Should show:
# X509v3 Key Usage: critical
#     Digital Signature, Key Encipherment
# X509v3 Extended Key Usage:
#     TLS Web Client Authentication

# Cleanup test files
rm test.crt test.key
```

**Success Criteria:**
- ✅ Provisioner created
- ✅ Template applied
- ✅ Test certificate has correct attributes

---

### Step 2: Create SPIRE Workload Identity for Authentik

**Register Authentik as SPIRE workload:**

```bash
# SSH to spire.funlab.casa (SPIRE server)
ssh spire.funlab.casa

# Register Authentik workload
spire-server entry create \
  -parentID spiffe://funlab.casa/spire-agent/pm01 \
  -spiffeID spiffe://funlab.casa/auth/authentik \
  -selector docker:label:com.docker.compose.service:authentik-server \
  -x509SVID

# Verify registration
spire-server entry show -spiffeID spiffe://funlab.casa/auth/authentik
```

**Configure Authentik container to use SPIRE:**

```yaml
# docker-compose.yml for Authentik
services:
  authentik-server:
    image: ghcr.io/goauthentik/server:latest
    volumes:
      - /run/spire/sockets:/run/spire/sockets:ro  # Mount SPIRE socket
      - ./media:/media
      - ./certs:/certs
    environment:
      # ... existing env vars ...
      SPIFFE_ENDPOINT_SOCKET: /run/spire/sockets/agent.sock
    labels:
      - "com.docker.compose.service=authentik-server"
```

**Test SPIRE identity:**

```bash
# Inside Authentik container
docker exec -it authentik-server bash

# Fetch SPIRE SVID
/opt/spire/spire-agent api fetch x509 \
  -socketPath /run/spire/sockets/agent.sock

# Should show:
# SPIFFE ID: spiffe://funlab.casa/auth/authentik
# X.509 certificate with 1-hour TTL
```

**Success Criteria:**
- ✅ Authentik has SPIRE workload identity
- ✅ Can fetch SVID from SPIRE agent
- ✅ SVID auto-rotates (1-hour TTL)

---

### Step 3: Store step-ca Credentials in OpenBao

**Store provisioner password in OpenBao:**

```bash
# SSH to openbao.funlab.casa
ssh openbao.funlab.casa

# Login to OpenBao (if needed)
export BAO_ADDR="https://localhost:8200"
bao login

# Store step-ca provisioner password
bao kv put secret/authentik/step-ca \
  provisioner=client-certs \
  provisioner_password="<password-from-step1>" \
  api_url="https://ca.funlab.casa"

# Create policy for Authentik
cat > authentik-policy.hcl << 'EOF'
path "secret/data/authentik/step-ca" {
  capabilities = ["read"]
}
EOF

bao policy write authentik-policy authentik-policy.hcl

# Configure JWT auth for SPIRE
bao auth enable jwt

bao write auth/jwt/config \
  oidc_discovery_url="https://spire.funlab.casa:8443" \
  bound_issuer="spiffe://funlab.casa"

# Create role for Authentik workload
bao write auth/jwt/role/authentik \
  role_type="jwt" \
  bound_audiences="openbao.funlab.casa" \
  user_claim="sub" \
  bound_subject="spiffe://funlab.casa/auth/authentik" \
  policies="authentik-policy" \
  ttl="1h"
```

**Test secret retrieval:**

```bash
# Get JWT from SPIRE
JWT=$(spire-agent api fetch jwt \
  -audience openbao.funlab.casa \
  -socketPath /run/spire/sockets/agent.sock)

# Authenticate to OpenBao with JWT
export BAO_TOKEN=$(bao write -field=token auth/jwt/login \
  role=authentik \
  jwt=$JWT)

# Retrieve step-ca credentials
bao kv get secret/authentik/step-ca

# Should return:
# Key                   Value
# ---                   -----
# provisioner           client-certs
# provisioner_password  <password>
# api_url              https://ca.funlab.casa
```

**Success Criteria:**
- ✅ Credentials stored in OpenBao
- ✅ Authentik can retrieve via SPIRE JWT
- ✅ Policy allows only required access

---

### Step 4: Create Authentik Device Enrollment Flow

**Create custom flow in Authentik:**

1. **Login to Authentik Admin:**
   ```
   https://auth.funlab.casa/if/admin/
   ```

2. **Create Flow:**
   - Navigate to: Flows & Stages → Flows
   - Click: Create Flow
   - Name: "Device Enrollment"
   - Title: "Enroll This Device"
   - Slug: device-enrollment
   - Designation: Enrollment
   - Authentication: Required (user must be logged in)

3. **Create Stages:**

   **Stage 1: Device Information**
   - Type: Prompt Stage
   - Name: "device-info"
   - Fields:
     - Device Name (text, optional - auto-detected if blank)
     - Browser (hidden, auto-filled)
     - Operating System (hidden, auto-filled)

   **Stage 2: CSR Generation**
   - Type: Custom Python Stage
   - Name: "csr-generation"
   - Code:
     ```python
     from cryptography import x509
     from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID
     from cryptography.hazmat.primitives import hashes
     from cryptography.hazmat.primitives.asymmetric import rsa
     from cryptography.hazmat.primitives import serialization

     # Get user and device info
     user = request.user
     device_name = context.get('prompt_data', {}).get('device_name', 'unknown-device')

     # Generate private key
     private_key = rsa.generate_private_key(
         public_exponent=65537,
         key_size=2048
     )

     # Build CSR
     csr = x509.CertificateSigningRequestBuilder().subject_name(x509.Name([
         x509.NameAttribute(NameOID.COMMON_NAME, f"{device_name}.{user.username}.funlab.casa"),
         x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Funlab.Casa"),
         x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, "User Devices"),
     ])).add_extension(
         x509.ExtendedKeyUsage([ExtendedKeyUsageOID.CLIENT_AUTH]),
         critical=True,
     ).sign(private_key, hashes.SHA256())

     # Store in flow context
     context['private_key'] = private_key.private_bytes(
         encoding=serialization.Encoding.PEM,
         format=serialization.PrivateFormat.PKCS8,
         encryption_algorithm=serialization.NoEncryption()
     ).decode('utf-8')

     context['csr'] = csr.public_bytes(serialization.Encoding.PEM).decode('utf-8')
     context['device_cn'] = f"{device_name}.{user.username}.funlab.casa"

     return True
     ```

   **Stage 3: step-ca Certificate Issuance**
   - Type: Custom Python Stage
   - Name: "step-ca-issuance"
   - Code:
     ```python
     import requests
     import subprocess
     import json

     # Get SPIRE JWT
     jwt_result = subprocess.run([
         '/opt/spire/spire-agent', 'api', 'fetch', 'jwt',
         '-audience', 'openbao.funlab.casa',
         '-socketPath', '/run/spire/sockets/agent.sock'
     ], capture_output=True, text=True)

     spire_jwt = jwt_result.stdout.strip()

     # Authenticate to OpenBao
     vault_response = requests.post(
         'https://openbao.funlab.casa:8200/v1/auth/jwt/login',
         json={'role': 'authentik', 'jwt': spire_jwt}
     )
     vault_token = vault_response.json()['auth']['client_token']

     # Get step-ca credentials
     secrets_response = requests.get(
         'https://openbao.funlab.casa:8200/v1/secret/data/authentik/step-ca',
         headers={'X-Vault-Token': vault_token}
     )
     step_ca_creds = secrets_response.json()['data']['data']

     # Submit CSR to step-ca
     csr_pem = context['csr']
     step_ca_response = requests.post(
         f"{step_ca_creds['api_url']}/sign",
         json={
             'csr': csr_pem,
             'provisioner': step_ca_creds['provisioner'],
             'password': step_ca_creds['provisioner_password'],
             'notAfter': '2160h'  # 90 days
         }
     )

     if step_ca_response.status_code != 200:
         logger.error(f"step-ca error: {step_ca_response.text}")
         return False

     # Store signed certificate
     cert_data = step_ca_response.json()
     context['certificate'] = cert_data['crt']
     context['ca_chain'] = cert_data['ca']

     return True
     ```

   **Stage 4: PKCS#12 Packaging**
   - Type: Custom Python Stage
   - Name: "pkcs12-packaging"
   - Code:
     ```python
     from cryptography.hazmat.primitives import serialization
     from cryptography import x509
     from cryptography.hazmat.primitives.serialization import pkcs12
     import secrets

     # Load components
     private_key_pem = context['private_key'].encode('utf-8')
     cert_pem = context['certificate'].encode('utf-8')
     ca_chain_pem = context['ca_chain'].encode('utf-8')

     private_key = serialization.load_pem_private_key(private_key_pem, password=None)
     certificate = x509.load_pem_x509_certificate(cert_pem)
     ca_cert = x509.load_pem_x509_certificate(ca_chain_pem)

     # Generate random password for PKCS#12
     p12_password = secrets.token_urlsafe(16)

     # Create PKCS#12 bundle
     p12_bytes = pkcs12.serialize_key_and_certificates(
         name=context['device_cn'].encode('utf-8'),
         key=private_key,
         cert=certificate,
         cas=[ca_cert],
         encryption_algorithm=serialization.BestAvailableEncryption(p12_password.encode('utf-8'))
     )

     # Store in flow context
     context['pkcs12_bytes'] = p12_bytes
     context['pkcs12_password'] = p12_password
     context['filename'] = f"{context['device_cn']}.p12"

     return True
     ```

   **Stage 5: Download & Instructions**
   - Type: Custom Template Stage
   - Name: "download-certificate"
   - Template:
     ```html
     <div class="container">
       <h2>✅ Certificate Generated Successfully!</h2>

       <div class="alert alert-success">
         <strong>Device:</strong> {{ device_cn }}<br>
         <strong>Valid Until:</strong> {{ expiry_date }}<br>
         <strong>Serial:</strong> {{ serial_number }}
       </div>

       <div class="download-section">
         <a href="data:application/x-pkcs12;base64,{{ pkcs12_base64 }}"
            download="{{ filename }}"
            class="btn btn-primary btn-lg">
           📥 Download Certificate (.p12)
         </a>
       </div>

       <div class="alert alert-info mt-4">
         <strong>PKCS#12 Password:</strong>
         <code class="password">{{ pkcs12_password }}</code>
         <button onclick="copyPassword()" class="btn btn-sm btn-secondary">Copy</button>
       </div>

       <div class="instructions mt-4">
         <h3>Installation Instructions:</h3>
         <ul>
           <li><strong>iPhone/iPad:</strong> AirDrop file → Settings → General → VPN & Device Management → Install Profile</li>
           <li><strong>Android:</strong> Settings → Security → Install Certificate → VPN and app user certificate</li>
           <li><strong>macOS:</strong> Double-click .p12 file → Keychain Access → Enter password</li>
           <li><strong>Windows:</strong> Double-click .p12 file → Certificate Import Wizard → Enter password</li>
         </ul>
       </div>
     </div>

     <script>
     function copyPassword() {
       navigator.clipboard.writeText('{{ pkcs12_password }}');
       alert('Password copied to clipboard!');
     }
     </script>
     ```

4. **Link Stages to Flow:**
   - Device Enrollment Flow
     - Stage 1: Device Information
     - Stage 2: CSR Generation
     - Stage 3: step-ca Issuance
     - Stage 4: PKCS#12 Packaging
     - Stage 5: Download & Instructions

**Success Criteria:**
- ✅ Flow created in Authentik
- ✅ All stages configured
- ✅ Stages linked in correct order

---

### Step 5: Create "My Devices" Page

**Add custom page to Authentik:**

1. **Create Application:**
   - Applications → Create
   - Name: "My Devices"
   - Slug: my-devices
   - Provider: Proxy Provider (if needed)
   - Launch URL: /if/user/#/devices

2. **Create Custom Page:**
   ```html
   <!-- /etc/authentik/templates/if/user/devices.html -->
   {% extends "if/user/base.html" %}

   {% block content %}
   <div class="pf-c-page__main-section">
     <div class="pf-c-content">
       <h1>My Devices</h1>

       <div class="device-list">
         {% for device in user_devices %}
         <div class="device-card">
           <div class="device-info">
             <h3>{{ device.name }}</h3>
             <p>Enrolled: {{ device.enrolled_at }}</p>
             <p>Expires: {{ device.cert_expiry }}</p>
             <p>Status:
               {% if device.is_valid %}
                 <span class="badge badge-success">Valid</span>
               {% else %}
                 <span class="badge badge-danger">Expired/Revoked</span>
               {% endif %}
             </p>
           </div>
           <div class="device-actions">
             {% if device.is_valid %}
               <button onclick="renewDevice('{{ device.id }}')" class="btn btn-secondary">
                 🔄 Renew
               </button>
               <button onclick="revokeDevice('{{ device.id }}')" class="btn btn-danger">
                 ❌ Revoke
               </button>
             {% endif %}
           </div>
         </div>
         {% endfor %}
       </div>

       <div class="enroll-section mt-4">
         <a href="/flows/device-enrollment/" class="btn btn-primary btn-lg">
           ➕ Enroll This Device
         </a>
       </div>
     </div>
   </div>

   <script>
   function renewDevice(deviceId) {
     if (confirm('Renew certificate for this device?')) {
       window.location.href = `/flows/device-enrollment/?renew=${deviceId}`;
     }
   }

   function revokeDevice(deviceId) {
     if (confirm('Revoke certificate for this device? This cannot be undone.')) {
       fetch(`/api/v3/devices/${deviceId}/revoke/`, {
         method: 'POST',
         headers: {
           'Authorization': `Bearer ${getAuthToken()}`,
           'Content-Type': 'application/json'
         }
       }).then(() => {
         alert('Certificate revoked successfully');
         window.location.reload();
       });
     }
   }
   </script>
   {% endblock %}
   ```

**Success Criteria:**
- ✅ My Devices page accessible
- ✅ Shows enrolled devices
- ✅ Enrollment button works
- ✅ Revocation works

---

## User Experience Flow

### End-to-End User Journey

**1. User Wants to Enroll Phone**

```
User opens Safari on iPhone
  ↓
Navigates to https://auth.funlab.casa
  ↓
Clicks "My Devices"
  ↓
Redirected to login (if not authenticated)
  ↓
Authenticates with Face ID (passkey)
  ↓
Sees "My Devices" page (currently empty)
  ↓
Clicks "➕ Enroll This Device"
  ↓
Device Enrollment flow starts
```

**2. Enrollment Process**

```
Stage 1: Device Information
  ├─ Device Name: (auto-filled: "iPhone 13 Pro")
  ├─ Browser: Safari 17.2
  └─ OS: iOS 17.2
  User clicks "Next" →

Stage 2: CSR Generation (automatic, no user input)
  ├─ Private key generated in browser
  ├─ CSR created: CN=iphone-13-pro.user.funlab.casa
  └─ Processing... →

Stage 3: Certificate Issuance (automatic)
  ├─ Authentik → OpenBao (get credentials)
  ├─ Authentik → step-ca (submit CSR)
  ├─ step-ca signs certificate
  └─ Processing... →

Stage 4: PKCS#12 Packaging (automatic)
  ├─ Create bundle: cert + key + CA chain
  ├─ Encrypt with random password
  └─ Processing... →

Stage 5: Download
  ├─ Shows success message
  ├─ Displays PKCS#12 password
  ├─ "📥 Download Certificate" button
  └─ Installation instructions
```

**3. Certificate Installation**

```
User clicks "Download Certificate"
  ↓
iphone-13-pro.user.funlab.casa.p12 saved to device
  ↓
User opens .p12 file
  ↓
iOS prompts: "Install Profile?"
  ↓
User taps "Install"
  ↓
iOS prompts for PKCS#12 password
  ↓
User enters password (from enrollment page)
  ↓
iOS installs certificate to keychain
  ↓
Certificate appears in Settings → General → VPN & Device Management
```

**4. Accessing Protected Service**

```
User opens Safari on iPhone
  ↓
Navigates to https://test.funlab.casa
  ↓
Safari automatically presents client certificate
  ↓
NPM validates certificate
  ↓
Service loads immediately (NO login prompt!)
  ↓
Page shows: "Authenticated via: mTLS (Client Certificate)"
```

**Timeline:**
- Enrollment: ~2-3 minutes
- Installation: ~1 minute
- First access: Instant (< 1 second)
- Subsequent access: Always instant

---

## Technical Details

### Certificate Attributes

**Subject Distinguished Name:**
```
CN=iphone-13-pro.user.funlab.casa
O=Funlab.Casa
OU=User Devices
```

**X.509 Extensions:**
```
X509v3 Key Usage: critical
    Digital Signature, Key Encipherment

X509v3 Extended Key Usage:
    TLS Web Client Authentication (1.3.6.1.5.5.7.3.2)

X509v3 Basic Constraints: critical
    CA:FALSE

X509v3 Subject Alternative Name:
    DNS:iphone-13-pro.user.funlab.casa
```

**Validity:**
- Not Before: Enrollment timestamp
- Not After: Enrollment timestamp + 90 days

**Key Type:**
- RSA 2048-bit or ECDSA P-256

### PKCS#12 Bundle Structure

```
PKCS#12 Bundle (.p12 file)
├─ Friendly Name: "iphone-13-pro.user.funlab.casa"
├─ Encryption: AES-256-CBC (password-protected)
├─ Contents:
│  ├─ Private Key (encrypted)
│  ├─ Client Certificate
│  └─ CA Chain
│     ├─ step-ca Intermediate Certificate
│     └─ step-ca Root Certificate
```

**Password:**
- Random 16-byte URL-safe string
- Displayed once during enrollment
- User must copy/save (not recoverable)

### API Interactions

**Authentik → SPIRE (Get SVID):**
```bash
/opt/spire/spire-agent api fetch jwt \
  -audience openbao.funlab.casa \
  -socketPath /run/spire/sockets/agent.sock
```

**Authentik → OpenBao (Get Credentials):**
```http
POST /v1/auth/jwt/login HTTP/1.1
Host: openbao.funlab.casa:8200
Content-Type: application/json

{
  "role": "authentik",
  "jwt": "<spire-jwt-token>"
}

Response:
{
  "auth": {
    "client_token": "<vault-token>",
    "policies": ["authentik-policy"],
    "metadata": {
      "role": "authentik"
    }
  }
}
```

**Authentik → step-ca (Submit CSR):**
```http
POST /sign HTTP/1.1
Host: ca.funlab.casa:443
Content-Type: application/json

{
  "csr": "-----BEGIN CERTIFICATE REQUEST-----\n...",
  "provisioner": "client-certs",
  "password": "<provisioner-password>",
  "notAfter": "2160h"
}

Response:
{
  "crt": "-----BEGIN CERTIFICATE-----\n...",
  "ca": "-----BEGIN CERTIFICATE-----\n...",
  "certChain": [...]
}
```

---

## Testing

### Test Plan

**Test 1: End-to-End Enrollment (iPhone)**
- [ ] Navigate to auth.funlab.casa
- [ ] Login with passkey (Face ID)
- [ ] Navigate to "My Devices"
- [ ] Click "Enroll This Device"
- [ ] Complete enrollment flow
- [ ] Download .p12 file
- [ ] Install certificate
- [ ] Visit protected service
- [ ] Verify zero-click access

**Test 2: Multi-Device Enrollment**
- [ ] Enroll iPhone
- [ ] Enroll MacBook
- [ ] Enroll iPad
- [ ] Verify all devices listed in "My Devices"
- [ ] Verify each device can access services

**Test 3: Certificate Validation**
- [ ] Verify certificate attributes correct
- [ ] Verify CA chain complete
- [ ] Verify extended key usage (Client Auth)
- [ ] Verify validity period (90 days)

**Test 4: Certificate Revocation**
- [ ] Enroll device
- [ ] Access service (should work)
- [ ] Revoke certificate in Authentik
- [ ] Update CRL on NPM
- [ ] Access service again (should fail mTLS, fallback to OAuth)

**Test 5: Password Fallback**
- [ ] Visit protected service with enrolled device
- [ ] Should succeed with mTLS
- [ ] Visit from non-enrolled device
- [ ] Should redirect to Authentik
- [ ] Login with passkey
- [ ] Should succeed with OAuth

**Test 6: Certificate Renewal**
- [ ] Enroll device
- [ ] Wait until certificate near expiry (or set short TTL for testing)
- [ ] User sees renewal reminder in "My Devices"
- [ ] Click "Renew"
- [ ] New certificate issued
- [ ] Old certificate revoked
- [ ] New certificate automatically used

### Validation Criteria

**Enrollment Success:**
- ✅ .p12 file downloads
- ✅ Password displayed
- ✅ Certificate installs without errors
- ✅ Device appears in "My Devices" list

**mTLS Success:**
- ✅ Browser presents certificate automatically
- ✅ NPM validates certificate successfully
- ✅ Service accessible without login prompt
- ✅ Page shows "mTLS (Client Certificate)"

**OAuth Fallback Success:**
- ✅ Non-enrolled device redirected to login
- ✅ Passkey authentication works
- ✅ JWT token issued
- ✅ Service accessible with OAuth

---

## Troubleshooting

### Common Issues

**Issue: "Certificate generation failed"**

**Symptoms:**
- Enrollment flow fails at CSR stage
- Error: "Unable to contact step-ca"

**Diagnosis:**
```bash
# Check step-ca connectivity from Authentik
docker exec authentik-server curl -I https://ca.funlab.casa

# Check SPIRE SVID
docker exec authentik-server /opt/spire/spire-agent api fetch x509

# Check OpenBao connectivity
docker exec authentik-server curl -I https://openbao.funlab.casa:8200/v1/sys/health
```

**Resolution:**
1. Verify network connectivity (Authentik → step-ca)
2. Verify SPIRE agent running in Authentik container
3. Verify OpenBao unsealed and accessible
4. Check step-ca provisioner configuration

---

**Issue: "Certificate installed but not presented by browser"**

**Symptoms:**
- Certificate installs successfully
- Browser doesn't present certificate to server
- Falls back to OAuth login

**Diagnosis:**
- **iOS:** Settings → General → VPN & Device Management → Check certificate trust
- **macOS:** Keychain Access → Check certificate location (should be in "login" keychain)
- **Windows:** certmgr.msc → Check certificate in "Personal" store
- **Android:** Settings → Security → Trusted credentials → User tab

**Resolution:**
1. Verify certificate installed in correct keystore
2. Verify certificate trusted (iOS: tap certificate, tap "Trust", set to "Always Trust")
3. Verify browser configured to use certificates (Chrome: Settings → Privacy → Certificates)
4. Try different browser (some browsers have separate certificate stores)

---

**Issue: "Certificate validation fails at NPM"**

**Symptoms:**
- Browser presents certificate
- NPM rejects certificate
- Falls back to OAuth

**Diagnosis:**
```bash
# Check NPM certificate validation logs
docker logs nginx-proxy-manager | grep ssl_client

# Check NPM has correct CA bundle
docker exec nginx-proxy-manager ls -la /etc/nginx/ssl/client-ca/

# Check CRL
docker exec nginx-proxy-manager openssl crl -in /etc/nginx/ssl/crl.pem -text
```

**Resolution:**
1. Verify NPM has step-ca CA bundle uploaded
2. Verify `ssl_verify_client optional` configured
3. Verify CRL up-to-date
4. Check certificate not revoked

---

**Issue: "Enrollment flow hangs at certificate issuance"**

**Symptoms:**
- Flow gets stuck at "Processing..."
- Never completes
- No error message

**Diagnosis:**
```bash
# Check Authentik logs
docker logs authentik-server | grep "step-ca"

# Check step-ca logs
ssh ca.funlab.casa "journalctl -u step-ca -n 50"

# Check OpenBao logs
ssh openbao.funlab.casa "journalctl -u openbao -n 50"
```

**Resolution:**
1. Check Authentik can authenticate to OpenBao (SPIRE JWT)
2. Check step-ca API responding
3. Check provisioner password correct
4. Verify no network timeouts

---

## Next Steps

### Implementation Checklist

**Prerequisites:**
- [ ] step-ca deployed and operational
- [ ] OpenBao deployed and unsealed
- [ ] SPIRE server and agents deployed
- [ ] Authentik deployed with passkeys

**Configuration:**
- [ ] step-ca provisioner created
- [ ] SPIRE workload identity for Authentik
- [ ] OpenBao secrets and policies
- [ ] Authentik enrollment flow created
- [ ] "My Devices" page created

**Testing:**
- [ ] Test enrollment on iPhone
- [ ] Test enrollment on Android
- [ ] Test enrollment on macOS
- [ ] Test enrollment on Windows
- [ ] Test certificate validation
- [ ] Test certificate revocation

**Documentation:**
- [ ] User guide for enrollment
- [ ] Installation instructions per platform
- [ ] Troubleshooting guide
- [ ] Admin runbook

**Production:**
- [ ] Roll out to pilot users
- [ ] Monitor enrollment success rate
- [ ] Gather user feedback
- [ ] Iterate on UX
- [ ] Full deployment

---

**Status:** 📋 Design Complete
**Next Action:** Begin Step 1 (Configure step-ca provisioner)
**Timeline:** 1 week for full implementation

**Last Updated:** 2026-02-11
**Author:** Infrastructure Team
