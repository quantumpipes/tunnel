# CMMC 2.0

The Cybersecurity Maturity Model Certification (CMMC) 2.0 is required for Department of Defense contractors handling Controlled Unclassified Information (CUI). CMMC Level 2 aligns with NIST SP 800-171 Rev. 2 (110 controls). QP Tunnel provides infrastructure-level capabilities that address access control, audit, and system/communications protection requirements for remote access scenarios.

---

## Access Control (AC)

| Control | Requirement | How Tunnel Addresses It |
|---|---|---|
| **AC.L2-3.1.12** | Monitor and control remote access sessions | Every tunnel operation is logged to `audit.log` with timestamp, action, user, and result. `tunnel-status.sh` shows live handshake data, endpoint addresses, and connection state per peer. |
| **AC.L2-3.1.13** | Employ cryptographic mechanisms to protect remote access sessions | WireGuard encrypts all tunnel traffic with Curve25519/ChaCha20-Poly1305. `tunnel-open` adds PQ TLS 1.3 (ML-KEM-768 + AES-256-GCM) for exposed services. No unencrypted fallback exists. |
| **AC.L2-3.1.14** | Route remote access via managed access control points | All remote access routes through the relay server (10.8.0.1). Split-tunnel configuration ensures only VPN subnet traffic traverses the relay. The relay forwards encrypted packets without inspecting or storing payload data. |
| **AC.L2-3.1.15** | Authorize remote execution of privileged commands | Peer access is explicit and named. Each peer receives a unique keypair, preshared key, and tunnel IP. `tunnel-remove-peer.sh` revokes access immediately. Firewall rules restrict exposed services to the tunnel subnet. |

## Audit and Accountability (AU)

| Control | Requirement | How Tunnel Addresses It |
|---|---|---|
| **AU.L2-3.3.1** | Create audit records for defined events | Every command (`setup_relay`, `tunnel_join`, `peer_add`, `peer_remove`, `key_rotate`, `service_open`, `service_close`) writes a structured JSON entry to `audit.log`. Error traps log failures with script name and line number. |
| **AU.L2-3.3.2** | Unique user accountability | `peers.json` maps each peer name to a unique IP, public key, and creation timestamp. Audit entries include the `user` field. Token values are masked (last 4 chars only). |
| **AU.L2-3.3.4** | Alert on audit logging process failure | `set -euo pipefail` with ERR trap ensures any failure is caught and logged. Applications monitoring `audit.log` can alert on `"status": "failure"` entries. |
| **AU.L2-3.3.5** | Correlate audit review, analysis, and reporting | Structured JSON format enables programmatic parsing, correlation, and reporting. Capsule Protocol integration provides `correlation_id` and chain-based temporal ordering. |
| **AU.L2-3.3.8** | Protect audit information | Optional Capsule Protocol sealing provides SHA3-256 + Ed25519 tamper evidence. Hash chain verification detects modification, deletion, or insertion of records. Key files use mode 600 (owner-only). |
| **AU.L2-3.3.9** | Manage and retain audit logs | `audit.log` uses append-only JSONL format. Revoked peer configs are archived, never deleted. `capsules.db` provides SQLite-backed persistent storage for sealed records. |

## System and Communications Protection (SC)

| Control | Requirement | How Tunnel Addresses It |
|---|---|---|
| **SC.L2-3.13.8** | Implement cryptographic mechanisms to prevent unauthorized disclosure during transmission | Double encryption: WireGuard outer layer (Curve25519/ChaCha20-Poly1305) + PQ TLS inner layer (ML-KEM-768/AES-256-GCM) for exposed services. Both must fail simultaneously for data exposure. |
| **SC.L2-3.13.10** | Establish and manage cryptographic keys | `tunnel-rotate-keys.sh` rotates relay keys with dry-run safety and automatic backup. Per-peer keys are generated at creation time. Per-service TLS certificates are signed by an internal Ed25519 CA. All keys use umask 077 (mode 600). |
| **SC.L2-3.13.11** | Employ FIPS-validated cryptography | **Partial.** Inner PQ TLS layer uses ML-KEM-768 (FIPS 203) and AES-256-GCM. Audit sealing uses SHA3-256 (FIPS 202) and Ed25519 (FIPS 186-5). However, WireGuard's outer layer uses ChaCha20-Poly1305, which is not FIPS-validated. See the FIPS note below. |

## What Tunnel Provides

- Encrypted remote access with unique cryptographic identity per peer
- Managed access control point (relay server)
- Immediate peer revocation with archival
- Structured audit logging of all operations
- Key rotation with backup and dry-run verification
- Firewall isolation for exposed services (tunnel subnet only)
- Post-quantum TLS for exposed services
- Optional tamper-evident audit sealing (Capsule Protocol)

## Complementary Controls

The following CMMC requirements are outside the tunnel's scope:

- **AC.L2-3.1.1 through 3.1.11** Access control policies: application-level authentication, authorization, MFA
- **IA** Identification and authentication: user identity management, credential policies
- **IR** Incident response: organizational procedures (Tunnel provides audit evidence)
- **MP** Media protection: physical media security
- **PE** Physical protection: facility security for relay and target infrastructure
- **PS** Personnel security: organizational workforce management
- **RA** Risk assessment: organizational risk analysis process

## FIPS Note

WireGuard uses ChaCha20-Poly1305, which is not FIPS 140-2/140-3 validated. For CMMC assessments requiring FIPS-validated cryptography (SC.L2-3.13.11), substitute IPsec with FIPS-validated modules for the outer tunnel layer. The inner PQ TLS layer and audit sealing use FIPS-approved algorithms.

For classified environments (SECRET and above), no software VPN qualifies. Those deployments require NSA-approved Type 1 hardware encryption devices.

---

[Back to Compliance Overview](./README.md)
