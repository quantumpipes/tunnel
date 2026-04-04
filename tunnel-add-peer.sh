#!/usr/bin/env bash
# tunnel-add-peer.sh
# Add a new tunnel peer: generate keypair, hot-add to WireGuard, output client config + QR.
# Usage: tunnel-add-peer.sh <peer-name>
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
PEER_NAME="${1:?Usage: tunnel-add-peer.sh <peer-name>}"

if ! validate_peer_name "$PEER_NAME"; then
    exit 1
fi

log_info "Adding peer: $PEER_NAME"

# ---------------------------------------------------------------------------
# Check relay is configured
# ---------------------------------------------------------------------------
if ! registry_get_relay >/dev/null 2>&1; then
    log_error "Relay not configured. Run tunnel-setup-relay.sh or tunnel-join.sh first."
    exit 1
fi

relay_json="$(registry_get_relay)"
RELAY_ENDPOINT="$(echo "$relay_json" | jq -r '.endpoint')"
RELAY_PUBLIC_KEY="$(echo "$relay_json" | jq -r '.public_key')"

# ---------------------------------------------------------------------------
# Generate keypair and preshared key
# ---------------------------------------------------------------------------
set_safe_umask

keypair="$(wg_genkeypair)"
CLIENT_PRIVATE_KEY="${keypair%% *}"
CLIENT_PUBLIC_KEY="${keypair##* }"

PRESHARED_KEY="$(wg_genpsk)"

# ---------------------------------------------------------------------------
# Allocate IP from pool
# ---------------------------------------------------------------------------
CLIENT_TUNNEL_IP="$(registry_next_ip)"
log_info "Allocated IP: $CLIENT_TUNNEL_IP"

# ---------------------------------------------------------------------------
# Register peer
# ---------------------------------------------------------------------------
registry_add_peer "$PEER_NAME" "$CLIENT_PUBLIC_KEY" "$CLIENT_TUNNEL_IP"

# ---------------------------------------------------------------------------
# Save client config and preshared key to config dir
# ---------------------------------------------------------------------------
config_dir="$(ensure_config_dir)"
peer_dir="${config_dir}/peers/${PEER_NAME}"
mkdir -p "$peer_dir"
chmod 700 "$peer_dir"

# Write preshared key file (needed for hot-add)
psk_file="${peer_dir}/preshared.key"
printf '%s\n' "$PRESHARED_KEY" > "$psk_file"
chmod 600 "$psk_file"

# Render client config
TEMPLATE_FILE="${SCRIPT_DIR}/templates/client.conf.tpl"
client_conf="$(wg_render_client_config "$TEMPLATE_FILE" \
    "CLIENT_PRIVATE_KEY=$CLIENT_PRIVATE_KEY" \
    "CLIENT_TUNNEL_IP=$CLIENT_TUNNEL_IP" \
    "TUNNEL_DNS_SERVER=${TUNNEL_DNS_SERVER}" \
    "RELAY_PUBLIC_KEY=$RELAY_PUBLIC_KEY" \
    "PRESHARED_KEY=$PRESHARED_KEY" \
    "RELAY_ENDPOINT=$RELAY_ENDPOINT" \
    "TUNNEL_ALLOWED_IPS=${TUNNEL_ALLOWED_IPS}")"

conf_file="${peer_dir}/${PEER_NAME}.conf"
printf '%s\n' "$client_conf" > "$conf_file"
chmod 600 "$conf_file"
log_info "Client config written to $conf_file"

# ---------------------------------------------------------------------------
# Hot-add peer to WireGuard interface (if running)
# ---------------------------------------------------------------------------
if wg_interface_exists 2>/dev/null; then
    wg_hot_add_peer "$CLIENT_PUBLIC_KEY" "${CLIENT_TUNNEL_IP}/32" "$psk_file"
    wg_save
    log_success "Peer hot-added to live interface"
else
    log_warn "WireGuard interface not running. Peer registered but not active on wire."
fi

# ---------------------------------------------------------------------------
# Audit
# ---------------------------------------------------------------------------
audit_log "peer_add" "success" "Added peer $PEER_NAME ($CLIENT_TUNNEL_IP)" \
    "$(jq -cn --arg n "$PEER_NAME" --arg ip "$CLIENT_TUNNEL_IP" '{"name":$n,"tunnel_ip":$ip}')"

# ---------------------------------------------------------------------------
# Output client config (never print private key separately)
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "  Client config for: $PEER_NAME"
echo "  Tunnel IP: $CLIENT_TUNNEL_IP"
echo "  Config: $conf_file"
echo "========================================"
echo ""
cat "$conf_file"
echo ""

# QR code output if qrencode is available
if command -v qrencode &>/dev/null; then
    echo "QR Code (scan with WireGuard mobile app):"
    echo ""
    qrencode -t ansiutf8 < "$conf_file"
else
    log_warn "Install qrencode for QR code output: apt install qrencode"
fi

log_success "Peer '$PEER_NAME' added successfully"
