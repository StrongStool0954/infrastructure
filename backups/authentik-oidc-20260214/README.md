# Authentik OIDC Integration - Configuration Backup
**Date**: February 14, 2026
**Status**: ✅ Fully Operational

## Overview

Complete OIDC authentication integration between Authentik, OpenBao, and step-ca. This enables centralized user authentication and certificate issuance via OIDC tokens.

## What Was Implemented

### Phase 1: Authentik OIDC Providers (Blueprints)
- **openbao-oidc-provider.yaml** - OAuth2/OIDC provider for OpenBao authentication
- **step-ca-oidc-provider.yaml** - OAuth2/OIDC provider for step-ca certificate issuance

### Phase 2: OpenBao OIDC Auth Backend
- **OIDC Auth Method**: Enabled at `auth/oidc/` with RS256 support
- **Three Roles**:
  - `admin` - Full PKI management (policies: admin, pki-admin)
  - `cert-user` - Certificate issuance only (policy: pki-issue)
  - `default` - Read-only access (policy: read-only)
- **Policies Created**:
  - `admin` - Full access to PKI, secrets, database, system health
  - `pki-admin` - Comprehensive PKI management
  - `pki-issue` - Certificate issuance for specific roles

### Phase 3: step-ca OIDC Provisioner
- **Provisioner Name**: authentik
- **Certificate Template**: `/etc/step-ca/templates/oidc-certificate.tpl`
  - Organization: Funlab.Casa
  - OU: OIDC Users
  - Key Usage: digitalSignature, keyEncipherment
  - Extended Key Usage: clientAuth, emailProtection
- **Claims**:
  - Default TTL: 24h
  - Max TTL: 168h
  - Min TTL: 5m

## Critical Configuration Details

### JWT Signing Algorithm Fix
**Problem**: Authentik was signing JWT tokens with HS256 (symmetric HMAC), but OpenBao/step-ca require RS256 (asymmetric RSA) for security.

**Solution**: Assigned RSA certificate keypair (`authentik Self-signed Certificate`) to both providers' `signing_key` field.

### Groups Scope Mapping
**Problem**: OIDC tokens didn't include user groups, causing "groups claim not found" errors.

**Solution**:
1. Created custom `ScopeMapping` with scope_name="groups"
2. Expression: `return {"groups": [group.name for group in request.user.ak_groups.all()]}`
3. Added to both providers' `property_mappings`
4. Updated OpenBao roles to request `oidc_scopes="openid,profile,email,groups"`

### OpenBao Algorithm Support
**Problem**: OpenBao's `jwt_supported_algs` was empty, causing RS256 tokens to be rejected.

**Solution**: Explicitly configured `jwt_supported_algs=["RS256"]` in OpenBao OIDC auth config.

## User Groups

- **openbao-admins** - Full PKI admin access (users: admin@funlab.casa)
- **openbao-cert-users** - Certificate issuance (users: testuser1)
- **step-ca-users** - Can request certificates from step-ca (users: testuser1, admin@funlab.casa)

## Testing Performed

### ✅ OpenBao OIDC Authentication
```bash
# Web UI login successful
URL: https://openbao.funlab.casa:8088/ui/
Method: OIDC
Role: admin
Result: Authenticated successfully with admin + pki-admin policies
```

### ✅ Certificate Issuance via OpenBao
```bash
# Issued test certificate after OIDC login
Common Name: test-oidc.funlab.casa
Key Type: EC (ECDSA)
Serial: 16:85:9c:8d:69:14:eb:35:16:56:00:53:88:99:7f:fa:f5:e8:68:28
Result: SUCCESS
```

### ✅ step-ca OIDC Provisioner
```bash
# OIDC flow initiated successfully
Provisioner: authentik (OIDC)
Device URL: https://auth.funlab.casa/device
Result: Flow working, requires browser completion
```

## Known Issues & Workarounds

### 1. Database Credential Expiration (1-hour TTL)
**Symptom**: Authentik shows "Server Error" / "password authentication failed"

**Fix**:
```bash
# On spire.funlab.casa
export BAO_ADDR='https://openbao.funlab.casa:8088'
export BAO_SKIP_VERIFY=true
export BAO_TOKEN=$(sudo cat /root/.openbao-token)

# Generate fresh credentials
NEW_CREDS=$(bao read database/creds/authentik -format=json)
NEW_USER=$(echo $NEW_CREDS | jq -r .data.username)
NEW_PASS=$(echo $NEW_CREDS | jq -r .data.password)

# On auth.funlab.casa
cd /opt/authentik/authentik
sudo sed -i "s/^AUTHENTIK_DB_USER=.*/AUTHENTIK_DB_USER=$NEW_USER/" .env
sudo sed -i "s/^AUTHENTIK_DB_PASSWORD=.*/AUTHENTIK_DB_PASSWORD=$NEW_PASS/" .env
sudo docker compose down && sudo docker compose up -d
```

**Permanent Solution**: Extend TTL to 24h
```bash
bao write database/roles/authentik default_ttl="24h" max_ttl="72h"
```

### 2. OIDC Discovery Endpoint Format
**Issue**: OpenBao requires base issuer URL, not full `.well-known` URL

**Correct**: `https://auth.funlab.casa/application/o/openbao/`
**Incorrect**: `https://auth.funlab.casa/application/o/openbao/.well-known/openid-configuration`

### 3. Blueprint Attribute Names
**Issue**: Signing algorithm field is `signing_key` (RSA keypair object), not `signing_alg`

**Solution**: Reference CertificateKeyPair object in blueprint:
```yaml
signing_key: !Find [authentik_crypto.certificatekeypair, [name, "authentik Self-signed Certificate"]]
```

## Files in This Backup

- `openbao-oidc-provider.yaml` - Authentik blueprint for OpenBao
- `step-ca-oidc-provider.yaml` - Authentik blueprint for step-ca
- `step-ca-config.json` - Complete step-ca configuration with OIDC provisioner
- `oidc-certificate.tpl` - Certificate template for OIDC-issued certs
- `openbao-auth-methods.txt` - List of OpenBao auth methods
- `openbao-role-admin.txt` - Admin role configuration
- `openbao-role-cert-user.txt` - Cert-user role configuration
- `openbao-policy-admin.hcl` - Admin policy definition

## Recovery Procedure

### Restore Authentik Providers

1. Copy blueprints to Authentik server:
```bash
scp openbao-oidc-provider.yaml auth.funlab.casa:/opt/authentik/blueprints/custom/
scp step-ca-oidc-provider.yaml auth.funlab.casa:/opt/authentik/blueprints/custom/
```

2. Restart Authentik worker to apply:
```bash
ssh auth.funlab.casa "cd /opt/authentik/authentik && sudo docker compose restart authentik-worker"
```

3. Assign RSA signing keys via Django shell:
```bash
ssh auth.funlab.casa 'sudo docker exec -i authentik-server ak shell' << 'EOF'
from authentik.providers.oauth2.models import OAuth2Provider
from authentik.crypto.models import CertificateKeyPair

rsa_key = CertificateKeyPair.objects.get(name="authentik Self-signed Certificate")

openbao = OAuth2Provider.objects.get(name="openbao-oidc-provider")
openbao.signing_key = rsa_key
openbao.save()

stepca = OAuth2Provider.objects.get(name="step-ca-oidc-provider")
stepca.signing_key = rsa_key
stepca.save()
EOF
```

4. Add groups scope to both providers (same shell commands as above)

### Restore step-ca Configuration

```bash
# Backup current config
ssh ca.funlab.casa "sudo cp /etc/step-ca/config/ca.json /etc/step-ca/config/ca.json.backup-$(date +%Y%m%d-%H%M%S)"

# Restore from backup
scp step-ca-config.json ca.funlab.casa:/tmp/
ssh ca.funlab.casa "sudo mv /tmp/step-ca-config.json /etc/step-ca/config/ca.json"

# Restore template
scp oidc-certificate.tpl ca.funlab.casa:/tmp/
ssh ca.funlab.casa "sudo mkdir -p /etc/step-ca/templates && sudo mv /tmp/oidc-certificate.tpl /etc/step-ca/templates/"
ssh ca.funlab.casa "sudo chown step:step /etc/step-ca/templates/oidc-certificate.tpl"

# Restart step-ca
ssh ca.funlab.casa "sudo systemctl restart step-ca"
```

### Restore OpenBao Configuration

```bash
# On spire.funlab.casa
export BAO_ADDR='https://openbao.funlab.casa:8088'
export BAO_SKIP_VERIFY=true
export BAO_TOKEN=$(sudo cat /root/.openbao-token)

# Enable OIDC auth (if not already)
bao auth enable oidc

# Configure OIDC (use current client credentials from Authentik)
bao write auth/oidc/config \
  oidc_discovery_url="https://auth.funlab.casa/application/o/openbao/" \
  oidc_client_id="openbao-client-2026" \
  oidc_client_secret="<FROM_AUTHENTIK>" \
  default_role="default" \
  jwt_supported_algs="RS256"

# Restore policies and roles using the backup files
bao policy write admin openbao-policy-admin.hcl
# ... (see configuration files for full role/policy definitions)
```

## Next Steps

1. **Extend Database TTL**: Change from 1h to 24h to reduce credential rotation frequency
2. **Update Blueprints**: Add signing_key to blueprints for reproducibility
3. **Add Monitoring**: Alert on Authentik database connection failures
4. **MFA Integration**: Require MFA for openbao-admins group
5. **Certificate Renewal**: Implement automated renewal via OIDC tokens

## References

- Authentik OIDC Docs: https://goauthentik.io/docs/providers/oauth2/
- OpenBao OIDC Auth: https://openbao.org/docs/auth/oidc/
- step-ca Provisioners: https://smallstep.com/docs/step-ca/provisioners/

---

**Implementation Date**: February 13-14, 2026
**Implemented By**: Claude Sonnet 4.5
**System**: Funlab.Casa Infrastructure
