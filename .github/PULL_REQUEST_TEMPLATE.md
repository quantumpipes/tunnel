## Description

Brief description of the changes in this PR.

## Type of Change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to change)
- [ ] Documentation update
- [ ] Refactoring (no functional changes)
- [ ] Test addition or update

## Related Issue

Fixes #(issue number)

## Changes Made

- Change 1
- Change 2
- Change 3

## How Has This Been Tested?

Describe the tests you ran to verify your changes.

```bash
# Commands used to test
make test
make test-smoke
```

- [ ] Unit tests pass (`make test-unit`)
- [ ] Integration tests pass (`make test-integration`)
- [ ] Smoke tests pass (`make test-smoke`)
- [ ] ShellCheck passes with no warnings

## Security Considerations

- [ ] No private keys are logged, leaked, or improperly permissioned
- [ ] All inputs are validated against `[a-zA-Z0-9_-]`
- [ ] No use of `eval`
- [ ] Audit log is written for all state-changing operations
- [ ] New files use `umask 077` for key material

## Documentation

- [ ] I have updated the README if adding commands or configuration
- [ ] I have updated CRYPTO-NOTICE.md if changing cryptographic behavior
- [ ] I have updated the CHANGELOG.md (if applicable)

## Checklist

- [ ] My code follows the project's style guidelines (`set -euo pipefail`, local vars, quoted expansions)
- [ ] I have performed a self-review of my code
- [ ] My changes generate no new ShellCheck warnings
- [ ] I have added tests that prove my fix/feature works
- [ ] New and existing tests pass locally with my changes
