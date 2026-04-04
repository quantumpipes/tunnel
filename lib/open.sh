#!/usr/bin/env bash
# lib/open.sh
# Core logic for tunnel-open / tunnel-close commands.
# Manages: internal CA, per-service TLS certs, Caddy PQ TLS processes,
# firewall rules, and the services.json registry.
# Sourced by tunnel-open.sh and tunnel-close.sh. Never executed directly.
#
# Copyright 2026 Quantum Pipes Technologies, LLC
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
OPEN_PORT_RANGE_START="${TUNNEL_PORT_RANGE_START:-8443}"
OPEN_PORT_RANGE_END="${TUNNEL_PORT_RANGE_END:-8499}"
OPEN_CA_VALIDITY_DAYS=3650   # 10 years
OPEN_CERT_VALIDITY_DAYS=365  # 1 year

# ===========================================================================
# Internal Certificate Authority
# ===========================================================================

# ---------------------------------------------------------------------------
# _generate_ca
# Creates a self-signed Ed25519 CA if one does not already exist.
# Outputs: $TUNNEL_CONFIG_DIR/tls/ca.key, ca.crt
# ---------------------------------------------------------------------------
_generate_ca() {
    local config_dir
    config_dir="$(ensure_config_dir)"
    local tls_dir="${config_dir}/tls"
    mkdir -p "$tls_dir"

    if [[ -f "${tls_dir}/ca.crt" && -f "${tls_dir}/ca.key" ]]; then
        # Verify existing CA is still valid
        if openssl x509 -checkend 86400 -noout -in "${tls_dir}/ca.crt" 2>/dev/null; then
            log_info "CA certificate already exists and is valid"
            return 0
        fi
        log_warn "CA certificate is expiring or invalid, regenerating"
    fi

    log_info "Generating internal CA (Ed25519, ${OPEN_CA_VALIDITY_DAYS}-day validity)..."
    set_safe_umask

    # Generate Ed25519 private key
    openssl genpkey -algorithm Ed25519 -out "${tls_dir}/ca.key" 2>/dev/null
    chmod 600 "${tls_dir}/ca.key"

    # Generate self-signed CA certificate
    openssl req -new -x509 \
        -key "${tls_dir}/ca.key" \
        -out "${tls_dir}/ca.crt" \
        -days "$OPEN_CA_VALIDITY_DAYS" \
        -subj "/CN=${TUNNEL_APP_NAME:-qp-tunnel} Internal CA/O=${TUNNEL_APP_NAME:-qp-tunnel}" \
        2>/dev/null

    log_success "CA certificate created at ${tls_dir}/ca.crt"

    # Generate iOS .mobileconfig profile
    _generate_mobileconfig "${tls_dir}"
}

# ---------------------------------------------------------------------------
# _generate_mobileconfig TLS_DIR
# Creates an iOS CA trust profile from the CA public certificate.
# ---------------------------------------------------------------------------
_generate_mobileconfig() {
    local tls_dir="${1:?tls_dir required}"
    local ca_crt="${tls_dir}/ca.crt"
    local profile="${tls_dir}/ca.mobileconfig"
    local app_name="${TUNNEL_APP_NAME:-qp-tunnel}"

    if [[ ! -f "$ca_crt" ]]; then
        log_warn "CA certificate not found, skipping mobileconfig generation"
        return 0
    fi

    # Base64-encode the CA cert (DER format)
    local ca_der_b64
    ca_der_b64="$(openssl x509 -in "$ca_crt" -outform DER 2>/dev/null | base64)"

    local uuid_payload
    uuid_payload="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "00000000-0000-0000-0000-000000000001")"
    local uuid_content
    uuid_content="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "00000000-0000-0000-0000-000000000002")"

    cat > "$profile" <<MOBILECONFIG
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadCertificateFileName</key>
            <string>${app_name}-ca.cer</string>
            <key>PayloadContent</key>
            <data>${ca_der_b64}</data>
            <key>PayloadDescription</key>
            <string>Adds the ${app_name} internal CA for tunnel TLS verification.</string>
            <key>PayloadDisplayName</key>
            <string>${app_name} Internal CA</string>
            <key>PayloadIdentifier</key>
            <string>com.${app_name}.ca</string>
            <key>PayloadType</key>
            <string>com.apple.security.root</string>
            <key>PayloadUUID</key>
            <string>${uuid_content}</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
    </array>
    <key>PayloadDisplayName</key>
    <string>${app_name} Tunnel CA</string>
    <key>PayloadIdentifier</key>
    <string>com.${app_name}.tunnel-ca</string>
    <key>PayloadRemovalDisallowed</key>
    <false/>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>${uuid_payload}</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>
MOBILECONFIG

    log_info "iOS trust profile created at ${profile}"
}

# ---------------------------------------------------------------------------
# _generate_service_cert NAME
# Generates a per-service TLS certificate signed by the internal CA.
# SAN: tunnel server IP + <name>.tunnel
# ---------------------------------------------------------------------------
_generate_service_cert() {
    local name="${1:?service name required}"
    local config_dir
    config_dir="$(ensure_config_dir)"
    local tls_dir="${config_dir}/tls"
    local server_ip="${TUNNEL_SERVER_IP:-10.8.0.2}"

    # Skip if cert exists and is valid
    if [[ -f "${tls_dir}/${name}.crt" && -f "${tls_dir}/${name}.key" ]]; then
        if openssl x509 -checkend 86400 -noout -in "${tls_dir}/${name}.crt" 2>/dev/null; then
            log_info "Certificate for '${name}' already exists and is valid"
            return 0
        fi
        log_warn "Certificate for '${name}' is expiring, regenerating"
    fi

    # Require CA
    if [[ ! -f "${tls_dir}/ca.key" || ! -f "${tls_dir}/ca.crt" ]]; then
        log_error "CA not found. Run _generate_ca first."
        return 1
    fi

    log_info "Generating TLS certificate for '${name}' (Ed25519, ${OPEN_CERT_VALIDITY_DAYS}-day validity)..."
    set_safe_umask

    # Generate service private key
    openssl genpkey -algorithm Ed25519 -out "${tls_dir}/${name}.key" 2>/dev/null
    chmod 600 "${tls_dir}/${name}.key"

    # Create CSR with SAN
    local san_ext="subjectAltName=IP:${server_ip},DNS:${name}.tunnel"

    openssl req -new \
        -key "${tls_dir}/${name}.key" \
        -subj "/CN=${name}.tunnel/O=${TUNNEL_APP_NAME:-qp-tunnel}" \
        -addext "$san_ext" \
        -out "${tls_dir}/${name}.csr" \
        2>/dev/null

    # Sign with CA
    openssl x509 -req \
        -in "${tls_dir}/${name}.csr" \
        -CA "${tls_dir}/ca.crt" \
        -CAkey "${tls_dir}/ca.key" \
        -CAcreateserial \
        -out "${tls_dir}/${name}.crt" \
        -days "$OPEN_CERT_VALIDITY_DAYS" \
        -copy_extensions copyall \
        2>/dev/null

    # Clean up CSR
    rm -f "${tls_dir}/${name}.csr"

    local fingerprint
    fingerprint="$(openssl x509 -fingerprint -sha256 -noout -in "${tls_dir}/${name}.crt" 2>/dev/null | cut -d= -f2)"

    log_success "Certificate for '${name}' created (SHA256: ${fingerprint})"
}

# ===========================================================================
# Caddy Process Management
# ===========================================================================

# ---------------------------------------------------------------------------
# _render_caddyfile NAME UPSTREAM PORT
# Renders a Caddyfile from the template for a given service.
# ---------------------------------------------------------------------------
_render_caddyfile() {
    local name="${1:?service name required}"
    local upstream="${2:?upstream required}"
    local port="${3:?port required}"

    local config_dir
    config_dir="$(ensure_config_dir)"
    local tls_dir="${config_dir}/tls"
    local service_dir="${config_dir}/services/${name}"
    local server_ip="${TUNNEL_SERVER_IP:-10.8.0.2}"

    mkdir -p "$service_dir"

    local template="${TUNNEL_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/templates/Caddyfile.open.tpl"

    if [[ ! -f "$template" ]]; then
        log_error "Caddyfile template not found at ${template}"
        return 1
    fi

    # Substitute template variables
    sed \
        -e "s|\${SERVICE_NAME}|${name}|g" \
        -e "s|\${UPSTREAM}|${upstream}|g" \
        -e "s|\${LISTEN_PORT}|${port}|g" \
        -e "s|\${LISTEN_IP}|${server_ip}|g" \
        -e "s|\${TLS_CERT}|${tls_dir}/${name}.crt|g" \
        -e "s|\${TLS_KEY}|${tls_dir}/${name}.key|g" \
        "$template" > "${service_dir}/Caddyfile"

    log_info "Caddyfile rendered at ${service_dir}/Caddyfile"
}

# ---------------------------------------------------------------------------
# _start_caddy NAME
# Starts Caddy as a background process for the named service.
# Writes PID to services/<name>/caddy.pid.
# ---------------------------------------------------------------------------
_start_caddy() {
    local name="${1:?service name required}"
    local config_dir
    config_dir="$(ensure_config_dir)"
    local service_dir="${config_dir}/services/${name}"
    local caddyfile="${service_dir}/Caddyfile"
    local pidfile="${service_dir}/caddy.pid"

    if [[ ! -f "$caddyfile" ]]; then
        log_error "Caddyfile not found for service '${name}'"
        return 1
    fi

    # Check if already running
    if [[ -f "$pidfile" ]]; then
        local existing_pid
        existing_pid="$(cat "$pidfile")"
        if kill -0 "$existing_pid" 2>/dev/null; then
            log_info "Caddy already running for '${name}' (PID ${existing_pid})"
            return 0
        fi
        rm -f "$pidfile"
    fi

    require_cmd caddy

    # Start Caddy in background
    caddy run --config "$caddyfile" --adapter caddyfile &>/dev/null &
    local pid=$!

    # Brief wait to confirm startup
    sleep 1
    if ! kill -0 "$pid" 2>/dev/null; then
        log_error "Caddy failed to start for '${name}'"
        return 1
    fi

    printf '%s' "$pid" > "$pidfile"
    log_success "Caddy started for '${name}' (PID ${pid})"
}

# ---------------------------------------------------------------------------
# _stop_caddy NAME
# Stops the Caddy process for the named service.
# ---------------------------------------------------------------------------
_stop_caddy() {
    local name="${1:?service name required}"
    local config_dir
    config_dir="$(ensure_config_dir)"
    local pidfile="${config_dir}/services/${name}/caddy.pid"

    if [[ ! -f "$pidfile" ]]; then
        log_warn "No PID file for service '${name}', Caddy may not be running"
        return 0
    fi

    local pid
    pid="$(cat "$pidfile")"

    if kill -0 "$pid" 2>/dev/null; then
        # Graceful shutdown (SIGTERM), then force after 5s
        kill "$pid" 2>/dev/null || true
        local waited=0
        while kill -0 "$pid" 2>/dev/null && (( waited < 5 )); do
            sleep 1
            (( waited++ ))
        done
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
        fi
        log_success "Caddy stopped for '${name}' (PID ${pid})"
    else
        log_info "Caddy process for '${name}' already exited"
    fi

    rm -f "$pidfile"
}

# ===========================================================================
# Firewall Rules
# ===========================================================================

# ---------------------------------------------------------------------------
# _detect_firewall
# Detects whether nftables or iptables is available.
# Outputs: "nftables" or "iptables"
# ---------------------------------------------------------------------------
_detect_firewall() {
    if command -v nft &>/dev/null; then
        printf 'nftables'
    elif command -v iptables &>/dev/null; then
        printf 'iptables'
    else
        log_warn "No firewall tool found (nft or iptables). Skipping firewall rules."
        printf 'none'
    fi
}

# ---------------------------------------------------------------------------
# _apply_firewall_rules NAME PORT
# Installs per-service firewall rules restricting the port to tunnel subnet.
# ---------------------------------------------------------------------------
_apply_firewall_rules() {
    local name="${1:?service name required}"
    local port="${2:?port required}"
    local subnet="${TUNNEL_SUBNET:-10.8.0.0/24}"
    local fw
    fw="$(_detect_firewall)"

    case "$fw" in
        nftables)
            # Create table if needed (idempotent)
            nft add table inet tunnel-open 2>/dev/null || true

            # Delete existing chain for this service (idempotent)
            nft delete chain inet tunnel-open "${name}" 2>/dev/null || true

            # Create chain with rules
            nft add chain inet tunnel-open "${name}" '{ type filter hook input priority 0; }'
            nft add rule inet tunnel-open "${name}" ip saddr "${subnet}" tcp dport "${port}" accept
            nft add rule inet tunnel-open "${name}" tcp dport "${port}" drop
            log_success "Firewall rules applied for '${name}' (nftables, port ${port})"
            ;;
        iptables)
            local chain="TUNNEL-${name^^}"

            # Remove existing chain if present (idempotent)
            iptables -D INPUT -j "${chain}" 2>/dev/null || true
            iptables -F "${chain}" 2>/dev/null || true
            iptables -X "${chain}" 2>/dev/null || true

            # Create chain with rules
            iptables -N "${chain}"
            iptables -A "${chain}" -s "${subnet}" -p tcp --dport "${port}" -j ACCEPT
            iptables -A "${chain}" -p tcp --dport "${port}" -j DROP
            iptables -A INPUT -j "${chain}"
            log_success "Firewall rules applied for '${name}' (iptables, port ${port})"
            ;;
        none)
            log_warn "No firewall rules applied. Port ${port} relies on Caddy bind address for protection."
            ;;
    esac
}

# ---------------------------------------------------------------------------
# _remove_firewall_rules NAME PORT
# Removes per-service firewall rules.
# ---------------------------------------------------------------------------
_remove_firewall_rules() {
    local name="${1:?service name required}"
    local port="${2:?port required}"
    local fw
    fw="$(_detect_firewall)"

    case "$fw" in
        nftables)
            nft delete chain inet tunnel-open "${name}" 2>/dev/null || true
            log_info "Firewall rules removed for '${name}' (nftables)"
            ;;
        iptables)
            local chain="TUNNEL-${name^^}"
            iptables -D INPUT -j "${chain}" 2>/dev/null || true
            iptables -F "${chain}" 2>/dev/null || true
            iptables -X "${chain}" 2>/dev/null || true
            log_info "Firewall rules removed for '${name}' (iptables)"
            ;;
        none)
            ;;
    esac
}

# ===========================================================================
# Services Registry (services.json)
# ===========================================================================

# ---------------------------------------------------------------------------
# _services_path
# Returns the path to services.json.
# ---------------------------------------------------------------------------
_services_path() {
    local dir
    dir="$(ensure_config_dir)"
    printf '%s/services.json' "$dir"
}

# ---------------------------------------------------------------------------
# _services_init
# Creates services.json with empty structure if it does not exist.
# ---------------------------------------------------------------------------
_services_init() {
    local path
    path="$(_services_path)"
    if [[ -f "$path" ]]; then
        if jq empty "$path" 2>/dev/null; then
            return 0
        fi
        log_warn "Corrupt services.json detected, backing up and reinitializing"
        mv "$path" "${path}.bak.$(date +%s)"
    fi
    set_safe_umask
    cat > "$path" <<'SERVICES_JSON'
{
  "version": 1,
  "services": [],
  "port_pool": {
    "range_start": 8443,
    "range_end": 8499,
    "next_port": 8443
  }
}
SERVICES_JSON
    chmod 600 "$path"
}

# ---------------------------------------------------------------------------
# _next_port
# Returns the next available port from the pool.
# ---------------------------------------------------------------------------
_next_port() {
    local path
    path="$(_services_path)"
    _services_init

    local next_port
    next_port="$(jq -r '.port_pool.next_port' "$path")"
    local range_end
    range_end="$(jq -r '.port_pool.range_end' "$path")"

    if (( next_port > range_end )); then
        log_error "Port pool exhausted (${OPEN_PORT_RANGE_START}-${OPEN_PORT_RANGE_END})"
        return 1
    fi

    # Increment for next allocation
    local new_next=$(( next_port + 1 ))
    local tmp="${path}.tmp.$$"
    jq --argjson np "$new_next" '.port_pool.next_port = $np' "$path" > "$tmp"
    mv "$tmp" "$path"

    printf '%s' "$next_port"
}

# ---------------------------------------------------------------------------
# _register_service NAME UPSTREAM PORT PID
# Adds a service to services.json.
# ---------------------------------------------------------------------------
_register_service() {
    local name="${1:?name required}"
    local upstream="${2:?upstream required}"
    local port="${3:?port required}"
    local pid="${4:?pid required}"

    local path
    path="$(_services_path)"
    _services_init

    # Check for duplicate active service
    local existing
    existing="$(jq -r --arg n "$name" '.services[] | select(.name == $n and .status == "active") | .name' "$path")"
    if [[ -n "$existing" ]]; then
        log_error "Service '${name}' is already active"
        return 1
    fi

    local now
    now="$(ts_iso)"

    local config_dir
    config_dir="$(ensure_config_dir)"
    local cert_file="${config_dir}/tls/${name}.crt"
    local cert_expires=""
    if [[ -f "$cert_file" ]]; then
        cert_expires="$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)"
    fi

    local tmp="${path}.tmp.$$"
    jq --arg n "$name" --arg up "$upstream" --argjson p "$port" \
       --argjson pid "$pid" --arg ts "$now" --arg ce "$cert_expires" \
       '.services += [{"name": $n, "upstream": $up, "port": $p, "status": "active", "exposed_at": $ts, "cert_expires": $ce, "caddy_pid": $pid}]' \
       "$path" > "$tmp"
    mv "$tmp" "$path"
    log_info "Service '${name}' registered (port ${port})"
}

# ---------------------------------------------------------------------------
# _deregister_service NAME
# Marks a service as inactive in services.json. Returns the port it was using.
# ---------------------------------------------------------------------------
_deregister_service() {
    local name="${1:?name required}"
    local path
    path="$(_services_path)"

    local existing
    existing="$(jq -r --arg n "$name" '.services[] | select(.name == $n and .status == "active") | .name' "$path")"
    if [[ -z "$existing" ]]; then
        log_error "No active service named '${name}' found"
        return 1
    fi

    # Get the port before deregistering
    local port
    port="$(jq -r --arg n "$name" '.services[] | select(.name == $n and .status == "active") | .port' "$path")"

    local now
    now="$(ts_iso)"
    local tmp="${path}.tmp.$$"
    jq --arg n "$name" --arg ts "$now" \
       '(.services[] | select(.name == $n and .status == "active")) |= (.status = "closed" | .closed_at = $ts)' \
       "$path" > "$tmp"
    mv "$tmp" "$path"

    log_info "Service '${name}' deregistered"
    printf '%s' "$port"
}

# ---------------------------------------------------------------------------
# _get_service NAME
# Outputs the JSON object for an active service, or returns 1.
# ---------------------------------------------------------------------------
_get_service() {
    local name="${1:?name required}"
    local path
    path="$(_services_path)"
    _services_init

    local result
    result="$(jq -r --arg n "$name" '.services[] | select(.name == $n and .status == "active")' "$path")"
    if [[ -z "$result" ]]; then
        return 1
    fi
    printf '%s\n' "$result"
}

# ---------------------------------------------------------------------------
# _list_services
# Outputs JSON array of active services.
# ---------------------------------------------------------------------------
_list_services() {
    local path
    path="$(_services_path)"
    _services_init
    jq '[.services[] | select(.status == "active")]' "$path"
}

# ---------------------------------------------------------------------------
# _archive_service_certs NAME
# Moves service certs to archive directory (never deletes).
# ---------------------------------------------------------------------------
_archive_service_certs() {
    local name="${1:?service name required}"
    local config_dir
    config_dir="$(ensure_config_dir)"
    local tls_dir="${config_dir}/tls"
    local archive_dir
    archive_dir="${config_dir}/archive/tls/${name}/$(date +%s)"

    if [[ -f "${tls_dir}/${name}.crt" || -f "${tls_dir}/${name}.key" ]]; then
        mkdir -p "$archive_dir"
        mv "${tls_dir}/${name}.crt" "$archive_dir/" 2>/dev/null || true
        mv "${tls_dir}/${name}.key" "$archive_dir/" 2>/dev/null || true
        log_info "Certificates for '${name}' archived to ${archive_dir}"
    fi
}

# ---------------------------------------------------------------------------
# _cleanup_service_dir NAME
# Removes per-service runtime directory.
# ---------------------------------------------------------------------------
_cleanup_service_dir() {
    local name="${1:?service name required}"
    local config_dir
    config_dir="$(ensure_config_dir)"
    local service_dir="${config_dir}/services/${name}"

    if [[ -d "$service_dir" ]]; then
        rm -rf "$service_dir"
        log_info "Runtime directory cleaned up for '${name}'"
    fi
}

# ---------------------------------------------------------------------------
# _get_cert_fingerprint NAME
# Outputs the SHA-256 fingerprint of a service certificate.
# ---------------------------------------------------------------------------
_get_cert_fingerprint() {
    local name="${1:?service name required}"
    local config_dir
    config_dir="$(ensure_config_dir)"
    local cert="${config_dir}/tls/${name}.crt"

    if [[ -f "$cert" ]]; then
        openssl x509 -fingerprint -sha256 -noout -in "$cert" 2>/dev/null | cut -d= -f2
    fi
}
