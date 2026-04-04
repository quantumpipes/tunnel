#!/usr/bin/env bash
# lib/registry.sh
# Peer registry CRUD backed by peers.json (jq-based, no database).
# Sourced by tunnel-* scripts. Never executed directly.
#
# Copyright 2026 Quantum Pipes Technologies, LLC
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

# ---------------------------------------------------------------------------
# registry_path
# Returns the path to peers.json (creates config dir if needed).
# ---------------------------------------------------------------------------
registry_path() {
    local dir
    dir="$(ensure_config_dir)"
    printf '%s/peers.json' "$dir"
}

# ---------------------------------------------------------------------------
# registry_init
# Creates peers.json with empty structure if it does not exist.
# Idempotent: does nothing if the file already exists and is valid JSON.
# ---------------------------------------------------------------------------
registry_init() {
    local path
    path="$(registry_path)"
    if [[ -f "$path" ]]; then
        if jq empty "$path" 2>/dev/null; then
            return 0
        fi
        log_warn "Corrupt peers.json detected, backing up and reinitializing"
        mv "$path" "${path}.bak.$(date +%s)"
    fi
    set_safe_umask
    cat > "$path" <<'REGISTRY_JSON'
{
  "version": 1,
  "relay": null,
  "peers": [],
  "ip_pool": {
    "subnet": "10.8.0.0/24",
    "next_client_ip": "10.8.0.10",
    "reserved": ["10.8.0.1", "10.8.0.2"]
  }
}
REGISTRY_JSON
    chmod 600 "$path"
    log_info "Initialized peer registry at $path"
}

# ---------------------------------------------------------------------------
# registry_set_relay ENDPOINT PUBLIC_KEY TUNNEL_IP
# Sets or updates the relay object in peers.json.
# ---------------------------------------------------------------------------
registry_set_relay() {
    local endpoint="${1:?endpoint required}"
    local public_key="${2:?public_key required}"
    local tunnel_ip="${3:?tunnel_ip required}"
    local path
    path="$(registry_path)"

    local tmp="${path}.tmp.$$"
    jq --arg ep "$endpoint" --arg pk "$public_key" --arg ip "$tunnel_ip" \
        '.relay = {"endpoint": $ep, "public_key": $pk, "tunnel_ip": $ip}' \
        "$path" > "$tmp"
    mv "$tmp" "$path"
    log_info "Relay set: $tunnel_ip ($endpoint)"
}

# ---------------------------------------------------------------------------
# registry_add_peer NAME PUBLIC_KEY TUNNEL_IP [ADDED_BY]
# Adds a peer entry. Fails if a peer with the same name already exists.
# ---------------------------------------------------------------------------
registry_add_peer() {
    local name="${1:?name required}"
    local public_key="${2:?public_key required}"
    local tunnel_ip="${3:?tunnel_ip required}"
    local added_by="${4:-operator}"
    local path
    path="$(registry_path)"

    if ! validate_peer_name "$name"; then
        return 1
    fi

    # Check for duplicate name (active peers only)
    local existing
    existing="$(jq -r --arg n "$name" '.peers[] | select(.name == $n and .status == "active") | .name' "$path")"
    if [[ -n "$existing" ]]; then
        log_error "Peer '$name' already exists and is active"
        return 1
    fi

    local now
    now="$(ts_iso)"
    local tmp="${path}.tmp.$$"
    jq --arg n "$name" --arg pk "$public_key" --arg ip "$tunnel_ip" \
       --arg ab "$added_by" --arg ts "$now" \
       '.peers += [{"name": $n, "public_key": $pk, "tunnel_ip": $ip, "status": "active", "added_at": $ts, "added_by": $ab, "revoked_at": null}]' \
       "$path" > "$tmp"
    mv "$tmp" "$path"
    log_info "Peer added: $name ($tunnel_ip)"
}

# ---------------------------------------------------------------------------
# registry_remove_peer NAME
# Marks a peer as revoked (sets status=revoked, revoked_at=now).
# Does NOT delete the entry; that would lose audit history.
# ---------------------------------------------------------------------------
registry_remove_peer() {
    local name="${1:?name required}"
    local path
    path="$(registry_path)"

    if ! validate_peer_name "$name"; then
        return 1
    fi

    local existing
    existing="$(jq -r --arg n "$name" '.peers[] | select(.name == $n and .status == "active") | .name' "$path")"
    if [[ -z "$existing" ]]; then
        log_error "No active peer named '$name' found"
        return 1
    fi

    local now
    now="$(ts_iso)"
    local tmp="${path}.tmp.$$"
    jq --arg n "$name" --arg ts "$now" \
       '(.peers[] | select(.name == $n and .status == "active")) |= (.status = "revoked" | .revoked_at = $ts)' \
       "$path" > "$tmp"
    mv "$tmp" "$path"
    log_info "Peer revoked: $name"
}

# ---------------------------------------------------------------------------
# registry_get_peer NAME
# Outputs the JSON object for an active peer, or returns 1 if not found.
# ---------------------------------------------------------------------------
registry_get_peer() {
    local name="${1:?name required}"
    local path
    path="$(registry_path)"
    local result
    result="$(jq -r --arg n "$name" '.peers[] | select(.name == $n and .status == "active")' "$path")"
    if [[ -z "$result" ]]; then
        return 1
    fi
    printf '%s\n' "$result"
}

# ---------------------------------------------------------------------------
# registry_list_peers [--all]
# Lists active peers (or all peers with --all). Outputs JSON array.
# ---------------------------------------------------------------------------
registry_list_peers() {
    local path
    path="$(registry_path)"
    if [[ "${1:-}" == "--all" ]]; then
        jq '.peers' "$path"
    else
        jq '[.peers[] | select(.status == "active")]' "$path"
    fi
}

# ---------------------------------------------------------------------------
# registry_next_ip
# Returns the next available client IP and increments the counter.
# ---------------------------------------------------------------------------
registry_next_ip() {
    local path
    path="$(registry_path)"

    local next_ip
    next_ip="$(jq -r '.ip_pool.next_client_ip' "$path")"

    # Validate current IP is allocatable
    local prefix last
    prefix="$(echo "$next_ip" | cut -d. -f1-3)"
    last="$(echo "$next_ip" | cut -d. -f4)"

    if (( last > 254 )); then
        log_error "IP pool exhausted"
        return 1
    fi

    # Increment counter for the next allocation
    local new_last new_ip
    new_last=$(( last + 1 ))
    new_ip="${prefix}.${new_last}"

    local tmp="${path}.tmp.$$"
    jq --arg ip "$new_ip" '.ip_pool.next_client_ip = $ip' "$path" > "$tmp"
    mv "$tmp" "$path"

    printf '%s' "$next_ip"
}

# ---------------------------------------------------------------------------
# registry_get_relay
# Outputs the relay JSON object, or returns 1 if not set.
# ---------------------------------------------------------------------------
registry_get_relay() {
    local path
    path="$(registry_path)"
    local result
    result="$(jq -r '.relay // empty' "$path")"
    if [[ -z "$result" ]]; then
        return 1
    fi
    printf '%s\n' "$result"
}

# ---------------------------------------------------------------------------
# registry_peer_count
# Returns the number of active peers.
# ---------------------------------------------------------------------------
registry_peer_count() {
    local path
    path="$(registry_path)"
    jq '[.peers[] | select(.status == "active")] | length' "$path"
}

# ---------------------------------------------------------------------------
# registry_update_relay_key PUBLIC_KEY
# Updates the relay public key (used during key rotation).
# ---------------------------------------------------------------------------
registry_update_relay_key() {
    local public_key="${1:?public_key required}"
    local path
    path="$(registry_path)"
    local tmp="${path}.tmp.$$"
    jq --arg pk "$public_key" '.relay.public_key = $pk' "$path" > "$tmp"
    mv "$tmp" "$path"
    log_info "Relay public key updated in registry"
}
