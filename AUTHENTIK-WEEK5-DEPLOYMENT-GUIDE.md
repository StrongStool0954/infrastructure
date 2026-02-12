# Authentik Deployment Guide - Week 5

**Project:** Deploy Authentik at auth.funlab.casa
**Timeline:** Week 5 (7 days)
**Status:** 🔄 In Progress
**Prerequisites:** OpenBao, step-ca, SPIRE operational

---

## Overview

Deploy Authentik as the central authentication provider for Funlab.Casa zero-trust architecture, with PostgreSQL backend, Redis caching, and passkey (WebAuthn/FIDO2) authentication.

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   auth.funlab.casa                       │
│                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌───────────┐ │
│  │  Authentik   │───▶│  PostgreSQL  │    │   Redis   │ │
│  │   Server     │    │   Database   │    │   Cache   │ │
│  │              │◀───┤              │    │           │ │
│  └──────┬───────┘    └──────────────┘    └─────▲─────┘ │
│         │                                        │       │
│         │ SPIRE SVID                    Sessions │       │
│         ▼                                        │       │
│  ┌──────────────┐                       ┌───────┴─────┐ │
│  │   step-ca    │                       │   Workers   │ │
│  │  (certs)     │                       │  (celery)   │ │
│  └──────────────┘                       └─────────────┘ │
└─────────────────────────────────────────────────────────┘
         │
         ▼
   ┌──────────────┐
   │   OpenBao    │
   │  (secrets)   │
   └──────────────┘
```

### What You'll Deploy

- **PostgreSQL 16** - Authentik database backend
- **Redis 7** - Session cache and Celery broker
- **Authentik 2024.2** - Authentication server + workers
- **TLS Certificate** - From step-ca for auth.funlab.casa
- **Initial Configuration** - Admin account, passkey auth, test OAuth app

---

## Day 1-2: Deploy PostgreSQL + Redis

### Step 1: Create Docker Network

```bash
# Create dedicated network for Authentik stack
docker network create authentik-network
```

### Step 2: Deploy PostgreSQL

**Create PostgreSQL directory structure:**

```bash
sudo mkdir -p /opt/authentik/postgres/data
sudo mkdir -p /opt/authentik/postgres/init
sudo chown -R 999:999 /opt/authentik/postgres/data
```

**Create initialization script:**

```bash
cat > /opt/authentik/postgres/init/01-init-db.sql << 'EOF'
-- Create Authentik database
CREATE DATABASE authentik;

-- Create Authentik user
CREATE USER authentik WITH ENCRYPTED PASSWORD 'CHANGE_THIS_PASSWORD';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE authentik TO authentik;

-- Connect to authentik database
\c authentik

-- Grant schema privileges
GRANT ALL ON SCHEMA public TO authentik;
EOF
```

**Generate strong PostgreSQL password:**

```bash
# Generate password
POSTGRES_PASSWORD=$(openssl rand -base64 32)
AUTHENTIK_DB_PASSWORD=$(openssl rand -base64 32)

echo "PostgreSQL root password: $POSTGRES_PASSWORD"
echo "Authentik DB password: $AUTHENTIK_DB_PASSWORD"

# Store in OpenBao
bao kv put secret/authentik/postgres \
  postgres_password="$POSTGRES_PASSWORD" \
  authentik_password="$AUTHENTIK_DB_PASSWORD"
```

**Update initialization script with password:**

```bash
# Replace placeholder with actual password
sudo sed -i "s/CHANGE_THIS_PASSWORD/$AUTHENTIK_DB_PASSWORD/" \
  /opt/authentik/postgres/init/01-init-db.sql
```

**Create PostgreSQL docker-compose.yml:**

```bash
cat > /opt/authentik/postgres/docker-compose.yml << 'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    container_name: authentik-postgres
    restart: unless-stopped

    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: postgres
      PGDATA: /var/lib/postgresql/data/pgdata

    volumes:
      - ./data:/var/lib/postgresql/data
      - ./init:/docker-entrypoint-initdb.d:ro

    networks:
      - authentik-network

    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

    labels:
      - "com.docker.compose.project=authentik"
      - "com.docker.compose.service=postgres"

networks:
  authentik-network:
    external: true
EOF
```

**Create .env file for PostgreSQL:**

```bash
cat > /opt/authentik/postgres/.env << EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
EOF

chmod 600 /opt/authentik/postgres/.env
```

**Start PostgreSQL:**

```bash
cd /opt/authentik/postgres
docker-compose up -d

# Wait for PostgreSQL to be ready
sleep 10

# Verify PostgreSQL is running
docker-compose ps
docker-compose logs | grep "database system is ready"
```

**Test database connection:**

```bash
# Test connection as authentik user
docker exec -it authentik-postgres \
  psql -U authentik -d authentik -c "\dt"

# Should show "Did not find any relations" (empty database, expected)
```

### Step 3: Deploy Redis

**Create Redis directory:**

```bash
sudo mkdir -p /opt/authentik/redis/data
sudo chown -R 999:999 /opt/authentik/redis/data
```

**Create Redis configuration:**

```bash
cat > /opt/authentik/redis/redis.conf << 'EOF'
# Redis configuration for Authentik

# Network
bind 0.0.0.0
port 6379
protected-mode yes

# Persistence
save 900 1
save 300 10
save 60 10000

dir /data
dbfilename dump.rdb

# Memory
maxmemory 256mb
maxmemory-policy allkeys-lru

# Logging
loglevel notice

# Security
requirepass CHANGE_THIS_PASSWORD
EOF
```

**Generate Redis password:**

```bash
# Generate password
REDIS_PASSWORD=$(openssl rand -base64 32)
echo "Redis password: $REDIS_PASSWORD"

# Store in OpenBao
bao kv put secret/authentik/redis \
  password="$REDIS_PASSWORD"

# Update redis.conf with password
sudo sed -i "s/CHANGE_THIS_PASSWORD/$REDIS_PASSWORD/" \
  /opt/authentik/redis/redis.conf
```

**Create Redis docker-compose.yml:**

```bash
cat > /opt/authentik/redis/docker-compose.yml << 'EOF'
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    container_name: authentik-redis
    restart: unless-stopped

    command: redis-server /usr/local/etc/redis/redis.conf

    volumes:
      - ./data:/data
      - ./redis.conf:/usr/local/etc/redis/redis.conf:ro

    networks:
      - authentik-network

    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

    labels:
      - "com.docker.compose.project=authentik"
      - "com.docker.compose.service=redis"

networks:
  authentik-network:
    external: true
EOF
```

**Start Redis:**

```bash
cd /opt/authentik/redis
docker-compose up -d

# Wait for Redis to be ready
sleep 5

# Verify Redis is running
docker-compose ps
docker-compose logs | grep "Ready to accept connections"
```

**Test Redis connection:**

```bash
# Test Redis with password
docker exec -it authentik-redis \
  redis-cli -a "$REDIS_PASSWORD" ping

# Should return "PONG"
```

### Step 4: Verify Day 1-2 Completion

**Checklist:**

```bash
# All containers running
docker ps | grep authentik

# PostgreSQL healthy
docker exec authentik-postgres pg_isready -U postgres

# Redis healthy
docker exec authentik-redis redis-cli -a "$REDIS_PASSWORD" ping

# Network exists
docker network ls | grep authentik-network

# Secrets stored in OpenBao
bao kv get secret/authentik/postgres
bao kv get secret/authentik/redis
```

**Expected output:**
- ✅ 2 containers running (postgres, redis)
- ✅ PostgreSQL: "accepting connections"
- ✅ Redis: "PONG"
- ✅ Network: authentik-network exists
- ✅ OpenBao: Secrets retrieved successfully

---

## Day 3-4: Deploy Authentik Container

### Step 5: Generate TLS Certificate from step-ca

**Create certificate directory:**

```bash
sudo mkdir -p /opt/authentik/certs
```

**Generate certificate for auth.funlab.casa:**

```bash
cd /opt/authentik/certs

# Generate certificate using step-ca
step ca certificate auth.funlab.casa \
  auth.funlab.casa.crt \
  auth.funlab.casa.key \
  --provisioner admin \
  --not-after 8760h

# Verify certificate
openssl x509 -in auth.funlab.casa.crt -noout -text | grep -A2 "Subject:"

# Set permissions
chmod 644 auth.funlab.casa.crt
chmod 600 auth.funlab.casa.key
```

**Download root CA certificate:**

```bash
# Get root CA from step-ca
step ca root /opt/authentik/certs/root_ca.crt

# Verify chain
openssl verify -CAfile root_ca.crt auth.funlab.casa.crt
```

### Step 6: Generate Authentik Secret Key

```bash
# Generate Authentik secret key
AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60)
echo "Authentik secret key: $AUTHENTIK_SECRET_KEY"

# Store in OpenBao
bao kv put secret/authentik/app \
  secret_key="$AUTHENTIK_SECRET_KEY"
```

### Step 7: Create Authentik Configuration

**Create Authentik directory:**

```bash
sudo mkdir -p /opt/authentik/authentik/{media,custom-templates,certs}
sudo mkdir -p /opt/authentik/authentik/blueprints
```

**Create Authentik docker-compose.yml:**

```bash
cat > /opt/authentik/authentik/docker-compose.yml << 'EOF'
version: '3.8'

services:
  authentik-server:
    image: ghcr.io/goauthentik/server:2024.2
    container_name: authentik-server
    restart: unless-stopped

    command: server

    environment:
      # PostgreSQL
      AUTHENTIK_POSTGRESQL__HOST: authentik-postgres
      AUTHENTIK_POSTGRESQL__NAME: authentik
      AUTHENTIK_POSTGRESQL__USER: authentik
      AUTHENTIK_POSTGRESQL__PASSWORD: ${AUTHENTIK_DB_PASSWORD}

      # Redis
      AUTHENTIK_REDIS__HOST: authentik-redis
      AUTHENTIK_REDIS__PASSWORD: ${REDIS_PASSWORD}

      # Authentik
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
      AUTHENTIK_ERROR_REPORTING__ENABLED: "false"
      AUTHENTIK_LOG_LEVEL: info

      # Email (configure later)
      AUTHENTIK_EMAIL__HOST: localhost
      AUTHENTIK_EMAIL__PORT: 25
      AUTHENTIK_EMAIL__FROM: authentik@funlab.casa

      # Trust proxy headers from NPM
      AUTHENTIK_LISTEN__TRUSTED_PROXY_IP: 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16

    volumes:
      - ./media:/media
      - ./custom-templates:/templates
      - ./certs:/certs:ro

    ports:
      - "9000:9000"
      - "9443:9443"

    networks:
      - authentik-network

    depends_on:
      - authentik-postgres
      - authentik-redis

    labels:
      - "com.docker.compose.project=authentik"
      - "com.docker.compose.service=authentik-server"

  authentik-worker:
    image: ghcr.io/goauthentik/server:2024.2
    container_name: authentik-worker
    restart: unless-stopped

    command: worker

    environment:
      # PostgreSQL
      AUTHENTIK_POSTGRESQL__HOST: authentik-postgres
      AUTHENTIK_POSTGRESQL__NAME: authentik
      AUTHENTIK_POSTGRESQL__USER: authentik
      AUTHENTIK_POSTGRESQL__PASSWORD: ${AUTHENTIK_DB_PASSWORD}

      # Redis
      AUTHENTIK_REDIS__HOST: authentik-redis
      AUTHENTIK_REDIS__PASSWORD: ${REDIS_PASSWORD}

      # Authentik
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
      AUTHENTIK_ERROR_REPORTING__ENABLED: "false"
      AUTHENTIK_LOG_LEVEL: info

    volumes:
      - ./media:/media
      - ./custom-templates:/templates
      - /var/run/docker.sock:/var/run/docker.sock

    networks:
      - authentik-network

    depends_on:
      - authentik-postgres
      - authentik-redis

    labels:
      - "com.docker.compose.project=authentik"
      - "com.docker.compose.service=authentik-worker"

networks:
  authentik-network:
    external: true
EOF
```

**Create .env file for Authentik:**

```bash
# Retrieve secrets from OpenBao
AUTHENTIK_DB_PASSWORD=$(bao kv get -field=authentik_password secret/authentik/postgres)
REDIS_PASSWORD=$(bao kv get -field=password secret/authentik/redis)
AUTHENTIK_SECRET_KEY=$(bao kv get -field=secret_key secret/authentik/app)

cat > /opt/authentik/authentik/.env << EOF
AUTHENTIK_DB_PASSWORD=$AUTHENTIK_DB_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD
AUTHENTIK_SECRET_KEY=$AUTHENTIK_SECRET_KEY
EOF

chmod 600 /opt/authentik/authentik/.env
```

### Step 8: Start Authentik

```bash
cd /opt/authentik/authentik
docker-compose up -d

# Watch logs for startup
docker-compose logs -f
```

**Wait for initialization (look for these log entries):**

```
authentik-server | INFO     authentik.root: Starting authentik server
authentik-server | INFO     authentik.root: Using PostgreSQL database
authentik-server | INFO     authentik.root: Running database migrations
authentik-worker | INFO     authentik.root: Starting authentik worker
```

**Verify Authentik is running:**

```bash
# Check containers
docker ps | grep authentik

# Should see:
# - authentik-server (port 9000, 9443)
# - authentik-worker
# - authentik-postgres
# - authentik-redis

# Test HTTP endpoint
curl -I http://localhost:9000/if/flow/initial-setup/

# Should return HTTP 302 or 200
```

### Step 9: Configure NPM Reverse Proxy

**Add auth.funlab.casa to NPM:**

1. Log into NPM (Nginx Proxy Manager)
2. Add Proxy Host:
   - **Domain Names:** auth.funlab.casa
   - **Scheme:** http
   - **Forward Hostname/IP:** [authentik-server container IP or hostname]
   - **Forward Port:** 9000
   - **Cache Assets:** Yes
   - **Block Common Exploits:** Yes
   - **Websockets Support:** Yes

3. SSL Certificate:
   - **SSL Certificate:** Use existing step-ca certificate OR request new one
   - **Force SSL:** Yes
   - **HTTP/2 Support:** Yes
   - **HSTS Enabled:** Yes

4. Advanced configuration:
   ```nginx
   # Trust Authentik's response headers
   proxy_set_header Host $host;
   proxy_set_header X-Real-IP $remote_addr;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   proxy_set_header X-Forwarded-Proto $scheme;
   proxy_set_header X-Forwarded-Host $host;

   # Support large headers (for OAuth tokens)
   proxy_buffer_size 128k;
   proxy_buffers 4 256k;
   proxy_busy_buffers_size 256k;
   ```

**Alternative: Direct configuration (if not using NPM UI):**

```bash
# Get Authentik container IP
AUTHENTIK_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' authentik-server)

# Add to /etc/nginx/sites-available/auth.funlab.casa
cat > /etc/nginx/sites-available/auth.funlab.casa << EOF
server {
    listen 443 ssl http2;
    server_name auth.funlab.casa;

    ssl_certificate /opt/authentik/certs/auth.funlab.casa.crt;
    ssl_certificate_key /opt/authentik/certs/auth.funlab.casa.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://$AUTHENTIK_IP:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;

        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }
}

server {
    listen 80;
    server_name auth.funlab.casa;
    return 301 https://\$host\$request_uri;
}
EOF

# Enable site
ln -s /etc/nginx/sites-available/auth.funlab.casa /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx
```

### Step 10: Verify Day 3-4 Completion

**Checklist:**

```bash
# All containers running
docker ps | grep authentik

# Authentik accessible via HTTP (local)
curl -I http://localhost:9000/

# Authentik accessible via HTTPS (through NPM)
curl -I https://auth.funlab.casa/

# Database migrations completed
docker logs authentik-server | grep "migrations"

# Worker is processing tasks
docker logs authentik-worker | grep "celery"
```

**Expected output:**
- ✅ 4 containers running (server, worker, postgres, redis)
- ✅ HTTP 200 or 302 from localhost:9000
- ✅ HTTPS 200 or 302 from auth.funlab.casa
- ✅ Migrations: "Applied X migrations"
- ✅ Worker: "ready" in logs

---

## Day 5: Initial Setup + Passkey Config

### Step 11: Complete Initial Setup Wizard

**Access Authentik:**

1. Open browser: `https://auth.funlab.casa/if/flow/initial-setup/`

2. **Create Admin Account:**
   - Email: `admin@funlab.casa`
   - Username: `admin`
   - Password: Use strong password (store in 1Password!)

3. **Initial Configuration:**
   - Skip email configuration (we'll do this later)
   - Complete wizard

4. **Log into Admin Interface:**
   - Go to `https://auth.funlab.casa/if/admin/`
   - Login with admin credentials

### Step 12: Configure WebAuthn/Passkey Authentication

**Enable WebAuthn Stage:**

1. Navigate to **Flows & Stages** → **Stages**

2. Find or create **WebAuthn Authenticator Validation Stage**:
   - Name: `webauthn-validation`
   - User verification: `required`
   - Authenticator attachment: `platform` (for Face ID/Touch ID)
   - Resident key requirement: `preferred`

3. Find or create **WebAuthn Device Setup Stage**:
   - Name: `webauthn-setup`
   - User verification: `required`
   - Authenticator attachment: `platform`
   - Resident key requirement: `preferred`

**Modify Default Authentication Flow:**

1. Navigate to **Flows & Stages** → **Flows**

2. Edit **default-authentication-flow**:
   - Click **Stage Bindings**
   - Add WebAuthn stage BEFORE password stage:
     ```
     Order 10: identification (existing)
     Order 15: webauthn-validation (NEW)
     Order 20: password (existing)
     Order 30: mfa (existing)
     ```

   - Set policy: "If WebAuthn device enrolled, require it; otherwise fall back to password"

**Create Passkey Enrollment Flow:**

1. Create new flow:
   - Name: `passkey-enrollment`
   - Title: `Enroll Passkey (Face ID / Touch ID)`
   - Designation: `enrollment`

2. Add stages:
   - Order 10: `prompt-username-email` (collect user info)
   - Order 20: `user-write` (create user account)
   - Order 30: `webauthn-setup` (enroll passkey)
   - Order 40: `user-login` (log them in)

3. **Bind flow to tenant:**
   - Navigate to **System** → **Tenants**
   - Edit `authentik-default` tenant
   - Enrollment flow: `passkey-enrollment`
   - Save

### Step 13: Test Passkey Authentication

**Enroll Test User with Passkey:**

1. Open **incognito/private browser window**
2. Go to `https://auth.funlab.casa/if/flow/passkey-enrollment/`
3. Fill in user details:
   - Email: `testuser@funlab.casa`
   - Username: `testuser`
4. **Click "Set up Passkey"**
   - On macOS: Touch ID prompt will appear
   - On iOS: Face ID prompt will appear
5. Complete enrollment
6. Should be logged in automatically

**Test Passkey Login:**

1. Log out from test user
2. Go to `https://auth.funlab.casa/`
3. Enter username: `testuser`
4. **Passkey prompt should appear automatically** (no password needed!)
5. Use Touch ID / Face ID
6. Should be logged in instantly

**Verify in Admin Interface:**

1. Log back in as admin
2. Navigate to **Directory** → **Users**
3. Click on `testuser`
4. Click **Devices** tab
5. Should see WebAuthn device enrolled with:
   - Type: WebAuthn
   - Name: (device identifier)
   - Created: (timestamp)

### Step 14: Configure Branding

**Customize Tenant:**

1. Navigate to **System** → **Tenants**
2. Edit `authentik-default`:
   - **Branding title:** `Funlab.Casa`
   - **Branding logo:** (upload logo if you have one)
   - **Branding favicon:** (upload favicon if you have one)
   - **Footer links:** Add documentation links

**Customize Themes (Optional):**

1. Navigate to **Customization** → **Flows**
2. Edit flows to customize:
   - Welcome messages
   - Help text
   - Button labels

### Step 15: Verify Day 5 Completion

**Checklist:**

- ✅ Admin account created and accessible
- ✅ WebAuthn stages configured
- ✅ Default auth flow includes passkey validation
- ✅ Passkey enrollment flow created and works
- ✅ Test user enrolled with passkey successfully
- ✅ Test user can login with passkey (no password!)
- ✅ Branding updated to "Funlab.Casa"

**Test from multiple devices:**
- [ ] macOS Safari (Touch ID)
- [ ] iOS Safari (Face ID)
- [ ] Android Chrome (fingerprint)

---

## Day 6-7: Create Test OAuth Application

### Step 16: Create OAuth2 Provider

**Create Provider:**

1. Navigate to **Applications** → **Providers**
2. Click **Create**
3. Select **OAuth2/OpenID Provider**

**Provider Configuration:**

- **Name:** `test-validation-service`
- **Authentication flow:** `default-authentication-flow`
- **Authorization flow:** `default-provider-authorization-implicit-consent`

**Protocol Settings:**

- **Client Type:** `Confidential`
- **Client ID:** (auto-generated, copy this!)
- **Client Secret:** (auto-generated, copy this!)
- **Redirect URIs:**
  ```
  https://test.funlab.casa/oauth/callback
  https://test.funlab.casa/auth/callback
  http://localhost:3000/oauth/callback
  ```

**Advanced Settings:**

- **Scopes:**
  - `openid` (required)
  - `profile`
  - `email`
  - `groups`

- **Subject Mode:** `Based on the User's UUID`
- **Include claims in id_token:** Yes
- **Issuer Mode:** `Per Provider`

**Token Settings:**

- **Access token validity:** `minutes=60`
- **Refresh token validity:** `days=30`
- **Signing Key:** `authentik Self-signed Certificate`

**Save Provider**

### Step 17: Create Application

**Create Application:**

1. Navigate to **Applications** → **Applications**
2. Click **Create**

**Application Configuration:**

- **Name:** `Test Validation Service`
- **Slug:** `test-validation-service`
- **Provider:** `test-validation-service` (select the provider you just created)
- **Launch URL:** `https://test.funlab.casa`

**Icon (Optional):**
- Upload icon or leave default

**Policy Bindings (Optional):**
- Leave empty for now (all authenticated users can access)

**UI Settings:**

- **Description:** `Hello World validation service for testing Authentik OAuth flow`
- **Publisher:** `Funlab.Casa`
- **Open in new tab:** No

**Save Application**

### Step 18: Store OAuth Credentials in OpenBao

```bash
# Retrieve client ID and secret from Authentik UI
# Store in OpenBao

bao kv put secret/authentik/oauth/test-validation-service \
  client_id="<CLIENT_ID_FROM_AUTHENTIK>" \
  client_secret="<CLIENT_SECRET_FROM_AUTHENTIK>" \
  issuer_url="https://auth.funlab.casa/application/o/test-validation-service/" \
  redirect_uri="https://test.funlab.casa/oauth/callback"
```

### Step 19: Test OAuth Flow

**Using OAuth Debugger:**

1. Go to `https://oauthdebugger.com/`

2. **Configuration:**
   - **Authorize URI:** `https://auth.funlab.casa/application/o/authorize/`
   - **Client ID:** (paste from Authentik)
   - **Scope:** `openid profile email`
   - **Response Type:** `code`
   - **Use PKCE:** Yes

3. Click **Send Request**

4. **Should redirect to Authentik:**
   - Login with passkey (testuser)
   - Consent screen (if not implicit consent)
   - Redirect back with authorization code

5. **Exchange code for token:**
   ```bash
   curl -X POST https://auth.funlab.casa/application/o/token/ \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "grant_type=authorization_code" \
     -d "client_id=<CLIENT_ID>" \
     -d "client_secret=<CLIENT_SECRET>" \
     -d "code=<AUTHORIZATION_CODE>" \
     -d "redirect_uri=https://test.funlab.casa/oauth/callback"
   ```

6. **Should receive tokens:**
   ```json
   {
     "access_token": "...",
     "token_type": "Bearer",
     "expires_in": 3600,
     "refresh_token": "...",
     "id_token": "..."
   }
   ```

**Decode ID Token:**

```bash
# Copy id_token from response
# Decode at https://jwt.io/

# Should see claims:
{
  "iss": "https://auth.funlab.casa/application/o/test-validation-service/",
  "sub": "<user-uuid>",
  "aud": "<client-id>",
  "exp": <timestamp>,
  "iat": <timestamp>,
  "email": "testuser@funlab.casa",
  "name": "Test User",
  "preferred_username": "testuser",
  "groups": []
}
```

### Step 20: Create Test Groups (For Future Authorization)

**Create Groups:**

1. Navigate to **Directory** → **Groups**
2. Create groups for future use:
   - **Name:** `authenticated-users`
     - **Description:** All authenticated users
   - **Name:** `test-service-users`
     - **Description:** Users allowed to access test validation service
   - **Name:** `admins`
     - **Description:** Administrative users

**Add Test User to Groups:**

1. Navigate to **Directory** → **Users**
2. Click on `testuser`
3. Click **Groups** tab
4. Add to groups:
   - `authenticated-users`
   - `test-service-users`

**Verify Groups in Token:**

1. Repeat OAuth test from Step 19
2. Decode id_token
3. Should now see:
   ```json
   {
     "groups": [
       "authenticated-users",
       "test-service-users"
     ]
   }
   ```

### Step 21: Verify Day 6-7 Completion

**Checklist:**

- ✅ OAuth2 provider created (`test-validation-service`)
- ✅ Application created and linked to provider
- ✅ Client credentials stored in OpenBao
- ✅ OAuth authorization flow works (oauthdebugger.com)
- ✅ Token exchange successful
- ✅ ID token contains correct claims (email, name, sub)
- ✅ Groups created (authenticated-users, test-service-users, admins)
- ✅ Groups appear in ID token claims

**Test Scenarios:**

- [ ] Login with passkey → OAuth → Receive token
- [ ] Token refresh works
- [ ] Logout works
- [ ] Multiple sessions work (desktop + mobile)

---

## Week 5 Completion Checklist

### Infrastructure ✅

- [ ] PostgreSQL deployed and healthy
- [ ] Redis deployed and healthy
- [ ] Authentik server running
- [ ] Authentik worker running
- [ ] All secrets stored in OpenBao
- [ ] TLS certificate from step-ca installed
- [ ] NPM reverse proxy configured
- [ ] DNS resolves auth.funlab.casa

### Configuration ✅

- [ ] Admin account created
- [ ] WebAuthn/Passkey authentication configured
- [ ] Default auth flow uses passkeys
- [ ] Passkey enrollment flow created
- [ ] Test user enrolled with passkey
- [ ] Branding updated to Funlab.Casa

### OAuth Integration ✅

- [ ] OAuth2 provider created
- [ ] Test application created
- [ ] Client credentials in OpenBao
- [ ] OAuth flow tested and working
- [ ] ID token contains correct claims
- [ ] Groups configured and in token
- [ ] Refresh token works

### Testing ✅

- [ ] Passkey login works on macOS (Touch ID)
- [ ] Passkey login works on iOS (Face ID)
- [ ] OAuth authorization flow works
- [ ] Token exchange successful
- [ ] Token refresh successful
- [ ] Multiple concurrent sessions work

---

## Troubleshooting

### PostgreSQL Issues

**Problem:** Database connection refused

```bash
# Check if PostgreSQL is running
docker ps | grep postgres

# Check logs
docker logs authentik-postgres

# Test connection
docker exec -it authentik-postgres pg_isready -U postgres

# Verify network
docker network inspect authentik-network
```

**Problem:** Authentication failed

```bash
# Verify password in .env matches database
docker exec -it authentik-postgres psql -U postgres -c "SELECT usename FROM pg_user;"

# Reset password if needed
docker exec -it authentik-postgres psql -U postgres -c "ALTER USER authentik WITH PASSWORD 'new_password';"
```

### Redis Issues

**Problem:** Redis connection refused

```bash
# Check if Redis is running
docker ps | grep redis

# Test connection
docker exec -it authentik-redis redis-cli -a "$REDIS_PASSWORD" ping

# Check logs
docker logs authentik-redis
```

**Problem:** Authentication failed

```bash
# Verify password in redis.conf
docker exec -it authentik-redis cat /usr/local/etc/redis/redis.conf | grep requirepass

# Update password and restart
docker-compose restart redis
```

### Authentik Issues

**Problem:** Authentik not starting

```bash
# Check logs
docker logs authentik-server
docker logs authentik-worker

# Common issues:
# - Database migrations failed
# - Redis connection failed
# - Missing environment variables

# Verify environment
docker exec authentik-server env | grep AUTHENTIK
```

**Problem:** Migrations failed

```bash
# Run migrations manually
docker exec -it authentik-server ak migrate

# If migrations are stuck, check PostgreSQL
docker exec -it authentik-postgres psql -U authentik -d authentik -c "\dt"
```

**Problem:** Can't access admin interface

```bash
# Reset admin password
docker exec -it authentik-server ak create_admin_group
docker exec -it authentik-server ak change_password admin

# Create new admin user
docker exec -it authentik-server ak create_admin --username newadmin --email admin@funlab.casa
```

### Passkey Issues

**Problem:** Passkey enrollment fails

- Check browser console for errors
- Verify HTTPS is working (passkeys require secure context)
- Verify domain matches (auth.funlab.casa)
- Try different browser (Safari, Chrome, Firefox)

**Problem:** Passkey not prompting on login

- Verify WebAuthn stage is in authentication flow
- Check stage order (should be before password)
- Verify user has WebAuthn device enrolled
- Check browser supports WebAuthn

### OAuth Issues

**Problem:** Redirect URI mismatch

```bash
# Verify redirect URIs in provider match application
# Check for trailing slashes
# Verify HTTPS vs HTTP
```

**Problem:** Token exchange fails

```bash
# Verify client_id and client_secret
bao kv get secret/authentik/oauth/test-validation-service

# Check provider configuration
# Verify client type is "Confidential"
```

**Problem:** ID token missing claims

- Verify scopes include `openid profile email`
- Check "Include claims in id_token" is enabled
- Verify user has email address set
- Check groups are assigned to user

---

## Next Steps (Week 6)

After completing Week 5, you're ready for:

**Week 6-7: Device Enrollment Flow**
- Configure step-ca provisioner for client certificates
- Create SPIRE workload identity for Authentik
- Build 5-stage enrollment flow in Authentik
- Create "My Devices" page
- Test end-to-end certificate enrollment

**Reference:** See `AUTHENTIK-DEVICE-ENROLLMENT-FLOW.md` for detailed implementation.

---

## Quick Reference Commands

**View all Authentik containers:**
```bash
docker ps | grep authentik
```

**View logs:**
```bash
docker logs -f authentik-server
docker logs -f authentik-worker
```

**Restart Authentik:**
```bash
cd /opt/authentik/authentik
docker-compose restart
```

**Access database:**
```bash
docker exec -it authentik-postgres psql -U authentik -d authentik
```

**Access Redis:**
```bash
docker exec -it authentik-redis redis-cli -a "$REDIS_PASSWORD"
```

**Check secrets in OpenBao:**
```bash
bao kv get secret/authentik/postgres
bao kv get secret/authentik/redis
bao kv get secret/authentik/app
bao kv get secret/authentik/oauth/test-validation-service
```

**Backup database:**
```bash
docker exec authentik-postgres pg_dump -U authentik authentik > authentik-backup-$(date +%Y%m%d).sql
```

**Restore database:**
```bash
cat authentik-backup.sql | docker exec -i authentik-postgres psql -U authentik -d authentik
```

---

**Week 5 Status:** 🔄 In Progress
**Next Milestone:** Week 6 - Device Enrollment Flow
**Documentation:** This guide + AUTHENTIK-DEVICE-ENROLLMENT-FLOW.md
**Support:** Check troubleshooting section above
