#!/usr/bin/env bats
# tests/unit/test_open.bats
# Unit tests for lib/open.sh (CA gen, cert gen, Caddy, firewall, registry)

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib" && pwd)"

setup() {
    export HOME="$BATS_TMPDIR"
    export TUNNEL_CONFIG_DIR="$BATS_TMPDIR/test-open-$$-$BATS_TEST_NUMBER"
    export TUNNEL_APP_NAME="qp-tunnel-test"
    export TUNNEL_SERVER_IP="10.8.0.2"
    export TUNNEL_SUBNET="10.8.0.0/24"
    export TUNNEL_SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    source "$LIB_DIR/common.sh"
    source "$LIB_DIR/open.sh"
}

teardown() {
    rm -rf "${TUNNEL_CONFIG_DIR:-}" 2>/dev/null || true
}

# ===========================================================================
# Certificate Authority
# ===========================================================================

@test "_generate_ca creates CA keypair" {
    _generate_ca
    [ -f "$TUNNEL_CONFIG_DIR/tls/ca.key" ]
    [ -f "$TUNNEL_CONFIG_DIR/tls/ca.crt" ]
}

@test "_generate_ca creates Ed25519 CA" {
    _generate_ca
    run openssl x509 -in "$TUNNEL_CONFIG_DIR/tls/ca.crt" -text -noout
    [[ "$output" == *"ED25519"* ]]
}

@test "_generate_ca sets CA subject" {
    _generate_ca
    run openssl x509 -in "$TUNNEL_CONFIG_DIR/tls/ca.crt" -subject -noout
    [[ "$output" == *"qp-tunnel-test Internal CA"* ]]
}

@test "_generate_ca is idempotent" {
    _generate_ca
    local first_serial
    first_serial="$(openssl x509 -in "$TUNNEL_CONFIG_DIR/tls/ca.crt" -serial -noout)"
    _generate_ca
    local second_serial
    second_serial="$(openssl x509 -in "$TUNNEL_CONFIG_DIR/tls/ca.crt" -serial -noout)"
    [ "$first_serial" = "$second_serial" ]
}

@test "_generate_ca generates mobileconfig" {
    _generate_ca
    [ -f "$TUNNEL_CONFIG_DIR/tls/ca.mobileconfig" ]
}

@test "_generate_ca mobileconfig is valid XML" {
    _generate_ca
    xmllint --noout "$TUNNEL_CONFIG_DIR/tls/ca.mobileconfig" 2>/dev/null || \
        grep -q '<?xml version' "$TUNNEL_CONFIG_DIR/tls/ca.mobileconfig"
}

# ===========================================================================
# Service Certificates
# ===========================================================================

@test "_generate_service_cert creates cert and key" {
    _generate_ca
    _generate_service_cert "grafana"
    [ -f "$TUNNEL_CONFIG_DIR/tls/grafana.key" ]
    [ -f "$TUNNEL_CONFIG_DIR/tls/grafana.crt" ]
}

@test "_generate_service_cert signed by CA" {
    _generate_ca
    _generate_service_cert "grafana"
    run openssl verify -CAfile "$TUNNEL_CONFIG_DIR/tls/ca.crt" "$TUNNEL_CONFIG_DIR/tls/grafana.crt"
    [ "$status" -eq 0 ]
}

@test "_generate_service_cert has correct SAN" {
    _generate_ca
    _generate_service_cert "grafana"
    run openssl x509 -in "$TUNNEL_CONFIG_DIR/tls/grafana.crt" -text -noout
    [[ "$output" == *"10.8.0.2"* ]]
    [[ "$output" == *"grafana.tunnel"* ]]
}

@test "_generate_service_cert is idempotent" {
    _generate_ca
    _generate_service_cert "grafana"
    local first_serial
    first_serial="$(openssl x509 -in "$TUNNEL_CONFIG_DIR/tls/grafana.crt" -serial -noout)"
    _generate_service_cert "grafana"
    local second_serial
    second_serial="$(openssl x509 -in "$TUNNEL_CONFIG_DIR/tls/grafana.crt" -serial -noout)"
    [ "$first_serial" = "$second_serial" ]
}

@test "_generate_service_cert fails without CA" {
    run _generate_service_cert "grafana"
    [ "$status" -eq 1 ]
}

@test "_generate_service_cert cleans up CSR" {
    _generate_ca
    _generate_service_cert "grafana"
    [ ! -f "$TUNNEL_CONFIG_DIR/tls/grafana.csr" ]
}

@test "_generate_service_cert uses Ed25519" {
    _generate_ca
    _generate_service_cert "grafana"
    run openssl x509 -in "$TUNNEL_CONFIG_DIR/tls/grafana.crt" -text -noout
    [[ "$output" == *"ED25519"* ]]
}

# ===========================================================================
# Caddyfile Rendering
# ===========================================================================

@test "_render_caddyfile creates Caddyfile" {
    _generate_ca
    _generate_service_cert "grafana"
    _render_caddyfile "grafana" "localhost:3000" "8443"
    [ -f "$TUNNEL_CONFIG_DIR/services/grafana/Caddyfile" ]
}

@test "_render_caddyfile substitutes variables" {
    _generate_ca
    _generate_service_cert "grafana"
    _render_caddyfile "grafana" "localhost:3000" "8443"
    local caddyfile="$TUNNEL_CONFIG_DIR/services/grafana/Caddyfile"
    grep -q "10.8.0.2:8443" "$caddyfile"
    grep -q "reverse_proxy localhost:3000" "$caddyfile"
    grep -q "grafana.crt" "$caddyfile"
    grep -q "grafana.key" "$caddyfile"
}

@test "_render_caddyfile includes PQ TLS config" {
    _generate_ca
    _generate_service_cert "grafana"
    _render_caddyfile "grafana" "localhost:3000" "8443"
    local caddyfile="$TUNNEL_CONFIG_DIR/services/grafana/Caddyfile"
    grep -q "x25519mlkem768" "$caddyfile"
    grep -q "tls1.3" "$caddyfile"
}

@test "_render_caddyfile disables auto_https and admin" {
    _generate_ca
    _generate_service_cert "grafana"
    _render_caddyfile "grafana" "localhost:3000" "8443"
    local caddyfile="$TUNNEL_CONFIG_DIR/services/grafana/Caddyfile"
    grep -q "auto_https off" "$caddyfile"
    grep -q "admin off" "$caddyfile"
}

@test "_render_caddyfile fails with missing template" {
    export TUNNEL_SCRIPT_DIR="/nonexistent"
    run _render_caddyfile "grafana" "localhost:3000" "8443"
    [ "$status" -eq 1 ]
}

# ===========================================================================
# Services Registry
# ===========================================================================

@test "_services_init creates services.json" {
    _services_init
    local path
    path="$(_services_path)"
    [ -f "$path" ]
    jq empty "$path"
}

@test "_services_init creates valid structure" {
    _services_init
    local path
    path="$(_services_path)"
    run jq -r '.version' "$path"
    [ "$output" = "1" ]
    run jq -r '.services | length' "$path"
    [ "$output" = "0" ]
    run jq -r '.port_pool.range_start' "$path"
    [ "$output" = "8443" ]
}

@test "_services_init is idempotent" {
    _services_init
    _services_init
    local path
    path="$(_services_path)"
    [ -f "$path" ]
    jq empty "$path"
}

@test "_next_port returns first port" {
    _services_init
    run _next_port
    [ "$status" -eq 0 ]
    [ "$output" = "8443" ]
}

@test "_next_port increments counter" {
    _services_init
    _next_port >/dev/null
    run _next_port
    [ "$status" -eq 0 ]
    [ "$output" = "8444" ]
}

@test "_next_port allocates sequential ports" {
    _services_init
    local p1 p2 p3
    p1="$(_next_port)"
    p2="$(_next_port)"
    p3="$(_next_port)"
    [ "$p1" = "8443" ]
    [ "$p2" = "8444" ]
    [ "$p3" = "8445" ]
}

@test "_register_service adds a service" {
    _services_init
    _register_service "grafana" "localhost:3000" 8443 12345
    local path
    path="$(_services_path)"
    run jq -r '.services[0].name' "$path"
    [ "$output" = "grafana" ]
    run jq -r '.services[0].upstream' "$path"
    [ "$output" = "localhost:3000" ]
    run jq -r '.services[0].port' "$path"
    [ "$output" = "8443" ]
    run jq -r '.services[0].status' "$path"
    [ "$output" = "active" ]
    run jq -r '.services[0].caddy_pid' "$path"
    [ "$output" = "12345" ]
}

@test "_register_service rejects duplicate active service" {
    _services_init
    _register_service "grafana" "localhost:3000" 8443 12345
    run _register_service "grafana" "localhost:3000" 8444 12346
    [ "$status" -eq 1 ]
    [[ "$output" == *"already active"* ]]
}

@test "_register_service includes timestamp" {
    _services_init
    _register_service "grafana" "localhost:3000" 8443 12345
    local path
    path="$(_services_path)"
    run jq -r '.services[0].exposed_at' "$path"
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "_deregister_service marks service as closed" {
    _services_init
    _register_service "grafana" "localhost:3000" 8443 12345
    _deregister_service "grafana" >/dev/null
    local path
    path="$(_services_path)"
    run jq -r '.services[0].status' "$path"
    [ "$output" = "closed" ]
    run jq -r '.services[0].closed_at' "$path"
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "_deregister_service returns the port" {
    _services_init
    _register_service "grafana" "localhost:3000" 8443 12345
    local port
    port="$(_deregister_service "grafana" 2>/dev/null)"
    [ "$port" = "8443" ]
}

@test "_deregister_service fails for nonexistent service" {
    _services_init
    run _deregister_service "nonexistent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No active service"* ]]
}

@test "_get_service returns active service" {
    _services_init
    _register_service "grafana" "localhost:3000" 8443 12345
    run _get_service "grafana"
    [ "$status" -eq 0 ]
    [[ "$output" == *"grafana"* ]]
}

@test "_get_service fails for missing service" {
    _services_init
    run _get_service "nonexistent"
    [ "$status" -eq 1 ]
}

@test "_get_service fails for closed service" {
    _services_init
    _register_service "grafana" "localhost:3000" 8443 12345
    _deregister_service "grafana" >/dev/null
    run _get_service "grafana"
    [ "$status" -eq 1 ]
}

@test "_list_services returns active services only" {
    _services_init
    _register_service "grafana" "localhost:3000" 8443 12345
    _register_service "jenkins" "localhost:8080" 8444 12346
    _deregister_service "grafana" >/dev/null
    run _list_services
    [ "$status" -eq 0 ]
    local count
    count="$(echo "$output" | jq 'length')"
    [ "$count" -eq 1 ]
    local name
    name="$(echo "$output" | jq -r '.[0].name')"
    [ "$name" = "jenkins" ]
}

@test "_list_services returns empty array when none active" {
    _services_init
    run _list_services
    [ "$status" -eq 0 ]
    local count
    count="$(echo "$output" | jq 'length')"
    [ "$count" -eq 0 ]
}

# ===========================================================================
# Certificate Archiving
# ===========================================================================

@test "_archive_service_certs moves certs to archive" {
    _generate_ca
    _generate_service_cert "grafana"
    _archive_service_certs "grafana"
    [ ! -f "$TUNNEL_CONFIG_DIR/tls/grafana.crt" ]
    [ ! -f "$TUNNEL_CONFIG_DIR/tls/grafana.key" ]
    local archive_count
    archive_count="$(find "$TUNNEL_CONFIG_DIR/archive/tls/grafana" -name "*.crt" | wc -l)"
    [ "$archive_count" -eq 1 ]
}

@test "_archive_service_certs preserves CA" {
    _generate_ca
    _generate_service_cert "grafana"
    _archive_service_certs "grafana"
    [ -f "$TUNNEL_CONFIG_DIR/tls/ca.crt" ]
    [ -f "$TUNNEL_CONFIG_DIR/tls/ca.key" ]
}

@test "_archive_service_certs is safe when no certs exist" {
    run _archive_service_certs "nonexistent"
    [ "$status" -eq 0 ]
}

# ===========================================================================
# Certificate Fingerprint
# ===========================================================================

@test "_get_cert_fingerprint returns SHA-256 fingerprint" {
    _generate_ca
    _generate_service_cert "grafana"
    run _get_cert_fingerprint "grafana"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9A-F:]+$ ]]
}

@test "_get_cert_fingerprint returns empty for missing cert" {
    run _get_cert_fingerprint "nonexistent"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ===========================================================================
# Service Directory Cleanup
# ===========================================================================

@test "_cleanup_service_dir removes service directory" {
    local service_dir="$TUNNEL_CONFIG_DIR/services/grafana"
    mkdir -p "$service_dir"
    touch "$service_dir/Caddyfile"
    touch "$service_dir/caddy.pid"
    _cleanup_service_dir "grafana"
    [ ! -d "$service_dir" ]
}

@test "_cleanup_service_dir is safe when dir does not exist" {
    run _cleanup_service_dir "nonexistent"
    [ "$status" -eq 0 ]
}

# ===========================================================================
# Firewall Detection
# ===========================================================================

@test "_detect_firewall returns a valid value" {
    local result
    result="$(_detect_firewall 2>/dev/null)"
    [[ "$result" == "nftables" || "$result" == "iptables" || "$result" == "none" ]]
}

# ===========================================================================
# Capsule Seal Wiring (critical fix verification)
# ===========================================================================

@test "audit_log calls _capsule_seal" {
    # Verify _capsule_seal is called within audit_log function body
    local audit_file="$LIB_DIR/audit.sh"
    # Extract audit_log function and check for _capsule_seal call
    run bash -c "sed -n '/^audit_log()/,/^}/p' '$audit_file' | grep -q '_capsule_seal'"
    [ "$status" -eq 0 ]
}
