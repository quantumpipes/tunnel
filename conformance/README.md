# Audit Log Conformance

Golden test vectors for validating QP Tunnel's structured JSONL audit log format.

## Audit Log Format

QP Tunnel writes one JSON object per line to `~/.config/<app-name>/audit.log`. Each line is a self-contained JSON object (JSONL format, not a JSON array).

### Required Fields

Every audit entry must contain these six fields:

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | string | ISO 8601 UTC timestamp (`YYYY-MM-DDTHH:MM:SSZ`) |
| `action` | string | Operation identifier (see valid actions below) |
| `status` | string | `"success"` or `"failure"` |
| `message` | string | Human-readable description of the operation |
| `user` | string | System username that executed the command |
| `details` | object | Structured metadata (action-specific, may be empty `{}`) |

### Valid Actions

| Action | Script | Description |
|--------|--------|-------------|
| `setup_relay` | tunnel-setup-relay.sh | Relay provisioned (local, SSH, or DigitalOcean) |
| `tunnel_join` | tunnel-join.sh | Device joined the relay |
| `peer_add` | tunnel-add-peer.sh | New peer registered and configured |
| `peer_remove` | tunnel-remove-peer.sh | Peer revoked and archived |
| `key_rotate` | tunnel-rotate-keys.sh | Relay keys rotated |
| `service_open` | tunnel-open.sh | Service exposed with PQ TLS |
| `service_close` | tunnel-close.sh | Service stopped and archived |
| `*_error` | Any (ERR trap) | Error trap fired during execution |

### Details by Action

Each action writes specific fields in the `details` object:

**setup_relay** (local/SSH provider):
```json
{"relay_ip": "198.51.100.23", "provider": "local"}
```

**setup_relay** (DigitalOcean provider):
```json
{"droplet_ip": "198.51.100.23", "droplet_id": "412345678", "provider": "digitalocean"}
```

**tunnel_join:**
```json
{"relay_endpoint": "198.51.100.23:51820", "server_ip": "10.8.0.2"}
```

**peer_add:**
```json
{"name": "alice", "tunnel_ip": "10.8.0.10"}
```

**peer_remove:**
```json
{"name": "alice", "tunnel_ip": "10.8.0.10"}
```

**key_rotate:**
```json
{"old_public_key": "abc123...", "new_public_key": "def456..."}
```

**service_open:**
```json
{"name": "grafana", "upstream": "localhost:3000", "port": 8443, "listen_ip": "10.8.0.2", "tls_fingerprint": "SHA256:..."}
```

**service_close:**
```json
{"name": "grafana", "port": 8443}
```

**error trap:**
```json
{"line": "42", "script": "tunnel-add-peer"}
```

## Validation Rules

A conformant audit entry must satisfy all of the following:

1. The entry is valid JSON (parseable by `jq`)
2. All six required fields are present
3. `timestamp` matches the pattern `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$`
4. `action` is a non-empty string
5. `status` is `"success"` or `"failure"`
6. `message` is a string (may be empty)
7. `user` is a non-empty string
8. `details` is a JSON object (not null, not an array, not a scalar)
9. No API tokens appear unmasked in the `message` field
10. The entry occupies exactly one line (no embedded newlines in the serialized JSON)

## Capsule Sealing (Optional)

When `qp-capsule` is installed, each audit entry is also sealed as a tamper-evident Capsule in `capsules.db`. The sealed entry includes:

- SHA3-256 hash of the JSON content
- Ed25519 signature
- Chain linkage to the previous Capsule

The JSONL audit log is the fast local index. The Capsule database is the cryptographic source of truth. Both contain the same entries.

Verify integrity:

```bash
qp-capsule verify --db ~/.config/qp-tunnel/capsules.db
```

## Test Fixtures

The `audit-fixtures.json` file contains golden test vectors. Each fixture has:

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | What this fixture tests |
| `entry` | object | The exact JSON audit log entry |
| `valid` | boolean | Whether a conformant validator should accept this entry |

### Using the Fixtures

For every fixture where `valid` is `true`:

1. Serialize `entry` as compact JSON (no whitespace)
2. Parse it back
3. Confirm all six required fields are present and correctly typed
4. Confirm `timestamp`, `status`, and `details` pass validation rules

For every fixture where `valid` is `false`:

1. Attempt to validate `entry`
2. Confirm the validator rejects it
3. The `description` field explains what is wrong

## Adding New Fixtures

New fixtures must:

1. Test a specific edge case or action type
2. Be deterministic (no random data)
3. Include `description`, `entry`, and `valid`
4. Use realistic but fictional data
