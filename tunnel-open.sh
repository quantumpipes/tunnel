#!/usr/bin/env bash
# tunnel-open.sh
# Expose a local web application over the WireGuard tunnel with PQ TLS.
#
# Usage:
#   tunnel-open --name grafana --to localhost:3000
#   tunnel-open --name hub --to localhost:8090 --port 8445
#
# This starts a Caddy reverse proxy with TLS 1.3 + ML-KEM-768 key exchange,
# binds it to the tunnel interface, and installs firewall rules restricting
# access to the tunnel subnet only.
#
# Copyright 2026 Quantum Pipes Technologies, LLC
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/tunnel-preflight.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/open.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: tunnel-open --name <name> --to <host:port> [--port <port>]

Arguments:
  --name    Service name (alphanumeric, hyphen, underscore)
  --to      Upstream address (e.g., localhost:3000)
  --port    TLS listen port (default: auto-assigned from pool 8443-8499)
  -h|--help Show this help

Examples:
  tunnel-open --name grafana --to localhost:3000
  tunnel-open --name hub --to localhost:8090 --port 8445
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
SERVICE_NAME=""
UPSTREAM=""
MANUAL_PORT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)   SERVICE_NAME="${2:?--name requires a value}"; shift 2 ;;
        --to)     UPSTREAM="${2:?--to requires a value}"; shift 2 ;;
        --port)   MANUAL_PORT="${2:?--port requires a value}"; shift 2 ;;
        -h|--help) usage ;;
        *) log_error "Unknown argument: $1"; usage ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
if [[ -z "$SERVICE_NAME" ]]; then
    log_error "--name is required"
    usage
fi
if [[ -z "$UPSTREAM" ]]; then
    log_error "--to is required"
    usage
fi

# Validate service name (reuse peer name validation)
validate_peer_name "$SERVICE_NAME" || exit 1

# Validate upstream format (host:port)
if [[ ! "$UPSTREAM" =~ ^[a-zA-Z0-9._-]+:[0-9]+$ ]]; then
    log_error "Invalid upstream format '${UPSTREAM}'. Expected host:port (e.g., localhost:3000)"
    exit 1
fi

# Validate manual port if provided
if [[ -n "$MANUAL_PORT" ]]; then
    if ! [[ "$MANUAL_PORT" =~ ^[0-9]+$ ]] || (( MANUAL_PORT < 1024 || MANUAL_PORT > 65535 )); then
        log_error "Invalid port '${MANUAL_PORT}'. Must be 1024-65535."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Check if service is already active (idempotent)
# ---------------------------------------------------------------------------
if _get_service "$SERVICE_NAME" >/dev/null 2>&1; then
    existing="$(_get_service "$SERVICE_NAME")"
    existing_port="$(echo "$existing" | jq -r '.port')"
    existing_pid="$(echo "$existing" | jq -r '.caddy_pid')"
    server_ip="${TUNNEL_SERVER_IP:-10.8.0.2}"

    if kill -0 "$existing_pid" 2>/dev/null; then
        log_info "Service '${SERVICE_NAME}' is already open"
        echo ""
        echo "========================================"
        echo "  ${SERVICE_NAME} (already active)"
        echo "========================================"
        echo ""
        echo "  URL:  https://${server_ip}:${existing_port}"
        echo ""
        exit 0
    fi

    # PID dead but registry says active: clean up and re-open
    log_warn "Service '${SERVICE_NAME}' registered but Caddy is not running. Re-opening..."
    _deregister_service "$SERVICE_NAME" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# Determine port
# ---------------------------------------------------------------------------
if [[ -n "$MANUAL_PORT" ]]; then
    PORT="$MANUAL_PORT"
else
    PORT="$(_next_port)"
fi

SERVER_IP="${TUNNEL_SERVER_IP:-10.8.0.2}"

# ---------------------------------------------------------------------------
# Execute: CA, cert, Caddy, firewall, registry
# ---------------------------------------------------------------------------
log_info "Opening '${SERVICE_NAME}' (${UPSTREAM}) on port ${PORT}..."

# 1. Generate CA (idempotent)
_generate_ca

# 2. Generate service certificate (idempotent)
_generate_service_cert "$SERVICE_NAME"

# 3. Render Caddyfile
_render_caddyfile "$SERVICE_NAME" "$UPSTREAM" "$PORT"

# 4. Start Caddy
_start_caddy "$SERVICE_NAME"

# 5. Apply firewall rules
_apply_firewall_rules "$SERVICE_NAME" "$PORT"

# 6. Get PID for registry
config_dir="$(ensure_config_dir)"
CADDY_PID="$(cat "${config_dir}/services/${SERVICE_NAME}/caddy.pid")"

# 7. Register service
_register_service "$SERVICE_NAME" "$UPSTREAM" "$PORT" "$CADDY_PID"

# 8. Get certificate fingerprint
FINGERPRINT="$(_get_cert_fingerprint "$SERVICE_NAME")"

# ---------------------------------------------------------------------------
# Audit
# ---------------------------------------------------------------------------
audit_log "service_open" "success" "Opened ${SERVICE_NAME} at https://${SERVER_IP}:${PORT}" \
    "$(jq -cn --arg name "$SERVICE_NAME" --arg up "$UPSTREAM" \
        --argjson port "$PORT" --arg ip "$SERVER_IP" --arg fp "$FINGERPRINT" \
        '{"name":$name,"upstream":$up,"port":$port,"listen_ip":$ip,"tls_fingerprint":$fp}')"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "  ${SERVICE_NAME} is now accessible"
echo "========================================"
echo ""
echo "  URL:         https://${SERVER_IP}:${PORT}"
echo "  Upstream:    ${UPSTREAM}"
echo "  TLS:         TLS 1.3 + ML-KEM-768 (post-quantum)"
echo "  Fingerprint: ${FINGERPRINT}"
echo "  CA cert:     ${config_dir}/tls/ca.crt"
echo ""
echo "  First time? Install the CA on your device:"
echo "    iOS:     Transfer ca.mobileconfig to device"
echo "    macOS:   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ${config_dir}/tls/ca.crt"
echo "    Linux:   sudo cp ${config_dir}/tls/ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates"
echo ""

log_success "Service '${SERVICE_NAME}' opened at https://${SERVER_IP}:${PORT}"
