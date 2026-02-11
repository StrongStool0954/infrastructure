# Remaining Tasks - Tower of Omens Infrastructure

**Date:** 2026-02-10 23:00 EST
**Current Status:** Sprint 3 Phase 3 - Ready for Final Migration

---

## 📊 Current Infrastructure State

### Hosts and Attestation Status
| Host | SPIRE Agent | Attestation Type | Keylime Agent | Status |
|------|-------------|------------------|---------------|--------|
| auth.funlab.casa | ✅ Running | Keylime (HTTP) | ✅ Running | ⚠️ Needs HTTPS upgrade |
| ca.funlab.casa | ✅ Running | **Keylime (HTTPS/mTLS)** | ✅ Running | ✅ **COMPLETE** |
| spire.funlab.casa | ✅ Running | join_token | ❌ Not deployed | ❌ Needs migration |

### SPIRE Agents Summary
- **Total:** 5 agents registered
- **Keylime:** 2 agents (auth, ca)
- **join_token:** 3 agents (all expired/stale)
  - 48fc8456-ac44-427b-8fd6-1f1475bbcb3d (expires: 2026-02-10 23:49:15)
  - 2e7396a1-bb83-4ef7-9219-7dd6e0f53672 (expires: 2026-02-10 19:47:10) ⚠️ EXPIRED
  - 188e3c11-f996-4a63-9536-d6cc834b1753 (expires: 2026-02-10 20:17:47) ⚠️ EXPIRED

### Keylime Agents
- **Registered:** 3 agents
  - 12345678-1234-5678-9012-345678901234 (spire - placeholder)
  - cfb94005e524009687bd0d14eb57578a0185bbcd846a4d3953f79902d688a71f (ca) ✅
  - d432fbb3-d2f1-4a97-9ef7-75bd81c00000 (auth) ⚠️ HTTP only

---

## 🎯 Priority 1: Complete Migration (Sprint 3 Phase 3-4)

### Task 1.1: Upgrade auth.funlab.casa to HTTPS/mTLS ⚠️ HIGH PRIORITY
**Status:** Needs upgrade
**Current:** HTTP-only Keylime agent
**Target:** HTTPS/mTLS like ca.funlab.casa
**Effort:** 2-3 hours

**Steps:**
1. Copy modified SPIRE plugin to auth.funlab.casa
2. Enable mTLS on Keylime agent
3. Update SPIRE agent configuration with TLS parameters
4. Restart services and verify attestation
5. Test continuous attestation

**Why Important:**
- Eliminates remaining HTTP communication
- Standardizes infrastructure configuration
- Completes Phase 3 security objectives

---

### Task 1.2: Migrate spire.funlab.casa to Keylime 🔴 CRITICAL
**Status:** Not started
**Current:** Using join_token attestation
**Target:** Keylime TPM attestation
**Effort:** 3-4 hours
**Risk:** Medium (SPIRE server host)

**Prerequisites:**
- [ ] Deploy Keylime agent on spire.funlab.casa
- [ ] Generate unique UUID from TPM
- [ ] Issue client certificates from Book of Omens PKI
- [ ] Deploy modified SPIRE plugin with HTTPS support

**Steps:**
1. Install and configure Keylime agent on spire
2. Register agent with Keylime registrar
3. Generate agent certificates (agent.crt, agent.key)
4. Install modified SPIRE plugin binary
5. Update SPIRE agent configuration
6. Test attestation before switching
7. Restart SPIRE agent with Keylime attestation
8. Verify continuous attestation
9. Monitor for issues

**Rollback Plan:**
- Keep join_token configuration backed up
- Can revert to join_token if needed
- No impact to other hosts

**Why Critical:**
- Last host using insecure join_token
- Completes infrastructure migration
- Enables removal of join_token plugin

---

### Task 1.3: Clean Up Stale join_token Agents
**Status:** Not started
**Effort:** 15 minutes

**Commands:**
```bash
# Remove expired agents
sudo /opt/spire/bin/spire-server agent evict -spiffeID spiffe://funlab.casa/spire/agent/join_token/2e7396a1-bb83-4ef7-9219-7dd6e0f53672
sudo /opt/spire/bin/spire-server agent evict -spiffeID spiffe://funlab.casa/spire/agent/join_token/188e3c11-f996-4a63-9536-d6cc834b1753
sudo /opt/spire/bin/spire-server agent evict -spiffeID spiffe://funlab.casa/spire/agent/join_token/48fc8456-ac44-427b-8fd6-1f1475bbcb3d
```

---

### Task 1.4: Remove join_token Plugin from SPIRE Server
**Status:** Not started
**Depends on:** Task 1.2 complete
**Effort:** 30 minutes

**Steps:**
1. Verify all agents using Keylime attestation
2. Edit `/etc/spire/server.conf`
3. Remove join_token NodeAttestor block
4. Restart SPIRE server
5. Verify no disruption to existing agents

**File:** `/etc/spire/server.conf`
```hcl
# REMOVE THIS BLOCK:
# NodeAttestor "join_token" {
#   plugin_data {}
# }
```

---

## 🎯 Priority 2: Documentation Updates

### Task 2.1: Update PHASE-3-FINAL-SUMMARY.md
**Status:** Needs update
**Effort:** 30 minutes

**Updates needed:**
- Update ca.funlab.casa port from HTTP to HTTPS
- Add HTTPS/mTLS completion status
- Update network ports table
- Add auth.funlab.casa HTTPS upgrade section

---

### Task 2.2: Document nginx Proxy Architecture
**Status:** Not started
**Effort:** 1 hour

**Create:** `nginx-keylime-proxy-architecture.md`

**Contents:**
- Purpose: TLS translation for SPIRE plugin
- Configuration details
- Network flow diagram
- Troubleshooting guide
- Alternative solutions considered

---

### Task 2.3: Update Infrastructure README
**Status:** Not started
**Effort:** 1-2 hours

**Updates needed:**
- Add Keylime architecture diagram
- Document HTTPS/mTLS implementation
- Update host configurations
- Add SPIRE plugin modification notes
- Include verification commands

---

### Task 2.4: Create PHASE-4-COMPLETION.md
**Status:** Not started
**Depends on:** Tasks 1.1-1.4 complete
**Effort:** 2 hours

**Contents:**
- Final infrastructure state
- All hosts migrated to Keylime
- HTTPS/mTLS everywhere
- Performance metrics
- Lessons learned
- Operational procedures

---

## 🎯 Priority 3: Operational Tasks

### Task 3.1: Performance Testing Under Load
**Status:** Not started
**Effort:** 2-3 hours

**Tests:**
1. Attestation latency under load
2. Certificate renewal stress testing
3. Concurrent workload registration
4. Failover scenarios
5. Memory and CPU usage profiling

---

### Task 3.2: Set Up Monitoring and Alerting
**Status:** Not started
**Effort:** 4-6 hours

**Monitoring Points:**
- Keylime attestation success rate
- Certificate expiration warnings
- SPIRE agent health status
- Disk encryption status
- TPM availability

---

### Task 3.3: Create Runbooks
**Status:** Partially complete
**Effort:** 3-4 hours

**Needed Runbooks:**
- [ ] Keylime attestation failure troubleshooting
- [ ] Adding new hosts to infrastructure
- [ ] Certificate renewal procedures
- [ ] SPIRE agent recovery procedures
- [ ] Disaster recovery procedures

---

## 🎯 Priority 4: Future Enhancements

### Task 4.1: Contribute HTTPS Support Upstream
**Status:** Not started
**Effort:** Variable (depends on upstream)

**Steps:**
1. File issue in keylime/spire-keylime-plugin
2. Describe HTTPS/mTLS use case
3. Reference our fork implementation
4. Create pull request if requested
5. Document nginx proxy workaround

**Repository:** https://github.com/StrongStool0954/spire-keylime-plugin

---

### Task 4.2: DevID Rotation Automation
**Status:** Planned (Sprint 4)
**Effort:** 2-3 days

**Goal:** Automate 90-day DevID certificate rotation

---

### Task 4.3: Investigate Python Keylime Agent
**Status:** Deferred
**Effort:** 1-2 days

**Why:** Evaluate if Python agent has better SPIRE plugin compatibility

---

## 📋 Execution Order Recommendation

### Immediate (Today/Tomorrow)
1. ✅ **Task 1.3** - Clean up stale agents (15 min)
2. 🔴 **Task 1.1** - Upgrade auth.funlab.casa to HTTPS (2-3 hours)
3. 🔴 **Task 1.2** - Migrate spire.funlab.casa to Keylime (3-4 hours)
4. ✅ **Task 1.4** - Remove join_token plugin (30 min)

**Timeline:** 6-8 hours total
**Result:** Complete infrastructure migration to Keylime with HTTPS/mTLS

### Short Term (This Week)
5. **Task 2.1** - Update Phase 3 summary (30 min)
6. **Task 2.2** - Document nginx proxy (1 hour)
7. **Task 2.3** - Update infrastructure README (1-2 hours)
8. **Task 2.4** - Create Phase 4 completion doc (2 hours)

**Timeline:** 4-5 hours total
**Result:** Complete documentation of infrastructure

### Medium Term (Next Week)
9. **Task 3.1** - Performance testing (2-3 hours)
10. **Task 3.2** - Monitoring setup (4-6 hours)
11. **Task 3.3** - Create runbooks (3-4 hours)

**Timeline:** 9-13 hours total
**Result:** Production-ready operational procedures

### Long Term (Future Sprints)
12. **Task 4.1** - Contribute upstream (variable)
13. **Task 4.2** - DevID rotation automation (2-3 days)
14. **Task 4.3** - Evaluate Python agent (1-2 days)

---

## 🎬 Recommended Next Action

**Start with Task 1.3 + 1.1 combined session:**

1. **Clean stale agents** (15 min)
2. **Upgrade auth.funlab.casa to HTTPS** (2-3 hours)
   - Achieves complete HTTPS/mTLS across infrastructure
   - Low risk (same process as ca.funlab.casa)
   - Immediate security improvement

**Then proceed to Task 1.2:**

3. **Migrate spire.funlab.casa to Keylime** (3-4 hours)
   - Completes Phase 3 objectives
   - Enables removal of join_token plugin
   - Higher risk, but well-documented rollback

**Total Time:** 6-8 hours to complete core migration
**Result:** All hosts on Keylime with HTTPS/mTLS, join_token plugin removed

---

## 📊 Progress Tracking

**Sprint 3 Status:**
- Phase 1: Keylime Attestation ✅ COMPLETE
- Phase 2: Book of Omens PKI ✅ COMPLETE
- **Phase 3: Certificate Deployment** 🚀 **IN PROGRESS (90% complete)**
  - [x] ca.funlab.casa HTTPS/mTLS ✅
  - [ ] auth.funlab.casa HTTPS/mTLS ⏳
  - [ ] spire.funlab.casa migration ⏳
- Phase 4: Complete Migration ⏳ PENDING

**Completion:** 2 of 3 hosts fully migrated (67%)

---

**Last Updated:** 2026-02-10 23:00 EST
**Next Review:** After auth.funlab.casa upgrade
