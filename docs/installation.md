# Installation

> Part of the [main README](../readme.md) · [Screenshot evidence](../screenshots/README.md)

The project was built the way the brief asks: **first by hand, then as a
script**. This page keeps both paths so the reasoning behind every command is
visible.

## 0. Prerequisites

- A Debian 12 or Ubuntu 22.04+ VM with a public IPv4 address.
- A domain `A` record pointing at that IP (needed for Let's Encrypt).
- An Ed25519 SSH keypair on your own machine:
  ```bash
  ssh-keygen -t ed25519 -C "admin@<your-domain>"
  ```
- The cloud provider's own firewall/security group must also allow 22/80/443.

Replace `<your-domain>`, `<your-ip>` and `<admin-user>` below with your values.

## 1. Manual walkthrough (the notes the script was built from)

Connect as the provider's default user and become root:

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@<your-ip>
sudo -i
```

**Base packages**

```bash
apt-get update && apt-get upgrade -y
apt-get install -y curl ca-certificates gnupg lsb-release openssl sudo ufw \
                   nginx fail2ban python3-systemd unattended-upgrades \
                   apt-listchanges certbot python3-certbot-nginx
```

**Admin user + key**

```bash
useradd -m -s /bin/bash -G sudo <admin-user>
install -d -m 700 -o <admin-user> -g <admin-user> /home/<admin-user>/.ssh
install -m 600 -o <admin-user> -g <admin-user> /home/<admin-user>/.ssh/authorized_keys
# paste your PUBLIC key into authorized_keys
passwd -l root
```

**SSH hardening**

Write `/etc/ssh/sshd_config.d/99-hardening.conf` (see `config/sshd_config`),
then:

```bash
sshd -t && systemctl restart ssh
sshd -T | grep -E 'permitrootlogin|passwordauthentication|authenticationmethods'
```

> Test a **new** SSH session before closing the old one.

**Firewall**

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
ufw status
```

**nginx + certificate**

```bash
# serve the site from a dedicated user
useradd --system --home /var/www/<your-domain> --shell /usr/sbin/nologin webuser
# install config/nginx-site.conf and site/index.html, symlink into sites-enabled
nginx -t && systemctl reload nginx
certbot --nginx -d <your-domain> -m <you@example.com> --agree-tos --redirect --non-interactive
systemctl enable --now certbot.timer
```

**fail2ban + updates**

```bash
# install config/jail.local
fail2ban-client -t && systemctl restart fail2ban
fail2ban-client status sshd
# install 50unattended-upgrades and 20auto-upgrades (see config/ equivalents)
systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
```

## 2. Reproduce from scratch with the script

Once the manual steps are written down, the whole thing becomes one command:

```bash
git clone https://github.com/adarshtmg2060/hardened-linux-web-server.git
cd hardened-linux-web-server
cp config/example.env config/.env
nano config/.env                 # domain, email, admin user, PUBLIC key path
sudo bash scripts/setup.sh
```

Or pass everything on the command line:

```bash
sudo bash scripts/setup.sh \
  --domain example.com \
  --email you@example.com \
  --admin-user deploy \
  --ssh-key /home/you/.ssh/id_ed25519.pub
```

If DNS has not propagated yet:

```bash
sudo bash scripts/setup.sh --skip-certbot ...
# later, after the A record is live:
sudo bash scripts/setup.sh ...
```

Then **destroy the VM**, create a fresh one and run only `setup.sh`. That is the
real reproducibility test described in the brief.

## 3. Idempotency details

| Situation | Behaviour |
|---|---|
| User already exists | Reused; key file is only rewritten if content changed. |
| Initial password already generated | Kept — no surprise password rotation on re-run. |
| Certificate already exists | Issuance is skipped; hardened TLS config is installed. |
| ufw rule already present | Not duplicated. |
| Config file content identical | Not touched (no needless service restarts). |
| Config file changed | Timestamped `.bak.YYYYmmddHHMMSS` copy is kept. |
| `sshd -t` / `fail2ban-client -t` fails | Change is rolled back before the daemon restarts. |
