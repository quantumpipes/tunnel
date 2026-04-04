# Home Lab

Set up a local relay on a Raspberry Pi or home server. Connect your laptop, phone, and tablet. Expose Home Assistant (or any local service) for secure remote access.

## Scenario

You run Home Assistant on a Raspberry Pi at home. You want to access it from your laptop at work, your phone on the go, and your partner's tablet. You do not want to open ports on your router or use a third-party cloud service.

Solution: run QP Tunnel directly on the Pi. The Pi acts as both the relay and the target device. Your other devices connect as peers through your home internet connection.

## Prerequisites

- Raspberry Pi 4 or 5 (or any Linux home server) with a static LAN IP
- Port 51820/UDP forwarded on your router to the Pi's LAN IP
- Home Assistant running on `localhost:8123` (or substitute your own service)

## 1. Install Dependencies

SSH into your Pi and install WireGuard and jq:

```bash
sudo apt update && sudo apt install -y wireguard wireguard-tools jq qrencode
```

Clone the tunnel scripts:

```bash
git clone https://github.com/quantumpipes/tunnel.git ~/qp-tunnel
cd ~/qp-tunnel
```

## 2. Configure

```bash
cp .env.tunnel.example .env.tunnel
```

Edit `.env.tunnel`:

```bash
TUNNEL_APP_NAME=homelab
TUNNEL_SUBNET=10.8.0.0/24
TUNNEL_RELAY_IP=10.8.0.1
TUNNEL_SERVER_IP=10.8.0.2
TUNNEL_PORT=51820
TUNNEL_DNS_SERVER=10.8.0.1
```

Since the Pi is both relay and server, set `TUNNEL_DNS_SERVER` to the relay IP. If you run Pi-hole or AdGuard Home, point DNS there instead.

## 3. Set Up the Relay

Run the setup locally on the Pi:

```bash
sudo ./tunnel-setup-relay.sh --provider=local
```

Expected output:

```
[INFO] Configuring this machine as the tunnel relay
[1/6] Installing WireGuard...
[2/6] Writing WireGuard config...
[3/6] Enabling IP forwarding...
[4/6] Starting WireGuard...
[5/6] Configuring firewall...
[6/6] Done.

========================================
  Tunnel Relay Configured (local)
  Public IP: 73.42.198.105
  Relay Tunnel IP: 10.8.0.1
  Endpoint: 73.42.198.105:51820
========================================

[OK] Local relay setup complete
```

The public IP is your home internet IP. If it changes (most residential ISPs use dynamic IPs), update the endpoint in your peer configs. For a stable address, use a DDNS service like DuckDNS.

## 4. Forward the Port

On your router, forward UDP port 51820 to the Pi's LAN IP (for example, `192.168.1.50`). The exact steps vary by router. Check your router's admin page (usually `192.168.1.1`).

Verify the port is reachable from outside:

```bash
# From a different network (phone hotspot, VPS, etc.):
nc -zuv 73.42.198.105 51820
```

## 5. Add Peers

Add three peers for your devices:

```bash
sudo ./tunnel-add-peer.sh laptop
sudo ./tunnel-add-peer.sh phone
sudo ./tunnel-add-peer.sh tablet
```

IP assignments:

| Peer | Tunnel IP | Device |
|------|-----------|--------|
| laptop | 10.8.0.10 | MacBook Pro |
| phone | 10.8.0.11 | iPhone 16 |
| tablet | 10.8.0.12 | iPad Air |

### Laptop (macOS/Linux/Windows)

Install the WireGuard app. Import the config file:

```bash
# macOS: the config is at
cat ~/.config/homelab/peers/laptop/laptop.conf
```

Copy the config contents into the WireGuard app. Activate the tunnel.

### Phone (iOS/Android)

Open the WireGuard app. Tap the "+" button and select "Create from QR code." Scan the QR code printed by `tunnel-add-peer.sh`. The tunnel activates immediately.

### Tablet

Same process as the phone. Scan the QR code or transfer the `.conf` file via AirDrop, email, or a USB cable.

## 6. Expose Home Assistant

On the Pi, expose Home Assistant over the tunnel with PQ TLS:

```bash
sudo ./tunnel-open.sh --name homeassistant --to localhost:8123
```

Expected output:

```
========================================
  homeassistant is now accessible
========================================

  URL:         https://10.8.0.2:8443
  Upstream:    localhost:8123
  TLS:         TLS 1.3 + ML-KEM-768 (post-quantum)
```

### Trust the CA on Each Device

**macOS (laptop):**

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  ~/.config/homelab/tls/ca.crt
```

**iOS (phone and tablet):**

Transfer `~/.config/homelab/tls/ca.mobileconfig` to the device (AirDrop works well). Open it in Settings, install the profile, then go to Settings > General > About > Certificate Trust Settings and enable full trust for the QP Tunnel CA.

Now open `https://10.8.0.2:8443` in Safari or Chrome on any connected device. Home Assistant loads with a valid TLS certificate, no warnings.

## 7. Expose Additional Services

Add more services on different ports:

```bash
# Expose Pi-hole admin
sudo ./tunnel-open.sh --name pihole --to localhost:80

# Expose a Plex server
sudo ./tunnel-open.sh --name plex --to localhost:32400

# Expose Grafana
sudo ./tunnel-open.sh --name grafana --to localhost:3000
```

Each service gets its own port (auto-assigned from 8443 to 8499), its own TLS certificate, and its own firewall rules. List all open services:

```bash
sudo ./tunnel-list.sh
```

## 8. Dynamic DNS (Optional)

If your ISP changes your public IP, set up DuckDNS:

```bash
# Add to crontab (runs every 5 minutes):
*/5 * * * * curl -s "https://www.duckdns.org/update?domains=myhomelab&token=YOUR_TOKEN&ip=" > /dev/null
```

Update your peer configs to use the hostname instead of the IP:

```ini
[Peer]
Endpoint = myhomelab.duckdns.org:51820
```

## 9. Maintenance

### Check who is connected

```bash
sudo ./tunnel-status.sh
```

### Revoke a lost device

If you lose your phone:

```bash
sudo ./tunnel-remove-peer.sh phone
```

Access drops immediately. The phone can no longer reach any service on the tunnel. Later, add a replacement:

```bash
sudo ./tunnel-add-peer.sh phone-new
```

### Rotate keys quarterly

```bash
# Dry run first
sudo ./tunnel-rotate-keys.sh

# Execute
sudo CONFIRM=1 ./tunnel-rotate-keys.sh
```

After rotation, redistribute new configs to all peers.

### Review the audit log

```bash
jq '.' ~/.config/homelab/audit.log
```

Every peer addition, removal, service open/close, and key rotation is recorded with timestamps.
