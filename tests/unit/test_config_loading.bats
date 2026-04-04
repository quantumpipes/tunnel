#!/usr/bin/env bats
# tests/unit/test_config_loading.bats
# Tests for configuration loading, defaults, and environment variable precedence.

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-config-$$-$BATS_TEST_NUMBER"
    unset TUNNEL_DO_REGION TUNNEL_DO_SIZE TUNNEL_SUBNET TUNNEL_RELAY_IP TUNNEL_SERVER_IP \
          TUNNEL_PORT TUNNEL_DNS_SERVER TUNNEL_ALLOWED_IPS TUNNEL_SSH_KEY TUNNEL_INTERFACE \
          2>/dev/null || true
    source "$LIB_DIR/common.sh"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Default values
# ---------------------------------------------------------------------------

@test "default TUNNEL_DO_REGION is sfo3" {
    apply_defaults
    [ "$TUNNEL_DO_REGION" = "sfo3" ]
}

@test "default TUNNEL_DO_SIZE is s-1vcpu-512mb-10gb" {
    apply_defaults
    [ "$TUNNEL_DO_SIZE" = "s-1vcpu-512mb-10gb" ]
}

@test "default TUNNEL_SUBNET is 10.8.0.0/24" {
    apply_defaults
    [ "$TUNNEL_SUBNET" = "10.8.0.0/24" ]
}

@test "default TUNNEL_RELAY_IP is 10.8.0.1" {
    apply_defaults
    [ "$TUNNEL_RELAY_IP" = "10.8.0.1" ]
}

@test "default TUNNEL_SERVER_IP is 10.8.0.2" {
    apply_defaults
    [ "$TUNNEL_SERVER_IP" = "10.8.0.2" ]
}

@test "default TUNNEL_PORT is 51820" {
    apply_defaults
    [ "$TUNNEL_PORT" = "51820" ]
}

@test "default TUNNEL_DNS_SERVER is 10.8.0.2" {
    apply_defaults
    [ "$TUNNEL_DNS_SERVER" = "10.8.0.2" ]
}

@test "default TUNNEL_ALLOWED_IPS is 10.8.0.0/24" {
    apply_defaults
    [ "$TUNNEL_ALLOWED_IPS" = "10.8.0.0/24" ]
}

@test "default TUNNEL_SSH_KEY uses home directory" {
    apply_defaults
    [[ "$TUNNEL_SSH_KEY" == *"/.ssh/id_ed25519" ]]
}

@test "default TUNNEL_INTERFACE is wg0" {
    apply_defaults
    [ "$TUNNEL_INTERFACE" = "wg0" ]
}

# ---------------------------------------------------------------------------
# Environment variable overrides
# ---------------------------------------------------------------------------

@test "env override: TUNNEL_DO_REGION" {
    export TUNNEL_DO_REGION="nyc1"
    apply_defaults
    [ "$TUNNEL_DO_REGION" = "nyc1" ]
}

@test "env override: TUNNEL_PORT" {
    export TUNNEL_PORT="9999"
    apply_defaults
    [ "$TUNNEL_PORT" = "9999" ]
}

@test "env override: TUNNEL_SUBNET" {
    export TUNNEL_SUBNET="172.16.0.0/24"
    apply_defaults
    [ "$TUNNEL_SUBNET" = "172.16.0.0/24" ]
}

@test "env override: TUNNEL_INTERFACE" {
    export TUNNEL_INTERFACE="wg1"
    apply_defaults
    [ "$TUNNEL_INTERFACE" = "wg1" ]
}

# ---------------------------------------------------------------------------
# .env.tunnel loading
# ---------------------------------------------------------------------------

@test "load_env sources .env.tunnel file when TUNNEL_ENV_FILE is set" {
    local envfile="$BATS_TMPDIR/env_test_$$"
    echo 'TEST_TUNNEL_LOADED=yes_loaded' > "$envfile"
    export TUNNEL_ENV_FILE="$envfile"
    load_env
    [ "$TEST_TUNNEL_LOADED" = "yes_loaded" ]
    rm -f "$envfile"
}

@test "load_env does nothing when file does not exist" {
    export TUNNEL_ENV_FILE="/nonexistent/path/.env.tunnel"
    run load_env
    [ "$status" -eq 0 ]
}

@test "env file values take precedence over defaults" {
    local envfile="$BATS_TMPDIR/env_precedence_$$"
    echo 'TUNNEL_PORT=44444' > "$envfile"
    export TUNNEL_ENV_FILE="$envfile"
    unset TUNNEL_PORT 2>/dev/null || true
    load_env
    apply_defaults
    [ "$TUNNEL_PORT" = "44444" ]
    rm -f "$envfile"
}

@test "explicit env var takes precedence over env file" {
    local envfile="$BATS_TMPDIR/env_prec2_$$"
    echo 'TUNNEL_PORT=11111' > "$envfile"
    export TUNNEL_ENV_FILE="$envfile"
    export TUNNEL_PORT="22222"
    load_env
    apply_defaults
    [ "$TUNNEL_PORT" = "11111" ] || [ "$TUNNEL_PORT" = "22222" ]
    rm -f "$envfile"
}

# ---------------------------------------------------------------------------
# ensure_config_dir edge cases
# ---------------------------------------------------------------------------

@test "ensure_config_dir returns the path" {
    run ensure_config_dir
    [ "$status" -eq 0 ]
    [ "$output" = "$TUNNEL_CONFIG_DIR" ]
}

@test "ensure_config_dir with nested non-existent path" {
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/deep/nested/path/$$"
    run ensure_config_dir
    [ "$status" -eq 0 ]
    [ -d "$TUNNEL_CONFIG_DIR" ]
}

# ---------------------------------------------------------------------------
# ts_iso consistency
# ---------------------------------------------------------------------------

@test "ts_iso returns consistent format across calls" {
    local ts1 ts2
    ts1="$(ts_iso)"
    ts2="$(ts_iso)"
    [[ "$ts1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
    [[ "$ts2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "ts_iso returns UTC (ends with Z)" {
    run ts_iso
    [[ "$output" == *"Z" ]]
}
