# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-03-25

### Added

- **Relay provisioning** with four provider modes: DigitalOcean (doctl or curl fallback), SSH, local, and generate-script for manual deployment.
- **Device enrollment** via `tunnel-join.sh` with automatic keypair generation, WireGuard config writing, systemd autostart, and peer registry.
- **Peer management** with `tunnel-add-peer.sh` (IP allocation, config rendering, QR code output, hot-add) and `tunnel-remove-peer.sh` (instant revocation, archival, registry update).
- **Status monitoring** via `tunnel-status.sh` with handshake times, connection state, and column-formatted output.
- **Key rotation** via `tunnel-rotate-keys.sh` with dry-run mode and CONFIRM=1 execution gate.
- **Preflight checks** via `tunnel-preflight.sh` for dependency validation and environment loading.
- **Shared library** with four modules: `common.sh` (logging, config), `registry.sh` (peer CRUD), `wireguard.sh` (interface ops), `audit.sh` (structured JSON logging with optional Capsule sealing).
- **Capsule Protocol integration** for tamper-evident audit sealing (SHA3-256 + Ed25519) via qp-capsule.
- **TUNNEL_APP_NAME generalization** for white-labeling and custom branding.
- **333 bats tests** across 20 test files (15 unit, 5 integration) plus 37 smoke tests.
- **Makefile** with 17 targets for relay provisioning, tunnel operations, and testing.
- **Documentation**: README, GUIDE, CRYPTO-NOTICE, CONTRIBUTING, SECURITY, LICENSE, NOTICE, PATENTS.
- **GitHub configuration**: CI workflow (ShellCheck + bats), issue templates, PR template, CODEOWNERS.
