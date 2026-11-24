#!/usr/bin/env bash
# Shared helpers for every script in this repo.
# Sourced (not executed) — safe with `set -euo pipefail` in the caller.

# --- Colours (disabled when stdout is not a TTY, e.g. in CI logs) -----------
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[1;33m'; C_BLUE=$'\033[0;34m'; C_BOLD=$'\033[1m'
else
    C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''
fi

log()      { printf '%s\n' "$*"; }
log_step() { printf '\n%s==>%s %s%s\n' "$C_BOLD" "$C_RESET" "$C_BLUE" "$*"; }
log_info() { printf '    %s\n' "$*"; }
log_ok()   { printf '    %s[ ok ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_warn() { printf '    %s[warn]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error(){ printf '    %s[fail]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()      { log_error "$*"; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || die "This script must be run as root (try: sudo -i)."
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Install apt packages non-interactively.
apt_install() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

# Copy a file into place only when its content actually changed.
# Backs up the previous version with a timestamp so every change is auditable.
install_file() {
    local src="$1" dst="$2" mode="${3:-0644}"
    local owner="${4:-root:root}"
    local backup=""

    mkdir -p "$(dirname "$dst")"
    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
        log_info "unchanged: $dst"
        return 0
    fi
    if [[ -f "$dst" ]]; then
        backup="${dst}.bak.$(date +%Y%m%d%H%M%S)"
        cp -a "$dst" "$backup"
    fi
    install -o "${owner%:*}" -g "${owner#*:}" -m "$mode" "$src" "$dst"
    if [[ -n "$backup" ]]; then
        log_ok "updated: $dst (backup: $backup)"
    else
        log_ok "created: $dst"
    fi
}

# Write a heredoc/string to a file without touching it when unchanged.
write_if_changed() {
    local content="$1" dst="$2" mode="${3:-0644}" owner="${4:-root:root}"
    local tmp
    tmp="$(mktemp)"
    printf '%s\n' "$content" >"$tmp"
    install_file "$tmp" "$dst" "$mode" "$owner"
    rm -f "$tmp"
}

# Render a template by replacing __TOKEN__ placeholders.
# Usage: render_file src dst [mode] __TOKEN__ value __OTHER__ value
# The optional mode is any octal string (e.g. 0644); it defaults to 0644.
render_file() {
    local src="$1" dst="$2" mode="0644"; shift 2
    if [[ "${1:-}" =~ ^[0-7]{3,4}$ ]]; then
        mode="$1"; shift
    fi
    local tmp escaped
    tmp="$(mktemp)"
    cp "$src" "$tmp"
    while (($# >= 2)); do
        local token="$1" value="$2"; shift 2
        # Escape sed replacement specials so domains/paths are inserted literally.
        escaped="$(printf '%s' "$value" | sed -e 's/[\\&|]/\\&/g')"
        sed -i "s|${token}|${escaped}|g" "$tmp"
    done
    install_file "$tmp" "$dst" "$mode"
    rm -f "$tmp"
}

# Print the newest timestamped backup of a file, or nothing if there is none.
latest_backup() {
    local target="$1"
    local matches=( "$target".bak.* )
    if [[ -e "${matches[0]}" ]]; then
        printf '%s' "${matches[$((${#matches[@]} - 1))]}"
    fi
}

# Append a line to a file only if an exact match is not already present.
ensure_line() {
    local line="$1" file="$2"
    touch "$file"
    grep -qxF "$line" "$file" || printf '%s\n' "$line" >>"$file"
}

systemctl_enable_now() {
    systemctl enable "$1" >/dev/null 2>&1 || true
    systemctl start "$1" >/dev/null 2>&1 || true
}

is_debian_family() {
    [[ -r /etc/os-release ]] && grep -qE '^(ID|ID_LIKE)=(debian|ubuntu)' /etc/os-release
}
