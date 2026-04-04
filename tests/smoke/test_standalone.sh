#!/usr/bin/env bash
# tests/smoke/test_standalone.sh
# Smoke tests: verify that standalone tunnel toolkit files exist and are valid.
# Does NOT execute tunnel operations (no WireGuard required).

set -euo pipefail

TUNNEL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

PASS=0
FAIL=0
TOTAL=0

check() {
    local desc="$1"
    shift
    TOTAL=$((TOTAL + 1))
    if "$@" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

echo "QP Tunnel Smoke Tests"
echo "====================="

# Check scripts exist
check "tunnel-setup-relay.sh exists"    test -f "$TUNNEL_DIR/tunnel-setup-relay.sh"
check "tunnel-join.sh exists"           test -f "$TUNNEL_DIR/tunnel-join.sh"
check "tunnel-add-peer.sh exists"       test -f "$TUNNEL_DIR/tunnel-add-peer.sh"
check "tunnel-remove-peer.sh exists"    test -f "$TUNNEL_DIR/tunnel-remove-peer.sh"
check "tunnel-status.sh exists"         test -f "$TUNNEL_DIR/tunnel-status.sh"
check "tunnel-rotate-keys.sh exists"    test -f "$TUNNEL_DIR/tunnel-rotate-keys.sh"
check "tunnel-preflight.sh exists"      test -f "$TUNNEL_DIR/tunnel-preflight.sh"
check "tunnel-open.sh exists"          test -f "$TUNNEL_DIR/tunnel-open.sh"
check "tunnel-close.sh exists"         test -f "$TUNNEL_DIR/tunnel-close.sh"
check "tunnel-list.sh exists"          test -f "$TUNNEL_DIR/tunnel-list.sh"

# Check library files exist
check "lib/common.sh exists"     test -f "$TUNNEL_DIR/lib/common.sh"
check "lib/registry.sh exists"   test -f "$TUNNEL_DIR/lib/registry.sh"
check "lib/audit.sh exists"      test -f "$TUNNEL_DIR/lib/audit.sh"
check "lib/wireguard.sh exists"  test -f "$TUNNEL_DIR/lib/wireguard.sh"

# Check library files (new)
check "lib/open.sh exists"      test -f "$TUNNEL_DIR/lib/open.sh"

# Check templates exist
check "client.conf.tpl exists"      test -f "$TUNNEL_DIR/templates/client.conf.tpl"
check "Caddyfile.open.tpl exists"   test -f "$TUNNEL_DIR/templates/Caddyfile.open.tpl"

# Check config/docs
check ".env.tunnel.example exists"  test -f "$TUNNEL_DIR/.env.tunnel.example"
check "README.md exists"         test -f "$TUNNEL_DIR/README.md"
check "LICENSE exists"           test -f "$TUNNEL_DIR/LICENSE"
check "VERSION exists"           test -f "$TUNNEL_DIR/VERSION"
check "Makefile exists"          test -f "$TUNNEL_DIR/Makefile"
check "CRYPTO-NOTICE.md exists"  test -f "$TUNNEL_DIR/docs/CRYPTO-NOTICE.md"
check "GUIDE.md exists"          test -f "$TUNNEL_DIR/docs/GUIDE.md"
check "CONTRIBUTING.md exists"   test -f "$TUNNEL_DIR/CONTRIBUTING.md"
check "SECURITY.md exists"       test -f "$TUNNEL_DIR/SECURITY.md"
check "NOTICE exists"            test -f "$TUNNEL_DIR/NOTICE"
check "PATENTS.md exists"       test -f "$TUNNEL_DIR/PATENTS.md"
check "CODE_OF_CONDUCT.md exists" test -f "$TUNNEL_DIR/CODE_OF_CONDUCT.md"
check "CHANGELOG.md exists"     test -f "$TUNNEL_DIR/CHANGELOG.md"
check ".gitignore exists"       test -f "$TUNNEL_DIR/.gitignore"
check ".editorconfig exists"    test -f "$TUNNEL_DIR/.editorconfig"

# Check GitHub configuration
check ".github/workflows/ci.yaml exists"  test -f "$TUNNEL_DIR/.github/workflows/ci.yaml"
check ".github/CODEOWNERS exists"         test -f "$TUNNEL_DIR/.github/CODEOWNERS"
check ".github/PULL_REQUEST_TEMPLATE.md exists" test -f "$TUNNEL_DIR/.github/PULL_REQUEST_TEMPLATE.md"
check ".github/ISSUE_TEMPLATE/bug_report.md exists" test -f "$TUNNEL_DIR/.github/ISSUE_TEMPLATE/bug_report.md"
check ".github/ISSUE_TEMPLATE/feature_request.md exists" test -f "$TUNNEL_DIR/.github/ISSUE_TEMPLATE/feature_request.md"
check ".github/ISSUE_TEMPLATE/config.yml exists" test -f "$TUNNEL_DIR/.github/ISSUE_TEMPLATE/config.yml"

# Check Makefile has expected targets
check "Makefile: tunnel-setup"      grep -q 'tunnel-setup:' "$TUNNEL_DIR/Makefile"
check "Makefile: tunnel-join"       grep -q 'tunnel-join:' "$TUNNEL_DIR/Makefile"
check "Makefile: tunnel-add-peer"   grep -q 'tunnel-add-peer:' "$TUNNEL_DIR/Makefile"
check "Makefile: tunnel-remove-peer" grep -q 'tunnel-remove-peer:' "$TUNNEL_DIR/Makefile"
check "Makefile: tunnel-status"     grep -q 'tunnel-status:' "$TUNNEL_DIR/Makefile"
check "Makefile: tunnel-rotate-keys" grep -q 'tunnel-rotate-keys:' "$TUNNEL_DIR/Makefile"
check "Makefile: tunnel-open"       grep -q 'tunnel-open:' "$TUNNEL_DIR/Makefile"
check "Makefile: tunnel-close"      grep -q 'tunnel-close:' "$TUNNEL_DIR/Makefile"
check "Makefile: tunnel-list"       grep -q 'tunnel-list:' "$TUNNEL_DIR/Makefile"
check "Makefile: tunnel-verify"     grep -q 'tunnel-verify:' "$TUNNEL_DIR/Makefile"

# Check lib/audit.sh has Capsule integration (required, not optional)
check "audit.sh: ensure_capsule"    grep -q '_ensure_capsule' "$TUNNEL_DIR/lib/audit.sh"
check "audit.sh: pip install"       grep -q 'pip install.*qp-capsule' "$TUNNEL_DIR/lib/audit.sh"
check "audit.sh: capsule_seal"      grep -q '_capsule_seal' "$TUNNEL_DIR/lib/audit.sh"
check "audit.sh: audit_verify"      grep -q 'audit_verify' "$TUNNEL_DIR/lib/audit.sh"

# Check audit.sh calls _capsule_seal from audit_log (critical fix verification)
check "audit.sh: capsule_seal called in audit_log" bash -c 'sed -n "/^audit_log/,/^}/p" '"$TUNNEL_DIR"'/lib/audit.sh | grep -q "_capsule_seal"'

# Check preflight ensures capsule
check "preflight: ensure_capsule"   grep -q '_ensure_capsule' "$TUNNEL_DIR/tunnel-preflight.sh"

# Check TUNNEL_APP_NAME generalization
check "common.sh: TUNNEL_APP_NAME"  grep -q 'TUNNEL_APP_NAME' "$TUNNEL_DIR/lib/common.sh"

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
