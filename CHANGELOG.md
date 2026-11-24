# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-11-24

### Added

- `scripts/setup.sh` — idempotent orchestrator with `set -euo pipefail`,
  config-file/CLI/env inputs, preflight checks and a post-run checklist.
- Six focused building-block scripts plus a shared `lib/common.sh` with
  timestamped backups and change-only installs.
- sshd drop-in: key-only auth, no root, no forwarding, `AllowUsers`.
- ufw: default-deny inbound with only 22/80/443 allowed.
- nginx: dedicated `webuser`, TLS 1.2/1.3, HSTS/CSP/OCSP stapling, rate limits,
  ACME bootstrap flow and a reload-on-renew hook.
- fail2ban: `sshd`, `nginx-http-auth` and `recidive` jails using the ufw action.
- unattended-upgrades with security-only origins and opt-in reboots.
- `tests/verify-server.sh` for local and external (attacker-view) checks.
- Documentation: architecture, installation, hardening reference, verification
  and troubleshooting.
- MIT license, Makefile targets and a ShellCheck GitHub Actions workflow.

### Security notes

- Config syntax is validated with `sshd -t`, `nginx -t` and `fail2ban-client -t`
  **before** any daemon is reloaded; failed validation rolls back the change.
- The initial sudo password is generated once, stored root-only at
  `/root/.server-setup/<admin>-initial-password`, and must be rotated and
  deleted after first login.
