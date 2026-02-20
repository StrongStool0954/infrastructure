# Keylime + SPIRE Keylime Plugin Bundle v1.0.0

This bundle provides a unified installation package for:
- **Keylime Agent** (Rust-based TPM attestation agent)
- **SPIRE Keylime Plugin** (NodeAttestor for SPIRE using Keylime)

## Supported Platforms

- Rocky Linux 9
- Debian 12 (Bookworm)
- Debian 13 (Trixie)

## Prerequisites

- TPM 2.0 hardware or software TPM (swtpm)
- Keylime Registrar and Verifier (running separately)
- SPIRE Server (running separately)
- Root access for installation

## Quick Start

```bash
sudo ./install.sh
```

The installer will:
1. Detect your OS automatically
2. Install binaries to `/usr/local/bin/`
3. Create keylime user/group
4. Set up directory structure

## Post-Installation Configuration

### 1. Keylime Agent Configuration

Create `/etc/keylime/agent.conf`:

```ini
[agent]
# UUID will be auto-generated if not set
# uuid = "auto"

# Agent IP address (use 0.0.0.0 to bind all interfaces)
agent_contact_ip = "0.0.0.0"
agent_contact_port = 9002

# Registrar configuration
registrar_ip = "registrar.keylime.funlab.casa"
registrar_port = 443
registrar_tls_enabled = true
registrar_tls_ca_cert = "/etc/keylime/certs/ca-root-only.crt"
registrar_tls_client_cert = "/etc/keylime/certs/agent.crt"
registrar_tls_client_key = "/etc/keylime/certs/agent-pkcs8.key"

# Verifier configuration
verifier_ip = "verifier.keylime.funlab.casa"
verifier_port = 443
verifier_tls_enabled = true
verifier_tls_ca_cert = "/etc/keylime/certs/ca-root-only.crt"

[cloud_verifier]
cloudverifier_ip = "verifier.keylime.funlab.casa"
cloudverifier_port = 443
```

### 2. Bootstrap Certificates

The Keylime agent requires certificates for mTLS authentication. Bootstrap options:

#### Option A: Manual Certificate Placement
- Place your PKI-issued certificates in `/etc/keylime/certs/`:
  - `agent.crt` - Agent certificate
  - `agent-pkcs8.key` - Agent private key (PKCS#8 format)
  - `ca-root-only.crt` - Root CA (for TLS validation)
  - `ca-chain.crt` - Complete CA chain (for pre-flight validation)

#### Option B: Automated Bootstrap (if using OpenBao)
The agent includes built-in bootstrap functionality to fetch certificates from OpenBao via SSH.

### 3. Start Keylime Agent

Create systemd service `/etc/systemd/system/keylime-agent.service`:

```ini
[Unit]
Description=Keylime Agent
After=network.target

[Service]
Type=simple
User=keylime
Group=tss
ExecStart=/usr/local/bin/keylime_agent
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable keylime-agent
sudo systemctl start keylime-agent
sudo systemctl status keylime-agent
```

### 4. Configure SPIRE Agent with Keylime Plugin

Add to your SPIRE agent configuration (`/etc/spire/agent.conf`):

```hcl
plugins {
    NodeAttestor "keylime" {
        plugin_cmd = "/usr/local/bin/keylime-attestor-agent"
        plugin_checksum = ""
        plugin_data {
            registrar_url = "https://registrar.keylime.funlab.casa:443"
            agent_uuid = "auto"  # or specific UUID
        }
    }
}
```

Add to your SPIRE server configuration (`/etc/spire/server.conf`):

```hcl
plugins {
    NodeAttestor "keylime" {
        plugin_cmd = "/usr/local/bin/keylime-attestor-server"
        plugin_checksum = ""
        plugin_data {
            verifier_url = "https://verifier.keylime.funlab.casa:443"
        }
    }
}
```

## Component Versions

- **Keylime Agent**: Custom fork with reqwest 0.12.15
- **SPIRE Keylime Plugin**: v1.0.0 with updated dependencies:
  - github.com/spiffe/go-spiffe/v2: v2.2.0
  - github.com/spiffe/spire: v1.9.0
  - google.golang.org/grpc: v1.78.0

## Directory Structure

```
/usr/local/bin/
  ├── keylime_agent
  ├── keylime-attestor-agent
  └── keylime-attestor-server

/etc/keylime/
  ├── agent.conf
  └── certs/
      ├── agent.crt
      ├── agent-pkcs8.key
      ├── ca-root-only.crt
      └── ca-chain.crt

/var/lib/keylime/
  └── (agent runtime data)

/var/log/keylime/
  └── (agent logs)
```

## Troubleshooting

### Agent won't start
- Check TPM is accessible: `ls -la /dev/tpm*`
- Verify keylime user is in tss group: `groups keylime`
- Check logs: `sudo journalctl -u keylime-agent -n 50`

### Certificate errors
- Verify certificates exist in `/etc/keylime/certs/`
- Check certificate permissions: agent.crt should be 644, agent-pkcs8.key should be 640
- Validate certificate chain: `openssl verify -CAfile /etc/keylime/certs/ca-root-only.crt /etc/keylime/certs/agent.crt`

### TLS connection failures
- Test registrar connectivity: `curl -k https://registrar.keylime.funlab.casa:443`
- Verify DNS resolution: `dig registrar.keylime.funlab.casa`
- Check firewall rules

## Support

- Repository: https://github.com/keylime/rust-keylime
- SPIRE Plugin: https://github.com/keylime/spire-keylime-plugin
- Documentation: https://keylime.dev/

## License

- Keylime Agent: Apache-2.0
- SPIRE Keylime Plugin: Apache-2.0
