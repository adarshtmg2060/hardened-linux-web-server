# Screenshots

This folder is intentionally empty in the repo — add **your own** captures here
after you build the server. Do not commit secrets, IPs you do not own, or the
contents of `config/.env`.

Suggested evidence (matches the checks in `docs/verification.md`):

| File name | What to capture |
|---|---|
| `01-nmap.png` | `nmap -Pn -T4 --top-ports 200 <ip>` showing **only** 22, 80, 443 |
| `02-ssl-labs.png` | SSL Labs report for your domain (grade + TLS 1.2/1.3 + HSTS) |
| `03-password-denied.png` | Terminal showing `Permission denied (publickey)` for a password attempt |
| `04-key-login.png` | Successful `ssh -i ... deploy@<domain>` session |
| `05-ufw.png` | `sudo ufw status verbose` |
| `06-fail2ban.png` | `sudo fail2ban-client status sshd` with a non-zero banned count |
| `07-authlog.png` | `grep "Failed password" /var/log/auth.log | head` |
| `08-certbot-timer.png` | `systemctl status certbot.timer` and `certbot renew --dry-run` tail |
| `09-site.png` | Browser view of `https://<domain>` served over HTTPS |
| `10-rebuild.png` | Fresh VM running `sudo bash scripts/setup.sh` end to end |

Then reference them from the README, e.g.:

```markdown
![Open ports](screenshots/01-nmap.png)
```
