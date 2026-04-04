#!/usr/bin/env bats
# tests/unit/test_registry.bats
# Unit tests for lib/registry.sh

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-tunnel-$$-$BATS_TEST_NUMBER"
    source "$LIB_DIR/registry.sh"
    registry_init
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# registry_init
# ---------------------------------------------------------------------------

@test "registry_init creates peers.json" {
    local path
    path="$(registry_path)"
    [ -f "$path" ]
}

@test "registry_init is idempotent" {
    registry_init
    local path
    path="$(registry_path)"
    [ -f "$path" ]
    jq empty "$path"
}

@test "registry_init creates valid JSON structure" {
    local path
    path="$(registry_path)"
    run jq -r '.version' "$path"
    [ "$output" = "1" ]
    run jq -r '.peers | length' "$path"
    [ "$output" = "0" ]
    run jq -r '.relay' "$path"
    [ "$output" = "null" ]
}

# ---------------------------------------------------------------------------
# registry_set_relay
# ---------------------------------------------------------------------------

@test "registry_set_relay sets relay info" {
    registry_set_relay "1.2.3.4:51820" "PUBKEY123" "10.8.0.1"
    local path
    path="$(registry_path)"
    run jq -r '.relay.endpoint' "$path"
    [ "$output" = "1.2.3.4:51820" ]
    run jq -r '.relay.public_key' "$path"
    [ "$output" = "PUBKEY123" ]
    run jq -r '.relay.tunnel_ip' "$path"
    [ "$output" = "10.8.0.1" ]
}

# ---------------------------------------------------------------------------
# registry_add_peer
# ---------------------------------------------------------------------------

@test "registry_add_peer adds a peer" {
    registry_add_peer "alice" "ALICEPUBKEY" "10.8.0.10"
    local path
    path="$(registry_path)"
    run jq -r '.peers[0].name' "$path"
    [ "$output" = "alice" ]
    run jq -r '.peers[0].status' "$path"
    [ "$output" = "active" ]
    run jq -r '.peers[0].tunnel_ip' "$path"
    [ "$output" = "10.8.0.10" ]
}

@test "registry_add_peer rejects duplicate active peer" {
    registry_add_peer "alice" "KEY1" "10.8.0.10"
    run registry_add_peer "alice" "KEY2" "10.8.0.11"
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

@test "registry_add_peer rejects invalid names" {
    run registry_add_peer "bad name" "KEY" "10.8.0.10"
    [ "$status" -eq 1 ]
}

@test "registry_add_peer sets added_by" {
    registry_add_peer "bob" "BOBKEY" "10.8.0.11" "admin"
    local path
    path="$(registry_path)"
    run jq -r '.peers[0].added_by' "$path"
    [ "$output" = "admin" ]
}

@test "registry_add_peer allows re-adding a revoked peer" {
    registry_add_peer "alice" "KEY1" "10.8.0.10"
    registry_remove_peer "alice"
    run registry_add_peer "alice" "KEY2" "10.8.0.11"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# registry_remove_peer
# ---------------------------------------------------------------------------

@test "registry_remove_peer marks peer as revoked" {
    registry_add_peer "alice" "KEY" "10.8.0.10"
    registry_remove_peer "alice"
    local path
    path="$(registry_path)"
    run jq -r '.peers[0].status' "$path"
    [ "$output" = "revoked" ]
    run jq -r '.peers[0].revoked_at' "$path"
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "registry_remove_peer fails for unknown peer" {
    run registry_remove_peer "nobody"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No active peer"* ]]
}

# ---------------------------------------------------------------------------
# registry_get_peer
# ---------------------------------------------------------------------------

@test "registry_get_peer returns active peer" {
    registry_add_peer "alice" "KEY" "10.8.0.10"
    run registry_get_peer "alice"
    [ "$status" -eq 0 ]
    [[ "$output" == *"alice"* ]]
}

@test "registry_get_peer fails for missing peer" {
    run registry_get_peer "nobody"
    [ "$status" -eq 1 ]
}

@test "registry_get_peer fails for revoked peer" {
    registry_add_peer "alice" "KEY" "10.8.0.10"
    registry_remove_peer "alice"
    run registry_get_peer "alice"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# registry_list_peers
# ---------------------------------------------------------------------------

@test "registry_list_peers returns active peers only" {
    registry_add_peer "alice" "KEY1" "10.8.0.10"
    registry_add_peer "bob" "KEY2" "10.8.0.11"
    registry_remove_peer "alice"
    run registry_list_peers
    [ "$status" -eq 0 ]
    local count
    count="$(echo "$output" | jq 'length')"
    [ "$count" -eq 1 ]
}

@test "registry_list_peers --all returns all peers" {
    registry_add_peer "alice" "KEY1" "10.8.0.10"
    registry_add_peer "bob" "KEY2" "10.8.0.11"
    registry_remove_peer "alice"
    run registry_list_peers --all
    [ "$status" -eq 0 ]
    local count
    count="$(echo "$output" | jq 'length')"
    [ "$count" -eq 2 ]
}

# ---------------------------------------------------------------------------
# registry_next_ip
# ---------------------------------------------------------------------------

@test "registry_next_ip returns first client IP" {
    run registry_next_ip
    [ "$status" -eq 0 ]
    [ "$output" = "10.8.0.10" ]
}

@test "registry_next_ip increments counter" {
    registry_next_ip >/dev/null
    run registry_next_ip
    [ "$status" -eq 0 ]
    [ "$output" = "10.8.0.11" ]
}

# ---------------------------------------------------------------------------
# registry_peer_count
# ---------------------------------------------------------------------------

@test "registry_peer_count returns zero for empty registry" {
    run registry_peer_count
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "registry_peer_count counts active peers only" {
    registry_add_peer "alice" "KEY1" "10.8.0.10"
    registry_add_peer "bob" "KEY2" "10.8.0.11"
    registry_remove_peer "alice"
    run registry_peer_count
    [ "$output" = "1" ]
}

# ---------------------------------------------------------------------------
# registry_update_relay_key
# ---------------------------------------------------------------------------

@test "registry_update_relay_key updates key" {
    registry_set_relay "1.2.3.4:51820" "OLDKEY" "10.8.0.1"
    registry_update_relay_key "NEWKEY"
    local path
    path="$(registry_path)"
    run jq -r '.relay.public_key' "$path"
    [ "$output" = "NEWKEY" ]
}
