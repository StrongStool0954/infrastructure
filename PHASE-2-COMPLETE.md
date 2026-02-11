# ✅ Phase 2 Complete: Auto-Renewal Configured

**Date:** 2026-02-10 21:10 EST
**Status:** SUCCESS - Auto-renewal operational for spire
**Duration:** ~35 minutes

---

## What Was Accomplished

### 1. Auto-Renewal Scripts Deployed
- ✅ Created renewal script: `/usr/local/bin/renew-keylime-certs.sh`
- ✅ Created systemd service: `/etc/systemd/system/renew-keylime-certs.service`
- ✅ Created systemd timer: `/etc/systemd/system/renew-keylime-certs.timer`
- ✅ Deployed to spire.funlab.casa
- ✅ Deployed to auth.funlab.casa

### 2. OpenBao Token Configuration
- ✅ Stored token securely: `/root/.openbao-token` (mode 600)
- ✅ Updated renewal script to read token automatically
- ✅ Verified token authentication works

### 3. Renewal Testing
- ✅ Manual renewal tested and working on spire
- ✅ Verifier and Registrar certificates renewed successfully
- ✅ Services gracefully reloaded with pkill -HUP
- ✅ No service interruption during renewal

### 4. Systemd Timer Configuration
- ✅ Timer runs daily at 2 AM with 1-hour random delay
- ✅ Timer persists across reboots (Persistent=true)
- ✅ Timer enabled and active on spire
- ✅ Next run scheduled: Wed 2026-02-11 00:07:13 EST

---

## Configuration Details

### Spire Auto-Renewal
**Status:** ✅ Fully Operational

**Timer Schedule:**
- Daily at 2 AM (OnCalendar=daily + OnCalendar=*-*-* 02:00:00)
- Random delay: 0-60 minutes (RandomizedDelaySec=1h)
- Next run: Wed 2026-02-11 00:07:13 EST

**Certificates Renewed:**
- Verifier certificate (verifier.crt/key)
- Registrar certificate (registrar.crt/key)
- CA certificate (ca.crt)

**Service Reload Method:** `pkill -HUP` (graceful, no interruption)

### Auth Renewal
**Status:** ⚠️  Manual Renewal Required

**Issue:**
- `bao` CLI not installed on auth host
- SSH keys not configured between spire↔auth for automated distribution
- Centralized renewal approach requires cross-host SSH

**Current Solution:**
- Timer disabled on auth
- Manual renewal when needed (24-hour certificates)
- Renewal command available on spire

**Manual Renewal Procedure for auth:**
```bash
# On spire.funlab.casa
sudo bash -c '
export BAO_TOKEN=$(cat /root/.openbao-token)
export BAO_ADDR=https://127.0.0.1:8200
export BAO_SKIP_VERIFY=true

bao write -format=json pki_int/issue/keylime-services \
    common_name="agent.keylime.funlab.casa" \
    alt_names="localhost" \
    ip_sans="10.10.2.70,127.0.0.1" \
    ttl="24h" > /tmp/auth-cert.json

jq -r ".data.certificate" /tmp/auth-cert.json > /tmp/auth-agent.crt
jq -r ".data.private_key" /tmp/auth-cert.json > /tmp/auth-agent.key
jq -r ".data.issuing_ca" /tmp/auth-cert.json > /tmp/auth-ca.crt
'

# Copy to local machine
scp spire.funlab.casa:/tmp/auth-agent.{crt,key} spire.funlab.casa:/tmp/auth-ca.crt /tmp/

# Copy to auth
scp /tmp/auth-agent.crt /tmp/auth-agent.key /tmp/auth-ca.crt auth.funlab.casa:/tmp/

# Install on auth
ssh auth.funlab.casa "sudo mv /tmp/auth-agent.crt /etc/keylime/certs/agent.crt && \
    sudo mv /tmp/auth-agent.key /etc/keylime/certs/agent.key && \
    sudo mv /tmp/auth-ca.crt /etc/keylime/certs/ca.crt && \
    sudo chmod 644 /etc/keylime/certs/agent.crt /etc/keylime/certs/ca.crt && \
    sudo chmod 600 /etc/keylime/certs/agent.key && \
    sudo chown keylime:tss /etc/keylime/certs/* && \
    sudo pkill -HUP -f keylime_agent"
```

---

## Files Created

### On spire.funlab.casa:
- `/usr/local/bin/renew-keylime-certs.sh` - Local renewal script
- `/usr/local/bin/renew-all-keylime-certs.sh` - Centralized renewal (needs SSH keys)
- `/etc/systemd/system/renew-keylime-certs.service` - Systemd service
- `/etc/systemd/system/renew-keylime-certs.timer` - Systemd timer
- `/root/.openbao-token` - Secure token storage (mode 600)

### On auth.funlab.casa:
- `/usr/local/bin/renew-keylime-certs.sh` - Renewal script (needs bao CLI)
- `/etc/systemd/system/renew-keylime-certs.service` - Systemd service
- `/etc/systemd/system/renew-keylime-certs.timer` - Systemd timer (not used)
- `/root/.openbao-token` - Secure token storage (mode 600)

---

## Verification

### Timer Status
```bash
# On spire
sudo systemctl status renew-keylime-certs.timer
sudo systemctl list-timers renew-keylime-certs.timer
```

Output shows:
- Timer: Active (waiting)
- Next trigger: Wed 2026-02-11 00:07:13 EST
- Service: renew-keylime-certs.service
- Status: Enabled

### Manual Renewal Test
```bash
# On spire
sudo /usr/local/bin/renew-keylime-certs.sh
```

Results:
- ✅ Verifier certificate renewed
- ✅ Registrar certificate renewed
- ✅ Services reloaded without interruption
- ✅ New 24-hour validity period confirmed
- ✅ No errors or warnings

### Certificate Validity Check
```bash
sudo openssl x509 -in /etc/keylime/certs/verifier.crt -noout -dates
```

Shows:
- Issued: 2026-02-10 21:09:42
- Expires: 2026-02-11 21:09:42 (24 hours)

---

## Issues Resolved

### Issue 1: 1Password CLI Not Available
**Problem:** Script tried to use `op` command to read token
**Solution:** Created `/root/.openbao-token` file with token, updated script to read from file

### Issue 2: Line Ending Issues (CRLF)
**Problem:** Scripts had Windows line endings causing execution failures
**Solution:** Applied `sed -i 's/\r$//'` to convert to Unix line endings

### Issue 3: Auth Host Lacks bao CLI
**Problem:** Auth host can't issue certificates directly
**Solution:** Documented manual renewal procedure, prepared centralized approach for future

### Issue 4: SSH Keys Between Hosts
**Problem:** Centralized renewal requires spire↔auth SSH
**Solution:** Deferred cross-host SSH setup, using manual auth renewal for now

---

## Success Criteria

- [x] **Auto-renewal configured and tested**
- [x] **Systemd timer enabled and scheduled**
- [x] **Token authentication working**
- [x] **Manual renewal tested successfully**
- [x] **Services reload gracefully without interruption**
- [x] **Certificates renew with 24-hour validity**
- [x] **No errors in renewal process**
- [x] **Timer persists across reboots**

**Partial:**
- [~] Auth auto-renewal (manual procedure documented)

---

## Monitoring Auto-Renewal

### Check Timer Status
```bash
ssh spire.funlab.casa "sudo systemctl status renew-keylime-certs.timer"
```

### View Renewal Logs
```bash
ssh spire.funlab.casa "sudo journalctl -u renew-keylime-certs.service -n 50"
```

### Test Manual Renewal
```bash
ssh spire.funlab.casa "sudo systemctl start renew-keylime-certs.service"
```

### Verify Certificate Dates
```bash
ssh spire.funlab.casa "sudo openssl x509 -in /etc/keylime/certs/verifier.crt -noout -dates"
```

---

## Future Improvements

### For Full Automation of auth Renewal:

**Option 1: SSH Key Setup**
- Generate SSH keypair on spire
- Add spire's public key to auth's authorized_keys
- Enable centralized renewal script

**Option 2: Install bao CLI on auth**
- Install OpenBao CLI on auth.funlab.casa
- Configure to connect to remote OpenBao
- Use local renewal script

**Option 3: Keylime API-Based Renewal**
- Use Keylime Tenant API to request certificate
- Implement certificate rotation through Keylime protocol
- Most secure but more complex

**Recommendation:** Option 1 (SSH keys) for simplicity and security

---

## Next Steps

### Phase 3: Migrate ca Host to Keylime (Ready to Execute)
**Goal:** Move ca.funlab.casa from join_token to Keylime attestation
**Script Ready:** `/tmp/migrate-ca-to-keylime.sh`
**Prerequisites:**
- Issue Keylime certificate for ca host
- Install certificates on ca host
- Run migration script
**Estimated Time:** 30 minutes

### Phase 4: Migrate spire Host to Keylime (Ready to Execute)
**Goal:** Move spire.funlab.casa from join_token to Keylime attestation
**Similar process to ca migration**
**Estimated Time:** 30 minutes

---

## Rollback Procedure

If auto-renewal causes issues:

```bash
# Disable timer
sudo systemctl stop renew-keylime-certs.timer
sudo systemctl disable renew-keylime-certs.timer

# Remove service and timer
sudo rm /etc/systemd/system/renew-keylime-certs.{service,timer}
sudo systemctl daemon-reload

# Manual renewal still available
sudo /usr/local/bin/renew-keylime-certs.sh
```

---

## References

- [Phase 1 Complete](/home/bullwinkle/infrastructure/PHASE-1-COMPLETE.md)
- [Book of Omens PKI](/home/bullwinkle/infrastructure/book-of-omens-pki-deployment.md)
- [Keylime mTLS Deployment](/home/bullwinkle/infrastructure/keylime-mtls-deployment.md)

---

**Status:** 🟢 PHASE 2 COMPLETE - AUTO-RENEWAL OPERATIONAL (SPIRE)
**Next Phase:** Host Migration (Phase 3 & 4)
**Last Updated:** 2026-02-10 21:10 EST
**Certificate Expiry:** ~22 hours (auto-renewal at 00:07 EST)
