# Zero Trust + mTLS Validation Service - Combined Roadmap

**Date:** 2026-02-11
**Status:** 📋 Planning Complete
**Purpose:** Unified roadmap showing how mTLS validation service integrates with Zero Trust Architecture

---

## Executive Summary

This roadmap combines two initiatives:

1. **Zero Trust Architecture** - Complete infrastructure transformation ([Master Plan](zero-trust-architecture-master-plan.md))
2. **mTLS Validation Service** - "Hello World" test to prove auth stack works ([Service Plan](MTLS-WEB-SERVICE-PLAN.md))

**Key Insight:** The validation service serves as a **proof-of-concept** for the authentication components (Authentik, step-ca, SPIRE, OpenBao) before migrating production services.

---

## Timeline Overview (12 Weeks Total)

```
┌─────────────────────────────────────────────────────────────┐
│ FOUNDATION PHASE (Weeks 1-4)                                │
├─────────────────────────────────────────────────────────────┤
│ Week 1:  Zero Trust Phase 1 - Migrate Plex to NPM          │
│ Week 2-4: Zero Trust Phase 2 - Deploy Tower of Omens       │
│           ├─ step-ca with TPM                               │
│           ├─ OpenBao with TPM                               │
│           └─ SPIRE with TPM                                 │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ AUTHENTICATION PHASE (Weeks 5-7)                            │
├─────────────────────────────────────────────────────────────┤
│ Week 5-6: Zero Trust Phase 3 - Deploy Authentik            │
│           └─ auth.funlab.casa with passkeys                 │
│ Week 7:   Zero Trust Phase 4 - Client Certificate Flow     │
│           └─ Authentik ↔ step-ca integration                │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ VALIDATION PHASE (Weeks 7-10)                               │
├─────────────────────────────────────────────────────────────┤
│ Week 7:   Validation Service Phase 1 - Basic deployment    │
│ Week 8:   Validation Service Phase 2 - OAuth integration   │
│ Week 9:   Validation Service Phase 3 - Device enrollment   │
│ Week 10:  Validation Service Phase 4 - Dual auth (mTLS+OAuth)│
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ PRODUCTION MIGRATION (Weeks 10-12+)                         │
├─────────────────────────────────────────────────────────────┤
│ Week 10:  Zero Trust Phase 5 - Migrate Home Assistant      │
│ Week 11:  Zero Trust Phase 5 - Migrate MusicBrainz         │
│ Week 12:  Zero Trust Phase 6 - HA & Hardening              │
└─────────────────────────────────────────────────────────────┘
```

---

## Detailed Week-by-Week Plan

### **Week 1: Foundation - NPM Deployment**
**Zero Trust Phase 1**

**Objectives:**
- Establish NPM as central reverse proxy
- Migrate Plex to NPM
- Validate Bunny.net integration

**Tasks:**
- [ ] Deploy npm.funlab.casa (if not already deployed)
- [ ] Configure NPM proxy for plex.funlab.casa
- [ ] Request Let's Encrypt certificate via NPM
- [ ] Update Bunny.net origin to npm.funlab.casa
- [ ] Update Firewalla port forwarding
- [ ] Test Plex external access

**Success Criteria:**
- ✅ Plex accessible via NPM
- ✅ Bunny.net → NPM → Plex flow working
- ✅ Let's Encrypt automation working

**Deliverables:**
- NPM operational and proven with production service (Plex)

---

### **Weeks 2-4: Tower of Omens Infrastructure**
**Zero Trust Phase 2**

**Objectives:**
- Deploy three pillars of zero trust with TPM backing
- Create secure foundation for authentication

**Week 2: step-ca Deployment**
- [ ] Assess current tinyca deployment
- [ ] Deploy new step-ca instance with TPM support
- [ ] Initialize root CA with TPM-backed keys
- [ ] Create intermediate CA
- [ ] Configure ACME provisioner
- [ ] Test certificate issuance
- [ ] Migrate certificate distribution

**Week 3: OpenBao Deployment**
- [ ] Install OpenBao on TPM-equipped hardware
- [ ] Configure TPM auto-unseal
- [ ] Initialize vault with Shamir keys
- [ ] Test automatic unsealing on boot
- [ ] Create initial policies (admin, service, read-only)
- [ ] Migrate secrets from 1Password

**Week 4: SPIRE Deployment**
- [ ] Deploy SPIRE server with TPM attestation
- [ ] Configure upstream CA (step-ca integration)
- [ ] Deploy SPIRE agents on service hosts
- [ ] Configure workload attestors (Docker, systemd)
- [ ] Test workload registration
- [ ] Test service-to-service mTLS

**Success Criteria:**
- ✅ step-ca issuing certificates with TPM backing
- ✅ OpenBao auto-unseals on boot (TPM-encrypted keys)
- ✅ SPIRE issuing workload identities (SVIDs)
- ✅ All three components integrated and tested

**Deliverables:**
- Tower of Omens fully operational
- Foundation ready for authentication layer

---

### **Weeks 5-6: Authentik Deployment**
**Zero Trust Phase 3**

**Objectives:**
- Deploy auth.funlab.casa as OAuth/OIDC provider
- Enable passkey authentication
- Integrate with Tower of Omens

**Week 5: Core Authentik Deployment**
- [ ] Create LXC container for auth.funlab.casa
- [ ] Deploy Authentik stack (server, PostgreSQL, Redis)
- [ ] Request certificate from step-ca
- [ ] Configure NPM proxy for auth.funlab.casa
- [ ] Complete initial Authentik setup wizard
- [ ] Create admin user and test login

**Week 6: Passkey Configuration**
- [ ] Enable WebAuthn authentication stage
- [ ] Configure passkey enrollment flow
- [ ] Set passkey as default authentication
- [ ] Add password as fallback
- [ ] Test passkey registration (phone, laptop)
- [ ] Test passkey login (Face ID, Touch ID)
- [ ] Integrate Authentik with OpenBao (secrets retrieval)
- [ ] Configure split-brain DNS (LAN/WAN)
- [ ] Set up Cloudflare Tunnel for external access

**Success Criteria:**
- ✅ auth.funlab.casa accessible (LAN and WAN)
- ✅ Passkey registration working
- ✅ Passkey login working (Face ID/Touch ID)
- ✅ Password fallback functional
- ✅ Secrets retrieved from OpenBao
- ✅ Works offline (local DNS)

**Deliverables:**
- auth.funlab.casa fully operational
- Passkey authentication proven
- Ready for service integration

---

### **Week 7: Client Certificate Enrollment**
**Zero Trust Phase 4 + Validation Service Phase 1**

**Objectives:**
- Integrate Authentik with step-ca for certificate issuance
- Create device enrollment flow
- Deploy basic validation service

**Tasks:**

**Authentik ↔ step-ca Integration:**
- [ ] Configure step-ca provisioner for user certificates
- [ ] Create Authentik → step-ca API integration
- [ ] Test certificate issuance via API
- [ ] Configure certificate template (CN, OU, EKU)

**Device Enrollment Flow:**
- [ ] Create "Device Enrollment" flow in Authentik
- [ ] Add certificate request stage (CSR generation)
- [ ] Add step-ca issuance stage (API call)
- [ ] Add certificate download stage (PKCS#12 delivery)
- [ ] Create "My Devices" page in Authentik UI
- [ ] Add device revocation capability

**Basic Validation Service:**
- [ ] Deploy simple nginx static site (test backend)
- [ ] Create "Hello World" page
- [ ] Configure NPM proxy for test.funlab.casa
- [ ] Request Let's Encrypt certificate
- [ ] Test basic HTTPS access (no auth yet)

**Success Criteria:**
- ✅ Users can enroll devices via Authentik
- ✅ step-ca issues client certificates
- ✅ Certificates delivered as PKCS#12
- ✅ Certificates install on devices
- ✅ Basic validation service accessible
- ✅ NPM proxying working

**Deliverables:**
- Device enrollment functional
- Test service ready for auth integration

---

### **Week 8: OAuth Integration**
**Validation Service Phase 2**

**Objectives:**
- Integrate validation service with Authentik OAuth
- Prove passkey authentication flow
- Test end-to-end OAuth workflow

**Tasks:**
- [ ] Create OAuth application in Authentik
- [ ] Deploy oauth2-proxy on NPM host
- [ ] Configure NPM for OAuth validation
- [ ] Update test page to show auth info
- [ ] Test OAuth redirect flow
- [ ] Test passkey login from test service
- [ ] Verify JWT token validation
- [ ] Test session persistence

**Success Criteria:**
- ✅ Unauthenticated users redirected to auth.funlab.casa
- ✅ Passkey login works from test service
- ✅ Users redirected back with JWT token
- ✅ Test page shows user information
- ✅ Session persists (1-hour TTL)
- ✅ Logout clears session

**Deliverables:**
- OAuth flow proven
- Passkey authentication validated
- Ready for mTLS addition

---

### **Week 9: Device Enrollment Testing**
**Validation Service Phase 3**

**Objectives:**
- Test complete device enrollment workflow
- Validate certificate installation on multiple devices
- Verify certificate attributes

**Tasks:**
- [ ] Test enrollment from iPhone
- [ ] Test enrollment from Android
- [ ] Test enrollment from macOS
- [ ] Test enrollment from Windows
- [ ] Verify PKCS#12 file structure
- [ ] Verify certificate attributes (CN, EKU)
- [ ] Test certificate installation on all platforms
- [ ] Verify browser can select certificate

**Success Criteria:**
- ✅ Enrollment works on all device types
- ✅ Certificates install correctly
- ✅ Browsers can present certificates
- ✅ Certificate details correct
- ✅ Private keys protected

**Deliverables:**
- Enrollment proven on all platforms
- Ready for NPM mTLS validation

---

### **Week 10: Dual Authentication (mTLS + OAuth)**
**Validation Service Phase 4**

**Objectives:**
- Configure NPM for dual authentication
- Validate both mTLS and OAuth paths
- Prove priority-based authentication

**Tasks:**
- [ ] Upload step-ca CA bundle to NPM
- [ ] Configure NPM `ssl_verify_client optional`
- [ ] Implement priority-based auth logic
- [ ] Update test page to show auth method
- [ ] Test mTLS path (enrolled device)
- [ ] Test OAuth path (non-enrolled device)
- [ ] Test certificate revocation
- [ ] Verify CRL checking

**Success Criteria:**
- ✅ Enrolled devices: Zero-click access (mTLS)
- ✅ Non-enrolled devices: Passkey login (OAuth)
- ✅ Priority fallback correct
- ✅ Test page shows auth method
- ✅ Certificate revocation works
- ✅ Both paths audited in logs

**Deliverables:**
- **🎉 VALIDATION SERVICE COMPLETE**
- Authentication stack fully proven
- Ready for production service migrations

---

### **Week 11: Migrate Home Assistant**
**Zero Trust Phase 5.1**

**Objectives:**
- Migrate production service using proven auth pattern
- Apply validated configuration to real service

**Tasks:**
- [ ] Create OAuth application for Home Assistant
- [ ] Configure NPM proxy for ha.funlab.casa
- [ ] Configure HA trusted proxies
- [ ] Test OAuth login
- [ ] Test mTLS access (enrolled devices)
- [ ] Configure Bunny.net CDN
- [ ] Enable SPIRE workload identity
- [ ] Test mobile app access
- [ ] Monitor and validate

**Success Criteria:**
- ✅ HA accessible with OAuth login
- ✅ Passkey authentication working
- ✅ mTLS seamless access working
- ✅ Mobile app connectivity working
- ✅ No internet = local auth still works
- ✅ Zero trust: Always authenticate

**Deliverables:**
- Home Assistant migrated successfully
- Production service using new auth stack

---

### **Week 12: Migrate MusicBrainz + Hardening**
**Zero Trust Phase 5.2 + 6**

**Objectives:**
- Migrate MusicBrainz API with OAuth tokens
- Implement HA and hardening

**Tasks:**

**MusicBrainz Migration:**
- [ ] Configure OAuth client credentials
- [ ] Deploy MusicBrainz service
- [ ] Configure NPM proxy
- [ ] Configure Bunny Edge Script (JWT validation)
- [ ] Update API clients (Aurral, Lidarr)
- [ ] Test API access with bearer tokens

**High Availability:**
- [ ] Deploy secondary Authentik instance
- [ ] Configure NPM failover
- [ ] Implement JWT caching
- [ ] Test Authentik failover

**Hardening:**
- [ ] Configure monitoring (Prometheus + Grafana)
- [ ] Security hardening (fail2ban, rate limiting)
- [ ] Backup automation
- [ ] Load testing

**Success Criteria:**
- ✅ MusicBrainz API with OAuth tokens
- ✅ Dual Authentik instances with failover
- ✅ Monitoring operational
- ✅ Backups automated
- ✅ Load testing passed

**Deliverables:**
- All services migrated
- Production-grade zero trust architecture
- Complete observability

---

## Critical Path Analysis

### **Sequential Dependencies (Cannot Parallelize)**

```
Week 1: NPM
   ↓
Weeks 2-4: Tower of Omens (can parallelize internally)
   ↓
Weeks 5-6: Authentik
   ↓
Week 7: Client Certificates
   ↓
Weeks 8-10: Validation Service (must validate before production)
   ↓
Weeks 11-12: Production Migrations
```

**Total Critical Path: 12 weeks**

### **Parallel Opportunities**

**Tower of Omens (Weeks 2-4):**
- Can deploy step-ca, OpenBao, SPIRE in parallel if multiple people/machines

**Validation Service (Weeks 8-10):**
- Testing can overlap (OAuth testing while preparing mTLS)

**Production Migrations (Weeks 11-12):**
- HA and MusicBrainz can migrate in parallel if comfortable with risk

**Optimized Timeline: 10 weeks** (with parallelization)

---

## Success Metrics

### **Foundation Metrics (Weeks 1-4)**
- ✅ NPM operational and proven with Plex
- ✅ step-ca issuing certificates with TPM
- ✅ OpenBao auto-unseals (62 seconds)
- ✅ SPIRE issuing SVIDs

### **Authentication Metrics (Weeks 5-7)**
- ✅ Authentik deployed and operational
- ✅ Passkey authentication proven
- ✅ Device enrollment functional
- ✅ Certificates issued successfully

### **Validation Metrics (Weeks 8-10) - CRITICAL**
- ✅ OAuth flow: 100% success rate
- ✅ Passkey login: < 2 seconds
- ✅ mTLS validation: 100% success rate
- ✅ Certificate enrollment: Works on all platforms
- ✅ Dual auth: Both paths functional
- ✅ Zero manual intervention

### **Production Metrics (Weeks 11-12)**
- ✅ All services migrated successfully
- ✅ Zero downtime migrations
- ✅ User adoption: 100% (passkeys enrolled)
- ✅ mTLS adoption: > 80% (devices enrolled)
- ✅ Uptime: 99.9%

---

## Risk Management

### **High Risk: Validation Service Failure**

**Risk:** Validation service proves authentication stack doesn't work

**Impact:** Cannot migrate production services, must redesign

**Mitigation:**
- Validate each component independently first
- Test thoroughly before declaring success
- Document all issues and resolutions
- Fix issues in validation service before touching production

**Contingency:**
- Validation service is disposable - can tear down and rebuild
- No production impact if validation fails
- Learn from failures and iterate

### **Medium Risk: Authentik Deployment Issues**

**Risk:** auth.funlab.casa has problems, blocks validation service

**Impact:** Delays validation and production migrations

**Mitigation:**
- Deploy Authentik early (Week 5)
- Test extensively before relying on it
- Have Cloudflare Tunnel alternative ready
- Keep existing auth methods during transition

**Contingency:**
- Services keep existing auth (Plex.tv, HA built-in)
- Validation service can use basic auth temporarily
- Fix Authentik issues before production migrations

### **Low Risk: Certificate Enrollment UX Issues**

**Risk:** Users struggle with certificate installation

**Impact:** Lower mTLS adoption, more OAuth usage

**Mitigation:**
- Create detailed installation guides
- Test on all device types
- Provide screenshots and videos
- Support multiple enrollment methods

**Contingency:**
- OAuth path always works as fallback
- Can improve enrollment UX iteratively
- Device enrollment is optional enhancement

---

## Rollback Strategy

### **Validation Service (Weeks 8-10)**

**If validation fails:**
1. Validation service can be torn down completely
2. No production impact (it's a test service)
3. Fix issues and redeploy
4. Time to rollback: 0 seconds (never went to production)

### **Production Migrations (Weeks 11-12)**

**If migration fails:**

**Home Assistant:**
1. Update DNS: ha.funlab.casa → old IP
2. Remove NPM proxy host
3. HA continues with built-in auth
4. Time to rollback: 5 minutes

**MusicBrainz:**
1. Remove Bunny.net Pull Zone
2. Update DNS to direct access
3. Disable OAuth validation in NPM
4. Time to rollback: 10 minutes

**Authentik Failure:**
1. Services fall back to existing auth methods
2. Plex: Uses Plex.tv (unchanged)
3. HA: Uses built-in auth (revert config)
4. Validation service: Disposable
5. Time to rollback: 15 minutes

---

## Key Decision Points

### **Week 4: Go/No-Go for Authentik**

**Decision:** Is Tower of Omens stable enough to support Authentik?

**Criteria:**
- ✅ step-ca issuing certificates reliably
- ✅ OpenBao auto-unsealing consistently
- ✅ SPIRE workload identities working
- ✅ Integration tests passing

**If NO:** Delay Authentik, fix Tower issues first

---

### **Week 7: Go/No-Go for Validation Service**

**Decision:** Is Authentik ready for service integration?

**Criteria:**
- ✅ Passkey authentication working
- ✅ OAuth tokens issued correctly
- ✅ Session management functional
- ✅ Works both LAN and WAN

**If NO:** Fix Authentik issues before validation service

---

### **Week 10: Go/No-Go for Production Migrations**

**Decision:** Has validation service proven the auth stack works?

**Criteria:**
- ✅ OAuth flow: 100% success
- ✅ Passkey login: < 2 seconds
- ✅ mTLS validation: 100% success
- ✅ Device enrollment: Works on all platforms
- ✅ Dual auth: Both paths functional
- ✅ Certificate revocation works
- ✅ Monitoring and logging complete

**If NO:** Do NOT migrate production services yet, fix validation issues first

**This is the CRITICAL gate - validation service exists specifically to prove readiness**

---

## Documentation Requirements

### **Required Before Week 8 (Validation Service)**

- [ ] Authentik deployment guide
- [ ] Authentik passkey setup guide
- [ ] Device enrollment user guide
- [ ] Troubleshooting guide (Authentik)

### **Required Before Week 11 (Production Migrations)**

- [ ] Validation service test results (COMPLETE REPORT)
- [ ] Service migration template
- [ ] Rollback procedures (tested)
- [ ] User communication plan

### **Required After Week 12 (Complete)**

- [ ] Zero trust architecture documentation (final)
- [ ] Operational runbooks
- [ ] User guides (passkeys, device enrollment)
- [ ] Monitoring and alerting guide

---

## Next Steps

### **This Week (Week 1)**

1. **Review and approve this roadmap**
2. **Confirm Zero Trust Phase 1 status** (NPM deployment)
3. **Begin Zero Trust Phase 2 planning** (Tower of Omens hardware)
4. **Schedule Go/No-Go meetings** (Weeks 4, 7, 10)

### **Next 4 Weeks**

1. **Complete Tower of Omens deployment**
2. **Validate TPM-backed components**
3. **Prepare for Authentik deployment**
4. **Go/No-Go Week 4: Authentik deployment**

### **Weeks 5-10**

1. **Deploy and validate Authentik**
2. **Deploy validation service**
3. **Test authentication stack thoroughly**
4. **Go/No-Go Week 10: Production migrations**

### **Weeks 11-12**

1. **Migrate production services**
2. **Implement HA and hardening**
3. **Complete documentation**
4. **Celebrate zero trust architecture! 🎉**

---

**Status:** 📋 Planning Complete
**Next Action:** Begin Zero Trust Phase 1 (NPM deployment)
**Critical Gate:** Week 10 - Validation service must pass before production migrations

**Last Updated:** 2026-02-11
**Author:** Infrastructure Team
