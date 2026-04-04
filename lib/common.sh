#!/usr/bin/env bash
# lib/common.sh
# Common utilities for QP Tunnel automation scripts.
# Sourced by all tunnel-* scripts. Never executed directly.
#
# Copyright 2026 Quantum Pipes Technologies, LLC
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors (disabled when stdout is not a terminal)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    _C_RED='\033[0;31m'
    _C_GREEN='\033[0;32m'
    _C_YELLOW='\033[0;33m'
    _C_CYAN='\033[0;36m'
    _C_NC='\033[0m'
else
    _C_RED=''
    _C_GREEN=''
    _C_YELLOW=''
    _C_CYAN=''
    _C_NC=''
fi

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log_info() {
    printf '%b[INFO]%b %s\n' "$_C_CYAN" "$_C_NC" "$*" >&2
}

log_warn() {
    printf '%b[WARN]%b %s\n' "$_C_YELLOW" "$_C_NC" "$*" >&2
}

log_error() {
    printf '%b[ERROR]%b %s\n' "$_C_RED" "$_C_NC" "$*" >&2
}

log_success() {
    printf '%b[OK]%b %s\n' "$_C_GREEN" "$_C_NC" "$*" >&2
}

# ---------------------------------------------------------------------------
# require_cmd CMD [CMD ...]
# Exits with error if any command is not found on PATH.
# ---------------------------------------------------------------------------
require_cmd() {
    local cmd
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done
}

# ---------------------------------------------------------------------------
# require_env VAR [VAR ...]
# Exits with error if any environment variable is unset or empty.
# ---------------------------------------------------------------------------
require_env() {
    local var
    for var in "$@"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable not set: $var"
            return 1
        fi
    done
}

# ---------------------------------------------------------------------------
# validate_peer_name NAME
# Returns 0 if NAME matches ^[a-zA-Z0-9_-]+$, 1 otherwise.
# ---------------------------------------------------------------------------
validate_peer_name() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        log_error "Peer name must not be empty"
        return 1
    fi
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid peer name '$name': only alphanumeric, hyphen, underscore allowed"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# set_safe_umask
# Sets umask 077 so generated keys/configs are owner-only.
# ---------------------------------------------------------------------------
set_safe_umask() {
    umask 077
}

# ---------------------------------------------------------------------------
# mask_token VALUE
# Replaces all but the last 4 characters with asterisks.
# Used to safely log sensitive values like API tokens.
# ---------------------------------------------------------------------------
mask_token() {
    local val="${1:-}"
    local len=${#val}
    if (( len <= 4 )); then
        printf '%s' '****'
    else
        local masked_len=$(( len - 4 ))
        printf '%*s' "$masked_len" '' | tr ' ' '*'
        printf '%s' "${val: -4}"
    fi
}

# ---------------------------------------------------------------------------
# ensure_config_dir
# Creates TUNNEL_CONFIG_DIR with safe permissions if it does not exist.
# ---------------------------------------------------------------------------
ensure_config_dir() {
    local dir="${TUNNEL_CONFIG_DIR:-$HOME/.config/${TUNNEL_APP_NAME:-qp-tunnel}}"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        chmod 700 "$dir"
    fi
    printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# load_env
# Sources .env.tunnel from the project root if it exists.
# ---------------------------------------------------------------------------
load_env() {
    local env_file="${TUNNEL_ENV_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.env.tunnel}"
    if [[ -f "$env_file" ]]; then
        # shellcheck disable=SC1090
        source "$env_file"
    fi
}

# ---------------------------------------------------------------------------
# Default config values (can be overridden by .env.tunnel or environment)
# ---------------------------------------------------------------------------
apply_defaults() {
    export TUNNEL_APP_NAME="${TUNNEL_APP_NAME:-qp-tunnel}"
    export TUNNEL_DO_REGION="${TUNNEL_DO_REGION:-sfo3}"
    export TUNNEL_DO_SIZE="${TUNNEL_DO_SIZE:-s-1vcpu-512mb-10gb}"
    export TUNNEL_SUBNET="${TUNNEL_SUBNET:-10.8.0.0/24}"
    export TUNNEL_RELAY_IP="${TUNNEL_RELAY_IP:-10.8.0.1}"
    export TUNNEL_SERVER_IP="${TUNNEL_SERVER_IP:-10.8.0.2}"
    export TUNNEL_PORT="${TUNNEL_PORT:-51820}"
    export TUNNEL_DNS_SERVER="${TUNNEL_DNS_SERVER:-10.8.0.2}"
    export TUNNEL_ALLOWED_IPS="${TUNNEL_ALLOWED_IPS:-10.8.0.0/24}"
    export TUNNEL_CONFIG_DIR="${TUNNEL_CONFIG_DIR:-$HOME/.config/${TUNNEL_APP_NAME}}"
    export TUNNEL_SSH_KEY="${TUNNEL_SSH_KEY:-$HOME/.ssh/id_ed25519}"
    export TUNNEL_INTERFACE="${TUNNEL_INTERFACE:-wg0}"
}

# ---------------------------------------------------------------------------
# ts_iso
# Prints the current UTC timestamp in ISO 8601 format.
# ---------------------------------------------------------------------------
ts_iso() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}
