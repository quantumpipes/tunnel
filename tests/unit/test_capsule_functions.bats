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

@test "_ensure_capsule returns 1 when qp-capsule not found" {
    # Create a restricted PATH with only essential commands (no qp-capsule, pip, pip3)
    local restricted="$BATS_TMPDIR/restricted-bin-$$-$BATS_TEST_NUMBER"
    mkdir -p "$restricted"
    ln -sf "$(command -v bash)" "$restricted/bash"
    ln -sf "$(command -v printf)" "$restricted/printf"
    ln -sf "$(command -v command)" "$restricted/command" 2>/dev/null || true

    # Run in a subshell with restricted PATH and no vendored capsule.
    run bash -c "
        export PATH='$restricted'
        unset TUNNEL_CAPSULE_BIN
        source '$LIB_DIR/audit.sh' 2>/dev/null
        _ensure_capsule
    "
    [ "$status" -ne 0 ]
    rm -rf "$restricted"
}

@test "_ensure_capsule NEVER runs pip (no auto-install, air-gap safe)" {
    # SECURITY: auto-installing qp-capsule from public PyPI on every run is a
    # dependency-confusion / data-exfiltration vector and breaks air-gap.
    # Plant pip + pip3 that fail loudly if invoked, and no qp-capsule anywhere.
    cat > "$MOCK_BIN/pip3" <<MOCK
#!/bin/bash
echo "pip3 INVOKED with: \$*" > "$MOCK_BIN/pip3.log"
exit 0
MOCK
    cat > "$MOCK_BIN/pip" <<MOCK
#!/bin/bash
echo "pip INVOKED with: \$*" > "$MOCK_BIN/pip.log"
exit 0
MOCK
    chmod +x "$MOCK_BIN/pip3" "$MOCK_BIN/pip"
    export PATH="$MOCK_BIN:$PATH"
    unset TUNNEL_CAPSULE_BIN

    run _ensure_capsule
    # Must report unavailable...
    [ "$status" -ne 0 ]
    # ...and must NOT have shelled out to pip/pip3 at all.
    [ ! -f "$MOCK_BIN/pip3.log" ]
    [ ! -f "$MOCK_BIN/pip.log" ]
}

@test "_capsule_bin resolves TUNNEL_CAPSULE_BIN override" {
    cat > "$MOCK_BIN/qp-capsule" <<'MOCK'
#!/bin/bash
echo "override"
MOCK
    chmod +x "$MOCK_BIN/qp-capsule"
    export TUNNEL_CAPSULE_BIN="$MOCK_BIN/qp-capsule"

    run _capsule_bin
    [ "$status" -eq 0 ]
    [ "$output" = "$MOCK_BIN/qp-capsule" ]
}

# ---------------------------------------------------------------------------
# audit_require_capsule (fail-closed gate for state-changing commands)
# ---------------------------------------------------------------------------

@test "audit_require_capsule succeeds when qp-capsule is available" {
    cat > "$MOCK_BIN/qp-capsule" <<'MOCK'
#!/bin/bash
echo "ok"
MOCK
    chmod +x "$MOCK_BIN/qp-capsule"
    export PATH="$MOCK_BIN:$PATH"

    run audit_require_capsule "peer_add"
    [ "$status" -eq 0 ]
}

@test "audit_require_capsule FAILS CLOSED when qp-capsule is missing" {
    # Point the vendored resolver at an empty dir and clear PATH-based capsule.
    export TUNNEL_CAPSULE_BIN=""
    local empty_path="$BATS_TMPDIR/no-capsule-bin-$$-$BATS_TEST_NUMBER"
    mkdir -p "$empty_path"
    PATH="$empty_path:$PATH" run bash -c "
        unset TUNNEL_CAPSULE_BIN TUNNEL_ALLOW_UNSEALED_AUDIT
        source '$LIB_DIR/audit.sh'
        # Mask any real qp-capsule on PATH for this assertion.
        command() { if [ \"\$2\" = qp-capsule ]; then return 1; fi; builtin command \"\$@\"; }
        audit_require_capsule 'peer_add'
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"Refusing"* ]]
    rm -rf "$empty_path"
}

@test "audit_require_capsule allows explicit override TUNNEL_ALLOW_UNSEALED_AUDIT=1" {
    run bash -c "
        unset TUNNEL_CAPSULE_BIN
        export TUNNEL_ALLOW_UNSEALED_AUDIT=1
        source '$LIB_DIR/audit.sh'
        # Force capsule-absent so the override branch is what we exercise.
        command() { if [ \"\$2\" = qp-capsule ]; then return 1; fi; builtin command \"\$@\"; }
        audit_require_capsule 'peer_add'
    "
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# _capsule_seal
# ---------------------------------------------------------------------------

@test "_capsule_seal returns 0 with empty input" {
    run _capsule_seal ""
    [ "$status" -eq 0 ]
}

@test "_capsule_seal returns 0 when qp-capsule not available" {
    # Without qp-capsule resolvable, _capsule_seal must silently succeed
    # (audit.log still records; sealing is best-effort here).
    run bash -c "
        export TUNNEL_CONFIG_DIR='$TUNNEL_CONFIG_DIR'
        unset TUNNEL_CAPSULE_BIN
        source '$LIB_DIR/audit.sh'
        # Force capsule-absent regardless of host install.
        command() { if [ \"\$2\" = qp-capsule ]; then return 1; fi; builtin command \"\$@\"; }
        _capsule_seal '{\"test\":\"data\"}'
    "
    [ "$status" -eq 0 ]
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
