# Nginx Automation - Certificate Renewal & Monitoring

**Date:** 2026-02-11  
**Status:** ✅ OPERATIONAL  
**Purpose:** Automated certificate renewal and service monitoring for nginx reverse proxy

---

## Overview

Implemented automated systems for nginx infrastructure maintenance:
1. **Automated Certificate Renewal** - Weekly renewal of SSL certificates from OpenBao PKI
2. **Service Monitoring** - Continuous health checks with auto-recovery capabilities

---

## Automated Certificate Renewal

### Purpose
Automatically renew nginx SSL certificates before they expire, ensuring uninterrupted service.

### Implementation

**Script:** `/usr/local/bin/renew-nginx-certs.sh`

**Features:**
- Renews both OpenBao and Keylime certificates
- Automatic backup of existing certificates (keeps last 5)
- Validates nginx configuration before applying changes
- Automatic rollback on failure
- Comprehensive logging to `/var/log/nginx-cert-renewal.log`
- Graceful nginx reload (no downtime)

**Certificates Renewed:**
1. OpenBao services certificate (openbao.funlab.casa, spire.funlab.casa, keylime.funlab.casa)
2. Keylime services certificate (verifier.keylime.funlab.casa, registrar.keylime.funlab.casa)

### Systemd Timer

**Service:** `/etc/systemd/system/nginx-cert-renewal.service`  
**Timer:** `/etc/systemd/system/nginx-cert-renewal.timer`

**Schedule:**
- Runs every Sunday at 3:00 AM
- Random delay of 0-60 minutes to avoid load spikes
- Catches up missed runs on boot (Persistent=true)

**Check Schedule:**
```bash
systemctl list-timers nginx-cert-renewal.timer
```

### Manual Renewal

```bash
# Run renewal manually
sudo /usr/local/bin/renew-nginx-certs.sh

# View renewal logs
sudo tail -f /var/log/nginx-cert-renewal.log

# Trigger timer immediately
sudo systemctl start nginx-cert-renewal.service
```

### Configuration

**OpenBao Token:** `/root/.bao-token`
- Used for authentication to OpenBao PKI
- Permissions: 600 (root only)
- Update if token changes or expires

**Certificate Backup Location:** `/etc/nginx/certs/*.backup.YYYYMMDD`
- Automatic backups created before renewal
- Last 5 backups retained automatically

---

## Service Monitoring

### Purpose
Continuous monitoring of nginx service health with automatic recovery and alerting.

### Implementation

**Script:** `/usr/local/bin/monitor-nginx.sh`

**Checks Performed:**
1. ✅ Nginx process running
2. ✅ Nginx listening on port 443
3. ✅ Certificate expiration (7-day warning)
4. ✅ OpenBao endpoint health
5. ✅ Keylime Verifier endpoint health
6. ✅ Keylime Registrar endpoint health

**Auto-Recovery:**
- Automatically restarts nginx if process fails
- Validates all endpoints after recovery
- Logs all actions to `/var/log/nginx-monitor.log`

### Systemd Timer

**Service:** `/etc/systemd/system/nginx-monitor.service`  
**Timer:** `/etc/systemd/system/nginx-monitor.timer`

**Schedule:**
- Runs every 5 minutes
- First run 5 minutes after boot
- Persistent across reboots

**Check Schedule:**
```bash
systemctl list-timers nginx-monitor.timer
```

### Monitoring Status

**Status File:** `/var/run/nginx-monitor-status`

```bash
# View current status
cat /var/run/nginx-monitor-status

# Example output:
# status=0
# timestamp=1770788568
# nginx_running=active
```

**Status Codes:**
- `0` - All checks passed
- `1` - Warning or recoverable error
- `2` - Critical failure

### Manual Monitoring

```bash
# Run monitor check manually
sudo /usr/local/bin/monitor-nginx.sh

# View monitoring logs
sudo tail -f /var/log/nginx-monitor.log

# View last 50 log entries
sudo journalctl -u nginx-monitor.service -n 50
```

### Certificate Expiration Warnings

The monitor checks certificate expiration daily:
- **7 days before expiry:** WARNING logged
- **0 days (expired):** ERROR logged, status=1

Since certificates renew weekly, expiration should never occur under normal operation.

---

## System Integration

### Systemd Timers Status

```bash
# View all nginx-related timers
systemctl list-timers nginx-*

# Expected output:
# nginx-monitor.timer      - Next run in ~5 minutes
# nginx-cert-renewal.timer - Next run on Sunday at 3 AM
```

### Service Management

```bash
# Enable/disable certificate renewal
sudo systemctl enable nginx-cert-renewal.timer
sudo systemctl disable nginx-cert-renewal.timer

# Enable/disable monitoring
sudo systemctl enable nginx-monitor.timer
sudo systemctl disable nginx-monitor.timer

# Start/stop timers
sudo systemctl start nginx-cert-renewal.timer
sudo systemctl stop nginx-monitor.timer
```

### View Logs

```bash
# Certificate renewal logs
sudo journalctl -u nginx-cert-renewal.service -f
sudo tail -f /var/log/nginx-cert-renewal.log

# Monitoring logs
sudo journalctl -u nginx-monitor.service -f
sudo tail -f /var/log/nginx-monitor.log
```

---

## Alerting & Integration

### Current Implementation
- All events logged to systemd journal
- Status file updated every 5 minutes
- Logs written to dedicated files

### Future Integration Options

**External Monitoring Systems:**
```bash
# Poll status file from monitoring system
curl http://spire.funlab.casa/nginx-monitor-status
# Or SSH to read /var/run/nginx-monitor-status
```

**Email Alerts:**
Add to monitoring script:
```bash
# Send email on critical failure
if [ $overall_status -eq 2 ]; then
    echo "Nginx critical failure" | mail -s "Alert: Nginx Down" admin@example.com
fi
```

**Webhook Integration:**
```bash
# POST to webhook on failure
curl -X POST https://monitoring.example.com/webhook \
    -d '{"service":"nginx","status":"critical"}'
```

---

## Testing

### Test Certificate Renewal

```bash
# Dry run (manual execution)
sudo /usr/local/bin/renew-nginx-certs.sh

# Verify certificates renewed
sudo openssl x509 -in /etc/nginx/certs/services.crt -noout -dates
sudo openssl x509 -in /etc/nginx/certs/keylime.crt -noout -dates

# Check nginx still works
curl -k https://openbao.funlab.casa/v1/sys/health
curl -k https://verifier.keylime.funlab.casa/version
```

### Test Monitoring

```bash
# Run monitor check
sudo /usr/local/bin/monitor-nginx.sh

# Verify exit code
echo $?  # Should be 0 for success

# Check status file
cat /var/run/nginx-monitor-status

# Simulate failure (for testing)
sudo systemctl stop nginx
sudo /usr/local/bin/monitor-nginx.sh
# Should attempt auto-restart
```

---

## Files Created

### Scripts
- `/usr/local/bin/renew-nginx-certs.sh` - Certificate renewal script
- `/usr/local/bin/monitor-nginx.sh` - Monitoring script

### Systemd Units
- `/etc/systemd/system/nginx-cert-renewal.service`
- `/etc/systemd/system/nginx-cert-renewal.timer`
- `/etc/systemd/system/nginx-monitor.service`
- `/etc/systemd/system/nginx-monitor.timer`

### Configuration
- `/root/.bao-token` - OpenBao authentication token

### Logs
- `/var/log/nginx-cert-renewal.log` - Renewal activity log
- `/var/log/nginx-monitor.log` - Monitoring activity log

### Status Files
- `/var/run/nginx-monitor-status` - Current monitoring status

---

## Operational Status

### Current Schedule

| Task | Frequency | Next Run | Status |
|------|-----------|----------|--------|
| Certificate Renewal | Weekly (Sunday 3 AM) | 2026-02-15 03:XX:XX | ✅ Scheduled |
| Service Monitoring | Every 5 minutes | Next: ~5 min | ✅ Active |

### Current Health

```
Certificate Status:
- OpenBao certificate:  ✅ Valid for 29 days
- Keylime certificate:  ✅ Valid for 29 days

Service Status:
- Nginx process:        ✅ Active
- Port 443 listening:   ✅ Yes
- OpenBao endpoint:     ✅ Healthy
- Verifier endpoint:    ✅ Healthy
- Registrar endpoint:   ✅ Healthy

Overall Status:         ✅ All systems operational
```

---

## Troubleshooting

### Certificate Renewal Fails

```bash
# Check OpenBao token
sudo cat /root/.bao-token
export BAO_TOKEN=$(sudo cat /root/.bao-token)
export BAO_ADDR=https://openbao.funlab.casa
bao token lookup

# Check OpenBao connectivity
curl -k https://openbao.funlab.casa/v1/sys/health

# Check renewal logs
sudo tail -100 /var/log/nginx-cert-renewal.log

# Manual renewal attempt
sudo /usr/local/bin/renew-nginx-certs.sh
```

### Monitoring Reports Failures

```bash
# Check what failed
sudo tail -50 /var/log/nginx-monitor.log

# Check nginx status
sudo systemctl status nginx

# Check service endpoints manually
curl -k https://openbao.funlab.casa/v1/sys/health
curl -k https://verifier.keylime.funlab.casa/version
curl -k https://registrar.keylime.funlab.casa/version
```

### Timer Not Running

```bash
# Check timer status
systemctl status nginx-cert-renewal.timer
systemctl status nginx-monitor.timer

# Check if enabled
systemctl is-enabled nginx-cert-renewal.timer
systemctl is-enabled nginx-monitor.timer

# Re-enable if needed
sudo systemctl enable --now nginx-cert-renewal.timer
sudo systemctl enable --now nginx-monitor.timer
```

---

## Benefits Achieved

✅ **Zero-Touch Operations** - Certificates renew automatically  
✅ **Proactive Monitoring** - Issues detected within 5 minutes  
✅ **Auto-Recovery** - Nginx restarts automatically on failure  
✅ **Audit Trail** - Complete logs of all automation activities  
✅ **Graceful Handling** - No service disruption during renewals  
✅ **Safety Features** - Automatic rollback on configuration errors  
✅ **Certificate Lifecycle** - Backups maintained, old certs cleaned  

---

**Status:** Production ready! Fully automated nginx infrastructure management. 🎉
