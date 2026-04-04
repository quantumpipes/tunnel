---
name: Provider Request
about: Request support for a new relay provider
title: "[Provider] "
labels: enhancement, provider
assignees: ''
---

## Provider Name

Name of the relay provider (e.g., Tailscale, Cloudflare Tunnel, ngrok).

## Provider Type

- [ ] Cloud API (hosted relay service)
- [ ] SSH (remote port forwarding)
- [ ] Container (Docker/Podman sidecar)
- [ ] Other (describe below)

## Why This Provider Matters

Explain the use case. Who benefits from this provider and why?

## API Documentation

Links to the provider's API docs, CLI reference, or integration guides.

## Are You Willing to Implement It?

- [ ] Yes, I can submit a PR
- [ ] I can help test but not implement
- [ ] No, just requesting

## Security Considerations

- Does the provider require storing API keys or credentials?
- Does it introduce any external network dependencies?
- How does it handle key rotation?

## Additional Context

Any other context, diagrams, or examples about the provider request.

## Checklist

- [ ] I have searched existing issues to ensure this is not a duplicate
- [ ] I have verified the provider has public documentation
- [ ] I have considered the security implications
