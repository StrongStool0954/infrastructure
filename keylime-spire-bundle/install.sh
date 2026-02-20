#!/bin/bash
set -e

# Keylime + SPIRE Complete Bundle Installer
# Version: 2.10.1 - Add ca-chain.crt symlink for Rust agent PKI module

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================="
echo "Keylime + SPIRE Complete Bundle Installer"
echo "Version: 2.10.1 - Add ca-chain.crt symlink for Rust agent PKI module"
echo "========================================="
echo

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo "ERROR: Cannot detect OS (no /etc/os-release)"
    exit 1
fi

# Determine platform
if [ "$OS" = "rocky" ]; then
    PLATFORM="rocky9"
    echo "Detected: Rocky Linux $VER (using rocky9 binaries)"
elif [ "$OS" = "debian" ] && [ "${VER%%.*}" = "12" ]; then
    PLATFORM="debian-bookworm"
elif [ "$OS" = "debian" ] && [ "${VER%%.*}" = "13" ]; then
    PLATFORM="debian-bookworm"
else
    echo "ERROR: Unsupported OS: $OS $VER"
    echo "Supported: Rocky Linux (any version), Debian 12/13"
    exit 1
fi

echo "Using platform binaries: $PLATFORM"
BIN_DIR="$BUNDLE_DIR/bin/$PLATFORM"

if [ ! -d "$BIN_DIR" ]; then
    echo "ERROR: Binaries not found for $PLATFORM"
    exit 1
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Get hostname
HOSTNAME=$(hostname -f)
HOSTNAME_SHORT=$(hostname -s)

echo
echo "Installation will be configured for:"
echo "  Hostname: $HOSTNAME"
echo "  Platform: $PLATFORM"
echo
echo "This will install and configure:"
echo "  ✓ Keylime Agent (with auto-generated config)"
echo "  ✓ SPIRE Agent & Server v1.14.1 (with Keylime attestation)"
echo "  ✓ SPIRE Keylime Plugins"
echo "  ✓ SPIRE Trust Bundle (pre-included)"
echo "  ✓ Systemd services (enabled & started)"
echo "  ✓ Post-installation verification (auto-run)"
echo "  ✓ Daily health checks (enabled)"
echo
read -p "Continue with automated installation? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

echo
echo "========================================="
echo "Installing binaries..."
echo "========================================="

# Create directories
mkdir -p /usr/local/bin
mkdir -p /etc/keylime/certs
mkdir -p /etc/spire
mkdir -p /var/lib/keylime
mkdir -p /var/lib/spire/agent
mkdir -p /var/lib/spire/server
mkdir -p /var/log/keylime
mkdir -p /var/log/spire
mkdir -p /run/spire/sockets

# Install Keylime binaries
echo "Installing Keylime agent..."
install -m 755 "$BIN_DIR/keylime_agent" /usr/local/bin/
echo "  ✓ keylime_agent installed"

# Install SPIRE binaries
echo "Installing SPIRE binaries..."
install -m 755 "$BIN_DIR/spire-agent" /usr/local/bin/
install -m 755 "$BIN_DIR/spire-server" /usr/local/bin/
echo "  ✓ spire-agent installed (v1.14.1)"
echo "  ✓ spire-server installed (v1.14.1)"

# Install SPIRE Keylime plugins
echo "Installing SPIRE Keylime plugins..."
install -m 755 "$BIN_DIR/keylime-attestor-agent" /usr/local/bin/
install -m 755 "$BIN_DIR/keylime-attestor-server" /usr/local/bin/
echo "  ✓ keylime-attestor-agent installed"
echo "  ✓ keylime-attestor-server installed"

# Install SPIRE trust bundle
if [ -f "$BUNDLE_DIR/spire-bootstrap.crt" ]; then
    echo "Installing SPIRE trust bundle..."
    install -m 644 "$BUNDLE_DIR/spire-bootstrap.crt" /etc/spire/bootstrap.crt
    chown spire:spire /etc/spire/bootstrap.crt
    echo "  ✓ SPIRE trust bundle installed"
else
    echo "  ⚠ SPIRE trust bundle not found in package"
    echo "    You will need to fetch it manually after installation"
fi

# Install certificate renewal script
echo "Installing certificate renewal script..."
cat > /usr/local/bin/renew-keylime-certs.sh << 'RENEWAL_EOF'
#!/bin/bash
# Keylime Certificate Renewal Script
# Renews 24h Keylime mTLS certs from OpenBao via SPIRE SVID mTLS.
# At boot this may fail (SPIRE not yet attested) - that is expected.
# The keylime-cert-renewal.timer retries at T+10min after SPIRE is up.
set -e

export BAO_ADDR="${BAO_ADDR:-https://openbao.funlab.casa:8447}"
export VAULT_ADDR="${BAO_ADDR}"
export BAO_SKIP_VERIFY="${BAO_SKIP_VERIFY:-true}"
export VAULT_SKIP_VERIFY="${BAO_SKIP_VERIFY}"
export BAO_TOKEN="${BAO_TOKEN:-$(cat /root/.openbao-token 2>/dev/null || echo "")}"
export VAULT_TOKEN="${BAO_TOKEN}"
# Use the existing Keylime agent cert as the mTLS client credential for OpenBao
export BAO_CLIENT_CERT=/etc/keylime/certs/agent.crt
export BAO_CLIENT_KEY=/etc/keylime/certs/agent-pkcs8.key
export VAULT_CLIENT_CERT="${BAO_CLIENT_CERT}"
export VAULT_CLIENT_KEY="${BAO_CLIENT_KEY}"

CERT_DIR="/etc/keylime/certs"
BACKUP_DIR="/etc/keylime/certs/backups"
HOST_IP=$(hostname -I | awk '{print $1}')
HOSTNAME_SHORT=$(hostname -s)

mkdir -p "$BACKUP_DIR"

echo "=== Keylime Certificate Renewal ==="
echo "Host: ${HOSTNAME_SHORT} (${HOST_IP})"
echo "Date: $(date)"

renew_cert() {
    local cn=$1 alt_names=$2 ip_sans=$3 cert_file=$4 key_base=$5
    echo "Renewing: $cn"
    [ -f "$CERT_DIR/$cert_file" ] && \
        cp "$CERT_DIR/$cert_file" "$BACKUP_DIR/$cert_file.$(date +%Y%m%d-%H%M%S)"

    bao write -format=json pki_int/issue/keylime-services \
        common_name="$cn" \
        alt_names="$alt_names" \
        ip_sans="$ip_sans" \
        private_key_format=pkcs8 \
        ttl="24h" > /tmp/cert-response.json

    tr -d '\r' < /tmp/cert-response.json | jq -r '.data.certificate' > "$CERT_DIR/$cert_file.new"
    tr -d '\r' < /tmp/cert-response.json | jq -r '.data.private_key'  > "$CERT_DIR/${key_base}-pkcs8.key.new"
    tr -d '\r' < /tmp/cert-response.json | jq -r '.data.issuing_ca'   > "$CERT_DIR/ca.crt.new"

    mv "$CERT_DIR/$cert_file.new"          "$CERT_DIR/$cert_file"
    mv "$CERT_DIR/${key_base}-pkcs8.key.new" "$CERT_DIR/${key_base}-pkcs8.key"
    mv "$CERT_DIR/ca.crt.new"              "$CERT_DIR/ca.crt"

    chmod 644 "$CERT_DIR/$cert_file" "$CERT_DIR/ca.crt"
    chmod 640 "$CERT_DIR/${key_base}-pkcs8.key"
    chown keylime:tss "$CERT_DIR/$cert_file" "$CERT_DIR/${key_base}-pkcs8.key" "$CERT_DIR/ca.crt"
    rm -f /tmp/cert-response.json
}

# Always renew agent cert
renew_cert \
    "agent.keylime.funlab.casa" \
    "agent.keylime.funlab.casa,localhost" \
    "${HOST_IP},127.0.0.1" \
    "agent.crt" \
    "agent"

# Renew registrar cert if registrar service is installed on this host
if systemctl list-unit-files keylime_registrar.service &>/dev/null 2>&1; then
    renew_cert \
        "registrar.keylime.funlab.casa" \
        "registrar.keylime.funlab.casa,localhost" \
        "${HOST_IP},127.0.0.1" \
        "registrar.crt" \
        "registrar"
fi

# Renew verifier cert if verifier service is installed on this host
if systemctl list-unit-files keylime_verifier.service &>/dev/null 2>&1; then
    renew_cert \
        "verifier.keylime.funlab.casa" \
        "verifier.keylime.funlab.casa,localhost" \
        "${HOST_IP},127.0.0.1" \
        "verifier.crt" \
        "verifier"
fi

# Non-blocking service restarts so cert files are reloaded
systemctl try-restart keylime_agent.service  2>/dev/null || \
    systemctl try-restart keylime-agent.service 2>/dev/null || true
systemctl try-restart keylime_verifier.service   2>/dev/null || true
systemctl try-restart keylime_registrar.service  2>/dev/null || true

echo "=== Renewal Complete ==="
openssl x509 -in "$CERT_DIR/agent.crt" -noout -subject -enddate
echo "Next renewal: $(date -d '+23 hours' '+%Y-%m-%d %H:%M:%S')"
RENEWAL_EOF
chmod 755 /usr/local/bin/renew-keylime-certs.sh
echo "  ✓ renew-keylime-certs.sh installed"

# Install post-installation check script
if [ -f "$BUNDLE_DIR/post-install-check.sh" ]; then
    echo "Installing post-installation verification..."
    install -m 755 "$BUNDLE_DIR/post-install-check.sh" /usr/local/bin/keylime-verify
    echo "  ✓ keylime-verify installed"

# Install SPIRE CA update script
if [ -f "$BUNDLE_DIR/update-spire-ca.sh" ]; then
    echo "Installing SPIRE CA update script..."
    install -m 755 "$BUNDLE_DIR/update-spire-ca.sh" /usr/local/bin/
    echo "  ✓ update-spire-ca.sh installed"
fi
fi

echo
echo "========================================="
echo "Creating users and groups..."
echo "========================================="

# Create keylime user and group
if ! getent group keylime >/dev/null; then
    groupadd -r keylime
fi

if ! getent passwd keylime >/dev/null; then
    useradd -r -g keylime -G tss -d /var/lib/keylime -s /bin/false keylime
    echo "  ✓ keylime user created (added to tss group)"
else
    usermod -a -G tss keylime 2>/dev/null || true
    echo "  ✓ keylime user already exists (ensured in tss group)"
fi

# Create spire user and group
if ! getent group spire >/dev/null; then
    groupadd -r spire
fi

if ! getent passwd spire >/dev/null; then
    useradd -r -g spire -G keylime -d /var/lib/spire -s /bin/false spire
    echo "  ✓ spire user created"
else
    echo "  ✓ spire user already exists"
    usermod -a -G keylime spire 2>/dev/null || true
fi

# Set ownership
chown -R keylime:keylime /var/lib/keylime /var/log/keylime /etc/keylime
chown -R spire:spire /var/lib/spire /var/log/spire /run/spire /etc/spire

echo
echo "========================================="
echo "Generating configurations..."
echo "========================================="

# Generate Keylime agent config if it doesn't exist
if [ ! -f /etc/keylime/agent.conf ]; then
    cat > /etc/keylime/agent.conf << EOF
[agent]
# Agent UUID (auto-generated on first run)
uuid = "auto"

# Agent contact information
agent_contact_ip = "0.0.0.0"
agent_contact_port = 9002

# Registrar configuration
registrar_ip = "registrar.keylime.funlab.casa"
registrar_port = 443
registrar_tls_enabled = true
registrar_tls_ca_cert = "/etc/keylime/certs/ca-chain.crt"
registrar_tls_client_cert = "/etc/keylime/certs/agent.crt"
registrar_tls_client_key = "/etc/keylime/certs/agent-pkcs8.key"

# Verifier configuration
verifier_ip = "verifier.keylime.funlab.casa"
verifier_port = 443
verifier_tls_enabled = true
verifier_tls_ca_cert = "/etc/keylime/certs/ca-chain.crt"

[cloud_verifier]
cloudverifier_ip = "verifier.keylime.funlab.casa"
cloudverifier_port = 443
EOF
    chown keylime:keylime /etc/keylime/agent.conf
    chmod 640 /etc/keylime/agent.conf
    echo "  ✓ Keylime agent.conf created"
else
    echo "  ✓ Keylime agent.conf already exists (not overwriting)"
fi

# Ensure ca-chain.crt exists (Rust keylime_agent PKI module hardcodes this exact filename)
# Some hosts may have ca-complete-chain.crt or ca.crt but not ca-chain.crt.
# Without it, the PKI module returns CertificateStatus::Invalid and tries to bootstrap
# via OpenBao, which fails at boot since SPIRE isn't yet attested.
if [ ! -f /etc/keylime/certs/ca-chain.crt ] && [ ! -L /etc/keylime/certs/ca-chain.crt ]; then
    if [ -f /etc/keylime/certs/ca-complete-chain.crt ]; then
        ln -sf /etc/keylime/certs/ca-complete-chain.crt /etc/keylime/certs/ca-chain.crt
        echo "  ✓ ca-chain.crt → ca-complete-chain.crt (symlink created)"
    elif [ -f /etc/keylime/certs/ca.crt ]; then
        ln -sf /etc/keylime/certs/ca.crt /etc/keylime/certs/ca-chain.crt
        echo "  ✓ ca-chain.crt → ca.crt (symlink created)"
    else
        echo "  ⚠ ca-chain.crt not found and no CA cert to link from"
        echo "    After installing certs, run:"
        echo "    ln -sf /etc/keylime/certs/ca-complete-chain.crt /etc/keylime/certs/ca-chain.crt"
    fi
else
    echo "  ✓ ca-chain.crt already exists"
fi

# Generate SPIRE agent config (only if one doesn't already exist)
if [ ! -f /etc/spire/agent.conf ]; then
    cat > /etc/spire/agent.conf << EOF
agent {
    data_dir = "/var/lib/spire/agent"
    log_level = "INFO"
    server_address = "spire.funlab.casa"
    server_port = "443"
    socket_path = "/run/spire/sockets/agent.sock"
    trust_bundle_path = "/etc/spire/bootstrap.crt"
    trust_domain = "funlab.casa"
    insecure_bootstrap = false
}

plugins {
    NodeAttestor "keylime" {
        plugin_cmd = "/usr/local/bin/keylime-attestor-agent"
        plugin_checksum = ""
        plugin_data {
            keylime_agent_host = "127.0.0.1"
            keylime_agent_port = "9002"
            keylime_agent_use_tls = true
            keylime_agent_ca_cert = "/etc/keylime/certs/ca-chain.crt"
            keylime_agent_client_cert = "/etc/keylime/certs/agent.crt"
            keylime_agent_client_key = "/etc/keylime/certs/agent-pkcs8.key"
        }
    }

    KeyManager "disk" {
        plugin_data {
            directory = "/var/lib/spire/agent"
        }
    }

    WorkloadAttestor "unix" {
        plugin_data {}
    }
}

health_checks {
    listener_enabled = true
    bind_address = "127.0.0.1"
    bind_port = "8080"
    live_path = "/live"
    ready_path = "/ready"
}
EOF
    chown spire:spire /etc/spire/agent.conf
    chmod 640 /etc/spire/agent.conf
    echo "  ✓ SPIRE agent.conf created"
else
    echo "  ✓ SPIRE agent.conf already exists (not overwriting)"
fi

echo
echo "========================================="
echo "Creating systemd services..."
echo "========================================="

# Create keylime_agent service
cat > /etc/systemd/system/keylime_agent.service << 'EOF'
[Unit]
Description=Keylime TPM Attestation Agent
Documentation=https://keylime.dev/
# Cert renewal runs first (soft dependency - if it fails at boot because
# OpenBao isn't up yet, the agent starts with existing certs anyway).
# The keylime-cert-renewal.timer retries renewal at T+10min.
After=network-online.target keylime-cert-renewal.service
Wants=network-online.target

[Service]
Type=simple
User=keylime
Group=tss
ExecStart=/usr/local/bin/keylime_agent
Restart=on-failure
RestartSec=10s
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30
Environment="RUST_LOG=keylime_agent=info"

# Required for Keylime secure storage mount
AmbientCapabilities=CAP_SYS_ADMIN

# Health check: wait for agent to be listening before declaring service started
ExecStartPost=/bin/bash -c 'for i in {1..30}; do ss -tln | grep -q ":9002 " && exit 0; sleep 1; done; exit 1'

[Install]
WantedBy=multi-user.target
EOF
echo "  ✓ keylime_agent.service created"

# Create spire-agent service
cat > /etc/systemd/system/spire-agent.service << 'EOF'
[Unit]
Description=SPIRE Agent
Documentation=https://spiffe.io/docs/latest/spire/
# Soft dependency on keylime_agent: SPIRE needs Keylime to attest, but we
# don't use Requires= so a keylime boot failure doesn't permanently block SPIRE.
# SPIRE will retry (Restart=on-failure) once keylime is healthy.
After=network-online.target keylime_agent.service
Wants=network-online.target

[Service]
Type=exec
User=spire
Group=spire
ExecStart=/usr/local/bin/spire-agent run -config /etc/spire/agent.conf
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
echo "  ✓ spire-agent.service created"

# Create cert renewal service
cat > /etc/systemd/system/keylime-cert-renewal.service << 'EOF'
[Unit]
Description=Renew Keylime Agent Certificates
Documentation=https://keylime.dev/
# Must complete before the agent starts so fresh certs are used if available.
# If this fails (OpenBao not up yet at boot), the agent starts with existing
# certs. The keylime-cert-renewal.timer retries at T+10min.
Before=keylime_agent.service
After=network-online.target nss-lookup.target
Wants=network-online.target nss-lookup.target

[Service]
Type=oneshot
# Wait for DNS before attempting renewal
ExecStartPre=/bin/bash -c 'for i in {1..30}; do getent hosts openbao.funlab.casa >/dev/null 2>&1 && exit 0; sleep 2; done; exit 1'
ExecStart=/usr/local/bin/renew-keylime-certs.sh
RemainAfterExit=no
SuccessExitStatus=0

[Install]
WantedBy=multi-user.target
EOF
echo "  ✓ keylime-cert-renewal.service created"

# Create cert renewal timer
cat > /etc/systemd/system/keylime-cert-renewal.timer << 'EOF'
[Unit]
Description=Periodic Keylime Certificate Renewal
Documentation=https://keylime.dev/

[Timer]
# Retry 10 minutes after boot - by then SPIRE has attested and OpenBao is
# unsealed, so renewal succeeds even if the boot-time attempt failed.
OnBootSec=10min
# Renew every 12 hours (certs are 24h, giving a comfortable buffer).
OnUnitActiveSec=12h
# Spread requests if multiple hosts reboot together.
RandomizedDelaySec=3min
# Always catch up if the system was off during a scheduled run.
Persistent=true

[Install]
WantedBy=timers.target
EOF
echo "  ✓ keylime-cert-renewal.timer created (retries at T+10min, then every 12h)"

# Create post-installation verification service
cat > /etc/systemd/system/keylime-verify.service << 'EOF'
[Unit]
Description=Keylime Post-Installation Verification
After=keylime_agent.service spire-agent.service
Wants=keylime_agent.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/keylime-verify
StandardOutput=journal
StandardError=journal
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
echo "  ✓ keylime-verify.service created"

# Create verification timer (daily checks)
cat > /etc/systemd/system/keylime-verify.timer << 'EOF'
[Unit]
Description=Daily Keylime Verification
Requires=keylime-verify.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=1d
Unit=keylime-verify.service

[Install]
WantedBy=timers.target
EOF
echo "  ✓ keylime-verify.timer created (daily health checks)"

# Create SPIRE CA update service
cat > /etc/systemd/system/update-spire-ca.service << 'EOF'
[Unit]
Description=Update SPIRE CA bundle
After=spire-agent.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-spire-ca.sh
EOF
echo "  ✓ update-spire-ca.service created"

# Create SPIRE CA update timer (every 6 hours)
cat > /etc/systemd/system/update-spire-ca.timer << 'EOF'
[Unit]
Description=Update SPIRE CA bundle timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=6h

[Install]
WantedBy=timers.target
EOF
echo "  ✓ update-spire-ca.timer created (automatic CA bundle updates)"

# Reload systemd
systemctl daemon-reload
echo "  ✓ Systemd daemon reloaded"

echo
echo "========================================="
echo "Enabling and starting services..."
echo "========================================="

# Enable services
systemctl enable keylime_agent.service
echo "  ✓ keylime_agent.service enabled"

systemctl enable spire-agent.service
echo "  ✓ spire-agent.service enabled"

systemctl enable keylime-cert-renewal.timer
echo "  ✓ keylime-cert-renewal.timer enabled (boot retry + every 12h)"

systemctl enable keylime-verify.timer
echo "  ✓ keylime-verify.timer enabled (daily health checks)"

systemctl enable update-spire-ca.timer
echo "  ✓ update-spire-ca.timer enabled (automatic CA bundle updates)"

# Start cert renewal timer immediately
systemctl start keylime-cert-renewal.timer
echo "  ✓ keylime-cert-renewal.timer started"

# Start keylime agent if certificates exist
if [ -f /etc/keylime/certs/agent.crt ] && [ -f /etc/keylime/certs/agent-pkcs8.key ]; then
    echo
    echo "Keylime certificates found, attempting renewal then starting agent..."
    # Best-effort renewal now; timer handles it if this fails
    systemctl start keylime-cert-renewal.service 2>/dev/null || \
        echo "  (Renewal skipped - OpenBao not yet accessible, timer will retry at T+10min)"
    systemctl start keylime_agent.service
    echo "  ✓ keylime_agent.service started"
else
    echo
    echo "NOTE: Keylime certificates not found. Install them to /etc/keylime/certs/"
    echo "      then start: sudo systemctl start keylime_agent"
fi

# Start SPIRE agent if trust bundle exists
if [ -f /etc/spire/bootstrap.crt ]; then
    echo
    echo "SPIRE trust bundle found, starting agent..."
    sleep 5
    systemctl start spire-agent
    echo "  ✓ spire-agent.service started"
else
    echo
    echo "NOTE: SPIRE trust bundle missing — should have been in the bundle."
    echo "      Then start: sudo systemctl start spire-agent"
fi

# Start remaining timers
systemctl start keylime-verify.timer
echo "  ✓ keylime-verify.timer started"
systemctl start update-spire-ca.timer
echo "  ✓ update-spire-ca.timer started"

# Run initial CA bundle update
if [ -x /usr/local/bin/update-spire-ca.sh ]; then
    /usr/local/bin/update-spire-ca.sh
    echo "  ✓ Initial SPIRE CA bundle installed to system trust"
fi

echo
echo "========================================="
echo "Running post-installation verification..."
echo "========================================="

# Wait for services to stabilize
echo "Waiting for services to stabilize..."
sleep 10

# Run verification
if systemctl is-active --quiet keylime_agent; then
    systemctl start keylime-verify.service || true
    echo
    journalctl -u keylime-verify.service -n 100 --no-pager
else
    echo "⚠ Keylime agent not running - skipping verification"
    echo "  Start the agent after installing certificates, then run:"
    echo "  sudo systemctl start keylime-verify"
fi

echo
echo "========================================="
echo "Installation Summary"
echo "========================================="
echo
echo "Installed binaries:"
ls -lh /usr/local/bin/{keylime_agent,spire-agent,spire-server,keylime-attestor-*,keylime-verify} 2>/dev/null | awk '{printf "  %-45s %s\n", $9, "(" $5 ")"}'

echo
echo "Created users:"
echo "  keylime (uid=$(id -u keylime), groups=$(id -Gn keylime))"
echo "  spire   (uid=$(id -u spire), groups=$(id -Gn spire))"

echo
echo "Configuration files:"
echo "  /etc/keylime/agent.conf  - Keylime agent configuration"
echo "  /etc/spire/agent.conf    - SPIRE agent with Keylime attestation"
echo "  /etc/spire/bootstrap.crt - SPIRE trust bundle"

echo
echo "Services (enabled):"
systemctl is-enabled keylime_agent.service spire-agent.service \
    keylime-cert-renewal.timer keylime-verify.timer 2>/dev/null | awk '{print "  " $0}'

echo
echo "Health monitoring:"
echo "  ✓ Cert renewal timer: keylime-cert-renewal.timer"
echo "    Retries at T+10min after boot, then every 12h (certs are 24h)"
echo "  ✓ SPIRE CA bundle auto-update: update-spire-ca.timer (every 6h)"
echo "  ✓ Daily verification: keylime-verify.timer (5min after boot + daily)"
echo "  ✓ View cert renewal: sudo journalctl -u keylime-cert-renewal"
echo "  ✓ View verify results: sudo journalctl -u keylime-verify"

echo
echo "========================================="
echo "✅ Installation Complete!"
echo "========================================="
echo
echo "Next steps to complete setup:"
echo

if [ ! -f /etc/keylime/certs/agent.crt ]; then
    echo "1. Install Keylime certificates to /etc/keylime/certs/"
    echo "   (agent.crt, agent-pkcs8.key, ca.crt)"
    echo
    echo "2. Start Keylime agent:"
    echo "   sudo systemctl start keylime_agent"
    echo "   sudo systemctl status keylime_agent"
    echo
fi

echo "3. Verify everything is working:"
echo "   sudo systemctl start keylime-verify"
echo "   sudo journalctl -u keylime-verify -n 100"
echo
echo "4. Check SPIRE SVID generation:"
echo "   sudo /usr/local/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock"
echo
echo "For detailed setup:"
echo "  $BUNDLE_DIR/README.md"
echo "  $BUNDLE_DIR/POST_INSTALL_CHECKLIST.md"
echo
echo "Health checks are running daily automatically!"
echo
