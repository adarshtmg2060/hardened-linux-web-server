# Troubleshooting

> Part of the [main README](../readme.md) · [Screenshot evidence](../screenshots/README.md)

## I locked myself out of SSH

The script keeps the old session alive on purpose. From the **existing**
terminal (or the provider's serial/VNC console):

```bash
# See what is actually in effect
sshd -T | grep -E 'permitrootlogin|passwordauthentication|authenticationmethods|allowusers'

# Temporarily allow passwords again
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' \
    /etc/ssh/sshd_config.d/99-hardening.conf
systemctl restart ssh
```

The most common cause of a lockout is a key that was never installed:
`cat /home/<admin>/.ssh/authorized_keys` should contain your **public** key,
the file must be `600` and `/home/<admin>/.ssh` must be `700`.

`vagrant`/cloud users: most providers offer a "rescue mode" that mounts the
disk on another VM — that is the last resort.

## `sshd -t` fails

```bash
sshd -t                       # prints the offending line
journalctl -u ssh -n 50 --no-pager
```

The script rolls back automatically. If the failure persists, a keyword may be
unsupported by your OpenSSH version (check `ssh -V`). Remove that line from
`config/sshd_config` and re-run.

## certbot cannot obtain a certificate

1. Confirm DNS: `dig +short <domain> @1.1.1.1` must return the VM's public IP.
2. Confirm port 80 is reachable **from outside**: `curl -I http://<domain>`.
3. Confirm the cloud security group allows 80 (ufw alone is not enough).
4. Check `certbot certificates` and `/var/log/letsencrypt/letsencrypt.log`.

Common cause: the A record still points to an old IP. Wait for TTL, then:

```bash
sudo bash scripts/setup.sh        # idempotent — reuses everything else
```

If you need the site live before DNS is ready, use `--skip-certbot` and rerun
later.

## nginx fails `nginx -t`

- Certificate files missing → you are still on the bootstrap config; certbot
  must succeed before the hardened config can be installed.
- `unknown directive "http2"` → very old nginx; change `listen 443 ssl http2;`
  to `listen 443 ssl;` in `config/nginx-site.conf`.
- `limit_req_zone ... is unknown` → `conf.d/00-ratelimit.conf` was not loaded;
  re-run `scripts/configure-nginx.sh`.

## fail2ban not banning

```bash
fail2ban-client -t
fail2ban-client status sshd
fail2ban-client -d | grep -i ufw     # confirm the ban action
tail -f /var/log/fail2ban.log
```

If the `sshd` jail shows `0 total failed`, the journal backend may need
`python3-systemd` (the script installs it) or fail2ban needs a restart after
install. Also check the filter matches your sshd log format:

```bash
fail2ban-regex systemd-journal /etc/fail2ban/filter.d/sshd.conf
```

To free an IP you accidentally banned:

```bash
fail2ban-client set sshd unbanip <ip>
```

## Banned yourself through the cloud console?

Your provider's firewall logs will show the ufw INSERT rules. Remove them with
`fail2ban-client set sshd unbanip <your-ip>`, or wait out the 1-hour ban.

## Automatic upgrades are not running

```bash
systemctl status apt-daily.timer apt-daily-upgrade.timer
systemctl list-timers | grep apt
sudo unattended-upgrade --dry-run --debug
cat /var/log/unattended-upgrades/unattended-upgrades.log
```

## nginx workers cannot write / permission errors

The workers run as `webuser`. After a package upgrade the cache directories
may revert to root ownership:

```bash
chown -R webuser:webuser /var/cache/nginx /var/lib/nginx
systemctl reload nginx
```

Re-running `setup.sh` applies the same fix idempotently.

## Site files show a 403

```bash
namei -l /var/www/<domain>/index.html
ls -ld /var/www/<domain>
```

Expected: directories `750`, files `640`, owner `webuser`. The `location ~
/\.(?!well-known)` and backup-extension blocks in the nginx config deny some
paths on purpose — check the filename before "fixing" permissions.
