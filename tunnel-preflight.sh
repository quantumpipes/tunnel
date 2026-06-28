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

# Resolve the Capsule Protocol CLI from the vendored offline set or PATH.
# NEVER auto-installs: pip from a preflight script reaches public PyPI on every
# run (dependency-confusion + data-exfiltration) and breaks air-gap guarantees.
# _ensure_capsule / _capsule_bin are defined in lib/audit.sh.
_TUNNEL_CAPSULE_AVAILABLE=true
if ! _ensure_capsule; then
    _TUNNEL_CAPSULE_AVAILABLE=false
    log_warn "Capsule Protocol unavailable. Audit log will still record entries,"
    log_warn "but they will NOT be tamper-evident. State-changing commands gate"
    log_warn "on this via audit_require_capsule and will fail closed."
fi

# Verify Capsule chain integrity (warn-only; state-changing scripts can gate on this)
_TUNNEL_CAPSULE_CHAIN_VALID=true
if [[ "$_TUNNEL_CAPSULE_AVAILABLE" == "true" ]]; then
    _capsule_bin_path="$(_capsule_bin)"
    config_dir="$(ensure_config_dir)"
    if [[ -f "${config_dir}/capsules.db" ]]; then
        if ! "$_capsule_bin_path" verify --db "${config_dir}/capsules.db" &>/dev/null; then
            _TUNNEL_CAPSULE_CHAIN_VALID=false
            log_warn "Capsule audit chain verification failed. Investigate with:"
            log_warn "  $_capsule_bin_path inspect --db ${config_dir}/capsules.db"
        fi
    fi
    unset config_dir _capsule_bin_path
fi

# ---------------------------------------------------------------------------
# Fail-closed Capsule gate for state-changing / security-relevant commands.
#
# Read-only commands (status, list) never need tamper-evident sealing, so they
# proceed even when qp-capsule is absent. State-changing commands MUST be
# sealable; if Capsule is unavailable we refuse rather than silently claim audit
# coverage we cannot deliver (override: TUNNEL_ALLOW_UNSEALED_AUDIT=1).
#
# The invoking script is BASH_SOURCE[1] (the file that sourced this preflight).
# ---------------------------------------------------------------------------
_TUNNEL_INVOKING_SCRIPT=""
if [[ -n "${BASH_SOURCE[1]:-}" ]]; then
    _TUNNEL_INVOKING_SCRIPT="$(basename "${BASH_SOURCE[1]}" .sh)"
fi

# A sourced script sees the caller's positional parameters. Informational /
# dry-run invocations change no state, so they are never gated even on a
# state-changing script (e.g. `tunnel-setup-relay.sh --help`).
_TUNNEL_INFORMATIONAL_INVOCATION=false
for _arg in "$@"; do
    case "$_arg" in
        --help|-h|--generate-script|--version|-V)
            _TUNNEL_INFORMATIONAL_INVOCATION=true
            break
            ;;
    esac
done
unset _arg

if [[ "$_TUNNEL_INFORMATIONAL_INVOCATION" == "false" ]]; then
    case "$_TUNNEL_INVOKING_SCRIPT" in
        tunnel-setup-relay|tunnel-join|tunnel-add-peer|tunnel-remove-peer|tunnel-rotate-keys|tunnel-open|tunnel-close)
            if ! audit_require_capsule "$_TUNNEL_INVOKING_SCRIPT"; then
                exit 1
            fi
            ;;
        *)
            # Read-only or unknown caller: do not gate.
            ;;
    esac
fi
unset _TUNNEL_INVOKING_SCRIPT _TUNNEL_INFORMATIONAL_INVOCATION

# Set ERR trap for audit logging (scripts can override)
trap 'audit_trap_handler "$(basename "${BASH_SOURCE[0]}" .sh)"' ERR
