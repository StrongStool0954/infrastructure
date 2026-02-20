#!/bin/bash
# keylime-gc.sh
# Garbage collects stale Keylime agent registrations from the verifier and registrar.
#
# Tier 1 — AUTO-DELETE (safe, no human review needed):
#   Agents that were NEVER successfully attested (attestation_count=0)
#   and whose last quote attempt was more than STALE_DAYS ago.
#   These are orphaned registrations: test entries, renamed agents, or
#   registrations added against the wrong host.
#
# Tier 2 — REPORT ONLY (requires human review):
#   Agents that WERE once healthy (attestation_count>0) but have been in
#   a terminal state (FAILED=7 or INVALID_QUOTE=9) for more than REVIEW_DAYS.
#   Could be a decommissioned host, a renamed agent identity, or a real
#   security event. Use 'keylime_tenant -c delete -u <id>' after review.
#
# Usage:
#   keylime-gc.sh                        # live run
#   DRY_RUN=1 keylime-gc.sh             # preview without deleting
#   STALE_DAYS=3 keylime-gc.sh          # tighten staleness threshold
#   REVIEW_DAYS=7 keylime-gc.sh         # loosen review threshold

set -uo pipefail

STALE_DAYS=${STALE_DAYS:-7}
REVIEW_DAYS=${REVIEW_DAYS:-3}
DRY_RUN=${DRY_RUN:-0}

NOW=$(date +%s)
STALE_CUTOFF=$((NOW - STALE_DAYS * 86400))
REVIEW_CUTOFF=$((NOW - REVIEW_DAYS * 86400))

CV_DB="/var/lib/keylime/cv_data.sqlite"
LOG_TAG="keylime-gc"

# keylime_tenant connection params (backend ports, bypasses nginx)
TENANT_ARGS="-v 127.0.0.1 -vp 8881 -r 127.0.0.1 -rp 8891"

DELETED=0
REVIEW_COUNT=0
ERRORS=0

log() { logger -t "$LOG_TAG" "$*"; echo "$*"; }

# ── Sanity checks ─────────────────────────────────────────────────────────────

if [ ! -f "$CV_DB" ]; then
    log "ERROR: Verifier DB not found at $CV_DB"
    exit 1
fi

if ! command -v keylime_tenant &>/dev/null; then
    log "ERROR: keylime_tenant not found in PATH"
    exit 1
fi

log "=== Keylime Agent GC - $(date) ==="
log "Thresholds: auto-delete after ${STALE_DAYS}d never-attested | report after ${REVIEW_DAYS}d terminal state"
[ "$DRY_RUN" = "1" ] && log "*** DRY RUN — no changes will be made ***"

# ── Tier 1: Auto-delete ───────────────────────────────────────────────────────

log ""
log "── Tier 1: Never-attested orphans (auto-delete if >${STALE_DAYS} days old) ──"

mapfile -t TIER1 < <(sqlite3 "$CV_DB" \
    "SELECT agent_id, ip, operational_state, last_received_quote
     FROM verifiermain
     WHERE attestation_count = 0
       AND last_successful_attestation = 0
       AND last_received_quote > 0
       AND last_received_quote < ${STALE_CUTOFF}
       AND operational_state NOT IN (3, 4, 5);" 2>/dev/null)

if [ ${#TIER1[@]} -eq 0 ]; then
    log "  None found."
else
    for row in "${TIER1[@]}"; do
        IFS='|' read -r agent_id ip state last_quote <<< "$row"
        last_seen=$(date -d "@${last_quote}" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")
        state_name="FAILED"; [ "$state" = "9" ] && state_name="INVALID_QUOTE"
        log "  DELETE: ${agent_id:0:16}... ip=$ip state=$state_name last_seen=$last_seen"

        if [ "$DRY_RUN" = "1" ]; then
            log "    [DRY RUN] would run: keylime_tenant -c delete + regdelete"
            continue
        fi

        # Remove from verifier
        if keylime_tenant $TENANT_ARGS -c delete -u "$agent_id" \
                &>/tmp/keylime-gc-delete.log 2>&1; then
            log "    Verifier: deleted"
        else
            # 404 = already gone from verifier, that's fine
            if grep -qi "404\|not found\|does not exist" /tmp/keylime-gc-delete.log 2>/dev/null; then
                log "    Verifier: already absent (404)"
            else
                log "    Verifier: ERROR - $(tail -1 /tmp/keylime-gc-delete.log)"
                ERRORS=$((ERRORS + 1))
                continue
            fi
        fi

        # Remove from registrar (best-effort — may not be there)
        if keylime_tenant $TENANT_ARGS -c regdelete -u "$agent_id" \
                &>/tmp/keylime-gc-delete.log 2>&1; then
            log "    Registrar: deleted"
        else
            if grep -qi "404\|not found\|does not exist" /tmp/keylime-gc-delete.log 2>/dev/null; then
                log "    Registrar: already absent (404)"
            else
                log "    Registrar: ERROR - $(tail -1 /tmp/keylime-gc-delete.log)"
                # Non-fatal: verifier entry is already gone
            fi
        fi

        logger -t "$LOG_TAG" "GC deleted: $agent_id (ip=$ip, last_seen=$last_seen)"
        DELETED=$((DELETED + 1))
    done
fi

# ── Tier 2: Report agents that were healthy but have been failing ──────────────

log ""
log "── Tier 2: Previously-healthy agents in terminal state (>${REVIEW_DAYS}d, needs review) ──"

mapfile -t TIER2 < <(sqlite3 "$CV_DB" \
    "SELECT agent_id, ip, operational_state, attestation_count,
            last_successful_attestation, last_received_quote
     FROM verifiermain
     WHERE attestation_count > 0
       AND operational_state IN (7, 9)
       AND last_successful_attestation < ${REVIEW_CUTOFF};" 2>/dev/null)

if [ ${#TIER2[@]} -eq 0 ]; then
    log "  None."
else
    log "  To investigate or remove: keylime_tenant $TENANT_ARGS -c status -u <id>"
    log "  To delete after review:   keylime_tenant $TENANT_ARGS -c delete -u <id>"
    log "                            keylime_tenant $TENANT_ARGS -c regdelete -u <id>"
    log ""
    for row in "${TIER2[@]}"; do
        IFS='|' read -r agent_id ip state count last_ok last_quote <<< "$row"
        state_name="FAILED"; [ "$state" = "9" ] && state_name="INVALID_QUOTE"
        last_ok_str=$(date -d "@${last_ok}" "+%Y-%m-%d" 2>/dev/null || echo "unknown")
        log "  REVIEW: ${agent_id:0:16}... ip=$ip state=$state_name attestations=$count last_healthy=$last_ok_str"
        REVIEW_COUNT=$((REVIEW_COUNT + 1))
    done
fi

# ── Summary ───────────────────────────────────────────────────────────────────

log ""
log "=== Summary: deleted=$DELETED needs_review=$REVIEW_COUNT errors=$ERRORS ==="

[ "$ERRORS" -gt 0 ] && log "WARNING: $ERRORS deletion(s) failed — check journalctl -t keylime-gc"

if [ "$DRY_RUN" = "0" ] && [ $((DELETED + REVIEW_COUNT + ERRORS)) -gt 0 ]; then
    NOTIFY_MSG="Keylime GC: deleted=${DELETED} needs_review=${REVIEW_COUNT} errors=${ERRORS}"
    PRIORITY=0
    [ "$REVIEW_COUNT" -gt 0 ] && PRIORITY=-1  # lower priority for review items
    [ "$ERRORS" -gt 0 ] && PRIORITY=1          # high priority for errors
    /usr/local/bin/pushover-notify.sh "Keylime GC" "$NOTIFY_MSG" "$PRIORITY" 2>/dev/null || true
fi

[ "$ERRORS" -gt 0 ] && exit 1
exit 0
