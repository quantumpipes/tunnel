#!/usr/bin/env bash
# tunnel-status.sh
# Display tunnel peer status with names from registry and live handshake data.
# Usage: tunnel-status.sh
#
# Copyright 2026 Quantum Pipes Technologies, LLC
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/tunnel-preflight.sh"

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "  ${TUNNEL_APP_NAME} Tunnel Status"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# Relay info
# ---------------------------------------------------------------------------
if registry_get_relay >/dev/null 2>&1; then
    relay_json="$(registry_get_relay)"
    relay_ep="$(echo "$relay_json" | jq -r '.endpoint')"
    relay_ip="$(echo "$relay_json" | jq -r '.tunnel_ip')"
    echo "Relay: $relay_ep (Tunnel IP: $relay_ip)"
    echo ""
else
    log_warn "No relay configured"
    echo ""
fi

# ---------------------------------------------------------------------------
# Registered peers
# ---------------------------------------------------------------------------
peer_count="$(registry_peer_count)"
echo "Active peers: $peer_count"
echo ""

if (( peer_count == 0 )); then
    echo "No peers registered. Use tunnel-add-peer.sh <name> to add one."
    exit 0
fi

# ---------------------------------------------------------------------------
# Merge registry names with live WireGuard data
# ---------------------------------------------------------------------------
printf '%-16s %-16s %-14s %-24s %s\n' "NAME" "Tunnel IP" "STATUS" "LAST HANDSHAKE" "ENDPOINT"
printf '%-16s %-16s %-14s %-24s %s\n' "----" "------" "------" "--------------" "--------"

# Build a lookup map from public_key -> live data
declare -A live_handshakes
declare -A live_endpoints
if wg_interface_exists 2>/dev/null; then
    while IFS= read -r line; do
        pk="$(echo "$line" | jq -r '.public_key')"
        hs="$(echo "$line" | jq -r '.latest_handshake')"
        ep="$(echo "$line" | jq -r '.endpoint')"
        live_handshakes["$pk"]="$hs"
        live_endpoints["$pk"]="$ep"
    done < <(wg_show_peers)
fi

# Iterate registered peers
registry_list_peers | jq -c '.[]' | while IFS= read -r peer; do
    name="$(echo "$peer" | jq -r '.name')"
    tunnel_ip="$(echo "$peer" | jq -r '.tunnel_ip')"
    pubkey="$(echo "$peer" | jq -r '.public_key')"
    status="active"

    handshake="${live_handshakes[$pubkey]:-never}"
    endpoint="${live_endpoints[$pubkey]:-none}"

    if [[ "$handshake" == "never" ]]; then
        status="waiting"
    else
        status="connected"
    fi

    printf '%-16s %-16s %-14s %-24s %s\n' "$name" "$tunnel_ip" "$status" "$handshake" "$endpoint"
done

echo ""

# ---------------------------------------------------------------------------
# Show revoked peers (summary only)
# ---------------------------------------------------------------------------
revoked_count="$(registry_list_peers --all | jq '[.[] | select(.status == "revoked")] | length')"
if (( revoked_count > 0 )); then
    echo "Revoked peers: $revoked_count (use --all to see details)"
fi
