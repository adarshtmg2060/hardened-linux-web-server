#!/usr/bin/env bash
# Harden sshd: keys only, no root, no forwarding, short graceful timeouts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ADMIN_USER="${ADMIN_USER:-deploy}"
MAIN_CONFIG="/etc/ssh/sshd_config"
DROPIN_DIR="/etc/ssh/sshd_config.d"
DROPIN="$DROPIN_DIR/99-hardening.conf"

log_step "Hardening SSH daemon"

require_root
command -v sshd >/dev/null 2>&1 || die "sshd is not installed yet."
id "$ADMIN_USER" >/dev/null 2>&1 || die "Run scripts/create-admin.sh first."

# --- Make sure Debian/Ubuntu actually includes our drop-in directory --------
mkdir -p "$DROPIN_DIR"
if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/.*\.conf' "$MAIN_CONFIG"; then
    log_warn "Main sshd_config has no Include for sshd_config.d — adding one."
    tmp="$(mktemp)"
    printf 'Include /etc/ssh/sshd_config.d/*.conf\n\n' >"$tmp"
    cat "$MAIN_CONFIG" >>"$tmp"
    install_file "$tmp" "$MAIN_CONFIG" 0600
    rm -f "$tmp"
fi

# --- Generate any missing host keys ----------------------------------------
ssh-keygen -A >/dev/null 2>&1 || true

render_file "$REPO_ROOT/config/sshd_config" "$DROPIN" 0644 __ADMIN_USER__ "$ADMIN_USER"

# --- Validate BEFORE reloading: a typo here must not lock us out ------------
if ! sshd -t; then
    log_warn "New sshd config failed validation — restoring previous state."
    previous="$(latest_backup "$DROPIN")"
    if [[ -n "$previous" ]]; then
        mv -f "$previous" "$DROPIN"
    else
        rm -f "$DROPIN"
    fi
    die "sshd -t failed. Fix the template and re-run."
fi

systemctl_enable_now ssh
systemctl restart ssh 2>/dev/null || systemctl restart sshd

log_ok "sshd hardened and reloaded"
log_info "effective policy: $(sshd -T | grep -E '^(permitrootlogin|passwordauthentication|authenticationmethods|allowusers)' | tr '\n' ' ')"
log_warn "Keep your current session open and test a NEW key-based login before disconnecting."
