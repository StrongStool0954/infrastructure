# Infrastructure Roadmap - All Projects

**Compiled:** 2026-02-11
**Status:** Consolidated view of all planned phases across infrastructure projects

---

## Current Status Overview

### Completed Projects ✅
- ✅ Book of Omens PKI (intermediate CA)
- ✅ Keylime mTLS deployment
- ✅ 24-hour certificate lifecycle with twice-daily renewal
- ✅ Nginx automation and monitoring
- ✅ OpenBao auto-unseal with TPM + Keylime attestation
- ✅ Network redesign with Pica8 (Phase 1 - LACP bonds)
- ✅ Network Phase 2: 10G uplink to Firewalla

### In Progress 🔄
- 🔄 1Password service account troubleshooting (OpenBao vault access)
- 🔄 Monitoring 24-hour certificate renewals (first week)

---

## OpenBao Auto-Unseal Project

**Current Status:** ✅ Production-ready on spire.funlab.casa

### Phase 1: TPM + Keylime Auto-Unseal ✅ COMPLETE
**Timeline:** Completed 2026-02-11
- ✅ TPM-encrypted unseal keys (keys 1-3)
- ✅ Keylime attestation gate
- ✅ Automatic unsealing on boot (62 seconds)
- ✅ Fail-secure design
- ✅ Reboot test: 100% success

### Phase 2: Performance Optimization
**Timeline:** Next 30 Days
**Status:** 🔲 Planned

**Goals:**
- Parallel TPM key decryption (reduce 27s → 9s)
- Pre-cache attestation result
- Optimize service startup order

**Expected Impact:**
- Recovery time: 62s → ~45s
- Boot phase optimization

### Phase 3: Observability
**Timeline:** Next 60 Days (Q1 2026)
**Status:** 🔲 Planned

**Monitoring:**
- Prometheus metrics for auto-unseal duration
- Grafana dashboard for boot timeline
- Alert if attestation status ≠ PASS
- Alert if unsealing takes > 120 seconds

**Deliverables:**
- Metrics exporter for openbao-autounseal service
- Grafana dashboard with boot/attestation timeline
- Alert rules for Prometheus

### Phase 4: Advanced Security
**Timeline:** Next 90 Days (Q2 2026)
**Status:** 🔲 Planned

**Security Enhancements:**
- Enable IMA runtime integrity monitoring
- Add measured boot policy (UEFI/kernel verification)
- Integrate SPIRE workload identity
- Add YubiKey requirement for manual unseal

**Expected Benefits:**
- Runtime file integrity checking
- Boot chain verification
- Workload-level identity attestation
- Hardware 2FA for emergency access

### Phase 5: Scale Out & High Availability
**Timeline:** Next 6 Months (H1 2026)
**Status:** 🔲 Planned

**Deployment Expansion:**
- Deploy to ca.funlab.casa
- Deploy to auth.funlab.casa
- Multi-node OpenBao cluster with HA
- Distributed attestation across nodes

**HA Features:**
- Auto-unseal for all cluster nodes
- Attestation-based failover
- Distributed key management

### Phase 6: Key Rotation Automation
**Timeline:** Q3 2026
**Status:** 🔜 Future

**Automation:**
- Automated Shamir key rotation
- TPM re-encryption workflow
- 1Password backup updates
- Zero-downtime rotation

---

## Certificate Infrastructure

**Current Status:** ✅ 24-hour certificates with twice-daily renewal operational

### Week 1: Monitoring & Validation
**Timeline:** 2026-02-11 to 2026-02-18
**Status:** 🔄 In Progress

**Tasks:**
- Monitor first 48 hours of operation
- Verify both renewal windows (3 AM, 3 PM)
- Check logs for issues
- Validate renewal success rate

### Week 2-3: Validation Period
**Timeline:** 2026-02-18 to 2026-03-01
**Status:** 🔲 Upcoming

**Goals:**
- Validate 14 successful renewals (7 days × 2/day)
- Confirm monitoring alerts work correctly
- Document edge cases
- Measure system load during renewals

### Month 1+: Long-term Operations
**Timeline:** March 2026+
**Status:** 🔜 Future

**Ongoing Tasks:**
- Continuous monitoring of renewal success rate
- Track OpenBao PKI performance metrics
- Consider applying to other certificate workloads
- Share operational learnings with team

### Future: Certificate Expansion
**Timeline:** Q2 2026+
**Status:** 🔜 Future

**Potential Workloads:**
- Service mesh certificates (if deployed)
- Application-level TLS
- Client certificates for mTLS
- Database connection certificates

---

## Reboot Survival & Resilience

**Current Status:** ✅ Auto-unseal implemented and tested

### Immediate (This Week)
**Timeline:** 2026-02-11 to 2026-02-18
**Status:** 🔄 In Progress

- ✅ Document reboot test results
- ✅ Implement TPM + Keylime auto-unseal
- ✅ Re-test reboot survival with auto-unseal
- 🔲 Update monitoring to alert on sealed >5 min after boot

### Short-term (This Month)
**Timeline:** February 2026
**Status:** 🔲 Planned

- 🔲 Add nginx upstream health checks for verifier
- 🔲 Test attestation failure scenarios
- 🔲 Document emergency manual unseal runbook
- 🔲 Create reboot survival runbook
- 🔲 Monthly reboot test during maintenance window

### Long-term (Future)
**Timeline:** Q2 2026+
**Status:** 🔜 Future

- 🔲 Add YubiKey for admin operations (Phase 2)
- 🔲 Test multi-node OpenBao HA auto-unseal
- 🔲 Implement automated seal rotation
- 🔲 Add reboot survival to CI/CD testing

---

## 1Password Integration

**Current Status:** ⚠️ OpenBao vault service account needs recreation

### Immediate (This Week)
**Timeline:** 2026-02-11 to 2026-02-18
**Status:** 🔲 Blocked

**Critical Task:**
- 🔲 Recreate OpenBao vault service account in 1Password
  - Delete existing account
  - Create new account following wizard exactly
  - Test immediately after creation
  - Deploy to production systems

**Alternative:**
- 🔲 Manual retrieval of unseal keys from 1Password UI
  - Unblocks auto-unseal implementation
  - Fix service account later as separate task

### Short-term (This Month)
**Timeline:** February 2026
**Status:** 🔲 Planned

- 🔲 Document working baseline for other service accounts
- 🔲 Create service account creation checklist
- 🔲 Test service account access from multiple hosts

---

## Network Infrastructure

**Current Status:** ✅ Phase 1 & 2 complete (LACP bonds + 10G uplink)

### Phase 1: LACP Bond Configuration ✅ COMPLETE
**Timeline:** Completed
- ✅ Configure all LACP bonds
- ✅ Test failover scenarios
- ✅ Validate performance

### Phase 2: 10G Uplink ✅ COMPLETE
**Timeline:** Completed 2026-02-11
**Status:** ✅ Complete

**Completed:**
- ✅ Installed 10GBASE-T SFP+ module
- ✅ Configured Firewalla uplink
- ✅ Tested bandwidth and routing
- ✅ Validated failover

**Result:** 10G uplink operational

### Phase 3: Management Network
**Timeline:** Q2 2026
**Status:** 🔜 Planned

**Goals:**
- Create dedicated management network (10.10.20.0/24)
- Separate management from production traffic
- Implement management ACLs

**Benefits:**
- Better security isolation
- Out-of-band management access
- Reduced attack surface

---

## Keylime Infrastructure

**Current Status:** ✅ mTLS deployed, attestation operational

### Current Operations
- ✅ Registrar operational on spire.funlab.casa
- ✅ Verifier operational on spire.funlab.casa
- ✅ Agent operational on spire.funlab.casa
- ✅ mTLS with Book of Omens PKI
- ✅ TPM attestation (SHA256 PCR bank)
- ✅ Continuous attestation (2-second interval)

### Short-term Enhancements
**Timeline:** Q1 2026
**Status:** 🔲 Planned

- 🔲 Deploy agents to ca.funlab.casa
- 🔲 Deploy agents to auth.funlab.casa
- 🔲 Test distributed attestation
- 🔲 Document agent deployment procedure

### Mid-term: IMA Integration
**Timeline:** Q2 2026
**Status:** 🔜 Planned

**Runtime Integrity Monitoring:**
- Enable IMA (Integrity Measurement Architecture)
- Configure runtime policy for file integrity
- Attest running processes and file modifications
- Alert on unexpected changes

**Requirements:**
- IMA kernel support (already available)
- Policy development for each host
- Integration with auto-unseal logic

### Long-term: Measured Boot
**Timeline:** Q3 2026
**Status:** 🔜 Future

**Boot Chain Attestation:**
- UEFI Secure Boot verification
- Bootloader attestation
- Kernel and initrd validation
- Complete boot chain trust

---

## SPIRE Integration

**Current Status:** ✅ SPIRE server operational on spire.funlab.casa

### Phase 1: Foundation ✅ COMPLETE
- ✅ SPIRE server deployed
- ✅ Basic workload registration

### Phase 2: Workload Identity
**Timeline:** Q2 2026
**Status:** 🔜 Planned

**Integration Goals:**
- Integrate SPIRE with Keylime attestation
- Use SPIRE SVIDs for service authentication
- Workload-level identity attestation
- Zero-trust service mesh

**Use Cases:**
- Service-to-service authentication
- Database connection identity
- API authentication
- Certificate issuance based on workload identity

---

## Monitoring & Observability

**Current Status:** ⚠️ Basic monitoring (nginx-monitor, service status)

### Phase 1: Basic Monitoring ✅ PARTIAL
**Status:** 🔄 In Progress

Current:
- ✅ Nginx monitoring (systemd timer)
- ✅ Certificate expiration checks
- ✅ Service health checks
- 🔲 Centralized logging (pending)
- 🔲 Metrics collection (pending)

### Phase 2: Prometheus & Grafana
**Timeline:** Q1-Q2 2026
**Status:** 🔲 Planned

**Infrastructure:**
- Deploy Prometheus server
- Configure service discovery
- Create custom exporters for:
  - OpenBao auto-unseal metrics
  - Keylime attestation status
  - Certificate renewal metrics
  - Network switch metrics

**Dashboards:**
- Boot timeline and auto-unseal performance
- Certificate lifecycle and renewals
- Keylime attestation health
- Network performance and utilization

### Phase 3: Alerting
**Timeline:** Q2 2026
**Status:** 🔲 Planned

**Alert Rules:**
- OpenBao sealed >5 minutes after boot
- Keylime attestation status ≠ PASS
- Certificate renewal failures
- Service availability issues
- Network performance degradation

**Notification Channels:**
- Email alerts
- Slack/Discord integration
- PagerDuty for critical issues

---

## Documentation

**Current Status:** ✅ Comprehensive documentation for all completed projects

### Completed Documentation ✅
- ✅ OpenBao auto-unseal (executive summary, implementation, test results)
- ✅ 24-hour certificate implementation
- ✅ Book of Omens PKI deployment
- ✅ Keylime mTLS deployment
- ✅ Network redesign documentation
- ✅ 1Password troubleshooting (baseline, clean container tests)

### Planned Documentation 🔲
- 🔲 Emergency manual unseal runbook
- 🔲 Reboot survival runbook
- 🔲 Service account creation procedure
- 🔲 Attestation failure response guide
- 🔲 Monthly maintenance checklist
- 🔲 Disaster recovery procedures

---

## Priority Matrix

### Critical (Do First) 🔴
1. **1Password Service Account Recreation** - Blocking OpenBao vault access
2. **Monitor 24h Certificates** - Validate twice-daily renewal working
3. **Emergency Runbooks** - Manual unseal, attestation failure response

### High Priority (This Quarter) 🟡
1. **Observability (Phase 3)** - Prometheus, Grafana, alerting
2. **Deploy Auto-Unseal to Other Hosts** - ca.funlab.casa, auth.funlab.casa
3. **IMA Integration** - Runtime integrity monitoring

### Medium Priority (Next Quarter) 🟢
1. **Performance Optimization (Phase 2)** - Parallel TPM decryption
2. **Advanced Security (Phase 4)** - Measured boot, SPIRE integration
3. **YubiKey Integration** - Hardware 2FA for emergency access
4. **Management Network** - Dedicated OOB management

### Future/Backlog (6+ Months) 🔵
1. **Multi-Node HA** - OpenBao cluster with distributed auto-unseal
2. **Key Rotation Automation** - Automated Shamir key rotation
3. **Service Mesh** - Full zero-trust workload identity
4. **CI/CD Testing** - Automated reboot survival tests

---

## Dependencies & Blockers

### Current Blockers 🚫
1. **1Password Service Account** - OpenBao vault access blocked
   - Impact: Cannot automate key retrieval from 1Password
   - Workaround: Manual retrieval from 1Password UI
   - Resolution: Recreate service account

### Dependencies 📊

**Auto-Unseal Phase 2 depends on:**
- Phase 1 stable operations (monitoring period)

**IMA Integration depends on:**
- Auto-unseal operational on target hosts
- Policy development for each host type

**Multi-Node HA depends on:**
- Auto-unseal deployed to all nodes
- OpenBao cluster configuration
- Distributed attestation working

**SPIRE Integration depends on:**
- Keylime attestation stable
- Workload identity requirements defined

---

## Success Metrics

### Current Achievements ✅
- **Auto-Unseal Recovery Time:** 62 seconds (98% faster than manual)
- **Certificate Renewal:** Twice-daily automatic renewal
- **Attestation Success Rate:** 100% (continuous verification)
- **Reboot Test Success:** 100% (first test)
- **Service Availability:** 7/7 services auto-start

### Target Metrics for 2026 Q1-Q2

**Reliability:**
- Auto-unseal success rate: >99.9%
- Certificate renewal success rate: >99.9%
- Attestation uptime: >99.9%
- Reboot recovery time: <45 seconds (with optimizations)

**Security:**
- Zero failed attestations (legitimate systems)
- 100% audit trail coverage
- Emergency access via YubiKey only

**Operational:**
- Zero manual unseal interventions
- <10 minutes MTTR for any issues
- 100% documentation coverage
- Monthly reboot testing

---

## Timeline Summary

### February 2026 (Current)
- ✅ OpenBao auto-unseal implementation complete
- ✅ Network Phase 2: 10G uplink to Firewalla complete
- 🔄 Monitor 24h certificate renewals
- 🔲 Recreate 1Password service account
- 🔲 Write emergency runbooks
- 🔲 Update monitoring alerts

### March 2026 (Q1)
- Deploy auto-unseal to ca.funlab.casa
- Deploy auto-unseal to auth.funlab.casa
- Implement Prometheus + Grafana
- Test attestation failure scenarios

### April-June 2026 (Q2)
- Performance optimizations (parallel TPM decryption)
- IMA runtime integrity monitoring
- SPIRE workload identity integration
- YubiKey emergency access
- Management network deployment

### July-September 2026 (Q3)
- Measured boot policies
- Key rotation automation
- Multi-node OpenBao cluster planning
- Advanced alerting and dashboards

### October-December 2026 (Q4)
- OpenBao HA with distributed auto-unseal
- Service mesh deployment
- CI/CD integration for testing
- Year-end security review

---

## Budget & Resources

### Time Investment (Estimated)

**Q1 2026:**
- Monitoring & observability: 2-3 weeks
- Host expansion: 1 week
- Runbook creation: 1 week
- **Total:** ~1 month

**Q2 2026:**
- IMA integration: 2 weeks
- SPIRE integration: 2 weeks
- Performance optimization: 1 week
- YubiKey setup: 1 week
- **Total:** ~1.5 months

**Q3-Q4 2026:**
- Multi-node HA: 3-4 weeks
- Advanced security: 2-3 weeks
- Automation: 2 weeks
- **Total:** ~2 months

### Hardware Requirements

**Completed:**
- ✅ 10GBASE-T SFP+ module (Network Phase 2) - Acquired and installed

**Q2 2026:**
- YubiKeys for admin access - ~$100-150

**Future:**
- Additional hardware for HA nodes (if needed)

---

## Risk Assessment

### Low Risk ✅
- Auto-unseal implementation (already proven)
- Certificate renewals (tested and working)
- Host expansion (repeatable process)

### Medium Risk ⚠️
- IMA policy development (complexity in getting policies right)
- Network changes (potential for connectivity issues)
- Multi-node HA (coordination complexity)

### High Risk 🔴
- Attestation failure scenarios (could lock out systems)
- Key rotation (risk of losing access if done wrong)
- Production deployments without testing

### Mitigation Strategies
1. **Always test in non-production first**
2. **Maintain manual recovery procedures**
3. **Keep emergency keys accessible (1Password)**
4. **Document every change**
5. **Monthly reboot testing in maintenance windows**
6. **Have rollback plans for all changes**

---

## Conclusion

This roadmap represents a comprehensive plan for infrastructure maturity across:
- **Security:** Attestation-gated access, hardware root of trust, runtime integrity
- **Automation:** Zero-touch recovery, automated renewals, self-healing
- **Observability:** Metrics, dashboards, alerting
- **Resilience:** HA, distributed systems, automated failover
- **Operations:** Reduced toil, better debugging, faster recovery

**Current Status:** ✅ Strong foundation with multiple production-ready systems
**Next 6 Months:** Focus on observability, security hardening, and scale-out
**Next 12 Months:** Full zero-trust infrastructure with automated operations

---

**Last Updated:** 2026-02-11
**Maintained By:** Infrastructure Team
**Review Cadence:** Monthly
