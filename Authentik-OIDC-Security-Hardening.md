# Authentik OIDC Integration - Security Hardening Checklist

## Overview

This document provides security hardening recommendations and maintenance procedures for the Authentik OIDC integration with OpenBao and step-ca.

**Last Updated:** 2026-02-14
**Review Frequency:** Quarterly

---

## Immediate Actions (Completed ✅)

### Configuration Security

- ✅ **OIDC Client Secrets Generated:** Strong, random secrets for both providers
- ✅ **Secrets Stored Securely:** Client secrets stored in OpenBao KV
- ✅ **TLS Enabled:** All OIDC endpoints use HTTPS
- ✅ **Certificate Validation:** Services validate TLS certificates
- ✅ **Token TTLs Configured:** Short-lived tokens (15m-1h)
- ✅ **Group-Based Access Control:** Role mappings based on Authentik groups
- ✅ **Certificate Templates:** Restrictive templates for OIDC-issued certificates
- ✅ **Redirect URI Whitelisting:** Only authorized redirect URIs configured

### Credentials Stored

**OpenBao KV Secrets:**
```
secret/authentik/providers/openbao
  ├── client_id
  ├── client_secret
  └── discovery_url

secret/authentik/providers/step-ca
  ├── client_id
  ├── client_secret
  └── discovery_url
```

---

## Ongoing Security Tasks

### Daily

#### Monitor Authentication Failures

**Authentik:**
```bash
# Check failed login attempts (last 24 hours)
ssh auth.funlab.casa "docker logs authentik-server --since 24h 2>&1 | grep 'login_failed'"
```

**OpenBao:**
```bash
# Check OIDC auth failures
ssh spire.funlab.casa 'export BAO_ADDR="https://openbao.funlab.casa:8088" && \
  export BAO_SKIP_VERIFY=true && \
  export BAO_TOKEN=$(sudo cat /root/.openbao-token) && \
  bao audit log list'
```

#### Verify Service Health

```bash
# All services responding
curl -sk https://auth.funlab.casa/api/v3/admin/system/ | head -5
curl -sk https://openbao.funlab.casa:8088/v1/sys/health | jq .sealed
curl -sk https://ca.funlab.casa:8443/health
```

**Expected:**
- Authentik: HTTP 200/401 (401 = auth required, which is normal)
- OpenBao: `{"sealed": false}`
- step-ca: `{"status":"ok"}`

### Weekly

#### Review Certificate Issuance Logs

**OpenBao:**
```bash
# List recently issued certificates (if audit enabled)
ssh spire.funlab.casa 'export BAO_ADDR="https://openbao.funlab.casa:8088" && \
  export BAO_SKIP_VERIFY=true && \
  export BAO_TOKEN=$(sudo cat /root/.openbao-token) && \
  bao list pki_int/certs'
```

**step-ca:**
```bash
# Check step-ca logs for certificate issuance
ssh ca.funlab.casa "sudo journalctl -u step-ca --since '1 week ago' | grep 'certificate issued'"
```

#### Verify Database Credentials Valid

**Authentik Database Credentials (1h TTL):**
```bash
# Check current credentials
ssh auth.funlab.casa "sudo grep AUTHENTIK_DB_USER /opt/authentik/authentik/.env"

# Verify last rotation
ssh spire.funlab.casa 'export BAO_ADDR="https://openbao.funlab.casa:8088" && \
  export BAO_SKIP_VERIFY=true && \
  export BAO_TOKEN=$(sudo cat /root/.openbao-token) && \
  bao read database/creds/authentik'
```

**⚠️ Action Required:** If credentials show as expired or containers are failing, renew credentials:
```bash
# Generate new credentials
ssh spire.funlab.casa 'export BAO_ADDR="https://openbao.funlab.casa:8088" && \
  export BAO_SKIP_VERIFY=true && \
  export BAO_TOKEN=$(sudo cat /root/.openbao-token) && \
  bao read -format=json database/creds/authentik'

# Update .env file (see Phase 1 documentation)
# Recreate containers
```

### Monthly

#### Audit Group Memberships

**List all groups and members:**
```bash
ssh auth.funlab.casa 'docker exec -i authentik-server python manage.py shell' << 'EOF'
from authentik.core.models import Group, User

for group in Group.objects.filter(name__in=["openbao-admins", "openbao-cert-users", "step-ca-users"]):
    print(f"\n=== {group.name} ===")
    for user in group.users.all():
        print(f"  - {user.username} ({user.email})")
EOF
```

**Review:**
- Are all members still authorized?
- Should anyone be removed?
- Should anyone be added?

#### Review OIDC Token Policies

```bash
# List all OIDC roles
ssh spire.funlab.casa 'export BAO_ADDR="https://openbao.funlab.casa:8088" && \
  export BAO_SKIP_VERIFY=true && \
  export BAO_TOKEN=$(sudo cat /root/.openbao-token) && \
  bao list auth/oidc/role'

# Review each role's configuration
ssh spire.funlab.casa 'export BAO_ADDR="https://openbao.funlab.casa:8088" && \
  export BAO_SKIP_VERIFY=true && \
  export BAO_TOKEN=$(sudo cat /root/.openbao-token) && \
  bao read auth/oidc/role/admin'
```

**Check:**
- Token TTLs appropriate?
- Policies still needed?
- Bound claims correct?

#### Backup Configurations

**Critical Files:**
```bash
# Backup OpenBao policies
ssh spire.funlab.casa 'export BAO_ADDR="https://openbao.funlab.casa:8088" && \
  export BAO_SKIP_VERIFY=true && \
  export BAO_TOKEN=$(sudo cat /root/.openbao-token) && \
  bao policy list' > /tmp/openbao-policies-$(date +%Y%m%d).txt

# Backup step-ca config
ssh ca.funlab.casa "sudo cat /etc/step-ca/config/ca.json" > /tmp/step-ca-config-$(date +%Y%m%d).json

# Backup Authentik blueprints
ssh auth.funlab.casa "sudo tar -czf /tmp/authentik-blueprints-$(date +%Y%m%d).tar.gz /opt/authentik/blueprints/custom/"
scp auth.funlab.casa:/tmp/authentik-blueprints-*.tar.gz ~/backups/
```

**Store backups in:**
- Git repository (for blueprints and configs)
- 1Password (for sensitive data)
- Off-site backup location

### Quarterly

#### Rotate OIDC Client Secrets

**⚠️ High-Impact Change - Schedule Maintenance Window**

**Process:**

1. **Generate new secrets:**
```bash
# For each provider, generate new secret
NEW_SECRET=$(openssl rand -base64 48)
echo "New secret: $NEW_SECRET"
```

2. **Update Authentik provider:**
```bash
ssh auth.funlab.casa 'docker exec -i authentik-server python manage.py shell' << 'EOF'
from authentik.providers.oauth2.models import OAuth2Provider

provider = OAuth2Provider.objects.get(name="openbao-oidc-provider")
provider.client_secret = "<NEW_SECRET>"
provider.save()
print(f"Updated {provider.name}")
EOF
```

3. **Update OpenBao config:**
```bash
ssh spire.funlab.casa 'export BAO_ADDR="https://openbao.funlab.casa:8088" && \
  export BAO_SKIP_VERIFY=true && \
  export BAO_TOKEN=$(sudo cat /root/.openbao-token) && \
  bao write auth/oidc/config \
    oidc_discovery_url="https://auth.funlab.casa/application/o/openbao/" \
    oidc_client_id="openbao-client-2026" \
    oidc_client_secret="<NEW_SECRET>" \
    default_role="default"'
```

4. **Update stored secret in OpenBao:**
```bash
ssh spire.funlab.casa 'export BAO_ADDR="https://openbao.funlab.casa:8088" && \
  export BAO_SKIP_VERIFY=true && \
  export BAO_TOKEN=$(sudo cat /root/.openbao-token) && \
  bao kv patch secret/authentik/providers/openbao \
    client_secret="<NEW_SECRET>"'
```

5. **Verify:**
- Test OIDC login still works
- Check for errors in logs

6. **Repeat for step-ca provider**

#### Review Certificate Templates

**step-ca OIDC template:**
```bash
ssh ca.funlab.casa "sudo cat /etc/step-ca/templates/oidc-certificate.tpl"
```

**Review:**
- Key usage still appropriate?
- Extended key usage restrictions correct?
- Organization/OU values accurate?

**Update if needed:**
```bash
# Edit template
ssh ca.funlab.casa "sudo vi /etc/step-ca/templates/oidc-certificate.tpl"

# Restart step-ca
ssh ca.funlab.casa "sudo systemctl restart step-ca"
```

#### Audit Authentik Events

```bash
# Review authentication events
ssh auth.funlab.casa 'docker exec -i authentik-server python manage.py shell' << 'EOF'
from authentik.events.models import Event
from datetime import datetime, timedelta

start_date = datetime.now() - timedelta(days=90)
events = Event.objects.filter(
    created__gte=start_date,
    action__in=["login", "login_failed", "logout", "password_set"]
).order_by('-created')[:100]

for event in events:
    print(f"{event.created} - {event.action} - {event.user}")
EOF
```

### Annually

#### Comprehensive Security Audit

**Items to Review:**

1. **Access Control:**
   - [ ] All users still need access?
   - [ ] Group memberships appropriate?
   - [ ] Any orphaned accounts?

2. **Token/Certificate Policies:**
   - [ ] TTLs still appropriate?
   - [ ] Certificate durations reasonable?
   - [ ] Policies follow principle of least privilege?

3. **Infrastructure:**
   - [ ] All services on supported versions?
   - [ ] Security patches applied?
   - [ ] TLS certificates valid?

4. **Monitoring:**
   - [ ] Alerts working correctly?
   - [ ] Logs being retained appropriately?
   - [ ] Audit trails complete?

5. **Documentation:**
   - [ ] User guide up to date?
   - [ ] Security procedures documented?
   - [ ] Emergency contacts current?

6. **Disaster Recovery:**
   - [ ] Backups tested and restorable?
   - [ ] Emergency access procedures work?
   - [ ] Recovery time objectives met?

---

## Security Hardening Recommendations

### Implement MFA for Privileged Groups

**For openbao-admins group:**

1. Enable TOTP in Authentik
2. Create policy requiring MFA for admin group
3. Apply to OIDC provider flows
4. Test with admin users

**Implementation:**
```bash
# Via Authentik Web UI:
# 1. Flows → Create Flow → "MFA Required Flow"
# 2. Policies → Create Policy → "MFA Policy"
#    - Bind to group: openbao-admins
# 3. Applications → OpenBao → Update Flow
```

### Implement Token Revocation Monitoring

**Set up alerts for:**
- Multiple failed OIDC authentications
- Token usage from unexpected IPs
- Certificates issued outside business hours
- High volume of certificate issuance

**Example Alert (Prometheus/Grafana):**
```yaml
alert: HighFailedOIDCLogins
expr: rate(authentik_login_failed[5m]) > 10
for: 5m
labels:
  severity: warning
annotations:
  summary: "High rate of failed OIDC logins"
```

### Implement Certificate Revocation Lists

**OpenBao:**
```bash
# Enable CRL endpoints
ssh spire.funlab.casa 'export BAO_ADDR="https://openbao.funlab.casa:8088" && \
  export BAO_SKIP_VERIFY=true && \
  export BAO_TOKEN=$(sudo cat /root/.openbao-token) && \
  bao write pki_int/config/crl \
    expiry=72h \
    disable=false'
```

**step-ca:**
- CRL support requires enterprise features
- Consider OCSP instead

### Restrict Network Access

**Firewall Rules:**
```bash
# Only allow OIDC endpoints from authorized networks
# auth.funlab.casa:443 - Allow from all (public OIDC)
# openbao.funlab.casa:8088 - Restrict to internal network
# ca.funlab.casa:8443 - Restrict to internal network
```

**NPM/Nginx Configuration:**
- Already implemented: mTLS for enrolled devices
- OIDC discovery: No mTLS required (uses `ssl_verify_client optional`)

### Enable Audit Logging

**OpenBao Audit Device:**
```bash
# Enable file audit device
ssh spire.funlab.casa 'export BAO_ADDR="https://openbao.funlab.casa:8088" && \
  export BAO_SKIP_VERIFY=true && \
  export BAO_TOKEN=$(sudo cat /root/.openbao-token) && \
  bao audit enable file file_path=/var/log/openbao/audit.log'
```

**Authentik:**
- Events already logged to database
- Consider forwarding to centralized logging (syslog, Loki, etc.)

**step-ca:**
- Logs to journald
- Consider structured logging output

---

## Incident Response

### Compromised OIDC Client Secret

**Immediate Actions:**

1. **Rotate client secret immediately** (see Quarterly tasks)
2. **Revoke all active OIDC tokens:**
   ```bash
   # OpenBao: No bulk revocation - tokens expire naturally (15m-1h)
   # Force users to re-authenticate
   ```
3. **Review audit logs** for unauthorized access
4. **Notify users** of required re-authentication

### Compromised User Account

**Immediate Actions:**

1. **Disable user account:**
   ```bash
   ssh auth.funlab.casa 'docker exec -i authentik-server python manage.py shell' << 'EOF'
   from authentik.core.models import User
   user = User.objects.get(username="<compromised-user>")
   user.is_active = False
   user.save()
   EOF
   ```

2. **Review user's recent activity:**
   - Check Authentik event logs
   - Review certificates issued
   - Check OpenBao token usage

3. **Revoke issued certificates:**
   ```bash
   # List certificates by user
   # Revoke each one
   ```

4. **Reset password** before re-enabling account

### Database Credentials Expired

**Symptoms:**
- Authentik containers failing to start
- Database connection errors in logs
- HTTP 500 errors from Authentik

**Resolution:**
```bash
# 1. Generate new credentials from OpenBao
ssh spire.funlab.casa 'export BAO_ADDR="https://openbao.funlab.casa:8088" && \
  export BAO_SKIP_VERIFY=true && \
  export BAO_TOKEN=$(sudo cat /root/.openbao-token) && \
  bao read -format=json database/creds/authentik'

# 2. Update .env file
ssh auth.funlab.casa "sudo sed -i 's/^AUTHENTIK_DB_USER=.*/AUTHENTIK_DB_USER=<new-username>/' /opt/authentik/authentik/.env"
ssh auth.funlab.casa "sudo sed -i 's/^AUTHENTIK_DB_PASSWORD=.*/AUTHENTIK_DB_PASSWORD=<new-password>/' /opt/authentik/authentik/.env"

# 3. Recreate containers
ssh auth.funlab.casa "cd /opt/authentik/authentik && sudo docker compose down && sudo docker compose up -d"
```

### step-ca YubiKey Unavailable

**Symptoms:**
- step-ca fails to start
- YubiKey PIN errors in logs

**Resolution:**

1. **Verify YubiKey is connected:**
   ```bash
   ssh ca.funlab.casa "ykman info"
   ```

2. **Check PIN file:**
   ```bash
   ssh ca.funlab.casa "sudo cat /run/step-ca/yubikey-pin"
   ```

3. **Re-run PIN setup:**
   ```bash
   ssh ca.funlab.casa "sudo /usr/local/bin/setup-yubikey-pin-for-step-ca"
   ```

4. **Restart step-ca:**
   ```bash
   ssh ca.funlab.casa "sudo systemctl restart step-ca"
   ```

---

## Monitoring Recommendations

### Metrics to Track

**Authentication:**
- OIDC login success/failure rates
- Average authentication time
- Tokens issued per hour/day
- Failed login attempts by user/IP

**Certificates:**
- Certificates issued per day
- Average certificate duration
- Certificate validation failures
- Certificates nearing expiration

**Services:**
- OpenBao seal status
- step-ca health status
- Authentik database connection status
- API response times

### Alerting Thresholds

**Critical:**
- OpenBao becomes sealed
- step-ca health check fails
- Authentik database connection fails
- > 50 failed logins in 5 minutes

**Warning:**
- Authentik database credentials expire in < 10 minutes
- > 10 failed logins in 5 minutes
- Certificate issuance rate > 100/hour (unusual)
- OpenBao token TTL > 4 hours (misconfigured)

---

## Compliance & Audit Trail

### Log Retention

**Recommended Retention Periods:**
- **Authentication logs:** 90 days minimum, 1 year recommended
- **Certificate issuance:** 2 years minimum (compliance requirement)
- **Audit logs:** 1 year minimum
- **Configuration changes:** Indefinite (git history)

### Required Documentation

**For Compliance:**
- [ ] List of all users with access
- [ ] Group membership justifications
- [ ] Certificate issuance approval process
- [ ] Incident response procedures
- [ ] Last security audit date
- [ ] Backup and recovery procedures

---

## Emergency Contacts

**System Issues:**
- Infrastructure Team: (contact details)
- On-Call: (rotation schedule)

**Security Issues:**
- Security Team: (contact details)
- Emergency: (escalation procedure)

**Vendor Support:**
- Authentik: Community (https://goauthentik.io/discord)
- OpenBao: GitHub Issues
- Smallstep (step-ca): Community/Enterprise support

---

## Review Schedule

| Task | Frequency | Last Completed | Next Due |
|------|-----------|----------------|----------|
| Security audit | Annually | 2026-02-14 | 2027-02-14 |
| Client secret rotation | Quarterly | 2026-02-14 | 2026-05-14 |
| Group membership review | Monthly | 2026-02-14 | 2026-03-14 |
| Certificate template review | Quarterly | 2026-02-14 | 2026-05-14 |
| Backup verification | Monthly | 2026-02-14 | 2026-03-14 |
| Failed login review | Weekly | 2026-02-14 | 2026-02-21 |

---

**Document Owner:** Infrastructure Team
**Last Reviewed:** 2026-02-14
**Next Review:** 2027-02-14
