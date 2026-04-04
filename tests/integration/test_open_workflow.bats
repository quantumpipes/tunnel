#!/usr/bin/env bats
# tests/integration/test_open_workflow.bats
# Integration tests for the tunnel-open/close/list workflow.
# Tests the full lifecycle without requiring WireGuard or Caddy.

TUNNEL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-open-wf-$$-$BATS_TEST_NUMBER"
    export TUNNEL_APP_NAME="qp-tunnel-test"
    export TUNNEL_SERVER_IP="10.8.0.2"
    export TUNNEL_SUBNET="10.8.0.0/24"
    export TUNNEL_SCRIPT_DIR="$TUNNEL_DIR"

    # Source preflight to get all libs loaded
    # Use a subshell-friendly approach: source common + open directly
    source "$TUNNEL_DIR/lib/common.sh"
    source "$TUNNEL_DIR/lib/open.sh"
    source "$TUNNEL_DIR/lib/audit.sh"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ===========================================================================
# Full Lifecycle: CA -> Cert -> Registry
# ===========================================================================

@test "full lifecycle: generate CA, cert, register, deregister, archive" {
    # Generate CA
    _generate_ca
    [ -f "$TUNNEL_CONFIG_DIR/tls/ca.crt" ]
    [ -f "$TUNNEL_CONFIG_DIR/tls/ca.key" ]

    # Generate service cert
    _generate_service_cert "grafana"
    [ -f "$TUNNEL_CONFIG_DIR/tls/grafana.crt" ]

    # Verify cert is signed by CA
    run openssl verify -CAfile "$TUNNEL_CONFIG_DIR/tls/ca.crt" "$TUNNEL_CONFIG_DIR/tls/grafana.crt"
    [ "$status" -eq 0 ]

    # Register service
    _services_init
    _register_service "grafana" "localhost:3000" 8443 99999
    run _get_service "grafana"
    [ "$status" -eq 0 ]

    # Deregister
    _deregister_service "grafana" >/dev/null
    run _get_service "grafana"
    [ "$status" -eq 1 ]

    # Archive certs
    _archive_service_certs "grafana"
    [ ! -f "$TUNNEL_CONFIG_DIR/tls/grafana.crt" ]
    [ -f "$TUNNEL_CONFIG_DIR/tls/ca.crt" ]
}

# ===========================================================================
# Multi-Service Registration
# ===========================================================================

@test "multiple services can be registered simultaneously" {
    _services_init
    _register_service "grafana" "localhost:3000" 8443 10001
    _register_service "jenkins" "localhost:8080" 8444 10002
    _register_service "hub" "localhost:8090" 8445 10003

    run _list_services
    local count
    count="$(echo "$output" | jq 'length')"
    [ "$count" -eq 3 ]
}

@test "closing one service does not affect others" {
    _services_init
    _register_service "grafana" "localhost:3000" 8443 10001
    _register_service "jenkins" "localhost:8080" 8444 10002

    _deregister_service "grafana" >/dev/null

    run _get_service "jenkins"
    [ "$status" -eq 0 ]
    run _get_service "grafana"
    [ "$status" -eq 1 ]
}

@test "port pool allocates sequential ports across services" {
    _services_init
    local p1 p2 p3
    p1="$(_next_port)"
    p2="$(_next_port)"
    p3="$(_next_port)"

    [ "$p1" = "8443" ]
    [ "$p2" = "8444" ]
    [ "$p3" = "8445" ]
}

# ===========================================================================
# Multi-Service Certificate Generation
# ===========================================================================

@test "multiple services share one CA" {
    _generate_ca
    local ca_serial
    ca_serial="$(openssl x509 -in "$TUNNEL_CONFIG_DIR/tls/ca.crt" -serial -noout)"

    _generate_service_cert "grafana"
    _generate_service_cert "jenkins"

    # CA unchanged
    local ca_serial_after
    ca_serial_after="$(openssl x509 -in "$TUNNEL_CONFIG_DIR/tls/ca.crt" -serial -noout)"
    [ "$ca_serial" = "$ca_serial_after" ]

    # Both certs verify against same CA
    run openssl verify -CAfile "$TUNNEL_CONFIG_DIR/tls/ca.crt" "$TUNNEL_CONFIG_DIR/tls/grafana.crt"
    [ "$status" -eq 0 ]
    run openssl verify -CAfile "$TUNNEL_CONFIG_DIR/tls/ca.crt" "$TUNNEL_CONFIG_DIR/tls/jenkins.crt"
    [ "$status" -eq 0 ]
}

@test "each service gets unique certificate" {
    _generate_ca
    _generate_service_cert "grafana"
    _generate_service_cert "jenkins"

    local grafana_serial
    grafana_serial="$(openssl x509 -in "$TUNNEL_CONFIG_DIR/tls/grafana.crt" -serial -noout)"
    local jenkins_serial
    jenkins_serial="$(openssl x509 -in "$TUNNEL_CONFIG_DIR/tls/jenkins.crt" -serial -noout)"
    [ "$grafana_serial" != "$jenkins_serial" ]
}

# ===========================================================================
# Caddyfile Rendering for Multiple Services
# ===========================================================================

@test "each service gets its own Caddyfile" {
    _generate_ca
    _generate_service_cert "grafana"
    _generate_service_cert "jenkins"
    _render_caddyfile "grafana" "localhost:3000" "8443"
    _render_caddyfile "jenkins" "localhost:8080" "8444"

    [ -f "$TUNNEL_CONFIG_DIR/services/grafana/Caddyfile" ]
    [ -f "$TUNNEL_CONFIG_DIR/services/jenkins/Caddyfile" ]

    grep -q "localhost:3000" "$TUNNEL_CONFIG_DIR/services/grafana/Caddyfile"
    grep -q "localhost:8080" "$TUNNEL_CONFIG_DIR/services/jenkins/Caddyfile"
    grep -q "8443" "$TUNNEL_CONFIG_DIR/services/grafana/Caddyfile"
    grep -q "8444" "$TUNNEL_CONFIG_DIR/services/jenkins/Caddyfile"
}

# ===========================================================================
# Re-open After Close
# ===========================================================================

@test "service can be re-opened after closing" {
    _services_init
    _generate_ca
    _generate_service_cert "grafana"

    # Open
    _register_service "grafana" "localhost:3000" 8443 10001
    run _get_service "grafana"
    [ "$status" -eq 0 ]

    # Close
    _deregister_service "grafana" >/dev/null
    _archive_service_certs "grafana"

    # Re-open (new cert, new registration)
    _generate_service_cert "grafana"
    _register_service "grafana" "localhost:3000" 8443 10002
    run _get_service "grafana"
    [ "$status" -eq 0 ]
    [[ "$output" == *"10002"* ]]
}

# ===========================================================================
# Registry Resilience
# ===========================================================================

@test "services.json handles corrupt file gracefully" {
    local path
    _services_init
    path="$(_services_path)"
    echo "not json" > "$path"

    # Re-init should recover
    _services_init
    jq empty "$path"
}

@test "services.json backup created on corruption" {
    _services_init
    local path
    path="$(_services_path)"
    echo "not json" > "$path"
    _services_init

    # Should have a backup
    local backup_count
    backup_count="$(ls "${path}.bak."* 2>/dev/null | wc -l)"
    [ "$backup_count" -ge 1 ]
}

# ===========================================================================
# Audit Integration
# ===========================================================================

@test "audit_log writes JSONL after capsule seal fix" {
    # Verify audit_log still writes to audit.log
    audit_log "service_open" "success" "Opened grafana" '{"name":"grafana","port":8443}'
    [ -f "$TUNNEL_CONFIG_DIR/audit.log" ]
    local line
    line="$(cat "$TUNNEL_CONFIG_DIR/audit.log")"
    run jq -r '.action' <<< "$line"
    [ "$output" = "service_open" ]
    run jq -r '.details.name' <<< "$line"
    [ "$output" = "grafana" ]
}
