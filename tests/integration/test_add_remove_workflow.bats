#!/usr/bin/env bats
# tests/integration/test_add_remove_workflow.bats
# Integration tests for the add-peer and remove-peer workflows.
# Uses mocked wg commands to test the full script logic without WireGuard.

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"
TPL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../templates" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-workflow-$$-$BATS_TEST_NUMBER"
    source "$LIB_DIR/common.sh"
    source "$LIB_DIR/registry.sh"
    source "$LIB_DIR/audit.sh"
    source "$LIB_DIR/wireguard.sh"
    apply_defaults
    registry_init
    registry_set_relay "1.2.3.4:51820" "RELAYPUBKEY123" "10.8.0.1"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Simulated add-peer workflow (registry + config generation, no live wg)
# ---------------------------------------------------------------------------

@test "add workflow: allocate IP, register, render config" {
    local ip
    ip="$(registry_next_ip)"
    [ "$ip" = "10.8.0.10" ]

    registry_add_peer "alice" "ALICEPUB" "$ip"

    local peer_dir="${TUNNEL_CONFIG_DIR}/peers/alice"
    mkdir -p "$peer_dir"
    chmod 700 "$peer_dir"

    local conf
    conf="$(wg_render_client_config "$TPL_DIR/client.conf.tpl" \
        "CLIENT_PRIVATE_KEY=ALICEPRIV" \
        "CLIENT_TUNNEL_IP=$ip" \
        "TUNNEL_DNS_SERVER=${TUNNEL_DNS_SERVER}" \
        "RELAY_PUBLIC_KEY=RELAYPUBKEY123" \
        "PRESHARED_KEY=PSK456" \
        "RELAY_ENDPOINT=1.2.3.4:51820" \
        "TUNNEL_ALLOWED_IPS=${TUNNEL_ALLOWED_IPS}")"

    set_safe_umask
    printf '%s\n' "$conf" > "${peer_dir}/alice.conf"
    chmod 600 "${peer_dir}/alice.conf"

    [[ "$conf" == *"PrivateKey = ALICEPRIV"* ]]
    [[ "$conf" == *"Address = 10.8.0.10/32"* ]]
    [[ "$conf" == *"PublicKey = RELAYPUBKEY123"* ]]
    [[ "$conf" == *"Endpoint = 1.2.3.4:51820"* ]]
    [[ "$conf" == *"AllowedIPs = 10.8.0.0/24"* ]]

    local perms
    perms="$(stat -c '%a' "${peer_dir}/alice.conf")"
    [ "$perms" = "600" ]

    audit_log "peer_add" "success" "Added alice (10.8.0.10)"
}

@test "add workflow: second peer gets next IP" {
    registry_next_ip >/dev/null
    local ip
    ip="$(registry_next_ip)"
    [ "$ip" = "10.8.0.11" ]
}

# ---------------------------------------------------------------------------
# Simulated remove-peer workflow
# ---------------------------------------------------------------------------

@test "remove workflow: revoke and archive" {
    registry_add_peer "bob" "BOBPUB" "10.8.0.10"
    local peer_dir="${TUNNEL_CONFIG_DIR}/peers/bob"
    mkdir -p "$peer_dir"
    echo "fake config" > "${peer_dir}/bob.conf"
    echo "fake psk" > "${peer_dir}/preshared.key"

    local archive_dir="${TUNNEL_CONFIG_DIR}/archive"
    mkdir -p "$archive_dir"
    mv "$peer_dir" "${archive_dir}/bob_revoked_test"

    registry_remove_peer "bob"

    [ ! -d "$peer_dir" ]
    [ -d "${archive_dir}/bob_revoked_test" ]
    [ -f "${archive_dir}/bob_revoked_test/bob.conf" ]

    run registry_get_peer "bob"
    [ "$status" -eq 1 ]

    audit_log "peer_remove" "success" "Removed bob"
}

@test "remove workflow: cannot remove non-existent peer" {
    run registry_get_peer "nonexistent"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Full lifecycle: add, verify, archive, remove, re-add
# ---------------------------------------------------------------------------

@test "full lifecycle: add -> archive -> remove -> re-add" {
    local ip1
    ip1="$(registry_next_ip)"
    registry_add_peer "carol" "KEY1" "$ip1"
    local peer_dir="${TUNNEL_CONFIG_DIR}/peers/carol"
    mkdir -p "$peer_dir"
    echo "config v1" > "${peer_dir}/carol.conf"

    run registry_get_peer "carol"
    [ "$status" -eq 0 ]

    local archive_dir="${TUNNEL_CONFIG_DIR}/archive"
    mkdir -p "$archive_dir"
    mv "$peer_dir" "${archive_dir}/carol_revoked_1"
    registry_remove_peer "carol"

    run registry_get_peer "carol"
    [ "$status" -eq 1 ]

    local ip2
    ip2="$(registry_next_ip)"
    registry_add_peer "carol" "KEY2" "$ip2"
    mkdir -p "$peer_dir"
    echo "config v2" > "${peer_dir}/carol.conf"

    run registry_get_peer "carol"
    [ "$status" -eq 0 ]
    [[ "$output" == *"KEY2"* ]]

    [ -f "${archive_dir}/carol_revoked_1/carol.conf" ]
    [ -f "${peer_dir}/carol.conf" ]
}

# ---------------------------------------------------------------------------
# Status display (without live WireGuard)
# ---------------------------------------------------------------------------

@test "status: shows correct peer count" {
    registry_add_peer "alice" "K1" "10.8.0.10"
    registry_add_peer "bob" "K2" "10.8.0.11"
    registry_add_peer "carol" "K3" "10.8.0.12"
    registry_remove_peer "bob"

    run registry_peer_count
    [ "$output" = "2" ]
}

@test "status: list peers returns JSON with correct fields" {
    registry_add_peer "alice" "K1" "10.8.0.10"
    local peers
    peers="$(registry_list_peers)"
    run jq -r '.[0].name' <<< "$peers"
    [ "$output" = "alice" ]
    run jq -r '.[0].tunnel_ip' <<< "$peers"
    [ "$output" = "10.8.0.10" ]
    run jq -r '.[0].status' <<< "$peers"
    [ "$output" = "active" ]
    run jq -r '.[0].added_at' <<< "$peers"
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

# ---------------------------------------------------------------------------
# Key rotation (registry-level)
# ---------------------------------------------------------------------------

@test "key rotation: registry_update_relay_key changes key" {
    run registry_get_relay
    [[ "$output" == *"RELAYPUBKEY123"* ]]

    registry_update_relay_key "NEWRELAYKEY456"

    run registry_get_relay
    [[ "$output" == *"NEWRELAYKEY456"* ]]
    [[ "$output" != *"RELAYPUBKEY123"* ]]
}

@test "key rotation: relay endpoint preserved after key update" {
    registry_update_relay_key "ROTATEDKEY"
    local relay
    relay="$(registry_get_relay)"
    run jq -r '.endpoint' <<< "$relay"
    [ "$output" = "1.2.3.4:51820" ]
}

# ---------------------------------------------------------------------------
# Audit trail completeness
# ---------------------------------------------------------------------------

@test "audit trail captures full lifecycle" {
    registry_add_peer "dave" "DK" "10.8.0.10"
    audit_log "peer_add" "success" "Added dave" '{"name":"dave"}'

    registry_remove_peer "dave"
    audit_log "peer_remove" "success" "Removed dave" '{"name":"dave"}'

    registry_update_relay_key "NEWKEY"
    audit_log "key_rotate" "success" "Keys rotated" '{"old":"RELAYPUBKEY123","new":"NEWKEY"}'

    local entries
    entries="$(audit_read 10)"
    local count
    count="$(echo "$entries" | jq 'length')"
    [ "$count" -eq 3 ]

    local first_action last_action
    first_action="$(echo "$entries" | jq -r '.[0].action')"
    last_action="$(echo "$entries" | jq -r '.[2].action')"
    [ "$first_action" = "peer_add" ]
    [ "$last_action" = "key_rotate" ]
}
