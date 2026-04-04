#!/usr/bin/env bats
# tests/unit/test_open_security.bats
# Security-focused tests for tunnel-open features.

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"
SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-open-sec-$$-$BATS_TEST_NUMBER"
    export TUNNEL_APP_NAME="qp-tunnel-test"
    export TUNNEL_SERVER_IP="10.8.0.2"
    export TUNNEL_SCRIPT_DIR="$SCRIPTS_DIR"
    source "$LIB_DIR/common.sh"
    source "$LIB_DIR/open.sh"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ===========================================================================
# No eval in new files
# ===========================================================================

@test "no eval in lib/open.sh" {
    ! grep -q '\beval\b' "$LIB_DIR/open.sh"
}

@test "no eval in tunnel-open.sh" {
    ! grep -q '\beval\b' "$SCRIPTS_DIR/tunnel-open.sh"
}

@test "no eval in tunnel-close.sh" {
    ! grep -q '\beval\b' "$SCRIPTS_DIR/tunnel-close.sh"
}

@test "no eval in tunnel-list.sh" {
    ! grep -q '\beval\b' "$SCRIPTS_DIR/tunnel-list.sh"
}

# ===========================================================================
# set -euo pipefail in new files
# ===========================================================================

@test "set -euo pipefail in lib/open.sh" {
    grep -q 'set -euo pipefail' "$LIB_DIR/open.sh"
}

@test "set -euo pipefail in tunnel-open.sh" {
    grep -q 'set -euo pipefail' "$SCRIPTS_DIR/tunnel-open.sh"
}

@test "set -euo pipefail in tunnel-close.sh" {
    grep -q 'set -euo pipefail' "$SCRIPTS_DIR/tunnel-close.sh"
}

@test "set -euo pipefail in tunnel-list.sh" {
    grep -q 'set -euo pipefail' "$SCRIPTS_DIR/tunnel-list.sh"
}

# ===========================================================================
# Key File Permissions
# ===========================================================================

@test "CA private key has mode 600" {
    _generate_ca
    local perms
    perms="$(stat -c '%a' "$TUNNEL_CONFIG_DIR/tls/ca.key" 2>/dev/null || stat -f '%A' "$TUNNEL_CONFIG_DIR/tls/ca.key")"
    [ "$perms" = "600" ]
}

@test "service private key has mode 600" {
    _generate_ca
    _generate_service_cert "grafana"
    local perms
    perms="$(stat -c '%a' "$TUNNEL_CONFIG_DIR/tls/grafana.key" 2>/dev/null || stat -f '%A' "$TUNNEL_CONFIG_DIR/tls/grafana.key")"
    [ "$perms" = "600" ]
}

# ===========================================================================
# mobileconfig security
# ===========================================================================

@test "mobileconfig does not contain private key" {
    _generate_ca
    [ -f "$TUNNEL_CONFIG_DIR/tls/ca.mobileconfig" ]
    # Read CA private key content
    local ca_key_content
    ca_key_content="$(grep -v '^-' "$TUNNEL_CONFIG_DIR/tls/ca.key" | tr -d '\n')"
    # Ensure the private key is NOT in the mobileconfig
    ! grep -q "$ca_key_content" "$TUNNEL_CONFIG_DIR/tls/ca.mobileconfig"
}

@test "mobileconfig contains PayloadType security root" {
    _generate_ca
    grep -q "com.apple.security.root" "$TUNNEL_CONFIG_DIR/tls/ca.mobileconfig"
}

@test "mobileconfig is removable (PayloadRemovalDisallowed false)" {
    _generate_ca
    grep -q "<false/>" "$TUNNEL_CONFIG_DIR/tls/ca.mobileconfig"
}

# ===========================================================================
# Self-Containment
# ===========================================================================

@test "lib/open.sh has no parent directory references" {
    ! grep -q '\.\.\/' "$LIB_DIR/open.sh"
}

@test "tunnel-open.sh has no parent directory references" {
    ! grep -q '\.\.\/' "$SCRIPTS_DIR/tunnel-open.sh"
}

@test "tunnel-close.sh has no parent directory references" {
    ! grep -q '\.\.\/' "$SCRIPTS_DIR/tunnel-close.sh"
}

@test "tunnel-list.sh has no parent directory references" {
    ! grep -q '\.\.\/' "$SCRIPTS_DIR/tunnel-list.sh"
}

@test "no QP-specific references in lib/open.sh" {
    ! grep -qi 'QUANTUMPIPES\|hub_compose\|CORS_ORIGINS' "$LIB_DIR/open.sh"
}

@test "no QP-specific references in tunnel-open.sh" {
    ! grep -qi 'QUANTUMPIPES\|hub_compose\|CORS_ORIGINS' "$SCRIPTS_DIR/tunnel-open.sh"
}

# ===========================================================================
# Input Validation
# ===========================================================================

@test "tunnel-open rejects empty service name" {
    run bash "$SCRIPTS_DIR/tunnel-open.sh" --name "" --to "localhost:3000"
    [ "$status" -ne 0 ]
}

@test "tunnel-open rejects invalid upstream format" {
    run bash "$SCRIPTS_DIR/tunnel-open.sh" --name "test" --to "not-a-valid-upstream"
    [ "$status" -ne 0 ]
}

@test "tunnel-open rejects port out of range" {
    run bash "$SCRIPTS_DIR/tunnel-open.sh" --name "test" --to "localhost:3000" --port 80
    [ "$status" -ne 0 ]
}

@test "tunnel-open rejects non-numeric port" {
    run bash "$SCRIPTS_DIR/tunnel-open.sh" --name "test" --to "localhost:3000" --port "abc"
    [ "$status" -ne 0 ]
}

@test "tunnel-open rejects service name with special chars" {
    run bash "$SCRIPTS_DIR/tunnel-open.sh" --name '$(whoami)' --to "localhost:3000"
    [ "$status" -ne 0 ]
}

@test "tunnel-open rejects service name with path traversal" {
    run bash "$SCRIPTS_DIR/tunnel-open.sh" --name '../etc/passwd' --to "localhost:3000"
    [ "$status" -ne 0 ]
}

@test "tunnel-open rejects service name with spaces" {
    run bash "$SCRIPTS_DIR/tunnel-open.sh" --name "my service" --to "localhost:3000"
    [ "$status" -ne 0 ]
}

@test "tunnel-close rejects missing --name" {
    run bash "$SCRIPTS_DIR/tunnel-close.sh"
    [ "$status" -ne 0 ]
}

# ===========================================================================
# Caddyfile Security
# ===========================================================================

@test "Caddyfile template enforces TLS 1.3 only" {
    local tpl="$SCRIPTS_DIR/templates/Caddyfile.open.tpl"
    grep -q 'protocols tls1.3 tls1.3' "$tpl"
}

@test "Caddyfile template disables Caddy admin API" {
    local tpl="$SCRIPTS_DIR/templates/Caddyfile.open.tpl"
    grep -q 'admin off' "$tpl"
}

@test "Caddyfile template includes security headers" {
    local tpl="$SCRIPTS_DIR/templates/Caddyfile.open.tpl"
    grep -q 'X-Content-Type-Options nosniff' "$tpl"
    grep -q 'X-Frame-Options DENY' "$tpl"
    grep -q 'Strict-Transport-Security' "$tpl"
}

@test "Caddyfile template strips Server header" {
    local tpl="$SCRIPTS_DIR/templates/Caddyfile.open.tpl"
    grep -q '\-Server' "$tpl"
}

@test "Caddyfile template uses PQ key exchange" {
    local tpl="$SCRIPTS_DIR/templates/Caddyfile.open.tpl"
    grep -q 'x25519mlkem768' "$tpl"
}
