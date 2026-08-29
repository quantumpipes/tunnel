# DigitalOcean Quickstart

Provision a relay on DigitalOcean, join a device, add three peers, and expose a service. Total time: under ten minutes.

## 1. Configure Environment

Copy the example env file and set your DigitalOcean API token:

```bash
cp .env.tunnel.example .env.tunnel
```

Edit `.env.tunnel`:

```bash
DO_API_TOKEN=dop_v1_REPLACE_WITH_YOUR_DIGITALOCEAN_TOKEN
TUNNEL_DO_REGION=nyc3
TUNNEL_DO_SIZE=s-1vcpu-512mb-10gb
TUNNEL_APP_NAME=qp-tunnel
```

Verify your SSH key exists:

```bash
ls -la ~/.ssh/id_ed25519.pub
```

If it does not exist, generate one:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
```

## 2. Provision the Relay

```bash
./tunnel-setup-relay.sh --provider=digitalocean
```

Expected output:

```
[INFO] Setting up tunnel relay Droplet
[INFO] Region: nyc3, Size: s-1vcpu-512mb-10gb
[INFO] SSH key fingerprint: 3a:2b:4c:5d:6e:7f:8a:9b:0c:1d:2e:3f:4a:5b:6c:7d
[INFO] Creating Droplet: qp-tunnel-tunnel-relay
[INFO] Droplet 412837561 created, waiting for IP...
[OK] Droplet ready: 164.92.108.42

========================================
  Tunnel Relay Provisioned
  Droplet IP: 164.92.108.42
  Relay Tunnel IP: 10.8.0.1
  Endpoint: 164.92.108.42:51820
========================================

Next steps:
  1. On the target machine, run:
     tunnel-join.sh 164.92.108.42:51820 <RELAY_PUBLIC_KEY>

  2. Add peers with:
     tunnel-add-peer.sh <peer-name>

[OK] Relay setup complete
```

The relay public key is saved to `~/.config/qp-tunnel/relay.pub`. You need this value for the join step.

## 3. Join the Target Device

SSH into the device you want to reach remotely. Clone or copy the QP Tunnel scripts there, then run:

```bash
relay_key=$(cat ~/.config/qp-tunnel/relay.pub)
./tunnel-join.sh 164.92.108.42:51820 "$relay_key"
```

Expected output:

```
[INFO] Joining relay at 164.92.108.42:51820
[INFO] Generating device keypair...
[INFO] Generating preshared key...
[INFO] Writing WireGuard config...
[INFO] Starting WireGuard interface wg0...
[OK] Joined relay as 10.8.0.2
```

Verify the connection:

```bash
ping -c 3 10.8.0.1
```

You should see replies from the relay at `10.8.0.1`.

## 4. Add Three Peers

Back on your workstation (where the tunnel scripts are), add peers:

```bash
./tunnel-add-peer.sh alice
./tunnel-add-peer.sh bob
./tunnel-add-peer.sh carol
```

Each command outputs a WireGuard client config and a QR code (if `qrencode` is installed). Example output for alice:

```
[INFO] Adding peer: alice
[INFO] Allocated IP: 10.8.0.10
[OK] Peer hot-added to live interface

========================================
  Client config for: alice
  Tunnel IP: 10.8.0.10
  Config: /home/operator/.config/qp-tunnel/peers/alice/alice.conf
========================================

[Interface]
PrivateKey = <generated>
Address = 10.8.0.10/24
DNS = 10.8.0.2

[Peer]
PublicKey = <relay-public-key>
PresharedKey = <generated>
Endpoint = 164.92.108.42:51820
AllowedIPs = 10.8.0.0/24

QR Code (scan with WireGuard mobile app):
<QR code rendered here>

[OK] Peer 'alice' added successfully
```

IP assignments:

| Peer | Tunnel IP |
|------|-----------|
| alice | 10.8.0.10 |
| bob | 10.8.0.11 |
| carol | 10.8.0.12 |

Distribute the config files or QR codes to each person. They import the config into the WireGuard app on their device (macOS, Windows, Linux, iOS, or Android).

## 5. Expose a Service

On the target device, expose a web application (Grafana in this example):

```bash
./tunnel-open.sh --name grafana --to localhost:3000
```

Expected output:

```
[INFO] Opening 'grafana' (localhost:3000) on port 8443...
[INFO] Generated internal CA (Ed25519, 10-year validity)
[INFO] Generated TLS certificate for grafana
[INFO] Starting Caddy with TLS 1.3 + ML-KEM-768...
[INFO] Firewall: allowing 10.8.0.0/24 on port 8443

========================================
  grafana is now accessible
========================================

  URL:         https://10.8.0.2:8443
  Upstream:    localhost:3000
  TLS:         TLS 1.3 + ML-KEM-768 (post-quantum)
  Fingerprint: SHA256:a1b2c3d4e5f6...
  CA cert:     /home/operator/.config/qp-tunnel/tls/ca.crt

  First time? Install the CA on your device:
    iOS:     Transfer ca.mobileconfig to device
    macOS:   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /home/operator/.config/qp-tunnel/tls/ca.crt
    Linux:   sudo cp /home/operator/.config/qp-tunnel/tls/ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates

[OK] Service 'grafana' opened at https://10.8.0.2:8443
```

Any connected peer (alice, bob, carol) can now open `https://10.8.0.2:8443` in their browser to access Grafana. The connection is double-encrypted: WireGuard outer tunnel plus PQ TLS inner layer.

## 6. Verify Everything

Check peer status:

```bash
./tunnel-status.sh
```

List open services:

```bash
./tunnel-list.sh
```

Review the audit log:

```bash
jq '.' ~/.config/qp-tunnel/audit.log
```

## 7. Clean Up

Remove a peer:

```bash
./tunnel-remove-peer.sh carol
```

Close the exposed service:

```bash
./tunnel-close.sh --name grafana
```

To destroy the Droplet entirely:

```bash
doctl compute droplet delete qp-tunnel-tunnel-relay --force
```

Or via the DigitalOcean web console.

## Cost

The `s-1vcpu-512mb-10gb` Droplet costs $4/month. It handles dozens of peers with minimal resource usage. WireGuard's kernel-space implementation uses negligible CPU.
