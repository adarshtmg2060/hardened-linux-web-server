#!/usr/bin/env bash
# ufw: default-deny inbound, only SSH / HTTP / HTTPS reachable.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

log_step "Configuring ufw firewall"

require_root
command_exists ufw || apt_install ufw

# Default posture: drop everything inbound, allow everything outbound.
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw logging on >/dev/null

# Idempotent rule helper (ufw will happily add duplicates if asked twice).
allow_if_missing() {
    local rule="$1" label="$2"
    if ufw status | grep -qiE "${label}([[:space:]]|$)"; then
        log_info "already allowed: $label"
    else
        ufw allow "$rule" >/dev/null
        log_ok "allowed: $label"
    fi
}

allow_if_missing "22/tcp"  "22/tcp"
allow_if_missing "80/tcp"  "80/tcp"
allow_if_missing "443/tcp" "443/tcp"

if ufw status | grep -qi '^Status: active'; then
    log_info "ufw already active"
else
    ufw --force enable >/dev/null
    log_ok "ufw enabled"
fi

log_info "$(ufw status | sed -n '1,12p')"
