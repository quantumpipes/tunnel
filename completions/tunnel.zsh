#compdef tunnel-setup-relay.sh tunnel-join.sh tunnel-add-peer.sh tunnel-remove-peer.sh tunnel-rotate-keys.sh tunnel-status.sh tunnel-open.sh tunnel-close.sh tunnel-list.sh
# Zsh completion for QP Tunnel scripts.
# Copy this file to a directory in your $fpath (e.g., ~/.zsh/completions/_tunnel)
# and run: autoload -Uz compinit && compinit
#
# Copyright 2026 Quantum Pipes Technologies, LLC
# SPDX-License-Identifier: Apache-2.0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_tunnel_config_dir() {
    local dir="${TUNNEL_CONFIG_DIR:-}"
    if [[ -z "$dir" ]]; then
        local app="${TUNNEL_APP_NAME:-qp-tunnel}"
        dir="$HOME/.config/${app}"
    fi
    echo "$dir"
}

# Return active peer names from peers.json.
_tunnel_peer_names() {
    local config_dir="$(_tunnel_config_dir)"
    local peers_file="${config_dir}/peers.json"
    if [[ -f "$peers_file" ]] && (( $+commands[jq] )); then
        jq -r '.[] | select(.status == "active") | .name' "$peers_file" 2>/dev/null
    fi
}

# Return service names from services.json.
_tunnel_service_names() {
    local config_dir="$(_tunnel_config_dir)"
    local services_file="${config_dir}/services.json"
    if [[ -f "$services_file" ]] && (( $+commands[jq] )); then
        jq -r '.[].name' "$services_file" 2>/dev/null
    fi
}

# ---------------------------------------------------------------------------
# tunnel-setup-relay.sh
# ---------------------------------------------------------------------------
_tunnel-setup-relay.sh() {
    _arguments -s \
        '--provider=[Provisioning mode]:provider:(digitalocean ssh local script)' \
        '--host=[Server IP or hostname]:host:_hosts' \
        '--user=[SSH user]:user:_users' \
        '--generate-script[Output setup script to stdout]' \
        '(-h --help)'{-h,--help}'[Show help]'
}

# ---------------------------------------------------------------------------
# tunnel-join.sh
# ---------------------------------------------------------------------------
_tunnel-join.sh() {
    _arguments -s \
        '1:relay endpoint (host\:port):' \
        '2:relay public key:'
}

# ---------------------------------------------------------------------------
# tunnel-add-peer.sh
# ---------------------------------------------------------------------------
_tunnel-add-peer.sh() {
    _arguments -s \
        '1:peer name:'
}

# ---------------------------------------------------------------------------
# tunnel-remove-peer.sh
# ---------------------------------------------------------------------------
_tunnel-remove-peer.sh() {
    local peers
    peers=("${(@f)$(_tunnel_peer_names)}")
    _arguments -s \
        "1:peer name:(${peers[*]})"
}

# ---------------------------------------------------------------------------
# tunnel-rotate-keys.sh
# ---------------------------------------------------------------------------
_tunnel-rotate-keys.sh() {
    # No arguments. Controlled by CONFIRM=1 env var.
    _message 'no arguments (set CONFIRM=1 to execute)'
}

# ---------------------------------------------------------------------------
# tunnel-status.sh
# ---------------------------------------------------------------------------
_tunnel-status.sh() {
    _message 'no arguments'
}

# ---------------------------------------------------------------------------
# tunnel-open.sh
# ---------------------------------------------------------------------------
_tunnel-open.sh() {
    _arguments -s \
        '--name[Service name]:name:' \
        '--to[Upstream address (host\:port)]:upstream:' \
        '--port[TLS listen port (1024-65535)]:port:' \
        '(-h --help)'{-h,--help}'[Show help]'
}

# ---------------------------------------------------------------------------
# tunnel-close.sh
# ---------------------------------------------------------------------------
_tunnel-close.sh() {
    local services
    services=("${(@f)$(_tunnel_service_names)}")
    _arguments -s \
        "--name[Service name to close]:name:(${services[*]})" \
        '(-h --help)'{-h,--help}'[Show help]'
}

# ---------------------------------------------------------------------------
# tunnel-list.sh
# ---------------------------------------------------------------------------
_tunnel-list.sh() {
    _message 'no arguments'
}

# ---------------------------------------------------------------------------
# make (tunnel targets)
# ---------------------------------------------------------------------------
# This function can be chained into an existing make completion.
# Usage: add _tunnel_make_targets to your make completion or call it directly.
_tunnel_make_targets() {
    local targets=(
        'tunnel-setup:Set up relay (auto-detects provider from env)'
        'tunnel-setup-local:Set up relay on this machine'
        'tunnel-setup-ssh:Set up relay via SSH (RELAY_HOST=x.x.x.x)'
        'tunnel-setup-do:Provision DigitalOcean relay (requires DO_API_TOKEN)'
        'tunnel-generate-script:Output relay setup script for manual use'
        'tunnel-join:Join an existing relay'
        'tunnel-add-peer:Add a peer (NAME=alice)'
        'tunnel-remove-peer:Revoke a peer (NAME=alice)'
        'tunnel-status:Show all peers with handshake times'
        'tunnel-rotate-keys:Rotate relay keys (dry-run by default)'
        'tunnel-open:Open a local service with PQ TLS'
        'tunnel-close:Close an opened service'
        'tunnel-list:List all open services'
        'tunnel-verify:Verify Capsule audit chain integrity'
        'test:Run all tests'
        'test-unit:Run unit tests only'
        'test-integration:Run integration tests only'
        'test-smoke:Run smoke tests'
        'help:Show help'
    )
    _describe 'make target' targets
}
