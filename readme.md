# Hardened Linux Web Server

> A bare Ubuntu/Debian VM turned into a safe-to-expose public web server —
> locked down, auto-patching, verifiable from the attacker's side, and
> rebuildable from **one idempotent Bash script**.

![Ubuntu](https://img.shields.io/badge/OS-Ubuntu%20%2F%20Debian-E95420?style=flat-square&logo=linux&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-set%20-euo%20pipefail-4EAA25?style=flat-square&logo=gnubash&logoColor=white)
![nginx](https://img.shields.io/badge/nginx-TLS%201.2%20%2F%201.3-009639?style=flat-square&logo=nginx&logoColor=white)
![SSH](https://img.shields.io/badge/SSH-keys%20only-000000?style=flat-square&logo=openssh&logoColor=white)
![Firewall](https://img.shields.io/badge/ufw-22%20%7C%2080%20%7C%20443-orange?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)

One server, three doors, everything else closed.

---

## What it proves

This is a first-month-of-an-SRE-job project with a deliberately small blast
radius and a high signal-to-noise ratio:

- I can take a **fresh VM** and make it safe to put on the public internet.
- I understand users, permissions, systemd services, firewalls and TLS — not
  just the commands, but why each one exists.
- I **automate instead of clicking**, and the automation survives being run
  twice (`set -euo pipefail`, backups, config tests, no duplicate rules).
- I **verify from the outside** — nmap, SSL Labs, a password login attempt
  that must fail — instead of assuming the config worked.
- I can read `/var/log/auth.log` the next morning and explain what the bots
  tried.

## Features

| Layer | Tool | Implementation |
|---|---|---|
| Access | **sshd** | Non-root admin, key-only auth, root login disabled, no forwarding, `AllowUsers` |
| Network | **ufw** | Default-deny inbound; only 22, 80 and 443 |
| Web | **nginx** | Static site over HTTPS, HTTP→HTTPS redirect, security headers, dedicated `webuser` |
| TLS | **Let's Encrypt / certbot** | Auto-issuing certificate + `certbot.timer` renewal + reload hook |
| Response | **fail2ban** | SSH and nginx jails, ufw bans, 1-week recidive jail |
| Maintenance | **unattended-upgrades** | Daily security patches, unused deps removed, reboots operator-controlled |
| Repeatability | **Bash** | `scripts/setup.sh` — one command, safe to re-run, config-file driven |

## Architecture

```mermaid
flowchart LR
    A[Internet / bots] --> B[Cloud SG<br/>22 · 80 · 443]
    B --> C[ufw<br/>default deny]
    C -->|22| D[sshd<br/>keys only · no root]
    C -->|80| E[nginx<br/>ACME + 301]
    C -->|443| F[nginx TLS<br/>HSTS · CSP · OCSP]
    F --> G[static site<br/>owner: webuser]
    D -. failures .-> H[journal / auth.log]
    H -. reads .-> I[fail2ban]
    I -. bans .-> C
    J[certbot.timer] -. renews .-> F
    K[apt-daily-upgrade.timer] -. patches .-> L[packages]
```

Full rationale and threat model: [`docs/architecture.md`](docs/architecture.md).

## Repository layout

```text
hardened-linux-web-server/
├── scripts/
│   ├── setup.sh                  # orchestrator — the one command you run
│   ├── create-admin.sh           # admin user, key, sudo, lock root
│   ├── configure-ssh.sh          # hardened sshd drop-in + validation
│   ├── configure-firewall.sh     # ufw default-deny + 22/80/443
│   ├── configure-nginx.sh        # webuser, site, certbot, renewal hook
│   ├── configure-fail2ban.sh     # jails, ufw ban action, recidive
│   ├── configure-updates.sh      # unattended-upgrades + apt timers
│   └── lib/common.sh             # logging, idempotent install/render helpers
├── config/
│   ├── example.env               # copy to .env and fill in YOUR values
│   ├── sshd_config               # sshd drop-in template
│   ├── jail.local                # fail2ban jails template
│   ├── nginx-site.conf           # hardened HTTPS server block
│   ├── nginx-bootstrap.conf      # temporary HTTP challenge server
│   └── nginx-ratelimit.conf      # shared rate-limit zones
├── site/index.html               # zero-dependency static landing page
├── tests/verify-server.sh        # local + external security checks
├── docs/
│   ├── architecture.md           # trust boundaries and design decisions
│   ├── installation.md           # manual walkthrough + script usage
│   ├── security-hardening.md     # every setting explained
│   ├── verification.md           # nmap / SSL Labs / auth.log + results table
│   └── troubleshooting.md        # "I locked myself out" and friends
├── screenshots/                  # your evidence images go here
├── Makefile                      # make verify / lint / help
└── .github/workflows/lint.yml    # ShellCheck in CI
```

## Quick start

```bash
git clone https://github.com/adarshtmg2060/hardened-linux-web-server.git
cd hardened-linux-web-server

cp config/example.env config/.env
nano config/.env                       # DOMAIN, LE_EMAIL, ADMIN_USER, key path

sudo bash scripts/setup.sh
```

Everything can also be passed as flags:

```bash
sudo bash scripts/setup.sh \
  --domain your.domain.com \
  --email you@example.com \
  --admin-user deploy \
  --ssh-key ~/.ssh/id_ed25519.pub
```

The domain's A record must already point at the VM. If it does not yet:

```bash
sudo bash scripts/setup.sh --skip-certbot
# ... DNS propagates ...
sudo bash scripts/setup.sh             # re-run adds the certificate
```

Then do the real reproducibility test: **destroy the VM, create a new one and
run only `setup.sh`.**

See [`docs/installation.md`](docs/installation.md) for the original
command-by-command notes the script was distilled from.

## Verify it

From your own machine — not the server:

```bash
nmap -Pn -T4 --top-ports 200 <your-ip>
curl -sI http://<your-domain>                      # 301
curl -sI https://<your-domain>                     # 200 + HSTS/CSP
ssh -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no <admin>@<your-ip>    # must be denied
```

SSL Labs: <https://www.ssllabs.com/ssltest/analyze.html>

Automated checks:

```bash
sudo bash tests/verify-server.sh --local  --domain <your-domain>
bash tests/verify-server.sh --remote --host <your-ip> \
     --domain <your-domain> --admin-user deploy --ssh-key ~/.ssh/id_ed25519
```

After a day, count what the bots tried:

```bash
sudo grep -c "Failed password" /var/log/auth.log
sudo grep -c "Invalid user"    /var/log/auth.log
sudo fail2ban-client status sshd
```

Fill your own figures into the table in
[`docs/verification.md`](docs/verification.md).

## Results (example layout — replace with your own numbers)

| Check | Expected | Your result |
|---|---|---|
| Open ports | `22, 80, 443` | `___` |
| SSL Labs grade | `A` / `A+` | `___` |
| Password SSH login | `Permission denied` | `___` |
| Root SSH login | `Permission denied` | `___` |
| Failed passwords / 24 h | depends on your IP | `___` |
| Banned IPs | fail2ban `Total banned` | `___` |
| Rebuild from script | passed | `___` |

## CV line

> Built and hardened a public Linux web server (key-only SSH, ufw firewall,
> fail2ban, auto-renewing TLS, unattended upgrades), fully reproducible from a
> single idempotent Bash script. Verified externally with nmap, SSL Labs and
> forced password-login failures; quantified ~___ break-in attempts/day from
> `auth.log`.

## Next steps (if I kept going)

- SSH certificate authority / hardware keys instead of static authorized_keys
- Centralised logging (journald → Loki) and alerting on ban spikes
- Terraform for the VM + cloud security group, making the *whole* stack code
- WAF/CDN in front of nginx, plus HTTP/3 and OCSP must-staple
- Off-site backups and a documented restore drill

## License

MIT — see [`LICENSE`](LICENSE). Use the code, keep the attribution.
