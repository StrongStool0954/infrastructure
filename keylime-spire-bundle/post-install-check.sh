#!/bin/bash
# Keylime + SPIRE Post-Installation Verification Script
# Tests installation, configuration, attestation, and SVID generation

set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; }
fail() { echo -e "${RED}❌ FAIL${NC}: $1"; }
warn() { echo -e "${YELLOW}⚠️  WARN${NC}: $1"; }
info() { echo -e "${BOLD}$1${NC}"; }
section() { echo -e "${BLUE}━━━ $1 ━━━${NC}"; }

echo "========================================="
info "Keylime + SPIRE Post-Installation Check"
info "Version: 2.5.0"
echo "========================================="
echo

# Check 1: Binaries installed
section "1. Checking binaries"
if [ -x /usr/local/bin/keylime_agent ]; then
    pass "keylime_agent is installed and executable"
else
    fail "keylime_agent not found or not executable"
fi

if [ -x /usr/local/bin/spire-agent ]; then
    SPIRE_VERSION=$(/usr/local/bin/spire-agent --version 2>/dev/null || echo "unknown")
    pass "spire-agent is installed ($SPIRE_VERSION)"
else
    warn "spire-agent not found"
fi

if [ -x /usr/local/bin/keylime-attestor-agent ]; then
    pass "SPIRE Keylime plugin (agent) is installed"
else
    warn "SPIRE Keylime plugin (agent) not found"
fi
echo

# Check 2: User and groups
section "2. Checking users and groups"
if id keylime >/dev/null 2>&1; then
    KEYLIME_UID=$(id -u keylime)
    pass "keylime user exists (uid=$KEYLIME_UID)"

    if id -nG keylime | grep -q tss; then
        pass "keylime user is in tss group (TPM access enabled)"
    else
        fail "keylime user is NOT in tss group - TPM access will fail"
    fi
else
    fail "keylime user does not exist"
fi

if id spire >/dev/null 2>&1; then
    SPIRE_UID=$(id -u spire)
    pass "spire user exists (uid=$SPIRE_UID)"

    # Check if spire is in keylime group (needed to read Keylime certs)
    if id -nG spire | grep -q keylime; then
        pass "spire user is in keylime group (can read Keylime certificates)"
    else
        warn "spire user is NOT in keylime group - cannot read Keylime certs for mTLS"
    fi
else
    warn "spire user does not exist"
fi
echo

# Check 3: Directories
section "3. Checking directories"
for dir in /etc/keylime /var/lib/keylime /var/log/keylime /etc/spire /var/lib/spire /run/spire/sockets; do
    if [ -d "$dir" ]; then
        OWNER=$(stat -c '%U:%G' "$dir" 2>/dev/null || echo "unknown")
        pass "$dir exists (owner: $OWNER)"
    else
        warn "$dir does not exist"
    fi
done
echo

# Check 4: TPM access
section "4. Checking TPM access"
if [ -c /dev/tpm0 ]; then
    TPM_PERMS=$(ls -l /dev/tpm0 | awk '{print $1, $3, $4}')
    pass "TPM device exists: /dev/tpm0 ($TPM_PERMS)"
elif [ -c /dev/tpmrm0 ]; then
    TPM_PERMS=$(ls -l /dev/tpmrm0 | awk '{print $1, $3, $4}')
    pass "TPM resource manager exists: /dev/tpmrm0 ($TPM_PERMS)"
else
    warn "No TPM device found - using software TPM?"
fi
echo

# Check 5: Keylime configuration
section "5. Checking Keylime configuration"
if [ -f /etc/keylime/agent.conf ]; then
    pass "Configuration file exists: /etc/keylime/agent.conf"

    if grep -q "registrar_ip" /etc/keylime/agent.conf; then
        REGISTRAR=$(grep "^registrar_ip" /etc/keylime/agent.conf | head -1)
        pass "Registrar configured: $REGISTRAR"
    else
        warn "Registrar IP not configured"
    fi

    if grep -q "verifier_ip" /etc/keylime/agent.conf; then
        VERIFIER=$(grep "^verifier_ip" /etc/keylime/agent.conf | head -1)
        pass "Verifier configured: $VERIFIER"
    else
        warn "Verifier IP not configured"
    fi
else
    fail "Configuration file not found: /etc/keylime/agent.conf"
fi
echo

# Check 6: Keylime certificates
section "6. Checking Keylime certificates"
CERT_DIR="/etc/keylime/certs"
if [ -d "$CERT_DIR" ]; then
    pass "Certificate directory exists"

    if [ -f "$CERT_DIR/agent.crt" ]; then
        EXPIRY=$(openssl x509 -in "$CERT_DIR/agent.crt" -noout -enddate 2>/dev/null | cut -d= -f2)
        if [ $? -eq 0 ]; then
            EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo 0)
            NOW_EPOCH=$(date +%s)
            HOURS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 3600 ))

            if [ $HOURS_LEFT -lt 24 ]; then
                warn "Agent certificate expires soon: $EXPIRY ($HOURS_LEFT hours left)"
            else
                pass "Agent certificate valid (expires: $EXPIRY)"
            fi
        fi
    else
        warn "Agent certificate not found: $CERT_DIR/agent.crt"
    fi

    if [ -f "$CERT_DIR/agent-pkcs8.key" ]; then
        KEY_PERMS=$(stat -c '%a' "$CERT_DIR/agent-pkcs8.key")
        if [ "$KEY_PERMS" = "640" ] || [ "$KEY_PERMS" = "600" ]; then
            pass "Agent private key exists with secure permissions ($KEY_PERMS)"
        else
            warn "Agent private key has insecure permissions: $KEY_PERMS"
        fi
    else
        warn "Agent private key not found"
    fi

    if [ -f "$CERT_DIR/ca-root-only.crt" ]; then
        pass "Root CA certificate exists"
    else
        warn "Root CA not found: $CERT_DIR/ca-root-only.crt"
    fi
else
    warn "Certificate directory not found: $CERT_DIR"
fi
echo

# Check 7: SPIRE configuration and trust bundle
section "7. Checking SPIRE configuration"
if [ -f /etc/spire/agent.conf ]; then
    pass "SPIRE agent configuration exists"

    if grep -q "keylime" /etc/spire/agent.conf; then
        pass "Keylime NodeAttestor plugin configured"
    else
        warn "Keylime plugin not found in SPIRE config"
    fi

    # Check SPIRE trust bundle
    if [ -f /etc/spire/bootstrap.crt ]; then
        pass "SPIRE trust bundle exists"
        
        # Validate trust bundle certificates
        NUM_CERTS=$(grep -c "BEGIN CERTIFICATE" /etc/spire/bootstrap.crt 2>/dev/null || echo 0)
        pass "Trust bundle contains $NUM_CERTS certificate(s)"
        
        # Check expiration of first certificate in bundle
        BUNDLE_EXPIRY=$(openssl x509 -in /etc/spire/bootstrap.crt -noout -enddate 2>/dev/null | cut -d= -f2)
        if [ $? -eq 0 ] && [ -n "$BUNDLE_EXPIRY" ]; then
            BUNDLE_EXPIRY_EPOCH=$(date -d "$BUNDLE_EXPIRY" +%s 2>/dev/null || echo 0)
            NOW_EPOCH=$(date +%s)
            BUNDLE_HOURS_LEFT=$(( ($BUNDLE_EXPIRY_EPOCH - $NOW_EPOCH) / 3600 ))
            
            if [ $BUNDLE_HOURS_LEFT -lt 24 ]; then
                warn "SPIRE trust bundle expires soon: $BUNDLE_EXPIRY ($BUNDLE_HOURS_LEFT hours left)"
            elif [ $BUNDLE_EXPIRY_EPOCH -lt $NOW_EPOCH ]; then
                fail "SPIRE trust bundle EXPIRED: $BUNDLE_EXPIRY"
            else
                pass "SPIRE trust bundle valid (expires: $BUNDLE_EXPIRY)"
            fi
        else
            warn "Could not verify SPIRE trust bundle expiration"
        fi
        
        # Check permissions
        BUNDLE_PERMS=$(stat -c '%a' /etc/spire/bootstrap.crt)
        if [ "$BUNDLE_PERMS" = "644" ] || [ "$BUNDLE_PERMS" = "640" ]; then
            pass "SPIRE trust bundle has correct permissions ($BUNDLE_PERMS)"
        else
            warn "SPIRE trust bundle has unusual permissions: $BUNDLE_PERMS"
        fi
    else
        warn "SPIRE trust bundle missing: /etc/spire/bootstrap.crt"
        echo "   This should have been included in the bundle"
    fi
else
    warn "SPIRE agent configuration not found"
fi
echo

# Check 8: Network connectivity
section "8. Checking network connectivity"
if [ -f /etc/keylime/agent.conf ]; then
    REGISTRAR_HOST=$(grep "^registrar_ip" /etc/keylime/agent.conf | cut -d= -f2 | tr -d ' "' | head -1)
    REGISTRAR_PORT=$(grep "^registrar_port" /etc/keylime/agent.conf | cut -d= -f2 | tr -d ' "' | head -1)

    if [ -n "$REGISTRAR_HOST" ] && [ -n "$REGISTRAR_PORT" ]; then
        if timeout 5 bash -c "echo > /dev/tcp/$REGISTRAR_HOST/$REGISTRAR_PORT" 2>/dev/null; then
            pass "Registrar is reachable: $REGISTRAR_HOST:$REGISTRAR_PORT"
        else
            warn "Cannot connect to registrar: $REGISTRAR_HOST:$REGISTRAR_PORT"
        fi
    fi

    VERIFIER_HOST=$(grep "^verifier_ip" /etc/keylime/agent.conf | cut -d= -f2 | tr -d ' "' | head -1)
    VERIFIER_PORT=$(grep "^verifier_port" /etc/keylime/agent.conf | cut -d= -f2 | tr -d ' "' | head -1)

    if [ -n "$VERIFIER_HOST" ] && [ -n "$VERIFIER_PORT" ]; then
        if timeout 5 bash -c "echo > /dev/tcp/$VERIFIER_HOST/$VERIFIER_PORT" 2>/dev/null; then
            pass "Verifier is reachable: $VERIFIER_HOST:$VERIFIER_PORT"
        else
            warn "Cannot connect to verifier: $VERIFIER_HOST:$VERIFIER_PORT"
        fi
    fi
fi

# Check SPIRE server connectivity
if [ -f /etc/spire/agent.conf ]; then
    SPIRE_SERVER=$(grep "server_address" /etc/spire/agent.conf | cut -d'"' -f2)
    SPIRE_PORT=$(grep "server_port" /etc/spire/agent.conf | cut -d'"' -f2)

    if [ -n "$SPIRE_SERVER" ] && [ -n "$SPIRE_PORT" ]; then
        if timeout 5 bash -c "echo > /dev/tcp/$SPIRE_SERVER/$SPIRE_PORT" 2>/dev/null; then
            pass "SPIRE server is reachable: $SPIRE_SERVER:$SPIRE_PORT"
        else
            warn "Cannot connect to SPIRE server: $SPIRE_SERVER:$SPIRE_PORT"
        fi
    fi
fi
echo

# Check 9: Keylime Agent Service
section "9. Checking Keylime Agent service"
if [ -f /etc/systemd/system/keylime-agent.service ]; then
    pass "Systemd service file exists"

    if systemctl is-enabled keylime-agent.service >/dev/null 2>&1; then
        pass "Service is enabled"
    else
        warn "Service is not enabled"
    fi

    if systemctl is-active keylime-agent.service >/dev/null 2>&1; then
        pass "Service is running"

        if ss -tlnp 2>/dev/null | grep -q ":9002"; then
            pass "Agent is listening on port 9002"
        else
            warn "Agent not listening on expected port 9002"
        fi
    else
        warn "Service is not running"
    fi
else
    warn "Systemd service file not found"
fi
echo

# Check 10: Keylime Agent registration
section "10. Checking Keylime attestation"
if systemctl is-active keylime-agent.service >/dev/null 2>&1; then
    if journalctl -u keylime-agent.service --since "10 minutes ago" | grep -q "SUCCESS.*registered"; then
        pass "Agent successfully registered with Keylime"
    elif journalctl -u keylime-agent.service --since "1 hour ago" | grep -q "SUCCESS.*registered"; then
        pass "Agent registered (not recently, but previously successful)"
    else
        warn "No registration success messages found"
    fi

    if journalctl -u keylime-agent.service --since "10 minutes ago" | grep -q -i "quote"; then
        pass "TPM quote activity detected (attestation active)"
    else
        warn "No recent TPM quote activity"
    fi
else
    warn "Keylime agent not running - cannot check attestation"
fi
echo

# Check 11: SPIRE Agent Service
section "11. Checking SPIRE Agent service"
if [ -f /etc/systemd/system/spire-agent.service ]; then
    pass "SPIRE agent service file exists"

    if systemctl is-enabled spire-agent.service >/dev/null 2>&1; then
        pass "SPIRE agent service is enabled"
    else
        warn "SPIRE agent service is not enabled"
    fi

    if systemctl is-active spire-agent.service >/dev/null 2>&1; then
        pass "SPIRE agent service is running"
    else
        warn "SPIRE agent service is not running"
    fi
else
    warn "SPIRE agent service file not found"
fi
echo

# Check 12: SPIRE SVID Generation
section "12. Checking SPIRE SVID generation"
if systemctl is-active spire-agent.service >/dev/null 2>&1; then
    if [ -S /run/spire/sockets/agent.sock ]; then
        pass "SPIRE agent socket exists"

        SVID_OUTPUT=$(/usr/local/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock 2>&1 || true)

        if echo "$SVID_OUTPUT" | grep -q "SPIFFE ID"; then
            SPIFFE_ID=$(echo "$SVID_OUTPUT" | grep "SPIFFE ID" | head -1 | awk '{print $3}')
            pass "SVID generation successful"
            pass "SPIFFE ID: $SPIFFE_ID"

            if echo "$SVID_OUTPUT" | grep -q "Expires at"; then
                SVID_EXPIRY=$(echo "$SVID_OUTPUT" | grep "Expires at" | head -1 | cut -d':' -f2-)
                pass "SVID expires: $SVID_EXPIRY"
            fi
        else
            warn "Cannot fetch SVID - agent may not be attested yet"
            echo "   Output: $SVID_OUTPUT"
        fi
    else
        warn "SPIRE agent socket not found: /run/spire/sockets/agent.sock"
    fi

    if journalctl -u spire-agent.service --since "10 minutes ago" | grep -q "Attestation succeeded"; then
        pass "SPIRE agent attestation successful"
    elif journalctl -u spire-agent.service --since "1 hour ago" | grep -q "Attestation succeeded"; then
        pass "SPIRE agent attested (not recently, but previously successful)"
    else
        warn "No SPIRE attestation success messages found"
    fi
else
    warn "SPIRE agent not running - cannot check SVID generation"
fi
echo

# Check 13: Health monitoring
section "13. Checking health monitoring"
if [ -f /etc/systemd/system/keylime-verify.timer ]; then
    pass "Health check timer exists"

    if systemctl is-enabled keylime-verify.timer >/dev/null 2>&1; then
        pass "Health check timer is enabled"
    else
        warn "Health check timer is not enabled"
    fi

    if systemctl is-active keylime-verify.timer >/dev/null 2>&1; then
        pass "Health check timer is running"

        NEXT_RUN=$(systemctl status keylime-verify.timer 2>/dev/null | grep "Trigger:" | cut -d':' -f2-)
        if [ -n "$NEXT_RUN" ]; then
            info "   Next health check: $NEXT_RUN"
        fi
    else
        warn "Health check timer is not active"
    fi
else
    warn "Health check timer not found"
fi
echo

# Summary
echo "========================================="
section "Summary"
echo "========================================="
echo
echo "Service Status:"
for svc in keylime-agent spire-agent keylime-verify.timer; do
    if systemctl is-active --quiet $svc 2>/dev/null; then
        echo -e "  ${GREEN}●${NC} $svc - running"
    elif systemctl is-enabled --quiet $svc 2>/dev/null; then
        echo -e "  ${YELLOW}○${NC} $svc - enabled but not running"
    else
        echo -e "  ${RED}○${NC} $svc - not enabled"
    fi
done

echo
echo "Key Metrics:"
if systemctl is-active --quiet keylime-agent; then
    echo "  ✓ Keylime attestation: ACTIVE"
else
    echo "  ✗ Keylime attestation: INACTIVE"
fi

if systemctl is-active --quiet spire-agent; then
    if [ -S /run/spire/sockets/agent.sock ]; then
        echo "  ✓ SPIRE SVID generation: ACTIVE"
    else
        echo "  ⚠ SPIRE agent running but socket not ready"
    fi
else
    echo "  ✗ SPIRE SVID generation: INACTIVE"
fi

if systemctl is-active --quiet keylime-verify.timer; then
    echo "  ✓ Daily health checks: ENABLED"
else
    echo "  ⚠ Daily health checks: DISABLED"
fi

echo
echo "========================================="
info "Verification Complete"
echo "========================================="

