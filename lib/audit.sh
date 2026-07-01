#!/usr/bin/env bash
# lib/audit.sh
# Structured JSON audit log writer for tunnel operations.
# Appends one JSON object per line to the audit log.
# Sourced by tunnel-* scripts. Never executed directly.
#
# Copyright 2026 Quantum Pipes Technologies, LLC
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

# ---------------------------------------------------------------------------
# audit_log ACTION STATUS [MESSAGE] [DETAILS_JSON]
#
# Writes a structured JSON line to the audit log.
#   ACTION:       e.g. "peer_add", "peer_remove", "key_rotate", "setup_relay"
#   STATUS:       "success" or "failure"
#   MESSAGE:      human-readable description (optional)
#   DETAILS_JSON: additional JSON object to merge (optional)
#
# Output format (one line per entry, no pretty-printing):
# {"timestamp":"...","action":"...","status":"...","message":"...","user":"...","details":{...}}
# ---------------------------------------------------------------------------
audit_log() {
    local action="${1:?action required}"
    local status="${2:?status required}"
    local message="${3:-}"
    local empty_obj='{}'
    local details="${4:-$empty_obj}"

    local config_dir
    config_dir="$(ensure_config_dir)"
    local log_file="${config_dir}/audit.log"

    local timestamp
    timestamp="$(ts_iso)"
    local user
    user="$(whoami 2>/dev/null || echo 'unknown')"

    # Validate details is valid JSON, fallback to empty object
    if ! echo "$details" | jq empty 2>/dev/null; then
        details='{}'
    fi

    # Build the log entry (mask any token values in the message)
    local masked_message="$message"
    if [[ -n "${DO_API_TOKEN:-}" ]]; then
        masked_message="${masked_message//$DO_API_TOKEN/****}"
    fi

    local entry
    entry="$(jq -cn \
        --arg ts "$timestamp" \
        --arg act "$action" \
        --arg st "$status" \
        --arg msg "$masked_message" \
        --arg usr "$user" \
        --argjson det "$details" \
        '{"timestamp":$ts,"action":$act,"status":$st,"message":$msg,"user":$usr,"details":$det}'
    )"

    # Append atomically (single write)
    printf '%s\n' "$entry" >> "$log_file"

    # Seal as tamper-evident Capsule
    _capsule_seal "$entry"
}

# ---------------------------------------------------------------------------
# audit_read [N]
# Reads the last N entries from the audit log (default: 10).
# ---------------------------------------------------------------------------
audit_read() {
    local count="${1:-10}"
    local config_dir
    config_dir="$(ensure_config_dir)"
    local log_file="${config_dir}/audit.log"

    if [[ ! -f "$log_file" ]]; then
        echo '[]'
        return 0
    fi

    tail -n "$count" "$log_file" | jq -s '.'
}

# ---------------------------------------------------------------------------
# audit_trap_handler
# Intended to be used as: trap 'audit_trap_handler "script_name"' ERR
# Logs a failure entry when an ERR trap fires.
# ---------------------------------------------------------------------------
audit_trap_handler() {
    local script_name="${1:-unknown}"
    local line="${BASH_LINENO[0]:-unknown}"
    audit_log "${script_name}_error" "failure" \
        "ERR trap fired at line $line" \
        "{\"line\":\"$line\",\"script\":\"$script_name\"}"
}

# ---------------------------------------------------------------------------
# _capsule_bin
# Resolves the qp-capsule executable from the vendored offline set first, then
# from PATH. The vendored binary is pinned and shipped with the tunnel scripts,
# so an air-gapped host never needs network access. Honors a TUNNEL_CAPSULE_BIN
# override for operators who install it elsewhere on a sealed image.
#
# Outputs:
#   The resolved executable path on stdout (empty if none found).
# Returns:
#   0 if a usable qp-capsule was found, 1 otherwise.
# ---------------------------------------------------------------------------
_capsule_bin() {
    # Explicit operator override (must be an executable file).
    if [[ -n "${TUNNEL_CAPSULE_BIN:-}" && -x "${TUNNEL_CAPSULE_BIN}" ]]; then
        printf '%s' "${TUNNEL_CAPSULE_BIN}"
        return 0
    fi

    # Vendored, pinned offline copy shipped alongside the tunnel scripts.
    # SCRIPT_DIR is lib/, so the repo root is one level up.
    local vendored="${SCRIPT_DIR}/../vendor/qp-capsule/qp-capsule"
    if [[ -x "$vendored" ]]; then
        printf '%s' "$vendored"
        return 0
    fi

    # System install on PATH (e.g. a sealed enterprise image).
    local on_path
    if on_path="$(command -v qp-capsule 2>/dev/null)"; then
        printf '%s' "$on_path"
        return 0
    fi

    return 1
}

# ---------------------------------------------------------------------------
# _ensure_capsule
# Checks whether the qp-capsule CLI is available from the vendored offline set
# or a sealed system install. NEVER installs anything: running pip from this
# script would reach public PyPI on every invocation, a dependency-confusion
# and data-exfiltration vector that also breaks air-gap guarantees. Ship
# qp-capsule via the pinned vendored set instead.
#
# Returns:
#   0 if qp-capsule is available, 1 otherwise (caller decides how to gate).
# ---------------------------------------------------------------------------
_ensure_capsule() {
    if _capsule_bin >/dev/null; then
        return 0
    fi

    log_warn "qp-capsule CLI not found (vendored set or PATH)."
    log_warn "Tamper-evident Capsule sealing is unavailable. This script will"
    log_warn "NOT auto-install it: pip from a script breaks air-gap and is a"
    log_warn "dependency-confusion risk. Ship the pinned vendored qp-capsule."
    return 1
}

# ---------------------------------------------------------------------------
# _capsule_seal ENTRY_JSON
# Seals an audit entry as a tamper-evident Capsule (if qp-capsule is available).
# Silently skips if qp-capsule is not installed.
# ---------------------------------------------------------------------------
_capsule_seal() {
    local entry="${1:-}"
    if [[ -z "$entry" ]]; then
        return 0
    fi

    local cap_bin
    if ! cap_bin="$(_capsule_bin)"; then
        return 0
    fi

    local config_dir
    config_dir="$(ensure_config_dir)"
    local db_file="${config_dir}/capsules.db"

    printf '%s' "$entry" | "$cap_bin" seal --db "$db_file" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# audit_verify
# Verifies the integrity of the Capsule audit chain.
# Returns 0 if all Capsules are valid, 1 if tampered or unavailable.
# ---------------------------------------------------------------------------
audit_verify() {
    local cap_bin
    if ! cap_bin="$(_capsule_bin)"; then
        log_error "qp-capsule CLI not installed. Cannot verify audit chain."
        log_info "Ship the pinned qp-capsule via the vendored offline set."
        return 1
    fi

    local config_dir
    config_dir="$(ensure_config_dir)"
    local db_file="${config_dir}/capsules.db"

    if [[ ! -f "$db_file" ]]; then
        log_warn "No capsules database found at $db_file"
        return 1
    fi

    "$cap_bin" verify --db "$db_file"
}

# ---------------------------------------------------------------------------
# audit_require_capsule COMMAND_LABEL
#
# Fail-closed guard for state-changing / security-relevant commands. Call this
# before performing such an operation. If qp-capsule is unavailable the script
# cannot produce tamper-evident audit records, so we REFUSE to proceed rather
# than silently claim audit coverage we cannot deliver. Read-only commands do
# not need this guard.
#
# Override (sealed images where Capsule is intentionally external) is via an
# explicit, named env var so the decision is auditable, never accidental.
#
# Args:
#   COMMAND_LABEL: human-readable name of the command being gated (for logs).
# Returns:
#   0 if Capsule sealing is available (or explicitly overridden), 1 otherwise.
# ---------------------------------------------------------------------------
audit_require_capsule() {
    local command_label="${1:-state-changing command}"

    if _capsule_bin >/dev/null; then
        return 0
    fi

    if [[ "${TUNNEL_ALLOW_UNSEALED_AUDIT:-}" == "1" ]]; then
        log_warn "qp-capsule unavailable; proceeding with '${command_label}'"
        log_warn "because TUNNEL_ALLOW_UNSEALED_AUDIT=1. Audit records for this"
        log_warn "run are NOT tamper-evident."
        return 0
    fi

    log_error "Refusing '${command_label}': qp-capsule unavailable, so this"
    log_error "operation cannot be sealed as tamper-evident audit evidence."
    log_error "Ship the pinned vendored qp-capsule, or set"
    log_error "TUNNEL_ALLOW_UNSEALED_AUDIT=1 to explicitly accept unsealed audit."
    return 1
}
