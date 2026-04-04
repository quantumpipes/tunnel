# QP Tunnel - Makefile
# WireGuard tunnel automation for secure remote access.
# https://github.com/quantumpipes/tunnel
#
# Override TUNNEL_APP_NAME to rebrand for your project.
# Include this Makefile in your own: include path/to/tunnel/Makefile

SHELL := /bin/bash
.DEFAULT_GOAL := help

TUNNEL_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
.PHONY: help
help: ## Show this help
	@echo ""
	@echo "  QP Tunnel - WireGuard Automation"
	@echo "  ================================"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ---------------------------------------------------------------------------
# Relay Provisioning
# ---------------------------------------------------------------------------
.PHONY: tunnel-setup
tunnel-setup: ## Set up relay (auto-detects provider from env)
	@bash $(TUNNEL_DIR)/tunnel-setup-relay.sh

.PHONY: tunnel-setup-local
tunnel-setup-local: ## Set up relay on this machine
	@bash $(TUNNEL_DIR)/tunnel-setup-relay.sh --provider=local

.PHONY: tunnel-setup-ssh
tunnel-setup-ssh: ## Set up relay via SSH (RELAY_HOST=x.x.x.x)
	@bash $(TUNNEL_DIR)/tunnel-setup-relay.sh --provider=ssh --host=$(RELAY_HOST)

.PHONY: tunnel-setup-do
tunnel-setup-do: ## Provision DigitalOcean relay (requires DO_API_TOKEN)
	@bash $(TUNNEL_DIR)/tunnel-setup-relay.sh --provider=digitalocean

.PHONY: tunnel-generate-script
tunnel-generate-script: ## Output relay setup script for manual use
	@bash $(TUNNEL_DIR)/tunnel-setup-relay.sh --generate-script

# ---------------------------------------------------------------------------
# Tunnel Operations
# ---------------------------------------------------------------------------
.PHONY: tunnel-join
tunnel-join: ## Join an existing relay (RELAY_ENDPOINT=x RELAY_PUBLIC_KEY=x)
	@bash $(TUNNEL_DIR)/tunnel-join.sh $(RELAY_ENDPOINT) $(RELAY_PUBLIC_KEY)

.PHONY: tunnel-add-peer
tunnel-add-peer: ## Add a peer (NAME=alice)
	@bash $(TUNNEL_DIR)/tunnel-add-peer.sh $(NAME)

.PHONY: tunnel-remove-peer
tunnel-remove-peer: ## Revoke a peer (NAME=alice)
	@bash $(TUNNEL_DIR)/tunnel-remove-peer.sh $(NAME)

.PHONY: tunnel-status
tunnel-status: ## Show all peers with handshake times
	@bash $(TUNNEL_DIR)/tunnel-status.sh

.PHONY: tunnel-rotate-keys
tunnel-rotate-keys: ## Rotate relay keys (dry-run; CONFIRM=1 to execute)
	@bash $(TUNNEL_DIR)/tunnel-rotate-keys.sh

.PHONY: tunnel-open
tunnel-open: ## Open a local service with PQ TLS (NAME=grafana TO=localhost:3000)
	@bash $(TUNNEL_DIR)/tunnel-open.sh --name $(NAME) --to $(TO) $(if $(PORT),--port $(PORT),)

.PHONY: tunnel-close
tunnel-close: ## Close an opened service (NAME=grafana)
	@bash $(TUNNEL_DIR)/tunnel-close.sh --name $(NAME)

.PHONY: tunnel-list
tunnel-list: ## List all open services
	@bash $(TUNNEL_DIR)/tunnel-list.sh

.PHONY: tunnel-verify
tunnel-verify: ## Verify Capsule audit chain integrity
	@bash -c 'source $(TUNNEL_DIR)/tunnel-preflight.sh && qp-capsule verify'

# ---------------------------------------------------------------------------
# Testing
# ---------------------------------------------------------------------------
.PHONY: test
test: ## Run all tests (requires bats-core)
	@bats $(TUNNEL_DIR)/tests/unit/ $(TUNNEL_DIR)/tests/integration/

.PHONY: test-unit
test-unit: ## Run unit tests only
	@bats $(TUNNEL_DIR)/tests/unit/

.PHONY: test-integration
test-integration: ## Run integration tests only
	@bats $(TUNNEL_DIR)/tests/integration/

.PHONY: test-smoke
test-smoke: ## Run smoke tests
	@bash $(TUNNEL_DIR)/tests/smoke/test_standalone.sh
