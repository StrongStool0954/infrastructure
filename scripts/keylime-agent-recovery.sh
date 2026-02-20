#!/bin/bash
# keylime-agent-recovery.sh
# Runs every 5 minutes. Resets verifier state-7 agents back to state 3 (GET_QUOTE)
# ONLY if the agent is currently reachable on its registered port (i.e., it rebooted
# and came back up). This handles the case where an individual agent host reboots
# while the verifier keeps running - the verifier marks the agent FAILED (7), but
# once the agent is back up, this script detects it and resumes polling.
#
# Safety: requires agent to be actively listening on port 9002 before resetting.
# Does NOT touch state 9 (INVALID_QUOTE) - genuine attestation failures require
# manual review.

DB="/var/lib/keylime/cv_data.sqlite"
LOG_TAG="keylime-agent-recovery"
RESET_COUNT=0
CHECKED_COUNT=0

if [ ! -f "$DB" ]; then
    exit 0
fi

# Find all state-7 agents
while IFS='|' read -r agent_id ip port; do
    [ -z "$agent_id" ] || [ -z "$ip" ] || [ -z "$port" ] && continue
    CHECKED_COUNT=$((CHECKED_COUNT + 1))

    # Check if agent is actively listening (came back up after reboot)
    if timeout 3 bash -c "echo > /dev/tcp/${ip}/${port}" 2>/dev/null; then
        sqlite3 "$DB" "UPDATE verifiermain SET operational_state=3 WHERE agent_id='${agent_id}' AND operational_state=7;"
        logger -t "$LOG_TAG" "Auto-recovered agent ${agent_id} (${ip}:${port}): state 7->3 (agent is alive)"
        RESET_COUNT=$((RESET_COUNT + 1))
    fi
done < <(sqlite3 "$DB" "SELECT agent_id, ip, port FROM verifiermain WHERE operational_state=7;" 2>/dev/null)

if [ "$RESET_COUNT" -gt 0 ]; then
    logger -t "$LOG_TAG" "Recovery complete: reset $RESET_COUNT of $CHECKED_COUNT failed agent(s) to GET_QUOTE"
fi
