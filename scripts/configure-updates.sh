#!/usr/bin/env bash
# Automatic security patches via unattended-upgrades.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DOMAIN="${DOMAIN:-example.com}"
LE_EMAIL="${LE_EMAIL:-admin@$DOMAIN}"
AUTO_REBOOT="${AUTO_REBOOT:-0}"
case "$AUTO_REBOOT" in
    1|true|yes|on) REBOOT_BOOL="true" ;;
    *)            REBOOT_BOOL="false" ;;
esac

log_step "Configuring unattended security upgrades"

require_root
apt_install unattended-upgrades apt-listchanges >/dev/null

# Only security (and base) pockets are auto-installed — never -proposed/-backports.
write_if_changed "Unattended-Upgrade::Allowed-Origins {
    \"\${distro_id}:\${distro_codename}-security\";
    \"\${distro_id}:\${distro_codename}-updates\";
};

// Email a summary (requires a working MTA; harmless without one).
Unattended-Upgrade::Mail \"$LE_EMAIL\";
Unattended-Upgrade::MailOnlyOnError \"false\";

Unattended-Upgrade::Remove-Unused-Dependencies \"true\";
Unattended-Upgrade::Remove-New-Unused-Dependencies \"true\";
Unattended-Upgrade::AutoFixInterruptedDpkg \"true\";

// Reboots are opt-in: a web server shouldn't disappear without warning.
Unattended-Upgrade::Automatic-Reboot \"$REBOOT_BOOL\";
Unattended-Upgrade::Automatic-Reboot-Time \"04:00\";
" /etc/apt/apt.conf.d/50unattended-upgrades 0644

write_if_changed "APT::Periodic::Update-Package-Lists \"1\";
APT::Periodic::Download-Upgradeable-Packages \"1\";
APT::Periodic::AutocleanInterval \"7\";
APT::Periodic::Unattended-Upgrade \"1\";
" /etc/apt/apt.conf.d/20auto-upgrades 0644

systemctl_enable_now apt-daily.timer
systemctl_enable_now apt-daily-upgrade.timer

log_ok "Daily package-list refresh + security upgrades enabled"
log_info "config: /etc/apt/apt.conf.d/50unattended-upgrades"
log_info "dry run: sudo unattended-upgrade --dry-run --debug"
