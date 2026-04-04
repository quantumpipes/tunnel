#!/usr/bin/env bash
# Bash completion for QP Tunnel scripts.
# Source this file or copy it to /etc/bash_completion.d/tunnel
#
# Copyright 2026 Quantum Pipes Technologies, LLC
# SPDX-License-Identifier: Apache-2.0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Resolve the tunnel config directory without sourcing any tunnel scripts.
_tunnel_config_dir() {
    local dir="${TUNNEL_CONFIG_DIR:-}"
    if [[ -z "$dir" ]]; then
        local app="${TUNNEL_APP_NAME:-qp-tunnel}"
        dir="$HOME/.config/${app}"
    fi
    printf '%s' "$dir"
}

# List peer names from peers.json (active only).
_tunnel_peer_names() {
    local config_dir
    config_dir="$(_tunnel_config_dir)"
    local peers_file="${config_dir}/peers.json"
    if [[ -f "$peers_file" ]] && command -v jq &>/dev/null; then
        jq -r '.[] | select(.status == "active") | .name' "$peers_file" 2>/dev/null
    fi
}

# List service names from services.json.
_tunnel_service_names() {
    local config_dir
    config_dir="$(_tunnel_config_dir)"
    local services_file="${config_dir}/services.json"
    if [[ -f "$services_file" ]] && command -v jq &>/dev/null; then
        jq -r '.[].name' "$services_file" 2>/dev/null
    fi
}

# ---------------------------------------------------------------------------
# tunnel-setup-relay.sh
# ---------------------------------------------------------------------------
_tunnel_setup_relay() {
    local cur="${COMP_WORDS[COMP_CWORD]}"

    local opts="--provider= --host= --user= --generate-script --help"

    if [[ "$cur" == --provider=* ]]; then
        local prefix="--provider="
        local providers="digitalocean ssh local script"
        COMPREPLY=()
        local p
        for p in $providers; do
            if [[ "${prefix}${p}" == "${cur}"* ]]; then
                COMPREPLY+=("${prefix}${p}")
            fi
        done
        return
    fi

    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    # Append = for options that take values (no trailing space)
    local i
    for i in "${!COMPREPLY[@]}"; do
        if [[ "${COMPREPLY[$i]}" == *= ]]; then
            compopt -o nospace 2>/dev/null
        fi
    done
}
complete -F _tunnel_setup_relay tunnel-setup-relay.sh

# ---------------------------------------------------------------------------
# tunnel-join.sh
# ---------------------------------------------------------------------------
_tunnel_join() {
    # Positional: <relay-endpoint:port> <relay-public-key>
    # No meaningful completions for these values.
    COMPREPLY=()
}
complete -F _tunnel_join tunnel-join.sh

# ---------------------------------------------------------------------------
# tunnel-add-peer.sh
# ---------------------------------------------------------------------------
_tunnel_add_peer() {
    # Positional: <peer-name> (free-form, no completion)
    COMPREPLY=()
}
complete -F _tunnel_add_peer tunnel-add-peer.sh

# ---------------------------------------------------------------------------
# tunnel-remove-peer.sh
# ---------------------------------------------------------------------------
_tunnel_remove_peer() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if (( COMP_CWORD == 1 )); then
        local names
        names="$(_tunnel_peer_names)"
        COMPREPLY=( $(compgen -W "$names" -- "$cur") )
    fi
}
complete -F _tunnel_remove_peer tunnel-remove-peer.sh

# ---------------------------------------------------------------------------
# tunnel-rotate-keys.sh
# ---------------------------------------------------------------------------
_tunnel_rotate_keys() {
    # No arguments. Controlled by CONFIRM=1 env var.
    COMPREPLY=()
}
complete -F _tunnel_rotate_keys tunnel-rotate-keys.sh

# ---------------------------------------------------------------------------
# tunnel-status.sh
# ---------------------------------------------------------------------------
_tunnel_status() {
    COMPREPLY=()
}
complete -F _tunnel_status tunnel-status.sh

# ---------------------------------------------------------------------------
# tunnel-open.sh (tunnel-open)
# ---------------------------------------------------------------------------
_tunnel_open() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"

    case "$prev" in
        --name)
            # Free-form service name; no completion.
            COMPREPLY=()
            return ;;
        --to)
            # Suggest common patterns.
            COMPREPLY=( $(compgen -W "localhost:" -- "$cur") )
            compopt -o nospace 2>/dev/null
            return ;;
        --port)
            # Numeric port; no completion.
            COMPREPLY=()
            return ;;
    esac

    local opts="--name --to --port --help"
    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
}
complete -F _tunnel_open tunnel-open.sh

# ---------------------------------------------------------------------------
# tunnel-close.sh
# ---------------------------------------------------------------------------
_tunnel_close() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"

    if [[ "$prev" == "--name" ]]; then
        local names
        names="$(_tunnel_service_names)"
        COMPREPLY=( $(compgen -W "$names" -- "$cur") )
        return
    fi

    local opts="--name --help"
    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
}
complete -F _tunnel_close tunnel-close.sh

# ---------------------------------------------------------------------------
# tunnel-list.sh
# ---------------------------------------------------------------------------
_tunnel_list() {
    COMPREPLY=()
}
complete -F _tunnel_list tunnel-list.sh

# ---------------------------------------------------------------------------
# make (tunnel targets)
# ---------------------------------------------------------------------------
_tunnel_make_targets() {
    local targets=(
        tunnel-setup
        tunnel-setup-local
        tunnel-setup-ssh
        tunnel-setup-do
        tunnel-generate-script
        tunnel-join
        tunnel-add-peer
        tunnel-remove-peer
        tunnel-status
        tunnel-rotate-keys
        tunnel-open
        tunnel-close
        tunnel-list
        tunnel-verify
        test
        test-unit
        test-integration
        test-smoke
        help
    )
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=( $(compgen -W "${targets[*]}" -- "$cur") )
}

# Only register make completion if no other make completion is active.
# Users can call _tunnel_make_targets manually or chain it.
if ! complete -p make &>/dev/null; then
    complete -F _tunnel_make_targets make
fi
