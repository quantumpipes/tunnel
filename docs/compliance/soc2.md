# SOC 2 Type II

SOC 2 Type II reports evaluate the design and operating effectiveness of controls relevant to the Trust Services Criteria (TSC). QP Tunnel provides infrastructure-level capabilities that support the Security and Availability categories, specifically logical access, encryption in transit, and system monitoring for remote access scenarios.

---

## Common Criteria (CC) Mappings

### CC6: Logical and Physical Access Controls

| Criterion | Requirement | How Tunnel Addresses It |
|---|---|---|
| **CC6.1** | Logical access security | Each peer receives a unique Curve25519 keypair, a unique preshared key, and a unique tunnel IP address. `peers.json` maintains the authoritative registry of all peers (active and revoked). Access is granted explicitly via `tunnel-add-peer.sh` and revoked immediately via `tunnel-remove-peer.sh`. |
| **CC6.2** | Prior to issuing credentials, register and authorize users | `tunnel-add-peer.sh` generates credentials only when explicitly invoked by an operator. Each peer creation is logged to `audit.log` with the operator's username and timestamp. |
| **CC6.3** | Credential lifecycle management | `tunnel-rotate-keys.sh` rotates relay keys with dry-run safety and automatic backup. Revoked peer credentials are archived (never deleted). Key files are stored with mode 600 (owner-only). |
| **CC6.6** | Restrict access through managed access points | The relay server (10.8.0.1) is the sole ingress point. Exposed services bind exclusively to the tunnel interface. Firewall rules (nftables or iptables) restrict access to the tunnel subnet (10.8.0.0/24). LAN and WAN interfaces cannot reach exposed services. |
| **CC6.7** | Restrict transmission of data to authorized parties | WireGuard encrypts all tunnel traffic (Curve25519/ChaCha20-Poly1305). `tunnel-open` adds PQ TLS 1.3 (ML-KEM-768 + AES-256-GCM) for exposed services. Split-tunnel routes only VPN subnet traffic through the relay. No unencrypted fallback exists. |
| **CC6.8** | Prevent or detect unauthorized software | Input validation uses strict regex (`[a-zA-Z0-9_-]`) for all peer names. Zero use of `eval` in the codebase. `set -euo pipefail` with ERR traps catches unexpected failures. |

### CC7: System Operations

| Criterion | Requirement | How Tunnel Addresses It |
|---|---|---|
| **CC7.1** | Detect and monitor for security events | `audit.log` records all operations as structured JSON (JSONL). `tunnel-status.sh` provides live handshake data per peer. Error traps log failures with script name and line number. Token values are masked in all output. |
| **CC7.2** | Monitor system components for anomalies | `tunnel-status.sh` shows last handshake time, endpoint address, and data transfer per peer. WireGuard handshakes occur every two minutes during active traffic; "never" indicates a peer has not connected. Operators can identify stale or unexpected connections. |
| **CC7.3** | Evaluate detected events | Structured JSON audit format enables programmatic parsing, filtering, and alerting. Capsule Protocol integration provides tamper-evident chain verification and `correlation_id` for event correlation. |
| **CC7.4** | Respond to identified events | `tunnel-remove-peer.sh` provides immediate revocation. `tunnel-close.sh` stops exposed services and removes firewall rules. Both actions create audit records. Revoked peers are archived for incident investigation. |

### CC8: Change Management

| Criterion | Requirement | How Tunnel Addresses It |
|---|---|---|
| **CC8.1** | Authorize, design, develop, configure, test, and implement changes | `tunnel-rotate-keys.sh` defaults to dry-run mode, showing changes without applying them. `CONFIRM=1` is required for execution. Key backups are created automatically before rotation. Service changes are registered in `services.json`. |

## What Tunnel Provides

- Unique cryptographic identity per peer (keypair + preshared key + tunnel IP)
- Managed access control point with firewall isolation
- Immediate peer revocation with archival (never delete)
- Encrypted transport with double encryption for exposed services
- Structured audit logging of all operations
- Optional tamper-evident audit sealing (Capsule Protocol)
- Key rotation with dry-run safety and automatic backup
- Live connection monitoring via `tunnel-status.sh`
- Input validation and defensive scripting (no eval, strict regex)

## Complementary Controls

The following SOC 2 requirements are outside the tunnel's scope:

- **CC1** Control environment: organizational governance and oversight
- **CC2** Communication and information: organizational policies and procedures
- **CC3** Risk assessment: organizational risk management process
- **CC4** Monitoring activities: management oversight and review
- **CC5** Control activities: organizational policies and enforcement
- **CC6.4/CC6.5** Physical access controls: facility security
- **CC9** Risk mitigation: organizational risk treatment decisions
- User identity management, MFA, and role-based access: application-level
- Backup and disaster recovery: infrastructure-level
- Vulnerability management and patching: operating system level

---

[Back to Compliance Overview](./README.md)
