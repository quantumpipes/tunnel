# FedRAMP (NIST SP 800-53 Rev. 5)

The Federal Risk and Authorization Management Program (FedRAMP) standardizes security assessment for cloud services used by federal agencies. FedRAMP controls are drawn from NIST SP 800-53 Rev. 5. QP Tunnel provides infrastructure-level capabilities that address controls in the Access Control (AC), Audit (AU), and System and Communications Protection (SC) families for remote access scenarios.

---

## Access Control (AC)

| Control | Title | Baseline | How Tunnel Addresses It |
|---|---|---|---|
| **AC-17** | Remote Access | Low | All remote access routes through the WireGuard relay (10.8.0.1), a single managed access control point. Peer access is explicit: `tunnel-add-peer.sh` grants, `tunnel-remove-peer.sh` revokes immediately. Split-tunnel routes only VPN subnet traffic through the relay. |
| **AC-17(1)** | Automated Monitoring/Control | Moderate | `tunnel-status.sh` provides live handshake data, endpoint addresses, and connection state per peer. `audit.log` records all access grant/revoke operations with timestamps. |
| **AC-17(2)** | Protection of Confidentiality/Integrity of Transmitted Information | Moderate | WireGuard encrypts all tunnel traffic (Curve25519/ChaCha20-Poly1305). `tunnel-open` adds PQ TLS 1.3 (ML-KEM-768 + AES-256-GCM) for exposed services. No unencrypted fallback. |
| **AC-17(3)** | Managed Access Control Points | Moderate | The relay server is the sole ingress point. Exposed services bind exclusively to the tunnel interface. Firewall rules restrict access to the tunnel subnet (10.8.0.0/24). |

## Audit and Accountability (AU)

| Control | Title | Baseline | How Tunnel Addresses It |
|---|---|---|---|
| **AU-2** | Event Logging | Low | All operations are logged: `setup_relay`, `tunnel_join`, `peer_add`, `peer_remove`, `key_rotate`, `service_open`, `service_close`, and error traps. Each entry includes timestamp, action, status, message, and user. |
| **AU-3** | Content of Audit Records | Low | Structured JSON format with timestamp, action name, success/failure status, descriptive message, operating user, and detail fields (peer name, tunnel IP, service name). |
| **AU-6** | Audit Review, Analysis, and Reporting | Low | JSONL format enables programmatic parsing and correlation. Capsule Protocol integration provides chain-based temporal ordering and tamper detection. |
| **AU-9** | Protection of Audit Information | Low | Audit files use owner-only permissions. Optional Capsule Protocol sealing provides SHA3-256 + Ed25519 tamper evidence with hash chain verification. |
| **AU-9(3)** | Cryptographic Protection of Audit Information | High | Capsule Protocol seals each audit event with SHA3-256 (FIPS 202) integrity hash + Ed25519 (FIPS 186-5) digital signature. `chain.verify()` detects modification, deletion, or insertion. |
| **AU-11** | Audit Record Retention | Low | Revoked peer configs are archived, never deleted. `audit.log` uses append-only JSONL. `capsules.db` provides SQLite-backed persistent storage. Retention period is configurable at the deployment level. |

## System and Communications Protection (SC)

| Control | Title | Baseline | How Tunnel Addresses It |
|---|---|---|---|
| **SC-8** | Transmission Confidentiality and Integrity | Moderate | Double encryption: WireGuard outer layer + PQ TLS inner layer for exposed services. Both layers must fail simultaneously for data exposure. |
| **SC-8(1)** | Cryptographic Protection (Transmission) | Moderate | WireGuard: Curve25519/ChaCha20-Poly1305. PQ TLS: X25519MLKEM768/AES-256-GCM. Per-service TLS certificates signed by internal Ed25519 CA. |
| **SC-12** | Cryptographic Key Establishment and Management | Moderate | `tunnel-rotate-keys.sh` handles key rotation with dry-run safety, automatic backup, and audit logging. Per-peer keys generated at creation. Per-service TLS certs from internal CA. All keys stored with mode 600. |
| **SC-13** | Cryptographic Protection | Low | Inner PQ TLS uses ML-KEM-768 (FIPS 203) and AES-256-GCM. Audit sealing uses SHA3-256 (FIPS 202) and Ed25519 (FIPS 186-5). WireGuard outer layer uses ChaCha20-Poly1305 (not FIPS-validated; see note below). |

## Air-Gapped Operation

QP Tunnel is designed for air-gapped federal environments:

- Zero runtime internet dependencies after initial setup
- No telemetry, analytics, or license server
- No phone-home or update checks
- All cryptographic operations use locally generated key material
- State stored in local files (`peers.json`, `audit.log`, `services.json`)
- White-label support for agency-specific branding

## What Tunnel Provides

- Managed remote access control point (relay server)
- Encrypted transport with double encryption for exposed services
- Structured audit logging with optional cryptographic sealing
- Immediate peer revocation
- Key rotation with backup and dry-run verification
- Firewall isolation for exposed services
- Air-gap compatible operation
- Post-quantum TLS for exposed services

## Complementary Controls

The following FedRAMP control families are outside the tunnel's scope:

- **AC-2 through AC-16** Account management, separation of duties, least privilege: application-level
- **AT** Awareness and training: organizational
- **CA** Assessment, authorization, and monitoring: organizational
- **CP** Contingency planning: infrastructure-level backup and recovery
- **IA** Identification and authentication: user identity management, MFA
- **IR** Incident response: organizational procedures (Tunnel provides audit evidence)
- **PE** Physical and environmental protection: facility security

## FIPS Note

WireGuard uses ChaCha20-Poly1305, which is not FIPS 140-2/140-3 validated. For FedRAMP Moderate and High baselines requiring FIPS-validated encryption (SC-13), substitute IPsec with FIPS-validated modules for the outer tunnel layer. The inner PQ TLS layer and audit sealing use FIPS-approved algorithms.

The relay must run on FedRAMP-authorized infrastructure to satisfy the authorization boundary requirements.

---

[Back to Compliance Overview](./README.md)
