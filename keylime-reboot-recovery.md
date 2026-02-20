# Keylime Reboot Recovery - State 7 (FAILED) Fix

**Date:** 2026-02-20
**Status:** ✅ Deployed on spire.funlab.casa
**Problem:** After a power outage or simultaneous reboot of all hosts, the
Keylime verifier marks agents as FAILED (state 7) before they have time to
come back up. State 7 is terminal — the verifier stops polling and the agent
can never recover without manual intervention.

---

## Root Cause

**The exact failure sequence on spire.funlab.casa (observed 2026-02-20):**

```
09:35:12  keylime_verifier starts, immediately tries to quote agent at 10.10.2.62
09:35:12  Connection refused (agent still booting)
09:35:14  Retry 2/5 (+2s backoff)
09:35:18  Retry 3/5 (+4s backoff)
09:35:29  Retry 4/5 (+8s backoff... exponential)
09:35:48  Retry 5/5 (+16s backoff)
09:36:23  "Agent was not reachable for quote in 5 tries, setting state to FAILED"
09:36:23  Verifier broadcasts revocation to all agents (all also down, Error 599)
09:38:00  Agent finally boots, re-registers with registrar — too late, state=7
```

**Total verifier retry window:** ~71 seconds (exponential backoff: 2+4+8+16+32s)
**Time agent needed to boot:** ~107 seconds
**Gap:** 36 seconds — just enough to miss the window

**Downstream cascade:**
- State 7 → SPIRE attestor plugin sees Keylime state 7 → SPIRE can't attest
- SPIRE socket never created → OpenBao can't get SVIDs → OpenBao fails to start
- OpenBao down → cert renewal fails at boot
- Cert renewal reports failure via Pushover alert

**Why state 7 is terminal:** This is intentional Keylime security design.
An unreachable agent could mean tampering. The verifier stops polling and
broadcasts revocation. Recovery requires manual `keylime_tenant` intervention.

**Why the verifier and registrar Python source was NOT modified:**
Both are upstream Keylime 7.14.0, installed 2026-02-11, unmodified. The fix
is entirely in systemd service units and a shell script.

---

## Solution

**Combined Option B + C:**

1. **DB reset before verifier starts** — `keylime-reset-failed.sh` resets agents
   in state 7 (connectivity failure) back to state 3 (GET_QUOTE) before the
   verifier process starts. State 9 (INVALID_QUOTE = genuine TPM failure) and
   state 10 (TENANT_FAILED) are deliberately left alone.

2. **Boot ordering** — verifier now starts `After=keylime_agent.service`, so
   the local agent is registered and listening before the verifier starts polling.
   The 71-second race condition is eliminated.

3. **Cert renewal timer** — a `keylime-cert-renewal.timer` retries renewal
   10 minutes after boot and every 12 hours. If boot-time renewal fails (because
   OpenBao isn't up yet), the timer recovers it once the full stack is running.

4. **Soft OpenBao dependency** — cert renewal uses `Wants=openbao.service`
   (was `Requires=`). If OpenBao isn't up, renewal is skipped gracefully and
   existing certs are used; the timer retries later.

---

## Files Changed

### New: `/usr/local/bin/keylime-reset-failed.sh`

Resets `operational_state=7` → `operational_state=3` in `/var/lib/keylime/cv_data.sqlite`.
Logs to syslog via `logger`. Run as `ExecStartPre` on the verifier service.

### Modified: `/etc/systemd/system/keylime_verifier.service`

```ini
[Unit]
Description=Keylime Verifier
After=network-online.target keylime_registrar.service keylime_agent.service
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/usr/local/bin/keylime-reset-failed.sh   # <-- NEW
ExecStart=/usr/local/bin/keylime_verifier
Restart=on-failure
RestartSec=10s
Environment="RUST_LOG=keylime_verifier=info"
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Key changes:
- Added `keylime_registrar.service keylime_agent.service` to `After=`
- Added `ExecStartPre=/usr/local/bin/keylime-reset-failed.sh`

### Modified: `/etc/systemd/system/keylime_agent.service`

Added `keylime_registrar.service` to `After=` so the agent doesn't try to
register before the registrar is listening.

### Modified: `/etc/systemd/system/keylime-cert-renewal.service`

- Changed `Requires=openbao.service` → `Wants=openbao.service`
- Changed `RemainAfterExit=yes` → `no` (timer needs to re-trigger it)
- ExecStartPre OpenBao health check now exits 1 (not 0) on timeout so the
  service fails cleanly instead of running renewal against a sealed vault

### New: `/etc/systemd/system/keylime-cert-renewal.timer`

```ini
[Timer]
OnBootSec=10min         # retry after boot if boot-time renewal failed
OnUnitActiveSec=12h     # every 12h (certs are 24h)
RandomizedDelaySec=3min
Persistent=true
```

---

## Boot Sequence After Fix

```
network-online.target
       │
       ├─► keylime_registrar.service  (starts, no agent dependency)
       │
       ├─► keylime-cert-renewal.service (oneshot, Wants OpenBao)
       │         │ if OpenBao not up: skips gracefully, agent uses existing certs
       │
       ├─► keylime_agent.service
       │         │ After: registrar + cert-renewal
       │         │ ExecStartPost: waits for :9002
       │         │ Registers with registrar ✓
       │
       └─► keylime_verifier.service
                 │ After: agent (registered + listening)
                 │ ExecStartPre: resets any state-7 agents → state 3
                 │ Starts verifier → quotes agent → state 3 ✓
                 │
                 └─► SPIRE agent attests ✓
                           │
                           └─► SPIRE socket created
                                     │
                                     └─► openbao.service starts + unseals
                                               │
                                               └─► keylime-cert-renewal.timer
                                                   fires at T+10min → renewal ✓
```

---

## Security Considerations

- Only state 7 (connectivity timeout) is reset. State 9 (INVALID_QUOTE = bad
  TPM quote) and state 10 (TENANT_FAILED) are permanent and require manual
  `keylime_tenant` intervention — this is intentional.
- If an agent was genuinely compromised and set to state 7 (not state 9),
  it will get one more quote attempt on verifier restart. If it fails the quote,
  it moves to state 9 (permanent). Acceptable risk for this environment.
- The reset only runs during verifier startup — if the verifier is running
  continuously and an agent goes to state 7 during normal operation, it stays
  in state 7 (normal security behavior).

---

## Verifying Recovery After Reboot

```bash
# Watch the recovery sequence in real time
journalctl -f -u keylime_verifier -u keylime_agent -u spire-agent -u openbao

# Confirm reset script fired and what it reset
journalctl -b | grep keylime-reset-failed

# Check agent states in verifier DB
sqlite3 /var/lib/keylime/cv_data.sqlite \
  "SELECT agent_id, operational_state FROM verifiermain;"
# state 3 = GET_QUOTE (healthy), state 7 = FAILED, state 9 = INVALID_QUOTE

# Confirm SPIRE agent attested
journalctl -b -u spire-agent | grep -i "attest\|socket\|svid"

# Confirm cert renewal succeeded
journalctl -b -u keylime-cert-renewal | tail -20
systemctl status keylime-cert-renewal.timer
```

---

## Manual Recovery (if automated fix fails)

If for any reason the automated reset doesn't work:

```bash
# Check what state agents are in
sudo sqlite3 /var/lib/keylime/cv_data.sqlite \
  "SELECT agent_id, operational_state FROM verifiermain;"

# Manual reset (same as the script)
sudo sqlite3 /var/lib/keylime/cv_data.sqlite \
  "UPDATE verifiermain SET operational_state=3 WHERE operational_state=7;"

# Then restart the verifier
sudo systemctl restart keylime_verifier
```
