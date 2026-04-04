#!/usr/bin/env bats
# tests/unit/test_audit.bats
# Unit tests for lib/audit.sh

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-tunnel-audit-$$-$BATS_TEST_NUMBER"
    source "$LIB_DIR/audit.sh"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# audit_log
# ---------------------------------------------------------------------------

@test "audit_log creates audit.log file" {
    audit_log "test_action" "success" "test message"
    [ -f "$TUNNEL_CONFIG_DIR/audit.log" ]
}

@test "audit_log writes valid JSON" {
    audit_log "test_action" "success" "test message"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    echo "$line" | jq empty
}

@test "audit_log includes all fields" {
    audit_log "peer_add" "success" "Added peer alice" '{"peer":"alice"}'
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.action' <<< "$line"
    [ "$output" = "peer_add" ]
    run jq -r '.status' <<< "$line"
    [ "$output" = "success" ]
    run jq -r '.message' <<< "$line"
    [ "$output" = "Added peer alice" ]
    run jq -r '.details.peer' <<< "$line"
    [ "$output" = "alice" ]
}

@test "audit_log includes timestamp" {
    audit_log "test" "success" "msg"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.timestamp' <<< "$line"
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "audit_log includes user" {
    audit_log "test" "success" "msg"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.user' <<< "$line"
    [ -n "$output" ]
    [ "$output" != "null" ]
}

@test "audit_log appends multiple entries" {
    audit_log "action1" "success" "first"
    audit_log "action2" "failure" "second"
    local count
    count="$(wc -l < "$TUNNEL_CONFIG_DIR/audit.log")"
    [ "$count" -eq 2 ]
}

@test "audit_log masks DO_API_TOKEN in message" {
    export DO_API_TOKEN="dop_v1_supersecrettoken1234"
    audit_log "setup" "success" "Using token dop_v1_supersecrettoken1234 for setup"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.message' <<< "$line"
    [[ "$output" != *"supersecret"* ]]
    [[ "$output" == *"****"* ]]
    unset DO_API_TOKEN
}

@test "audit_log handles invalid details JSON gracefully" {
    audit_log "test" "success" "msg" "not-json"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.details' <<< "$line"
    [ "$output" = "{}" ]
}

@test "audit_log handles empty details" {
    audit_log "test" "success" "msg"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.details' <<< "$line"
    [ "$output" = "{}" ]
}

# ---------------------------------------------------------------------------
# audit_read
# ---------------------------------------------------------------------------

@test "audit_read returns empty array when no log exists" {
    run audit_read
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "audit_read returns last N entries" {
    audit_log "a1" "success" "first"
    audit_log "a2" "success" "second"
    audit_log "a3" "success" "third"
    run audit_read 2
    [ "$status" -eq 0 ]
    local count
    count="$(echo "$output" | jq 'length')"
    [ "$count" -eq 2 ]
    local last_action
    last_action="$(echo "$output" | jq -r '.[1].action')"
    [ "$last_action" = "a3" ]
}

# ---------------------------------------------------------------------------
# audit_trap_handler
# ---------------------------------------------------------------------------

@test "audit_trap_handler logs failure" {
    audit_trap_handler "test_script"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.action' <<< "$line"
    [ "$output" = "test_script_error" ]
    run jq -r '.status' <<< "$line"
    [ "$output" = "failure" ]
}
