#!/usr/bin/env bats
# tests/unit/test_common_edge_cases.bats
# Edge case tests for lib/common.sh: require_cmd, require_env, mask_token, validate_peer_name.

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-common-edge-$$-$BATS_TEST_NUMBER"
    source "$LIB_DIR/common.sh"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# require_cmd
# ---------------------------------------------------------------------------

@test "require_cmd succeeds for existing command" {
    run require_cmd "jq"
    [ "$status" -eq 0 ]
}

@test "require_cmd fails for missing command" {
    run require_cmd "nonexistent_cmd_xyz_12345"
    [ "$status" -eq 1 ]
    [[ "$output" == *"nonexistent_cmd_xyz_12345"* ]]
}

@test "require_cmd checks multiple commands and fails on first missing" {
    run require_cmd "jq" "nonexistent_cmd_xyz_12345"
    [ "$status" -eq 1 ]
    [[ "$output" == *"nonexistent_cmd_xyz_12345"* ]]
}

@test "require_cmd succeeds with multiple existing commands" {
    run require_cmd "jq" "bash"
    [ "$status" -eq 0 ]
}

@test "require_cmd error message includes command name" {
    run require_cmd "zzz_not_a_real_cmd"
    [[ "$output" == *"Required command not found"* ]]
    [[ "$output" == *"zzz_not_a_real_cmd"* ]]
}

# ---------------------------------------------------------------------------
# require_env
# ---------------------------------------------------------------------------

@test "require_env succeeds for set variable" {
    export TEST_VAR_REQUIRE="hello"
    run require_env "TEST_VAR_REQUIRE"
    [ "$status" -eq 0 ]
    unset TEST_VAR_REQUIRE
}

@test "require_env fails for unset variable" {
    unset UNSET_VAR_XYZ 2>/dev/null || true
    run require_env "UNSET_VAR_XYZ"
    [ "$status" -eq 1 ]
    [[ "$output" == *"UNSET_VAR_XYZ"* ]]
}

@test "require_env fails for empty variable" {
    export EMPTY_VAR=""
    run require_env "EMPTY_VAR"
    [ "$status" -eq 1 ]
    unset EMPTY_VAR
}

@test "require_env checks multiple vars and fails on first empty" {
    export GOOD_VAR="ok"
    export BAD_VAR=""
    run require_env "GOOD_VAR" "BAD_VAR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BAD_VAR"* ]]
    unset GOOD_VAR BAD_VAR
}

@test "require_env succeeds with multiple set variables" {
    export V1="a" V2="b"
    run require_env "V1" "V2"
    [ "$status" -eq 0 ]
    unset V1 V2
}

# ---------------------------------------------------------------------------
# mask_token edge cases
# ---------------------------------------------------------------------------

@test "mask_token with 1-char input returns ****" {
    run mask_token "x"
    [ "$output" = "****" ]
}

@test "mask_token with 2-char input returns ****" {
    run mask_token "ab"
    [ "$output" = "****" ]
}

@test "mask_token with 3-char input returns ****" {
    run mask_token "abc"
    [ "$output" = "****" ]
}

@test "mask_token with empty input returns ****" {
    run mask_token ""
    [ "$output" = "****" ]
}

@test "mask_token preserves exact length for long tokens" {
    local token="dop_v1_0123456789abcdef01234567"
    run mask_token "$token"
    [ "${#output}" -eq "${#token}" ]
}

@test "mask_token output starts with asterisks" {
    run mask_token "secretvalue"
    [[ "$output" == "***"* ]]
}

@test "mask_token output ends with last 4 chars" {
    run mask_token "secretvalue"
    [[ "$output" == *"alue" ]]
}

# ---------------------------------------------------------------------------
# validate_peer_name: error message content
# ---------------------------------------------------------------------------

@test "validate_peer_name empty error says must not be empty" {
    run validate_peer_name ""
    [[ "$output" == *"must not be empty"* ]]
}

@test "validate_peer_name invalid char error includes the name" {
    run validate_peer_name "bad.name"
    [[ "$output" == *"bad.name"* ]]
    [[ "$output" == *"only alphanumeric"* ]]
}

# ---------------------------------------------------------------------------
# TUNNEL_APP_NAME customization
# ---------------------------------------------------------------------------

@test "TUNNEL_APP_NAME defaults to qp-tunnel" {
    unset TUNNEL_APP_NAME
    source "$LIB_DIR/common.sh"
    [ "$TUNNEL_APP_NAME" = "qp-tunnel" ]
}

@test "TUNNEL_APP_NAME can be overridden" {
    export TUNNEL_APP_NAME="custom-app"
    source "$LIB_DIR/common.sh"
    [ "$TUNNEL_APP_NAME" = "custom-app" ]
}

# ---------------------------------------------------------------------------
# ensure_config_dir idempotent
# ---------------------------------------------------------------------------

@test "ensure_config_dir creates and returns path" {
    run ensure_config_dir
    [ "$status" -eq 0 ]
    [ -d "$TUNNEL_CONFIG_DIR" ]
    [ "$output" = "$TUNNEL_CONFIG_DIR" ]
}

@test "ensure_config_dir is idempotent with existing dir" {
    mkdir -p "$TUNNEL_CONFIG_DIR"
    chmod 700 "$TUNNEL_CONFIG_DIR"
    run ensure_config_dir
    [ "$status" -eq 0 ]
    [ -d "$TUNNEL_CONFIG_DIR" ]
}
