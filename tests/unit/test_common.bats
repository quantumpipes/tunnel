#!/usr/bin/env bats
# tests/unit/test_common.bats
# Unit tests for lib/common.sh

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-tunnel-$$"
    source "$LIB_DIR/common.sh"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

@test "log_info writes to stderr" {
    run log_info "hello world"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INFO]"* ]]
    [[ "$output" == *"hello world"* ]]
}

@test "log_warn writes to stderr" {
    run log_warn "caution"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN]"* ]]
    [[ "$output" == *"caution"* ]]
}

@test "log_error writes to stderr" {
    run log_error "something broke"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[ERROR]"* ]]
    [[ "$output" == *"something broke"* ]]
}

@test "log_success writes to stderr" {
    run log_success "done"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[OK]"* ]]
    [[ "$output" == *"done"* ]]
}

# ---------------------------------------------------------------------------
# require_cmd
# ---------------------------------------------------------------------------

@test "require_cmd succeeds for existing commands" {
    run require_cmd bash
    [ "$status" -eq 0 ]
}

@test "require_cmd fails for missing command" {
    run require_cmd nonexistent_cmd_xyz_123
    [ "$status" -eq 1 ]
    [[ "$output" == *"nonexistent_cmd_xyz_123"* ]]
}

@test "require_cmd checks multiple commands" {
    run require_cmd bash ls
    [ "$status" -eq 0 ]
}

@test "require_cmd fails if any command is missing" {
    run require_cmd bash nonexistent_cmd_xyz_123
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# require_env
# ---------------------------------------------------------------------------

@test "require_env succeeds when variable is set" {
    export TEST_VAR_ABC="value"
    run require_env TEST_VAR_ABC
    [ "$status" -eq 0 ]
    unset TEST_VAR_ABC
}

@test "require_env fails when variable is unset" {
    unset MISSING_VAR_XYZ 2>/dev/null || true
    run require_env MISSING_VAR_XYZ
    [ "$status" -eq 1 ]
    [[ "$output" == *"MISSING_VAR_XYZ"* ]]
}

@test "require_env fails when variable is empty" {
    export EMPTY_VAR=""
    run require_env EMPTY_VAR
    [ "$status" -eq 1 ]
    unset EMPTY_VAR
}

# ---------------------------------------------------------------------------
# validate_peer_name
# ---------------------------------------------------------------------------

@test "validate_peer_name accepts alphanumeric" {
    run validate_peer_name "alice"
    [ "$status" -eq 0 ]
}

@test "validate_peer_name accepts hyphens and underscores" {
    run validate_peer_name "bob-laptop_2"
    [ "$status" -eq 0 ]
}

@test "validate_peer_name rejects empty" {
    run validate_peer_name ""
    [ "$status" -eq 1 ]
}

@test "validate_peer_name rejects spaces" {
    run validate_peer_name "has space"
    [ "$status" -eq 1 ]
}

@test "validate_peer_name rejects dots" {
    run validate_peer_name "has.dot"
    [ "$status" -eq 1 ]
}

@test "validate_peer_name rejects slashes" {
    run validate_peer_name "../../etc/passwd"
    [ "$status" -eq 1 ]
}

@test "validate_peer_name rejects shell metacharacters" {
    run validate_peer_name 'foo;rm -rf /'
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# set_safe_umask
# ---------------------------------------------------------------------------

@test "set_safe_umask sets umask to 077" {
    set_safe_umask
    result="$(umask)"
    [ "$result" = "0077" ]
}

# ---------------------------------------------------------------------------
# mask_token
# ---------------------------------------------------------------------------

@test "mask_token masks long token" {
    run mask_token "abcdefghijklmnop"
    [ "$status" -eq 0 ]
    [[ "$output" == *"mnop" ]]
    [[ "$output" != *"abcdefghij"* ]]
}

@test "mask_token masks short token" {
    run mask_token "abc"
    [ "$status" -eq 0 ]
    [ "$output" = "****" ]
}

@test "mask_token handles empty" {
    run mask_token ""
    [ "$status" -eq 0 ]
    [ "$output" = "****" ]
}

# ---------------------------------------------------------------------------
# ensure_config_dir
# ---------------------------------------------------------------------------

@test "ensure_config_dir creates directory" {
    run ensure_config_dir
    [ "$status" -eq 0 ]
    [ -d "$TUNNEL_CONFIG_DIR" ]
}

@test "ensure_config_dir is idempotent" {
    ensure_config_dir >/dev/null
    run ensure_config_dir
    [ "$status" -eq 0 ]
    [ -d "$TUNNEL_CONFIG_DIR" ]
}

@test "ensure_config_dir sets 700 permissions" {
    ensure_config_dir >/dev/null
    perms="$(stat -c '%a' "$TUNNEL_CONFIG_DIR")"
    [ "$perms" = "700" ]
}

# ---------------------------------------------------------------------------
# apply_defaults
# ---------------------------------------------------------------------------

@test "apply_defaults sets TUNNEL_PORT" {
    unset TUNNEL_PORT 2>/dev/null || true
    apply_defaults
    [ "$TUNNEL_PORT" = "51820" ]
}

@test "apply_defaults does not override existing values" {
    export TUNNEL_PORT="12345"
    apply_defaults
    [ "$TUNNEL_PORT" = "12345" ]
}

@test "apply_defaults sets TUNNEL_SUBNET" {
    unset TUNNEL_SUBNET 2>/dev/null || true
    apply_defaults
    [ "$TUNNEL_SUBNET" = "10.8.0.0/24" ]
}

# ---------------------------------------------------------------------------
# ts_iso
# ---------------------------------------------------------------------------

@test "ts_iso returns ISO 8601 format" {
    run ts_iso
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}
