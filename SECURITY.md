# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in QP Tunnel, please report it responsibly.

**Email:** security@quantumpipes.com

**What to include:**
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

**Response timeline:**
- Acknowledgment within 48 hours
- Initial assessment within 7 days
- Fix or mitigation plan within 30 days

## Scope

Security reports are accepted for:
- Command injection or code execution vulnerabilities
- Key material exposure (private keys logged, leaked, or improperly permissioned)
- Audit log bypass or tampering
- Input validation bypass
- Cryptographic weaknesses in how WireGuard is configured
- Privilege escalation

## Out of Scope

- WireGuard protocol vulnerabilities (report to the WireGuard project)
- DigitalOcean API issues (report to DigitalOcean)
- Social engineering attacks
- Denial of service via resource exhaustion

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.1.x | Yes |

## Security Design

QP Tunnel follows these security principles:

- All keys generated with umask 077 (owner-only permissions)
- Private keys never appear in logs, terminal output, or audit trails
- Input validation rejects all characters outside `[a-zA-Z0-9_-]`
- Zero use of `eval` in the entire codebase
- API tokens masked in all log output
- `set -euo pipefail` in every script
- ERR trap ensures failures are recorded in the audit trail
- Revoked peers are archived, never deleted (audit compliance)

Copyright 2026 Quantum Pipes Technologies, LLC.
