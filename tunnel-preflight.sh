#!/usr/bin/env bash
# tunnel-preflight.sh
# Pre-flight checks sourced by all tunnel-* scripts.
# Validates environment, loads config, initializes registry.
#
# Copyright 2026 Quantum Pipes Technologies, LLC
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Guard against double-sourcing
if [[ "${_TUNNEL_PREFLIGHT_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || true
fi
_TUNNEL_PREFLIGHT_LOADED=1

TUNNEL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries (order matters: common first, then others that depend on it)
# shellcheck disable=SC1091
source "$TUNNEL_SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$TUNNEL_SCRIPT_DIR/lib/registry.sh"
# shellcheck disable=SC1091
source "$TUNNEL_SCRIPT_DIR/lib/audit.sh"
# shellcheck disable=SC1091
source "$TUNNEL_SCRIPT_DIR/lib/wireguard.sh"

# Load environment file if present
load_env

# Apply default configuration values
apply_defaults

# Ensure config directory exists
ensure_config_dir >/dev/null

# Initialize peer registry if needed
registry_init 2>/dev/null || true

# Validate core dependencies
require_cmd jq

# Ensure Capsule Protocol CLI is available (auto-installs via pip if needed)
# _ensure_capsule is defined in lib/audit.sh
_ensure_capsule || log_warn "Capsule Protocol unavailable. Audit log will still work but without tamper evidence."

# Verify Capsule chain integrity (warn-only; state-changing scripts can gate on this)
_TUNNEL_CAPSULE_CHAIN_VALID=true
if command -v qp-capsule &>/dev/null; then
    config_dir="$(ensure_config_dir)"
    if [[ -f "${config_dir}/capsules.db" ]]; then
        if ! qp-capsule verify --db "${config_dir}/capsules.db" &>/dev/null; then
            _TUNNEL_CAPSULE_CHAIN_VALID=false
            log_warn "Capsule audit chain verification failed. Investigate with:"
            log_warn "  qp-capsule inspect --db ${config_dir}/capsules.db"
        fi
    fi
    unset config_dir
fi

# Set ERR trap for audit logging (scripts can override)
trap 'audit_trap_handler "$(basename "${BASH_SOURCE[0]}" .sh)"' ERR
