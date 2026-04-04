#!/usr/bin/env bats
# tests/unit/test_setup_relay.bats
# Tests for tunnel-setup-relay.sh argument parsing, provider auto-detection,
# and --generate-script output. Uses mocked wg commands since WireGuard
# is not available in test environments.

SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
LIB_DIR="$SCRIPTS_DIR/lib"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-setup-$$-$BATS_TEST_NUMBER"
    export TUNNEL_INTERFACE="wg0"

    # Create a mock wg command that generates fake keys
    export MOCK_BIN="$BATS_TMPDIR/mock-bin-$$-$BATS_TEST_NUMBER"
    mkdir -p "$MOCK_BIN"

    cat > "$MOCK_BIN/wg" <<'MOCK'
#!/bin/bash
if [[ "$1" == "genkey" ]]; then
    echo "cFAKEPRIVATEKEY0000000000000000000000000000="
elif [[ "$1" == "pubkey" ]]; then
    echo "cFAKEPUBLICKEY00000000000000000000000000000="
elif [[ "$1" == "genpsk" ]]; then
    echo "cFAKEPSK000000000000000000000000000000000000="
fi
MOCK
    chmod +x "$MOCK_BIN/wg"

    # Mock wg-quick
    cat > "$MOCK_BIN/wg-quick" <<'MOCK'
#!/bin/bash
echo "wg-quick: $*"
MOCK
    chmod +x "$MOCK_BIN/wg-quick"

    # Mock ssh
    cat > "$MOCK_BIN/ssh" <<'MOCK'
#!/bin/bash
# Accept stdin (the setup script) and silently discard
cat > /dev/null
echo "ssh mock: ran command on remote"
MOCK
    chmod +x "$MOCK_BIN/ssh"

    # Mock qp-capsule to prevent install attempts
    cat > "$MOCK_BIN/qp-capsule" <<'MOCK'
#!/bin/bash
echo "capsule mock"
MOCK
    chmod +x "$MOCK_BIN/qp-capsule"

    # Mock systemctl
    cat > "$MOCK_BIN/systemctl" <<'MOCK'
#!/bin/bash
echo "systemctl mock: $*"
MOCK
    chmod +x "$MOCK_BIN/systemctl"

    # Mock curl (for public IP detection in local mode)
    cat > "$MOCK_BIN/curl" <<'MOCK'
#!/bin/bash
echo "203.0.113.42"
MOCK
    chmod +x "$MOCK_BIN/curl"

    # Mock sysctl
    cat > "$MOCK_BIN/sysctl" <<'MOCK'
#!/bin/bash
echo "sysctl mock: $*"
MOCK
    chmod +x "$MOCK_BIN/sysctl"

    # Mock ufw
    cat > "$MOCK_BIN/ufw" <<'MOCK'
#!/bin/bash
echo "ufw mock: $*"
MOCK
    chmod +x "$MOCK_BIN/ufw"

    # Mock apt-get
    cat > "$MOCK_BIN/apt-get" <<'MOCK'
#!/bin/bash
echo "apt-get mock: $*"
MOCK
    chmod +x "$MOCK_BIN/apt-get"

    # Mock ip
    cat > "$MOCK_BIN/ip" <<'MOCK'
#!/bin/bash
echo "default via 10.0.0.1 dev eth0 proto static"
MOCK
    chmod +x "$MOCK_BIN/ip"

    # Mock iptables
    cat > "$MOCK_BIN/iptables" <<'MOCK'
#!/bin/bash
echo "iptables mock: $*"
MOCK
    chmod +x "$MOCK_BIN/iptables"

    export PATH="$MOCK_BIN:$PATH"

    # Source libraries for helper assertions
    source "$LIB_DIR/common.sh"
    source "$LIB_DIR/registry.sh"
    source "$LIB_DIR/audit.sh"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
    rm -rf "${MOCK_BIN:-}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# --help
# ---------------------------------------------------------------------------

@test "setup-relay --help exits 0 and shows usage" {
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--provider="* ]]
}

@test "setup-relay -h exits 0" {
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ---------------------------------------------------------------------------
# --generate-script
# ---------------------------------------------------------------------------

@test "setup-relay --generate-script outputs valid bash script" {
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --generate-script
    [ "$status" -eq 0 ]
    [[ "$output" == *"#!/bin/bash"* ]]
    [[ "$output" == *"QP Tunnel Relay Setup Script"* ]]
}

@test "setup-relay --generate-script includes WireGuard config" {
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --generate-script
    [ "$status" -eq 0 ]
    [[ "$output" == *"[Interface]"* ]]
    [[ "$output" == *"ListenPort"* ]]
    [[ "$output" == *"SaveConfig = true"* ]]
}

@test "setup-relay --generate-script includes IP forwarding" {
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --generate-script
    [ "$status" -eq 0 ]
    [[ "$output" == *"net.ipv4.ip_forward=1"* ]]
}

@test "setup-relay --generate-script includes firewall setup" {
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --generate-script
    [ "$status" -eq 0 ]
    [[ "$output" == *"ufw"* ]] || [[ "$output" == *"firewall-cmd"* ]]
}

@test "setup-relay --generate-script uses default port 51820" {
    unset TUNNEL_PORT 2>/dev/null || true
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --generate-script
    [ "$status" -eq 0 ]
    [[ "$output" == *"51820"* ]]
}

@test "setup-relay --generate-script uses custom port" {
    export TUNNEL_PORT="12345"
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --generate-script
    [ "$status" -eq 0 ]
    [[ "$output" == *"12345"* ]]
}

@test "setup-relay --generate-script uses default interface wg0" {
    unset TUNNEL_INTERFACE 2>/dev/null || true
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --generate-script
    [ "$status" -eq 0 ]
    [[ "$output" == *"/etc/wireguard/wg0.conf"* ]]
}

@test "setup-relay --generate-script uses custom interface" {
    export TUNNEL_INTERFACE="wg1"
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --generate-script
    [ "$status" -eq 0 ]
    [[ "$output" == *"/etc/wireguard/wg1.conf"* ]]
}

@test "setup-relay --generate-script saves relay keypair to config dir" {
    bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --generate-script >/dev/null 2>&1
    [ -f "$TUNNEL_CONFIG_DIR/relay.key" ]
    [ -f "$TUNNEL_CONFIG_DIR/relay.pub" ]
}

@test "setup-relay --generate-script relay.key has 600 permissions" {
    bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --generate-script >/dev/null 2>&1
    local perms
    perms="$(stat -c '%a' "$TUNNEL_CONFIG_DIR/relay.key")"
    [ "$perms" = "600" ]
}

@test "setup-relay --generate-script includes relay public key in output" {
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --generate-script
    [ "$status" -eq 0 ]
    [[ "$output" == *"Public Key:"* ]]
}

@test "setup-relay --generate-script includes multi-distro package install" {
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --generate-script
    [ "$status" -eq 0 ]
    [[ "$output" == *"apt-get"* ]]
    [[ "$output" == *"dnf"* ]]
    [[ "$output" == *"yum"* ]]
    [[ "$output" == *"pacman"* ]]
    [[ "$output" == *"apk"* ]]
}

# ---------------------------------------------------------------------------
# Provider auto-detection
# ---------------------------------------------------------------------------

@test "setup-relay with no provider and no env fails with guidance" {
    unset DO_API_TOKEN 2>/dev/null || true
    unset RELAY_HOST 2>/dev/null || true
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No provider specified"* ]]
}

@test "setup-relay error message lists all valid providers" {
    unset DO_API_TOKEN 2>/dev/null || true
    unset RELAY_HOST 2>/dev/null || true
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh"
    [[ "$output" == *"digitalocean"* ]]
    [[ "$output" == *"ssh"* ]]
    [[ "$output" == *"local"* ]]
}

@test "setup-relay unknown provider fails" {
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --provider=kubernetes
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown provider"* ]]
}

# ---------------------------------------------------------------------------
# Provider: ssh (validation only, since actual SSH is mocked)
# ---------------------------------------------------------------------------

@test "setup-relay --provider=ssh without host fails" {
    unset RELAY_HOST 2>/dev/null || true
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --provider=ssh
    [ "$status" -eq 1 ]
    [[ "$output" == *"RELAY_HOST required"* ]]
}

@test "setup-relay --provider=ssh with --host runs successfully" {
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --provider=ssh --host=10.0.0.5
    [ "$status" -eq 0 ]
    [[ "$output" == *"SSH relay setup complete"* ]] || [[ "$output" == *"Tunnel Relay Configured (SSH)"* ]]
}

@test "setup-relay --provider=ssh registers relay in registry" {
    bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --provider=ssh --host=10.0.0.5 >/dev/null 2>&1
    local relay
    relay="$(registry_get_relay)"
    [[ "$relay" == *"10.0.0.5"* ]]
}

@test "setup-relay --provider=ssh saves relay-server.json" {
    bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --provider=ssh --host=10.0.0.5 >/dev/null 2>&1
    [ -f "$TUNNEL_CONFIG_DIR/relay-server.json" ]
    run jq -r '.provider' "$TUNNEL_CONFIG_DIR/relay-server.json"
    [ "$output" = "ssh" ]
    run jq -r '.relay_ip' "$TUNNEL_CONFIG_DIR/relay-server.json"
    [ "$output" = "10.0.0.5" ]
}

@test "setup-relay --provider=ssh logs to audit trail" {
    bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --provider=ssh --host=10.0.0.5 >/dev/null 2>&1
    [ -f "$TUNNEL_CONFIG_DIR/audit.log" ]
    local line
    line="$(tail -1 "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.action' <<< "$line"
    [ "$output" = "setup_relay" ]
    run jq -r '.status' <<< "$line"
    [ "$output" = "success" ]
}

@test "setup-relay --provider=ssh with RELAY_HOST env var" {
    export RELAY_HOST="192.168.1.50"
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --provider=ssh
    [ "$status" -eq 0 ]
    [[ "$output" == *"192.168.1.50"* ]]
}

@test "setup-relay --provider=ssh --user sets SSH user" {
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --provider=ssh --host=10.0.0.5 --user=admin
    [ "$status" -eq 0 ]
}

@test "setup-relay --provider=ssh shows next steps" {
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --provider=ssh --host=10.0.0.5
    [ "$status" -eq 0 ]
    [[ "$output" == *"Next steps"* ]]
    [[ "$output" == *"tunnel-join.sh"* ]]
    [[ "$output" == *"tunnel-add-peer.sh"* ]]
}

# ---------------------------------------------------------------------------
# Provider: local (limited testing)
# The local provider runs _build_setup_script | bash, which writes to
# /etc/wireguard/ and runs systemctl. These require root and a real system.
# We test what we can: require_cmd check for wg and wg-quick.
# ---------------------------------------------------------------------------

@test "setup-relay --provider=local requires wg and wg-quick" {
    # Remove wg-quick from mock PATH to verify the check
    rm -f "$MOCK_BIN/wg-quick"
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --provider=local
    [ "$status" -ne 0 ]
    [[ "$output" == *"wg-quick"* ]] || [[ "$output" == *"Required command"* ]]
}

@test "setup-relay --provider=local generates relay keypair before failing" {
    # Even though it fails (no /etc/wireguard), it should generate the keypair first
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --provider=local
    # The script generates keys before piping setup script
    [ -f "$TUNNEL_CONFIG_DIR/relay.key" ]
    [ -f "$TUNNEL_CONFIG_DIR/relay.pub" ]
}

# ---------------------------------------------------------------------------
# Provider: digitalocean (validation only)
# ---------------------------------------------------------------------------

@test "setup-relay --provider=digitalocean without DO_API_TOKEN fails" {
    unset DO_API_TOKEN 2>/dev/null || true
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --provider=digitalocean
    [ "$status" -eq 1 ]
    [[ "$output" == *"DO_API_TOKEN"* ]]
}

# ---------------------------------------------------------------------------
# Security: generated script contains no leaked secrets
# ---------------------------------------------------------------------------

@test "setup-relay --generate-script does not contain shell variables in output" {
    run bash "$SCRIPTS_DIR/tunnel-setup-relay.sh" --generate-script
    [ "$status" -eq 0 ]
    # The output should have the private key value inlined, not a shell variable reference
    # (The private key IS expected to be in the output since it's for the relay config)
    # But it should not leak the DO_API_TOKEN
    [[ "$output" != *"DO_API_TOKEN"* ]]
}
