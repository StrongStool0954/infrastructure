# Tygra SSH CA Public Keys

## SSH Host CA Public Key
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAntL2ChmQQR6cUqmCAG3jVGW/8dyWLoqHTOMUg+vKIm tygra.funlab.casa SSH Host CA
```

## SSH User CA Public Key
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDxiwMjSnVSwS4qMHDM27BkXdbpN9EDjvwtM3jfd1sTA tygra.funlab.casa SSH User CA
```

## Configuration

- **Domain**: tygra.funlab.casa
- **Backend Port**: 8444 (proxied via nginx on port 443)
- **Host**: ca.funlab.casa (10.10.2.60)
- **Service**: step-ca-ssh.service
- **Config**: /etc/step-ca-ssh/config/ca.json
- **Keys**: /etc/step-ca-ssh/secrets/
- **Provisioner**: tygra-admin (JWK)

## Usage

To install the SSH CA public keys on hosts, add these to `/etc/ssh/known_hosts` or `~/.ssh/known_hosts`:

```bash
# Trust tygra SSH Host CA for all hosts in funlab.casa
@cert-authority *.funlab.casa ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAntL2ChmQQR6cUqmCAG3jVGW/8dyWLoqHTOMUg+vKIm
```

To configure sshd to accept user certificates, add to `/etc/ssh/sshd_config`:

```bash
# Trust tygra SSH User CA
TrustedUserCAKeys /etc/ssh/tygra_user_ca.pub
```
