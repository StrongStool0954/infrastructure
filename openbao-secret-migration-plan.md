# OpenBao Secret Migration Plan
**Date:** 2026-02-12
**Purpose:** Migrate hardcoded secrets to centralized OpenBao secret management

---

## Executive Summary

Scan identified **15 distinct secrets** across 3 hosts that should be migrated to OpenBao for centralized secret management. These include database credentials, service account tokens, API keys, and SSH private keys.

---

## Secrets Inventory

### **Priority 1: Database Credentials (CRITICAL)**

#### auth.funlab.casa

**Location:** `/opt/npm/.env`
- `NPM_DB_PASSWORD` - Nginx Proxy Manager database password
- `NPM_DB_ROOT_PASSWORD` - MySQL root password

**Location:** `/opt/authentik/postgres/.env`
- `POSTGRES_PASSWORD` - PostgreSQL database password for Authentik

**Location:** `/opt/authentik/authentik/.env`
- `AUTHENTIK_DB_PASSWORD` - Authentik application database password
- `REDIS_PASSWORD` - Redis database password
- `AUTHENTIK_SECRET_KEY` - Django secret key for Authentik

**Impact:** HIGH - These are actively used by running services  
**Migration Urgency:** HIGH - Replace with dynamic secrets from OpenBao

---

### **Priority 2: Service Account Tokens (HIGH)**

#### ca.funlab.casa

**Location:** `/etc/1password/service-account-token`
- 1Password service account token
- Used by: step-ca to retrieve YubiKey PIN
- Access: root + onepassword group

#### spire.funlab.casa

**Location:** `/etc/1password/service-account-token`
- 1Password service account token
- Access: root + onepassword group

**Location:** `/opt/1password-connect/1password-credentials.json`
- 1Password Connect server credentials
- Size: 1.1K
- Used for: 1Password Connect API access

**Impact:** HIGH - Compromise allows access to all 1Password secrets  
**Migration Urgency:** MEDIUM - Already in a secrets manager, but could be rotated through OpenBao

---

### **Priority 3: OpenBao Root Tokens (MEDIUM)**

#### ca.funlab.casa

**Location:** `/root/.openbao-token`
- OpenBao authentication token
- Size: 27 bytes
- Permissions: 600 (root only)

**Impact:** MEDIUM - Used for OpenBao CLI access  
**Migration Urgency:** LOW - This is the secrets manager itself, needs secure rotation procedure

---

### **Priority 4: SSH Private Keys (MEDIUM)**

#### ca.funlab.casa

**Location:** `/root/.ssh/id_ed25519`
- Root user SSH private key
- Used for: Automated SSH between hosts (trust bundle updates, monitoring)

#### auth.funlab.casa

**Location:** `/root/.ssh/id_ed25519`
- Root user SSH private key
- Used for: Automated SSH between hosts

**Impact:** MEDIUM - Used for infrastructure automation  
**Migration Urgency:** MEDIUM - Consider SSH certificate authentication via step-ca instead

---

### **Priority 5: TLS Private Keys (LOW)**

#### All Hosts

**Keylime Agent Keys:**
- `/etc/keylime/certs/agent.key` (all hosts)
- `/etc/keylime/certs/agent-pkcs8.key` (all hosts)

**Keylime Infrastructure Keys (spire only):**
- `/etc/keylime/certs/registrar.key`
- `/etc/keylime/certs/verifier.key`

**NGINX Keys (spire only):**
- `/etc/nginx/certs/services.key`
- `/etc/nginx/certs/registrar.key`
- `/etc/nginx/certs/keylime.key`

**SPIRE Bundle Keys (spire only):**
- `/etc/spire/bundle-certs/bundle.key`

**Impact:** LOW - Automatically rotated by certificate renewal systems  
**Migration Urgency:** LOW - Current PKI automation is working well

---

## Migration Strategy

### Phase 1: Database Credentials (Week 1)

**Goal:** Migrate all database passwords to OpenBao dynamic secrets

#### Step 1.1: Create OpenBao Database Secret Engine

```bash
# On spire.funlab.casa
bao secrets enable database

# Configure PostgreSQL for Authentik
bao write database/config/authentik-postgres \
    plugin_name=postgresql-database-plugin \
    allowed_roles="authentik" \
    connection_url="postgresql://{{username}}:{{password}}@localhost:5432/authentik" \
    username="authentik_admin" \
    password="<current_password>"

# Configure MySQL for NPM
bao write database/config/npm-mysql \
    plugin_name=mysql-database-plugin \
    allowed_roles="npm" \
    connection_url="{{username}}:{{password}}@tcp(localhost:3306)/" \
    username="root" \
    password="<current_password>"
```

#### Step 1.2: Create Dynamic Roles

```bash
# Authentik role
bao write database/roles/authentik \
    db_name=authentik-postgres \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"

# NPM role
bao write database/roles/npm \
    db_name=npm-mysql \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; \
        GRANT ALL PRIVILEGES ON npm.* TO '{{name}}'@'%';" \
    default_ttl="1h" \
    max_ttl="24h"
```

#### Step 1.3: Update Application Configurations

**For Authentik (auth.funlab.casa):**

Replace static credentials in docker-compose or systemd with OpenBao retrieval:

```bash
# Create wrapper script to fetch credentials
cat > /opt/authentik/get-db-credentials.sh << 'SCRIPT'
#!/bin/bash
# Fetch fresh database credentials from OpenBao
bao read -field=username database/creds/authentik > /tmp/authentik-db-user
bao read -field=password database/creds/authentik > /tmp/authentik-db-pass
SCRIPT

# Update systemd service to call wrapper before starting
```

**For NPM (auth.funlab.casa):**

Similar approach - fetch credentials at startup.

---

### Phase 2: Service Account Tokens (Week 2)

**Goal:** Rotate 1Password tokens through OpenBao

#### Step 2.1: Store 1Password Tokens in OpenBao

```bash
# Store current tokens (temporary - will rotate)
bao kv put secret/1password/service-account \
    ca_token="@/etc/1password/service-account-token" \
    spire_token="@/etc/1password/service-account-token"

bao kv put secret/1password/connect \
    credentials="@/opt/1password-connect/1password-credentials.json"
```

#### Step 2.2: Update Applications to Use OpenBao

**Update `/usr/local/bin/op-with-service-account`:**

```bash
#!/bin/bash
# Modified version - fetch token from OpenBao instead of file

# Fetch token from OpenBao
export OP_SERVICE_ACCOUNT_TOKEN=$(bao kv get -field=ca_token secret/1password/service-account)
exec /usr/bin/op "$@"
```

#### Step 2.3: Rotate Original Tokens

After migration is complete and validated:
1. Generate new 1Password service account tokens
2. Update OpenBao secrets
3. Delete old token files

---

### Phase 3: SSH Key Management (Week 3)

**Goal:** Migrate to SSH certificate authentication

**Current State:**
- SSH private keys stored in `/root/.ssh/`
- Used for automated trust bundle updates and monitoring

**Target State:**
- SSH certificates issued by step-ca
- Short-lived certificates (24 hours)
- No long-lived private keys

#### Step 3.1: Configure step-ca for SSH

```bash
# On ca.funlab.casa
step ca provisioner add ssh-provisioner --type SSHPOP --admin-subject step
```

#### Step 3.2: Update Automation Scripts

Replace SSH key authentication with certificate-based:

```bash
# Request SSH certificate from step-ca
step ssh certificate id_ecdsa-cert.pub id_ecdsa \
    --provisioner ssh-provisioner \
    --host spire.funlab.casa

# Use certificate for SSH
ssh -i id_ecdsa-cert.pub -i id_ecdsa user@spire.funlab.casa
```

---

### Phase 4: OpenBao Token Management (Week 4)

**Goal:** Implement secure token rotation

**Current State:**
- Root token stored in `/root/.openbao-token`
- No automatic rotation

**Target State:**
- AppRole authentication for automated systems
- Periodic token rotation
- Audit logging

#### Step 4.1: Create AppRole for Infrastructure

```bash
bao auth enable approle

bao write auth/approle/role/infrastructure \
    secret_id_ttl=24h \
    token_num_uses=0 \
    token_ttl=1h \
    token_max_ttl=24h \
    secret_id_num_uses=0 \
    policies="infrastructure-policy"
```

#### Step 4.2: Replace Root Token Usage

Update scripts to use AppRole authentication instead of root token.

---

## Security Benefits

### Before Migration

❌ **Static Credentials:**
- Database passwords in plaintext .env files
- No automatic rotation
- Credentials stored on disk
- No audit trail of access

❌ **Token Management:**
- Service account tokens in files
- No centralized rotation
- Difficult to revoke access

❌ **SSH Keys:**
- Long-lived private keys
- No expiration
- Manual rotation required

### After Migration

✅ **Dynamic Secrets:**
- Database credentials generated on-demand
- Automatic rotation (1 hour TTL)
- Centralized in OpenBao
- Full audit trail

✅ **Centralized Token Management:**
- All tokens managed through OpenBao
- Easy rotation and revocation
- Access policies enforced

✅ **Certificate-Based SSH:**
- Short-lived SSH certificates (24 hours)
- Automatic expiration
- Issued by step-ca PKI

---

## Implementation Checklist

### Pre-Migration

- [ ] Backup all current credential files
- [ ] Document all services using each credential
- [ ] Test OpenBao connectivity from all hosts
- [ ] Create rollback procedures

### Phase 1: Database Credentials

- [ ] Enable database secret engine in OpenBao
- [ ] Configure database connections
- [ ] Create dynamic roles
- [ ] Test credential generation
- [ ] Update Authentik configuration
- [ ] Update NPM configuration
- [ ] Verify services restart successfully
- [ ] Monitor for 24 hours
- [ ] Remove static credentials from files

### Phase 2: Service Account Tokens

- [ ] Store current tokens in OpenBao
- [ ] Update op-with-service-account script
- [ ] Test 1Password access
- [ ] Verify step-ca YubiKey PIN retrieval
- [ ] Generate new service account tokens
- [ ] Update OpenBao secrets
- [ ] Delete old token files

### Phase 3: SSH Certificate Authentication

- [ ] Configure step-ca for SSH
- [ ] Test SSH certificate issuance
- [ ] Update trust bundle update scripts
- [ ] Update monitoring scripts
- [ ] Verify automated operations
- [ ] Remove SSH private keys

### Phase 4: Token Rotation

- [ ] Create AppRole for infrastructure
- [ ] Update scripts to use AppRole
- [ ] Test token renewal
- [ ] Revoke root token (create emergency token)
- [ ] Document emergency procedures

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Service disruption during migration | Medium | High | Pilot on non-critical service first, maintain backups |
| OpenBao unavailable | Low | Critical | Implement HA for OpenBao, keep emergency static credentials |
| Credential rotation breaks app | Medium | High | Test thoroughly, implement health checks, rollback plan |
| Failed authentication after migration | Medium | Medium | Keep old credentials for 24h grace period |
| Certificate expiration | Low | Medium | Monitor certificate TTLs, alert before expiry |

---

## Rollback Procedures

### Database Credentials

1. Stop affected service
2. Restore original .env file from backup
3. Restart service
4. Verify functionality
5. Investigate root cause

### Service Account Tokens

1. Restore original token files from backup
2. Restart affected services
3. Verify 1Password connectivity
4. Investigate root cause

### SSH Certificates

1. Restore SSH private keys
2. Update scripts to use keys instead of certificates
3. Test automated operations
4. Investigate root cause

---

## Success Criteria

Migration considered successful when:

- [ ] All database credentials dynamically generated from OpenBao
- [ ] Zero static passwords in .env files
- [ ] All service account tokens managed through OpenBao
- [ ] SSH authentication using certificates, not keys
- [ ] AppRole authentication for automated systems
- [ ] Root token secured and rarely used
- [ ] Full audit trail of secret access
- [ ] All services operational for 7+ days
- [ ] No manual credential rotation required

---

## Monitoring & Maintenance

### Daily

- Check OpenBao audit logs for failed authentications
- Verify database credential generation working
- Monitor service health

### Weekly

- Review secret access patterns
- Check for expiring certificates
- Verify automated rotation working

### Monthly

- Rotate service account tokens
- Review and update policies
- Audit secret access logs
- Test rollback procedures

---

## Next Steps

1. **Review this plan** with infrastructure team
2. **Create test environment** to validate migration procedures
3. **Schedule migration windows** for each phase
4. **Begin Phase 1** with NPM database (lowest risk)
5. **Document results** and lessons learned

---

**Document Version:** 1.0  
**Last Updated:** 2026-02-12 21:10 EST  
**Owner:** Infrastructure Team  
**Status:** Ready for Review
