#!/usr/bin/env bats
# tests/integration/test_key_rotation_workflow.bats
# Integration tests for key rotation workflows: backup, registry updates, atomicity.

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-rotate-$$-$BATS_TEST_NUMBER"
    source "$LIB_DIR/common.sh"
    source "$LIB_DIR/registry.sh"
    source "$LIB_DIR/audit.sh"
    source "$LIB_DIR/wireguard.sh"
    apply_defaults
    registry_init
    registry_set_relay "1.2.3.4:51820" "ORIGINAL_RELAY_KEY" "10.8.0.1"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Key backup workflow
# ---------------------------------------------------------------------------

@test "key backup: old keys backed up to timestamped directory" {
    set_safe_umask
    # Simulate existing relay keys
    echo "OLD_PRIVATE_KEY" > "$TUNNEL_CONFIG_DIR/relay.key"
    chmod 600 "$TUNNEL_CONFIG_DIR/relay.key"
    echo "ORIGINAL_RELAY_KEY" > "$TUNNEL_CONFIG_DIR/relay.pub"
    chmod 600 "$TUNNEL_CONFIG_DIR/relay.pub"

    # Create backup like tunnel-rotate-keys.sh does
    local backup_dir="${TUNNEL_CONFIG_DIR}/key-backups/$(date +%s)"
    mkdir -p "$backup_dir"
    cp "$TUNNEL_CONFIG_DIR/relay.key" "${backup_dir}/relay.key"
    cp "$TUNNEL_CONFIG_DIR/relay.pub" "${backup_dir}/relay.pub"

    [ -f "${backup_dir}/relay.key" ]
    [ -f "${backup_dir}/relay.pub" ]
    local perms
    perms="$(stat -c '%a' "$backup_dir")"
    [ "$perms" = "700" ]
}

@test "key rotation: registry update preserves endpoint and tunnel IP" {
    registry_update_relay_key "NEW_ROTATED_KEY"
    local relay
    relay="$(registry_get_relay)"
    run jq -r '.endpoint' <<< "$relay"
    [ "$output" = "1.2.3.4:51820" ]
    run jq -r '.tunnel_ip' <<< "$relay"
    [ "$output" = "10.8.0.1" ]
    run jq -r '.public_key' <<< "$relay"
    [ "$output" = "NEW_ROTATED_KEY" ]
}

@test "key rotation: peers unaffected by relay key change" {
    registry_add_peer "alice" "ALICE_PUB" "10.8.0.10"
    registry_add_peer "bob" "BOB_PUB" "10.8.0.11"

    registry_update_relay_key "ROTATED_KEY"

    run registry_peer_count
    [ "$output" = "2" ]
    run registry_get_peer "alice"
    [[ "$output" == *"ALICE_PUB"* ]]
    run registry_get_peer "bob"
    [[ "$output" == *"BOB_PUB"* ]]
}

@test "key rotation: audit trail records rotation" {
    registry_update_relay_key "NEW_KEY"
    audit_log "key_rotate" "success" "Keys rotated" \
        '{"old_key":"ORIGINAL_RELAY_KEY","new_key":"NEW_KEY"}'

    local entries
    entries="$(audit_read 5)"
    run jq -r '.[0].action' <<< "$entries"
    [ "$output" = "key_rotate" ]
    run jq -r '.[0].details.old_key' <<< "$entries"
    [ "$output" = "ORIGINAL_RELAY_KEY" ]
}

# ---------------------------------------------------------------------------
# Registry atomicity (temp file + mv pattern)
# ---------------------------------------------------------------------------

@test "atomicity: registry operations use tmp file pattern" {
    # After an operation, there should be no leftover .tmp files
    registry_add_peer "test" "KEY" "10.8.0.10"
    local tmp_count
    tmp_count="$(find "${TUNNEL_CONFIG_DIR}" -maxdepth 1 -name '*.tmp.*' 2>/dev/null | wc -l)"
    [ "$tmp_count" -eq 0 ]
}

@test "atomicity: peers.json is valid JSON after every operation" {
    registry_add_peer "a" "K1" "10.8.0.10"
    jq empty "$(registry_path)"
    registry_add_peer "b" "K2" "10.8.0.11"
    jq empty "$(registry_path)"
    registry_remove_peer "a"
    jq empty "$(registry_path)"
    registry_update_relay_key "NEWKEY"
    jq empty "$(registry_path)"
    registry_set_relay "5.6.7.8:51820" "OTHERKEY" "10.8.0.1"
    jq empty "$(registry_path)"
}

# ---------------------------------------------------------------------------
# Full rotation simulation with peer re-enrollment
# ---------------------------------------------------------------------------

@test "full rotation: add peers, rotate, verify state, re-enroll" {
    # Phase 1: Add peers
    local ip1 ip2
    ip1="$(registry_next_ip)"
    ip2="$(registry_next_ip)"
    registry_add_peer "alice" "APUB1" "$ip1"
    registry_add_peer "bob" "BPUB1" "$ip2"

    # Phase 2: Rotate relay key
    registry_update_relay_key "ROTATED_RELAY_KEY"
    audit_log "key_rotate" "success" "Rotated" '{"old":"ORIGINAL_RELAY_KEY","new":"ROTATED_RELAY_KEY"}'

    # Phase 3: Verify relay updated
    local relay
    relay="$(registry_get_relay)"
    run jq -r '.public_key' <<< "$relay"
    [ "$output" = "ROTATED_RELAY_KEY" ]

    # Phase 4: Remove old peers (they need new configs)
    registry_remove_peer "alice"
    registry_remove_peer "bob"

    # Phase 5: Re-add with new keys
    local ip3 ip4
    ip3="$(registry_next_ip)"
    ip4="$(registry_next_ip)"
    registry_add_peer "alice" "APUB2" "$ip3"
    registry_add_peer "bob" "BPUB2" "$ip4"

    # Verify final state
    run registry_peer_count
    [ "$output" = "2" ]

    # Verify IPs never reused
    [ "$ip1" != "$ip3" ]
    [ "$ip2" != "$ip4" ]

    # Verify 4 total peer entries (2 revoked + 2 active)
    run registry_list_peers --all
    local total
    total="$(echo "$output" | jq 'length')"
    [ "$total" -eq 4 ]
}

# ---------------------------------------------------------------------------
# Config generation after rotation
# ---------------------------------------------------------------------------

@test "config generation: new client config uses rotated relay key" {
    registry_update_relay_key "NEW_RELAY_PUB"
    local tpl_dir
    tpl_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../templates" && pwd)"
    run wg_render_client_config "$tpl_dir/client.conf.tpl" \
        "CLIENT_PRIVATE_KEY=CLIENTPRIV" \
        "CLIENT_TUNNEL_IP=10.8.0.10" \
        "TUNNEL_DNS_SERVER=10.8.0.2" \
        "RELAY_PUBLIC_KEY=NEW_RELAY_PUB" \
        "PRESHARED_KEY=PSK123" \
        "RELAY_ENDPOINT=1.2.3.4:51820" \
        "TUNNEL_ALLOWED_IPS=10.8.0.0/24"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PublicKey = NEW_RELAY_PUB"* ]]
    [[ "$output" != *"ORIGINAL_RELAY_KEY"* ]]
}
