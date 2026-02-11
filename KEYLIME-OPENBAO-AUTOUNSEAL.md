# Keylime-Based OpenBao Auto-Unseal Design

**Date:** 2026-02-11
**Status:** 📋 DESIGN PHASE
**Goal:** Auto-unseal OpenBao after successful attestation

---

## Architecture Overview

```
Boot Sequence:
1. System boots
2. Keylime services start (registrar, verifier, agent)
3. Agent performs measured boot attestation
4. If attestation PASSES → Deliver unseal keys to agent
5. Agent auto-unseals OpenBao
6. OpenBao ready for PKI operations

If attestation FAILS:
- Unseal keys NOT delivered
- OpenBao remains sealed
- Alert triggered
```

---

## Why Keylime for Auto-Unseal?

### Security Benefits
✅ **Attestation-based trust** - Only unseal if system integrity verified
✅ **Measured boot** - TPM validates boot chain before unsealing
✅ **Zero-touch on good state** - Automatic when system is trusted
✅ **Fail-secure** - Stays sealed if attestation fails
✅ **Revocation aware** - Can re-seal if system becomes compromised

### Operational Benefits
✅ **No cloud dependencies** - Pure on-premise solution
✅ **Uses existing infrastructure** - Keylime already deployed
✅ **Logged and auditable** - All attestation events tracked
✅ **Integrated monitoring** - Same monitoring stack

### Proven Independent Operation
From reboot test (2026-02-11):
```
✅ Keylime registrar - Started 08:30:54 (PID 1052)
✅ Keylime verifier - Started 08:30:54 (PID 1053)
✅ Keylime agent - Started 08:30:54 (PID 1050)
✅ OpenBao - Started 08:30:54 but SEALED
```

**No chicken-and-egg problem** - Keylime operates independently of OpenBao.

---

## Current State

### OpenBao Configuration
```
Seal Type:       shamir
Total Shares:    5
Threshold:       3 (need 3 keys to unseal)
Current Status:  SEALED
Storage:         raft (integrated)
```

### Keylime Configuration
```
Payload encryption: Configured (RSA 2048)
Secure mount:       /var/lib/keylime/secure/ (created on payload delivery)
Verifier:           Running on spire.funlab.casa
Agent:              Running on spire.funlab.casa (localhost)
```

---

## Implementation Options

### Option 1: Keylime Payload Delivery (RECOMMENDED)

**How it works:**
1. Store 3 unseal keys encrypted in Keylime verifier database
2. Configure payload script to deliver keys after successful attestation
3. Agent receives keys in `/var/lib/keylime/secure/payload/unseal-keys.json`
4. Post-attestation script unseals OpenBao
5. Keys remain in tmpfs mount (not persisted to disk)

**Advantages:**
- Keys only delivered to attested systems
- Keys stored in memory only (tmpfs)
- Fully automated on successful attestation
- Leverages Keylime's secure payload delivery

**Configuration:**
```ini
# On Verifier (/etc/keylime/verifier.conf)
payload_script = /usr/local/bin/openbao-unseal.sh

# On Agent (/etc/keylime/agent.conf)
enable_revocation_notifications = true
```

**Unseal script (`/usr/local/bin/openbao-unseal.sh`):**
```bash
#!/bin/bash
# Triggered after successful attestation and payload delivery

KEYS_FILE="/var/lib/keylime/secure/payload/unseal-keys.json"
export BAO_ADDR=https://localhost:8200
export BAO_SKIP_VERIFY=true

if [ -f "$KEYS_FILE" ]; then
    # Read 3 unseal keys (threshold)
    KEY1=$(jq -r '.key1' "$KEYS_FILE")
    KEY2=$(jq -r '.key2' "$KEYS_FILE")
    KEY3=$(jq -r '.key3' "$KEYS_FILE")

    # Unseal OpenBao
    bao operator unseal "$KEY1"
    bao operator unseal "$KEY2"
    bao operator unseal "$KEY3"

    logger "OpenBao auto-unsealed via Keylime attestation"

    # Securely delete keys from memory
    shred -u "$KEYS_FILE"
fi
```

---

### Option 2: TPM-Sealed Keys + Attestation Trigger

**How it works:**
1. Store unseal keys sealed by TPM PCRs
2. Keylime attestation validates PCR state
3. On successful attestation, trigger script to unseal keys from TPM
4. Use TPM-unsealed keys to unseal OpenBao

**Advantages:**
- Keys never leave the host
- TPM hardware protection
- PCR-based binding ensures measured boot integrity

**Challenges:**
- More complex TPM integration
- Keys must be re-sealed if PCRs change (system updates)

---

### Option 3: Hybrid - Local Encrypted Keys + Attestation Gate

**How it works:**
1. Store unseal keys locally, encrypted with master key
2. Master key stored in Keylime verifier
3. On successful attestation, deliver master key as payload
4. Agent decrypts unseal keys and unseals OpenBao

**Advantages:**
- Balances local storage with attestation gating
- Keys can't be accessed without attestation
- Simpler than TPM integration

---

## Recommended Approach: Option 1 (Payload Delivery)

**Rationale:**
- ✅ Simplest implementation
- ✅ Proven Keylime feature (payload delivery)
- ✅ Keys in memory only (tmpfs)
- ✅ Fully automated
- ✅ Can be implemented immediately

---

## Implementation Plan

### Phase 1: Preparation (Day 1)
1. Locate/verify OpenBao unseal keys (5 shares)
2. Select 3 keys for automated unsealing
3. Test manual unsealing procedure
4. Create encrypted payload with 3 keys

### Phase 2: Keylime Integration (Day 2)
1. Create unseal script (`/usr/local/bin/openbao-unseal.sh`)
2. Configure Keylime verifier to use payload script
3. Package unseal keys as Keylime payload
4. Test payload delivery to agent

### Phase 3: Testing (Day 3)
1. Seal OpenBao manually
2. Trigger Keylime re-attestation
3. Verify automatic unsealing
4. Test failure scenarios (attestation failure)
5. Test reboot with auto-unseal

### Phase 4: Production (Day 4)
1. Enable auto-unseal in production
2. Document runbook procedures
3. Update monitoring to track unseal events
4. Test full reboot survival again

---

## Security Considerations

### Key Storage
- **Current:** Unseal keys stored on verifier (need to locate)
- **Delivery:** Encrypted payload via Keylime's RSA 2048 encryption
- **Runtime:** Keys exist in tmpfs only, shredded after use
- **Backup:** Keep 2 unused shares offline for emergency recovery

### Attestation Requirements
- **Measured boot:** TPM PCRs must match expected values
- **IMA:** Integrity Measurement Architecture validates files
- **Runtime:** Agent must be in good state (no revocations)

### Failure Modes
- **Attestation fails:** OpenBao remains sealed, alert triggered
- **Payload delivery fails:** OpenBao remains sealed, manual intervention
- **Unseal script fails:** Logged, can retry manually
- **Keys compromised:** Rotate OpenBao seal (rekey operation)

---

## Monitoring Integration

### Log Events
```bash
# Success
"OpenBao auto-unsealed via Keylime attestation"

# Failure
"Keylime attestation failed - OpenBao remains sealed"
"Unseal script failed - check /var/log/keylime/agent.log"
```

### Alerts
- OpenBao sealed >5 minutes after boot → WARNING
- Attestation failed → CRITICAL
- Auto-unseal failed → ERROR

### Status Check
```bash
# Add to /usr/local/bin/monitor-nginx.sh
check_openbao_seal_status() {
    local sealed=$(curl -k -s https://localhost:8200/v1/sys/seal-status | jq -r '.sealed')
    local uptime_min=$(awk '{print int($1/60)}' /proc/uptime)

    if [ "$sealed" = "true" ] && [ $uptime_min -gt 5 ]; then
        log "ERROR: OpenBao still sealed $uptime_min minutes after boot"
        return 1
    fi
}
```

---

## Rollback Plan

If auto-unseal proves problematic:
1. Remove payload script from verifier config
2. Delete unseal keys from agent secure mount
3. Return to manual unsealing procedure
4. Document issues encountered

**Manual unseal procedure:**
```bash
export BAO_ADDR=https://openbao.funlab.casa
export BAO_SKIP_VERIFY=true

bao operator unseal <key1>
bao operator unseal <key2>
bao operator unseal <key3>
```

---

## Success Criteria

### Functional
- ✅ System boots and Keylime attests successfully
- ✅ Unseal keys delivered to agent securely
- ✅ OpenBao auto-unseals within 2 minutes of boot
- ✅ Certificate renewal works post-unseal

### Security
- ✅ Keys only delivered to attested systems
- ✅ Attestation failure prevents unsealing
- ✅ Keys not persisted to disk
- ✅ All events logged and monitored

### Operational
- ✅ Zero manual intervention on normal reboot
- ✅ Clear failure modes and alerts
- ✅ Documented recovery procedures
- ✅ Rollback tested and verified

---

## Next Steps

1. **Locate unseal keys** - Find where the 5 Shamir shares are stored
2. **Create payload** - Package 3 keys as encrypted Keylime payload
3. **Write unseal script** - Implement `/usr/local/bin/openbao-unseal.sh`
4. **Test integration** - Verify payload delivery and unsealing
5. **Enable in production** - Add to systemd startup sequence

---

## Questions to Resolve

1. **Where are the OpenBao unseal keys currently stored?**
   - Need to locate the 5 Shamir shares
   - Select 3 for automated unsealing
   - Keep 2 offline for emergency recovery

2. **Should we implement revocation-triggered re-sealing?**
   - If agent fails attestation, automatically re-seal OpenBao?
   - Adds security but may cause operational disruption

3. **What's the acceptable unseal timeout?**
   - How long after boot is it acceptable for OpenBao to be sealed?
   - Recommendation: 2-5 minutes

---

## Documentation References

- **Keylime Payload Docs:** https://keylime.dev
- **OpenBao Seal Docs:** https://openbao.org/docs/concepts/seal/
- **Reboot Test Results:** `REBOOT-SURVIVAL-TEST.md` (to be created)

---

**Status:** Awaiting unseal key location to proceed with implementation
**Priority:** High - Enables fully automated recovery
**Risk:** Low - Can always rollback to manual unsealing
