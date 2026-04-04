#!/usr/bin/env bats
# tests/unit/test_security.bats
# Security-focused tests: file permissions, key handling, token masking, no eval.

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"
SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-sec-$$-$BATS_TEST_NUMBER"
    source "$LIB_DIR/common.sh"
    source "$LIB_DIR/registry.sh"
    source "$LIB_DIR/audit.sh"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# No eval in any script (critical security guarantee)
# ---------------------------------------------------------------------------

@test "no eval in lib/common.sh" {
    ! grep -q '\beval\b' "$LIB_DIR/common.sh"
}

@test "no eval in lib/registry.sh" {
    ! grep -q '\beval\b' "$LIB_DIR/registry.sh"
}

@test "no eval in lib/audit.sh" {
    ! grep -q '\beval\b' "$LIB_DIR/audit.sh"
}

@test "no eval in lib/wireguard.sh" {
    ! grep -q '\beval\b' "$LIB_DIR/wireguard.sh"
}

@test "no eval in tunnel-add-peer.sh" {
    ! grep -q '\beval\b' "$SCRIPTS_DIR/tunnel-add-peer.sh"
}

@test "no eval in tunnel-remove-peer.sh" {
    ! grep -q '\beval\b' "$SCRIPTS_DIR/tunnel-remove-peer.sh"
}

@test "no eval in tunnel-setup-relay.sh" {
    ! grep -q '\beval\b' "$SCRIPTS_DIR/tunnel-setup-relay.sh"
}

@test "no eval in tunnel-join.sh" {
    ! grep -q '\beval\b' "$SCRIPTS_DIR/tunnel-join.sh"
}

@test "no eval in tunnel-status.sh" {
    ! grep -q '\beval\b' "$SCRIPTS_DIR/tunnel-status.sh"
}

@test "no eval in tunnel-rotate-keys.sh" {
    ! grep -q '\beval\b' "$SCRIPTS_DIR/tunnel-rotate-keys.sh"
}

@test "no eval in tunnel-preflight.sh" {
    ! grep -q '\beval\b' "$SCRIPTS_DIR/tunnel-preflight.sh"
}

# ---------------------------------------------------------------------------
# set -euo pipefail in every script
# ---------------------------------------------------------------------------

@test "set -euo pipefail in lib/common.sh" {
    grep -q 'set -euo pipefail' "$LIB_DIR/common.sh"
}

@test "set -euo pipefail in lib/registry.sh" {
    grep -q 'set -euo pipefail' "$LIB_DIR/registry.sh"
}

@test "set -euo pipefail in lib/audit.sh" {
    grep -q 'set -euo pipefail' "$LIB_DIR/audit.sh"
}

@test "set -euo pipefail in lib/wireguard.sh" {
    grep -q 'set -euo pipefail' "$LIB_DIR/wireguard.sh"
}

@test "set -euo pipefail in tunnel-add-peer.sh" {
    grep -q 'set -euo pipefail' "$SCRIPTS_DIR/tunnel-add-peer.sh"
}

@test "set -euo pipefail in tunnel-remove-peer.sh" {
    grep -q 'set -euo pipefail' "$SCRIPTS_DIR/tunnel-remove-peer.sh"
}

@test "set -euo pipefail in tunnel-setup-relay.sh" {
    grep -q 'set -euo pipefail' "$SCRIPTS_DIR/tunnel-setup-relay.sh"
}

@test "set -euo pipefail in tunnel-join.sh" {
    grep -q 'set -euo pipefail' "$SCRIPTS_DIR/tunnel-join.sh"
}

@test "set -euo pipefail in tunnel-status.sh" {
    grep -q 'set -euo pipefail' "$SCRIPTS_DIR/tunnel-status.sh"
}

@test "set -euo pipefail in tunnel-rotate-keys.sh" {
    grep -q 'set -euo pipefail' "$SCRIPTS_DIR/tunnel-rotate-keys.sh"
}

@test "set -euo pipefail in tunnel-preflight.sh" {
    grep -q 'set -euo pipefail' "$SCRIPTS_DIR/tunnel-preflight.sh"
}

# ---------------------------------------------------------------------------
# File permissions
# ---------------------------------------------------------------------------

@test "config directory created with 700 permissions" {
    ensure_config_dir >/dev/null
    local perms
    perms="$(stat -c '%a' "$TUNNEL_CONFIG_DIR")"
    [ "$perms" = "700" ]
}

@test "peers.json created with 600 permissions" {
    registry_init
    local path
    path="$(registry_path)"
    local perms
    perms="$(stat -c '%a' "$path")"
    [ "$perms" = "600" ]
}

@test "set_safe_umask enforces 077" {
    set_safe_umask
    local result
    result="$(umask)"
    [ "$result" = "0077" ]
    local testfile="$TUNNEL_CONFIG_DIR/umask_test"
    mkdir -p "$TUNNEL_CONFIG_DIR"
    touch "$testfile"
    local perms
    perms="$(stat -c '%a' "$testfile")"
    [ "$perms" = "600" ]
}

# ---------------------------------------------------------------------------
# Token masking thoroughness
# ---------------------------------------------------------------------------

@test "mask_token masks 8-char token" {
    run mask_token "abcd1234"
    [[ "$output" == "****1234" ]]
}

@test "mask_token masks 64-char token (typical DO token)" {
    local token="dop_v1_0123456789abcdef0123456789abcdef0123456789abcdef0123456789ab"
    run mask_token "$token"
    [[ "$output" == *"89ab" ]]
    [[ "$output" != *"dop_v1"* ]]
    [ "${#output}" -eq "${#token}" ]
}

@test "mask_token with exactly 4 chars masks entirely" {
    run mask_token "abcd"
    [ "$output" = "****" ]
}

@test "mask_token with exactly 5 chars shows last 4" {
    run mask_token "abcde"
    [ "$output" = "*bcde" ]
}

# ---------------------------------------------------------------------------
# Peer name injection prevention
# ---------------------------------------------------------------------------

@test "validate_peer_name blocks null bytes" {
    run validate_peer_name $'\x00'
    [ "$status" -eq 1 ]
}

@test "validate_peer_name blocks command substitution syntax" {
    run validate_peer_name '$(whoami)'
    [ "$status" -eq 1 ]
}

@test "validate_peer_name blocks backtick command substitution" {
    run validate_peer_name '`id`'
    [ "$status" -eq 1 ]
}

@test "validate_peer_name blocks glob characters" {
    run validate_peer_name 'peer*'
    [ "$status" -eq 1 ]
}

@test "validate_peer_name blocks question mark glob" {
    run validate_peer_name 'peer?'
    [ "$status" -eq 1 ]
}

@test "validate_peer_name blocks square brackets" {
    run validate_peer_name 'peer[0]'
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Audit log token masking in details
# ---------------------------------------------------------------------------

@test "audit_log message does not leak DO_API_TOKEN" {
    export DO_API_TOKEN="dop_v1_supersecretvalue"
    audit_log "setup" "success" "Using token dop_v1_supersecretvalue for relay"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    local msg
    msg="$(jq -r '.message' <<< "$line")"
    [[ "$msg" != *"supersecret"* ]]
    [[ "$msg" == *"****"* ]]
    unset DO_API_TOKEN
}
