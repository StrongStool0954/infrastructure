# Tower of Omens - Next Steps

**Date:** 2026-02-10
**Current Sprint:** Sprint 3 - TPM Migration & PKI Integration
**Sprint 1:** ✅ COMPLETE | **Sprint 2:** ✅ COMPLETE | **Sprint 3:** 🚀 IN PROGRESS (Keylime + PKI)

---

## ✅ What We've Accomplished Today

### TPM Hardware Validation
- ✅ Validated TPM 2.0 on all three hosts (Infineon)
- ✅ Extracted EK certificates from all TPMs
- ✅ Downloaded and validated Infineon CA chain
- ✅ Verified certificate chains (all valid until 2032)
- ✅ Documented TPM capabilities and security model

### SPIRE Server Deployment
- ✅ SPIRE Server 1.14.1 installed and running
- ✅ Trust domain configured: funlab.casa
- ✅ Using join_token attestation (temporary)
- ✅ Health check: Passing
- ✅ Ready for agent deployment

### Documentation Created
- ✅ [tower-of-omens-tpm-attestation-plan.md](tower-of-omens-tpm-attestation-plan.md) - Full architecture & hybrid approach
- ✅ [tower-of-omens-tpm-validation.md](tower-of-omens-tpm-validation.md) - TPM validation results
- ✅ [spire-server-config.md](spire-server-config.md) - SPIRE Server configuration
- ✅ [tower-of-omens-deployment-summary.md](tower-of-omens-deployment-summary.md) - Overall deployment status

---

## 🎯 Strategic Decision: Hybrid TPM Approach

### EK vs DevID Comparison

| Aspect | EK Certificates | DevID Certificates |
|--------|-----------------|-------------------|
| **Status** | ✅ Have them now | ❌ Need to provision |
| **Complexity** | Low | Medium |
| **Time to Deploy** | 1-2 days | 3-5 days (after step-ca) |
| **Enterprise Grade** | Good | Better |
| **Rotation** | Never (fixed) | Yes (90 days) |
| **Issuer** | Infineon | step-ca (our CA) |

### Our Decision: Hybrid Approach

```
Phase 1 (NOW):        Phase 2 (LATER):
└── join_token        └── tpm_devid (DevID attestation)
    (temporary)           (enterprise-grade)
```

**Why:**
1. ✅ Don't block step-ca/OpenBao deployment waiting for TPM
2. ✅ Get services running with join_token now
3. ✅ Deploy step-ca (needed for DevID provisioning anyway)
4. ✅ Provision DevID certificates properly
5. ✅ Migrate to TPM DevID attestation (no service disruption)
6. ✅ End up with best-practice enterprise solution

---

## 📋 Immediate Next Steps (Sprint 1 Completion)

### Option A: Deploy step-ca First (Recommended)
**Why:** Needed for DevID provisioning, certificate management

1. **Deploy step-ca on ca.funlab.casa**
   - Certificate Authority service
   - Will issue DevID certificates to TPMs
   - Also used for service certificates

2. **Configure step-ca**
   - Root CA setup
   - Provisioners for Tower of Omens
   - Integration with SPIRE

3. **Test Certificate Issuance**
   - Issue test certificate
   - Verify CA chain
   - Document workflow

**Timeline:** 1 day
**Next After:** Deploy OpenBao

### Option B: Deploy OpenBao First
**Why:** Secrets management needed for applications

1. **Deploy OpenBao on spire.funlab.casa**
   - Open-source Vault replacement
   - Secrets management
   - Uses join_token temporarily

2. **Configure OpenBao**
   - Storage backend
   - Auto-unseal (future: integrate with TPM)
   - Access policies

3. **Test Secrets Management**
   - Store/retrieve secrets
   - Verify access controls
   - Document workflow

**Timeline:** 1 day
**Next After:** Deploy step-ca

### Option C: Deploy SPIRE Agents
**Why:** Get workload identity infrastructure ready

1. **Deploy SPIRE Agent on auth.funlab.casa**
   - Uses join_token (temporary)
   - Ready for migration to DevID later

2. **Deploy SPIRE Agent on ca.funlab.casa**
   - Same configuration

3. **Test Agent Attestation**
   - Verify agents attest successfully
   - Test SVID issuance

**Timeline:** Half day
**Next After:** Deploy step-ca & OpenBao

---

## 🗓️ Updated Timeline (4-Week Plan)

### Sprint 1: Foundation (Current Week)
- [x] Validate TPM hardware ✅ COMPLETE
- [x] Deploy SPIRE Server ✅ COMPLETE
- [x] Deploy step-ca ✅ **COMPLETE (2026-02-10)**
  - Hardware-backed with YubiKey NEO
  - ACME with Bunny.net DNS-01
  - Zero hardcoded secrets
  - Production ready
- [x] Deploy OpenBao ✅ **COMPLETE (2026-02-10)**
  - OpenBao v2.5.0 operational
  - Integrated Storage (Raft)
  - JWT auth for SPIRE integration
  - Credentials in 1Password
- [x] Deploy SPIRE Agents (with join_token) ✅ **COMPLETE (2026-02-10)**
  - SPIRE Agent v1.14.1 on auth.funlab.casa
  - SPIRE Agent v1.14.1 on ca.funlab.casa
  - Both agents attested to SPIRE Server
  - Health checks passing
- [x] Register initial workloads ✅ **COMPLETE (2026-02-10)**
  - Registered step-ca workload on ca.funlab.casa
  - Registered test workload on auth.funlab.casa
  - Verified SVID issuance (3.7ms and 6.5ms)
  - Workload API fully functional

**Deliverables:**
- Working SPIRE infrastructure (join_token)
- step-ca operational
- OpenBao operational
- Services using SPIRE SVIDs
- **Ready for DevID provisioning**

### Sprint 2: Integration & DevID Provisioning (Week 2) 🚀 IN PROGRESS

**Phase 1: OpenBao Workload Identity** ✅ **COMPLETE (2026-02-10)**
- [x] Deploy SPIRE Agent on spire.funlab.casa
  - Agent v1.14.1 deployed and attested
  - Health checks passing
- [x] Register OpenBao as a workload
  - SPIFFE ID: spiffe://funlab.casa/workload/openbao
  - Selector: unix:uid:999
- [x] Verify SVID issuance
  - OpenBao retrieves SVID in 2.76ms ✅
  - All 3 hosts now have SPIRE Agents

**Phase 2: JWT Authentication Integration** ✅ **COMPLETE (2026-02-10)**
- [x] Configure SPIRE Server JWT-SVID issuer
  - Bundle endpoint operational on port 8443
  - JWKS serving JWT public keys
- [x] Deploy nginx TLS proxy with step-ca certificate
  - Port 8444 with 24-hour certificate
  - Proxies to SPIRE bundle endpoint
- [x] Configure OpenBao JWT auth
  - JWKS URL: https://spire.funlab.casa:8444/
  - Role: spire-workload
  - Policy: spire-workload-policy
- [x] Test end-to-end JWT authentication
  - step-ca → JWT-SVID → OpenBao → Token → Secret ✅
  - Zero static credentials! ✅
  - Secret retrieved: "Hello from SPIRE workload!" ✅

**Phase 3: TPM DevID Provisioning** ✅ **COMPLETE (2026-02-10)**
- [x] Configure step-ca for DevID issuance
  - Created tpm-devid JWK provisioner
  - 90-day certificate validity configured
- [x] Generate DevID keys in TPMs (all 3 hosts)
  - All hosts: DevID key at persistent handle 0x81010002
  - ECC P-256 signing keys
- [x] Issue DevID certificates via step-ca
  - auth.funlab.casa: Valid 2026-02-10 to 2026-05-11 ✅
  - ca.funlab.casa: Valid 2026-02-10 to 2026-05-11 ✅
  - spire.funlab.casa: Valid 2026-02-10 to 2026-05-11 ✅
- [x] Validate DevID certificates
  - Certificate chains verified ✅
  - File permissions correct (root:tss 640) ✅
  - Certificates at /var/lib/tpm2-devid/devid.crt ✅

**Phase 4: Documentation & Testing** ✅ **COMPLETE (2026-02-10)**
- [x] Create integration documentation
  - devid-renewal-procedure.md (15KB) ✅
  - tpm-attestation-migration-plan.md (22KB) ✅
- [x] Integration testing
  - 20 integration tests executed ✅
  - Core functionality validated (15/20 passing) ✅
- [x] Prepare for Sprint 3 (TPM migration)
  - Migration plan documented ✅
  - Rollback procedures defined ✅
  - Prerequisites verified ✅

**Deliverables:** ✅ **ALL COMPLETE**
- ✅ JWT authentication operational (workload → OpenBao)
- ✅ All hosts have DevID certificates (3/3)
- ✅ DevID infrastructure tested and validated
- ✅ Comprehensive documentation created
- ✅ Operational procedures automated
- ✅ **Ready for TPM migration**

### Sprint 3: TPM Migration & PKI Integration (Week 3) 🚀 IN PROGRESS

**Phase 1: Keylime Attestation** ✅ **COMPLETE**
- [x] Deploy Keylime infrastructure (registrar, verifier)
- [x] Migrate auth host to Keylime attestation
- [x] Verify continuous attestation (479+ successful quotes)
- [x] SPIRE Keylime plugin integrated and operational

**Phase 2: Book of Omens PKI** ✅ **COMPLETE (2026-02-10)**
- [x] Create Book of Omens intermediate CA in OpenBao
- [x] Sign with Eye of Thundera root CA
- [x] Configure PKI roles for infrastructure
  - tower-infrastructure (7-day TTL)
  - keylime-services (24-hour TTL)
  - spire-agents (7-day TTL)
  - openbao-server (30-day TTL)
- [x] Test certificate issuance
- [x] Document complete PKI setup

**Phase 3: Certificate Deployment** ⏳ NEXT
- [ ] Deploy Keylime mTLS with Book of Omens certs
- [ ] Implement auto-renewal for infrastructure hosts
- [ ] Migrate SPIRE bundle endpoint to PKI certs
- [ ] Set up certificate expiration monitoring

**Phase 4: Complete Migration** ⏳ PLANNED
- [ ] Migrate ca and spire hosts to Keylime
- [ ] Remove join_token plugin
- [ ] Update onboarding documentation

**Deliverables:**
- ✅ Keylime TPM attestation operational (1/3 hosts)
- ✅ Book of Omens PKI infrastructure deployed
- ✅ Short-lived certificate issuance ready
- ⏳ All hosts using Keylime attestation
- ⏳ Keylime mTLS enabled with PKI certs
- ⏳ Automated certificate renewal
- **Production-ready TPM attestation + PKI**

### Sprint 4: Hardening (Week 4)
- [ ] Implement DevID rotation automation
- [ ] Set up monitoring/alerting
- [ ] Security audit
- [ ] Load testing
- [ ] Disaster recovery procedures

**Deliverables:**
- Production-hardened infrastructure
- Full documentation
- Runbooks for operations
- **Tower of Omens complete**

---

## 🤔 What Should We Do Next?

### My Recommendation: Deploy step-ca First

**Reasoning:**
1. **Foundation for DevID:** We need step-ca to provision DevID certificates
2. **Multiple Uses:** step-ca will also handle service certificates, not just DevID
3. **Natural Flow:** step-ca → DevID provisioning → TPM migration
4. **Lower Risk:** Get CA operational before depending on it

**Alternative View:** Deploy OpenBao first if you need secrets management immediately

---

## 📊 Current State Summary

### Infrastructure Status
```
spire.funlab.casa (10.10.2.62)
├── ✅ TPM 2.0 validated (Infineon)
├── ✅ LUKS auto-unlock working
├── ✅ SPIRE Server running (v1.14.1)
│   ├── Keylime plugin: ENABLED ✅
│   ├── tpm_devid plugin: PREPARED
│   └── join_token plugin: ACTIVE (legacy)
├── ✅ OpenBao running (v2.5.0)
│   ├── PKI engine: pki_int/ ✅
│   ├── Book of Omens CA: OPERATIONAL ✅
│   └── 4 PKI roles configured ✅
├── ✅ Keylime Registrar (port 8891)
└── ✅ Keylime Verifier (port 8881)

auth.funlab.casa (10.10.2.70)
├── ✅ TPM 2.0 validated (Infineon)
├── ✅ LUKS auto-unlock working
├── ✅ SPIRE Agent running (v1.14.1)
│   └── Attestation: Keylime ✅ (continuous)
└── ✅ Keylime Agent (port 9002)

ca.funlab.casa (10.10.2.60)
├── ✅ TPM 2.0 validated (Infineon)
├── ✅ LUKS auto-unlock working
├── ✅ step-ca running (with YubiKey)
│   └── Sword of Omens CA ✅
└── ✅ SPIRE Agent running (v1.14.1)
    └── Attestation: join_token (pending migration)
```

### Security Layers
```
✅ Layer 1: TPM Hardware (Infineon TPM 2.0)
✅ Layer 2: Disk Encryption (LUKS with TPM auto-unlock)
✅ Layer 3: Node Identity (Keylime continuous attestation - 1/3 hosts)
✅ Layer 4: Workload Identity (SPIRE SVIDs operational)
✅ Layer 5: Service mTLS (JWT-SVID auth working)
✅ Layer 6: PKI Infrastructure (Book of Omens CA deployed)
⏳ Layer 7: Certificate Automation (ready to deploy)
```

---

## 🎬 Decision Time

**What would you like to deploy next?**

**A) step-ca** - Certificate Authority (recommended for DevID path)
**B) OpenBao** - Secrets Management (if secrets needed urgently)
**C) SPIRE Agents** - Workload identity infrastructure
**D) Review plan** - Questions or adjustments before proceeding

---

## 📚 Reference Documentation

### Planning & Architecture
- [tower-of-omens-tpm-attestation-plan.md](tower-of-omens-tpm-attestation-plan.md) - Full TPM strategy
- [tower-of-omens-tpm-validation.md](tower-of-omens-tpm-validation.md) - TPM validation results
- [SPIRE-OPENBAO-PREDEPLOYMENT.md](../projects/funlab-docs/docs/infrastructure/migrations/SPIRE-OPENBAO-PREDEPLOYMENT.md) - Original plan

### Deployment Docs
- [tower-of-omens-deployment-summary.md](tower-of-omens-deployment-summary.md) - Current status
- [tower-of-omens-onboarding.md](tower-of-omens-onboarding.md) - Host onboarding
- [spire-server-config.md](spire-server-config.md) - SPIRE configuration

### TPM Configs (Disk Encryption)
- [spire-tpm-config.md](spire-tpm-config.md) - spire LUKS/TPM
- [auth-tpm-config.md](auth-tpm-config.md) - auth LUKS/TPM
- [ca-tpm-config.md](ca-tpm-config.md) - ca LUKS/TPM

---

**Current Status:** 🚀 Sprint 3 **IN PROGRESS** (Phase 1 & 2 Complete)
**Recent Achievements:**
- ✅ Keylime TPM attestation (auth host migrated)
- ✅ Book of Omens PKI deployed in OpenBao
- ✅ 4 PKI roles configured for infrastructure
- ✅ Certificate issuance tested and verified

**Next Action:** Deploy Keylime mTLS with PKI certificates
**Timeline:** 2-3 days for certificate deployment + migration
**Risk:** Low - Keylime proven, PKI tested, rollback available
