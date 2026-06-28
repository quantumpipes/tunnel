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

# ---------------------------------------------------------------------------
# Fail-closed Capsule gate for state-changing commands (air-gap / tamper)
# ---------------------------------------------------------------------------

# Build a wrapper script with a state-changing basename that sources the real
# preflight, so BASH_SOURCE[1] in preflight resolves to that name.
_make_state_changing_wrapper() {
    local name="$1"
    local dir="$BATS_TMPDIR/sc-wrap-$$-$BATS_TEST_NUMBER"
    mkdir -p "$dir"
    cat > "$dir/${name}.sh" <<WRAP
#!/usr/bin/env bash
set -euo pipefail
source "$PREFLIGHT_DIR/tunnel-preflight.sh"
echo "REACHED_BODY"
WRAP
    chmod +x "$dir/${name}.sh"
    printf '%s' "$dir/${name}.sh"
}

@test "preflight FAILS CLOSED for a state-changing command when qp-capsule is absent" {
    local wrapper
    wrapper="$(_make_state_changing_wrapper tunnel-add-peer)"
    # Empty PATH dir + no vendored capsule + no override => must refuse.
    local empty="$BATS_TMPDIR/empty-bin-$$-$BATS_TEST_NUMBER"
    mkdir -p "$empty"
    run env PATH="$empty:$PATH" TUNNEL_CAPSULE_BIN="" TUNNEL_ALLOW_UNSEALED_AUDIT="" \
        bash -c "unset TUNNEL_ALLOW_UNSEALED_AUDIT; \
                 command() { if [ \"\$2\" = qp-capsule ]; then return 1; fi; builtin command \"\$@\"; }; \
                 export -f command; bash '$wrapper'"
    [ "$status" -ne 0 ]
    [[ "$output" != *"REACHED_BODY"* ]]
    [[ "$output" == *"Refusing"* ]]
    rm -rf "$empty"
}

@test "preflight proceeds for a state-changing command with override set" {
    local wrapper
    wrapper="$(_make_state_changing_wrapper tunnel-add-peer)"
    run bash -c "export TUNNEL_ALLOW_UNSEALED_AUDIT=1; \
                 command() { if [ \"\$2\" = qp-capsule ]; then return 1; fi; builtin command \"\$@\"; }; \
                 export -f command; bash '$wrapper'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"REACHED_BODY"* ]]
}

@test "preflight does NOT gate a read-only command (status) when qp-capsule is absent" {
    local wrapper
    wrapper="$(_make_state_changing_wrapper tunnel-status)"
    run bash -c "unset TUNNEL_ALLOW_UNSEALED_AUDIT; \
                 command() { if [ \"\$2\" = qp-capsule ]; then return 1; fi; builtin command \"\$@\"; }; \
                 export -f command; bash '$wrapper'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"REACHED_BODY"* ]]
}
