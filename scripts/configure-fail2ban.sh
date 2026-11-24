#!/usr/bin/env bash
# fail2ban: temporary ufw bans for SSH / nginx abusers and repeat offenders.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DOMAIN="${DOMAIN:-example.com}"
LE_EMAIL="${LE_EMAIL:-admin@$DOMAIN}"

log_step "Configuring fail2ban"

require_root
command_exists ufw || die "Run scripts/configure-firewall.sh first."
apt_install fail2ban python3-systemd >/dev/null

render_file "$REPO_ROOT/config/jail.local" /etc/fail2ban/jail.local 0644 \
    __ADMIN_EMAIL__ "$LE_EMAIL" \
    __DOMAIN__ "$DOMAIN"

# Validate before restarting — a broken jail file stops the whole daemon.
if ! fail2ban-client -t >/dev/null 2>&1; then
    previous="$(latest_backup /etc/fail2ban/jail.local)"
    if [[ -n "$previous" ]]; then
        mv -f "$previous" /etc/fail2ban/jail.local
    else
        rm -f /etc/fail2ban/jail.local
    fi
    die "fail2ban config test failed — previous config restored."
fi

systemctl_enable_now fail2ban
systemctl restart fail2ban

sleep 2
fail2ban-client status sshd 2>/dev/null || log_warn "sshd jail not reported yet."

log_ok "fail2ban active with jails: $(fail2ban-client status 2>/dev/null | grep 'Jail list' || echo 'n/a')"
