#!/usr/bin/env bats
# tests/unit/test_input_validation.bats
# Exhaustive input validation tests for peer names and environment variables.

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-validation-$$-$BATS_TEST_NUMBER"
    source "$LIB_DIR/common.sh"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Valid peer names
# ---------------------------------------------------------------------------

@test "validate: simple lowercase" {
    run validate_peer_name "alice"
    [ "$status" -eq 0 ]
}

@test "validate: uppercase" {
    run validate_peer_name "ALICE"
    [ "$status" -eq 0 ]
}

@test "validate: mixed case" {
    run validate_peer_name "AlIcE"
    [ "$status" -eq 0 ]
}

@test "validate: with numbers" {
    run validate_peer_name "alice123"
    [ "$status" -eq 0 ]
}

@test "validate: with hyphens" {
    run validate_peer_name "alice-laptop"
    [ "$status" -eq 0 ]
}

@test "validate: with underscores" {
    run validate_peer_name "alice_laptop"
    [ "$status" -eq 0 ]
}

@test "validate: single character" {
    run validate_peer_name "a"
    [ "$status" -eq 0 ]
}

@test "validate: numbers only" {
    run validate_peer_name "123"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Invalid peer names
# ---------------------------------------------------------------------------

@test "reject: empty string" {
    run validate_peer_name ""
    [ "$status" -eq 1 ]
}

@test "reject: spaces" {
    run validate_peer_name "has space"
    [ "$status" -eq 1 ]
}

@test "reject: dots" {
    run validate_peer_name "has.dot"
    [ "$status" -eq 1 ]
}

@test "reject: forward slash" {
    run validate_peer_name "a/b"
    [ "$status" -eq 1 ]
}

@test "reject: backslash" {
    run validate_peer_name 'a\b'
    [ "$status" -eq 1 ]
}

@test "reject: path traversal" {
    run validate_peer_name "../../etc/passwd"
    [ "$status" -eq 1 ]
}

@test "reject: semicolon (command injection)" {
    run validate_peer_name "alice;rm -rf /"
    [ "$status" -eq 1 ]
}

@test "reject: pipe (command injection)" {
    run validate_peer_name "alice|cat /etc/shadow"
    [ "$status" -eq 1 ]
}

@test "reject: backtick (command substitution)" {
    run validate_peer_name 'alice`whoami`'
    [ "$status" -eq 1 ]
}

@test "reject: dollar sign (variable expansion)" {
    run validate_peer_name 'alice$HOME'
    [ "$status" -eq 1 ]
}

@test "reject: newline" {
    run validate_peer_name $'alice\nmalicious'
    [ "$status" -eq 1 ]
}

@test "reject: tab" {
    run validate_peer_name $'alice\tmalicious'
    [ "$status" -eq 1 ]
}

@test "reject: at sign" {
    run validate_peer_name "alice@host"
    [ "$status" -eq 1 ]
}

@test "reject: hash" {
    run validate_peer_name "alice#1"
    [ "$status" -eq 1 ]
}

@test "reject: ampersand" {
    run validate_peer_name "alice&bob"
    [ "$status" -eq 1 ]
}

@test "reject: parentheses" {
    run validate_peer_name "alice(1)"
    [ "$status" -eq 1 ]
}

@test "reject: quotes" {
    run validate_peer_name "alice'quote"
    [ "$status" -eq 1 ]
}

@test "reject: double quotes" {
    run validate_peer_name 'alice"quote'
    [ "$status" -eq 1 ]
}

@test "reject: angle brackets" {
    run validate_peer_name "alice<script>"
    [ "$status" -eq 1 ]
}

@test "reject: curly braces" {
    run validate_peer_name "alice{0}"
    [ "$status" -eq 1 ]
}

@test "reject: unicode" {
    run validate_peer_name "alice😀"
    [ "$status" -eq 1 ]
}
