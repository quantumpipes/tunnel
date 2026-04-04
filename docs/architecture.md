---
title: "QP Tunnel Architecture"
description: "Technical architecture of QP Tunnel: double-encryption model, component design, state management, peer lifecycle, service exposure, audit chain, key management, and network topology."
date_modified: "2026-04-04"
ai_context: |
  Full architecture of QP Tunnel. Covers the double-encryption model
  (WireGuard outer + PQ TLS inner), 9 commands and 5 library modules,
  JSON state management (peers.json, services.json), peer lifecycle,
  service exposure via internal CA + Caddy + firewall, JSONL audit with
  optional Capsule Protocol sealing, key management and rotation, network
  topology with split-tunnel routing, and multi-provider relay abstraction.
  Source: tunnel-*.sh, lib/ (common.sh, registry.sh, audit.sh, wireguard.sh, open.sh).
---

# Architecture

> **Double-encrypted tunnels. JSON state. Cryptographic audit. Zero dependencies on cloud services.**

---

## Design Philosophy

QP Tunnel follows three principles:

1. **Shell-native.** Nine shell scripts, five library modules, zero compiled binaries. Every operation is inspectable, auditable, and modifiable.
2. **State as files.** Two JSON files (peers.json, services.json) and one JSONL log (audit.log) hold all state. No database server. No daemon. Back them up with `cp`.
3. **Defense in depth.** WireGuard encrypts the tunnel. PQ TLS encrypts the payload. Firewall rules restrict the port. The CA restricts trust. Each layer operates independently.

---

## Double-Encryption Model

<!-- VERIFIED: lib/open.sh:1-10, docs/CRYPTO-NOTICE.md:17-28 -->

Every exposed service runs through two independent encryption layers:

```
┌─────────────────────────────────────────────────────────────────┐
│                        DATA FLOW                                │
│                                                                 │
│  Client App                                      Local Service  │
│     │                                                 ▲         │
│     ▼                                                 │         │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  INNER LAYER: PQ TLS 1.3                                │   │
│  │  Key Exchange:  X25519MLKEM768 (hybrid PQ)              │   │
│  │  Bulk Cipher:   AES-256-GCM                             │   │
│  │  Certificates:  Ed25519 (internal CA)                   │   │
│  │  Implementation: Caddy (Go 1.24+ stdlib ML-KEM-768)    │   │
│  └──────────────────────────────────────────────────────────┘   │
│     │                                                 ▲         │
│     ▼                                                 │         │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  OUTER LAYER: WireGuard                                 │   │
│  │  Key Exchange:  Curve25519 (X25519)                     │   │
│  │  Bulk Cipher:   ChaCha20-Poly1305                       │   │
│  │  Hashing:       BLAKE2s                                 │   │
│  │  Implementation: Linux kernel module                    │   │
│  └──────────────────────────────────────────────────────────┘   │
│     │                                                 ▲         │
│     ▼                                                 │         │
│  [  UDP packets over public internet  ]                         │
└─────────────────────────────────────────────────────────────────┘
```

| Layer | Protocol | Key Exchange | Encryption | PQ Status |
|---|---|---|---|---|
| Outer | WireGuard | Curve25519 | ChaCha20-Poly1305 | Classical only |
| Inner | TLS 1.3 | X25519MLKEM768 | AES-256-GCM | Post-quantum hybrid |

Both layers must fail simultaneously for data exposure. If Curve25519 is broken by a quantum computer, the inner PQ TLS layer still protects session data. If ML-KEM-768 has an implementation flaw, WireGuard's outer layer still protects.

The outer layer (WireGuard) is always active for all tunnel traffic. The inner layer (PQ TLS) activates when you expose services via `tunnel-open`.

---

## Component Architecture

### 9 Commands

| Command | Purpose | Key Operations |
|---|---|---|
| `tunnel-setup-relay.sh` | Provision relay server | Install WireGuard, generate keypair, configure NAT, enable firewall |
| `tunnel-join.sh` | Connect target device to relay | Generate device keypair + PSK, create systemd service |
| `tunnel-add-peer.sh` | Grant access to a person or device | Generate keypair, allocate IP, hot-add to interface, output QR code |
| `tunnel-remove-peer.sh` | Revoke access immediately | Hot-remove from interface, archive config, mark revoked in registry |
| `tunnel-status.sh` | Display live connection data | Query WireGuard for handshake times, transfer stats, endpoints |
| `tunnel-rotate-keys.sh` | Rotate relay cryptographic keys | Dry-run by default, backup old keys, update config and registry |
| `tunnel-open.sh` | Expose a local service with PQ TLS | Generate cert, start Caddy, apply firewall rules, register service |
| `tunnel-close.sh` | Stop exposing a service | Stop Caddy, remove firewall rules, archive certs, deregister |
| `tunnel-list.sh` | List exposed services | Read services.json, check process status |

Every command sources `tunnel-preflight.sh`, which loads environment, applies defaults, and initializes the config directory.

### 5 Library Modules

<!-- VERIFIED: lib/common.sh:1-168, lib/registry.sh:1-243, lib/audit.sh:1-180, lib/wireguard.sh:1-163, lib/open.sh:1-643 -->

| Module | File | Responsibility |
|---|---|---|
| **Common** | `lib/common.sh` | Logging, input validation, config defaults, environment loading, token masking |
| **Registry** | `lib/registry.sh` | Peer CRUD against `peers.json` via `jq`, IP pool allocation, relay metadata |
| **Audit** | `lib/audit.sh` | JSONL audit log writer, Capsule Protocol sealing, ERR trap handler |
| **WireGuard** | `lib/wireguard.sh` | Keypair generation, hot add/remove peers, config rendering, interface queries |
| **Open** | `lib/open.sh` | Internal CA, per-service TLS certs, Caddy management, firewall rules, service registry |

```
┌────────────────────────────────────────────────────────┐
│                    9 Command Scripts                    │
│  setup-relay  join  add-peer  remove-peer  status      │
│  rotate-keys  open  close  list                        │
├────────────────────────────────────────────────────────┤
│                     tunnel-preflight                    │
│              (env loading, config init)                 │
├──────────┬──────────┬──────────┬──────────┬────────────┤
│  common  │ registry │  audit   │ wireguard│   open     │
│  .sh     │ .sh      │  .sh     │ .sh      │   .sh      │
│          │          │          │          │            │
│ logging  │ peers.json│ JSONL   │ wg CLI   │ CA + certs │
│ validate │ IP pool  │ Capsule │ hot ops  │ Caddy mgmt │
│ defaults │ relay    │ traps   │ configs  │ firewall   │
│ masking  │ CRUD     │         │ queries  │ services   │
└──────────┴──────────┴──────────┴──────────┴────────────┘
```

---

## State Management

### Directory Structure

All state lives in `~/.config/${TUNNEL_APP_NAME}/` (default: `~/.config/qp-tunnel/`):

```
~/.config/qp-tunnel/
├── peers.json              Peer registry (relay metadata, peers, IP pool)
├── services.json           Open services registry
├── audit.log               Structured JSONL audit log
├── capsules.db             SQLite Capsule database (tamper-evident)
├── relay.key               Relay private key (mode 600)
├── relay.pub               Relay public key
├── relay-server.json       Relay server metadata
├── server-relay.psk        Server-relay preshared key (mode 600)
├── tls/
│   ├── ca.key              Ed25519 CA private key (mode 600)
│   ├── ca.crt              CA public certificate
│   ├── ca.mobileconfig     iOS trust profile
│   ├── <name>.key          Per-service TLS key (mode 600)
│   └── <name>.crt          Per-service TLS cert
├── services/
│   └── <name>/
│       ├── Caddyfile        Caddy config for this service
│       └── caddy.pid        Caddy process ID
├── peers/
│   └── <name>/
│       ├── <name>.conf      WireGuard client config
│       └── preshared.key    Peer preshared key (mode 600)
├── archive/                 Revoked peers + closed service certs
└── key-backups/             Old keys from rotation
```

### peers.json

<!-- VERIFIED: lib/registry.sh:41-52 -->

The peer registry is a flat JSON file managed entirely through `jq`. No database required.

```json
{
  "version": 1,
  "relay": {
    "endpoint": "203.0.113.10:51820",
    "public_key": "base64...",
    "tunnel_ip": "10.8.0.1"
  },
  "peers": [
    {
      "name": "alice",
      "public_key": "base64...",
      "tunnel_ip": "10.8.0.10",
      "status": "active",
      "added_at": "2026-04-04T12:00:00Z",
      "added_by": "operator",
      "revoked_at": null
    }
  ],
  "ip_pool": {
    "subnet": "10.8.0.0/24",
    "next_client_ip": "10.8.0.11",
    "reserved": ["10.8.0.1", "10.8.0.2"]
  }
}
```

Key design decisions:

- **Revoked peers are never deleted.** They remain in the array with `status: "revoked"` and a `revoked_at` timestamp. This preserves audit history.
- **IP allocation is sequential.** IPs start at `.10` and increment. The pool supports up to 244 peers (`.10` through `.254`).
- **Duplicate detection checks active peers only.** You can re-add a name after revoking the previous holder.

### services.json

<!-- VERIFIED: lib/open.sh:449-461 -->

The service registry follows the same pattern:

```json
{
  "version": 1,
  "services": [
    {
      "name": "grafana",
      "upstream": "localhost:3000",
      "port": 8443,
      "status": "active",
      "exposed_at": "2026-04-04T12:00:00Z",
      "cert_expires": "Apr  4 12:00:00 2027 GMT",
      "caddy_pid": 12345
    }
  ],
  "port_pool": {
    "range_start": 8443,
    "range_end": 8499,
    "next_port": 8444
  }
}
```

Ports are allocated from the range 8443 to 8499 (57 concurrent services). Closed services remain in the array with `status: "closed"` and a `closed_at` timestamp.

---

## Peer Lifecycle

```
         ADD                    CONNECT               REVOKE
   ┌─────────────┐        ┌─────────────┐       ┌─────────────┐
   │ Generate    │        │ Peer scans  │       │ Hot-remove  │
   │ keypair +   │───────▶│ QR or pastes│──────▶│ from live   │
   │ PSK + IP    │        │ config      │       │ WireGuard   │
   └─────────────┘        └─────────────┘       └─────────────┘
         │                       │                     │
         ▼                       ▼                     ▼
   ┌─────────────┐        ┌─────────────┐       ┌─────────────┐
   │ Register in │        │ WireGuard   │       │ Archive     │
   │ peers.json  │        │ handshake   │       │ config to   │
   │ (active)    │        │ established │       │ archive/    │
   └─────────────┘        └─────────────┘       └─────────────┘
         │                       │                     │
         ▼                       ▼                     ▼
   ┌─────────────┐        ┌─────────────┐       ┌─────────────┐
   │ Hot-add to  │        │ Split-tunnel │       │ Mark        │
   │ live WG     │        │ traffic     │       │ "revoked"   │
   │ interface   │        │ flows       │       │ in registry │
   └─────────────┘        └─────────────┘       └─────────────┘
         │                                            │
         ▼                                            ▼
   ┌─────────────┐                              ┌─────────────┐
   │ Audit log   │                              │ Audit log   │
   │ + Capsule   │                              │ + Capsule   │
   └─────────────┘                              └─────────────┘
```

**Add:** `tunnel-add-peer.sh` generates a unique keypair and preshared key, allocates the next IP from the pool, writes a client config file, hot-adds the peer to the running WireGuard interface (no restart), and creates an audit record.

**Revoke:** `tunnel-remove-peer.sh` hot-removes the peer from the WireGuard interface (access drops instantly), archives the config directory to `archive/`, marks the peer as revoked with a timestamp, and creates an audit record. The revocation is immediate, not dependent on session expiry or grace periods.

---

## Service Exposure Model

<!-- VERIFIED: lib/open.sh:34-68, 144-201, 210-288, 351-418 -->

When you run `tunnel-open --name grafana --to localhost:3000`, six things happen:

### 1. Internal CA (one-time)

An Ed25519 self-signed CA is generated with 10-year validity. This CA signs all service certificates. It is created once and reused for all subsequent services.

Files: `tls/ca.key` (mode 600), `tls/ca.crt`, `tls/ca.mobileconfig` (iOS trust profile).

### 2. Per-Service TLS Certificate

An Ed25519 key and certificate are generated for the service, signed by the internal CA. The certificate includes Subject Alternative Names for the tunnel server IP (`10.8.0.2`) and `<name>.tunnel`.

Validity: 1 year. Files: `tls/<name>.key` (mode 600), `tls/<name>.crt`.

### 3. Caddy Reverse Proxy

A Caddyfile is rendered from the template (`templates/Caddyfile.open.tpl`) with PQ TLS 1.3 configuration:

- TLS cipher: X25519MLKEM768 key exchange
- Listens on tunnel interface IP only (e.g., `10.8.0.2:8443`)
- Proxies to the local upstream (e.g., `localhost:3000`)

Caddy starts as a background process. Its PID is recorded for lifecycle management.

### 4. Interface Binding

The listening port binds exclusively to the tunnel interface IP. It is unreachable from LAN, WAN, or any other network interface. Even without firewall rules, the service is invisible outside the tunnel.

### 5. Firewall Rules

Per-service firewall rules restrict the port to the tunnel subnet only. The system auto-detects nftables or iptables:

- **nftables:** Creates a chain in table `inet tunnel-open` with accept for subnet, drop for everything else.
- **iptables:** Creates a chain `TUNNEL-<NAME>` with equivalent rules.

### 6. Registration and Audit

The service is registered in `services.json` with port, upstream, PID, and certificate expiration. An audit log entry and optional Capsule are created.

---

## Audit Chain

<!-- VERIFIED: lib/audit.sh:28-71, 140-155, 157-179 -->

### JSONL Audit Log

Every operation writes a structured JSON line to `audit.log`:

```json
{"timestamp":"2026-04-04T12:00:00Z","action":"peer_add","status":"success","message":"Added peer alice (10.8.0.10)","user":"operator","details":{"name":"alice","tunnel_ip":"10.8.0.10"}}
```

Logged actions: `setup_relay`, `tunnel_join`, `peer_add`, `peer_remove`, `key_rotate`, `service_open`, `service_close`, and all error traps.

Security properties of the audit log:

- **Token masking.** API tokens are replaced with asterisks (last 4 characters visible) before writing.
- **Error trapping.** Every script registers `audit_trap_handler` on ERR. If any command fails, the failure is recorded with script name and line number.
- **Atomic writes.** Each entry is a single `printf` appended to the file.

### Capsule Protocol Integration

When `qp-capsule` is installed, every audit entry is sealed as a tamper-evident Capsule:

```
audit_log()
    │
    ├──▶ Append JSON line to audit.log (fast local index)
    │
    └──▶ _capsule_seal()
              │
              └──▶ qp-capsule seal --db capsules.db
                        │
                        ├──▶ SHA3-256 hash
                        ├──▶ Ed25519 signature
                        └──▶ Hash chain link
```

The JSONL audit log serves as a fast local index. Capsules are the cryptographic source of truth. You can verify the entire chain at any time:

```bash
qp-capsule verify --db ~/.config/qp-tunnel/capsules.db
```

If `qp-capsule` is not installed, audit logging continues normally without sealing. The system never blocks on Capsule availability.

---

## Key Management

### Key Types

| Key | Algorithm | Generated By | Storage | Purpose |
|---|---|---|---|---|
| Relay keypair | Curve25519 | `wg genkey` / `wg pubkey` | `relay.key` (600), `relay.pub` | WireGuard relay identity |
| Peer keypair | Curve25519 | `wg genkey` / `wg pubkey` | `peers/<name>/<name>.conf` | WireGuard peer identity |
| Preshared key | 256-bit random | `wg genpsk` | `peers/<name>/preshared.key` (600) | Additional symmetric layer per peer |
| CA key | Ed25519 | `openssl genpkey -algorithm Ed25519` | `tls/ca.key` (600) | Signs all service TLS certificates |
| Service key | Ed25519 | `openssl genpkey -algorithm Ed25519` | `tls/<name>.key` (600) | Per-service TLS identity |
| Capsule key | Ed25519 | `qp-capsule` auto-generate | `~/.quantumpipes/key` (600) | Audit record signing |

### Key Generation Safety

<!-- VERIFIED: lib/common.sh:97-99, lib/wireguard.sh:21-27 -->

All key generation follows the same safety protocol:

1. `set_safe_umask` sets umask 077 before any key operation
2. Private keys are captured via command substitution (never echoed to terminal)
3. Files are written with mode 600 (owner-only read/write)
4. Private keys never appear in logs, audit entries, or command output

### Key Rotation

`tunnel-rotate-keys.sh` rotates the relay's WireGuard keypair:

1. **Dry-run (default).** Shows what would happen without changing anything.
2. **Confirm (`CONFIRM=1`).** Generates new keypair, backs up old keys to `key-backups/`, updates WireGuard config, restarts the interface, updates `peers.json`.

After rotation, all active peers need new configs with the updated relay public key. The audit log records the rotation event.

Rotation schedule: every 90 days in standard environments, monthly in high-security contexts, immediately when someone with relay access leaves the organization.

---

## Network Topology

```
                        INTERNET
                           │
                           │ UDP :51820
                           ▼
                ┌──────────────────────┐
                │    Relay Server      │
                │    10.8.0.1          │
                │                      │
                │  - Forwards packets  │
                │  - Holds no data     │
                │  - NAT + IP forward  │
                │  - No app logic      │
                └───┬──────────────┬───┘
                    │              │
         WireGuard  │              │  WireGuard
         (persistent)             (on-demand)
                    │              │
          ┌─────────┴──┐     ┌────┴──────────┐
          │ Target     │     │ Remote Peers   │
          │ Device     │     │                │
          │ 10.8.0.2   │     │ alice: .0.10   │
          │            │     │ bob:   .0.11   │
          │ Auto-      │     │ carol: .0.12   │
          │ reconnect  │     │ ...    .0.254  │
          │ via systemd│     │                │
          └────────────┘     └────────────────┘
```

### Split-Tunnel Routing

Only traffic destined for `10.8.0.0/24` routes through the VPN. All other traffic takes the peer's normal internet path.

This design has two consequences:

1. **Performance.** You are not routing all internet traffic through the relay. The relay handles only tunnel traffic.
2. **Attack surface.** The tunnel carries only your traffic. No unrelated internet traffic passes through the encrypted channel.

The `TUNNEL_ALLOWED_IPS` variable controls the routed range. Default: `10.8.0.0/24`.

### Relay Role

The relay is a rendezvous point. It forwards encrypted WireGuard packets between peers. It cannot decrypt the traffic (it lacks peer private keys). If the relay is compromised, attackers see only encrypted packets they cannot read.

The relay runs no application logic. It holds no data. Its only functions are WireGuard packet forwarding, NAT, and IP forwarding.

---

## Provider Abstraction

<!-- VERIFIED: README.md:129-138 -->

`tunnel-setup-relay.sh` supports four relay provisioning modes:

| Provider | Flag | How It Works |
|---|---|---|
| **SSH** | `--provider=ssh --host=IP` | SSHs into an existing server, installs WireGuard, configures everything |
| **Local** | `--provider=local` | Runs setup directly on the current machine |
| **DigitalOcean** | `--provider=digitalocean` | Provisions a new Droplet via API, waits for boot, configures via SSH |
| **Script** | `--generate-script` | Outputs the setup commands to stdout for manual execution |

Auto-detection: if `DO_API_TOKEN` is set, defaults to DigitalOcean. If `RELAY_HOST` is set, defaults to SSH.

The provider abstraction is deliberate. The relay is any Linux server with WireGuard. The provisioning method is a deployment detail, not an architectural constraint. You can use AWS, Hetzner, Linode, Oracle Cloud (free tier), a Raspberry Pi, or any machine with a public IP and SSH access.

---

## Related Documentation

- [Why QP Tunnel](./why-tunnel.md) -- Business case and comparison positioning
- [Security Evaluation](./security.md) -- Cryptographic inventory and threat model for CISOs
- [Cryptographic Notice](./CRYPTO-NOTICE.md) -- WireGuard crypto primitives and PQ analysis
- [Complete Guide](./GUIDE.md) -- Narrative walkthrough of all capabilities
