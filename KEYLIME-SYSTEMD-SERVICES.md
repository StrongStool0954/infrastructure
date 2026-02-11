# Keylime Systemd Services

**Date:** 2026-02-11  
**Status:** ✅ OPERATIONAL  
**Purpose:** Systemd service units for Keylime Verifier and Registrar

---

## Overview

Created systemd service units for Keylime infrastructure services to ensure automatic startup on boot and proper service management.

---

## Service Files Created

### 1. Keylime Verifier Service

**Location:** `/etc/systemd/system/keylime_verifier.service`

```ini
[Unit]
Description=Keylime Verifier
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/keylime_verifier
Restart=on-failure
RestartSec=10s
Environment="RUST_LOG=keylime_verifier=info"
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

### 2. Keylime Registrar Service

**Location:** `/etc/systemd/system/keylime_registrar.service`

```ini
[Unit]
Description=Keylime Registrar
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/keylime_registrar
Restart=on-failure
RestartSec=10s
Environment="RUST_LOG=keylime_registrar=info"
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

---

## Service Management

### Check Status
```bash
sudo systemctl status keylime_verifier
sudo systemctl status keylime_registrar
```

### Start/Stop Services
```bash
# Start
sudo systemctl start keylime_verifier
sudo systemctl start keylime_registrar

# Stop
sudo systemctl stop keylime_verifier
sudo systemctl stop keylime_registrar

# Restart
sudo systemctl restart keylime_verifier
sudo systemctl restart keylime_registrar
```

### Enable/Disable Automatic Startup
```bash
# Enable (already done)
sudo systemctl enable keylime_verifier
sudo systemctl enable keylime_registrar

# Disable
sudo systemctl disable keylime_verifier
sudo systemctl disable keylime_registrar
```

### View Logs
```bash
# Real-time logs
sudo journalctl -u keylime_verifier -f
sudo journalctl -u keylime_registrar -f

# Recent logs
sudo journalctl -u keylime_verifier -n 50
sudo journalctl -u keylime_registrar -n 50

# Logs since boot
sudo journalctl -u keylime_verifier -b
sudo journalctl -u keylime_registrar -b
```

---

## Service Configuration

### Features

- **Automatic Restart:** Services restart automatically on failure (10s delay)
- **Network Dependency:** Services wait for network before starting
- **Logging:** All output captured to systemd journal
- **Boot Startup:** Enabled to start automatically on system boot

### Ports

- Keylime Verifier: **8881** (HTTPS)
- Keylime Registrar: **8891** (TLS)

### Nginx Reverse Proxy

Both services are accessible via nginx reverse proxy on port 443:

- `https://verifier.keylime.funlab.casa` → localhost:8881
- `https://registrar.keylime.funlab.casa` → localhost:8891

---

## Verification

### Service Status
```bash
systemctl is-active keylime_verifier
systemctl is-active keylime_registrar
# Should return: active
```

### Check Listening Ports
```bash
sudo ss -tlnp | grep -E '8881|8891'
# Should show both services listening
```

### Test Endpoints
```bash
curl -k https://verifier.keylime.funlab.casa/version
curl -k https://registrar.keylime.funlab.casa/version
# Both should return JSON with version 2.5
```

---

## Current Status

```
● keylime_verifier.service - Keylime Verifier
   Loaded: loaded (/etc/systemd/system/keylime_verifier.service; enabled)
   Active: active (running)
   
● keylime_registrar.service - Keylime Registrar
   Loaded: loaded (/etc/systemd/system/keylime_registrar.service; enabled)
   Active: active (running)
```

---

## Benefits

✅ **Automatic Startup** - Services start on boot  
✅ **Process Management** - Systemd handles lifecycle  
✅ **Automatic Recovery** - Restarts on failure  
✅ **Centralized Logging** - Logs via journalctl  
✅ **Service Dependencies** - Proper network ordering  

---

## Notes

- Both services run as root (required for TPM access)
- Services use Python multiprocessing (multiple processes per service)
- Configuration files remain at `/etc/keylime/verifier.conf` and `/etc/keylime/registrar.conf`
- Services integrate with nginx reverse proxy for standard HTTPS port access

---

**Status:** Production ready! Services will survive reboots and automatically recover from failures. 🎉
