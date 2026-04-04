#!/usr/bin/env bash
# tunnel-join.sh
# Join an existing tunnel relay from a target device.
# Configures WireGuard on this machine as a peer of the relay.
# Usage: tunnel-join.sh <relay-endpoint> <relay-public-key>
#
# Copyright 2026 Quantum Pipes Technologies, LLC
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/tunnel-preflight.sh"

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
RELAY_ENDPOINT="${1:?Usage: tunnel-join.sh <relay-endpoint:port> <relay-public-key>}"
RELAY_PUBLIC_KEY="${2:?Usage: tunnel-join.sh <relay-endpoint:port> <relay-public-key>}"

log_info "Joining tunnel relay at $RELAY_ENDPOINT"

# ---------------------------------------------------------------------------
# Require WireGuard
# ---------------------------------------------------------------------------
require_cmd wg wg-quick

# ---------------------------------------------------------------------------
# Generate server keypair
# ---------------------------------------------------------------------------
set_safe_umask
keypair="$(wg_genkeypair)"
SERVER_PRIVATE_KEY="${keypair%% *}"
SERVER_PUBLIC_KEY="${keypair##* }"

log_info "Generated server keypair"

# ---------------------------------------------------------------------------
# Generate preshared key
# ---------------------------------------------------------------------------
PSK="$(wg_genpsk)"

config_dir="$(ensure_config_dir)"
psk_file="${config_dir}/server-relay.psk"
printf '%s\n' "$PSK" > "$psk_file"
chmod 600 "$psk_file"

# ---------------------------------------------------------------------------
# Write WireGuard config
# ---------------------------------------------------------------------------
WG_CONF="/etc/wireguard/${TUNNEL_INTERFACE}.conf"

if [[ -f "$WG_CONF" ]]; then
    backup="${WG_CONF}.bak.$(date +%s)"
    cp "$WG_CONF" "$backup"
    log_warn "Existing config backed up to $backup"
fi

set_safe_umask
cat > "$WG_CONF" <<EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = ${TUNNEL_SERVER_IP}/24
ListenPort = ${TUNNEL_PORT}
SaveConfig = true

[Peer]
PublicKey = $RELAY_PUBLIC_KEY
PresharedKey = $PSK
Endpoint = $RELAY_ENDPOINT
AllowedIPs = ${TUNNEL_SUBNET}
PersistentKeepalive = 25
EOF
chmod 600 "$WG_CONF"

log_info "WireGuard config written to $WG_CONF"

# ---------------------------------------------------------------------------
# Register relay in peers.json
# ---------------------------------------------------------------------------
registry_set_relay "$RELAY_ENDPOINT" "$RELAY_PUBLIC_KEY" "${TUNNEL_RELAY_IP}"

# ---------------------------------------------------------------------------
# Enable and start WireGuard
# ---------------------------------------------------------------------------
if wg_interface_exists 2>/dev/null; then
    wg-quick down "${TUNNEL_INTERFACE}" 2>/dev/null || true
fi

wg-quick up "${TUNNEL_INTERFACE}"
log_success "WireGuard interface ${TUNNEL_INTERFACE} is up"

# Enable on boot
if command -v systemctl &>/dev/null; then
    systemctl enable "wg-quick@${TUNNEL_INTERFACE}" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Audit
# ---------------------------------------------------------------------------
audit_log "tunnel_join" "success" "Joined relay $RELAY_ENDPOINT as $TUNNEL_SERVER_IP" \
    "$(jq -cn --arg ep "$RELAY_ENDPOINT" --arg ip "$TUNNEL_SERVER_IP" '{"relay_endpoint":$ep,"server_ip":$ip}')"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "  Server joined tunnel relay"
echo "  Relay: $RELAY_ENDPOINT"
echo "  Server Tunnel IP: $TUNNEL_SERVER_IP"
echo "  Interface: ${TUNNEL_INTERFACE}"
echo "========================================"
echo ""
echo "Server public key (provide to relay admin):"
echo "  $SERVER_PUBLIC_KEY"
echo ""
echo "Preshared key (provide to relay admin):"
echo "  (saved to $psk_file)"
echo ""

log_success "tunnel join complete"
