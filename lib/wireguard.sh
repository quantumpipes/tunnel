#!/usr/bin/env bash
# lib/wireguard.sh
# WireGuard wg/wg-quick wrappers for keypair generation and hot add/remove.
# Sourced by tunnel-* scripts. Never executed directly.
#
# Copyright 2026 Quantum Pipes Technologies, LLC
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

# ---------------------------------------------------------------------------
# wg_genkeypair
# Generates a WireGuard keypair. Prints "PRIVATE_KEY PUBLIC_KEY" to stdout.
# IMPORTANT: Private key is ONLY returned via stdout for capture by the caller.
#            It must NEVER be logged or printed to stderr.
# ---------------------------------------------------------------------------
wg_genkeypair() {
    set_safe_umask
    local privkey pubkey
    privkey="$(wg genkey)"
    pubkey="$(echo "$privkey" | wg pubkey)"
    printf '%s %s' "$privkey" "$pubkey"
}

# ---------------------------------------------------------------------------
# wg_genpsk
# Generates a WireGuard preshared key. Prints to stdout.
# ---------------------------------------------------------------------------
wg_genpsk() {
    set_safe_umask
    wg genpsk
}

# ---------------------------------------------------------------------------
# wg_hot_add_peer PUBLIC_KEY ALLOWED_IPS [PSK_FILE] [INTERFACE]
# Adds a peer to a running WireGuard interface without restart.
# ---------------------------------------------------------------------------
wg_hot_add_peer() {
    local pubkey="${1:?public_key required}"
    local allowed_ips="${2:?allowed_ips required}"
    local psk_file="${3:-}"
    local iface="${4:-${TUNNEL_INTERFACE:-wg0}}"

    local cmd=(wg set "$iface" peer "$pubkey" allowed-ips "$allowed_ips")
    if [[ -n "$psk_file" && -f "$psk_file" ]]; then
        cmd+=(preshared-key "$psk_file")
    fi

    "${cmd[@]}"
    log_info "Hot-added peer to $iface: allowed_ips=$allowed_ips"
}

# ---------------------------------------------------------------------------
# wg_hot_remove_peer PUBLIC_KEY [INTERFACE]
# Removes a peer from a running WireGuard interface without restart.
# ---------------------------------------------------------------------------
wg_hot_remove_peer() {
    local pubkey="${1:?public_key required}"
    local iface="${2:-${TUNNEL_INTERFACE:-wg0}}"

    wg set "$iface" peer "$pubkey" remove
    log_info "Hot-removed peer from $iface"
}

# ---------------------------------------------------------------------------
# wg_save [INTERFACE]
# Persists the current in-memory WireGuard config to disk.
# ---------------------------------------------------------------------------
wg_save() {
    local iface="${1:-${TUNNEL_INTERFACE:-wg0}}"
    wg-quick save "$iface"
    log_info "Saved $iface configuration to disk"
}

# ---------------------------------------------------------------------------
# wg_show_peers [INTERFACE]
# Lists peers with their latest handshake and transfer stats.
# Output: one JSON object per peer (public_key, latest_handshake, transfer_rx,
#         transfer_tx, endpoint).
# ---------------------------------------------------------------------------
wg_show_peers() {
    local iface="${1:-${TUNNEL_INTERFACE:-wg0}}"

    wg show "$iface" dump | tail -n +2 | while IFS=$'\t' read -r pubkey psk endpoint allowed_ips handshake rx tx keepalive; do
        local handshake_str="never"
        if [[ "$handshake" != "0" ]]; then
            handshake_str="$(date -d "@$handshake" -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "$handshake")"
        fi
        jq -cn \
            --arg pk "$pubkey" \
            --arg ep "${endpoint:-none}" \
            --arg hs "$handshake_str" \
            --arg rx "$rx" \
            --arg tx "$tx" \
            --arg aips "$allowed_ips" \
            '{"public_key":$pk,"endpoint":$ep,"latest_handshake":$hs,"transfer_rx":$rx,"transfer_tx":$tx,"allowed_ips":$aips}'
    done
}

# ---------------------------------------------------------------------------
# wg_interface_exists [INTERFACE]
# Returns 0 if the WireGuard interface exists, 1 otherwise.
# ---------------------------------------------------------------------------
wg_interface_exists() {
    local iface="${1:-${TUNNEL_INTERFACE:-wg0}}"
    wg show "$iface" &>/dev/null
}

# ---------------------------------------------------------------------------
# wg_write_config FILE PRIVATE_KEY ADDRESS LISTEN_PORT
# Writes a minimal WireGuard server config file.
# ---------------------------------------------------------------------------
wg_write_config() {
    local file="${1:?file required}"
    local privkey="${2:?private_key required}"
    local address="${3:?address required}"
    local listen_port="${4:?listen_port required}"

    set_safe_umask
    cat > "$file" <<EOF
[Interface]
PrivateKey = $privkey
Address = $address
ListenPort = $listen_port
SaveConfig = true
EOF
    chmod 600 "$file"
    log_info "Wrote WireGuard config to $file"
}

# ---------------------------------------------------------------------------
# wg_render_client_config TEMPLATE_FILE VARS...
# Renders a client config from a template file using envsubst-style replacement.
# Variables passed as KEY=VALUE pairs.
# ---------------------------------------------------------------------------
wg_render_client_config() {
    local template="${1:?template required}"
    shift

    if [[ ! -f "$template" ]]; then
        log_error "Template not found: $template"
        return 1
    fi

    local content
    content="$(cat "$template")"

    local pair key val escaped_val
    for pair in "$@"; do
        key="${pair%%=*}"
        val="${pair#*=}"
        # Use sed with proper escaping to avoid bash glob expansion on val
        escaped_val=$(printf '%s\n' "$val" | sed -e 's:[\/&]:\\&:g')
        content="$(printf '%s\n' "$content" | sed "s|\\\${${key}}|${escaped_val}|g")"
    done

    printf '%s\n' "$content"
}
