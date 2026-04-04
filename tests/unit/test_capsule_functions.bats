#!/usr/bin/env bats
# tests/unit/test_capsule_functions.bats
# Unit tests for _ensure_capsule, _capsule_seal, and audit_verify in lib/audit.sh.

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-capsule-$$-$BATS_TEST_NUMBER"

    # Create mock bin directory
    export MOCK_BIN="$BATS_TMPDIR/mock-cap-bin-$$-$BATS_TEST_NUMBER"
    mkdir -p "$MOCK_BIN"

    source "$LIB_DIR/audit.sh"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
    rm -rf "${MOCK_BIN:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# _ensure_capsule
# ---------------------------------------------------------------------------

@test "_ensure_capsule returns 0 when qp-capsule is on PATH" {
    cat > "$MOCK_BIN/qp-capsule" <<'MOCK'
#!/bin/bash
echo "mock capsule"
MOCK
    chmod +x "$MOCK_BIN/qp-capsule"
    export PATH="$MOCK_BIN:$PATH"

    run _ensure_capsule
    [ "$status" -eq 0 ]
}

@test "_ensure_capsule returns 1 when qp-capsule not found and no pip" {
    # Create a restricted PATH with only essential commands (no qp-capsule, pip, pip3)
    local restricted="$BATS_TMPDIR/restricted-bin-$$-$BATS_TEST_NUMBER"
    mkdir -p "$restricted"
    ln -sf "$(command -v bash)" "$restricted/bash"
    ln -sf "$(command -v printf)" "$restricted/printf"
    ln -sf "$(command -v command)" "$restricted/command" 2>/dev/null || true

    # Run in a subshell with restricted PATH
    run bash -c "
        export PATH='$restricted'
        source '$LIB_DIR/audit.sh' 2>/dev/null
        _ensure_capsule
    "
    [ "$status" -ne 0 ]
    rm -rf "$restricted"
}

@test "_ensure_capsule tries pip3 first" {
    # Create a pip3 that logs it was called
    cat > "$MOCK_BIN/pip3" <<MOCK
#!/bin/bash
echo "pip3 called with: \$*" > "$MOCK_BIN/pip3.log"
exit 1
MOCK
    chmod +x "$MOCK_BIN/pip3"
    export PATH="$MOCK_BIN:$PATH"

    run _ensure_capsule
    # Should have tried pip3
    [ -f "$MOCK_BIN/pip3.log" ]
    grep -q "qp-capsule" "$MOCK_BIN/pip3.log"
}

# ---------------------------------------------------------------------------
# _capsule_seal
# ---------------------------------------------------------------------------

@test "_capsule_seal returns 0 with empty input" {
    run _capsule_seal ""
    [ "$status" -eq 0 ]
}

@test "_capsule_seal returns 0 when qp-capsule not available" {
    # Without qp-capsule on PATH, _capsule_seal should silently succeed
    # Use a subshell with a restricted PATH
    local restricted="$BATS_TMPDIR/restricted-seal-$$-$BATS_TEST_NUMBER"
    mkdir -p "$restricted"
    for cmd in bash printf mkdir chmod date jq whoami stat cat; do
        local real_cmd
        real_cmd="$(command -v "$cmd" 2>/dev/null || true)"
        if [[ -n "$real_cmd" ]]; then
            ln -sf "$real_cmd" "$restricted/$cmd"
        fi
    done

    run bash -c "
        export PATH='$restricted'
        export TUNNEL_CONFIG_DIR='$TUNNEL_CONFIG_DIR'
        source '$LIB_DIR/audit.sh' 2>/dev/null || true
        source '$LIB_DIR/common.sh'
        _capsule_seal '{\"test\":\"data\"}'
    "
    [ "$status" -eq 0 ]
    rm -rf "$restricted"
}

@test "_capsule_seal calls qp-capsule seal when available" {
    cat > "$MOCK_BIN/qp-capsule" <<MOCK
#!/bin/bash
echo "seal called" > "$MOCK_BIN/seal.log"
cat > /dev/null
MOCK
    chmod +x "$MOCK_BIN/qp-capsule"
    export PATH="$MOCK_BIN:$PATH"
    ensure_config_dir >/dev/null

    run _capsule_seal '{"action":"test"}'
    [ "$status" -eq 0 ]
    [ -f "$MOCK_BIN/seal.log" ]
}

# ---------------------------------------------------------------------------
# audit_verify
# ---------------------------------------------------------------------------

@test "audit_verify fails when qp-capsule not installed" {
    # Create a PATH without qp-capsule but with essential commands
    local restricted="$BATS_TMPDIR/restricted-verify-$$-$BATS_TEST_NUMBER"
    mkdir -p "$restricted"
    for cmd in bash printf mkdir chmod date jq whoami stat cat; do
        local real_cmd
        real_cmd="$(command -v "$cmd" 2>/dev/null || true)"
        if [[ -n "$real_cmd" ]]; then
            ln -sf "$real_cmd" "$restricted/$cmd"
        fi
    done

    run bash -c "
        export PATH='$restricted'
        export TUNNEL_CONFIG_DIR='$TUNNEL_CONFIG_DIR'
        source '$LIB_DIR/common.sh'
        source '$LIB_DIR/audit.sh' 2>/dev/null || true
        audit_verify
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"not installed"* ]]
    rm -rf "$restricted"
}

@test "audit_verify fails when no capsules.db exists" {
    cat > "$MOCK_BIN/qp-capsule" <<'MOCK'
#!/bin/bash
echo "verify mock"
exit 0
MOCK
    chmod +x "$MOCK_BIN/qp-capsule"
    export PATH="$MOCK_BIN:$PATH"
    ensure_config_dir >/dev/null

    run audit_verify
    [ "$status" -eq 1 ]
    [[ "$output" == *"No capsules database"* ]]
}

@test "audit_verify calls qp-capsule verify when db exists" {
    cat > "$MOCK_BIN/qp-capsule" <<MOCK
#!/bin/bash
echo "verify called with: \$*" > "$MOCK_BIN/verify.log"
echo "All capsules verified"
exit 0
MOCK
    chmod +x "$MOCK_BIN/qp-capsule"
    export PATH="$MOCK_BIN:$PATH"

    local config_dir
    config_dir="$(ensure_config_dir)"
    touch "${config_dir}/capsules.db"

    run audit_verify
    [ "$status" -eq 0 ]
    [ -f "$MOCK_BIN/verify.log" ]
    grep -q "verify" "$MOCK_BIN/verify.log"
}
