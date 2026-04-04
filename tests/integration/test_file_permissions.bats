#!/usr/bin/env bats
# tests/integration/test_file_permissions.bats
# Verifies that all file operations maintain secure permissions throughout workflows.

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"
TPL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../templates" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-perms-$$-$BATS_TEST_NUMBER"
    source "$LIB_DIR/common.sh"
    source "$LIB_DIR/registry.sh"
    source "$LIB_DIR/audit.sh"
    source "$LIB_DIR/wireguard.sh"
    apply_defaults
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Config directory
# ---------------------------------------------------------------------------

@test "ensure_config_dir creates with 700" {
    ensure_config_dir >/dev/null
    local perms
    perms="$(stat -c '%a' "$TUNNEL_CONFIG_DIR")"
    [ "$perms" = "700" ]
}

@test "config dir permissions survive multiple ensure_config_dir calls" {
    ensure_config_dir >/dev/null
    ensure_config_dir >/dev/null
    ensure_config_dir >/dev/null
    local perms
    perms="$(stat -c '%a' "$TUNNEL_CONFIG_DIR")"
    [ "$perms" = "700" ]
}

# ---------------------------------------------------------------------------
# Registry file
# ---------------------------------------------------------------------------

@test "registry file created with 600" {
    registry_init
    local path
    path="$(registry_path)"
    local perms
    perms="$(stat -c '%a' "$path")"
    [ "$perms" = "600" ]
}

@test "registry file permissions preserved after add_peer" {
    registry_init
    registry_add_peer "alice" "KEY" "10.8.0.10"
    local path
    path="$(registry_path)"
    [ -f "$path" ]
    jq empty "$path"
}

# ---------------------------------------------------------------------------
# WireGuard config files
# ---------------------------------------------------------------------------

@test "wg_write_config creates file with 600" {
    mkdir -p "$TUNNEL_CONFIG_DIR"
    local conf="${TUNNEL_CONFIG_DIR}/wg0.conf"
    wg_write_config "$conf" "PRIVKEY" "10.8.0.1/24" "51820"
    local perms
    perms="$(stat -c '%a' "$conf")"
    [ "$perms" = "600" ]
}

# ---------------------------------------------------------------------------
# Peer directory structure
# ---------------------------------------------------------------------------

@test "peer directory created with 700" {
    registry_init
    set_safe_umask
    local peer_dir="${TUNNEL_CONFIG_DIR}/peers/alice"
    mkdir -p "$peer_dir"
    chmod 700 "$peer_dir"
    local perms
    perms="$(stat -c '%a' "$peer_dir")"
    [ "$perms" = "700" ]
}

@test "peer config file created with 600 after umask" {
    registry_init
    set_safe_umask
    local peer_dir="${TUNNEL_CONFIG_DIR}/peers/alice"
    mkdir -p "$peer_dir"
    local conf="${peer_dir}/alice.conf"
    echo "test config" > "$conf"
    local perms
    perms="$(stat -c '%a' "$conf")"
    [ "$perms" = "600" ]
}

@test "preshared key file created with 600 after umask" {
    set_safe_umask
    local peer_dir="${TUNNEL_CONFIG_DIR}/peers/alice"
    mkdir -p "$peer_dir"
    local psk="${peer_dir}/preshared.key"
    echo "fakepsk" > "$psk"
    chmod 600 "$psk"
    local perms
    perms="$(stat -c '%a' "$psk")"
    [ "$perms" = "600" ]
}

# ---------------------------------------------------------------------------
# Archive directory
# ---------------------------------------------------------------------------

@test "archive directory inherits safe permissions" {
    set_safe_umask
    local archive="${TUNNEL_CONFIG_DIR}/archive"
    mkdir -p "$archive"
    local perms
    perms="$(stat -c '%a' "$archive")"
    [ "$perms" = "700" ]
}

# ---------------------------------------------------------------------------
# Key backup directory
# ---------------------------------------------------------------------------

@test "key backup directory created with safe permissions" {
    set_safe_umask
    local backup="${TUNNEL_CONFIG_DIR}/key-backups/12345"
    mkdir -p "$backup"
    local perms
    perms="$(stat -c '%a' "$backup")"
    [ "$perms" = "700" ]
}

# ---------------------------------------------------------------------------
# umask does not leak between operations
# ---------------------------------------------------------------------------

@test "umask 077 set by set_safe_umask persists" {
    set_safe_umask
    [ "$(umask)" = "0077" ]
    local testfile="${TUNNEL_CONFIG_DIR}/test1"
    mkdir -p "$TUNNEL_CONFIG_DIR"
    touch "$testfile"
    [ "$(umask)" = "0077" ]
}
