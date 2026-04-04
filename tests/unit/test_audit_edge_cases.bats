#!/usr/bin/env bats
# tests/unit/test_audit_edge_cases.bats
# Edge case and security tests for the audit logging system.

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-audit-edge-$$-$BATS_TEST_NUMBER"
    source "$LIB_DIR/audit.sh"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Special characters in messages
# ---------------------------------------------------------------------------

@test "audit_log handles double quotes in message" {
    audit_log "test" "success" 'He said "hello"'
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.message' <<< "$line"
    [ "$output" = 'He said "hello"' ]
}

@test "audit_log handles single quotes in message" {
    audit_log "test" "success" "It's working"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.message' <<< "$line"
    [ "$output" = "It's working" ]
}

@test "audit_log handles backslashes in message" {
    audit_log "test" "success" 'path: C:\Users\admin'
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.message' <<< "$line"
    [[ "$output" == *"C:"* ]]
}

@test "audit_log handles newlines in message safely" {
    audit_log "test" "success" "line1
line2"
    local line
    line="$(tail -1 "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq empty <<< "$line"
    [ "$status" -eq 0 ]
}

@test "audit_log handles unicode in message" {
    audit_log "test" "success" "User added: cafe"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.message' <<< "$line"
    [[ "$output" == *"cafe"* ]]
}

# ---------------------------------------------------------------------------
# Token masking edge cases
# ---------------------------------------------------------------------------

@test "audit_log masks token appearing multiple times" {
    export DO_API_TOKEN="dop_v1_secret123"
    audit_log "test" "success" "Token dop_v1_secret123 used, confirmed dop_v1_secret123"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.message' <<< "$line"
    [[ "$output" != *"dop_v1_secret"* ]]
    unset DO_API_TOKEN
}

@test "audit_log does not mask when no token set" {
    unset DO_API_TOKEN 2>/dev/null || true
    audit_log "test" "success" "Normal message with no token"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.message' <<< "$line"
    [ "$output" = "Normal message with no token" ]
}

# ---------------------------------------------------------------------------
# Details JSON edge cases
# ---------------------------------------------------------------------------

@test "audit_log handles nested JSON details" {
    audit_log "test" "success" "msg" '{"peer":{"name":"alice","ip":"10.8.0.10"}}'
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.details.peer.name' <<< "$line"
    [ "$output" = "alice" ]
}

@test "audit_log handles array in details" {
    audit_log "test" "success" "msg" '{"peers":["alice","bob"]}'
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.details.peers[1]' <<< "$line"
    [ "$output" = "bob" ]
}

@test "audit_log handles numeric values in details" {
    audit_log "test" "success" "msg" '{"count":42,"ratio":3.14}'
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.details.count' <<< "$line"
    [ "$output" = "42" ]
}

# ---------------------------------------------------------------------------
# Multiple rapid writes
# ---------------------------------------------------------------------------

@test "audit_log handles ten rapid sequential writes" {
    for i in $(seq 1 10); do
        audit_log "action_${i}" "success" "Message ${i}"
    done
    local count
    count="$(wc -l < "$TUNNEL_CONFIG_DIR/audit.log")"
    [ "$count" -eq 10 ]
    while IFS= read -r line; do
        echo "$line" | jq empty
    done < "$TUNNEL_CONFIG_DIR/audit.log"
}

# ---------------------------------------------------------------------------
# audit_read edge cases
# ---------------------------------------------------------------------------

@test "audit_read with count larger than entries returns all" {
    audit_log "a1" "success" "first"
    audit_log "a2" "success" "second"
    run audit_read 100
    [ "$status" -eq 0 ]
    local count
    count="$(echo "$output" | jq 'length')"
    [ "$count" -eq 2 ]
}

@test "audit_read with count of one returns last entry only" {
    audit_log "a1" "success" "first"
    audit_log "a2" "success" "second"
    audit_log "a3" "success" "third"
    run audit_read 1
    [ "$status" -eq 0 ]
    local count
    count="$(echo "$output" | jq 'length')"
    [ "$count" -eq 1 ]
    run jq -r '.[0].action' <<< "$(audit_read 1)"
    [ "$output" = "a3" ]
}

# ---------------------------------------------------------------------------
# Empty and missing message
# ---------------------------------------------------------------------------

@test "audit_log with empty message stores empty string" {
    audit_log "test" "failure" ""
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.message' <<< "$line"
    [ "$output" = "" ]
}

# ---------------------------------------------------------------------------
# Status values
# ---------------------------------------------------------------------------

@test "audit_log accepts arbitrary status strings" {
    audit_log "test" "partial" "half done"
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.status' <<< "$line"
    [ "$output" = "partial" ]
}

# ---------------------------------------------------------------------------
# Audit log file permissions
# ---------------------------------------------------------------------------

@test "audit.log is created in the config directory" {
    audit_log "test" "success" "msg"
    [ -f "$TUNNEL_CONFIG_DIR/audit.log" ]
}

@test "config directory has 700 permissions after audit write" {
    audit_log "test" "success" "msg"
    local perms
    perms="$(stat -c '%a' "$TUNNEL_CONFIG_DIR")"
    [ "$perms" = "700" ]
}
