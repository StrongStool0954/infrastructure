# OpenBao Auto-Unseal Architecture Decision

**Date:** 2026-02-11
**Status:** ✅ APPROVED FOR IMPLEMENTATION
**Decision:** TPM + Keylime attestation-based auto-unseal

---

## Executive Summary

**Selected Approach:** TPM-encrypted keys + Keylime attestation-gated delivery

**Rationale:**
- ✅ Fully automated recovery after reboot
- ✅ Hardware-backed security (TPM)
- ✅ Attestation-gated access (Keylime measured boot)
- ✅ No external dependencies
- ✅ Fast, reliable, proven technology stack

**Future Enhancement:** Add Yubikey for admin operations and emergency recovery (Phase 2)

---

## Problem Statement

From reboot survival test (2026-02-11):
```
✅ All services auto-started within 1 minute
✅ Keylime infrastructure fully operational
❌ OpenBao started but SEALED
   - Blocks certificate renewal
   - Requires manual intervention
   - Not acceptable for production automation
```

**Goal:** Auto-unseal OpenBao after successful system attestation, enabling fully automated recovery.

---

## Options Evaluated

### Option 1: Cloud KMS (AWS/Azure/GCP)
**Verdict:** ❌ Rejected
**Reason:** Adds external cloud dependency, not suitable for on-premise infrastructure

### Option 2: 1Password Vault + OP CLI
**Verdict:** ⚠️ Viable but Complex
**Pros:**
- Centralized secret management
- Audit trail
- Easy rotation

**Cons:**
- Network dependency at boot
- Adds external service dependency
- Slower boot/unseal process
- Service account token management

**Decision:** Keep as backup/source-of-truth, but not primary mechanism

### Option 3: Yubikey Hardware Token
**Verdict:** ⚠️ Good for Admin, Not for Automation
**Pros:**
- Physical security token
- Hardware-backed crypto
- Cannot extract keys

**Cons:**
- Requires physical presence (contradicts automation)
- Single point of failure if lost/damaged
- Prevents remote recovery
- No better than TPM for always-connected server

**Decision:** Phase 2 enhancement for admin operations

### Option 4: TPM + Keylime Attestation ✅ **SELECTED**
**Verdict:** ✅ **APPROVED**

**Architecture:**
```
Boot → Keylime Services Start → Attestation Check
  ↓
  PASS? → Decrypt keys from TPM → Deliver via Keylime payload
  ↓
  Agent receives encrypted payload → Auto-unseal OpenBao
  ↓
  OpenBao ready for PKI operations

  FAIL? → Keys NOT delivered → OpenBao remains sealed → Alert
```

**Pros:**
- ✅ Fully automated (zero-touch on normal boot)
- ✅ Hardware-backed security (TPM 2.0)
- ✅ Attestation-gated (measured boot via Keylime)
- ✅ No external dependencies
- ✅ Fast unseal (<2 minutes after boot)
- ✅ Uses existing infrastructure (Keylime already deployed)
- ✅ Fail-secure (stays sealed if attestation fails)
- ✅ Works remotely (no physical access required)

**Cons:**
- ⚠️ Keys on same system as OpenBao (mitigated by TPM + attestation)
- ⚠️ TPM compromise = key exposure (extremely difficult, requires physical access)

---

## Selected Architecture: TPM + Keylime

### Security Layers

**Layer 1: Hardware (TPM 2.0)**
- Unseal keys encrypted by TPM
- Keys sealed to PCR values (measured boot state)
- Cannot decrypt unless system in expected boot state
- Hardware-backed encryption, keys cannot be extracted

**Layer 2: Attestation (Keylime)**
- Runtime integrity verification before key delivery
- Validates: Boot chain (PCRs), File integrity (IMA), Runtime state
- Only delivers keys if system passes all checks
- Continuous monitoring with revocation capability

**Layer 3: Payload Encryption (Keylime)**
- Keys encrypted in transit using RSA 2048
- Agent's private key required to decrypt
- Keys delivered to tmpfs only (never disk)
- Auto-shredded after use

**Layer 4: Access Control**
- Keys stored in /run/keylime/ (tmpfs, root-only)
- Strict file permissions (400, root:root)
- SELinux/AppArmor policies enforced
- All access logged

### Key Distribution Strategy

**OpenBao Shamir Shares: 5 total, threshold 3**

**Phase 1: TPM + Keylime (Immediate)**
```
Share 1 → Encrypted by TPM → Keylime automated unseal
Share 2 → Encrypted by TPM → Keylime automated unseal
Share 3 → Encrypted by TPM → Keylime automated unseal
Share 4 → Stored in 1Password → Emergency admin recovery
Share 5 → Stored in 1Password → Emergency admin recovery
```

**Phase 2: Enhanced with Yubikey (Future)**
```
Share 1 → Encrypted by TPM → Keylime automated unseal
Share 2 → Encrypted by TPM → Keylime automated unseal
Share 3 → Encrypted by TPM → Keylime automated unseal
Share 4 → Stored on Yubikey #1 → Admin emergency unseal
Share 5 → Stored on Yubikey #2 → Backup admin emergency unseal
```

---

## Implementation Plan

### Phase 1: TPM + Keylime Auto-Unseal (This Phase)

**Prerequisites:**
1. ✅ TPM 2.0 available on spire.funlab.casa (verified)
2. ✅ systemd with TPM support (verified)
3. ✅ Keylime infrastructure operational (verified)
4. 🔲 Locate OpenBao unseal keys (5 Shamir shares)

**Tasks:**

**Day 1: Preparation**
- [ ] Locate/verify OpenBao unseal keys (5 shares)
- [ ] Test manual unseal procedure
- [ ] Verify TPM functionality (systemd-creds)
- [ ] Create encrypted credential files

**Day 2: Integration**
- [ ] Create unseal script: `/usr/local/bin/openbao-autounseal.sh`
- [ ] Configure Keylime verifier for payload delivery
- [ ] Create systemd service: `openbao-autounseal.service`
- [ ] Package unseal keys as Keylime payload

**Day 3: Testing**
- [ ] Test manual unseal with script
- [ ] Test Keylime payload delivery
- [ ] Test automatic unseal after attestation
- [ ] Test failure scenarios (attestation failure)
- [ ] Perform full reboot survival test

**Day 4: Production**
- [ ] Enable auto-unseal in production
- [ ] Update monitoring scripts
- [ ] Document runbook procedures
- [ ] Update reboot survival checklist
- [ ] Commit all changes to git

---

### Phase 2: Yubikey Enhancement (Future)

**When:** After Phase 1 proven stable (30+ days)

**Hardware:**
- Purchase 2x Yubikey 5 NFC (~$100 total)
- Label: "OpenBao Admin #1" and "OpenBao Admin #2"

**Tasks:**
- [ ] Install Yubikey tools (yubikey-manager)
- [ ] Configure PIV/Challenge-Response slots
- [ ] Store shares 4+5 on Yubikeys
- [ ] Create admin unseal scripts
- [ ] Document Yubikey procedures
- [ ] Test emergency recovery path
- [ ] Update runbooks

**Use Cases:**
1. Emergency manual unseal (if automation fails)
2. Seal rotation operations (requires physical admin)
3. Root token access (high-security operations)
4. Compliance/audit requirements

---

## Security Analysis

### Threat Model

| Threat | Mitigation | Residual Risk |
|--------|------------|---------------|
| **Compromised boot chain** | TPM PCR validation, measured boot | Low - Would need physical access + sophisticated attack |
| **Compromised runtime** | Keylime IMA verification | Low - Attestation would fail, keys not delivered |
| **TPM compromise** | Requires physical hardware attack | Very Low - Nation-state level difficulty |
| **Stolen server** | Keys sealed to specific TPM | Low - Cannot decrypt without original TPM |
| **Insider threat** | Root access = key access | Medium - Phase 2 Yubikey mitigates |
| **Network attack** | No network dependency | None - Fully local operation |
| **Failed attestation** | OpenBao stays sealed, alert triggered | None - Fail-secure design |

### Compliance Considerations

**Meets requirements for:**
- ✅ Hardware-backed key storage
- ✅ Automated disaster recovery
- ✅ Audit logging (Keylime events)
- ✅ Separation of duties (Phase 2 with Yubikey)
- ✅ Measured boot / attestation

**May require for higher compliance:**
- Phase 2: Yubikey for two-factor admin access
- External audit logging (forward Keylime logs)
- Key rotation procedures (automated quarterly)

---

## Operational Procedures

### Normal Boot (Automated)
```
1. System boots
2. Keylime services start (registrar, verifier, agent)
3. Agent performs attestation (~30 seconds)
4. Verifier validates and delivers encrypted unseal payload
5. Agent decrypts and runs auto-unseal script
6. OpenBao unsealed (~2 minutes total)
7. Certificate renewal can proceed
```

**Expected timeline:** OpenBao unsealed within **2-3 minutes** of boot

### Failed Attestation (Fail-Secure)
```
1. System boots
2. Keylime attestation FAILS (bad PCR, IMA violation, etc.)
3. Verifier does NOT deliver unseal keys
4. OpenBao remains SEALED
5. Alert triggered: "Attestation failed - OpenBao sealed"
6. Admin investigation required
```

**Recovery:** Fix attestation issue → re-attest → automatic unseal

### Emergency Manual Unseal (Admin)
```
1. Access 1Password vault: "OpenBao Unseal Keys Backup"
2. Retrieve shares 4 + 5 (+ any 1 of shares 1-3)
3. SSH to spire.funlab.casa
4. Execute: bao operator unseal <key4>
5. Execute: bao operator unseal <key5>
6. Execute: bao operator unseal <key1>  # or key2 or key3
7. OpenBao unsealed
```

**When needed:** Automation failure, attestation cannot be fixed immediately

---

## Monitoring & Alerting

### Key Metrics

**Boot-time monitoring:**
- Time from boot to OpenBao unsealed (target: <3 min)
- Attestation success/failure rate
- Auto-unseal success/failure rate

**Runtime monitoring:**
- OpenBao seal status every 5 minutes
- Alert if sealed >5 minutes after boot
- Keylime attestation status

**Audit events:**
- All unseal attempts (auto and manual)
- Attestation failures
- Key delivery events
- Payload decryption events

### Alert Thresholds

| Condition | Severity | Action |
|-----------|----------|--------|
| OpenBao sealed >5 min after boot | WARNING | Check auto-unseal logs |
| Attestation failed | CRITICAL | Investigate system integrity |
| Auto-unseal failed (attestation passed) | ERROR | Check script logs, may need manual unseal |
| OpenBao re-sealed during runtime | CRITICAL | Security incident - investigate immediately |

### Log Locations
```
/var/log/keylime/agent.log        - Attestation and payload events
/var/log/keylime/verifier.log     - Key delivery events
/var/log/openbao-autounseal.log   - Unseal script execution
/var/log/openbao/openbao.log      - OpenBao seal/unseal events
```

---

## Backup & Recovery

### Key Backup Strategy

**Primary (Automated):**
- Shares 1-3: TPM-encrypted on spire.funlab.casa
- Used for automatic unseal

**Backup (Manual):**
- Shares 4-5: Stored in 1Password vault
- Used for emergency manual unseal
- Admin access required

**Phase 2 (Enhanced):**
- Shares 4-5: Moved to Yubikey hardware tokens
- Physical security for admin operations

### Disaster Recovery Scenarios

**Scenario 1: TPM Failure**
- Cannot decrypt automated keys (shares 1-3)
- **Recovery:** Manual unseal using shares 4-5 from 1Password + any 1 automated share
- Re-encrypt shares with new TPM

**Scenario 2: Server Hardware Failure**
- Complete hardware replacement needed
- **Recovery:**
  - Restore OpenBao data from backup
  - Manual unseal using any 3 of 5 shares from 1Password
  - Re-configure TPM encryption with new hardware
  - Re-establish Keylime attestation baseline

**Scenario 3: Attestation Baseline Drift**
- System updates changed PCR values
- Attestation fails, auto-unseal blocked
- **Recovery:**
  - Manual unseal using 1Password keys
  - Update Keylime attestation policy with new PCR values
  - Re-establish automated unseal

**Scenario 4: All Keys Lost (Catastrophic)**
- All 5 Shamir shares lost/compromised
- **Recovery:**
  - OpenBao rekey operation required
  - Generate new 5 shares with 3 threshold
  - Re-distribute and re-encrypt keys
  - Update all automation

---

## Success Criteria

### Functional Requirements
- ✅ OpenBao auto-unseals after successful attestation
- ✅ Unseal completes within 3 minutes of boot
- ✅ Zero manual intervention required on normal boot
- ✅ Certificate renewal proceeds automatically
- ✅ Failed attestation keeps OpenBao sealed (fail-secure)

### Security Requirements
- ✅ Keys encrypted by hardware (TPM)
- ✅ Keys only delivered to attested systems
- ✅ Keys never persisted to disk (tmpfs only)
- ✅ All events logged and auditable
- ✅ Manual emergency recovery path available

### Operational Requirements
- ✅ Runbook documented and tested
- ✅ Monitoring and alerting configured
- ✅ Failure modes identified and tested
- ✅ Recovery procedures validated
- ✅ Team trained on procedures

---

## Rollback Plan

If auto-unseal proves problematic:

**Step 1: Disable Automation**
```bash
sudo systemctl disable openbao-autounseal.service
sudo systemctl stop openbao-autounseal.service
```

**Step 2: Manual Unseal**
```bash
# Use 1Password backup keys (shares 4+5 + any other)
export BAO_ADDR=https://openbao.funlab.casa
export BAO_SKIP_VERIFY=true

bao operator unseal <share-4>
bao operator unseal <share-5>
bao operator unseal <share-1>
```

**Step 3: Remove Keylime Payload**
```bash
# On verifier
sudo rm /var/lib/keylime/payload/unseal-keys.json
```

**Step 4: Document Issues**
- Record what went wrong
- Determine if fixable or architectural issue
- Plan remediation if viable

---

## Cost-Benefit Analysis

### Implementation Costs
- **Time:** ~2-3 days engineering effort
- **Risk:** Low (can rollback to manual)
- **Ongoing:** None (uses existing infrastructure)

### Benefits
- **Automation:** Eliminates manual unseal after every reboot
- **Availability:** Faster recovery (3 min vs manual wait)
- **Security:** Attestation-gated, fail-secure design
- **Compliance:** Meets automated disaster recovery requirements
- **Operational:** Reduces on-call burden

### ROI
- **Immediate:** Enables 24-hour certificate automation
- **Ongoing:** ~30 min saved per reboot (no manual intervention)
- **Security:** Defense in depth with measured boot attestation

---

## Future Enhancements (Roadmap)

### Phase 2: Yubikey Integration (Q2 2026)
- Add physical security tokens for admin operations
- Implement two-factor for sensitive operations
- Enhanced compliance posture

### Phase 3: Key Rotation Automation (Q3 2026)
- Automated quarterly seal rotation
- Scripted rekey operations
- Audit trail integration

### Phase 4: Multi-Node HA (Future)
- Extend to additional OpenBao nodes
- Automated unseal for HA cluster
- Distributed key management

---

## References

- **Keylime Documentation:** https://keylime.dev
- **OpenBao Seal Concepts:** https://openbao.org/docs/concepts/seal/
- **systemd-creds TPM:** https://www.freedesktop.org/software/systemd/man/systemd-creds.html
- **Reboot Survival Test:** 2026-02-11 (documented in this session)
- **TPM 2.0 Specification:** https://trustedcomputinggroup.org/

---

## Approval

**Decision Made By:** Infrastructure Team
**Date:** 2026-02-11
**Approved For:** Phase 1 Implementation (TPM + Keylime)
**Status:** ✅ Proceed with Implementation

**Next Steps:**
1. Locate OpenBao unseal keys
2. Begin Day 1 implementation tasks
3. Complete Phase 1 within 4 days
4. Evaluate Phase 2 (Yubikey) after 30 days

---

**Document Status:** APPROVED
**Implementation Status:** READY TO START
**Target Completion:** 2026-02-15
