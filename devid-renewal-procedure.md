# TPM DevID Certificate Renewal Procedure

**Owner:** Infrastructure Team
**Last Updated:** 2026-02-10
**Review Cycle:** Quarterly

---

## Overview

TPM DevID certificates are issued with a **90-day validity period** to balance security with operational overhead. This document describes the renewal process for DevID certificates across all Tower of Omens hosts.

---

## Certificate Lifecycle

### Current DevID Certificates

| Host | Certificate Path | Issued | Expires | Renewal Due |
|------|-----------------|--------|---------|-------------|
| auth.funlab.casa | /var/lib/tpm2-devid/devid.crt | 2026-02-10 | 2026-05-11 | ~2026-05-01 |
| ca.funlab.casa | /var/lib/tpm2-devid/devid.crt | 2026-02-10 | 2026-05-11 | ~2026-05-01 |
| spire.funlab.casa | /var/lib/tpm2-devid/devid.crt | 2026-02-10 | 2026-05-11 | ~2026-05-01 |

**Renewal Window:** 10-15 days before expiration
**Certificate Validity:** 90 days (2160 hours)
**Alert Threshold:** 30 days before expiration

---

## Renewal Process

### Prerequisites

**Required Access:**
- SSH access to all hosts (auth, ca, spire)
- sudo privileges on all hosts
- Access to step-ca on ca.funlab.casa

**Required Tools:**
- tpm2-tools (installed on all hosts)
- openssl (installed on all hosts)
- step CLI (installed on ca host)

---

### Manual Renewal (Per Host)

#### Step 1: Generate New CSR

**On target host (e.g., auth.funlab.casa):**

```bash
# Navigate to DevID directory
cd /var/lib/tpm2-devid

# Backup existing certificate
sudo cp devid.crt devid.crt.old

# Generate temporary key for CSR
sudo openssl ecparam -name prime256v1 -genkey -out temp-devid.key

# Create CSR with updated dates
sudo openssl req -new -key temp-devid.key -out devid-renewal.csr \
  -subj '/CN=auth.funlab.casa/O=Tower of Omens/OU=DevID/C=US'

# Verify CSR
sudo openssl req -in devid-renewal.csr -noout -text
```

**Expected Output:**
- CSR file: `devid-renewal.csr`
- Subject: CN=auth.funlab.casa, O=Tower of Omens, OU=DevID, C=US

---

#### Step 2: Sign CSR with step-ca

**Copy CSR to CA host:**

```bash
# From your workstation
HOST=auth  # or ca, or spire
scp $HOST:/var/lib/tpm2-devid/devid-renewal.csr /tmp/$HOST-devid-renewal.csr
scp /tmp/$HOST-devid-renewal.csr ca:/tmp/$HOST-devid-renewal.csr
```

**On ca.funlab.casa, sign the CSR:**

```bash
# Sign CSR with step-ca
sudo -u step step certificate sign /tmp/$HOST-devid-renewal.csr \
  /etc/step-ca/certs/intermediate_ca.crt \
  /etc/step-ca/secrets/intermediate_ca_key \
  --profile leaf \
  --not-after 2160h \
  --bundle > /tmp/$HOST-devid-renewed.crt

# Verify new certificate
sudo -u step openssl x509 -in /tmp/$HOST-devid-renewed.crt -noout -dates -subject
```

**Expected Output:**
```
subject=CN=auth.funlab.casa, O=Tower of Omens, OU=DevID, C=US
notBefore=<current date>
notAfter=<current date + 90 days>
```

---

#### Step 3: Install Renewed Certificate

**Copy certificate back to host:**

```bash
# From your workstation
scp ca:/tmp/$HOST-devid-renewed.crt /tmp/$HOST-devid-renewed.crt
scp /tmp/$HOST-devid-renewed.crt $HOST:/tmp/$HOST-devid-renewed.crt
```

**On target host, install certificate:**

```bash
# Install new certificate
sudo cp /tmp/$HOST-devid-renewed.crt /var/lib/tpm2-devid/devid.crt

# Set proper permissions
sudo chown root:tss /var/lib/tpm2-devid/devid.crt
sudo chmod 640 /var/lib/tpm2-devid/devid.crt

# Verify installation
sudo openssl x509 -in /var/lib/tpm2-devid/devid.crt -noout -dates -subject

# Clean up temporary files
sudo rm /tmp/$HOST-devid-renewed.crt
sudo rm /var/lib/tpm2-devid/temp-devid.key
sudo rm /var/lib/tpm2-devid/devid-renewal.csr
```

---

#### Step 4: Restart SPIRE Agent (If Using TPM Attestation)

**⚠️ Note:** Only required after migrating to tpm_devid attestation (Sprint 3)

```bash
# Check if SPIRE is using TPM attestation
sudo grep -q "tpm" /etc/spire/agent.conf && echo "Using TPM attestation" || echo "Not using TPM attestation"

# If using TPM attestation, restart SPIRE agent
sudo systemctl restart spire-agent

# Verify agent health
sleep 5
curl -s http://127.0.0.1:8088/ready

# Verify agent attestation
sudo /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock
```

**Expected Output:**
- Health check: `{"agent":{}}`
- SVID fetch: Success with valid SPIFFE ID

---

#### Step 5: Verify Certificate Chain

```bash
# Verify certificate chain on host
sudo openssl verify \
  -CAfile /etc/step-ca/certs/root_ca.crt \
  -untrusted /etc/step-ca/certs/intermediate_ca.crt \
  /var/lib/tpm2-devid/devid.crt
```

**Expected Output:**
```
/var/lib/tpm2-devid/devid.crt: OK
```

---

### Automated Renewal Script

**Location:** `/usr/local/bin/renew-devid-cert.sh`

```bash
#!/bin/bash
# TPM DevID Certificate Renewal Script
# Usage: sudo /usr/local/bin/renew-devid-cert.sh

set -euo pipefail

# Configuration
DEVID_DIR="/var/lib/tpm2-devid"
HOSTNAME=$(hostname -f)
BACKUP_DIR="/var/lib/tpm2-devid/backups"
CA_HOST="ca.funlab.casa"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
   exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup existing certificate
log "Backing up existing certificate..."
BACKUP_FILE="$BACKUP_DIR/devid.crt.$(date +%Y%m%d-%H%M%S)"
cp "$DEVID_DIR/devid.crt" "$BACKUP_FILE"
log "Backup saved to: $BACKUP_FILE"

# Check current certificate expiry
EXPIRY=$(openssl x509 -in "$DEVID_DIR/devid.crt" -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
CURRENT_EPOCH=$(date +%s)
DAYS_UNTIL_EXPIRY=$(( ($EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))

log "Current certificate expires in $DAYS_UNTIL_EXPIRY days ($EXPIRY)"

if [[ $DAYS_UNTIL_EXPIRY -gt 30 ]]; then
    warn "Certificate still valid for $DAYS_UNTIL_EXPIRY days. Consider renewing closer to expiry."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Renewal cancelled"
        exit 0
    fi
fi

# Generate temporary key and CSR
log "Generating new CSR..."
cd "$DEVID_DIR"
openssl ecparam -name prime256v1 -genkey -out temp-devid.key 2>/dev/null
openssl req -new -key temp-devid.key -out devid-renewal.csr \
    -subj "/CN=$HOSTNAME/O=Tower of Omens/OU=DevID/C=US" 2>/dev/null

# Copy CSR to CA host
log "Copying CSR to CA host..."
scp -q devid-renewal.csr "$CA_HOST:/tmp/$(hostname -s)-devid-renewal.csr"

# Sign CSR on CA host
log "Signing CSR with step-ca..."
ssh "$CA_HOST" "sudo -u step step certificate sign \
    /tmp/$(hostname -s)-devid-renewal.csr \
    /etc/step-ca/certs/intermediate_ca.crt \
    /etc/step-ca/secrets/intermediate_ca_key \
    --profile leaf \
    --not-after 2160h \
    --bundle > /tmp/$(hostname -s)-devid-renewed.crt"

# Retrieve signed certificate
log "Retrieving signed certificate..."
scp -q "$CA_HOST:/tmp/$(hostname -s)-devid-renewed.crt" "$DEVID_DIR/devid.crt.new"

# Verify new certificate
log "Verifying new certificate..."
NEW_EXPIRY=$(openssl x509 -in "$DEVID_DIR/devid.crt.new" -noout -enddate | cut -d= -f2)
NEW_SUBJECT=$(openssl x509 -in "$DEVID_DIR/devid.crt.new" -noout -subject | cut -d= -f2-)

if [[ ! "$NEW_SUBJECT" =~ "$HOSTNAME" ]]; then
    error "Certificate subject mismatch! Expected $HOSTNAME, got $NEW_SUBJECT"
    rm "$DEVID_DIR/devid.crt.new"
    exit 1
fi

log "New certificate expires: $NEW_EXPIRY"

# Install new certificate
log "Installing new certificate..."
mv "$DEVID_DIR/devid.crt.new" "$DEVID_DIR/devid.crt"
chown root:tss "$DEVID_DIR/devid.crt"
chmod 640 "$DEVID_DIR/devid.crt"

# Clean up temporary files
rm -f "$DEVID_DIR/temp-devid.key" "$DEVID_DIR/devid-renewal.csr"
ssh "$CA_HOST" "rm -f /tmp/$(hostname -s)-devid-renewal.csr /tmp/$(hostname -s)-devid-renewed.crt"

# Check if SPIRE is using TPM attestation
if grep -q "tpm" /etc/spire/agent.conf 2>/dev/null; then
    log "SPIRE is using TPM attestation, restarting agent..."
    systemctl restart spire-agent
    sleep 5

    # Verify SPIRE agent health
    if curl -s http://127.0.0.1:8088/ready | grep -q "agent"; then
        log "SPIRE agent restarted successfully"
    else
        error "SPIRE agent health check failed!"
        error "Restoring backup certificate..."
        cp "$BACKUP_FILE" "$DEVID_DIR/devid.crt"
        systemctl restart spire-agent
        exit 1
    fi
else
    log "SPIRE not using TPM attestation, no restart needed"
fi

log "✅ DevID certificate renewal complete!"
log "Old certificate backed up to: $BACKUP_FILE"
log "New certificate expires: $NEW_EXPIRY"
```

**Installation:**

```bash
# On each host
sudo tee /usr/local/bin/renew-devid-cert.sh > /dev/null << 'SCRIPT'
# ... paste script content above ...
SCRIPT

sudo chmod +x /usr/local/bin/renew-devid-cert.sh
```

---

### Monitoring Certificate Expiry

**Create monitoring script:** `/usr/local/bin/check-devid-expiry.sh`

```bash
#!/bin/bash
# Check DevID certificate expiry and alert if needed

CERT_FILE="/var/lib/tpm2-devid/devid.crt"
WARN_DAYS=30

if [[ ! -f "$CERT_FILE" ]]; then
    echo "ERROR: DevID certificate not found at $CERT_FILE"
    exit 2
fi

EXPIRY=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
CURRENT_EPOCH=$(date +%s)
DAYS_UNTIL_EXPIRY=$(( ($EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))

if [[ $DAYS_UNTIL_EXPIRY -lt 0 ]]; then
    echo "CRITICAL: DevID certificate EXPIRED $((DAYS_UNTIL_EXPIRY * -1)) days ago!"
    exit 2
elif [[ $DAYS_UNTIL_EXPIRY -lt 7 ]]; then
    echo "CRITICAL: DevID certificate expires in $DAYS_UNTIL_EXPIRY days!"
    exit 2
elif [[ $DAYS_UNTIL_EXPIRY -lt $WARN_DAYS ]]; then
    echo "WARNING: DevID certificate expires in $DAYS_UNTIL_EXPIRY days"
    exit 1
else
    echo "OK: DevID certificate valid for $DAYS_UNTIL_EXPIRY days"
    exit 0
fi
```

**Installation:**

```bash
sudo tee /usr/local/bin/check-devid-expiry.sh > /dev/null << 'SCRIPT'
# ... paste script content above ...
SCRIPT

sudo chmod +x /usr/local/bin/check-devid-expiry.sh
```

**Cron job for monitoring (daily check):**

```bash
# Add to /etc/cron.d/devid-monitoring
0 9 * * * root /usr/local/bin/check-devid-expiry.sh || logger -t devid-cert "$(hostname): $(/usr/local/bin/check-devid-expiry.sh)"
```

---

### Automated Renewal via Cron

**Option 1: Scheduled renewal (recommended)**

Renew certificates automatically 10 days before expiry:

```bash
# Add to /etc/cron.d/devid-renewal
# Run renewal script daily at 2 AM, will only renew if within 30 days of expiry
0 2 * * * root /usr/local/bin/check-devid-expiry.sh | grep -q "WARNING\|CRITICAL" && /usr/local/bin/renew-devid-cert.sh >> /var/log/devid-renewal.log 2>&1
```

**Option 2: Manual trigger (more control)**

Set up monitoring alerts and manually trigger renewal when needed.

---

## Troubleshooting

### Issue: CSR Generation Fails

**Symptoms:**
- `openssl req` command fails
- Permission denied errors

**Resolution:**
```bash
# Ensure running as root
sudo su -

# Check directory permissions
ls -la /var/lib/tpm2-devid/

# Verify openssl is installed
which openssl
openssl version
```

---

### Issue: Certificate Signing Fails on CA

**Symptoms:**
- `step certificate sign` fails
- Permission denied on CA host

**Resolution:**
```bash
# On ca host, check intermediate CA files
sudo ls -la /etc/step-ca/certs/intermediate_ca.crt
sudo ls -la /etc/step-ca/secrets/intermediate_ca_key

# Verify step user permissions
sudo -u step step version

# Check step-ca is running
sudo systemctl status step-ca
```

---

### Issue: SPIRE Agent Fails After Renewal

**Symptoms:**
- Agent health check fails after certificate renewal
- SVIDs not being issued

**Resolution:**
```bash
# Restore backup certificate
sudo cp /var/lib/tpm2-devid/backups/devid.crt.<timestamp> \
    /var/lib/tpm2-devid/devid.crt

# Restart SPIRE agent
sudo systemctl restart spire-agent

# Check agent logs
sudo journalctl -u spire-agent -n 50

# Verify agent can attest
sudo /opt/spire/bin/spire-agent api fetch x509 \
    -socketPath /run/spire/sockets/agent.sock
```

---

### Issue: Certificate Chain Verification Fails

**Symptoms:**
- `openssl verify` fails
- Certificate not trusted

**Resolution:**
```bash
# Ensure CA certificates are present
sudo ls -la /etc/step-ca/certs/root_ca.crt
sudo ls -la /etc/step-ca/certs/intermediate_ca.crt

# Download CA certs from ca host if missing
scp ca:/etc/step-ca/certs/root_ca.crt /tmp/
scp ca:/etc/step-ca/certs/intermediate_ca.crt /tmp/
sudo mkdir -p /etc/step-ca/certs
sudo cp /tmp/root_ca.crt /etc/step-ca/certs/
sudo cp /tmp/intermediate_ca.crt /etc/step-ca/certs/

# Verify chain
sudo openssl verify -CAfile /etc/step-ca/certs/root_ca.crt \
    -untrusted /etc/step-ca/certs/intermediate_ca.crt \
    /var/lib/tpm2-devid/devid.crt
```

---

## Emergency Procedures

### Mass Renewal (All Hosts)

**When needed:**
- Approaching expiry on all hosts
- CA key rotation
- Policy changes

**Process:**

```bash
# From your workstation
for HOST in auth ca spire; do
    echo "=== Renewing DevID certificate on $HOST ==="
    ssh $HOST "sudo /usr/local/bin/renew-devid-cert.sh"
    echo
done
```

---

### Certificate Revocation

**When needed:**
- Host compromised
- Key material suspected leaked
- Host decommissioned

**Process:**

1. **Revoke certificate in step-ca:**
   ```bash
   # On ca host
   sudo -u step step ca revoke --cert /path/to/devid.crt
   ```

2. **Remove from host:**
   ```bash
   # On affected host
   sudo rm /var/lib/tpm2-devid/devid.crt
   ```

3. **Update SPIRE configuration:**
   - Remove host from SPIRE agent list
   - Revoke agent SPIFFE ID
   - Remove workload entries

---

## Checklist

### Pre-Renewal Checklist
- [ ] Verify current certificate expiry date
- [ ] Confirm renewal window (30 days before expiry)
- [ ] Ensure CA (ca.funlab.casa) is accessible
- [ ] Verify SSH access to all hosts
- [ ] Check SPIRE agent status

### Renewal Checklist (Per Host)
- [ ] Backup existing certificate
- [ ] Generate new CSR
- [ ] Sign CSR with step-ca
- [ ] Verify new certificate validity
- [ ] Install new certificate
- [ ] Set proper file permissions
- [ ] Restart SPIRE agent (if using TPM attestation)
- [ ] Verify SPIRE agent health
- [ ] Test SVID issuance
- [ ] Clean up temporary files

### Post-Renewal Checklist
- [ ] Verify all hosts have renewed certificates
- [ ] Update monitoring/tracking systems
- [ ] Document renewal in change log
- [ ] Schedule next renewal
- [ ] Archive old certificates

---

## References

- [TPM DevID Provisioning Documentation](sprint-2-phase-3-complete.md)
- [SPIRE TPM Attestation Plan](tower-of-omens-tpm-attestation-plan.md)
- [step-ca Certificate Management](https://smallstep.com/docs/step-ca/)
- [TPM 2.0 Specification](https://trustedcomputinggroup.org/resource/tpm-library-specification/)

---

**Document Version:** 1.0
**Last Reviewed:** 2026-02-10
**Next Review:** 2026-05-01 (before certificate expiry)
