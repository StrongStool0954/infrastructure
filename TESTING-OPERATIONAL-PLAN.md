# Testing & Operational Plan

**Date:** 2026-02-11  
**Status:** 📋 PLANNED  
**Purpose:** Validate production readiness and optimize certificate lifecycle

---

## Reboot Survival Testing

### Objective
Verify all infrastructure services survive host reboots and automatically restore full functionality.

### Test Scope: All 3 Physical Hosts

#### 1. spire.funlab.casa (Primary Infrastructure Host)
**Services to validate:**
- ✅ nginx reverse proxy (port 443)
- ✅ Keylime registrar (ports 8890/8891)
- ✅ Keylime verifier (port 8881)
- ✅ Keylime agent (local)
- ✅ OpenBao PKI (port 8200)
- ✅ SPIRE server (port 8081)

**Test procedure:**
```bash
# Pre-reboot validation
sudo systemctl status nginx keylime_registrar keylime_verifier keylime_agent openbao spire-server
curl -k https://registrar.keylime.funlab.casa/version
curl -k https://verifier.keylime.funlab.casa/version
curl -k https://openbao.funlab.casa/v1/sys/health

# Reboot
sudo reboot

# Post-reboot validation (after 2-3 minutes)
sudo systemctl status nginx keylime_registrar keylime_verifier keylime_agent openbao spire-server
curl -k https://registrar.keylime.funlab.casa/version
curl -k https://verifier.keylime.funlab.casa/version
curl -k https://openbao.funlab.casa/v1/sys/health

# Check systemd timers
systemctl list-timers nginx-cert-renewal.timer nginx-monitor.timer

# Verify agent registration
sudo journalctl -u keylime_agent -n 50 | grep SUCCESS
```

#### 2. ca.funlab.casa (Nginx Proxy Client - Working)
**Services to validate:**
- ✅ Keylime agent via nginx proxy (https://registrar.keylime.funlab.casa:443)

**Test procedure:**
```bash
# Pre-reboot validation
sudo systemctl status keylime_agent
sudo journalctl -u keylime_agent -n 20 | grep "Building Registrar"

# Reboot
sudo reboot

# Post-reboot validation
sudo systemctl status keylime_agent
sudo journalctl -u keylime_agent -n 50 | grep -E "SUCCESS|Building Registrar|TLS=true"

# Verify nginx proxy connection
timeout 30 sudo RUST_LOG=info keylime_agent 2>&1 | grep -E "scheme=https.*TLS=true"
```

#### 3. auth.funlab.casa (Direct HTTP Client)
**Services to validate:**
- ✅ Keylime agent via direct HTTP (http://spire.funlab.casa:8890)

**Test procedure:**
```bash
# Pre-reboot validation
sudo systemctl status keylime_agent
sudo journalctl -u keylime_agent -n 20 | grep "Building Registrar"

# Reboot
sudo reboot

# Post-reboot validation
sudo systemctl status keylime_agent
sudo journalctl -u keylime_agent -n 50 | grep -E "SUCCESS|Building Registrar"

# Verify direct HTTP connection
timeout 30 sudo RUST_LOG=info keylime_agent 2>&1 | grep -E "scheme=http"
```

---

## Core Functionality Retesting

### After Each Reboot - Validate Full Stack

#### 1. Certificate Chain Validation
```bash
# Verify nginx certificates
echo | openssl s_client -connect registrar.keylime.funlab.casa:443 -showcerts 2>/dev/null | grep -c "BEGIN CERTIFICATE"
# Expected: 3 (leaf + intermediate + root)

echo | openssl s_client -connect verifier.keylime.funlab.casa:443 -showcerts 2>/dev/null | grep -c "BEGIN CERTIFICATE"
# Expected: 3

echo | openssl s_client -connect openbao.funlab.casa:443 -showcerts 2>/dev/null | grep -c "BEGIN CERTIFICATE"
# Expected: 3

# Verify certificate expiration
openssl s_client -connect registrar.keylime.funlab.casa:443 </dev/null 2>/dev/null | openssl x509 -noout -dates
```

#### 2. Agent Registration
```bash
# Check all agents are registered
curl -k https://registrar.keylime.funlab.casa/v2.5/agents/ | jq '.results.uuids | length'
# Expected: 3 (ca, auth, spire)

# Verify agent operational states
for agent_uuid in $(curl -k -s https://registrar.keylime.funlab.casa/v2.5/agents/ | jq -r '.results.uuids[]'); do
  echo "Agent: $agent_uuid"
  curl -k -s "https://registrar.keylime.funlab.casa/v2.5/agents/$agent_uuid" | jq '.results.operational_state'
done
# Expected: All agents show operational state
```

#### 3. PKI Operations
```bash
# Verify OpenBao is operational
export BAO_ADDR=https://openbao.funlab.casa
export BAO_TOKEN=<token>
bao status
# Expected: Initialized: true, Sealed: false

# Test certificate issuance
bao write -format=json pki_int/issue/openbao-server \
    common_name='test.keylime.funlab.casa' \
    ttl='24h' | jq .data.certificate
# Expected: Certificate issued successfully
```

#### 4. Monitoring & Automation
```bash
# Check nginx monitor status
cat /var/run/nginx-monitor-status
# Expected: status=0

# Check timer schedules
systemctl list-timers nginx-cert-renewal.timer nginx-monitor.timer
# Expected: Both timers active with next run times

# Check recent logs
sudo tail -50 /var/log/nginx-cert-renewal.log
sudo tail -50 /var/log/nginx-monitor.log
```

#### 5. End-to-End Attestation Test
```bash
# Add an agent to verifier (if not already added)
# Verify quote generation and validation
# Check IMA/measured boot validation
# Verify revocation works
```

---

## Certificate Renewal Optimization

### Current State (Weekly Renewal)

**Current configuration:**
- **Renewal frequency:** Weekly (Sundays at 3 AM)
- **Certificate lifetime:** 30 days (720 hours)
- **Renewal margin:** ~3-4 weeks before expiry
- **Automation:** ✅ Implemented with backup/rollback

**Current schedule:**
```ini
# /etc/systemd/system/nginx-cert-renewal.timer
OnCalendar=Sun *-*-* 03:00:00
RandomizedDelaySec=3600
```

---

### Proposed: Aggressive Renewal Strategy

#### Theory: Fail Fast with Renewal Automation

**Benefits of frequent renewal:**
1. **Early problem detection** - Issues discovered quickly, not 30 days later
2. **Continuous validation** - Ensures PKI infrastructure always works
3. **Reduced blast radius** - Shorter certificate lifetimes limit compromise window
4. **Operational confidence** - Frequent testing builds trust in automation
5. **Modern best practice** - Follows Let's Encrypt model (90-day certs, renew every 60 days)

#### Option 1: Daily Renewal (Recommended)

**Configuration:**
- **Renewal frequency:** Daily at 3 AM
- **Certificate lifetime:** 7 days (168 hours)
- **Renewal margin:** 6 days before expiry

**Implementation:**
```bash
# Update timer
sudo tee /etc/systemd/system/nginx-cert-renewal.timer > /dev/null << 'TIMER'
[Unit]
Description=Daily nginx certificate renewal timer

[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=1800
Persistent=true

[Install]
WantedBy=timers.target
TIMER

# Reload and restart timer
sudo systemctl daemon-reload
sudo systemctl restart nginx-cert-renewal.timer
```

**Benefits:**
- Issues detected within 24 hours
- Very short compromise window (7 days)
- Daily operational validation
- High confidence in automation

**Considerations:**
- Increased OpenBao API calls (365/year vs 52/year)
- More log entries
- Requires reliable PKI infrastructure

#### Option 2: 24-Hour Certificates (Aggressive)

**Configuration:**
- **Renewal frequency:** Every 12 hours
- **Certificate lifetime:** 24 hours
- **Renewal margin:** 12 hours before expiry

**Implementation:**
```bash
# Update timer for twice-daily renewal
sudo tee /etc/systemd/system/nginx-cert-renewal.timer > /dev/null << 'TIMER'
[Unit]
Description=Twice-daily nginx certificate renewal timer

[Timer]
OnCalendar=*-*-* 03:00:00,15:00:00
RandomizedDelaySec=900
Persistent=true

[Install]
WantedBy=timers.target
TIMER

# Update renewal script to request 24h certificates
# In /usr/local/bin/renew-nginx-certs.sh, change ttl='720h' to ttl='24h'
```

**Benefits:**
- Maximum fail-fast capability
- Minimal compromise window
- Forces infrastructure reliability
- Aligns with modern zero-trust principles

**Considerations:**
- Requires bulletproof automation
- 730 API calls per year
- Must handle failure gracefully
- Network dependency increases

#### Option 3: Hybrid Approach (Pragmatic)

**Configuration:**
- **Renewal frequency:** Twice weekly (Wednesday 3 AM, Sunday 3 AM)
- **Certificate lifetime:** 14 days (336 hours)
- **Renewal margin:** ~10 days before expiry

**Implementation:**
```bash
# Update timer
sudo tee /etc/systemd/system/nginx-cert-renewal.timer > /dev/null << 'TIMER'
[Unit]
Description=Twice-weekly nginx certificate renewal timer

[Timer]
OnCalendar=Wed,Sun *-*-* 03:00:00
RandomizedDelaySec=1800
Persistent=true

[Install]
WantedBy=timers.target
TIMER
```

**Benefits:**
- Balanced between frequency and stability
- Issues detected within 3-4 days
- Reasonable compromise window (14 days)
- Less aggressive than daily

---

### Recommended: Option 1 (Daily Renewal)

**Rationale:**
1. ✅ Aligns with fail-fast philosophy
2. ✅ Daily validation of PKI infrastructure
3. ✅ Modern security best practice
4. ✅ Automation already proven reliable
5. ✅ Provides operational confidence
6. ✅ Reasonable balance between security and operational load

**Implementation plan:**
1. Test daily renewal on non-production cert first
2. Monitor for 1 week to ensure reliability
3. Adjust certificate lifetime to 7 days
4. Update monitoring to alert on renewal failures
5. Document runbook for failure scenarios

---

## Monitoring Enhancements for Frequent Renewal

### Additional Alerts Needed

**Certificate renewal failures:**
```bash
# Add to monitoring script
if [ ! -f /var/log/nginx-cert-renewal.log ]; then
    echo "ERROR: Certificate renewal log missing"
    exit 2
fi

# Check for recent renewal success (within 25 hours for daily)
last_success=$(grep "Successfully renewed certificates" /var/log/nginx-cert-renewal.log | tail -1 | awk '{print $1, $2}')
last_success_epoch=$(date -d "$last_success" +%s 2>/dev/null || echo 0)
current_epoch=$(date +%s)
age_hours=$(( (current_epoch - last_success_epoch) / 3600 ))

if [ $age_hours -gt 25 ]; then
    echo "WARNING: Last successful renewal was $age_hours hours ago"
    exit 1
fi
```

**Certificate expiration warnings:**
```bash
# Add early warning thresholds
# Current: 7 days
# Daily renewal: 2 days (for 7-day certs)
# 24-hour: 6 hours (for 24-hour certs)
```

---

## Success Criteria

### Reboot Survival Test: PASS
- ✅ All services restart automatically
- ✅ All agents re-register successfully
- ✅ All endpoints respond within 5 minutes
- ✅ No manual intervention required

### Core Functionality Test: PASS
- ✅ Certificate chains validate correctly
- ✅ All agents show operational state
- ✅ PKI can issue new certificates
- ✅ Monitoring shows healthy status
- ✅ Automation timers scheduled correctly

### Certificate Renewal Optimization: IMPLEMENTED
- ✅ Renewal frequency updated
- ✅ Certificate lifetime adjusted
- ✅ Monitoring updated for new cadence
- ✅ Failure scenarios documented
- ✅ Runbook created

---

## Timeline

### Phase 1: Reboot Survival Testing (Week 1)
- Day 1: Test spire.funlab.casa
- Day 2: Test ca.funlab.casa
- Day 3: Test auth.funlab.casa
- Day 4: Document results, address any issues

### Phase 2: Certificate Renewal Optimization (Week 2)
- Day 5-6: Implement daily renewal on test certificate
- Day 7-11: Monitor daily renewal reliability
- Day 12: Deploy to production if successful
- Day 13-14: Monitor and tune

### Phase 3: Operational Validation (Week 3)
- Continuous monitoring of daily renewals
- Performance metrics collection
- Incident response testing
- Documentation finalization

---

## Rollback Plan

If daily renewal proves problematic:
1. Revert timer to weekly schedule
2. Restore certificate lifetime to 30 days
3. Document issues encountered
4. Plan remediation before retry

**Rollback command:**
```bash
# Restore weekly timer
sudo cp /etc/systemd/system/nginx-cert-renewal.timer.backup \
       /etc/systemd/system/nginx-cert-renewal.timer
sudo systemctl daemon-reload
sudo systemctl restart nginx-cert-renewal.timer
```

---

## Documentation References

- `NGINX-AUTOMATION.md` - Current automation setup
- `NGINX-REVERSE-PROXY-COMPLETE.md` - Infrastructure overview
- `KEYLIME-SYSTEMD-SERVICES.md` - Service management
- `FINAL-TLS-INVESTIGATION.md` - TLS investigation results

---

**Status:** Ready for implementation  
**Owner:** Infrastructure team  
**Priority:** High - Operational validation

