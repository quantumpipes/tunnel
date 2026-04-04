# Cryptographic Notice: WireGuard VPN Automation

## WireGuard Cryptographic Primitives

WireGuard uses the following fixed cryptographic primitives:

- **Key Exchange:** Curve25519 (X25519)
- **Symmetric Encryption:** ChaCha20-Poly1305
- **Hashing:** BLAKE2s
- **Key Derivation:** HKDF

These are hardcoded in the WireGuard protocol and cannot be changed.

## Post-Quantum TLS (tunnel-open)

The `tunnel-open` command adds a post-quantum TLS 1.3 layer inside the WireGuard tunnel:

- **Key Exchange:** X25519MLKEM768 (hybrid classical + post-quantum, FIPS 203)
- **Bulk Encryption:** AES-256-GCM
- **Certificates:** Ed25519 (internal CA, per-service certs)
- **Implementation:** Caddy built with Go 1.24+ (ML-KEM-768 in Go stdlib)

This creates a double-encryption architecture:

| Layer | Protocol | Key Exchange | Encryption | PQ Status |
|-------|----------|-------------|------------|-----------|
| Outer | WireGuard | Curve25519 | ChaCha20-Poly1305 | Classical only |
| Inner | TLS 1.3 | X25519MLKEM768 | AES-256-GCM | Post-quantum hybrid |

**Why double encryption matters:** If Curve25519 is broken by a quantum computer, the inner PQ TLS layer still protects session data. If ML-KEM-768 has an implementation flaw, WireGuard's outer layer still protects. Both must fail simultaneously for data exposure.

## Tradeoff Rationale

WireGuard does not support post-quantum key exchange (ML-KEM-768) or
post-quantum signatures (ML-DSA-65). This is a protocol-level limitation,
not a configuration choice. The `tunnel-open` PQ TLS layer compensates.

**Why this tradeoff is acceptable for most deployments:**

1. WireGuard's Curve25519 key exchange remains secure against all known
   classical attacks. A quantum computer capable of breaking X25519 does not
   exist today and is not expected within the operational lifetime of a tunnel
   session.

2. WireGuard tunnels are ephemeral transport channels, not long-term storage.
   Data at rest should be protected by your application's own encryption layer.

3. WireGuard keys can be rotated regularly via `tunnel-rotate-keys.sh`. Short key
   lifetimes reduce the window of exposure.

4. No post-quantum tunnel protocol has reached production maturity. Alternatives
   like Rosenpass (WireGuard + ML-KEM hybrid) are experimental.

5. The tunnel carries only control-plane and API traffic between the relay
   and on-premises servers. Sensitive payloads should have independent
   encryption.

## FIPS Consideration

WireGuard uses ChaCha20-Poly1305, which is not FIPS 140-2/140-3 validated.
For environments that mandate FIPS-validated encryption (FedRAMP High,
some CMMC scenarios), consider IPsec with FIPS-validated modules instead.

## Capsule Protocol Integration

When the `qp-capsule` CLI is available, tunnel audit events are sealed as
tamper-evident Capsules using SHA3-256 + Ed25519 (FIPS 202, FIPS 186-5).
This provides cryptographic audit integrity independent of WireGuard's
transport cryptography.

## Mitigation Plan

When WireGuard or a compatible protocol adds post-quantum key exchange support,
this toolkit will adopt it. Candidates to monitor:

- **Rosenpass:** Post-quantum WireGuard extension (McEliece-based, experimental)
- **WireGuard PQ proposals:** Community efforts for ML-KEM integration
- **NIST PQC finalization:** ML-KEM-768 and ML-DSA-65 standardization progress

## Review Schedule

This notice should be reviewed quarterly or whenever NIST publishes updates
to post-quantum cryptography standards.

**Last reviewed:** 2026-03-25
