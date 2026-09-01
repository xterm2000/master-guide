# Triage: Is an Exposed SSH Host Being Scanned / Brute-Forced?

For a server that has had any SSH port reachable from the internet. Failed
attempts **will** be in the logs within hours of exposure — that is baseline
background noise, not evidence of a problem.

Two questions actually matter:

1. **Did anything ever succeed?** (§2, the `Accepted` check)
2. **Is `PasswordAuthentication no` actually enforced?** If so, brute-force
   volume is cosmetic — it cannot succeed without the private key no matter how
   many attempts are logged. Confirm the *effective* value, not the file:

   ```bash
   sudo sshd -T | grep -Ei 'passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication'
   ```

   (See [`passwordless-login.md`](passwordless-login.md) §5 for why the drop-in
   merge means the file can lie.)

---

## 1. Volume and sources of failed attempts

Service unit is `sshd` on RHEL/Rocky, `ssh` on Debian/Ubuntu.

```bash
# Failed / rejected connections in the last 24h. High volume against random or
# invalid usernames is opportunistic scanning; repeated hits against your ACTUAL
# username suggest targeting rather than a bot sweep.
sudo journalctl -u sshd --since '24 hours ago' \
  | grep -iE 'failed|invalid|not allowed|banner exchange'

# Tally by source IP — a handful of IPs with hundreds of attempts each is
# classic botnet brute-forcing. Extracting the IP by regex is more robust than
# a fixed field position, because the log line format varies by rejection type.
sudo journalctl -u sshd --since '24 hours ago' \
  | grep -iE 'failed|invalid|not allowed|banner exchange' \
  | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' \
  | sort | uniq -c | sort -rn | head -20
```

---

## 2. Successful logins — the one that matters

```bash
sudo journalctl -u sshd --since '7 days ago' | grep -i 'Accepted'
```

Every line should be genuinely you, from a recognised source IP, with the
expected auth method. Example of a healthy line (key/cert auth):

```
Accepted publickey for user from 203.0.113.10 port 51234 ssh2: ED25519-CERT SHA256:... 
```

An `Accepted password` line on a host that is supposed to be key-only is a
red flag — it means password auth was reachable at that time.

---

## 3. fail2ban

```bash
sudo fail2ban-client status          # which jails are active
sudo fail2ban-client status sshd     # ban counts + current ban list for the sshd jail
```

Output shape:

```
Status for the jail: sshd
|- Filter
|  |- Currently failed: 0
|  |- Total failed:     7
|  `- Journal matches:  _SYSTEMD_UNIT=sshd.service + _COMM=sshd + _COMM=sshd-session
`- Actions
   |- Currently banned: 0
   |- Total banned:     1
   `- Banned IP list:
```

A steadily growing `Total banned` confirms both that scanning is continuous and
that fail2ban is actually acting on it. `Currently failed: 0` / `Currently
banned: 0` at a quiet moment is normal. If `Total failed` stays at 0 while the
raw `journalctl` tally in §1 is large, the jail's `Journal matches` / filter
isn't seeing the same lines — check `logpath` / `backend` in the jail config.

---

## 4. Optional: roughly place the noisiest IPs

```bash
sudo dnf install -y GeoIP GeoIP-data      # RHEL/Rocky
geoiplookup 203.0.113.10
```

Context only, **not a security control** — most brute-force traffic originates
from compromised devices and cloud hosting worldwide, not from wherever a human
attacker sits.

---

## 5. Router-side

A consumer mesh/router may have a thin Security / Notifications view showing
blocked intrusion attempts, but its logging depth is far below a real firewall.
Treat host-side logs (`sshd`, `fail2ban`) as the source of truth and the router
UI as a low-detail supplement only.

---

## See Also

- [`passwordless-login.md`](passwordless-login.md) — §5 hardening an exposed SSH port (fail2ban, source allowlist, don't expose consoles)
- [`ssh-ca.md`](ssh-ca.md) — §8 troubleshooting cert auth; §4 revoking a leaked cert
- [`restricted-networks.md`](restricted-networks.md) — the connecting-out side of the same setup
- [`../sysadmin/firewalld.md`](../sysadmin/firewalld.md) — scoping the SSH port to known source networks with a rich rule
