#!/usr/bin/env bash
# =============================================================================
# verify-server.sh — check the hardening from BOTH sides.
#
#   Local (on the server):  sudo bash tests/verify-server.sh --local --domain example.com
#   Remote (your laptop):   bash tests/verify-server.sh --remote --host 203.0.113.10 \
#                               --domain example.com --admin-user deploy --ssh-key ~/.ssh/id_ed25519
#
# No `set -e` on purpose: a failed check is data, not a crash.
# =============================================================================
set -uo pipefail

MODE="local"
HOST="${HOST:-}"
DOMAIN="${DOMAIN:-}"
ADMIN_USER="${ADMIN_USER:-deploy}"
SSH_KEY="${SSH_KEY:-}"

while (($#)); do
    case "$1" in
        --local)   MODE="local"; shift ;;
        --remote)  MODE="remote"; shift ;;
        --all)     MODE="all"; shift ;;
        --host)    HOST="$2"; shift 2 ;;
        --domain)  DOMAIN="$2"; shift 2 ;;
        --admin-user) ADMIN_USER="$2"; shift 2 ;;
        --ssh-key) SSH_KEY="$2"; shift 2 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
done

[[ -n "$DOMAIN" ]] || DOMAIN="${HOST:-}"
[[ -n "$HOST" ]] || HOST="$DOMAIN"
[[ -n "$HOST" ]] || { printf 'Pass --host or --domain.\n' >&2; exit 2; }

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'; RESET=$'\033[0m'
PASS=0; FAIL=0

pass() { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; PASS=$((PASS + 1)); }
fail() { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; FAIL=$((FAIL + 1)); }
note() { printf '  %sNOTE%s  %s\n' "$YELLOW" "$RESET" "$1"; }

expect_eq() { # description expected actual
    if [[ "$2" == "$3" ]]; then pass "$1 ($3)"; else fail "$1 — expected '$2', got '$3'"; fi
}

sshed() {
    sshd -T 2>/dev/null | awk -v key="$1" '$1 == key { print $2; exit }'
}

check_local() {
    printf '\n[ LOCAL / configuration ]\n'
    [[ $EUID -eq 0 ]] || { note "Some local checks need root; re-run with sudo for full coverage."; }

    expect_eq "permitrootlogin"   "no"        "$(sshed permitrootlogin)"
    expect_eq "passwordauthentication" "no"   "$(sshed passwordauthentication)"
    expect_eq "kbdinteractiveauthentication" "no" "$(sshed kbdinteractiveauthentication)"
    expect_eq "authenticationmethods" "publickey" "$(sshed authenticationmethods)"
    expect_eq "allowusers"        "$ADMIN_USER" "$(sshed allowusers)"

    if ufw status 2>/dev/null | grep -qi '^Status: active'; then
        pass "ufw is active"
        actual="$(ufw status | grep -oE '^[0-9]+/tcp' | sort -u | tr '\n' ' ' | sed 's/ $//')"
        expect_eq "only ports 22/80/443 allowed" "22/tcp 443/tcp 80/tcp" "$actual"
    else
        fail "ufw is not active"
    fi

    for unit in nginx fail2ban; do
        expect_eq "$unit is running" "active" "$(systemctl is-active "$unit" 2>/dev/null)"
    done
    for unit in certbot.timer apt-daily-upgrade.timer; do
        expect_eq "$unit is enabled" "enabled" "$(systemctl is-enabled "$unit" 2>/dev/null)"
    done
    for jail in sshd nginx-http-auth recidive; do
        if fail2ban-client status "$jail" 2>/dev/null | grep -q 'Filter'; then
            pass "fail2ban jail: $jail"
        else
            fail "fail2ban jail: $jail"
        fi
    done

    if nginx -t >/dev/null 2>&1; then pass "nginx config syntax"; else fail "nginx config syntax"; fi

    cert="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    if [[ -f "$cert" ]]; then
        days="$(openssl x509 -in "$cert" -noout -enddate | cut -d= -f2)"
        pass "certificate present (expires $days)"
    else
        fail "certificate missing for $DOMAIN"
    fi

    owner="$(stat -c '%U' "/var/www/$DOMAIN/index.html" 2>/dev/null || echo missing)"
    expect_eq "site files owned by webuser" "webuser" "$owner"

    headers="$(curl -skI "https://$DOMAIN" 2>/dev/null || true)"
    for header in 'strict-transport-security' 'x-content-type-options' 'content-security-policy'; do
        if printf '%s' "$headers" | grep -qi "$header"; then
            pass "header: $header"
        else
            fail "header: $header"
        fi
    done
}

check_remote() {
    printf '\n[ REMOTE / attacker view of %s ]\n' "$HOST"
    if command -v nmap >/dev/null 2>&1; then
        open="$(nmap -Pn -T4 --open --top-ports 200 "$HOST" 2>/dev/null \
            | grep -oE '^[0-9]+/tcp' | sort -t/ -k1,1n | tr '\n' ' ' | sed 's/ $//')"
        expect_eq "exposed ports" "22/tcp 80/tcp 443/tcp" "$open"
    else
        note "nmap not installed — install it to verify the open-port set."
    fi

    redirect="$(curl -s -o /dev/null -w '%{http_code}' "http://$DOMAIN" 2>/dev/null || true)"
    expect_eq "HTTP redirects to HTTPS" "301" "$redirect"

    code="$(curl -sk -o /dev/null -w '%{http_code}' "https://$DOMAIN" 2>/dev/null || true)"
    expect_eq "HTTPS serves 200" "200" "$code"

    hsts="$(curl -skI "https://$DOMAIN" 2>/dev/null | grep -i 'strict-transport-security' || true)"
    if [[ -n "$hsts" ]]; then pass "HSTS header present"; else fail "HSTS header present"; fi

    # A password login MUST fail. BatchMode avoids an interactive prompt.
    ssh_args=(-o BatchMode=yes -o PreferredAuthentications=password
              -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1
              -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)
    if ssh "${ssh_args[@]}" "$ADMIN_USER@$HOST" true >/dev/null 2>&1; then
        fail "password SSH login was ACCEPTED (should be impossible)"
    else
        pass "password SSH login refused"
    fi

    if [[ -n "$SSH_KEY" ]]; then
        if ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=8 \
            -o StrictHostKeyChecking=accept-new "$ADMIN_USER@$HOST" \
            'echo key-ok' 2>/dev/null | grep -q key-ok; then
            pass "key-based SSH login works"
        else
            fail "key-based SSH login works"
        fi
    else
        note "Pass --ssh-key PATH to verify key-based login too."
    fi
}

check_authlog() {
    printf '\n[ AUTH LOG / 24h break-in attempts ]\n'
    if [[ ! -r /var/log/auth.log ]]; then
        note "auth.log not readable here (journald-only host? try: journalctl -u ssh)."
        return
    fi
    since="$(date -d '24 hours ago' '+%b %e' 2>/dev/null || date '+%b %e')"
    failed="$(grep -c "$since.*Failed password" /var/log/auth.log 2>/dev/null || true)"
    invalid="$(grep -c "$since.*Invalid user" /var/log/auth.log 2>/dev/null || true)"
    printf '  Failed password attempts (24h): %s\n' "${failed:-0}"
    printf '  Invalid user attempts   (24h): %s\n' "${invalid:-0}"
    if command -v fail2ban-client >/dev/null 2>&1; then
        banned="$(fail2ban-client status sshd 2>/dev/null | grep 'Total banned' | cut -d: -f2 | tr -d ' ')"
        printf '  IPs banned by fail2ban        : %s\n' "${banned:-0}"
    fi
}

case "$MODE" in
    local)  check_local; check_authlog ;;
    remote) check_remote ;;
    all)    check_local; check_remote; check_authlog ;;
esac

printf '\n%s========================================%s\n' "$GREEN" "$RESET"
printf '  RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
printf '%s========================================%s\n\n' "$GREEN" "$RESET"

[[ $FAIL -eq 0 ]]
