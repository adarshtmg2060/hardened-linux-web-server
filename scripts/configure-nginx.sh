#!/usr/bin/env bash
# nginx + Let's Encrypt: static site served by a dedicated unprivileged user.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DOMAIN="${DOMAIN:-}"
LE_EMAIL="${LE_EMAIL:-}"
SKIP_CERTBOT="${SKIP_CERTBOT:-0}"
WEB_USER="${WEB_USER:-webuser}"
SITE_ROOT="/var/www/$DOMAIN"
AVAILABLE="/etc/nginx/sites-available/$DOMAIN"
ENABLED="/etc/nginx/sites-enabled/$DOMAIN"
CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"

log_step "Configuring nginx and HTTPS for ${DOMAIN:-<no domain>}"

require_root
[[ -n "$DOMAIN" && "$DOMAIN" != "example.com" ]] || die "Set DOMAIN to your real FQDN (config/.env or --domain)."
[[ -n "$LE_EMAIL" ]] || LE_EMAIL="admin@$DOMAIN"
[[ -r "$REPO_ROOT/site/index.html" ]] || die "Missing site/index.html in the repo."

# --- Packages ---------------------------------------------------------------
apt_install nginx certbot python3-certbot-nginx openssl >/dev/null

# --- Dedicated, login-disabled user owns the web root and nginx workers -----
if ! id "$WEB_USER" >/dev/null 2>&1; then
    useradd --system --home "$SITE_ROOT" --shell /usr/sbin/nologin \
        --no-create-home "$WEB_USER"
    log_ok "created system user: $WEB_USER"
else
    log_info "system user already exists: $WEB_USER"
fi

install -d -o "$WEB_USER" -g "$WEB_USER" -m 750 "$SITE_ROOT"
install -o "$WEB_USER" -g "$WEB_USER" -m 640 \
    "$REPO_ROOT/site/index.html" "$SITE_ROOT/index.html"
# ACME challenge directory must be writable by the nginx worker only briefly;
# certbot uses the webroot path but writes as root, so read access is enough.
install -d -o "$WEB_USER" -g "$WEB_USER" -m 750 "$SITE_ROOT/.well-known/acme-challenge"

# Run nginx workers as the dedicated user (master still runs as root).
NGINX_CONF=/etc/nginx/nginx.conf
if grep -q '^user[[:space:]]' "$NGINX_CONF"; then
    sed -i -E "s|^user[[:space:]]+.*;|user $WEB_USER;|" "$NGINX_CONF"
else
    tmp="$(mktemp)"
    printf 'user %s;\n\n' "$WEB_USER" >"$tmp"
    cat "$NGINX_CONF" >>"$tmp"
    install_file "$tmp" "$NGINX_CONF" 0644
    rm -f "$tmp"
fi
chown -R "$WEB_USER:$WEB_USER" /var/cache/nginx /var/lib/nginx 2>/dev/null || true

# --- Shared http-context config (rate-limit zones) --------------------------
render_file "$REPO_ROOT/config/nginx-ratelimit.conf" \
    /etc/nginx/conf.d/00-ratelimit.conf

# --- Enable our site, disable the stock placeholder -------------------------
rm -f /etc/nginx/sites-enabled/default

install_site_conf() {
    local template="$1"
    render_file "$template" "$AVAILABLE" 0644 \
        __DOMAIN__ "$DOMAIN" __SITE_ROOT__ "$SITE_ROOT"
    ln -sfn "$AVAILABLE" "$ENABLED"
    nginx -t >/dev/null 2>&1 || die "nginx -t failed — see output above."
    systemctl enable nginx >/dev/null 2>&1 || true
    systemctl reload nginx 2>/dev/null || systemctl start nginx
}

# --- Bootstrap HTTP, obtain cert, then switch to hardened TLS config --------
CERT_OK=1
if [[ "$SKIP_CERTBOT" == "1" ]]; then
    CERT_OK=0
    log_warn "SKIP_CERTBOT=1 — leaving nginx on HTTP only."
    log_warn "Point DNS at this host, then re-run: sudo $SCRIPT_DIR/setup.sh"
    install_site_conf "$REPO_ROOT/config/nginx-bootstrap.conf"
elif [[ -f "$CERT" ]]; then
    log_info "existing certificate found for $DOMAIN — skipping issuance"
    install_site_conf "$REPO_ROOT/config/nginx-site.conf"
else
    log_info "no certificate yet — starting temporary HTTP challenge server"
    install_site_conf "$REPO_ROOT/config/nginx-bootstrap.conf"

    if certbot --nginx --non-interactive --agree-tos --no-eff-email \
        --email "$LE_EMAIL" --redirect -d "$DOMAIN"; then
        log_ok "certificate issued for $DOMAIN"
        install_site_conf "$REPO_ROOT/config/nginx-site.conf"
    else
        CERT_OK=0
        log_warn "certbot could not obtain a certificate (DNS not propagated?)"
        log_warn "nginx is serving HTTP only. Fix DNS and re-run setup.sh."
    fi
fi

if [[ "$CERT_OK" == "1" ]]; then
    # Reload nginx after every renewal, even if certbot's own hook changes.
    HOOK_DIR=/etc/letsencrypt/renewal-hooks/deploy
    install -d -m 755 "$HOOK_DIR"
    write_if_changed '#!/bin/sh
# Reload nginx after a successful certificate renewal.
systemctl reload nginx >/dev/null 2>&1 || true' \
        "$HOOK_DIR/reload-nginx.sh" 0755

    systemctl_enable_now certbot.timer
    log_ok "nginx + TLS ready for https://$DOMAIN"
else
    log_warn "nginx is serving HTTP only until a certificate exists."
fi
log_info "site root: $SITE_ROOT (owner: $WEB_USER)"
