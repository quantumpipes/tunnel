#!/usr/bin/env bash
# tunnel-list.sh
# List all services currently exposed over the tunnel.
#
# Usage: tunnel-list
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
# Get active services
# ---------------------------------------------------------------------------
services="$(_list_services)"
count="$(echo "$services" | jq 'length')"

if (( count == 0 )); then
    echo ""
    echo "  No services open."
    echo ""
    echo "  Open one with: tunnel-open --name <name> --to <host:port>"
    echo ""
    exit 0
fi

# ---------------------------------------------------------------------------
# Display table
# ---------------------------------------------------------------------------
server_ip="${TUNNEL_SERVER_IP:-10.8.0.2}"

echo ""
echo "========================================"
echo "  Open Services (${count})"
echo "========================================"
echo ""
printf "  %-16s %-22s %-8s %-10s %s\n" "NAME" "UPSTREAM" "PORT" "STATUS" "URL"
printf "  %-16s %-22s %-8s %-10s %s\n" "----" "--------" "----" "------" "---"

echo "$services" | jq -r '.[] | [.name, .upstream, (.port | tostring), .caddy_pid] | @tsv' | \
while IFS=$'\t' read -r name upstream port pid; do
    # Check if Caddy process is alive
    if kill -0 "$pid" 2>/dev/null; then
        status="running"
    else
        status="down"
    fi
    printf "  %-16s %-22s %-8s %-10s https://%s:%s\n" "$name" "$upstream" "$port" "$status" "$server_ip" "$port"
done

echo ""
