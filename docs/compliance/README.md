# Regulatory Compliance Mapping

> **How QP Tunnel maps to the frameworks your auditors care about.**

---

## Scope

This directory maps **infrastructure-level** VPN and network security capabilities to regulatory controls. Every mapping describes what QP Tunnel itself provides: encrypted tunnels, peer identity management, immediate revocation, structured audit logging, double encryption (WireGuard + PQ TLS), and firewall isolation.

Application-level controls (user authentication, data classification, organizational policies) are the responsibility of the deployment environment, not the tunnel toolkit.

---

## Cryptographic Posture

| Layer | Algorithm | Standard | Usage |
|---|---|---|---|
| WireGuard (outer) | Curve25519 / ChaCha20-Poly1305 / BLAKE2s | Not FIPS-validated | Tunnel transport encryption |
| PQ TLS (inner) | X25519MLKEM768 / AES-256-GCM | FIPS 203 (ML-KEM), AES | Service exposure via `tunnel-open` |
| Internal CA | Ed25519 | FIPS 186-5 | Per-service TLS certificates |
| Audit sealing | SHA3-256 + Ed25519 | FIPS 202, FIPS 186-5 | Optional Capsule Protocol integration |

**FIPS note:** WireGuard uses ChaCha20-Poly1305, which is not FIPS 140-2/140-3 validated. For FIPS-mandatory environments, substitute IPsec with FIPS-validated modules for the outer tunnel layer.

---

## Framework Mappings

| Framework | Controls Mapped | Document |
|---|---|---|
| [HIPAA Security Rule](./hipaa.md) | 164.312(a), 164.312(b), 164.312(e) | Transmission security, access control, audit |
| [CMMC 2.0 Level 2](./cmmc.md) | AC.L2-3.1.12/13/14, AU.L2-3.3.x, SC.L2-3.13.x | Remote access, encryption, audit |
| [FedRAMP](./fedramp.md) | AC-17, SC-8, SC-13, AU-2, AU-3, AU-6 | Federal cloud authorization |
| [SOC 2 Type II](./soc2.md) | CC6.1, CC6.6, CC6.7, CC7.1, CC7.2 | Trust Services Criteria |
| [ISO 27001:2022](./iso27001.md) | A.5.15, A.8.20, A.8.24, A.8.26 | Annex A controls |

---

## What Tunnel Provides vs. What Requires Complementary Controls

### Tunnel Provides

- Encrypted transport with unique cryptographic identity per peer
- Post-quantum TLS inner layer for exposed services (ML-KEM-768)
- Immediate peer revocation (no grace period, no session expiry)
- Structured JSON audit logging of all operations
- Optional tamper-evident audit sealing via Capsule Protocol
- Firewall isolation binding exposed services to tunnel subnet only
- Key rotation with automatic backup and dry-run safety
- Peer archival (never delete) for compliance retention
- Input validation preventing injection attacks
- Token masking in all log output

### Requires Complementary Controls

- User identity management and multi-factor authentication
- Network perimeter security and intrusion detection
- Physical security of relay and target infrastructure
- Organizational access policies and workforce security
- Incident response procedures (Tunnel provides evidence, not process)
- Data classification and handling policies
- FIPS-validated outer encryption (use IPsec if required)
- Backup and disaster recovery for tunnel state

---

## Related Documentation

- [Cryptographic Notice](../CRYPTO-NOTICE.md): WireGuard primitives, PQ TLS, FIPS analysis
- [Complete Guide](../GUIDE.md): Architecture, commands, security model
- [Capsule Protocol](https://github.com/quantumpipes/capsule): Tamper-evident audit sealing
