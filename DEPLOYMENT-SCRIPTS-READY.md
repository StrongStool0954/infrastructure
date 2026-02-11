# 🚀 Keylime mTLS & Migration - Deployment Scripts Ready

**Date:** 2026-02-10
**Status:** All scripts created, ready to execute
**Location:** `/tmp/` on local machine

---

## 📦 Scripts Created

All deployment scripts are ready in `/tmp/`:

| Script | Purpose | Run On | Duration |
|--------|---------|--------|----------|
| `restart-keylime-mtls.sh` | Restart services with mTLS | spire | 2 min |
| `renew-keylime-certs.sh` | Manual certificate renewal | all hosts | 1 min |
| `setup-cert-autorenewal.sh` | Configure daily auto-renewal | all hosts | 2 min |
| `migrate-ca-to-keylime.sh` | Migrate ca host to Keylime | ca | 5 min |
| `deployment-guide.md` | Complete deployment guide | - | - |

---

## 🎯 Quick Execution Plan

### Phase 1: Activate mTLS (10 minutes)

```bash
# 1. Copy restart script to spire
scp /tmp/restart-keylime-mtls.sh spire.funlab.casa:/tmp/

# 2. Restart Keylime services with mTLS
ssh spire.funlab.casa "sudo /tmp/restart-keylime-mtls.sh"

# 3. Restart agent on auth
ssh auth.funlab.casa "sudo systemctl restart keylime_agent"

# 4. Verify mTLS is working
ssh spire.funlab.casa "sudo tail -30 /var/log/keylime-verifier.log | grep -i tls"
ssh auth.funlab.casa "sudo journalctl -u keylime_agent -n 30 | grep -i tls"

# 5. Test attestation
ssh spire.funlab.casa "sudo keylime_tenant -c status --uuid d432fbb3-d2f1-4a97-9ef7-75bd81c00000"
```

**Success Indicators:**
- "TLS connection established" in logs
- "attestation_status: PASS"
- No certificate errors

---

### Phase 2: Setup Auto-Renewal (15 minutes)

```bash
# On spire host
scp /tmp/renew-keylime-certs.sh spire.funlab.casa:/tmp/
scp /tmp/setup-cert-autorenewal.sh spire.funlab.casa:/tmp/
ssh spire.funlab.casa "sudo /tmp/setup-cert-autorenewal.sh"

# On auth host
scp /tmp/renew-keylime-certs.sh auth.funlab.casa:/tmp/
scp /tmp/setup-cert-autorenewal.sh auth.funlab.casa:/tmp/
ssh auth.funlab.casa "sudo /tmp/setup-cert-autorenewal.sh"

# Verify timers are active
ssh spire.funlab.casa "sudo systemctl list-timers renew-keylime-certs.timer"
ssh auth.funlab.casa "sudo systemctl list-timers renew-keylime-certs.timer"
```

**Success Indicators:**
- Timers enabled and active
- Next run scheduled
- Manual test successful

---

### Phase 3: Migrate ca Host (30 minutes)

```bash
# 1. Issue certificate for ca host
ssh spire.funlab.casa "sudo bash -c '
export BAO_ADDR=https://127.0.0.1:8200
export BAO_SKIP_VERIFY=true
export BAO_TOKEN=s.eNHhmKyqvqW7Q93yVfswqFtx

bao write -format=json pki_int/issue/keylime-services \
    common_name=\"agent.keylime.funlab.casa\" \
    alt_names=\"localhost\" \
    ip_sans=\"10.10.2.60,127.0.0.1\" \
    ttl=\"24h\" | tee /tmp/ca-agent-cert.json | \
    jq -r \".data.certificate\" > /tmp/ca-agent.crt

jq -r \".data.private_key\" /tmp/ca-agent-cert.json > /tmp/ca-agent.key
jq -r \".data.issuing_ca\" /tmp/ca-agent-cert.json > /tmp/ca-ca.crt
'"

# 2. Install certificates on ca host
ssh ca.funlab.casa "sudo mkdir -p /etc/keylime/certs"

# Copy certificates (using pipe to avoid SSH key issues)
ssh spire.funlab.casa "sudo cat /tmp/ca-agent.crt" | \
    ssh ca.funlab.casa "sudo tee /etc/keylime/certs/agent.crt > /dev/null"
ssh spire.funlab.casa "sudo cat /tmp/ca-agent.key" | \
    ssh ca.funlab.casa "sudo tee /etc/keylime/certs/agent.key > /dev/null"
ssh spire.funlab.casa "sudo cat /tmp/ca-ca.crt" | \
    ssh ca.funlab.casa "sudo tee /etc/keylime/certs/ca.crt > /dev/null"

# Set permissions
ssh ca.funlab.casa "sudo chmod 644 /etc/keylime/certs/*.crt && \
    sudo chmod 600 /etc/keylime/certs/*.key && \
    sudo chown -R keylime:tss /etc/keylime/certs"

# 3. Run migration script
scp /tmp/migrate-ca-to-keylime.sh ca.funlab.casa:/tmp/
ssh ca.funlab.casa "sudo /tmp/migrate-ca-to-keylime.sh"

# 4. Verify migration
ssh spire.funlab.casa "sudo /opt/spire/bin/spire-server agent list | grep ca"
```

---

### Phase 4: Migrate spire Host (30 minutes)

Same process as ca host, but:
- Use IP: 10.10.2.62
- Agent will be co-located with verifier/registrar

---

## 📊 Current Status

### Completed ✅
- Book of Omens PKI deployed in OpenBao
- 4 PKI roles configured
- Keylime certificates issued (spire, auth)
- Certificates installed on spire and auth
- Configurations updated for mTLS
- Auto-renewal scripts created
- Migration scripts created

### Pending ⏳
- Restart services to activate mTLS
- Setup auto-renewal timers
- Migrate ca host to Keylime
- Migrate spire host to Keylime
- Remove join_token plugin

---

## 🔍 Verification Commands

After each phase, use these commands to verify success:

### Check mTLS Status
```bash
# Verifier logs
ssh spire "sudo grep -i 'tls\|certificate' /var/log/keylime-verifier.log | tail -10"

# Agent logs
ssh auth "sudo journalctl -u keylime_agent -n 20 | grep -i tls"
```

### Check Certificate Validity
```bash
# On any host
ssh <host> "sudo openssl x509 -in /etc/keylime/certs/agent.crt -noout -dates"
```

### Check Attestation Status
```bash
# On spire host
ssh spire "sudo keylime_tenant -c status --uuid <agent-uuid>"
# Look for: attestation_status: PASS
#           attestation_count: increasing
```

### Check SPIRE Agents
```bash
ssh spire "sudo /opt/spire/bin/spire-server agent list"
# Should show agents with keylime attestation type
```

### Check Auto-Renewal
```bash
ssh <host> "sudo systemctl status renew-keylime-certs.timer"
ssh <host> "sudo systemctl list-timers"
```

---

## 🚨 Rollback Procedures

If something goes wrong:

### Rollback mTLS Configuration
```bash
# On spire
ssh spire "sudo cp /etc/keylime/verifier.conf.backup-20260210 /etc/keylime/verifier.conf && \
    sudo cp /etc/keylime/registrar.conf.backup-20260210 /etc/keylime/registrar.conf && \
    sudo pkill -9 -f keylime_verifier && sudo pkill -9 -f keylime_registrar && \
    sudo nohup keylime_registrar &> /var/log/keylime-registrar.log & \
    sudo nohup keylime_verifier &> /var/log/keylime-verifier.log &"

# On auth
ssh auth "sudo cp /etc/keylime/keylime-agent.conf.backup-20260210 /etc/keylime/keylime-agent.conf && \
    sudo systemctl restart keylime_agent"
```

### Rollback SPIRE Agent
```bash
# On migrated host
ssh <host> "sudo cp /etc/spire/agent.conf.backup-keylime-* /etc/spire/agent.conf && \
    sudo systemctl restart spire-agent"
```

---

## 📚 Documentation

### Created Documentation
1. **book-of-omens-pki-deployment.md** - PKI infrastructure (✅ in git)
2. **keylime-mtls-deployment.md** - mTLS configuration (✅ in git)
3. **DEPLOYMENT-SCRIPTS-READY.md** - This file (⏳ to commit)
4. **/tmp/deployment-guide.md** - Detailed deployment guide

### Reference During Deployment
- Read `/tmp/deployment-guide.md` for detailed steps
- Check troubleshooting section if issues arise
- Review rollback procedures before starting

---

## 🎯 Success Criteria

Complete deployment achieved when:

✅ All Keylime services running with mTLS enabled
✅ No certificate validation errors in logs
✅ All 3 hosts (auth, ca, spire) using Keylime attestation
✅ SPIRE agents healthy and attesting successfully
✅ Auto-renewal configured and tested on all hosts
✅ Continuous attestation showing PASS status
✅ Workloads (step-ca, openbao) still functioning
✅ Old join_token agents removed

---

## 🚀 Ready to Execute

**Estimated Total Time:** 1.5-2 hours

**Recommended Approach:**
1. Start with Phase 1 (mTLS activation) - 10 min
2. Verify it works before proceeding
3. Continue to Phase 2 (auto-renewal) - 15 min
4. Test manual renewal before proceeding
5. Phase 3 & 4 (migration) - 1 hour total

**Risk Level:** Low
- Configurations backed up
- Rollback procedures documented
- Each phase is independent
- Can pause between phases

---

## 📝 Next Command

To begin deployment:

```bash
# Read the deployment guide
cat /tmp/deployment-guide.md

# Then start with Phase 1
scp /tmp/restart-keylime-mtls.sh spire.funlab.casa:/tmp/
ssh spire.funlab.casa "sudo /tmp/restart-keylime-mtls.sh"
```

---

**Status:** 🟢 READY TO DEPLOY
**Scripts Location:** `/tmp/` (local machine)
**Documentation:** Complete
**Rollback:** Prepared
**Last Updated:** 2026-02-10 21:00 EST
