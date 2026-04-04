#!/usr/bin/env bash
# Copyright 2026 Quantum Pipes Technologies, LLC
# SPDX-License-Identifier: Apache-2.0
#
# Security tests for tunnel shell scripts.
#
# Validates:
# - Template rendering escapes special characters (no glob expansion)
# - sed replacement escapes special characters (no command injection)
#
# Run: bash repos/tunnel/tests/test_security.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TUNNEL_DIR="$(dirname "$SCRIPT_DIR")"
PASS=0
FAIL=0

pass() { ((PASS++)); echo "  PASS: $1"; }
fail() { ((FAIL++)); echo "  FAIL: $1"; }

# Source the library under test
# shellcheck source=../lib/wireguard.sh
source "$TUNNEL_DIR/lib/common.sh" 2>/dev/null || true
source "$TUNNEL_DIR/lib/wireguard.sh" 2>/dev/null || true

echo "=== Tunnel Security Tests ==="
echo ""

# ---------------------------------------------------------------------------
# Template Rendering: Special Character Safety
# ---------------------------------------------------------------------------
echo "--- Template Rendering ---"

# Create a temp template
TEMPLATE=$(mktemp)
echo 'PrivateKey = ${PRIVATE_KEY}' > "$TEMPLATE"
echo 'Endpoint = ${ENDPOINT}' >> "$TEMPLATE"

# Test 1: Normal values render correctly
result=$(wg_render_client_config "$TEMPLATE" "PRIVATE_KEY=abc123def456" "ENDPOINT=1.2.3.4:51820")
if echo "$result" | grep -q "PrivateKey = abc123def456"; then
    pass "Normal private key renders correctly"
else
    fail "Normal private key not rendered"
fi

# Test 2: Ampersand in value does not trigger sed back-reference
result=$(wg_render_client_config "$TEMPLATE" "PRIVATE_KEY=abc&def" "ENDPOINT=1.2.3.4:51820")
if echo "$result" | grep -q "PrivateKey = abc&def"; then
    pass "Ampersand in value preserved literally"
else
    fail "Ampersand caused sed back-reference expansion"
    echo "    Got: $(echo "$result" | grep PrivateKey)"
fi

# Test 3: Forward slash in value does not break sed delimiter
result=$(wg_render_client_config "$TEMPLATE" "PRIVATE_KEY=abc/def/ghi" "ENDPOINT=1.2.3.4:51820")
if echo "$result" | grep -q "PrivateKey = abc/def/ghi"; then
    pass "Forward slash in value preserved literally"
else
    fail "Forward slash broke sed delimiter"
    echo "    Got: $(echo "$result" | grep PrivateKey)"
fi

# Test 4: Backslash in value does not escape
result=$(wg_render_client_config "$TEMPLATE" 'PRIVATE_KEY=abc\def' "ENDPOINT=1.2.3.4:51820")
if echo "$result" | grep -qF 'abc\def'; then
    pass "Backslash in value preserved literally"
else
    fail "Backslash caused escape sequence"
    echo "    Got: $(echo "$result" | grep PrivateKey)"
fi

# Test 5: Glob characters (* ? [) in value do not expand
result=$(wg_render_client_config "$TEMPLATE" "PRIVATE_KEY=test*?[abc]" "ENDPOINT=1.2.3.4:51820")
if echo "$result" | grep -qF "test*?[abc]"; then
    pass "Glob characters in value not expanded"
else
    fail "Glob characters were expanded by shell"
    echo "    Got: $(echo "$result" | grep PrivateKey)"
fi

# Test 6: Template with no matching vars returns content unchanged
TEMPLATE2=$(mktemp)
echo 'StaticLine = unchanged' > "$TEMPLATE2"
result=$(wg_render_client_config "$TEMPLATE2" "UNRELATED=value")
if echo "$result" | grep -q "StaticLine = unchanged"; then
    pass "Non-matching vars leave content unchanged"
else
    fail "Non-matching vars corrupted content"
fi

rm -f "$TEMPLATE" "$TEMPLATE2"

echo ""

# ---------------------------------------------------------------------------
# sed Replacement Escaping (simulates tunnel-rotate-keys.sh fix)
# ---------------------------------------------------------------------------
echo "--- sed Replacement Escaping ---"

# Test 7: Ampersand in replacement is escaped
CONF=$(mktemp)
echo "PrivateKey = OLDKEY" > "$CONF"
NEW_KEY="abc&def+ghi"
escaped_key=$(printf '%s\n' "$NEW_KEY" | sed -e 's:[\/&]:\\&:g')
sed -i.bak "s|^PrivateKey = .*|PrivateKey = ${escaped_key}|" "$CONF"
if grep -qF "PrivateKey = abc&def+ghi" "$CONF"; then
    pass "sed replacement with ampersand works correctly"
else
    fail "sed replacement with ampersand failed"
    echo "    Got: $(cat "$CONF")"
fi

# Test 8: Forward slash in replacement is escaped
echo "PrivateKey = OLDKEY" > "$CONF"
NEW_KEY="abc/def/ghi"
escaped_key=$(printf '%s\n' "$NEW_KEY" | sed -e 's:[\/&]:\\&:g')
sed -i.bak "s|^PrivateKey = .*|PrivateKey = ${escaped_key}|" "$CONF"
if grep -qF "PrivateKey = abc/def/ghi" "$CONF"; then
    pass "sed replacement with forward slash works correctly"
else
    fail "sed replacement with forward slash failed"
    echo "    Got: $(cat "$CONF")"
fi

# Test 9: Base64-like key (typical WireGuard key format)
echo "PrivateKey = OLDKEY" > "$CONF"
NEW_KEY="YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXo9Cg=="
escaped_key=$(printf '%s\n' "$NEW_KEY" | sed -e 's:[\/&]:\\&:g')
sed -i.bak "s|^PrivateKey = .*|PrivateKey = ${escaped_key}|" "$CONF"
if grep -qF "PrivateKey = $NEW_KEY" "$CONF"; then
    pass "Base64 WireGuard key format works correctly"
else
    fail "Base64 key format failed"
    echo "    Got: $(cat "$CONF")"
fi

rm -f "$CONF" "$CONF.bak"

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
echo "=== Results: $PASS/$TOTAL passed ==="
if [ "$FAIL" -gt 0 ]; then
    echo "SECURITY TESTS FAILED"
    exit 1
else
    echo "All security tests passed."
    exit 0
fi
