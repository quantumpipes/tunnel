<div align="center">

# QP Tunnel

**Encrypted remote access to any device, from anywhere.**

Automate WireGuard VPN setup, peer management, and service exposure with post-quantum TLS. Nine commands. Structured audit logging. Double encryption. Zero cloud dependency.

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Tests](https://img.shields.io/badge/Tests-370%2B-brightgreen.svg)](./tests/)
[![Conformance](https://img.shields.io/badge/Conformance-15_vectors-ff69b4.svg)](./conformance/)
[![Crypto](https://img.shields.io/badge/Crypto-WireGuard_%2B_PQ_TLS-purple.svg)](#security)
[![Capsule](https://img.shields.io/badge/Audit-Capsule_Protocol-orange.svg)](https://github.com/quantumpipes/capsule)

</div>

---

## The Problem

You have a device behind a firewall. You need to reach it from anywhere, securely, without exposing it to the internet. Traditional options all have tradeoffs: port forwarding is fragile and insecure, SSH tunnels break under reconnection, commercial VPNs require cloud accounts and ongoing subscriptions, and manual WireGuard setup is error-prone at scale.

QP Tunnel solves this with automation, audit logging, and defense-in-depth encryption.

```
You (laptop)            Relay (any server)          Your device
  ┌────────┐            ┌──────────────┐            ┌──────────────┐
  │ alice  │──WireGuard─│   10.8.0.1   │──WireGuard─│   10.8.0.2   │
  │ .0.10  │            │    relay     │            │  your server │
  └────────┘            └──────────────┘            └──────────────┘
  ┌────────┐                   │
  │ bob    │───────────────────┘
  │ .0.11  │   Split-tunnel: only 10.8.0.0/24
  └────────┘   routes through the VPN
```

---

## Why QP Tunnel

**Works with any server.** DigitalOcean, AWS, Hetzner, Linode, Oracle Cloud (free tier), a Raspberry Pi, or your old laptop. If it runs Linux and WireGuard, it works.

**Nine commands.** Setup, join, add peer, remove peer, status, rotate keys, open, close, list. That is the entire interface.

**Double encryption.** WireGuard provides the outer tunnel (Curve25519/ChaCha20-Poly1305). Caddy provides an inner PQ TLS 1.3 layer (ML-KEM-768 hybrid key exchange) for exposed services. Both must fail for data exposure.

**Cryptographic audit trail.** Every operation logged as structured JSON. Optional [Capsule Protocol](https://github.com/quantumpipes/capsule) integration seals each entry with SHA3-256 + Ed25519 for tamper evidence.

**Instant revocation.** Remove a peer and access drops immediately. No grace period. No session expiry. Revoked configs archived for compliance.

**Air-gap compatible.** No internet required after initial setup. No phone-home. No telemetry. No vendor lock-in.

**White-label ready.** Set `TUNNEL_APP_NAME=yourproject` and every path, tag, and certificate adapts.

---

## Quick Start

### Option 1: Use any existing server (SSH)

```bash
# Configure your remote server as the relay
./tunnel-setup-relay.sh --provider=ssh --host=203.0.113.10

# On the target device: join the relay
./tunnel-join.sh 203.0.113.10:51820 <relay-public-key>

# Add yourself as a peer
./tunnel-add-peer.sh alice
# Scan the QR code or paste the config into your WireGuard app. Done.
```

### Option 2: This machine IS the relay

```bash
./tunnel-setup-relay.sh --provider=local
```

### Option 3: Provision a DigitalOcean Droplet

```bash
export DO_API_TOKEN=dop_v1_...
./tunnel-setup-relay.sh --provider=digitalocean
```

### Option 4: Generate a setup script

```bash
./tunnel-setup-relay.sh --generate-script > setup-relay.sh
ssh root@your-server < setup-relay.sh
```

### Option 5: Use Make targets

```bash
cp .env.tunnel.example .env.tunnel
make tunnel-setup-local      # Or: tunnel-setup-ssh, tunnel-setup-do
make tunnel-add-peer NAME=alice
make tunnel-status
```

---

## Commands

| Command | Description |
|---------|-------------|
| `tunnel-setup-relay.sh` | Configure a WireGuard relay (multi-provider) |
| `tunnel-join.sh <endpoint> <key>` | Join an existing relay from the target machine |
| `tunnel-add-peer.sh <name>` | Add a peer: generates config + QR code |
| `tunnel-remove-peer.sh <name>` | Revoke a peer immediately, archive config |
| `tunnel-status.sh` | Show all peers with live handshake data |
| `tunnel-rotate-keys.sh` | Rotate relay keys (dry-run by default, `CONFIRM=1` to execute) |
| `tunnel-open.sh --name <n> --to <host:port>` | Expose a local service with PQ TLS over the tunnel |
| `tunnel-close.sh --name <n>` | Stop exposing a service |
| `tunnel-list.sh` | List all open services |

### Exposing Services

Expose any local application over the tunnel with post-quantum TLS:

```bash
# Expose Grafana with PQ TLS
./tunnel-open.sh --name grafana --to localhost:3000

# Expose Jenkins on a specific port
./tunnel-open.sh --name jenkins --to localhost:8080 --port 8444

# List open services
./tunnel-list.sh

# Close a service
./tunnel-close.sh --name grafana
```

**How it works:**
1. Generates an internal CA (Ed25519) and per-service TLS certificates
2. Starts a Caddy reverse proxy with TLS 1.3 + ML-KEM-768 key exchange
3. Binds the port to the tunnel interface only (unreachable from LAN)
4. Installs firewall rules allowing only tunnel subnet traffic
5. Registers the service and creates a Capsule audit record

Mobile devices: install the generated `ca.mobileconfig` on iOS to trust the internal CA. macOS and Linux trust store commands shown in the command output.

---

## Architecture

```
                      ┌─────────────────────────────────┐
                      │        Relay Server             │
                      │   (any Linux machine/VPS)       │
                      │                                 │
                      │   WireGuard: 10.8.0.1           │
                      │   Port: 51820/udp               │
                      │   NAT + IP forwarding           │
                      │   Holds no data. Forwards only. │
                      └──────────┬──────────┬───────────┘
                                 │          │
              ┌──────────────────┘          └──────────────────┐
              │                                                │
      ┌───────┴──────────┐                        ┌────────────┴─────────┐
      │  Target Device   │                        │    Remote Peers      │
      │  (your server)   │                        │                      │
      │                  │                        │    alice:  10.8.0.10 │
      │  10.8.0.2        │                        │    bob:    10.8.0.11 │
      │  Persistent peer │                        │    carol:  10.8.0.12 │
      │  Auto-reconnect  │                        │    ...up to .0.254   │
      └──────────────────┘                        └──────────────────────┘
```

**The relay** is a rendezvous point. It forwards encrypted WireGuard packets between peers. It holds no data and runs no application logic. If compromised, attackers see only encrypted traffic they cannot decrypt.

**The target device** connects to the relay as a persistent peer and reconnects automatically on reboot via systemd.

**Remote peers** connect through WireGuard apps on any platform: macOS, Windows, Linux, iOS, Android. Each peer gets a unique keypair, a unique preshared key, and a unique IP address.

**Split-tunnel** routes only `10.8.0.0/24` through the VPN. Everything else takes the normal internet path.

---

## Double Encryption

```
┌──────────────────────────────────────────────────────────────────────┐
│                        OUTER LAYER: WireGuard                        │
│                                                                      │
│     Key exchange: Curve25519 (X25519)                                │
│     Encryption:   ChaCha20-Poly1305                                  │
│     Hashing:      BLAKE2s                                            │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                   INNER LAYER: PQ TLS 1.3                    │    │
│  │                   (tunnel-open services only)                │    │
│  │                                                              │    │
│  │  Key exchange: X25519MLKEM768 (hybrid classical + PQ)        │    │
│  │  Encryption:   AES-256-GCM                                   │    │
│  │  Certificates: Ed25519 (internal CA)                         │    │
│  │                                                              │    │
│  │              ┌────────────────────────┐                      │    │
│  │              │   Your application     │                      │    │
│  │              │   (plaintext HTTP)     │                      │    │
│  │              └────────────────────────┘                      │    │
│  └──────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
```

If Curve25519 is broken by a quantum computer, the inner PQ TLS layer still protects session data. If ML-KEM-768 has an implementation flaw, WireGuard's outer layer still protects. Both must fail simultaneously for data exposure.

See [CRYPTO-NOTICE.md](docs/CRYPTO-NOTICE.md) for the full cryptographic analysis.

---

## Audit System

Every operation writes a structured JSON entry to `audit.log`:

```json
{
  "timestamp": "2026-03-24T15:30:00Z",
  "action": "peer_add",
  "status": "success",
  "message": "Added peer alice (10.8.0.10)",
  "user": "operator",
  "details": {"name": "alice", "tunnel_ip": "10.8.0.10"}
}
```

Logged actions: `setup_relay`, `tunnel_join`, `peer_add`, `peer_remove`, `key_rotate`, `service_open`, `service_close`, and all error traps.

### Capsule Protocol Integration

When [qp-capsule](https://github.com/quantumpipes/capsule) is installed, audit events are sealed as tamper-evident Capsules using SHA3-256 + Ed25519 signatures. This provides cryptographic proof that records have not been modified after creation.

```bash
pip install qp-capsule           # Or: auto-installs on first use
qp-capsule verify --db capsules.db   # Verify chain integrity
```

The JSON audit log is the fast local index. Capsules are the cryptographic source of truth. Golden test vectors for the audit format are in [`conformance/`](./conformance/).

---

## Security

| Layer | Mechanism |
|-------|-----------|
| **Transport (outer)** | WireGuard: Curve25519 + ChaCha20-Poly1305 + BLAKE2s |
| **Transport (inner)** | PQ TLS 1.3: ML-KEM-768 + AES-256-GCM (tunnel-open) |
| **Identity** | Unique keypair + preshared key per peer |
| **File protection** | umask 077 on all keys (owner-only, mode 600) |
| **Input validation** | Strict `[a-zA-Z0-9_-]` regex (prevents injection) |
| **No eval** | Zero use of `eval` in the entire codebase |
| **Token masking** | API tokens masked in all logs (last 4 chars only) |
| **Audit trail** | Every operation logged with timestamp, user, and result |
| **Tamper evidence** | Optional Capsule Protocol sealing (SHA3-256 + Ed25519) |
| **Revocation** | Immediate removal from live WireGuard interface |
| **Archival** | Revoked configs archived, never deleted (compliance) |
| **Key rotation** | Built-in with dry-run safety and automatic backup |

See [Security Evaluation](./docs/security.md) for the full CISO-targeted assessment including STRIDE threat model.

---

## Compliance

Tunnel maps to 5 regulatory frameworks. Each mapping documents which controls the toolkit satisfies and which require complementary application-level controls.

| Framework | Controls | Focus |
|-----------|----------|-------|
| [HIPAA](./docs/compliance/hipaa.md) | 164.312(e)(1), 164.308(a)(5) | Transmission security, access control, audit |
| [CMMC 2.0](./docs/compliance/cmmc.md) | AC.L2-3.1.12/13/14, AU.L2-3.3.x | Remote access monitoring, encrypted sessions |
| [FedRAMP](./docs/compliance/fedramp.md) | AC-17, SC-8, AU-2/3 | Remote access, transmission confidentiality |
| [SOC 2](./docs/compliance/soc2.md) | CC6.1, CC6.7, CC7.x | Logical access, encryption, incident response |
| [ISO 27001](./docs/compliance/iso27001.md) | A.5.15, A.8.20, A.8.24, A.8.26 | Access control, network security, crypto |

For FIPS-mandatory environments: WireGuard uses ChaCha20-Poly1305, which is not FIPS 140-2/140-3 validated. Substitute IPsec with FIPS-validated modules for those deployments. See the [compliance overview](./docs/compliance/).

---

## Configuration

Copy `.env.tunnel.example` to `.env.tunnel` and customize:

| Variable | Default | Description |
|----------|---------|-------------|
| `TUNNEL_APP_NAME` | `qp-tunnel` | Config directory, server tags |
| `TUNNEL_SUBNET` | `10.8.0.0/24` | VPN subnet |
| `TUNNEL_RELAY_IP` | `10.8.0.1` | Relay address within VPN |
| `TUNNEL_SERVER_IP` | `10.8.0.2` | Target device address within VPN |
| `TUNNEL_PORT` | `51820` | WireGuard listen port |
| `TUNNEL_DNS_SERVER` | `10.8.0.2` | DNS server for peers |
| `TUNNEL_ALLOWED_IPS` | `10.8.0.0/24` | IPs routed through tunnel |
| `TUNNEL_INTERFACE` | `wg0` | WireGuard interface name |
| `TUNNEL_CONFIG_DIR` | `~/.config/qp-tunnel` | State directory |
| `DO_API_TOKEN` | (none) | DigitalOcean API token |
| `RELAY_HOST` | (none) | Server IP for SSH provider |

All values are overridable via environment variables or `.env.tunnel`.

### Relay Setup Providers

| Provider | Flag | Requires | What it does |
|----------|------|----------|--------------|
| **SSH** | `--provider=ssh --host=IP` | SSH access | Configures an existing server remotely |
| **Local** | `--provider=local` | Root on relay | Configures this machine as the relay |
| **DigitalOcean** | `--provider=digitalocean` | `DO_API_TOKEN` | Provisions a new Droplet |
| **Script** | `--generate-script` | Nothing | Outputs setup script to stdout |

Auto-detection: if `DO_API_TOKEN` is set, defaults to DigitalOcean. If `RELAY_HOST` is set, defaults to SSH.

---

## Testing

370+ tests across three tiers using [bats-core](https://github.com/bats-core/bats-core):

```bash
make test              # All tests (unit + integration)
make test-unit         # Lib functions in isolation
make test-integration  # Full peer lifecycle workflows
make test-smoke        # File existence and structure
```

Tests cover: input validation, key generation, registry CRUD, audit logging, Capsule sealing, certificate generation, PQ TLS config, firewall rules, service lifecycle, file permissions (600/700), peer lifecycle, key rotation, security hardening, edge cases, and error paths.

---

## Dependencies

**Required:**

| Dependency | Purpose |
|------------|---------|
| `bash` 4.0+ | Shell runtime |
| `jq` | JSON processing for peer registry |
| `wg`, `wg-quick` | WireGuard tools |

**Optional:**

| Dependency | Purpose |
|------------|---------|
| `caddy` (Go 1.24+) | PQ TLS reverse proxy for tunnel-open |
| `openssl` | Certificate generation for tunnel-open |
| `qrencode` | QR codes for mobile WireGuard apps |
| `qp-capsule` | Tamper-evident audit sealing (auto-installs via pip) |
| `doctl` | DigitalOcean CLI (curl fallback exists) |

---

## Documentation

| Document | Audience |
|----------|----------|
| [Architecture](./docs/architecture.md) | Developers, Auditors |
| [Security Evaluation](./docs/security.md) | CISOs, Security Teams |
| [Why Tunnel](./docs/why-tunnel.md) | Decision-Makers, Architects |
| [Compliance Mappings](./docs/compliance/) | Regulators, GRC |
| [Cryptographic Notice](./docs/CRYPTO-NOTICE.md) | Security Engineers |
| [Narrative Guide](./docs/GUIDE.md) | New Users |

### Examples

| Guide | Use Case |
|-------|----------|
| [DigitalOcean Quickstart](./examples/digitalocean-quickstart.md) | Cloud relay with 3 peers and exposed service |
| [Home Lab](./examples/home-lab.md) | Raspberry Pi relay with Home Assistant |
| [Healthcare Clinic](./examples/healthcare-clinic.md) | HIPAA-compliant remote EHR access |

---

## Project Structure

```
.
├── tunnel-*.sh                  # 9 commands (setup, join, add, remove, status, rotate, open, close, list)
├── tunnel-preflight.sh          # Pre-flight setup (sourced by all scripts)
├── lib/
│   ├── common.sh                # Logging, validation, config defaults
│   ├── registry.sh              # Peer registry CRUD (JSON/jq)
│   ├── audit.sh                 # Structured audit logging + Capsule sealing
│   ├── open.sh                  # Service exposure: CA, certs, Caddy, firewall
│   └── wireguard.sh             # WireGuard CLI wrappers
├── templates/
│   ├── client.conf.tpl          # Client config template
│   └── Caddyfile.open.tpl       # PQ TLS Caddy template
├── conformance/                 # Audit log golden test vectors (15 fixtures)
├── completions/                 # Bash and Zsh tab-completion scripts
├── tests/                       # 370+ tests (unit, integration, smoke)
├── docs/                        # Architecture, security, compliance, guides
├── examples/                    # Deployment walkthroughs
├── .env.tunnel.example          # Configuration template
├── Makefile                     # All operations as Make targets
└── VERSION                      # 0.1.0
```

---

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). Issues and pull requests welcome. New relay providers can be proposed via [provider request](https://github.com/quantumpipes/tunnel/issues/new?template=provider-request.md).

## License and Patents

[Apache License 2.0](./LICENSE) with [additional patent grant](./PATENTS.md). You can use all patented innovations freely for any purpose, including commercial use.

---

<div align="center">

**Encrypted remote access. Zero cloud dependency. Full audit trail.**

[Documentation](./docs/) · [Examples](./examples/) · [Conformance](./conformance/) · [Security Policy](./SECURITY.md) · [Patent Grant](./PATENTS.md)

Copyright 2026 [Quantum Pipes Technologies, LLC](https://quantumpipes.com)

</div>
