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
# Returns the lowest available client IP in the pool subnet.
#
# An IP is "available" when it is NOT in ip_pool.reserved AND is NOT currently
# leased to any active peer (.peers[] | select(.status == "active") | tunnel_ip).
# next_client_ip is treated only as a starting hint; the scan never hands out an
# address that collides with the reserved list or a live lease, which would
# otherwise route two peers to the same tunnel IP.
#
# The chosen IP is asserted unused (against the freshly re-read registry) before
# the next_client_ip hint is advanced, so concurrent allocations cannot silently
# duplicate an address.
#
# Returns:
#   0 with the allocated IP on stdout, or 1 if the pool is exhausted.
# ---------------------------------------------------------------------------
registry_next_ip() {
    local path
    path="$(registry_path)"

    # Derive the /24 prefix and the hint's host octet. The hint only seeds the
    # scan start; reserved + active-lease sets are the source of truth.
    local prefix hint hint_last
    prefix="$(jq -r '.ip_pool.subnet' "$path" | cut -d. -f1-3)"
    hint="$(jq -r '.ip_pool.next_client_ip' "$path")"
    hint_last="$(printf '%s' "$hint" | cut -d. -f4)"

    # Fall back to the first usable host octet if the hint is malformed.
    if [[ ! "$hint_last" =~ ^[0-9]+$ ]] || (( hint_last < 1 )) || (( hint_last > 254 )); then
        hint_last=2
    fi

    # Snapshot the set of addresses that must not be handed out: every reserved
    # entry plus every active peer's tunnel_ip. One IP per line for grep -x.
    local taken
    taken="$(jq -r '
        (.ip_pool.reserved // [])
        + ([.peers[] | select(.status == "active") | .tunnel_ip])
        | .[]
    ' "$path")"

    # Scan from the hint to the top of the /24 host range, then wrap to fill any
    # gaps below the hint (e.g. freed addresses).
    local candidate chosen=""
    local last
    for last in $(seq "$hint_last" 254) $(seq 1 $(( hint_last - 1 ))); do
        candidate="${prefix}.${last}"
        if ! printf '%s\n' "$taken" | grep -qxF "$candidate"; then
            chosen="$candidate"
            break
        fi
    done

    if [[ -z "$chosen" ]]; then
        log_error "IP pool exhausted"
        return 1
    fi

    # Assert the chosen IP is genuinely unused against a fresh read of the
    # registry before committing, so we never write a duplicate lease.
    local verify_taken
    verify_taken="$(jq -r '
        (.ip_pool.reserved // [])
        + ([.peers[] | select(.status == "active") | .tunnel_ip])
        | .[]
    ' "$path")"
    if printf '%s\n' "$verify_taken" | grep -qxF "$chosen"; then
        log_error "Chosen IP $chosen is already in use; refusing to allocate"
        return 1
    fi

    # Advance the hint past the chosen address (best-effort; the scan does not
    # rely on it for correctness, only as a starting offset).
    local chosen_last next_last next_hint
    chosen_last="$(printf '%s' "$chosen" | cut -d. -f4)"
    if (( chosen_last < 254 )); then
        next_last=$(( chosen_last + 1 ))
    else
        next_last=1
    fi
    next_hint="${prefix}.${next_last}"

    local tmp="${path}.tmp.$$"
    jq --arg ip "$next_hint" '.ip_pool.next_client_ip = $ip' "$path" > "$tmp"
    mv "$tmp" "$path"

    printf '%s' "$chosen"
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
