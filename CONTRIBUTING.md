# Contributing to QP Tunnel

Thank you for your interest in contributing. QP Tunnel is open source under the Apache 2.0 license and welcomes contributions from the community.

## How to Contribute

### Reporting Issues

Open a GitHub issue with:
- A clear title describing the problem
- Steps to reproduce
- Expected vs. actual behavior
- Your OS, bash version, and WireGuard version

### Submitting Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-change`)
3. Make your changes
4. Run the test suite: `make test`
5. Commit with a clear message
6. Open a pull request

### Pull Request Guidelines

- Keep PRs focused on a single change
- Include tests for new functionality
- Update documentation if behavior changes
- Follow the existing code style (see below)

## Code Style

### Shell Scripts

- `set -euo pipefail` at the top of every script
- Functions documented with a comment block explaining purpose and parameters
- Use `local` for all function variables
- Validate inputs at function boundaries
- Never use `eval`
- Use `$(command)` instead of backticks
- Quote all variable expansions: `"$var"` not `$var`
- File permissions: 600 for keys, 700 for directories

### Testing

- Tests use [bats-core](https://github.com/bats-core/bats-core)
- Follow AAA pattern: Arrange, Act, Assert
- Tests must be deterministic and isolated (use `$BATS_TMPDIR`)
- Test both success paths and error paths
- New lib functions require unit tests

### Documentation

- Update README.md if adding commands or configuration
- Update CRYPTO-NOTICE.md if changing cryptographic behavior
- Comments in code should explain "why", not "what"

## Architecture Principles

- **Self-contained:** No dependencies on external projects (except optional qp-capsule)
- **Configurable:** All defaults overridable via environment variables
- **Auditable:** Every state-changing operation must write to the audit log
- **Secure by default:** Safe umask, no eval, strict input validation
- **Never delete:** Revoked peers are archived, never deleted

## Testing Your Changes

```bash
# Install bats-core
git clone https://github.com/bats-core/bats-core.git
cd bats-core && sudo ./install.sh /usr/local

# Run all tests
make test

# Run specific test tiers
make test-unit
make test-integration
make test-smoke
```

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.

Copyright 2026 Quantum Pipes Technologies, LLC.
