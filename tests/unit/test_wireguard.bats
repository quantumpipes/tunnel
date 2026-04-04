#!/usr/bin/env bats
# tests/unit/test_wireguard.bats
# Unit tests for lib/wireguard.sh
# Tests only functions that do NOT require a live WireGuard interface.

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"
TPL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../templates" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-wg-$$-$BATS_TEST_NUMBER"
    export TUNNEL_INTERFACE="wg0"
    mkdir -p "$TUNNEL_CONFIG_DIR"
    source "$LIB_DIR/wireguard.sh"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# wg_write_config
# ---------------------------------------------------------------------------

@test "wg_write_config creates a valid config file" {
    local conf="$TUNNEL_CONFIG_DIR/test-wg0.conf"
    wg_write_config "$conf" "FAKEPRIVKEY" "10.8.0.1/24" "51820"
    [ -f "$conf" ]
    grep -q "PrivateKey = FAKEPRIVKEY" "$conf"
    grep -q "Address = 10.8.0.1/24" "$conf"
    grep -q "ListenPort = 51820" "$conf"
    grep -q "SaveConfig = true" "$conf"
}

@test "wg_write_config sets 600 permissions" {
    local conf="$TUNNEL_CONFIG_DIR/test-wg0.conf"
    wg_write_config "$conf" "FAKEPRIVKEY" "10.8.0.1/24" "51820"
    local perms
    perms="$(stat -c '%a' "$conf")"
    [ "$perms" = "600" ]
}

@test "wg_write_config overwrites existing file" {
    local conf="$TUNNEL_CONFIG_DIR/test-wg0.conf"
    echo "old content" > "$conf"
    wg_write_config "$conf" "NEWKEY" "10.8.0.2/24" "51821"
    grep -q "NEWKEY" "$conf"
    ! grep -q "old content" "$conf"
}

@test "wg_write_config starts with [Interface] section" {
    local conf="$TUNNEL_CONFIG_DIR/test-wg0.conf"
    wg_write_config "$conf" "KEY" "10.8.0.1/24" "51820"
    local first_line
    first_line="$(head -1 "$conf")"
    [ "$first_line" = "[Interface]" ]
}

# ---------------------------------------------------------------------------
# wg_render_client_config
# ---------------------------------------------------------------------------

@test "wg_render_client_config renders template with variables" {
    local tpl="$TUNNEL_CONFIG_DIR/test.tpl"
    cat > "$tpl" <<'EOF'
[Interface]
PrivateKey = ${CLIENT_KEY}
Address = ${CLIENT_IP}/32
EOF
    run wg_render_client_config "$tpl" "CLIENT_KEY=abc123" "CLIENT_IP=10.8.0.10"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PrivateKey = abc123"* ]]
    [[ "$output" == *"Address = 10.8.0.10/32"* ]]
}

@test "wg_render_client_config with real template file" {
    run wg_render_client_config "$TPL_DIR/client.conf.tpl" \
        "CLIENT_PRIVATE_KEY=PRIVKEY123" \
        "CLIENT_TUNNEL_IP=10.8.0.10" \
        "TUNNEL_DNS_SERVER=10.8.0.2" \
        "RELAY_PUBLIC_KEY=RELAYPUB456" \
        "PRESHARED_KEY=PSK789" \
        "RELAY_ENDPOINT=1.2.3.4:51820" \
        "TUNNEL_ALLOWED_IPS=10.8.0.0/24"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PrivateKey = PRIVKEY123"* ]]
    [[ "$output" == *"Address = 10.8.0.10/32"* ]]
    [[ "$output" == *"DNS = 10.8.0.2"* ]]
    [[ "$output" == *"PublicKey = RELAYPUB456"* ]]
    [[ "$output" == *"PresharedKey = PSK789"* ]]
    [[ "$output" == *"Endpoint = 1.2.3.4:51820"* ]]
    [[ "$output" == *"AllowedIPs = 10.8.0.0/24"* ]]
    [[ "$output" == *"PersistentKeepalive = 25"* ]]
}

@test "wg_render_client_config fails for missing template" {
    run wg_render_client_config "/nonexistent/template.tpl" "KEY=val"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Template not found"* ]]
}

@test "wg_render_client_config leaves unreplaced vars as-is" {
    local tpl="$TUNNEL_CONFIG_DIR/partial.tpl"
    cat > "$tpl" <<'EOF'
Key = ${REPLACED}
Other = ${NOT_REPLACED}
EOF
    run wg_render_client_config "$tpl" "REPLACED=yes"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Key = yes"* ]]
    [[ "$output" == *'${NOT_REPLACED}'* ]]
}

@test "wg_render_client_config handles empty value" {
    local tpl="$TUNNEL_CONFIG_DIR/empty.tpl"
    echo 'DNS = ${DNS}' > "$tpl"
    run wg_render_client_config "$tpl" "DNS="
    [ "$status" -eq 0 ]
    [[ "$output" == "DNS = " ]]
}

@test "wg_render_client_config handles values with special characters" {
    local tpl="$TUNNEL_CONFIG_DIR/special.tpl"
    echo 'Key = ${KEY}' > "$tpl"
    run wg_render_client_config "$tpl" "KEY=abc+def/ghi="
    [ "$status" -eq 0 ]
    [[ "$output" == *"abc+def/ghi="* ]]
}

@test "wg_render_client_config handles values with slashes (base64 keys)" {
    local tpl="$TUNNEL_CONFIG_DIR/b64.tpl"
    echo 'PrivateKey = ${KEY}' > "$tpl"
    run wg_render_client_config "$tpl" "KEY=aB3d+E/fG7h8iJ9kL0mN1oP2qR3sT4u="
    [ "$status" -eq 0 ]
    [[ "$output" == *"aB3d+E/fG7h8iJ9kL0mN1oP2qR3sT4u="* ]]
}

# ---------------------------------------------------------------------------
# wg_interface_exists (always false without WireGuard)
# ---------------------------------------------------------------------------

@test "wg_interface_exists returns false when wg not available" {
    run wg_interface_exists "nonexistent_iface_test_12345"
    [ "$status" -ne 0 ]
}
