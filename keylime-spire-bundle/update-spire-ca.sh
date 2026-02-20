#!/bin/bash
# Update SPIRE CA bundle in system trust store

SVID_DIR="/var/lib/spire/svids/$(hostname -s)-client"
CA_FILE="/usr/local/share/ca-certificates/spire-funlab-casa.crt"

# Ensure SVID directory exists
mkdir -p "$SVID_DIR"

# Fetch fresh SVID (includes current CA bundle)
/usr/local/bin/spire-agent api fetch x509 \
  -socketPath /run/spire/sockets/agent.sock \
  -write "$SVID_DIR" >/dev/null 2>&1

# Update system CA if bundle changed
if [ -f "$SVID_DIR/bundle.0.pem" ]; then
    if ! cmp -s "$SVID_DIR/bundle.0.pem" "$CA_FILE" 2>/dev/null; then
        cp "$SVID_DIR/bundle.0.pem" "$CA_FILE"
        update-ca-certificates
        echo "$(date): SPIRE CA bundle updated"
    fi
fi
