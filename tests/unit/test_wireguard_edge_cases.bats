#!/usr/bin/env bats
# tests/unit/test_wireguard_edge_cases.bats
# Edge case and security tests for lib/wireguard.sh template rendering.

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-wg-edge-$$-$BATS_TEST_NUMBER"
    export TUNNEL_INTERFACE="wg0"
    mkdir -p "$TUNNEL_CONFIG_DIR"
    source "$LIB_DIR/wireguard.sh"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# wg_render_client_config: injection prevention
# ---------------------------------------------------------------------------

@test "render: value containing \${OTHER} does not expand nested var" {
    local tpl="$TUNNEL_CONFIG_DIR/inject.tpl"
    echo 'Key = ${KEY}' > "$tpl"
    run wg_render_client_config "$tpl" 'KEY=${SHOULD_NOT_EXPAND}'
    [ "$status" -eq 0 ]
    [[ "$output" == 'Key = ${SHOULD_NOT_EXPAND}' ]]
}

@test "render: value containing shell metacharacters passes through safely" {
    local tpl="$TUNNEL_CONFIG_DIR/meta.tpl"
    echo 'Val = ${VAL}' > "$tpl"
    run wg_render_client_config "$tpl" 'VAL=`whoami`; rm -rf /'
    [ "$status" -eq 0 ]
    [[ "$output" == 'Val = `whoami`; rm -rf /' ]]
}

@test "render: value containing dollar sign but not \${} passes through" {
    local tpl="$TUNNEL_CONFIG_DIR/dollar.tpl"
    echo 'Val = ${VAL}' > "$tpl"
    run wg_render_client_config "$tpl" 'VAL=$HOME'
    [ "$status" -eq 0 ]
    [[ "$output" == 'Val = $HOME' ]]
}

@test "render: value with newlines passes through" {
    local tpl="$TUNNEL_CONFIG_DIR/newline.tpl"
    echo 'Val = ${VAL}' > "$tpl"
    run wg_render_client_config "$tpl" "VAL=line1
line2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"line1"* ]]
}

@test "render: no args just returns template content" {
    local tpl="$TUNNEL_CONFIG_DIR/noargs.tpl"
    echo 'Static content only' > "$tpl"
    run wg_render_client_config "$tpl"
    [ "$status" -eq 0 ]
    [[ "$output" == "Static content only" ]]
}

@test "render: multiple occurrences of same variable all replaced" {
    local tpl="$TUNNEL_CONFIG_DIR/multi.tpl"
    printf '%s\n%s\n' 'First = ${KEY}' 'Second = ${KEY}' > "$tpl"
    run wg_render_client_config "$tpl" "KEY=replaced"
    [ "$status" -eq 0 ]
    [[ "$output" == *"First = replaced"* ]]
    [[ "$output" == *"Second = replaced"* ]]
}

@test "render: value containing equals sign" {
    local tpl="$TUNNEL_CONFIG_DIR/eq.tpl"
    echo 'Key = ${KEY}' > "$tpl"
    run wg_render_client_config "$tpl" "KEY=aB3d+E/fG7h8=iJ9="
    [ "$status" -eq 0 ]
    [[ "$output" == *"aB3d+E/fG7h8=iJ9="* ]]
}

# ---------------------------------------------------------------------------
# wg_write_config: edge cases
# ---------------------------------------------------------------------------

@test "wg_write_config: config contains exactly 5 lines" {
    local conf="$TUNNEL_CONFIG_DIR/count.conf"
    wg_write_config "$conf" "KEY" "10.8.0.1/24" "51820"
    local lines
    lines="$(wc -l < "$conf")"
    [ "$lines" -eq 5 ]
}

@test "wg_write_config: handles base64 key with slashes and plus" {
    local conf="$TUNNEL_CONFIG_DIR/b64.conf"
    local key="aB3d+E/fG7h8iJ9kL0mN1oP2qR3sT4uVwXyZ012345="
    wg_write_config "$conf" "$key" "10.8.0.1/24" "51820"
    grep -q "$key" "$conf"
}

@test "wg_write_config: creates parent directories if they exist" {
    local conf="$TUNNEL_CONFIG_DIR/sub/dir/wg.conf"
    mkdir -p "$(dirname "$conf")"
    wg_write_config "$conf" "KEY" "10.8.0.1/24" "51820"
    [ -f "$conf" ]
}

@test "wg_write_config: does not contain any shell variable references" {
    local conf="$TUNNEL_CONFIG_DIR/noshell.conf"
    wg_write_config "$conf" "MYKEY" "10.8.0.1/24" "51820"
    ! grep -q '\$' "$conf"
}

# ---------------------------------------------------------------------------
# wg_interface_exists: negative case without WireGuard
# ---------------------------------------------------------------------------

@test "wg_interface_exists: returns non-zero for any interface when wg unavailable" {
    run wg_interface_exists "wg99"
    [ "$status" -ne 0 ]
}

@test "wg_interface_exists: uses TUNNEL_INTERFACE default" {
    export TUNNEL_INTERFACE="wg_test_iface"
    run wg_interface_exists
    [ "$status" -ne 0 ]
}
