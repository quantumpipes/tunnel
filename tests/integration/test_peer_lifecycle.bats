#!/usr/bin/env bats
# tests/integration/test_peer_lifecycle.bats
# Integration tests for the full peer add/remove lifecycle (registry-level, no WireGuard required).

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-lifecycle-$$-$BATS_TEST_NUMBER"
    source "$LIB_DIR/registry.sh"
    source "$LIB_DIR/audit.sh"
    registry_init
    registry_set_relay "1.2.3.4:51820" "RELAYPUBKEY" "10.8.0.1"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

@test "full lifecycle: add, verify, remove, verify revoked" {
    registry_add_peer "alice" "ALICEKEY" "10.8.0.10"
    audit_log "peer_add" "success" "Added alice"

    run registry_get_peer "alice"
    [ "$status" -eq 0 ]
    [[ "$output" == *"active"* ]]

    registry_remove_peer "alice"
    audit_log "peer_remove" "success" "Removed alice"

    run registry_get_peer "alice"
    [ "$status" -eq 1 ]

    run audit_read 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"peer_add"* ]]
    [[ "$output" == *"peer_remove"* ]]
}

@test "multiple peers: add three, remove one, verify counts" {
    registry_add_peer "alice" "KEY1" "10.8.0.10"
    registry_add_peer "bob" "KEY2" "10.8.0.11"
    registry_add_peer "carol" "KEY3" "10.8.0.12"

    run registry_peer_count
    [ "$output" = "3" ]

    registry_remove_peer "bob"

    run registry_peer_count
    [ "$output" = "2" ]

    run registry_list_peers --all
    local total
    total="$(echo "$output" | jq 'length')"
    [ "$total" -eq 3 ]
}

@test "IP allocation tracks correctly through lifecycle" {
    ip1="$(registry_next_ip)"
    [ "$ip1" = "10.8.0.10" ]

    ip2="$(registry_next_ip)"
    [ "$ip2" = "10.8.0.11" ]

    ip3="$(registry_next_ip)"
    [ "$ip3" = "10.8.0.12" ]

    registry_add_peer "alice" "KEY1" "$ip1"
    registry_remove_peer "alice"

    ip4="$(registry_next_ip)"
    [ "$ip4" = "10.8.0.13" ]
}

@test "re-adding revoked peer creates separate entry" {
    registry_add_peer "alice" "KEY1" "10.8.0.10"
    registry_remove_peer "alice"
    registry_add_peer "alice" "KEY2" "10.8.0.11"

    run registry_list_peers --all
    local total
    total="$(echo "$output" | jq 'length')"
    [ "$total" -eq 2 ]

    run registry_get_peer "alice"
    [[ "$output" == *"KEY2"* ]]
    [[ "$output" == *"10.8.0.11"* ]]
}

@test "relay update preserves peer data" {
    registry_add_peer "alice" "KEY1" "10.8.0.10"
    registry_set_relay "5.6.7.8:51820" "NEWRELAYKEY" "10.8.0.1"

    run registry_get_peer "alice"
    [ "$status" -eq 0 ]

    run registry_get_relay
    [[ "$output" == *"5.6.7.8"* ]]
}
