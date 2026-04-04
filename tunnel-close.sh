#!/usr/bin/env bash
# tunnel-close.sh
# Stop exposing a service over the tunnel.
#
# Usage:
#   tunnel-close --name grafana
#
# Stops the Caddy process, removes firewall rules, archives certificates,
# and deregisters the service.
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
Usage: tunnel-close --name <name>

Arguments:
  --name    Service name to close
  -h|--help Show this help

Examples:
  tunnel-close --name grafana
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
SERVICE_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)   SERVICE_NAME="${2:?--name requires a value}"; shift 2 ;;
        -h|--help) usage ;;
        *) log_error "Unknown argument: $1"; usage ;;
    esac
done

if [[ -z "$SERVICE_NAME" ]]; then
    log_error "--name is required"
    usage
fi

validate_peer_name "$SERVICE_NAME" || exit 1

# ---------------------------------------------------------------------------
# Validate service exists
# ---------------------------------------------------------------------------
if ! _get_service "$SERVICE_NAME" >/dev/null 2>&1; then
    log_error "No active service named '${SERVICE_NAME}'"
    log_info "Run tunnel-list to see active services"
    exit 1
fi

service_json="$(_get_service "$SERVICE_NAME")"
PORT="$(echo "$service_json" | jq -r '.port')"

log_info "Closing '${SERVICE_NAME}' (port ${PORT})..."

# ---------------------------------------------------------------------------
# Execute: stop Caddy, remove firewall, deregister, archive
# ---------------------------------------------------------------------------

# 1. Stop Caddy process
_stop_caddy "$SERVICE_NAME"

# 2. Remove firewall rules
_remove_firewall_rules "$SERVICE_NAME" "$PORT"

# 3. Deregister from services.json
_deregister_service "$SERVICE_NAME" >/dev/null

# 4. Archive certificates (never delete)
_archive_service_certs "$SERVICE_NAME"

# 5. Clean up runtime directory
_cleanup_service_dir "$SERVICE_NAME"

# ---------------------------------------------------------------------------
# Audit
# ---------------------------------------------------------------------------
audit_log "service_close" "success" "Closed ${SERVICE_NAME} (port ${PORT})" \
    "$(jq -cn --arg name "$SERVICE_NAME" --argjson port "$PORT" \
        '{"name":$name,"port":$port}')"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "  ${SERVICE_NAME} closed"
echo "========================================"
echo ""
echo "  Port ${PORT} released"
echo "  Certificates archived (not deleted)"
echo ""

log_success "Service '${SERVICE_NAME}' closed"
