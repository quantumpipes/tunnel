#!/usr/bin/env bash
# tunnel-remove-peer.sh
# Remove (revoke) a tunnel peer: hot-remove from WireGuard, archive config, mark revoked.
# Usage: tunnel-remove-peer.sh <peer-name>
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
PEER_NAME="${1:?Usage: tunnel-remove-peer.sh <peer-name>}"

if ! validate_peer_name "$PEER_NAME"; then
    exit 1
fi

log_info "Removing peer: $PEER_NAME"

# ---------------------------------------------------------------------------
# Look up peer in registry
# ---------------------------------------------------------------------------
peer_json="$(registry_get_peer "$PEER_NAME")" || {
    log_error "No active peer named '$PEER_NAME' found in registry"
    exit 1
}

PEER_PUBLIC_KEY="$(echo "$peer_json" | jq -r '.public_key')"
PEER_TUNNEL_IP="$(echo "$peer_json" | jq -r '.tunnel_ip')"

# ---------------------------------------------------------------------------
# Hot-remove from WireGuard interface (if running)
# ---------------------------------------------------------------------------
if wg_interface_exists 2>/dev/null; then
    wg_hot_remove_peer "$PEER_PUBLIC_KEY"
    wg_save
    log_success "Peer hot-removed from live interface"
else
    log_warn "WireGuard interface not running. Peer will be removed from registry only."
fi

# ---------------------------------------------------------------------------
# Archive peer config (never delete)
# ---------------------------------------------------------------------------
config_dir="$(ensure_config_dir)"
peer_dir="${config_dir}/peers/${PEER_NAME}"
archive_dir="${config_dir}/archive"
mkdir -p "$archive_dir"

if [[ -d "$peer_dir" ]]; then
    archive_name="${PEER_NAME}_revoked_$(date +%s)"
    mv "$peer_dir" "${archive_dir}/${archive_name}"
    log_info "Peer config archived to ${archive_dir}/${archive_name}"
fi

# ---------------------------------------------------------------------------
# Mark as revoked in registry
# ---------------------------------------------------------------------------
registry_remove_peer "$PEER_NAME"

# ---------------------------------------------------------------------------
# Audit
# ---------------------------------------------------------------------------
audit_log "peer_remove" "success" "Removed peer $PEER_NAME ($PEER_TUNNEL_IP)" \
    "$(jq -cn --arg n "$PEER_NAME" --arg ip "$PEER_TUNNEL_IP" '{"name":$n,"tunnel_ip":$ip}')"

log_success "Peer '$PEER_NAME' removed and access revoked"
