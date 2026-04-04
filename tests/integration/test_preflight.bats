#!/usr/bin/env bats
# tests/integration/test_preflight.bats
# Integration tests for tunnel-preflight.sh sourcing and initialization.

PREFLIGHT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-preflight-$$-$BATS_TEST_NUMBER"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

@test "preflight creates config directory" {
    source "$PREFLIGHT_DIR/tunnel-preflight.sh"
    [ -d "$TUNNEL_CONFIG_DIR" ]
}

@test "preflight initializes peers.json" {
    source "$PREFLIGHT_DIR/tunnel-preflight.sh"
    [ -f "$TUNNEL_CONFIG_DIR/peers.json" ]
    jq empty "$TUNNEL_CONFIG_DIR/peers.json"
}

@test "preflight sets default TUNNEL_PORT" {
    unset TUNNEL_PORT 2>/dev/null || true
    source "$PREFLIGHT_DIR/tunnel-preflight.sh"
    [ "$TUNNEL_PORT" = "51820" ]
}

@test "preflight loads .env.tunnel if present" {
    mkdir -p "$BATS_TMPDIR"
    export TUNNEL_ENV_FILE="$BATS_TMPDIR/.env.tunnel.test.$$"
    echo 'TUNNEL_PORT=99999' > "$TUNNEL_ENV_FILE"
    unset TUNNEL_PORT 2>/dev/null || true
    source "$PREFLIGHT_DIR/tunnel-preflight.sh"
    [ "$TUNNEL_PORT" = "99999" ]
    rm -f "$TUNNEL_ENV_FILE"
}

@test "preflight is idempotent" {
    source "$PREFLIGHT_DIR/tunnel-preflight.sh"
    source "$PREFLIGHT_DIR/tunnel-preflight.sh"
    [ -d "$TUNNEL_CONFIG_DIR" ]
    [ -f "$TUNNEL_CONFIG_DIR/peers.json" ]
}
