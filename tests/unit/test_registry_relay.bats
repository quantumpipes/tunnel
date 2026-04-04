#!/usr/bin/env bats
# tests/unit/test_registry_relay.bats
# Tests for registry_get_relay and relay-related operations.

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-relay-$$-$BATS_TEST_NUMBER"
    source "$LIB_DIR/registry.sh"
    registry_init
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# registry_get_relay: success cases
# ---------------------------------------------------------------------------

@test "registry_get_relay returns relay JSON after set" {
    registry_set_relay "1.2.3.4:51820" "RELAYPUB" "10.8.0.1"
    run registry_get_relay
    [ "$status" -eq 0 ]
    [[ "$output" == *"1.2.3.4:51820"* ]]
}

@test "registry_get_relay output contains all fields" {
    registry_set_relay "5.6.7.8:51820" "MYPUBKEY" "10.8.0.1"
    local relay
    relay="$(registry_get_relay)"
    run jq -r '.endpoint' <<< "$relay"
    [ "$output" = "5.6.7.8:51820" ]
    run jq -r '.public_key' <<< "$relay"
    [ "$output" = "MYPUBKEY" ]
    run jq -r '.tunnel_ip' <<< "$relay"
    [ "$output" = "10.8.0.1" ]
}

@test "registry_get_relay output is valid JSON" {
    registry_set_relay "1.2.3.4:51820" "KEY" "10.8.0.1"
    local relay
    relay="$(registry_get_relay)"
    echo "$relay" | jq empty
}

# ---------------------------------------------------------------------------
# registry_set_relay: update (overwrite) behavior
# ---------------------------------------------------------------------------

@test "registry_set_relay overwrites previous relay" {
    registry_set_relay "1.1.1.1:51820" "KEY1" "10.8.0.1"
    registry_set_relay "2.2.2.2:51820" "KEY2" "10.8.0.1"
    local relay
    relay="$(registry_get_relay)"
    run jq -r '.endpoint' <<< "$relay"
    [ "$output" = "2.2.2.2:51820" ]
    run jq -r '.public_key' <<< "$relay"
    [ "$output" = "KEY2" ]
}

@test "registry_set_relay preserves peers" {
    registry_add_peer "alice" "AKEY" "10.8.0.10"
    registry_set_relay "1.2.3.4:51820" "RKEY" "10.8.0.1"
    run registry_peer_count
    [ "$output" = "1" ]
    run registry_get_peer "alice"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# registry_update_relay_key: preserves other relay fields
# ---------------------------------------------------------------------------

@test "registry_update_relay_key preserves endpoint" {
    registry_set_relay "9.8.7.6:51820" "OLDKEY" "10.8.0.1"
    registry_update_relay_key "NEWKEY"
    local relay
    relay="$(registry_get_relay)"
    run jq -r '.endpoint' <<< "$relay"
    [ "$output" = "9.8.7.6:51820" ]
    run jq -r '.public_key' <<< "$relay"
    [ "$output" = "NEWKEY" ]
}

@test "registry_update_relay_key preserves tunnel_ip" {
    registry_set_relay "1.2.3.4:51820" "OLDKEY" "10.8.0.1"
    registry_update_relay_key "NEWKEY"
    local relay
    relay="$(registry_get_relay)"
    run jq -r '.tunnel_ip' <<< "$relay"
    [ "$output" = "10.8.0.1" ]
}

# ---------------------------------------------------------------------------
# Relay + peer interaction
# ---------------------------------------------------------------------------

@test "peers can be added before relay is set" {
    registry_add_peer "alice" "AKEY" "10.8.0.10"
    registry_set_relay "1.2.3.4:51820" "RKEY" "10.8.0.1"
    run registry_peer_count
    [ "$output" = "1" ]
    run registry_get_relay
    [ "$status" -eq 0 ]
}

@test "key rotation does not affect peer data" {
    registry_set_relay "1.2.3.4:51820" "OLDKEY" "10.8.0.1"
    registry_add_peer "alice" "AKEY" "10.8.0.10"
    registry_add_peer "bob" "BKEY" "10.8.0.11"
    registry_update_relay_key "ROTATEDKEY"

    run registry_peer_count
    [ "$output" = "2" ]
    run registry_get_peer "alice"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AKEY"* ]]
    run registry_get_peer "bob"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BKEY"* ]]
}
