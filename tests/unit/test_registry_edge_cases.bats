#!/usr/bin/env bats
# tests/unit/test_registry_edge_cases.bats
# Edge case and error path tests for the peer registry.

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-reg-edge-$$-$BATS_TEST_NUMBER"
    source "$LIB_DIR/registry.sh"
    registry_init
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Corrupt JSON recovery
# ---------------------------------------------------------------------------

@test "registry_init recovers from corrupt peers.json" {
    local path
    path="$(registry_path)"
    echo "NOT VALID JSON{{{" > "$path"
    registry_init
    run jq -r '.version' "$path"
    [ "$output" = "1" ]
}

@test "registry_init backs up corrupt file before reinitializing" {
    local path
    path="$(registry_path)"
    echo "CORRUPT" > "$path"
    registry_init
    local backups
    backups="$(ls "${path}".bak.* 2>/dev/null | wc -l)"
    [ "$backups" -ge 1 ]
}

# ---------------------------------------------------------------------------
# IP pool exhaustion
# ---------------------------------------------------------------------------

@test "registry_next_ip allocates .254 as last valid address" {
    local path
    path="$(registry_path)"
    local tmp="${path}.tmp.$$"
    jq '.ip_pool.next_client_ip = "10.8.0.254"' "$path" > "$tmp"
    mv "$tmp" "$path"
    run registry_next_ip
    [ "$status" -eq 0 ]
    [ "$output" = "10.8.0.254" ]
}

@test "registry_next_ip exhausts pool when every host is reserved or leased" {
    # True exhaustion: the hint is only advisory now, so a high hint alone is
    # not exhaustion. Reserve the entire .1-.254 host range.
    local path reserved
    path="$(registry_path)"
    reserved="$(jq -cn '[range(1;255) | "10.8.0." + (tostring)]')"
    local tmp="${path}.tmp.$$"
    jq --argjson r "$reserved" '.ip_pool.reserved = $r' "$path" > "$tmp"
    mv "$tmp" "$path"
    run registry_next_ip
    [ "$status" -eq 1 ]
    [[ "$output" == *"IP pool exhausted"* ]]
}

@test "registry_next_ip treats a high next_client_ip hint as advisory, not exhaustion" {
    # A stale .255 hint must NOT block allocation while free addresses remain.
    local path
    path="$(registry_path)"
    local tmp="${path}.tmp.$$"
    jq '.ip_pool.next_client_ip = "10.8.0.255"' "$path" > "$tmp"
    mv "$tmp" "$path"
    run registry_next_ip
    [ "$status" -eq 0 ]
    # First free host above reserved (.1, .2) is .3.
    [ "$output" = "10.8.0.3" ]
}

# ---------------------------------------------------------------------------
# IP collision: must never hand out a reserved or actively-leased address
# ---------------------------------------------------------------------------

@test "registry_next_ip never returns a reserved address" {
    # Default reserved = .1 and .2; first allocation must skip both.
    run registry_next_ip
    [ "$status" -eq 0 ]
    [ "$output" != "10.8.0.1" ]
    [ "$output" != "10.8.0.2" ]
}

@test "registry_next_ip skips an IP already leased to an active peer (stale hint)" {
    # Simulate the collision bug: hint points at .10 but .10 is already leased.
    registry_add_peer "alice" "KEY" "10.8.0.10"
    local path
    path="$(registry_path)"
    local tmp="${path}.tmp.$$"
    jq '.ip_pool.next_client_ip = "10.8.0.10"' "$path" > "$tmp"
    mv "$tmp" "$path"
    run registry_next_ip
    [ "$status" -eq 0 ]
    [ "$output" != "10.8.0.10" ]
    [ "$output" = "10.8.0.11" ]
}

@test "registry_next_ip allocations across many peers are all distinct and unreserved" {
    local ips=""
    local i ip
    for i in $(seq 1 20); do
        ip="$(registry_next_ip)"
        registry_add_peer "peer${i}" "KEY${i}" "$ip"
        # No reserved address handed out.
        [ "$ip" != "10.8.0.1" ]
        [ "$ip" != "10.8.0.2" ]
        # No duplicate handed out.
        [[ "$ips" != *"|${ip}|"* ]]
        ips="${ips}|${ip}|"
    done
}

@test "registry_next_ip reuses an address freed by revocation" {
    # Lease .10, revoke it, then a later allocation may reuse it once freed.
    registry_add_peer "alice" "KEY1" "10.8.0.10"
    registry_remove_peer "alice"
    # .10 is no longer an active lease, so it is allocatable again.
    local path
    path="$(registry_path)"
    local tmp="${path}.tmp.$$"
    jq '.ip_pool.next_client_ip = "10.8.0.10"' "$path" > "$tmp"
    mv "$tmp" "$path"
    run registry_next_ip
    [ "$status" -eq 0 ]
    [ "$output" = "10.8.0.10" ]
}

# ---------------------------------------------------------------------------
# Concurrent-style operations (sequential but testing atomicity)
# ---------------------------------------------------------------------------

@test "rapid sequential adds maintain distinct entries" {
    for i in $(seq 1 10); do
        registry_add_peer "peer${i}" "KEY${i}" "10.8.0.$((9 + i))"
    done
    run registry_peer_count
    [ "$output" = "10" ]
}

@test "rapid sequential add-remove cycles maintain consistency" {
    for i in $(seq 1 5); do
        registry_add_peer "temp${i}" "KEY${i}" "10.8.0.$((9 + i))"
        registry_remove_peer "temp${i}"
    done
    run registry_peer_count
    [ "$output" = "0" ]
    run registry_list_peers --all
    local total
    total="$(echo "$output" | jq 'length')"
    [ "$total" -eq 5 ]
}

# ---------------------------------------------------------------------------
# Duplicate handling
# ---------------------------------------------------------------------------

@test "registry rejects adding peer with same name while active" {
    registry_add_peer "alice" "KEY1" "10.8.0.10"
    run registry_add_peer "alice" "KEY2" "10.8.0.11"
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

@test "registry allows same public key for different peer names" {
    registry_add_peer "alice" "SAMEKEY" "10.8.0.10"
    run registry_add_peer "bob" "SAMEKEY" "10.8.0.11"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Registry with relay not set
# ---------------------------------------------------------------------------

@test "registry_get_relay fails when relay is null" {
    run registry_get_relay
    [ "$status" -eq 1 ]
}

@test "registry operations work without relay set" {
    registry_add_peer "alice" "KEY1" "10.8.0.10"
    run registry_peer_count
    [ "$output" = "1" ]
}

# ---------------------------------------------------------------------------
# Edge case peer names (valid but unusual)
# ---------------------------------------------------------------------------

@test "registry handles maximum length peer name" {
    local long_name
    long_name="$(printf 'a%.0s' {1..200})"
    run registry_add_peer "$long_name" "KEY1" "10.8.0.10"
    [ "$status" -eq 0 ]
    run registry_get_peer "$long_name"
    [ "$status" -eq 0 ]
}

@test "registry handles single character names" {
    registry_add_peer "a" "KEY1" "10.8.0.10"
    registry_add_peer "b" "KEY2" "10.8.0.11"
    run registry_peer_count
    [ "$output" = "2" ]
}

@test "registry handles names with only hyphens and underscores" {
    run registry_add_peer "---" "KEY1" "10.8.0.10"
    [ "$status" -eq 0 ]
    run registry_add_peer "___" "KEY2" "10.8.0.11"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Remove non-existent peer
# ---------------------------------------------------------------------------

@test "registry_remove_peer on already-revoked peer fails" {
    registry_add_peer "alice" "KEY1" "10.8.0.10"
    registry_remove_peer "alice"
    run registry_remove_peer "alice"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No active peer"* ]]
}

# ---------------------------------------------------------------------------
# IP pool state consistency
# ---------------------------------------------------------------------------

@test "registry_next_ip starts at configured value" {
    local path
    path="$(registry_path)"
    run jq -r '.ip_pool.next_client_ip' "$path"
    [ "$output" = "10.8.0.10" ]
}

@test "registry_next_ip increments correctly over many allocations" {
    local ip
    for i in $(seq 10 20); do
        ip="$(registry_next_ip)"
        [ "$ip" = "10.8.0.$i" ]
    done
}

# ---------------------------------------------------------------------------
# peers.json file permissions
# ---------------------------------------------------------------------------

@test "peers.json has 600 permissions after init" {
    local path
    path="$(registry_path)"
    local perms
    perms="$(stat -c '%a' "$path")"
    [ "$perms" = "600" ]
}

@test "peers.json retains valid JSON after many operations" {
    registry_set_relay "1.2.3.4:51820" "RPUB" "10.8.0.1"
    for i in $(seq 1 5); do
        registry_add_peer "p${i}" "K${i}" "10.8.0.$((9 + i))"
    done
    registry_remove_peer "p2"
    registry_remove_peer "p4"
    registry_update_relay_key "NEWKEY"
    local path
    path="$(registry_path)"
    run jq empty "$path"
    [ "$status" -eq 0 ]
}
