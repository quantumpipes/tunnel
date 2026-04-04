# QP Tunnel

**Secure WireGuard tunnels to any device, from anywhere.**

QP Tunnel automates WireGuard VPN setup, peer management, key rotation, service exposure, and cryptographic audit logging. Nine commands give you encrypted remote access to any machine: a server in a data center, a Raspberry Pi at home, or a workstation behind a corporate firewall.

Works with any Linux server. No vendor lock-in. No cloud dependency. Fully open source.

```
You (laptop)            Relay (any server)          Your device
  ┌────────┐            ┌──────────────┐            ┌──────────────┐
  │  alice  │──WireGuard─│   10.8.0.1   │──WireGuard─│   10.8.0.2   │
  │  .0.10  │            │    relay     │            │  your server │
  └────────┘            └──────────────┘            └──────────────┘
  ┌────────┐                   │
  │  bob   │───────────────────┘
  │  .0.11  │   Split-tunnel: only 10.8.0.0/24
  └────────┘   routes through the VPN
```

## Why QP Tunnel?

**Works with any server.** DigitalOcean, AWS, Hetzner, Linode, Oracle Cloud (free tier), a Raspberry Pi, or your old laptop. If it runs Linux and WireGuard, it works.

**Nine commands.** Setup, join, add peer, remove peer, status, rotate keys, open, close, list. That is the entire interface.

**Instant revocation.** Remove a peer and access drops immediately. No grace period. No session expiry.

**Cryptographic audit trail.** Every operation logged as structured JSON. Optional [Capsule Protocol](https://github.com/quantumpipes/capsule) integration provides tamper-evident sealing with SHA3-256 + Ed25519.

**Split-tunnel by default.** Only VPN subnet traffic routes through the relay. Everything else takes the user's normal path.

**Air-gap compatible.** No internet required after initial setup. No phone-home. No telemetry.

**White-label ready.** Set `TUNNEL_APP_NAME=yourproject` and every path, tag, and config adapts.

## Quick Start

### Option 1: Use any existing server (SSH)

```bash
# Configure your remote server as the relay (runs setup over SSH)
./tunnel-setup-relay.sh --provider=ssh --host=203.0.113.10

# On the target device: join the relay
./tunnel-join.sh 203.0.113.10:51820 <relay-public-key>

# Add yourself as a peer
./tunnel-add-peer.sh alice
# Scan the QR code or paste the config into your WireGuard app. Done.
```

### Option 2: This machine IS the relay

```bash
# Run directly on the machine that will be the relay
./tunnel-setup-relay.sh --provider=local
```

### Option 3: Provision a DigitalOcean Droplet

```bash
export DO_API_TOKEN=dop_v1_...
./tunnel-setup-relay.sh --provider=digitalocean
```

### Option 4: Generate a setup script for manual use

```bash
# Output a setup script you can run anywhere, any way you like
./tunnel-setup-relay.sh --generate-script > setup-relay.sh

# Then: scp it, curl it, paste it, pipe it over SSH...
ssh root@your-server < setup-relay.sh
```

### Option 5: Use Make targets

```bash
cp .env.tunnel.example .env.tunnel   # Configure
make tunnel-setup-local              # Or: tunnel-setup-ssh, tunnel-setup-do
make tunnel-add-peer NAME=alice
make tunnel-status
```

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

### Exposing Services (tunnel-open)

Expose any local web application over the tunnel with post-quantum TLS encryption:

```bash
# Expose Grafana with PQ TLS
tunnel-open --name grafana --to localhost:3000

# Expose Jenkins on a specific port
tunnel-open --name jenkins --to localhost:8080 --port 8444

# List all open services
tunnel-list

# Close a service
tunnel-close --name grafana
```

**Double encryption:** WireGuard provides the outer tunnel (Curve25519/ChaCha20-Poly1305). Caddy provides the inner PQ TLS 1.3 layer (ML-KEM-768 hybrid key exchange). Exposed ports bind exclusively to the tunnel interface with firewall rules restricting access to the tunnel subnet.

**How it works:**
1. Generates an internal CA (Ed25519) and per-service TLS certificates
2. Starts a Caddy reverse proxy with TLS 1.3 + ML-KEM-768 key exchange
3. Binds the port to the tunnel interface only (unreachable from LAN)
4. Installs firewall rules allowing only tunnel subnet traffic
5. Registers the service and creates a Capsule audit record

**Mobile device access:** Install the generated `ca.mobileconfig` on iOS devices to trust the internal CA. macOS and Linux have equivalent trust store commands shown in the command output.

### Relay Setup Providers

| Provider | Flag | Requires | What it does |
|----------|------|----------|--------------|
| **SSH** | `--provider=ssh --host=IP` | SSH access | Configures an existing server remotely |
| **Local** | `--provider=local` | Root on relay | Configures this machine as the relay |
| **DigitalOcean** | `--provider=digitalocean` | `DO_API_TOKEN` | Provisions a new Droplet |
| **Script** | `--generate-script` | Nothing | Outputs setup script to stdout |

Auto-detection: if `DO_API_TOKEN` is set, defaults to DigitalOcean. If `RELAY_HOST` is set, defaults to SSH.

## Architecture

```
                      ┌─────────────────────────────────┐
                      │         Relay Server             │
                      │    (any Linux machine/VPS)       │
                      │                                  │
                      │    WireGuard: 10.8.0.1           │
                      │    Port: 51820/udp               │
                      │    NAT + IP forwarding           │
                      │    Holds no data. Forwards only. │
                      └──────────┬──────────┬────────────┘
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

**The relay** is a rendezvous point. It forwards encrypted WireGuard packets between peers. It holds no data. It runs no application logic. If compromised, attackers see only encrypted traffic they cannot decrypt.

**The target device** (your server, workstation, IoT device) connects to the relay as a persistent peer. It reconnects automatically on reboot via systemd.

**Remote peers** (you, your team, your customers) connect through WireGuard apps on any platform: macOS, Windows, Linux, iOS, Android. Each peer gets a unique keypair, a unique preshared key, and a unique IP address.

**Split-tunnel** routes only `10.8.0.0/24` traffic through the VPN. When alice watches YouTube, that goes through her normal internet. When she pings `10.8.0.2`, that goes through the encrypted tunnel.

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
| `TUNNEL_SSH_KEY` | `~/.ssh/id_ed25519` | SSH key for relay access |
| `DO_API_TOKEN` | (none) | DigitalOcean API token |
| `RELAY_HOST` | (none) | Server IP for SSH provider |
| `RELAY_SSH_USER` | `root` | SSH user for SSH provider |

All values are overridable via environment variables or `.env.tunnel`.

## State Directory

All state lives in `~/.config/${TUNNEL_APP_NAME}/`:

```
~/.config/qp-tunnel/
  peers.json              # Peer registry (relay, peers, IP pool)
  services.json           # Open services registry
  audit.log               # Structured JSON audit log (JSONL)
  capsules.db             # SQLite Capsule database (tamper-evident)
  relay.key               # Relay private key (mode 600)
  relay.pub               # Relay public key
  relay-server.json       # Relay server metadata
  server-relay.psk        # Server-relay preshared key
  tls/                    # Certificates (tunnel-open)
    ca.key                # Ed25519 CA private key (mode 600)
    ca.crt                # CA public certificate
    ca.mobileconfig       # iOS trust profile
    <name>.key            # Per-service TLS key (mode 600)
    <name>.crt            # Per-service TLS cert
  services/               # Per-service runtime (tunnel-open)
    <name>/
      Caddyfile           # Caddy config for this service
      caddy.pid           # Caddy process ID
  peers/
    alice/
      alice.conf          # WireGuard client config
      preshared.key       # Peer preshared key
  archive/                # Revoked peers + closed service certs
  key-backups/            # Old keys from rotation
```

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
pip install qp-capsule       # Or: auto-installs on first use
qp-capsule verify             # Verify audit chain integrity
```

The JSON audit log serves as a fast local index. Capsules are the cryptographic source of truth.

## Security

| Layer | Mechanism |
|-------|-----------|
| **Transport (outer)** | WireGuard: Curve25519 + ChaCha20-Poly1305 + BLAKE2s |
| **Transport (inner)** | PQ TLS 1.3: ML-KEM-768 + AES-256-GCM (via tunnel-open) |
| **Identity** | Unique keypair + preshared key per peer |
| **File protection** | umask 077 on all keys (owner-only read, mode 600) |
| **Input validation** | Strict `[a-zA-Z0-9_-]` peer names (prevents injection) |
| **No eval** | Zero use of `eval` in the entire codebase |
| **Token masking** | API tokens masked in all logs (last 4 chars only) |
| **Audit trail** | Every operation logged with timestamp, user, and result |
| **Tamper evidence** | Optional Capsule Protocol sealing (SHA3-256 + Ed25519) |
| **Revocation** | Immediate removal from live WireGuard interface |
| **Archival** | Revoked configs archived, never deleted (compliance) |
| **Key rotation** | Built-in with dry-run safety, automatic backup |
| **Error trapping** | `set -euo pipefail` + ERR trap logs failures to audit |

See [docs/CRYPTO-NOTICE.md](docs/CRYPTO-NOTICE.md) for WireGuard's cryptographic primitives and post-quantum analysis.

## Compliance Positioning

| Framework | Key Controls |
|-----------|-------------|
| **HIPAA** | 164.312(e)(1) Transmission Security, access control, audit controls |
| **CMMC L1-L2** | AC.L2-3.1.12/13/14 Remote access monitoring, encrypted sessions |
| **FedRAMP** | AC-17, SC-8, AU-2/3 (relay must run on authorized infrastructure) |
| **SOC 2** | CC6.1 Logical access, CC6.7 Encryption in transit |
| **ISO 27001** | A.10 Cryptography, A.9 Access Control, A.12 Operations Security |

For FIPS-mandatory environments: WireGuard uses ChaCha20-Poly1305, which is not FIPS 140-2/140-3 validated. Substitute IPsec with FIPS-validated modules for those deployments.

## Testing

370+ tests across three tiers using [bats-core](https://github.com/bats-core/bats-core):

```bash
make test              # All tests (unit + integration)
make test-unit         # Lib functions in isolation
make test-integration  # Full peer lifecycle workflows
make test-smoke        # File existence and structure
```

Tests cover: input validation, key generation, registry CRUD, audit logging, Capsule sealing, certificate generation, PQ TLS config, firewall rules, service lifecycle, file permissions (600/700), peer lifecycle, key rotation, security hardening (no eval, safe umask), edge cases, and error paths.

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
| `ssh` | Remote relay setup via `--provider=ssh` |

## Use in Your Own Project

QP Tunnel is designed to be embedded or forked.

**Embed via Makefile:**
```makefile
include path/to/tunnel/Makefile
```

**Rebrand:**
```bash
export TUNNEL_APP_NAME=mycompany
# Paths become ~/.config/mycompany/, tags become mycompany-tunnel, etc.
```

**Fork and customize:** the code is modular. `lib/` contains all shared logic. Scripts are thin wrappers. Swap the relay provider, change the subnet, add your own audit backend.

## Project Structure

```
.
├── tunnel-setup-relay.sh        # Relay provisioning (SSH, local, DigitalOcean, script)
├── tunnel-join.sh               # Join relay from target device
├── tunnel-add-peer.sh           # Add peer (config + QR)
├── tunnel-remove-peer.sh        # Revoke peer (immediate)
├── tunnel-status.sh             # Peer status with live data
├── tunnel-rotate-keys.sh        # Key rotation (dry-run default)
├── tunnel-open.sh               # Expose service with PQ TLS
├── tunnel-close.sh              # Stop exposing a service
├── tunnel-list.sh               # List open services
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
├── tests/
│   ├── unit/                    # 15 test files
│   ├── integration/             # 6 test files
│   └── smoke/                   # Standalone verification
├── docs/
│   ├── CRYPTO-NOTICE.md         # Cryptographic analysis
│   └── GUIDE.md                 # Narrative walkthrough
├── .env.tunnel.example          # Configuration template
├── Makefile                     # All operations as Make targets
├── VERSION                      # 0.1.0
├── LICENSE                      # Apache 2.0
├── CONTRIBUTING.md              # How to contribute
├── SECURITY.md                  # Vulnerability reporting
└── NOTICE                       # Copyright + attribution
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. Issues and pull requests welcome.

## License

Apache License 2.0. See [LICENSE](LICENSE).

Copyright 2026 Quantum Pipes Technologies, LLC.
