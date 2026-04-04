---
title: "Why QP Tunnel"
description: "Business case for QP Tunnel: the problem of secure remote access to on-premises devices, why WireGuard, why automation, why double encryption, why audit logging, and competitive positioning."
date_modified: "2026-04-04"
ai_context: |
  Business case document for QP Tunnel. Covers the remote access problem space,
  WireGuard selection rationale, automation value proposition, double-encryption
  defense-in-depth model, audit logging for compliance, comparison against
  Tailscale/Netbird/Headscale/OpenVPN/IPsec, target use cases, and explicit
  scope boundaries (what Tunnel is NOT).
---

# Why QP Tunnel

> **Secure remote access to on-premises devices should not require a SaaS subscription, a coordination server, or a networking PhD.**

---

## The Problem

You have a device behind a firewall. A server in a clinic. A workstation in a defense contractor's facility. A Raspberry Pi in a remote office. It works perfectly on the local network.

You need to reach it from somewhere else. Push an update. Debug an issue. Give a colleague temporary access. Pull a report.

Your options today are all bad in some way:

**Port forwarding.** You punch a hole in the firewall for SSH or RDP. Now that port is visible to the entire internet. Bots find it within hours. You add IP allowlists, which break when your IP changes. You add fail2ban, which helps but does not solve the fundamental problem: you have exposed a service to the internet.

**Traditional VPN (OpenVPN, IPsec).** You set up a VPN server with a 200-line config, manage certificate authorities, distribute OVPN profiles, troubleshoot MTU issues, deal with connection drops. It works, eventually. But the setup takes hours, the maintenance is ongoing, and revoking a single user requires regenerating certificates.

**SaaS tunneling (Tailscale, Cloudflare Tunnel).** You install an agent, authenticate through a cloud coordination server, and traffic flows. It is easy. It is also a cloud dependency. Your traffic metadata (who connects, when, from where) passes through infrastructure you do not control. For healthcare, defense, and government deployments, this is often a non-starter.

**SSH tunneling.** You forward ports over SSH. It works for one service at a time. Managing multiple tunnels, multiple users, and automatic reconnection turns into a pile of scripts that nobody else can maintain.

None of these solve the full problem: secure, auditable, revocable remote access that you can set up in minutes, that works with any device, that requires no cloud dependency, and that you can hand to a colleague without a training session.

---

## Why WireGuard

WireGuard is the answer to "which VPN protocol?" for three reasons:

### 1. Performance

WireGuard runs in the Linux kernel. Handshakes complete in milliseconds. Throughput matches the network link speed. CPU overhead is negligible. On a Raspberry Pi, WireGuard handles hundreds of megabits per second. OpenVPN on the same hardware caps at 30-50 Mbps.

### 2. Simplicity

A complete WireGuard config is 15 lines. An OpenVPN config is 200+. IPsec (StrongSwan) adds another layer of complexity. WireGuard's codebase is ~4,000 lines of C (auditable). OpenVPN is ~100,000 lines. Smaller attack surface, fewer bugs, faster audits.

### 3. Modern Cryptography

WireGuard uses Curve25519, ChaCha20-Poly1305, and BLAKE2s. These are modern, well-analyzed primitives. No cipher negotiation, no downgrade attacks, no legacy compatibility modes. The protocol was formally verified (Tamarin prover) and the implementation is part of the Linux kernel since version 5.6.

---

## Why Automation

WireGuard is simple, but managing it at scale is not. Setting up a relay server involves installing packages, generating keys, configuring NAT, enabling IP forwarding, and writing firewall rules. Adding a peer means generating a keypair, allocating an IP, writing a config, updating the server config, and restarting the interface. Revoking a peer means finding their public key, removing it, restarting again.

Do this manually for 10 peers across 3 devices and you will make a mistake. Forget to revoke someone who left. Reuse an IP address. Leave a key with wrong permissions. Skip the audit entry.

QP Tunnel automates the entire lifecycle:

| Manual Step | QP Tunnel Equivalent |
|---|---|
| Install WireGuard, generate keys, write config, enable NAT, configure firewall | `tunnel-setup-relay.sh --provider=ssh --host=IP` |
| Generate keypair, allocate IP, write peer config, update server, restart | `tunnel-add-peer.sh alice` |
| Find public key, remove from config, restart, document the change | `tunnel-remove-peer.sh alice` |
| Check who is connected and when they last handshaked | `tunnel-status.sh` |
| Generate new keys, update configs, restart, back up old keys | `tunnel-rotate-keys.sh` |
| Set up TLS, configure reverse proxy, write firewall rules | `tunnel-open --name grafana --to localhost:3000` |

Every operation writes to a structured audit log. Every key is generated with safe permissions. Every revocation is immediate. The system is idempotent: running any command twice does not break anything.

---

## Why Double Encryption

WireGuard provides strong encryption, but it has one limitation: no post-quantum key exchange. Curve25519 is secure against all known classical attacks, but a sufficiently powerful quantum computer could theoretically break it using Shor's algorithm.

QP Tunnel addresses this with a defense-in-depth approach. When you expose a service via `tunnel-open`, the system adds an inner TLS 1.3 layer with ML-KEM-768 hybrid key exchange (FIPS 203). This creates two independent encryption layers:

| Layer | Key Exchange | Encryption | PQ Status |
|---|---|---|---|
| Outer (WireGuard) | Curve25519 | ChaCha20-Poly1305 | Classical |
| Inner (PQ TLS 1.3) | X25519MLKEM768 | AES-256-GCM | Post-quantum hybrid |

Both layers must fail simultaneously for data exposure. This is not theoretical defense. It is practical risk management: you get post-quantum protection today without waiting for WireGuard to adopt PQ key exchange (which has no timeline).

---

## Why Audit Logging

Encryption protects data in transit. Audit logging protects your organization in court, during compliance audits, and after incidents.

QP Tunnel logs every operation as structured JSON:

```json
{"timestamp":"2026-04-04T12:00:00Z","action":"peer_remove","status":"success","message":"Revoked peer bob","user":"admin","details":{"name":"bob","tunnel_ip":"10.8.0.11"}}
```

When a compliance auditor asks "who had access to the clinic server last Tuesday?" you have the answer. When a security incident occurs, you have the timeline. When someone disputes an access change, you have the record.

With the optional [Capsule Protocol](https://github.com/quantumpipes/capsule) integration, every audit entry is additionally sealed with SHA3-256 hashing and Ed25519 signatures, linked into a tamper-evident hash chain. Modifying any record invalidates its signature and breaks the chain for every record after it.

---

## Comparison

| Capability | QP Tunnel | Tailscale | Netbird | Headscale | OpenVPN | IPsec |
|---|---|---|---|---|---|---|
| Cloud dependency | None | Yes (coord server) | Yes (management) | Self-hosted coord | None | None |
| Setup time | Minutes | Minutes | Minutes | Hours | Hours | Hours |
| Post-quantum option | Yes (inner TLS) | No | No | No | No | No |
| Audit trail | JSONL + Capsule | Dashboard logs | Dashboard logs | Logs | File logs | File logs |
| Immediate revocation | Yes | Yes | Yes | Yes | Certificate-based | Certificate-based |
| Protocol | WireGuard | WireGuard | WireGuard | WireGuard | TLS (custom) | IKEv2/ESP |
| Open source | Yes (Apache 2.0) | Client only | Yes | Yes | Yes | Varies |
| Mesh networking | No (star topology) | Yes | Yes | Yes | No | Site-to-site |
| Zero-trust / SSO | No | Yes | Yes | No | Via plugins | Via plugins |
| White-label ready | Yes | No | No | No | No | No |
| Air-gap compatible | Yes | No | No | Partially | Yes | Yes |
| Config complexity | 12 env vars | Web dashboard | Web dashboard | YAML + dashboard | 200+ line config | Complex |

### Where QP Tunnel Wins

**Air-gapped and regulated environments.** No cloud coordination server. No metadata leaving your infrastructure. No SaaS dependency to justify in a security review.

**Post-quantum readiness.** The only WireGuard-based solution with a production PQ TLS inner layer (ML-KEM-768).

**Embeddability.** Nine scripts, five libraries, two JSON files. Fork it, rebrand it (`TUNNEL_APP_NAME=yourproject`), embed it in your product.

**Audit depth.** Structured JSONL with optional cryptographic sealing. Not just "who connected" but tamper-evident proof of every lifecycle event.

### Where Others Win

**Mesh networking.** Tailscale, Netbird, and Headscale provide full mesh topologies where every device can reach every other device directly. QP Tunnel uses a star topology (relay in the center). For large organizations with peer-to-peer requirements, mesh solutions are better.

**SSO and identity integration.** Tailscale and Netbird integrate with Google, Okta, Azure AD, and other identity providers. QP Tunnel authenticates at the cryptographic level (keypairs), not the identity-provider level.

**Web dashboards.** Tailscale and Netbird provide polished web interfaces for managing devices, ACLs, and users. QP Tunnel is CLI-only. If your team needs a GUI, you need to build one or choose a different tool.

---

## Target Use Cases

### Healthcare Clinics

A practice management system running on a local server in a clinic. The IT provider needs remote access for maintenance. HIPAA requires encrypted transmission (164.312(e)(1)), access controls, and audit trails. QP Tunnel provides all three with immediate revocation when the IT contract ends.

### Defense Contractors

A workstation processing controlled unclassified information (CUI) in a facility with restricted network access. Engineers need occasional remote access for development. CMMC L2 requires encrypted sessions, remote access monitoring, and managed access points. No cloud coordination server is acceptable.

### Air-Gapped Facilities

A monitoring system in a facility with no internet access. A relay runs on the facility's internal network (or a DMZ host with controlled connectivity). Peers connect through the relay. After initial setup, no internet access is required for tunnel operation.

### Managed Service Providers

An MSP managing 50 client sites, each with an on-premises server. Each client gets a dedicated tunnel with independent keys and audit trails. White-label the tooling with `TUNNEL_APP_NAME=clientname`. Onboard new technicians with `tunnel-add-peer.sh`, offboard them with `tunnel-remove-peer.sh`.

### Development Teams

A staging server behind a home network or office firewall. Developers and QA need access. Set up in minutes, tear down when the sprint ends. The relay costs $4/month on any VPS provider (or free on Oracle Cloud).

---

## What QP Tunnel Is NOT

Be clear about scope. QP Tunnel is a specific tool for a specific problem.

**Not a mesh network.** QP Tunnel uses a star topology with a relay in the center. Peers do not connect directly to each other. For peer-to-peer mesh networking, use Tailscale, Netbird, or Headscale.

**Not a zero-trust platform.** QP Tunnel authenticates with cryptographic keys, not with identity providers, device posture checks, or policy engines. It does not integrate with Okta, Azure AD, or Google Workspace. For zero-trust network access (ZTNA), use a dedicated ZTNA product.

**Not a VPN product for end users.** There is no GUI, no app store listing, no consumer onboarding flow. QP Tunnel is a toolkit for operators and engineers who are comfortable with the command line.

**Not a replacement for IPsec in FIPS-mandatory environments.** WireGuard's ChaCha20-Poly1305 is not FIPS 140-2/140-3 validated. For FedRAMP High or environments that mandate FIPS-validated encryption modules, use IPsec with FIPS-validated implementations.

**Not approved for classified traffic.** No software VPN qualifies for SECRET or above. Those environments require NSA-approved Type 1 hardware encryption devices. This is a universal requirement, not a QP Tunnel limitation.

---

## Related Documentation

- [Architecture](./architecture.md) -- Double-encryption model, component design, state management
- [Security Evaluation](./security.md) -- Cryptographic inventory and threat model for CISOs
- [Cryptographic Notice](./CRYPTO-NOTICE.md) -- WireGuard primitives and PQ tradeoff analysis
- [Complete Guide](./GUIDE.md) -- Narrative walkthrough of all capabilities
