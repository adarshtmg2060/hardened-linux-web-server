# Security hardening reference

> Part of the [main README](../readme.md) · [Screenshot evidence](../screenshots/README.md)

Each control, the exact setting, and the reason it exists. All file paths are
on the server; the repo copies live in `config/`.

## 1. Users and SSH

| Setting | Value | Reason |
|---|---|---|
| Admin account | `deploy` (configurable) | Daily work never happens as root. |
| `PermitRootLogin` | `no` | Removes the most targeted account name entirely. |
| `AuthenticationMethods` | `publickey` | Even if another method were enabled later, auth must include a key. |
| `PasswordAuthentication` | `no` | Guessing passwords cannot work. |
| `KbdInteractiveAuthentication` | `no` | Closes the interactive/keyboard "back door" around password auth. |
| `AllowUsers` | `<admin-user>` | Everyone else is denied even with a valid key. |
| `MaxAuthTries` | `3` | Limits keys offered per connection. |
| `LoginGraceTime` | `30` | Unauthenticated sockets do not linger. |
| `ClientAliveInterval/CountMax` | `300 / 2` | Dead sessions are cleaned up after ~10 minutes. |
| Forwarding | `X11`, agent, TCP and tunnel all `no` | A compromised session cannot pivot through the server. |
| Root password | locked (`passwd -l root`) | Belt and braces alongside `PermitRootLogin no`. |

The login banner (`/etc/ssh/ssh_banner`) is a simple "authorised access only"
notice — useful for setting expectations during an audit.

## 2. Firewall (ufw)

```
Status: active

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW IN    Anywhere
80/tcp                     ALLOW IN    Anywhere
443/tcp                    ALLOW IN    Anywhere
```

Default incoming policy is `DROP`, outgoing is `ALLOW` (so apt, certbot and
OCSP lookups keep working). There is no rule for MySQL, Redis, SMTP or any
admin panel because none of those services are installed.

## 3. nginx and TLS

- **TLS 1.2 + 1.3 only.** TLS 1.0/1.1 are dead; no downgrade possible.
- **AEAD cipher suites only**, forward secret ECDHE; static RSA key exchange is gone.
- `ssl_session_tickets off` — session ticket keys are not rotated by nginx by
  default, which weakens forward secrecy.
- **OCSP stapling** with public resolvers — clients verify revocation without
  contacting Let's Encrypt themselves.
- **HSTS** `max-age=31536000; includeSubDomains` — browsers remember to use
  HTTPS. (`preload` is intentionally omitted to avoid breaking subdomains.)
- **CSP**, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`,
  `Permissions-Policy`, `X-XSS-Protection` — defence in depth against
  injection and clickjacking.
- `server_tokens off` — no version string in responses or error pages.
- **Dedicated `webuser`** runs the workers; site files are `640`, directories
  `750`. Dotfiles and backup extensions are denied by location blocks.
- **Rate limiting** `10 r/s` with a burst of 20 in `conf.d/00-ratelimit.conf`.

## 4. fail2ban

| Jail | Trigger | Ban |
|---|---|---|
| `sshd` | 3 auth failures in 10 min | 1 hour |
| `nginx-http-auth` | 5 failed HTTP auth attempts | 1 hour |
| `recidive` | 3 bans in 1 day | 1 week |

Bans are applied with the `ufw` action, so they appear in `ufw status` and are
removed automatically when the ban expires. `backend = systemd` reads the
journal directly, which works whether or not `/var/log/auth.log` is a real file.

Useful commands:

```bash
fail2ban-client status
fail2ban-client status sshd
fail2ban-client set sshd unbanip 203.0.113.10    # release yourself by mistake
fail2ban-regex /var/log/auth.log /etc/fail2ban/filter.d/sshd.conf
```

## 5. Automatic updates

`/etc/apt/apt.conf.d/50unattended-upgrades` allows only:

- `${distro_id}:${distro_codename}-security`
- `${distro_id}:${distro_codename}-updates`

Unused dependencies are removed and interrupted dpkg states are repaired.
Reboots are **off** (`Automatic-Reboot "false"`) so patching never causes
surprise downtime; set `AUTO_REBOOT=1` in `config/.env` if that trade-off suits
your environment.

## 6. Reproducibility as a security control

A scripted build is a security control because it makes the desired state
reviewable and repeatable. `setup.sh` uses `set -euo pipefail`, validates config
before changing anything, tests `sshd`/`fail2ban`/`nginx` configs **before**
reloading, and keeps timestamped backups of every file it replaces.
