---
name: Audit Format Change
about: Propose a change to the JSONL audit log format
title: "[Audit] "
labels: protocol, audit
assignees: ''
---

## Current Behavior

Describe how the audit log format works today. Which fields or structures are affected?

## Proposed Change

Describe the exact change to the JSONL audit format. Be specific about field names, types, and structure.

## Rationale

Why is this change needed? What problem does it solve?

## Backward Compatibility

- Does this break existing audit log parsers?
- Can old entries still be read after this change?
- Are new fields optional or required?

## Example Audit Entry

### Before

```json
{"timestamp": "2026-04-04T12:00:00Z", "action": "example", "existing_field": "value"}
```

### After

```json
{"timestamp": "2026-04-04T12:00:00Z", "action": "example", "existing_field": "value", "new_field": "value"}
```

## Migration Path

How should existing deployments handle the transition? Is a migration script needed?

## Checklist

- [ ] I have searched existing issues to ensure this is not a duplicate
- [ ] I have considered backward compatibility
- [ ] I have provided before/after examples
- [ ] I have described the migration path
