#!/usr/bin/env bash
# Create the non-root administrator, install their public key and lock root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ADMIN_USER="${ADMIN_USER:-deploy}"
ADMIN_PUBLIC_KEY_PATH="${ADMIN_PUBLIC_KEY_PATH:-}"
ADMIN_PUBLIC_KEY="${ADMIN_PUBLIC_KEY:-}"
SECRET_DIR="${SECRET_DIR:-/root/.server-setup}"

log_step "Creating administrator account '${ADMIN_USER}'"

require_root
command_exists openssl || apt_install openssl

if ! is_debian_family; then
    die "This script targets Debian/Ubuntu only."
fi

# --- Resolve the public key -------------------------------------------------
if [[ -z "$ADMIN_PUBLIC_KEY" && -n "$ADMIN_PUBLIC_KEY_PATH" ]]; then
    [[ -r "$ADMIN_PUBLIC_KEY_PATH" ]] || die "Cannot read public key: $ADMIN_PUBLIC_KEY_PATH"
    ADMIN_PUBLIC_KEY="$(cat "$ADMIN_PUBLIC_KEY_PATH")"
fi
[[ -n "$ADMIN_PUBLIC_KEY" ]] || die "Set ADMIN_PUBLIC_KEY_PATH (or export ADMIN_PUBLIC_KEY)."

# Accept the common OpenSSH public key types; reject private keys and junk.
case "$ADMIN_PUBLIC_KEY" in
    ssh-ed25519*|ssh-rsa*|ecdsa-sha2-*|sk-ssh-ed25519@*|sk-ecdsa-sha2-nistp256@*)
        ;;
    *)
        die "That does not look like an OpenSSH PUBLIC key (expected 'ssh-ed25519 AAAA...')."
        ;;
esac

# --- Create the account (idempotent) ---------------------------------------
if id "$ADMIN_USER" >/dev/null 2>&1; then
    log_info "user already exists: $ADMIN_USER"
else
    useradd --create-home --shell /bin/bash --groups sudo "$ADMIN_USER"
    log_ok "created user: $ADMIN_USER (member of sudo)"
fi

# --- Install authorized_keys ------------------------------------------------
SSH_DIR="/home/$ADMIN_USER/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
install -d -o "$ADMIN_USER" -g "$ADMIN_USER" -m 700 "$SSH_DIR"
write_if_changed "$ADMIN_PUBLIC_KEY" "$AUTH_KEYS" 600 "$ADMIN_USER:$ADMIN_USER"

# --- Initial password (for sudo only; SSH password auth stays disabled) -----
mkdir -p "$SECRET_DIR"
chmod 700 "$SECRET_DIR"
PASSWORD_FILE="$SECRET_DIR/${ADMIN_USER}-initial-password"
if [[ ! -s "$PASSWORD_FILE" ]]; then
    INITIAL_PASSWORD="$(openssl rand -base64 24 | tr -d '\n')"
    printf 'username: %s\npassword: %s\ngenerated: %s\n' \
        "$ADMIN_USER" "$INITIAL_PASSWORD" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$PASSWORD_FILE"
    chown root:root "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
    printf '%s:%s\n' "$ADMIN_USER" "$INITIAL_PASSWORD" | chpasswd
    log_warn "Initial sudo password written to $PASSWORD_FILE (root-only)."
    log_warn "Log in, run 'passwd', then delete that file."
else
    log_info "initial password already generated — leaving it untouched"
fi

# --- Lock root; key-only root login is forbidden at the sshd layer too ------
if passwd -S root | grep -q ' P '; then
    passwd -l root >/dev/null
    log_ok "root password locked"
else
    log_info "root password already locked"
fi

# --- Login banner -----------------------------------------------------------
write_if_changed "AUTHORISED ACCESS ONLY. All activity is monitored and logged." \
    /etc/ssh/ssh_banner 0644

log_ok "Admin account ready: $ADMIN_USER"
