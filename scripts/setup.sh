#!/usr/bin/env bash
# =============================================================================
# setup.sh — one idempotent script that turns a fresh Debian/Ubuntu VM into a
# hardened public web server.
#
#   sudo ./scripts/setup.sh --domain example.com --email you@example.com \
#       --admin-user deploy --ssh-key ~/.ssh/id_ed25519.pub
#
# Safe to run twice: every step checks state before changing anything, and
# config files are backed up with a timestamp before being replaced.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

CONFIG_FILE="${CONFIG_FILE:-$REPO_ROOT/config/.env}"

usage() {
    cat <<EOF
Usage: sudo $0 [options]

Options:
  --domain DOMAIN          Public FQDN pointing at this VM
  --email EMAIL            Let's Encrypt / notification email
  --admin-user USER        Non-root admin account (default: deploy)
  --ssh-key PATH           Path to the admin's PUBLIC SSH key
  --skip-certbot           Configure HTTP now, get TLS on a later run
  --config PATH            Alternate env file (default: config/.env)
  -h, --help               Show this help

Any value can also come from config/.env or the environment.
EOF
}

# --- Resolve --config first, then load the env file -------------------------
ARGS=("$@")
for ((i = 0; i < ${#ARGS[@]}; i++)); do
    if [[ "${ARGS[$i]}" == "--config" ]]; then
        CONFIG_FILE="${ARGS[$((i + 1))]:-$CONFIG_FILE}"
    fi
done

if [[ -f "$CONFIG_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    set +a
    log_info "loaded config: $CONFIG_FILE"
fi

# --- CLI flags override values from the file / environment -----------------
set -- "${ARGS[@]}"
while (($#)); do
    case "$1" in
        --domain)
            [[ $# -ge 2 && -n "$2" ]] || die "--domain needs a value"; DOMAIN="$2"; shift 2 ;;
        --email)
            [[ $# -ge 2 && -n "$2" ]] || die "--email needs a value"; LE_EMAIL="$2"; shift 2 ;;
        --admin-user)
            [[ $# -ge 2 && -n "$2" ]] || die "--admin-user needs a value"; ADMIN_USER="$2"; shift 2 ;;
        --ssh-key)
            [[ $# -ge 2 && -n "$2" ]] || die "--ssh-key needs a value"; ADMIN_PUBLIC_KEY_PATH="$2"; shift 2 ;;
        --skip-certbot) SKIP_CERTBOT=1; shift ;;
        --config)       shift 2 ;;   # already handled above
        -h|--help)      usage; exit 0 ;;
        *)              die "Unknown option: $1 (try --help)" ;;
    esac
done

DOMAIN="${DOMAIN:-}"
LE_EMAIL="${LE_EMAIL:-${ADMIN_EMAIL:-}}"
ADMIN_USER="${ADMIN_USER:-deploy}"
ADMIN_PUBLIC_KEY_PATH="${ADMIN_PUBLIC_KEY_PATH:-}"
SKIP_CERTBOT="${SKIP_CERTBOT:-0}"

if [[ -z "$LE_EMAIL" && -n "$DOMAIN" && "$DOMAIN" != "example.com" ]]; then
    LE_EMAIL="admin@$DOMAIN"
fi

# --- Preflight --------------------------------------------------------------
log_step "Preflight checks"
require_root
is_debian_family || die "This script supports Debian / Ubuntu only."

[[ -n "$DOMAIN" && "$DOMAIN" != "example.com" ]] || die \
    "Set your real domain: edit config/.env or pass --domain your.site"

if [[ -z "$ADMIN_PUBLIC_KEY_PATH" && -z "${ADMIN_PUBLIC_KEY:-}" ]]; then
    for candidate in \
        "/home/${SUDO_USER:-root}/.ssh/id_ed25519.pub" \
        "/root/.ssh/id_ed25519.pub" \
        "$HOME/.ssh/id_ed25519.pub"; do
        if [[ -r "$candidate" ]]; then
            ADMIN_PUBLIC_KEY_PATH="$candidate"
            log_info "auto-detected SSH key: $candidate"
            break
        fi
    done
fi
[[ -n "$ADMIN_PUBLIC_KEY_PATH" || -n "${ADMIN_PUBLIC_KEY:-}" ]] || die \
    "Provide your PUBLIC key with --ssh-key / ADMIN_PUBLIC_KEY_PATH."

# Export so the child scripts inherit the resolved configuration.
export DOMAIN LE_EMAIL ADMIN_USER ADMIN_PUBLIC_KEY_PATH SKIP_CERTBOT

log_info "domain : $DOMAIN"
log_info "admin  : $ADMIN_USER"
log_info "email  : $LE_EMAIL"
log_info "key    : ${ADMIN_PUBLIC_KEY_PATH:-<provided inline>}"

# --- Base packages ----------------------------------------------------------
log_step "Updating package index and installing prerequisites"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt_install curl ca-certificates gnupg lsb-release openssl sudo >/dev/null
log_ok "system packages up to date"

# --- Run the building blocks in dependency order ----------------------------
# Explicit `bash` means execution does not depend on the git executable bit
# surviving a clone onto Windows/other filesystems.
for step in create-admin configure-ssh configure-firewall \
            configure-nginx configure-fail2ban configure-updates; do
    bash "$SCRIPT_DIR/${step}.sh"
done

# --- Summary ----------------------------------------------------------------
log_step "Setup complete"
cat <<EOF
  Public IP      : $(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || echo '<unknown>')
  SSH            : ssh -i <your-private-key> ${ADMIN_USER}@${DOMAIN}
  Site           : https://${DOMAIN}
  Health check   : https://${DOMAIN}/healthz

  Next steps (from YOUR machine, outside the server):
    1. Open a NEW terminal and confirm key-only SSH works.
    2. nmap -Pn -p 1-65535 ${DOMAIN}          # expect only 22, 80, 443
    3. curl -sI https://${DOMAIN}              # check HSTS + other headers
    4. SSL Labs: https://www.ssllabs.com/ssltest/analyze.html?d=${DOMAIN}
    5. sudo bash tests/verify-server.sh --local --domain ${DOMAIN}

  Read /root/.server-setup/${ADMIN_USER}-initial-password, run 'passwd',
  then delete that file. Keep your current SSH session open until step 1 works.
EOF
