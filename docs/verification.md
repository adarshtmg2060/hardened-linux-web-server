# Verification (the attacker's view)

> Part of the [main README](../readme.md) · [Screenshot evidence](../screenshots/README.md) — each check below has a matching capture.

"Assume nothing, test from outside." Do these from a **different machine**, not
from the server itself. Fill in the Results table with your own numbers.

## 1. Open ports — nmap

```bash
nmap -Pn -T4 --top-ports 200 <your-ip>
# deeper (slow) sweep if you want to be thorough:
nmap -Pn -sT -T4 -p 1-65535 --open <your-ip>
```

Expected: **only** `22/tcp`, `80/tcp` and `443/tcp` open. Everything else
filtered/closed. If a cloud security group is misconfigured, this is where it
shows up even before ufw is involved.

## 2. Certificate — SSL Labs

```text
https://www.ssllabs.com/ssltest/analyze.html?d=<your-domain>
```

Expected: grade A or A+, valid chain, TLS 1.2/1.3 only, HSTS `yes`,
OCSP stapling `yes`. Quick local equivalent:

```bash
echo | openssl s_client -connect <your-domain>:443 -servername <your-domain> 2>/dev/null \
  | openssl x509 -noout -dates -subject -issuer
```

Renewal check (the "does it really renew itself" question):

```bash
sudo certbot renew --dry-run
systemctl status certbot.timer
```

## 3. Password login must fail

From your laptop:

```bash
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    -o NumberOfPasswordPrompts=1 <admin-user>@<your-ip>
# expected: Permission denied (publickey).

ssh -i ~/.ssh/id_ed25519 <admin-user>@<your-ip>
# expected: successful login
```

Also try as root: `ssh root@<your-ip>` — expected: `Permission denied (publickey).`

## 4. Headers and redirect

```bash
curl -sI http://<your-domain>          # expect 301 -> https
curl -sI https://<your-domain>         # expect 200 + HSTS/CSP headers
curl -s  https://<your-domain>/healthz # expect: ok
```

## 5. Read auth.log after a day

This is the "how noisy is the internet" moment worth capturing for your CV:

```bash
sudo grep -c "Failed password" /var/log/auth.log
sudo grep -c "Invalid user" /var/log/auth.log
sudo grep "Failed password" /var/log/auth.log | awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head
sudo fail2ban-client status sshd
```

If journald-only:

```bash
journalctl -u ssh --since "24 hours ago" | grep -c "Failed password"
```

## 6. Run the provided checker

```bash
# full local audit (on the server)
sudo bash tests/verify-server.sh --local --domain <your-domain>

# external audit (on your laptop)
bash tests/verify-server.sh --remote --host <your-ip> --domain <your-domain> \
    --admin-user <admin-user> --ssh-key ~/.ssh/id_ed25519
```

It exits non-zero if any check fails, so you can paste it into CI later.

## Results (fill with YOUR numbers)

| Check | Command | Result |
|---|---|---|
| Open ports | `nmap -Pn --top-ports 200` | `22, 80, 443` |
| SSL Labs grade | SSL Labs link | `A` |
| Password SSH login | `ssh -o PreferredAuthentications=password ...` | `Permission denied` |
| Root SSH login | `ssh root@<ip>` | `Permission denied` |
| HTTP → HTTPS | `curl -sI http://...` | `301` |
| Failed passwords / 24 h | `grep -c 'Failed password' /var/log/auth.log` | `___` |
| Invalid users / 24 h | `grep -c 'Invalid user' /var/log/auth.log` | `___` |
| IPs banned by fail2ban | `fail2ban-client status sshd` | `___` |
| Rebuild from script | destroy VM → `setup.sh` | `passed` |
