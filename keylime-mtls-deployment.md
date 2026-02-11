# Keylime mTLS Deployment with Book of Omens Certificates

**Date:** 2026-02-10
**Status:** ⏳ CONFIGURED - Services need restart
**Achievement:** Keylime mTLS configured with Book of Omens PKI short-lived certificates

---

## Executive Summary

Successfully configured Keylime infrastructure for mTLS communication using 24-hour certificates from the Book of Omens intermediate CA. All certificates have been issued, installed, and configuration files updated to enable mTLS.

**Next Step:** Restart Keylime services to activate mTLS.

---

## What Was Accomplished

### 1. Certificates Issued ✅

All Keylime components now have 24-hour certificates from Book of Omens PKI:

**Verifier Certificate (spire host):**
```
Subject: CN=verifier.keylime.funlab.casa
Valid From: 2026-02-11 01:42:30 GMT
Valid Until: 2026-02-12 01:43:00 GMT (24 hours)
Key Type: EC P-256
Location: /etc/keylime/certs/verifier.crt
```

**Registrar Certificate (spire host):**
```
Subject: CN=registrar.keylime.funlab.casa
Valid From: 2026-02-11 01:42:31 GMT
Valid Until: 2026-02-12 01:43:01 GMT (24 hours)
Key Type: EC P-256
Location: /etc/keylime/certs/registrar.crt
```

**Agent Certificate (auth host):**
```
Subject: CN=agent.keylime.funlab.casa
Valid From: 2026-02-11 01:42:31 GMT
Valid Until: 2026-02-12 01:43:01 GMT (24 hours)
Key Type: EC P-256
Location: /etc/keylime/certs/agent.crt
```

**CA Certificate (Book of Omens):**
```
Location (spire): /etc/keylime/certs/ca.crt
Location (auth): /etc/keylime/certs/ca.crt
```

---

### 2. Certificate Installation ✅

**On spire.funlab.casa:**
```
/etc/keylime/certs/
├── ca.crt          (Book of Omens intermediate CA)
├── verifier.crt    (Verifier TLS certificate)
├── verifier.key    (Verifier private key)
├── registrar.crt   (Registrar TLS certificate)
└── registrar.key   (Registrar private key)

Permissions:
- *.crt: 644 (root:root)
- *.key: 600 (root:root)
```

**On auth.funlab.casa:**
```
/etc/keylime/certs/
├── ca.crt       (Book of Omens intermediate CA)
├── agent.crt    (Agent TLS certificate)
└── agent.key    (Agent private key)

Permissions:
- *.crt: 644 (keylime:tss)
- *.key: 600 (keylime:tss)
```

---

### 3. Configuration Updated ✅

**Verifier Configuration** (`/etc/keylime/verifier.conf`):
```ini
# Backup created: /etc/keylime/verifier.conf.backup-20260210

enable_agent_mtls = True            # Changed from: False
tls_dir = /etc/keylime/certs       # Changed from: default
server_key = verifier.key           # Changed from: default
server_cert = verifier.crt          # Changed from: default
client_key = verifier.key           # Changed from: default
client_cert = verifier.crt          # Changed from: default
trusted_client_ca = ca.crt          # Changed from: default
trusted_server_ca = ca.crt          # Changed from: default
```

**Registrar Configuration** (`/etc/keylime/registrar.conf`):
```ini
# Backup created: /etc/keylime/registrar.conf.backup-20260210

tls_dir = /etc/keylime/certs       # Changed from: default
server_key = registrar.key          # Changed from: default
server_cert = registrar.crt         # Changed from: default
trusted_client_ca = ca.crt          # Changed from: default
```

**Agent Configuration** (`/etc/keylime/keylime-agent.conf`):
```ini
# Backup created: /etc/keylime/keylime-agent.conf.backup-20260210

enable_agent_mtls = true                            # Changed from: false
server_key = "/etc/keylime/certs/agent.key"        # Changed from: "default"
server_cert = "/etc/keylime/certs/agent.crt"       # Changed from: "default"
trusted_client_ca = "/etc/keylime/certs/ca.crt"    # Changed from: "default"
```

---

## Services Restart Required

### Current Status
```
spire.funlab.casa:
├── Keylime Verifier: RUNNING (old config)
├── Keylime Registrar: RUNNING (old config)
└── Status: Config updated, restart needed

auth.funlab.casa:
├── Keylime Agent: RUNNING (old config)
└── Status: Config updated, restart needed
```

### Restart Procedure

#### Option 1: systemd (If services are configured)
```bash
# On spire host
sudo systemctl restart keylime-verifier
sudo systemctl restart keylime-registrar

# On auth host
sudo systemctl restart keylime_agent
```

#### Option 2: Manual restart (Current setup)
```bash
# On spire host - Stop services
sudo pkill -f keylime_verifier
sudo pkill -f keylime_registrar

# On spire host - Start services
sudo nohup keylime_verifier > /var/log/keylime-verifier.log 2>&1 &
sudo nohup keylime_registrar > /var/log/keylime-registrar.log 2>&1 &

# On auth host - Restart agent
sudo systemctl restart keylime_agent
# OR
sudo pkill -f keylime_agent
sudo keylime_agent &
```

#### Option 3: Full system restart (Safest)
```bash
# Restart each host to ensure clean startup
sudo reboot
```

---

## Verification & Testing

After restarting services, verify mTLS is working:

### 1. Check Service Status
```bash
# On spire host
ps aux | grep keylime

# On auth host
systemctl status keylime_agent
ps aux | grep keylime_agent
```

### 2. Check TLS Connections
```bash
# Verify verifier is listening with TLS
sudo netstat -tlnp | grep 8881

# Verify registrar is listening with TLS
sudo netstat -tlnp | grep 8891

# Verify agent is listening with TLS
sudo netstat -tlnp | grep 9002
```

### 3. Test Agent Registration
```bash
# On spire host - Check agent registration
sudo keylime_tenant -c status --uuid d432fbb3-d2f1-4a97-9ef7-75bd81c00000

# Should show:
# - operational_state: "Registered" or "Get Quote"
# - attestation_status: "PASS"
# - With TLS connection confirmation
```

### 4. Check Logs for mTLS Activity
```bash
# On spire host
sudo tail -f /var/log/keylime-verifier.log | grep -i tls
sudo tail -f /var/log/keylime-registrar.log | grep -i tls

# On auth host
sudo journalctl -u keylime_agent -f | grep -i tls
```

### 5. Verify Certificate Usage
```bash
# Check that certificates are being used
sudo lsof -i :8881 | grep python  # Verifier
sudo lsof -i :8891 | grep python  # Registrar
sudo lsof -i :9002 | grep keylime # Agent

# Verify certificate files are being accessed
sudo lsof | grep /etc/keylime/certs
```

---

## Expected Behavior After Restart

### Successful mTLS Connection
```
Verifier → Agent:
1. Verifier presents verifier.crt (signed by Book of Omens)
2. Agent validates against ca.crt (Book of Omens)
3. Agent presents agent.crt (signed by Book of Omens)
4. Verifier validates against ca.crt (Book of Omens)
5. ✅ mTLS handshake successful

Registrar → Agent:
1. Similar mutual authentication
2. ✅ mTLS handshake successful
```

### Log Indicators of Success
```
- "TLS connection established"
- "mTLS enabled"
- "Certificate validation successful"
- "Agent attestation: PASS"
```

### Log Indicators of Failure
```
- "TLS handshake failed"
- "Certificate validation failed"
- "Permission denied"
- "Connection refused"
```

---

## Troubleshooting

### Issue 1: Services won't start with mTLS enabled

**Symptoms:** Services fail to start or crash immediately

**Common Causes:**
1. Certificate file permissions incorrect
2. Certificate/key mismatch
3. CA certificate not trusted

**Solutions:**
```bash
# Verify certificate permissions
ls -la /etc/keylime/certs/

# Verify certificate validity
openssl x509 -in /etc/keylime/certs/verifier.crt -noout -text
openssl x509 -in /etc/keylime/certs/agent.crt -noout -text

# Verify certificate chain
openssl verify -CAfile /etc/keylime/certs/ca.crt /etc/keylime/certs/verifier.crt
openssl verify -CAfile /etc/keylime/certs/ca.crt /etc/keylime/certs/agent.crt

# Check certificate/key match
openssl x509 -noout -modulus -in /etc/keylime/certs/verifier.crt | openssl md5
openssl rsa -noout -modulus -in /etc/keylime/certs/verifier.key | openssl md5
# Both should match
```

### Issue 2: Agent can't connect to verifier/registrar

**Symptoms:** Agent starts but can't register

**Solutions:**
```bash
# Check network connectivity
telnet spire.funlab.casa 8881
telnet spire.funlab.casa 8891

# Check certificate dates (not expired)
openssl x509 -in /etc/keylime/certs/agent.crt -noout -dates

# Verify CA certificate is the same on both hosts
md5sum /etc/keylime/certs/ca.crt  # Run on both hosts
```

### Issue 3: Certificate expired

**Symptoms:** Connection fails with "certificate expired" error

**Solution:** Renew certificates (see Auto-Renewal section below)

---

## Auto-Renewal Setup

### Renewal Script

Create `/usr/local/bin/renew-keylime-certs.sh`:

```bash
#!/bin/bash
set -e

export BAO_ADDR=https://spire.funlab.casa:8200
export BAO_SKIP_VERIFY=true
export BAO_TOKEN=<your-token>

CERT_DIR="/etc/keylime/certs"
HOSTNAME=$(hostname -s)

echo "=== Renewing Keylime Certificate for $HOSTNAME ==="

case $HOSTNAME in
  spire)
    # Renew verifier certificate
    bao write -format=json pki_int/issue/keylime-services \
        common_name="verifier.keylime.funlab.casa" \
        alt_names="localhost" \
        ip_sans="10.10.2.62,127.0.0.1" \
        ttl="24h" | jq -r '.data.certificate' > $CERT_DIR/verifier.crt.new

    bao write -format=json pki_int/issue/keylime-services \
        common_name="verifier.keylime.funlab.casa" \
        ttl="24h" | jq -r '.data.private_key' > $CERT_DIR/verifier.key.new

    # Renew registrar certificate
    bao write -format=json pki_int/issue/keylime-services \
        common_name="registrar.keylime.funlab.casa" \
        alt_names="localhost" \
        ip_sans="10.10.2.62,127.0.0.1" \
        ttl="24h" | jq -r '.data.certificate' > $CERT_DIR/registrar.crt.new

    # Atomic replacement
    mv $CERT_DIR/verifier.crt.new $CERT_DIR/verifier.crt
    mv $CERT_DIR/registrar.crt.new $CERT_DIR/registrar.crt

    # Restart services
    pkill -HUP keylime_verifier
    pkill -HUP keylime_registrar
    ;;

  auth)
    # Renew agent certificate
    bao write -format=json pki_int/issue/keylime-services \
        common_name="agent.keylime.funlab.casa" \
        alt_names="localhost" \
        ip_sans="10.10.2.70,127.0.0.1" \
        ttl="24h" | jq -r '.data.certificate' > $CERT_DIR/agent.crt.new

    # Atomic replacement
    mv $CERT_DIR/agent.crt.new $CERT_DIR/agent.crt
    chown keylime:tss $CERT_DIR/agent.crt

    # Restart agent
    systemctl reload keylime_agent
    ;;
esac

echo "✅ Certificates renewed"
```

### Systemd Timer for Auto-Renewal

Create `/etc/systemd/system/renew-keylime-certs.service`:
```ini
[Unit]
Description=Renew Keylime mTLS certificates
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/renew-keylime-certs.sh
User=root
```

Create `/etc/systemd/system/renew-keylime-certs.timer`:
```ini
[Unit]
Description=Renew Keylime certificates daily

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
```

Enable the timer:
```bash
sudo systemctl enable --now renew-keylime-certs.timer
```

---

## Security Benefits

### Before mTLS (Insecure)
```
Agent → Verifier: Unencrypted communication
Registrar → Agent: Unencrypted communication
Verifier → Agent: No mutual authentication
Risk: Man-in-the-middle attacks, eavesdropping
```

### After mTLS (Secure)
```
Agent ↔ Verifier: Encrypted + Mutual authentication
Registrar ↔ Agent: Encrypted + Mutual authentication
Verifier ↔ Agent: Both parties verify each other
Benefits:
- ✅ End-to-end encryption
- ✅ Mutual authentication
- ✅ Protection against MITM attacks
- ✅ Short-lived certificates (24 hours)
- ✅ Hardware-backed trust (TPM + PKI)
```

---

## Summary

### What We Built

✅ **Keylime mTLS Infrastructure**
- 3 certificates issued (verifier, registrar, agent)
- 24-hour validity period
- EC P-256 keys for performance

✅ **Certificate Installation**
- Proper file locations and permissions
- Separate certs for each component
- Trusted CA certificate distributed

✅ **Configuration Updated**
- mTLS enabled on all components
- Custom certificate paths configured
- Backup configurations created

⏳ **Pending**
- Services need restart to activate mTLS
- Testing and verification
- Auto-renewal implementation

### Benefits Achieved

1. **Secure Communication:** All Keylime traffic will be encrypted
2. **Mutual Authentication:** Both parties verify each other
3. **Short-Lived Certificates:** 24-hour TTL reduces compromise window
4. **Automated Issuance:** OpenBao PKI for easy renewal
5. **Hardware-Backed:** TPM attestation + PKI trust chain

### Next Steps

1. **Restart Keylime services** to activate mTLS
2. **Test connections** and verify mTLS is working
3. **Implement auto-renewal** for 24-hour certificates
4. **Monitor logs** for any issues
5. **Document any troubleshooting** needed

---

## Quick Reference

### Certificate Locations

```
spire.funlab.casa:
├── /etc/keylime/certs/verifier.crt
├── /etc/keylime/certs/verifier.key
├── /etc/keylime/certs/registrar.crt
├── /etc/keylime/certs/registrar.key
└── /etc/keylime/certs/ca.crt

auth.funlab.casa:
├── /etc/keylime/certs/agent.crt
├── /etc/keylime/certs/agent.key
└── /etc/keylime/certs/ca.crt
```

### Configuration Files

```
spire.funlab.casa:
├── /etc/keylime/verifier.conf
├── /etc/keylime/registrar.conf
├── /etc/keylime/verifier.conf.backup-20260210
└── /etc/keylime/registrar.conf.backup-20260210

auth.funlab.casa:
├── /etc/keylime/keylime-agent.conf
└── /etc/keylime/keylime-agent.conf.backup-20260210
```

### Common Commands

```bash
# Check certificate validity
openssl x509 -in /etc/keylime/certs/agent.crt -noout -dates

# Verify certificate chain
openssl verify -CAfile /etc/keylime/certs/ca.crt /etc/keylime/certs/agent.crt

# Check service status
ps aux | grep keylime

# View logs
sudo tail -f /var/log/keylime-verifier.log
sudo journalctl -u keylime_agent -f

# Test connectivity
telnet spire.funlab.casa 8881
telnet spire.funlab.casa 8891
```

---

**Deployment Status:** ✅ CONFIGURED (restart pending)
**Next Action:** Restart Keylime services to activate mTLS
**Priority:** Test mTLS connections after restart
**Last Updated:** 2026-02-10 20:48 EST
