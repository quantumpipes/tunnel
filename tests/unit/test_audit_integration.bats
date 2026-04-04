#!/usr/bin/env bats
# tests/unit/test_audit_integration.bats
# Tests for audit_log, audit_read, and audit_trap_handler edge cases.

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-audit-int-$$-$BATS_TEST_NUMBER"
    source "$LIB_DIR/audit.sh"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# audit_log: invalid JSON details fallback
# ---------------------------------------------------------------------------

@test "audit_log falls back to empty object for invalid JSON details" {
    audit_log "test" "success" "msg" "NOT_VALID_JSON"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.details' <<< "$line"
    [ "$output" = "{}" ]
}

@test "audit_log accepts valid nested JSON details" {
    audit_log "test" "success" "msg" '{"key":"val","nested":{"a":1}}'
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.details.key' <<< "$line"
    [ "$output" = "val" ]
    run jq -r '.details.nested.a' <<< "$line"
    [ "$output" = "1" ]
}

@test "audit_log defaults to empty object when no details provided" {
    audit_log "test" "success" "msg"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.details' <<< "$line"
    [ "$output" = "{}" ]
}

# ---------------------------------------------------------------------------
# audit_read: edge cases
# ---------------------------------------------------------------------------

@test "audit_read returns empty array when no log file exists" {
    run audit_read 10
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "audit_read default count is 10" {
    for i in $(seq 1 15); do
        audit_log "action_${i}" "success" "Message ${i}"
    done
    local entries
    entries="$(audit_read)"
    local count
    count="$(echo "$entries" | jq 'length')"
    [ "$count" -eq 10 ]
}

@test "audit_read returns entries in order" {
    audit_log "first" "success" "msg1"
    audit_log "second" "success" "msg2"
    audit_log "third" "success" "msg3"
    local entries
    entries="$(audit_read 3)"
    run jq -r '.[0].action' <<< "$entries"
    [ "$output" = "first" ]
    run jq -r '.[2].action' <<< "$entries"
    [ "$output" = "third" ]
}

# ---------------------------------------------------------------------------
# audit_trap_handler
# ---------------------------------------------------------------------------

@test "audit_trap_handler logs failure with script name" {
    audit_trap_handler "tunnel-add-peer"
    local line
    line="$(tail -1 "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.action' <<< "$line"
    [ "$output" = "tunnel-add-peer_error" ]
    run jq -r '.status' <<< "$line"
    [ "$output" = "failure" ]
}

@test "audit_trap_handler includes line number in message" {
    audit_trap_handler "test-script"
    local line
    line="$(tail -1 "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.message' <<< "$line"
    [[ "$output" == *"ERR trap fired at line"* ]]
}

@test "audit_trap_handler includes script name in details" {
    audit_trap_handler "my-script"
    local line
    line="$(tail -1 "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.details.script' <<< "$line"
    [ "$output" = "my-script" ]
}

@test "audit_trap_handler defaults script name to unknown" {
    audit_trap_handler
    local line
    line="$(tail -1 "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.details.script' <<< "$line"
    [ "$output" = "unknown" ]
}

# ---------------------------------------------------------------------------
# audit_log: field completeness
# ---------------------------------------------------------------------------

@test "audit_log entry contains all required fields" {
    audit_log "peer_add" "success" "Added peer"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r 'keys | sort | join(",")' <<< "$line"
    [[ "$output" == *"action"* ]]
    [[ "$output" == *"details"* ]]
    [[ "$output" == *"message"* ]]
    [[ "$output" == *"status"* ]]
    [[ "$output" == *"timestamp"* ]]
    [[ "$output" == *"user"* ]]
}

@test "audit_log timestamp is ISO 8601 UTC" {
    audit_log "test" "success" "msg"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.timestamp' <<< "$line"
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "audit_log user field is non-empty" {
    audit_log "test" "success" "msg"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.user' <<< "$line"
    [ -n "$output" ]
    [ "$output" != "null" ]
}

# ---------------------------------------------------------------------------
# audit_log: config dir auto-creation
# ---------------------------------------------------------------------------

@test "audit_log creates config dir if it does not exist" {
    rm -rf "$TUNNEL_CONFIG_DIR"
    audit_log "test" "success" "msg"
    [ -d "$TUNNEL_CONFIG_DIR" ]
    [ -f "$TUNNEL_CONFIG_DIR/audit.log" ]
}

# ---------------------------------------------------------------------------
# Token masking in audit entries
# ---------------------------------------------------------------------------

@test "audit_log masks DO_API_TOKEN in message field only" {
    export DO_API_TOKEN="dop_v1_abcdef1234567890"
    audit_log "setup" "success" "Token is dop_v1_abcdef1234567890" '{"endpoint":"1.2.3.4"}'
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.message' <<< "$line"
    [[ "$output" != *"abcdef"* ]]
    [[ "$output" == *"****"* ]]
    # Details should not be affected
    run jq -r '.details.endpoint' <<< "$line"
    [ "$output" = "1.2.3.4" ]
    unset DO_API_TOKEN
}
