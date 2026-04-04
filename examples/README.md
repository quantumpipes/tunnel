# QP Tunnel Examples

Step-by-step deployment guides for common scenarios. Each example is self-contained and copy-pasteable.

## Examples

| Guide | Scenario | Key Topics |
|-------|----------|------------|
| [DigitalOcean Quickstart](digitalocean-quickstart.md) | Cloud relay on DigitalOcean, 3 peers, exposed service | Droplet provisioning, peer management, tunnel-open |
| [Home Lab](home-lab.md) | Local relay on Raspberry Pi or home server | Self-hosted, multiple device types, Home Assistant |
| [Healthcare Clinic](healthcare-clinic.md) | Secure remote access to on-premises EHR | HIPAA compliance, audit logging, peer revocation, key rotation |

## Prerequisites

All examples assume:

- Bash 4.0+ on the relay machine
- WireGuard and jq installed (the setup script installs these automatically)
- An Ed25519 SSH key at `~/.ssh/id_ed25519`
- The QP Tunnel repository cloned locally

## Conventions

Commands prefixed with `relay#` run on the relay server. Commands prefixed with `local$` run on your workstation. Commands with no prefix run wherever you cloned the repository.
