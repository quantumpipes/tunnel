# Healthcare Clinic

Secure remote access to an on-premises EHR (Electronic Health Record) system. This guide emphasizes HIPAA compliance, audit logging, peer revocation for departing staff, and key rotation schedules.

## Scenario

Greenfield Family Medicine runs an on-premises EHR system (OpenEMR) on a server in their office. Three providers need remote access: Dr. Chen (physician), Maria (nurse practitioner), and James (IT administrator). The clinic must satisfy HIPAA Technical Safeguards for Transmission Security (164.312(e)(1)), Access Control (164.312(a)(1)), and Audit Controls (164.312(b)).

## Architecture

```
Dr. Chen (home)        Relay (VPS)              Clinic Server
  10.8.0.10  ──────── 10.8.0.1 ──────────────── 10.8.0.2
Maria (mobile)                                    OpenEMR :443
  10.8.0.11  ────────────┘                        (ePHI)
James (IT laptop)
  10.8.0.12  ────────────┘
```

The relay is a $4/month VPS. It forwards encrypted packets only. No ePHI touches the relay. End-to-end encryption (WireGuard + PQ TLS) ensures that patient data is protected in transit at all times.

## 1. Provision the Relay

Use a VPS provider that signs a Business Associate Agreement (BAA). DigitalOcean, AWS, and Azure all offer BAA-eligible infrastructure.

```bash
cp .env.tunnel.example .env.tunnel
```

Edit `.env.tunnel`:

```bash
TUNNEL_APP_NAME=greenfield-vpn
DO_API_TOKEN=dop_v1_c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9
TUNNEL_DO_REGION=nyc3
TUNNEL_DO_SIZE=s-1vcpu-512mb-10gb
TUNNEL_PORT=51820
```

Provision:

```bash
./tunnel-setup-relay.sh --provider=digitalocean
```

Record the relay endpoint and public key. Store the public key in your IT documentation (you need it for the join step and for staff onboarding procedures).

## 2. Join the Clinic Server

On the clinic server, install QP Tunnel and join the relay:

```bash
relay_key="<relay-public-key-from-step-1>"
sudo ./tunnel-join.sh 198.51.100.23:51820 "$relay_key"
```

Verify connectivity:

```bash
ping -c 3 10.8.0.1
```

The clinic server is now connected to the relay with automatic reconnection on reboot.

## 3. Expose the EHR with PQ TLS

OpenEMR runs on `localhost:443`. Expose it over the tunnel with post-quantum TLS:

```bash
sudo ./tunnel-open.sh --name openemr --to localhost:443 --port 8443
```

This creates a double-encrypted path:

1. **Outer layer:** WireGuard (Curve25519 + ChaCha20-Poly1305)
2. **Inner layer:** TLS 1.3 with ML-KEM-768 hybrid key exchange + AES-256-GCM

HIPAA 164.312(e)(1) requires encryption of ePHI in transit. This configuration exceeds that requirement.

## 4. Onboard Staff

Add each provider as a peer:

```bash
./tunnel-add-peer.sh dr-chen
./tunnel-add-peer.sh maria
./tunnel-add-peer.sh james-it
```

| Peer | Role | Tunnel IP | Device |
|------|------|-----------|--------|
| dr-chen | Physician | 10.8.0.10 | MacBook Pro |
| maria | NP | 10.8.0.11 | iPhone 15 Pro |
| james-it | IT Admin | 10.8.0.12 | ThinkPad T14s |

Distribute configs securely. Do not email WireGuard configs containing private keys. Use one of these methods:

- **In person:** Show the QR code on your screen. The staff member scans it with the WireGuard app.
- **Encrypted transfer:** Use Signal or an encrypted USB drive.
- **Printed config:** Hand a printed copy to the staff member, who types it in manually. Shred the paper afterward.

### Install the CA Certificate

Each device must trust the internal CA to access the EHR without certificate warnings:

**macOS:**

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  ~/.config/greenfield-vpn/tls/ca.crt
```

**iOS:**

Transfer `ca.mobileconfig` to the device via AirDrop. Install the profile in Settings. Enable full trust under Settings > General > About > Certificate Trust Settings.

**Linux:**

```bash
sudo cp ~/.config/greenfield-vpn/tls/ca.crt /usr/local/share/ca-certificates/greenfield-vpn.crt
sudo update-ca-certificates
```

## 5. HIPAA Compliance Controls

### 5a. Access Control (164.312(a)(1))

Each staff member has a unique cryptographic identity: a unique WireGuard keypair, a unique preshared key, and a unique tunnel IP. Access is individual, not shared.

Verify the peer registry:

```bash
jq '.peers[] | {name, tunnel_ip, status}' ~/.config/greenfield-vpn/peers.json
```

### 5b. Audit Controls (164.312(b))

Every tunnel operation writes a structured JSON entry to `audit.log`:

```bash
jq '.' ~/.config/greenfield-vpn/audit.log
```

Example entries:

```json
{"timestamp":"2026-04-04T09:15:00Z","action":"peer_add","status":"success","message":"Added peer dr-chen (10.8.0.10)","user":"james-it","details":{"name":"dr-chen","tunnel_ip":"10.8.0.10"}}
{"timestamp":"2026-04-04T09:16:00Z","action":"service_open","status":"success","message":"Opened openemr at https://10.8.0.2:8443","user":"james-it","details":{"name":"openemr","upstream":"localhost:443","port":8443,"listen_ip":"10.8.0.2","tls_fingerprint":"SHA256:f1e2d3c4b5a6..."}}
```

For tamper-evident logging, install qp-capsule:

```bash
pip install qp-capsule
```

All subsequent audit entries are sealed with SHA3-256 + Ed25519 signatures. Verify chain integrity:

```bash
qp-capsule verify --db ~/.config/greenfield-vpn/capsules.db
```

### 5c. Transmission Security (164.312(e)(1))

Satisfied by the double-encryption architecture. Document the following in your HIPAA Security Risk Assessment:

- WireGuard outer tunnel: Curve25519 key exchange, ChaCha20-Poly1305 symmetric encryption
- PQ TLS inner layer: ML-KEM-768 hybrid key exchange, AES-256-GCM symmetric encryption
- Unique preshared key per peer (additional symmetric layer)
- All keys generated with umask 077 (owner-only read)
- No ePHI touches the relay server (it forwards encrypted packets only)

## 6. Staff Departure: Peer Revocation

When a staff member leaves the organization, revoke their access immediately:

```bash
./tunnel-remove-peer.sh maria
```

Expected output:

```
[INFO] Removing peer: maria
[INFO] Removed maria from WireGuard interface
[INFO] Archived config to /home/james-it/.config/greenfield-vpn/archive/maria/
[OK] Peer 'maria' removed

```

What happens:

1. Maria's peer is removed from the live WireGuard interface. Connection drops instantly.
2. Her config files move to `archive/maria/` (never deleted, for audit compliance).
3. The registry marks her as revoked with a timestamp.
4. An audit entry records the revocation.

Verify revocation:

```bash
# Confirm maria is no longer active
./tunnel-status.sh

# Confirm the audit entry
jq 'select(.action == "peer_remove")' ~/.config/greenfield-vpn/audit.log
```

**Do not skip this step.** HIPAA requires termination of access when workforce members leave (164.312(a)(2)(iii)).

After revoking a departed staff member, rotate the relay keys as a precaution:

```bash
# Dry run
./tunnel-rotate-keys.sh

# Execute
CONFIRM=1 ./tunnel-rotate-keys.sh
```

Redistribute updated configs to remaining staff.

## 7. Key Rotation Schedule

Establish a regular key rotation cadence:

| Trigger | Action | Frequency |
|---------|--------|-----------|
| Scheduled maintenance | Rotate relay keys | Every 90 days |
| Staff departure | Rotate relay keys | Immediately |
| Suspected compromise | Rotate relay keys | Immediately |
| Annual review | Rotate relay keys + regenerate all peer configs | Annually |

### Rotation procedure

```bash
# 1. Announce maintenance window to staff (they will lose access briefly)

# 2. Dry run
./tunnel-rotate-keys.sh

# 3. Execute
CONFIRM=1 ./tunnel-rotate-keys.sh

# 4. Old keys are backed up to ~/.config/greenfield-vpn/key-backups/

# 5. Generate new configs for each active peer
./tunnel-add-peer.sh dr-chen
./tunnel-add-peer.sh james-it

# 6. Distribute new configs securely (same methods as onboarding)
```

## 8. Ongoing Monitoring

### Daily (automated)

Add a cron job to verify audit chain integrity:

```bash
# /etc/cron.daily/greenfield-audit-check
#!/bin/bash
qp-capsule verify --db /home/james-it/.config/greenfield-vpn/capsules.db || \
  echo "ALERT: Audit chain integrity failure" | mail -s "Greenfield VPN Alert" it@greenfieldmed.example.com
```

### Weekly (manual)

Review active peers and recent audit entries:

```bash
./tunnel-status.sh
jq -s '.[-20:]' ~/.config/greenfield-vpn/audit.log
```

### Quarterly

- Rotate relay keys (see section 7)
- Review and remove inactive peers
- Export audit log for compliance records
- Update HIPAA Security Risk Assessment if architecture changed

## 9. Disaster Recovery

### Relay goes down

Provision a new relay and update the endpoint. All peer configs need the new endpoint and public key. The clinic server needs to re-join.

### Clinic server goes down

Restore from backup. Re-run `tunnel-join.sh` with the existing relay endpoint and key.

### Audit log needed for investigation

The JSONL audit log at `~/.config/greenfield-vpn/audit.log` is human-readable. The Capsule database at `capsules.db` provides cryptographic proof of integrity. Export both for legal or compliance review:

```bash
cp ~/.config/greenfield-vpn/audit.log /secure-backup/greenfield-audit-$(date +%Y%m%d).jsonl
cp ~/.config/greenfield-vpn/capsules.db /secure-backup/greenfield-capsules-$(date +%Y%m%d).db
```

## HIPAA Documentation Checklist

Use this checklist when preparing your Security Risk Assessment:

- [ ] BAA signed with VPS provider (relay hosting)
- [ ] Encryption in transit documented (WireGuard + PQ TLS)
- [ ] Unique access credentials per workforce member
- [ ] Peer revocation procedure documented and tested
- [ ] Key rotation schedule established (90-day minimum)
- [ ] Audit log retention policy defined (6 years per HIPAA)
- [ ] Capsule Protocol installed for tamper-evident logging
- [ ] Audit chain verification automated (daily cron)
- [ ] Staff onboarding procedure documented (secure config distribution)
- [ ] Staff departure procedure documented (immediate revocation + key rotation)
- [ ] Disaster recovery procedure documented and tested
- [ ] Annual review scheduled
