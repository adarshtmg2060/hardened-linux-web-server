# Convenience wrappers around the scripts.
# Override any value on the command line, e.g.:
#   make verify-remote DOMAIN=example.com HOST=203.0.113.10 SSH_KEY=~/.ssh/id_ed25519

DOMAIN     ?= example.com
HOST       ?= $(DOMAIN)
ADMIN_USER ?= deploy
EMAIL      ?= admin@$(DOMAIN)
SSH_KEY    ?= $(HOME)/.ssh/id_ed25519

.PHONY: help setup verify-local verify-remote verify-all lint clean-help

help:
	@echo "Targets:"
	@echo "  setup          Run scripts/setup.sh on this machine (needs sudo/root)"
	@echo "  verify-local   Audit the local configuration (needs sudo/root)"
	@echo "  verify-remote  Audit open ports / TLS / SSH from this machine"
	@echo "  verify-all     Both local and remote audits"
	@echo "  lint           ShellCheck every shell script"
	@echo "  clean-help     List backup files the idempotent installer created"

setup:
	sudo bash scripts/setup.sh --domain $(DOMAIN) --email $(EMAIL) \
		--admin-user $(ADMIN_USER) --ssh-key $(SSH_KEY)

verify-local:
	sudo bash tests/verify-server.sh --local --domain $(DOMAIN) --admin-user $(ADMIN_USER)

verify-remote:
	bash tests/verify-server.sh --remote --host $(HOST) --domain $(DOMAIN) \
		--admin-user $(ADMIN_USER) --ssh-key $(SSH_KEY)

verify-all:
	sudo bash tests/verify-server.sh --all --host $(HOST) --domain $(DOMAIN) \
		--admin-user $(ADMIN_USER) --ssh-key $(SSH_KEY)

lint:
	@find scripts tests -name '*.sh' -print0 | xargs -0 shellcheck

clean-help:
	@echo "Server-side backups created before config changes:"
	@echo "  sudo find /etc -maxdepth 4 -name '*.bak.*' -printf '%TY-%Tm-%Td %p\n' | sort"
