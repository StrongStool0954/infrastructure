# spire.funlab.casa - SPIRE Server Configuration

**Date Configured:** 2026-02-10
**Hostname:** spire.funlab.casa
**IP Address:** 10.10.2.62
**Purpose:** SPIRE Server (SPIFFE Runtime Environment)

## SPIRE Server Details

**Version:** 1.14.1
**Installation Path:** /opt/spire
**Data Directory:** /opt/spire/data
**Configuration:** /etc/spire/server.conf
**Trust Domain:** funlab.casa

## Service Configuration

**Service File:** /etc/systemd/system/spire-server.service
**Status:** Active and enabled
**Ports:**
- TCP 8081 (SPIRE Server API)
- Unix Socket: /tmp/spire-server/private/api.sock

## Configuration

**Server Settings:**
- Bind Address: 0.0.0.0:8081
- Trust Domain: funlab.casa
- Data Directory: /opt/spire/data
- Log Level: INFO

**Plugins:**
1. **DataStore (sql):** SQLite3 database at /opt/spire/data/datastore.sqlite3
2. **NodeAttestor (join_token):** Token-based node attestation
3. **KeyManager (disk):** Disk-based key storage at /opt/spire/data/keys.json

## Service Management

### Start/Stop/Restart
```bash
sudo systemctl start spire-server
sudo systemctl stop spire-server
sudo systemctl restart spire-server
```

### Check Status
```bash
sudo systemctl status spire-server
sudo /opt/spire/bin/spire-server healthcheck
```

### View Logs
```bash
sudo journalctl -u spire-server -f
```

## Common Operations

### List Agents
```bash
sudo /opt/spire/bin/spire-server agent list
```

### List Entries
```bash
sudo /opt/spire/bin/spire-server entry show
```

### Create Join Token
```bash
sudo /opt/spire/bin/spire-server token generate -spiffeID spiffe://funlab.casa/agent/[hostname]
```

### Generate Bundle
```bash
sudo /opt/spire/bin/spire-server bundle show -format spiffe
```

## Security Model

**Trust Domain:** funlab.casa
- All workloads will be issued identities under spiffe://funlab.casa/*
- X509 CA rotates every 24 hours
- JWT keys rotate every 24 hours

**Node Attestation:**
- Currently using join_token (basic)
- Future: TPM-based attestation planned

**Data Security:**
- Keys stored on disk at /opt/spire/data/keys.json
- SQLite database at /opt/spire/data/datastore.sqlite3
- All data protected by host LUKS encryption + TPM auto-unlock

## Integration Points

### Planned Integrations:
- [ ] OpenBao (Vault replacement) - secrets backend
- [ ] step-ca (ca.funlab.casa) - certificate authority integration
- [ ] SPIRE Agents on other infrastructure hosts
- [ ] Workload attestation for services

## Backup and Recovery

### Critical Files to Backup:
```bash
/etc/spire/server.conf
/opt/spire/data/keys.json
/opt/spire/data/datastore.sqlite3
```

### Backup Command:
```bash
sudo tar czf spire-backup-$(date +%Y%m%d).tar.gz \
  /etc/spire/server.conf \
  /opt/spire/data/
```

## Troubleshooting

### Server Won't Start

**Check logs:**
```bash
sudo journalctl -u spire-server -n 100
```

**Common issues:**
- Port 8081 already in use: `sudo netstat -tlnp | grep 8081`
- Configuration syntax error: `sudo /opt/spire/bin/spire-server run -config /etc/spire/server.conf`
- Missing directories: Ensure /opt/spire/data exists

### Healthcheck Fails

**Verify service is running:**
```bash
sudo systemctl status spire-server
```

**Check socket permissions:**
```bash
sudo ls -la /tmp/spire-server/private/api.sock
```

### Database Locked

If SQLite database becomes locked:
```bash
sudo systemctl stop spire-server
sudo fuser /opt/spire/data/datastore.sqlite3
sudo systemctl start spire-server
```

## Maintenance

### After System Updates
```bash
sudo systemctl restart spire-server
sudo /opt/spire/bin/spire-server healthcheck
```

### Monitoring
Monitor these metrics:
- Service uptime: `systemctl status spire-server`
- Port availability: `ss -tlnp | grep 8081`
- Certificate expiration: Check logs for CA rotation
- Disk space in /opt/spire/data

### Regular Tasks

**Weekly:**
- Check SPIRE Server logs for errors
- Verify healthcheck passes
- Review registered agents and entries

**Monthly:**
- Backup SPIRE data directory
- Review and clean up unused entries
- Update SPIRE to latest stable version if needed

## Related Documentation

- [SPIRE Server Deployment Summary](tower-of-omens-deployment-summary.md)
- [spire.funlab.casa TPM Config](spire-tpm-config.md)
- [Tower of Omens Onboarding Guide](tower-of-omens-onboarding.md)
- [SPIRE Official Documentation](https://spiffe.io/docs/latest/deploying/spire_server/)

## Status

✅ **SPIRE Server:** Running and healthy
✅ **Trust Domain:** funlab.casa configured
✅ **Service:** Enabled and auto-starts on boot
✅ **Ports:** Listening on 8081
✅ **Database:** SQLite initialized and working

**Next Steps:**
1. Deploy SPIRE Agents on auth.funlab.casa and ca.funlab.casa
2. Configure OpenBao integration
3. Set up workload registration
4. Enable TPM-based node attestation
