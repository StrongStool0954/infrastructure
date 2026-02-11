# OpenBao Auto-Unseal Reboot Test - TPM + Keylime Attestation

**Date:** 2026-02-11
**Host:** spire.funlab.casa
**Test Type:** Full system reboot with attestation-gated auto-unseal
**Objective:** Verify zero-touch OpenBao recovery after reboot

---

## Pre-Reboot State

**Time:** 2026-02-11 17:12:13 EST
**System Uptime:** 8 hours, 41 minutes

### Pre-Reboot Verification Results ✅

```
✅ Auto-Unseal Service: ENABLED and ACTIVE
✅ Auto-Unseal Script: Present (3356 bytes)
✅ TPM-Encrypted Keys: All 3 keys present (559 bytes each)
✅ Keylime Services: Agent, Verifier, Registrar all ACTIVE
✅ Attestation Status: PASS
✅ OpenBao Status: Active and UNSEALED
✅ Keylime Certificates: Complete chain (2 certificates)
```

### Service States Before Reboot

```bash
openbao.service              active (running)
openbao-autounseal.service   active (exited) - last run successful
keylime_agent.service        active (running)
keylime_verifier.service     active (running)
keylime_registrar.service    active (running)
nginx.service                active (running)
spire-server.service         active (running)
```

### Attestation Status Before Reboot

```
Agent UUID: d884d34059618008b785b7cc83a50f671f5f3ff4b4522214d999a1a69222fb37
Attestation Status: PASS
Attestation Count: 78+
Last Successful Attestation: Recent (2-second interval)
Operational State: Get Quote
```

### Configuration Files Verified

- ✅ `/usr/local/bin/openbao-autounseal.sh` (3356 bytes)
- ✅ `/etc/systemd/system/openbao-autounseal.service` (enabled)
- ✅ `/etc/openbao/unseal-keys/unseal-key-{1,2,3}.enc` (TPM-encrypted)
- ✅ `/etc/keylime/agent.conf` (configured for direct backend)
- ✅ `/etc/keylime/certs/ca-complete-chain.crt` (2 certs)

---

## Expected Reboot Timeline

```
T+0:00  - Reboot initiated
T+0:30  - GRUB menu
T+0:45  - Kernel loads
T+1:00  - All services start
          ├─ nginx
          ├─ keylime_registrar
          ├─ keylime_verifier
          ├─ keylime_agent
          ├─ openbao (SEALED)
          └─ spire-server
T+1:15  - Keylime agent registers
T+1:30  - First attestation quote sent
T+1:35  - Attestation verified: PASS
T+1:40  - openbao-autounseal.service triggered
          ├─ Waits for Keylime agent
          ├─ Checks attestation status
          ├─ Attestation = PASS → proceed
          ├─ Decrypt key 1 from TPM
          ├─ Decrypt key 2 from TPM
          ├─ Decrypt key 3 from TPM
          └─ OpenBao unsealed
T+2:00  - Full operations restored ✅
```

**Expected Total Recovery Time:** ~2 minutes (zero-touch)

---

## Reboot Test Execution

### Reboot Command

```bash
sudo reboot
```

**Initiated:** 2026-02-11 17:13:00 EST

### Post-Reboot Verification Commands

```bash
# 1. Check OpenBao seal status
curl -sk https://localhost:8200/v1/sys/seal-status | jq '.sealed'
# Expected: false

# 2. Check auto-unseal service status
sudo systemctl status openbao-autounseal.service
# Expected: active (exited) with exit code 0

# 3. Check auto-unseal logs
sudo cat /var/log/openbao-autounseal.log
# Expected: Shows attestation PASS and successful unseal

# 4. Check attestation status
sudo keylime_tenant -c status -u d884d34059618008b785b7cc83a50f671f5f3ff4b4522214d999a1a69222fb37 | grep attestation_status
# Expected: "PASS"

# 5. Check service logs
sudo journalctl -u openbao-autounseal.service --no-pager
# Expected: Shows full unseal process

# 6. Verify all services running
systemctl is-active openbao keylime_agent keylime_verifier nginx
# Expected: active for all
```

---

## Test Results

### Post-Reboot State

**Reconnect Time:** [TO BE FILLED]
**System Uptime:** [TO BE FILLED]

### Service Status After Reboot

```
[TO BE FILLED AFTER REBOOT]
```

### OpenBao Seal Status

```
[TO BE FILLED AFTER REBOOT]
```

### Auto-Unseal Log Output

```
[TO BE FILLED AFTER REBOOT]
```

### Attestation Status After Reboot

```
[TO BE FILLED AFTER REBOOT]
```

### Timeline Analysis

```
[TO BE FILLED AFTER REBOOT]
```

---

## Success Criteria

### Must Pass ✅
- [ ] System boots successfully
- [ ] All services start automatically
- [ ] Keylime agent registers with registrar
- [ ] Attestation status reaches PASS
- [ ] openbao-autounseal.service executes
- [ ] Script detects attestation = PASS
- [ ] TPM keys decrypt successfully
- [ ] OpenBao unseals automatically
- [ ] OpenBao seal status = false
- [ ] Total recovery time < 5 minutes
- [ ] Zero manual intervention required

### Performance Targets 🎯
- [ ] Boot time < 60 seconds
- [ ] First attestation < 90 seconds
- [ ] Auto-unseal completion < 120 seconds
- [ ] Full operations < 180 seconds

### Logging & Observability 📊
- [ ] Auto-unseal log created
- [ ] Systemd journal contains execution details
- [ ] Attestation timeline visible in logs
- [ ] No errors in service logs

---

## Troubleshooting During Test

### If OpenBao Remains Sealed

**Check 1: Service Status**
```bash
sudo systemctl status openbao-autounseal.service
```

**Check 2: Service Logs**
```bash
sudo journalctl -u openbao-autounseal.service -n 100 --no-pager
```

**Check 3: Auto-Unseal Log**
```bash
sudo cat /var/log/openbao-autounseal.log
```

**Check 4: Attestation Status**
```bash
sudo keylime_tenant -c status -u d884d34059618008b785b7cc83a50f671f5f3ff4b4522214d999a1a69222fb37
```

### If Attestation Fails

**Check Agent Status:**
```bash
sudo systemctl status keylime_agent
sudo journalctl -u keylime_agent -n 50
```

**Check Verifier Status:**
```bash
sudo systemctl status keylime_verifier
sudo journalctl -u keylime_verifier -n 50
```

**Re-register Agent:**
```bash
sudo keylime_tenant -c delete -u d884d34059618008b785b7cc83a50f671f5f3ff4b4522214d999a1a69222fb37
sudo keylime_tenant -c add -t 127.0.0.1 -u d884d34059618008b785b7cc83a50f671f5f3ff4b4522214d999a1a69222fb37
```

### If TPM Decryption Fails

**Test TPM Access:**
```bash
sudo systemd-creds decrypt /etc/openbao/unseal-keys/unseal-key-1.enc -
```

**Check TPM Status:**
```bash
sudo tpm2_pcrread sha256
```

### Emergency Manual Unseal

**If auto-unseal fails, manual unseal procedure:**
```bash
# Get keys 4 and 5 from 1Password (Funlab.Casa.Openbao vault)
export BAO_ADDR="https://localhost:8200"
bao operator unseal
# Enter key 4
bao operator unseal
# Enter key 5
```

---

## Additional Monitoring

### Concurrent Monitoring Commands

**Terminal 1: Auto-unseal logs (live)**
```bash
sudo tail -f /var/log/openbao-autounseal.log
```

**Terminal 2: Service status (live)**
```bash
watch -n 1 'systemctl status openbao-autounseal.service | head -20'
```

**Terminal 3: OpenBao seal status (live)**
```bash
watch -n 2 'curl -sk https://localhost:8200/v1/sys/seal-status | jq'
```

**Terminal 4: Attestation status (live)**
```bash
watch -n 5 'sudo keylime_tenant -c status -u d884d34059618008b785b7cc83a50f671f5f3ff4b4522214d999a1a69222fb37 2>&1 | grep attestation_status'
```

---

## Post-Test Analysis

### What Worked Well
[TO BE FILLED AFTER TEST]

### Issues Encountered
[TO BE FILLED AFTER TEST]

### Performance Metrics
[TO BE FILLED AFTER TEST]

### Improvements Needed
[TO BE FILLED AFTER TEST]

---

## Test Conclusion

**Test Status:** [PENDING]
**Date Completed:** [TO BE FILLED]
**Auto-Unseal Result:** [TO BE FILLED]
**Total Recovery Time:** [TO BE FILLED]
**Manual Intervention Required:** [TO BE FILLED]

**Next Steps:**
[TO BE FILLED AFTER TEST]

---

**Test Prepared By:** Claude Code Assistant
**Test Execution Date:** 2026-02-11
**Implementation Reference:** OPENBAO-AUTOUNSEAL-IMPLEMENTATION.md
