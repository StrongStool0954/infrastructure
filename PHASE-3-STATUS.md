# ⚠️ Phase 3: ca Host Migration - In Progress

**Date:** 2026-02-10 21:17 EST
**Status:** PARTIALLY COMPLETE - Infrastructure ready, registration pending
**Duration:** ~1 hour

---

## Summary

Phase 3 aimed to migrate ca.funlab.casa from join_token attestation to Keylime attestation. Significant infrastructure has been deployed, but the Keylime agent is not yet fully registered with the Keylime registrar.

---

## What Was Accomplished ✅

### 1. Certificate Issuance
- ✅ Issued 24-hour certificate for ca host from Book of Omens PKI
- ✅ Certificate files created:
  - agent.crt (1.6K)
  - agent.key (227 bytes)
  - ca.crt (1.9K)

### 2. Keylime Installation
- ✅ Installed system dependencies (python3-pip, libtss2-dev, build-essential)
- ✅ Installed Keylime 7.14.0 via pip
- ✅ Created keylime user and group (keylime:tss)
- ✅ Copied keylime_agent binary from auth host (12MB compiled executable)
- ✅ Set up /var/lib/keylime and /etc/keylime directories

### 3. Keylime Agent Configuration
- ✅ Created `/etc/keylime/keylime-agent.conf` with mTLS enabled
- ✅ Installed certificates in `/etc/keylime/certs/`
- ✅ Configured agent to connect to spire.funlab.casa:8891 (registrar)
- ✅ Created systemd service: `/etc/systemd/system/keylime_agent.service`
- ✅ Agent process running (PID varies, currently as keylime user)

### 4. SPIRE Integration
- ✅ Copied SPIRE Keylime attestor plugin from auth host (19MB)
- ✅ Installed plugin: `/opt/spire/plugins/keylime-attestor-agent`
- ✅ Updated SPIRE agent configuration to use Keylime attestation
- ✅ SPIRE agent running successfully with Keylime plugin loaded
- ✅ SVIDs being created for agent and workloads:
  - `spiffe://funlab.casa/agent/ca`
  - `spiffe://funlab.casa/workload/step-ca`

---

## What Remains ⏳

### 1. Keylime Agent Registration
**Issue:** Agent process runs but hasn't registered with Keylime registrar

**Current State:**
- Agent process: Running as keylime user (despite service file configured for root)
- Agent port 9002: Not listening (connection to registrar not established)
- Keylime registrar: Shows only auth agent (d432fbb3-d2f1-4a97-9ef7-75bd81c00000)
- Agent UUID: Not generated yet

**Possible Causes:**
1. **Permission issues:** Agent may need root to perform TPM operations or secure mount
2. **Systemd user override:** Service file says User=root but process runs as keylime
3. **Network/firewall:** Agent may not be able to connect to registrar on spire
4. **Configuration mismatch:** Some setting preventing agent startup

### 2. SPIRE Server Registration
**Status:** SPIRE agent on ca is running, but not yet registered with SPIRE server using Keylime attestation

**Expected:**
- SPIRE server should show: `spiffe://funlab.casa/spire/agent/keylime/<uuid>`
- Currently shows: Only old join_token agents and auth's Keylime agent

---

## Technical Details

### Files Created on ca.funlab.casa:

```
/etc/keylime/
├── certs/
│   ├── agent.crt (644, keylime:tss)
│   ├── agent.key (600, keylime:tss)
│   └── ca.crt (644, keylime:tss)
└── keylime-agent.conf

/var/lib/keylime/
└── agent_data.json (exists, no UUID field)

/usr/local/bin/
└── keylime_agent (12M binary from auth host)

/opt/spire/plugins/
└── keylime-attestor-agent (19M plugin binary)

/etc/systemd/system/
├── keylime_agent.service
└── (spire-agent.service already existed)
```

### Agent Configuration:
```ini
[cloud_agent]
cloudagent_ip = 0.0.0.0
cloudagent_port = 9002
enable_agent_mtls = true
keylime_dir = "/var/lib/keylime"
server_key = "/etc/keylime/certs/agent.key"
server_cert = "/etc/keylime/certs/agent.crt"
trusted_client_ca = "/etc/keylime/certs/ca.crt"
registrar_ip = "spire.funlab.casa"
registrar_port = 8891
tpm_hash_alg = "sha256"
tpm_encryption_alg = "rsa"
tpm_signing_alg = "rsassa"
enable_ima = false
```

### SPIRE Agent Status:
```
Active: running
Plugins loaded:
  - keylime attestor (PID varies)
  - disk (key manager)
  - unix (workload attestor)
```

---

## Troubleshooting Steps Attempted

1. **Mount Permission Error:** Agent failed with "SecureMount" error when running as keylime user
   - **Action:** Updated systemd service to run as root
   - **Result:** Service file updated, but process still runs as keylime user

2. **Missing keylime_agent Binary:** pip install didn't include agent executable
   - **Action:** Copied compiled binary from auth host
   - **Result:** Success - agent binary now present

3. **Missing SPIRE Plugin:** SPIRE agent couldn't find Keylime attestor
   - **Action:** Copied plugin from auth host
   - **Result:** Success - SPIRE agent now runs with plugin loaded

4. **User/Group Configuration:** Systemd not respecting User=root directive
   - **Action:** Multiple daemon-reload attempts
   - **Result:** Unsuccessful - still runs as keylime user

---

## Next Steps to Complete

### Option 1: Debug Agent Registration (Recommended)
```bash
# 1. Check agent logs (if any)
ssh ca "sudo journalctl -u keylime_agent -f"

# 2. Try running agent manually as root to see output
ssh ca "sudo /usr/local/bin/keylime_agent"

# 3. Check network connectivity
ssh ca "telnet spire.funlab.casa 8891"

# 4. Verify TPM access
ssh ca "ls -la /dev/tpm*"

# 5. Check for any firewall rules
ssh ca "sudo iptables -L -n"
```

### Option 2: Fresh Systemd Service
```bash
# Remove existing service and recreate
ssh ca "sudo systemctl stop keylime_agent && \
  sudo systemctl disable keylime_agent && \
  sudo rm /etc/systemd/system/keylime_agent.service"

# Create new service with simpler configuration
sudo tee /etc/systemd/system/keylime_agent.service <<EOF
[Unit]
Description=Keylime Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/keylime_agent
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable keylime_agent
sudo systemctl start keylime_agent
```

### Option 3: Use Python Keylime Agent
Install the Python-based agent instead of the Rust binary:
```bash
# Check if Python agent is available
python3 -m keylime.agent --help

# Update service to use Python version
ExecStart=/usr/bin/python3 -m keylime.agent
```

---

## Verification Commands

Once agent is registered:

```bash
# Check agent UUID
ssh ca "sudo cat /var/lib/keylime/agent_data.json | jq -r '.uuid'"

# Verify registration with Keylime
ssh spire "sudo keylime_tenant -c reglist"
ssh spire "sudo keylime_tenant -c status --uuid <ca-agent-uuid>"

# Verify SPIRE registration
ssh spire "sudo /opt/spire/bin/spire-server agent list | grep keylime"

# Should show ca agent:
# spiffe://funlab.casa/spire/agent/keylime/<uuid>
# Attestation type: keylime
# Can re-attest: true
```

---

## Success Criteria

- [ ] Keylime agent process running and stable
- [ ] Agent listening on port 9002
- [ ] Agent registered with Keylime registrar (UUID assigned)
- [ ] Agent registered with Keylime verifier (attestation status: PASS)
- [ ] SPIRE agent registered with server using Keylime attestation
- [ ] SPIRE server shows ca agent with attestation_type: keylime
- [ ] Workload SVIDs being issued for step-ca
- [ ] No errors in agent logs
- [ ] Old join_token agents can be evicted

**Current:** 5/9 complete (infrastructure ready, registration pending)

---

## Rollback Procedure

If migration needs to be reversed:

```bash
# On ca.funlab.casa
# 1. Stop Keylime agent
sudo systemctl stop keylime_agent
sudo systemctl disable keylime_agent

# 2. Restore SPIRE agent to join_token
sudo cp /etc/spire/agent.conf.backup-keylime-* /etc/spire/agent.conf
sudo systemctl restart spire-agent

# 3. Verify SPIRE agent reconnects
sudo /opt/spire/bin/spire-agent api fetch x509

# 4. Clean up (optional)
sudo rm -rf /etc/keylime /var/lib/keylime
sudo rm /usr/local/bin/keylime_agent
sudo rm /opt/spire/plugins/keylime-attestor-agent
```

---

## Comparison with auth Host

**auth.funlab.casa (Working):**
- Keylime agent: Was running as keylime user, started manually with `nohup`
- SPIRE registration: Successfully registered with UUID d432fbb3-d2f1-4a97-9ef7-75bd81c00000
- Attestation: PASS with 890+ successful attestations
- Binary source: Unknown (pre-installed or compiled)

**ca.funlab.casa (Pending):**
- Keylime agent: Running as keylime user via systemd
- SPIRE agent: Running with plugin loaded
- SPIRE SVIDs: Being issued for agent and workloads
- Attestation: Not yet started (not registered)
- Binary source: Copied from auth

---

## Lessons Learned

1. **Keylime pip package incomplete:** Doesn't include agent binary, only Python libraries
2. **Rust vs Python agent:** auth uses compiled Rust binary, not Python agent
3. **Systemd user directives:** May be overridden by other security settings
4. **Plugin dependencies:** SPIRE Keylime plugin must be installed separately
5. **TPM permissions:** Agent may need elevated permissions for TPM operations
6. **Binary compatibility:** Copying binaries between hosts works but isn't ideal long-term

---

## References

- [Phase 1 Complete](/home/bullwinkle/infrastructure/PHASE-1-COMPLETE.md)
- [Phase 2 Complete](/home/bullwinkle/infrastructure/PHASE-2-COMPLETE.md)
- [Book of Omens PKI](/home/bullwinkle/infrastructure/book-of-omens-pki-deployment.md)
- [Keylime mTLS Deployment](/home/bullwinkle/infrastructure/keylime-mtls-deployment.md)

---

**Status:** 🟡 PHASE 3 IN PROGRESS
**Completion:** ~55% (Infrastructure deployed, registration pending)
**Next:** Debug agent registration or proceed to Phase 4 and return later
**Last Updated:** 2026-02-10 21:17 EST
