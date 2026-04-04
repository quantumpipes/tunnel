# QP Tunnel: The Complete Guide

## Chapter One: Why This Exists

You have a device that runs on-premises, behind a firewall, isolated from the internet. A server in a data center. A workstation in a secure facility. A Raspberry Pi in a remote office. Whatever it is, it works perfectly on the local network.

But you need to reach it from somewhere else. You need to push an update, debug an issue, or give a colleague temporary access. And you cannot physically walk to the machine every time.

So you need remote access. Secure, auditable, revocable remote access that you can set up in minutes and tear down just as fast.

That is what QP Tunnel does.

It uses WireGuard, the fastest and simplest VPN protocol available today. It creates a relay server that acts as a meeting point between you and the target machine. You connect to the relay. The target connects to the relay. Traffic flows through. When you are done, you revoke access. The whole thing is automated through six commands.

## Chapter Two: The Architecture

Picture three boxes connected by lines.

On the left is you, sitting at a coffee shop or your home office. You are the remote peer. On the far right is the target device, sitting behind a firewall, isolated from the internet. In the middle is a relay server.

The relay can be anything: a five-dollar VPS, a cloud instance, a spare machine at your office with a public IP. Its only job is to forward encrypted WireGuard packets between you and the target. Think of it as a post office box. You send a letter there, the target picks it up. The post office never opens the letter.

The network layout is simple. The relay gets address `10.8.0.1`. The target device gets `10.8.0.2`. Every remote peer you add gets the next address starting from `10.8.0.10`. Alice gets `.10`, Bob gets `.11`, Carol gets `.12`.

Only traffic destined for this private network goes through the tunnel. This is called split-tunnel configuration. When Alice watches a video on YouTube, that traffic goes through her normal internet connection. When Alice connects to the target device at `10.8.0.2`, that traffic goes through the encrypted WireGuard tunnel. This matters for two reasons. First, you are not routing all internet traffic through your relay, which would be slow and expensive. Second, the tunnel carries only your traffic, which reduces the attack surface.

## Chapter Three: The Six Commands

Everything is controlled through shell scripts (or Make targets, if you prefer).

### Command One: Setting Up the Relay

`tunnel-setup-relay.sh` configures any Linux server as a WireGuard relay. It supports four modes:

- **SSH mode:** You already have a server. The script SSHs in and sets up WireGuard automatically.
- **Local mode:** You are sitting on the relay machine itself. Run it directly.
- **DigitalOcean mode:** The script provisions a new Droplet, waits for it, and configures everything.
- **Script mode:** Outputs the setup commands to stdout. Pipe them wherever you want.

The script installs WireGuard, generates a relay keypair, writes the configuration, enables IP forwarding and NAT, starts the service, and configures the firewall. It detects your package manager (apt, dnf, pacman, apk) and adapts accordingly.

### Command Two: Joining the Relay

`tunnel-join.sh` runs on the target device. You provide the relay endpoint and public key. The script generates a keypair for the device, creates a preshared key for extra security, writes the WireGuard config, starts the interface, and enables it on boot via systemd. The target is now permanently connected to the relay. Even if it reboots, the VPN comes back automatically.

### Command Three: Adding a Peer

`tunnel-add-peer.sh` is the command you will use most. When you want to give someone access, you run it with their name. The system generates a fresh keypair, allocates the next IP from the pool, registers the peer in the JSON database, creates a WireGuard config file, and if the interface is running, hot-adds the peer without restarting anything.

It outputs the config file contents and (if `qrencode` is installed) a QR code that can be scanned with the WireGuard mobile app. One scan and the person is connected.

### Command Four: Removing a Peer

`tunnel-remove-peer.sh` revokes access immediately. It removes the peer from the live WireGuard interface, archives their config files (never deletes them, for audit compliance), and marks them as revoked in the registry with a timestamp. The moment you run this command, the peer can no longer reach the target device.

### Command Five: Checking Status

`tunnel-status.sh` displays every registered peer by name, their tunnel IP, connection status, last handshake time, and endpoint. WireGuard handshakes happen every two minutes during active traffic, so a recent handshake means the peer is actively connected. "never" means they have not connected yet.

### Command Six: Rotating Keys

`tunnel-rotate-keys.sh` rotates the relay's cryptographic keys. By default, it runs in dry-run mode, showing what would happen without changing anything. When you run it with `CONFIRM=1`, it generates a new keypair, backs up the old keys, updates the configuration, restarts WireGuard, and updates the registry. All active peers will need new configs with the updated relay public key.

Rotate keys every 90 days in standard environments, or monthly in high-security contexts. Always rotate if someone with relay access leaves the organization.

## Chapter Four: Where State Lives

All state lives in `~/.config/${TUNNEL_APP_NAME}/` (default: `~/.config/qp-tunnel/`).

The most important file is `peers.json`. This is a flat JSON file managed with `jq`. No database required. It tracks the relay endpoint and public key, every peer ever added (including revoked ones with timestamps), and the IP address pool.

Next to it is `audit.log`. Every operation writes a structured JSON entry: timestamp, action, status, message, and username. If an API token appears in any message, it is automatically masked to show only the last four characters.

Per-peer configs live in subdirectories under `peers/`. When a peer is revoked, their folder moves to `archive/`. Nothing is ever deleted. This is critical for audit compliance.

## Chapter Five: Security in Depth

**Key protection:** Every key is generated with umask 077 (owner-only permissions). Private keys are captured in memory via command substitution and written directly to files. They never appear in terminal output, logs, or the audit trail.

**Input validation:** Peer names pass through a strict regex that allows only `[a-zA-Z0-9_-]`. This prevents command injection, path traversal, and every other attack where a crafted name could trick the shell.

**No eval:** The word `eval` does not appear anywhere in the codebase. This eliminates an entire category of code injection vulnerabilities.

**Token masking:** API tokens in log messages are replaced with asterisks (last 4 chars visible). Prevents accidental credential exposure in shared logs.

**Idempotency:** Every script is safe to run twice. Existing data is preserved. Registry initialization is a no-op if the file already exists and is valid.

**Error trapping:** Every script uses `set -euo pipefail`. If any command fails, an ERR trap fires and writes a failure entry to the audit log, recording the script name and line number.

## Chapter Six: Exposing Services (tunnel-open)

You have a device on the tunnel. Now you want to access a web application running on it: Grafana, Jenkins, your own app, anything with an HTTP interface.

`tunnel-open` handles this. It wraps any local web application in post-quantum TLS and makes it available to tunnel peers, and only tunnel peers.

```bash
tunnel-open --name grafana --to localhost:3000
```

This one command does six things:

1. **Generates an internal CA** (Ed25519, 10-year validity) if one does not exist. This CA signs all service certificates. You install it once on each client device.

2. **Generates a per-service TLS certificate** signed by the CA. The cert has SANs for the tunnel server IP (10.8.0.2) and `grafana.tunnel`. Validity: one year.

3. **Starts a Caddy reverse proxy** configured for TLS 1.3 with ML-KEM-768 hybrid key exchange (X25519MLKEM768). This is post-quantum protection. Caddy listens on 10.8.0.2:8443 (or the next available port) and proxies to localhost:3000.

4. **Binds the port to the tunnel interface only.** The port is unreachable from the LAN, WAN, or any non-tunnel network interface. Even without firewall rules, the service is invisible to everything outside the tunnel.

5. **Installs firewall rules** (nftables or iptables, auto-detected) that explicitly allow only 10.8.0.0/24 and drop everything else. Defense in depth.

6. **Registers the service** in `services.json` and writes a Capsule audit record.

To close a service: `tunnel-close --name grafana`. This stops Caddy, removes firewall rules, archives the certificates, and creates a close audit record.

To see what is open: `tunnel-list`. Shows each service with its name, upstream, port, process status, and URL.

**Multiple services run simultaneously.** Each gets its own Caddy process, its own port (auto-assigned from 8443-8499), its own certificate, and its own firewall chain. Closing one does not affect the others.

**Mobile device access:** The first `tunnel-open` generates a `ca.mobileconfig` profile. Transfer it to your iPhone, install in Settings, and Safari trusts all tunnel services without certificate warnings.

**Double encryption:** WireGuard provides the outer encrypted tunnel (Curve25519/ChaCha20). Caddy provides the inner PQ TLS 1.3 layer (ML-KEM-768/AES-256-GCM). Both must fail for data exposure.

## Chapter Seven: The Cryptography Tradeoff

WireGuard uses Curve25519 for key exchange, ChaCha20-Poly1305 for encryption, and BLAKE2s for hashing. These are fixed in the protocol and cannot be changed.

WireGuard does not support post-quantum cryptography. No ML-KEM for key exchange, no ML-DSA for signatures. This is a protocol-level limitation. The `tunnel-open` PQ TLS layer compensates for this by providing ML-KEM-768 key exchange on the inner TLS connection.

This tradeoff is acceptable because:

1. Curve25519 is not broken. No quantum computer capable of attacking it exists today.
2. The `tunnel-open` inner layer provides post-quantum protection via ML-KEM-768.
3. Keys can be rotated regularly, limiting the window of exposure.
4. No post-quantum VPN protocol has reached production maturity.
5. Double encryption means both layers must fail simultaneously.

When WireGuard or a compatible protocol adds post-quantum support, QP Tunnel will adopt it. See [CRYPTO-NOTICE.md](CRYPTO-NOTICE.md) for the full analysis.

## Chapter Eight: Compliance

For HIPAA: the tunnel satisfies transmission security (164.312(e)(1)), access control (unique crypto identity per user), and audit controls (structured logging with timestamps).

For CMMC Level 1-2: encrypted sessions, remote access monitoring, managed access points, and audit accountability.

For FIPS-mandatory environments: WireGuard uses ChaCha20-Poly1305, which is not FIPS validated. Substitute IPsec with FIPS-validated modules for those deployments.

For classified environments (SECRET and above): no software VPN qualifies. Those require NSA-approved hardware encryption devices. This is a universal requirement, not a QP Tunnel limitation.

## Chapter Nine: The Day-to-Day Workflow

You need to access a server remotely. Here is the workflow:

1. Provision a relay: `tunnel-setup-relay.sh --provider=ssh --host=your-vps-ip`. Thirty seconds later, you have a relay running.

2. On the target machine: `tunnel-join.sh relay-ip:51820 relay-public-key`. The device is now connected to the relay, permanently.

3. Add yourself: `tunnel-add-peer.sh alice`. Paste the config into your WireGuard app. You are connected.

4. Need to add a colleague? `tunnel-add-peer.sh bob`. Send them the QR code.

5. Colleague is done? `tunnel-remove-peer.sh bob`. Immediate revocation.

6. Check who is connected: `tunnel-status.sh`.

7. Every action is in the audit log with timestamps and usernames.

8. When you are done, tear down the relay and all remote access ceases.

## Chapter Ten: Dependencies

The system requires two tools: WireGuard and jq. Both are available in every major Linux distribution's package manager.

Optional tools: `qrencode` for QR codes, `doctl` for DigitalOcean (with curl fallback), `qp-capsule` for tamper-evident audit sealing (auto-installs via pip).

The scripts are written in bash and work on any modern Linux distribution. The setup script auto-detects apt, dnf, yum, pacman, and apk package managers.
