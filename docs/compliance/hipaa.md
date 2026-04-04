# HIPAA Security Rule

The HIPAA Security Rule (45 CFR Part 164, Subparts A and C) establishes standards for protecting electronic Protected Health Information (ePHI). QP Tunnel provides infrastructure-level capabilities that support technical safeguards for transmission security, access control, and audit controls.

HIPAA has no formal certification. Compliance is demonstrated through risk analysis, attestation, and audit readiness.

---

## Technical Safeguards (164.312)

| Standard | Specification | How Tunnel Addresses It |
|---|---|---|
| **164.312(a)(1)** | Access control | Each peer receives a unique Curve25519 keypair, a unique preshared key, and a unique tunnel IP. `tunnel-remove-peer.sh` revokes access immediately by removing the peer from the live WireGuard interface. No grace period, no session expiry. |
| **164.312(a)(2)(i)** | Unique user identification | `peers.json` maps each peer name to a unique IP address, public key, and creation timestamp. The registry tracks the full lifecycle: active, revoked (with revocation timestamp). |
| **164.312(a)(2)(iv)** | Encryption and decryption | WireGuard encrypts all tunnel traffic with ChaCha20-Poly1305. `tunnel-open` adds a second encryption layer with PQ TLS 1.3 (ML-KEM-768 + AES-256-GCM) for exposed services. |
| **164.312(b)** | Audit controls | Every operation writes a structured JSON entry to `audit.log` with timestamp, action, status, message, and user. Optional Capsule Protocol sealing provides tamper-evident cryptographic proof of audit integrity. |
| **164.312(c)(1)** | Integrity | Capsule Protocol integration seals audit records with SHA3-256 + Ed25519 signatures. Hash chain verification detects any modification, deletion, or insertion of records. |
| **164.312(e)(1)** | Transmission security | All data in transit passes through WireGuard's encrypted tunnel (Curve25519/ChaCha20-Poly1305). Split-tunnel routing ensures only VPN subnet traffic traverses the tunnel, reducing attack surface. |
| **164.312(e)(2)(i)** | Integrity controls | Double encryption architecture: WireGuard outer layer + PQ TLS inner layer. Both must fail simultaneously for data exposure. Per-service TLS certificates signed by an internal Ed25519 CA provide endpoint authentication. |
| **164.312(e)(2)(ii)** | Encryption | WireGuard provides always-on encryption with no unencrypted fallback. The protocol has no option to disable encryption. `tunnel-open` services bind exclusively to the tunnel interface with firewall rules restricting access to the tunnel subnet. |

## Administrative Safeguards (164.308)

| Standard | Specification | How Tunnel Addresses It |
|---|---|---|
| **164.308(a)(1)(ii)(D)** | Information system activity review | `audit.log` provides structured records of all tunnel operations. `tunnel-status.sh` shows live handshake data per peer. Capsule chain verification confirms audit completeness. |
| **164.308(a)(4)** | Information access management | Peer access is explicit: `tunnel-add-peer.sh` grants access, `tunnel-remove-peer.sh` revokes it. No implicit trust. No wildcard access. |
| **164.308(a)(5)(ii)(D)** | Password management | Tunnel authentication uses cryptographic keys, not passwords. Key rotation via `tunnel-rotate-keys.sh` with dry-run safety and automatic backup. |

## What Tunnel Provides

- Encrypted transport for all ePHI in transit (double encryption for exposed services)
- Unique cryptographic identity per user/peer
- Immediate access revocation
- Structured audit logging with optional tamper-evident sealing
- Key rotation with backup and dry-run verification
- Firewall isolation for exposed services
- Archival of revoked peer configs (never deleted)

## Complementary Controls

The following HIPAA requirements are outside the tunnel's scope and must be addressed by the deployment environment:

- **164.312(d)** Person or entity authentication: user identity verification, MFA
- **164.308(a)(3)** Workforce security: organizational HR and access policies
- **164.308(a)(6)** Security incident procedures: organizational response process (Tunnel provides audit evidence for investigation)
- **164.310** Physical safeguards: facility security for relay and target infrastructure
- **164.314** Business associate agreements: contractual obligations
- **FIPS encryption:** WireGuard uses ChaCha20-Poly1305, which is not FIPS 140-3 validated. For environments requiring FIPS-validated encryption, substitute IPsec with FIPS-validated modules.

---

[Back to Compliance Overview](./README.md)
