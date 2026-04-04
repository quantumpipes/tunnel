#!/usr/bin/env bash
# tunnel-rotate-keys.sh
# Rotate WireGuard relay server keys.
# Dry-run by default. Set CONFIRM=1 to execute.
# Usage: tunnel-rotate-keys.sh
#
# Copyright 2026 Quantum Pipes Technologies, LLC
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/tunnel-preflight.sh"

DRY_RUN=true
if [[ "${CONFIRM:-0}" == "1" ]]; then
    DRY_RUN=false
fi

# ---------------------------------------------------------------------------
# Require WireGuard
# ---------------------------------------------------------------------------
require_cmd wg wg-quick

# ---------------------------------------------------------------------------
# Check relay is configured
# ---------------------------------------------------------------------------
if ! registry_get_relay >/dev/null 2>&1; then
    log_error "No relay configured. Nothing to rotate."
    exit 1
fi

relay_json="$(registry_get_relay)"
OLD_PUBLIC_KEY="$(echo "$relay_json" | jq -r '.public_key')"
RELAY_ENDPOINT="$(echo "$relay_json" | jq -r '.endpoint')"

# ---------------------------------------------------------------------------
# Show current state
# ---------------------------------------------------------------------------
peer_count="$(registry_peer_count)"

echo ""
echo "========================================"
echo "  Key Rotation Plan"
echo "========================================"
echo ""
echo "Relay endpoint: $RELAY_ENDPOINT"
echo "Current public key: $OLD_PUBLIC_KEY"
echo "Active peers affected: $peer_count"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] No changes will be made."
    echo ""
    echo "To execute rotation, run:"
    echo "  CONFIRM=1 tunnel-rotate-keys.sh"
    echo ""
    echo "WARNING: All peers will need to update their configs with the new relay public key."
    echo "Plan for a maintenance window."
    exit 0
fi

# ---------------------------------------------------------------------------
# Generate new keypair
# ---------------------------------------------------------------------------
log_info "Generating new relay keypair..."
set_safe_umask

keypair="$(wg_genkeypair)"
NEW_PRIVATE_KEY="${keypair%% *}"
NEW_PUBLIC_KEY="${keypair##* }"

config_dir="$(ensure_config_dir)"

# ---------------------------------------------------------------------------
# Backup current keys
# ---------------------------------------------------------------------------
backup_dir="${config_dir}/key-backups/$(date +%s)"
mkdir -p "$backup_dir"

if [[ -f "${config_dir}/relay.key" ]]; then
    cp "${config_dir}/relay.key" "${backup_dir}/relay.key.old"
fi
if [[ -f "${config_dir}/relay.pub" ]]; then
    cp "${config_dir}/relay.pub" "${backup_dir}/relay.pub.old"
fi
log_info "Old keys backed up to $backup_dir"

# ---------------------------------------------------------------------------
# Write new keys
# ---------------------------------------------------------------------------
printf '%s\n' "$NEW_PRIVATE_KEY" > "${config_dir}/relay.key"
chmod 600 "${config_dir}/relay.key"
printf '%s\n' "$NEW_PUBLIC_KEY" > "${config_dir}/relay.pub"

# ---------------------------------------------------------------------------
# Update WireGuard config on relay
# ---------------------------------------------------------------------------
WG_CONF="/etc/wireguard/${TUNNEL_INTERFACE}.conf"
if [[ -f "$WG_CONF" ]]; then
    # Backup config
    cp "$WG_CONF" "${backup_dir}/${TUNNEL_INTERFACE}.conf.old"

    # Bring down, update key, bring up
    wg-quick down "${TUNNEL_INTERFACE}" 2>/dev/null || true

    # Replace PrivateKey line in config (escape sed special chars in key value)
    escaped_key=$(printf '%s\n' "$NEW_PRIVATE_KEY" | sed -e 's:[\/&]:\\&:g')
    sed -i "s|^PrivateKey = .*|PrivateKey = ${escaped_key}|" "$WG_CONF"

    wg-quick up "${TUNNEL_INTERFACE}"
    log_success "WireGuard interface restarted with new key"
else
    log_warn "WireGuard config not found at $WG_CONF. Update manually on the relay."
fi

# ---------------------------------------------------------------------------
# Update registry
# ---------------------------------------------------------------------------
registry_update_relay_key "$NEW_PUBLIC_KEY"

# ---------------------------------------------------------------------------
# Rotate Capsule signing key
# ---------------------------------------------------------------------------
if command -v qp-capsule &>/dev/null; then
    log_info "Rotating Capsule signing key..."
    if qp-capsule keys rotate 2>/dev/null; then
        log_success "Capsule signing key rotated (new epoch)"
    else
        log_warn "Capsule key rotation failed. Old signing key remains active."
    fi
else
    log_warn "qp-capsule not available. Skipping Capsule key rotation."
fi

# ---------------------------------------------------------------------------
# Audit
# ---------------------------------------------------------------------------
audit_log "key_rotate" "success" "Relay keys rotated" \
    "$(jq -cn --arg old "$OLD_PUBLIC_KEY" --arg new "$NEW_PUBLIC_KEY" \
        '{"old_public_key":$old,"new_public_key":$new}')"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "  Key Rotation Complete"
echo "========================================"
echo ""
echo "New relay public key:"
echo "  $NEW_PUBLIC_KEY"
echo ""
echo "IMPORTANT: All $peer_count active peers must update their configs."
echo "Regenerate peer configs with:"
echo "  tunnel-remove-peer.sh <name>"
echo "  tunnel-add-peer.sh <name>"
echo ""

log_success "Key rotation complete"
