# Passwordless SSH Login (single host, from scratch)

Set up key-based login to **one** remote server, with no repo/cluster context.
For provisioning a whole fleet of nodes at once, see
[`ssh-key-distribution.md`](ssh-key-distribution.md) — this doc is the minimal
single-host version.

## The SSH files, and where they live

Two separate scopes. Per-user files under `~/.ssh/` say *who* may log in and how
*you* connect out; system-wide files under `/etc/ssh/` configure the daemon and
the client defaults for everyone.

| File | Scope | Side | Purpose |
|---|---|---|---|
| `~/.ssh/authorized_keys` | per-user | server | Public keys allowed to log in **as that user**. One key per line (+ optional restrictions). This is the "guest list" you edit to grant access. Must be `600`, with `~/.ssh` `700` and `$HOME` not group-writable, or sshd ignores it. |
| `~/.ssh/id_ed25519` / `.pub` | per-user | client | Your private key (never leaves the client) and its public half. |
| `~/.ssh/config` | per-user | client | Per-host connection settings (aliases, `User`, `IdentityFile`, `ProxyJump`…). See [`ssh-config.md`](ssh-config.md). |
| `~/.ssh/known_hosts` | per-user | client | Host keys this account has accepted before — drives the "authenticity of host" prompt. |
| `/etc/ssh/sshd_config` | system | server | The **server rulebook**: port, `PermitRootLogin`, `PasswordAuthentication`, where to find `authorized_keys`, CA trust, etc. Admin-only. Drop-ins in `/etc/ssh/sshd_config.d/` override it. |
| `/etc/ssh/ssh_config` | system | client | Default `ssh` client settings for this machine when *it* connects out. `~/.ssh/config` overrides it per-user. Drop-ins in `/etc/ssh/ssh_config.d/`. |
| `/etc/ssh/ssh_host_*_key` / `.pub` | system | server | The server's own identity keys — what it presents to prove itself to clients (and what a client records in `known_hosts`). Generated once at install. |

So `sshd_config` sets the rules of the game (is key auth even allowed, what
port); `authorized_keys` is the actual guest list for one account. The rest of
this doc is about populating that guest list without a password.

## Concept

Password auth sends your password to the server on every login. Public-key auth
replaces that with a **key pair**:

- the **private key** stays on your client (`~/.ssh/id_ed25519`) and never leaves it
- the **public key** is appended to the server's `~/.ssh/authorized_keys`

At login the server picks a public key from that file and challenges the client
to prove it holds the matching private key. If it can, you're in — no password
sent. You still type your key's passphrase (if it has one), but that's handled
locally by `ssh-agent`, not transmitted.

## 1. Client: generate a key

Skip if `~/.ssh/id_ed25519` already exists — reuse it.

```bash
ssh-keygen -t ed25519 -C "$USER@$(hostname)"
```

- `-t ed25519` — modern, short, fast. (`ssh -Q key` lists what your build supports.)
- Prompts for a file path (default `~/.ssh/id_ed25519`) and a passphrase.
- A passphrase encrypts the private key at rest — recommended. For an
  unattended/automation key use `-N ""` to skip it.
- Produces `id_ed25519` (private, mode 600) and `id_ed25519.pub` (public).

## 2. Copy the public key to the server

`ssh-copy-id` does it in one step — this is the **one time** you type the
remote password:

```bash
ssh-copy-id user@server
```

It logs in via password, creates `~/.ssh` (700) and `~/.ssh/authorized_keys`
(600) on the server if needed, and appends your public key — skipping keys
already present.

Manual equivalent, if `ssh-copy-id` isn't available:

```bash
cat ~/.ssh/id_ed25519.pub | ssh user@server \
  'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

Permissions matter: sshd **ignores** `authorized_keys` if `~/.ssh` or the file
is group/other-writable, or if the home directory itself is group-writable.

## 3. Test

```bash
ssh user@server              # should drop you in with no password prompt
ssh -o BatchMode=yes user@server true && echo OK   # scriptable check: no prompt allowed
```

`BatchMode=yes` disables all interactive prompts, so this fails fast rather than
silently falling back to a password.

## 4. Optional: `~/.ssh/config` alias

So it's just `ssh server`:

```
Host server
    HostName 192.0.2.10
    User youruser
    IdentityFile ~/.ssh/id_ed25519
```

See [`ssh-config.md`](ssh-config.md) for more.

## 5. Optional hardening: lock the server down

Once key login is confirmed working, close every method you don't use.

**Keep your current SSH session open** and test key login in a second terminal
before and after — a mistake here can lock you out.

### Auth methods are independent toggles

At connect time `sshd` advertises a *list* of methods it will accept — you can
see it in `ssh -v` output:

```
Authentications that can continue: publickey,gssapi-keyex,gssapi-with-mic,password
```

The client tries them in turn until one works. **Each method has its own on/off
switch, and enabling one never disables another.** Turning on
`PubkeyAuthentication` does nothing to `PasswordAuthentication` — if you don't
explicitly set `PasswordAuthentication no`, the server still accepts passwords
and the brute-force bots still get their guesses. You have to close each door
you don't want.

### The drop-in file

```bash
sudo tee /etc/ssh/sshd_config.d/50-hardening.conf <<'EOF'
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
GSSAPIAuthentication no
EOF
sudo sshd -t && sudo systemctl restart sshd
```

| Directive | Effect |
|---|---|
| `PermitRootLogin no` | `root` may not log in over SSH by any method. `root` is the one username guaranteed to exist on every Linux box — the #1 brute-force target. Log in as a normal user, then `sudo`. (Other values: `prohibit-password` = key only, `forced-commands-only` = automation only.) |
| `PubkeyAuthentication yes` | Accept public-key / CA-cert auth. Already the default; stating it makes the policy explicit and survives a future default change. |
| `PasswordAuthentication no` | Refuse password auth — the method that sends a guessable shared secret and that every SSH scanner targets. |
| `KbdInteractiveAuthentication no` | Disables the *second* password-capable channel (generic PAM `keyboard-interactive`). Disabling `PasswordAuthentication` alone can leave this route open. Re-enable deliberately if you later add TOTP/2FA. |
| `GSSAPIAuthentication no` | Kerberos SSO (Active Directory / MIT realms). If you have no realm it can never succeed, but it's still an exposed code path plus handshake round-trips. The pile of other `gssapi*` lines in `sshd -T` go inert once this is off. |

### Drop-in precedence

`/etc/ssh/sshd_config` on Rocky/RHEL has `Include /etc/ssh/sshd_config.d/*.conf`
at the **top** of the file. Per `sshd_config(5)`, "the first obtained value for
each parameter is used" — so a value set in a drop-in is read before the
defaults lower in `sshd_config` and wins. (This is unrelated to `ssh_config`'s
"first matching `Host` block" rule, and it's the opposite of the "last wins"
people often assume.)

- Keep **all** your SSH policy in one drop-in file. Overlapping files
  (`50-no-passwords.conf` *and* `50-hardening.conf` both setting
  `PasswordAuthentication`) make the effective value ambiguous — the first file
  read by glob order wins and the later one is silently ignored.
- Always confirm the merged result, not the file contents:
  ```bash
  sudo sshd -T | grep -Ei 'permitrootlogin|pubkeyauth|passwordauth|kbdinteractive|gssapiauth'
  ```
  `sshd -T` dumps the fully-merged effective config. `sshd -t` (no capital)
  just validates syntax — run it before every restart.

`sshd -t` validates config before the restart. On Rocky/RHEL the service is
`sshd`; on Debian/Ubuntu it's `ssh`.

### If the VM is exposed to the internet

Key-only auth already stops the brute-force bots, but an exposed sshd still gets
scanned continuously. Add:

- **fail2ban** (or a firewalld ipset) to ban IPs after repeated failures — cuts
  log noise and load even though cert auth blocks them anyway.
- **Source-IP allowlist** on the SSH port if you always connect from known
  networks — a firewall rule beats everything else here.
- **Don't expose management consoles.** Check `sudo ss -tlnp` and
  `sudo firewall-cmd --list-all` — e.g. the Cockpit web console on `:9090`
  should not be internet-reachable.
- **Patch automatically** (`dnf-automatic`) since it's exposed.
- A **non-standard port** (2222 etc.) reduces log volume only — it is not a
  security control.
- **Don't port-forward other services** (databases especially) — keep them on
  `localhost` and tunnel them through SSH: [`port-forwarding.md`](port-forwarding.md).
- **Check periodically whether anything got in.** Failed attempts are
  guaranteed background noise; what matters is whether any login *succeeded* and
  whether password auth is really off: [`ssh-scanning-triage.md`](ssh-scanning-triage.md).

## 6. Alternative: CA-signed certificate instead of `authorized_keys`

Steps 2–3 copy your public key onto every server's `authorized_keys`. With a
**user CA** you instead sign your key once, and each server trusts the CA — no
per-key entry anywhere. Worth it when you have more than a handful of servers,
or want logins that expire on their own. Full command reference (restrictions,
revocation, host certs) is in [`ssh-ca.md`](ssh-ca.md); this is just what goes
where.

Three roles: the **CA host** (where signing happens — can be your workstation),
the **client** you SSH *from*, the **server** you SSH *to*.

| File | Lives on | Notes |
|---|---|---|
| `ca_user_key` (CA **private** key) | **CA host only** | Never copy to client or server. Passphrase-protect it — it can mint a login for anyone. |
| `ca_user_key.pub` (CA **public** key) | **Server** → `/etc/ssh/ca_user_key.pub` | The trust anchor. Referenced by `TrustedUserCAKeys` in `sshd_config`. |
| `id_ed25519` (your private key) | **Client** → `~/.ssh/` | Generated in step 1. |
| `id_ed25519.pub` (your public key) | **Client**; also sent **to the CA host** to be signed | Not needed on the server. |
| `id_ed25519-cert.pub` (the certificate) | **Client** → `~/.ssh/`, beside the private key | Produced by `ssh-keygen -s` on the CA host, copied back. `ssh` auto-loads it when it shares the private key's basename. |

**Flow:**

```bash
# 1. Client — generate your key (same as step 1 above), then send id_ed25519.pub to the CA host.

# 2. CA host — one-time: create the CA keypair.
ssh-keygen -t ed25519 -f ~/.ssh/ca_user_key -C "user-ssh-ca"

# 3. CA host — sign the client's public key.
ssh-keygen -s ~/.ssh/ca_user_key \
  -I "youruser-laptop" \       # key ID, logged server-side on each login
  -n "youruser" \              # principals: usernames this cert may log in as
  -V +52w \                    # validity window (omit = never expires)
  -z 1 \                       # serial, needed to revoke this exact cert later
  id_ed25519.pub               # -> produces id_ed25519-cert.pub
# Copy id_ed25519-cert.pub back to the client's ~/.ssh/.

# 4. Server — one-time: install the CA public key and trust it.
sudo cp ca_user_key.pub /etc/ssh/ca_user_key.pub
sudo tee /etc/ssh/sshd_config.d/60-user-ca.conf <<'EOF'
TrustedUserCAKeys /etc/ssh/ca_user_key.pub
EOF
sudo sshd -t && sudo systemctl restart sshd

# 5. Client — log in. No authorized_keys entry anywhere.
ssh youruser@server
```

The server accepts any cert signed by `ca_user_key.pub` whose principals list
includes the target username. To decouple the two, add
`AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u` and list allowed
principal names there instead.

Host certificates (server proves itself to the client, killing the
`known_hosts` TOFU prompt) work the same way in reverse — use a **separate** CA
keypair; see [`ssh-ca.md`](ssh-ca.md) §2, §5.

**The CA-pubkey filename is arbitrary.** `ca_user_key.pub` is just a
convention — it could be `aqualabs-ca.pub` or anything else. What must line up
is three things: the file on disk, the path in `TrustedUserCAKeys`, and the
cert's `Signing CA` fingerprint (`ssh-keygen -L -f <cert>` vs
`ssh-keygen -l -f <the file TrustedUserCAKeys points at>`). A renamed or
stale file here means every cert is silently rejected and login falls through
to a password prompt. Also: `/etc/ssh/ca_user_key.pub` must be world-readable
(`644`) or `sshd` can't read it after dropping privileges.

**Keep the CA _private_ key off any internet-exposed server.** Signing happens
on a workstation or an offline host; only the CA *public* key belongs on the
servers.

### What happens when the cert expires

Not a permanent lockout. The server trusts the *CA*, not the individual cert,
so you just mint a fresh one over the **same public key** and swap the file on
the client — no server-side change:

```bash
ssh-keygen -s ~/.ssh/ca_user_key -I "youruser-laptop" -n youruser -V +52w -z 2 \
  id_ed25519.pub          # -> new id_ed25519-cert.pub, copy it over the old one
```

You're only truly locked out if you *also* lose the CA private key and left no
other way in. Keep one break-glass route (a plain `authorized_keys` key stored
offline, or console access) and re-sign a few weeks before expiry, not after.

### Using the cert without per-host config (ssh-agent)

> For the agent itself — `ssh-add` flags, key lifetimes, `systemd --user`, agent
> forwarding vs `ProxyJump` — see [`ssh-agent.md`](ssh-agent.md). This section
> only covers how the agent gets a CA cert offered with no per-host config.

`ssh` **always** attaches `<key>-cert.pub` automatically when it uses `<key>`,
as long as the two files share a basename and directory (`id_shiva` +
`id_shiva-cert.pub`). So the cert is never the thing you have to wire up — the
only question is how `ssh` decides to *try that key* when there's no
`IdentityFile` line for the host. Three ways, roughly increasing in scope:

| Method | What it does | Scope |
|---|---|---|
| `ssh-add ~/.ssh/id_shiva` | Loads key **and** cert into `ssh-agent`; agent offers them on every connection | all hosts |
| Name the key `id_ed25519` | `ssh` auto-tries the standard basenames for every host with zero config | all hosts |
| `Host *` / `IdentityFile ~/.ssh/id_shiva` | One global config line, no per-host block | all hosts |

**Why `ssh-add` also loads the cert:** per `ssh-add(1)`, "after loading a
private key, ssh-add will try to load corresponding certificate information
from the filename obtained by appending `-cert.pub` to the name of the private
key file." Confirm with `ssh-add -L` — a loaded cert shows as
`ssh-ed25519-cert-v01@openssh.com`.

**Windows** — the agent service ships disabled:

```powershell
Set-Service ssh-agent -StartupType Automatic
Start-Service ssh-agent
ssh-add C:\Users\mitek\.ssh\id_shiva     # pulls in id_shiva-cert.pub too
ssh-add -l                                # or -L to see the cert
```

Once `StartupType` is `Automatic` the agent (and its loaded keys) survive a
reboot — Windows persists agent contents in the registry, unlike Linux.

**Linux** — the agent is per-session. Options:

- `eval "$(ssh-agent)"` then `ssh-add ~/.ssh/id_shiva` in your shell rc
- `AddKeysToAgent yes` in `~/.ssh/config` — `ssh` adds the key to a running
  agent on first use, "as if by ssh-add(1)" (`ssh_config(5)`); the adjacent
  cert comes along
- a `systemd --user` service running `ssh-agent`

**Tradeoff:** the agent (and the default-filename trick) offer this cert to
*every* server you SSH to, not just shiva. That's harmless — a server that
doesn't trust `aqualabs-ca` just ignores an identity it can't verify — but
each offered identity counts against the server's `MaxAuthTries` (default 6),
so a large agent can get you disconnected before the *right* key is tried. If
that bites, scope it back: `IdentitiesOnly yes` plus an explicit
`IdentityFile` per `Host` block makes `ssh` send only the named key even when
the agent holds more.

For the other half of a config-free setup — a stable name when the server's
public IP keeps changing — see
[`dynamic-ip-access.md`](dynamic-ip-access.md).

## Troubleshooting

- `ssh -v user@server` — verbose handshake; shows which keys are offered and why
  each is rejected.
- Still prompted for a password → permissions on the server: `~/.ssh` must be
  700, `authorized_keys` 600, `$HOME` not group-writable.
- SELinux (Rocky/RHEL) after manually creating `~/.ssh`:
  `restorecon -R -v ~/.ssh` to fix the file context.
- Wrong key offered → point at it explicitly: `ssh -i ~/.ssh/id_ed25519 user@server`,
  or set `IdentityFile` in `~/.ssh/config`.
- **Key never even tried** (`ssh -v` `Will attempt key:` list shows only the
  default names, all `type -1`) → a non-standard filename like `id_shiva` is
  used *only* when named by `IdentityFile` or `-i`. And `ssh <ip>` /
  `ssh <rawhostname>` does **not** match a `Host <alias>` block — the alias
  matches only the literal string you type — so that block's `IdentityFile`,
  `User`, `Port` never apply. Use the alias, or pass `-i` / `-p` / `user@`
  explicitly.
- **CA cert offered but silently rejected, login falls to password** → work
  through, on the server:
  - `sudo sshd -T | grep -Ei 'trusteduserca|pubkeyauth|authorizedprincipalsfile|revokedkeys'`
    — `trustedusercakeys` must be set; `revokedkeys` pointing at an unreadable
    file makes sshd reject *all* pubkey auth.
  - `ssh-keygen -L -f <cert>` — `Principals` must contain the login username
    (required when `authorizedprincipalsfile none`); `Valid` window must be
    current; note the `Signing CA` fingerprint.
  - `sudo ssh-keygen -l -f <path from TrustedUserCAKeys>` — its fingerprint
    must equal the cert's `Signing CA`. A renamed/stale CA file is the classic
    cause.
  - `sudo journalctl -u sshd --since "10 min ago" | grep -iE 'cert|principal|invalid'`
    — gives the exact rejection reason.
  - If sshd listens on a non-standard port, `sudo ss -tlnp | grep <port>` — it
    may be a container or a second sshd with its own config that never saw
    `TrustedUserCAKeys` (`sshd -T` with no `-f` reads only the default
    `/etc/ssh/sshd_config`).

## See Also

- [`ssh-key-distribution.md`](ssh-key-distribution.md) — same idea across many nodes at once
- [`ssh-config.md`](ssh-config.md) — `~/.ssh/config` client options
- [`dynamic-ip-access.md`](dynamic-ip-access.md) — reaching a host whose public IP keeps changing (DDNS, mesh VPN)
- [`ssh-ca.md`](ssh-ca.md) — CA-signed certificates instead of per-host `authorized_keys` entries
- [`port-forwarding.md`](port-forwarding.md) — tunnelling services instead of exposing their ports
- [`ssh-scanning-triage.md`](ssh-scanning-triage.md) — checking an exposed host for scan / brute-force activity
- [`restricted-networks.md`](restricted-networks.md) — connecting out when the network blocks or intercepts SSH
- [`passwordless-sudo.md`](passwordless-sudo.md) — removing the *sudo* password prompt (separate topic)
- [`windows-key-permissions.md`](windows-key-permissions.md) — locking down the private key on a Windows client
