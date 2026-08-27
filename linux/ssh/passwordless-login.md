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

## 5. Optional hardening: disable password auth

Once key login is confirmed working, stop the server accepting passwords at all.

**Keep your current SSH session open** and test key login in a second terminal
before and after — a mistake here can lock you out.

Drop-in file (preferred over editing `/etc/ssh/sshd_config` directly):

```bash
sudo tee /etc/ssh/sshd_config.d/50-no-passwords.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
sudo sshd -t && sudo systemctl restart sshd
```

`sshd -t` validates config before the restart. On Rocky/RHEL the service is
`sshd`; on Debian/Ubuntu it's `ssh`.

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

## Troubleshooting

- `ssh -v user@server` — verbose handshake; shows which keys are offered and why
  each is rejected.
- Still prompted for a password → permissions on the server: `~/.ssh` must be
  700, `authorized_keys` 600, `$HOME` not group-writable.
- SELinux (Rocky/RHEL) after manually creating `~/.ssh`:
  `restorecon -R -v ~/.ssh` to fix the file context.
- Wrong key offered → point at it explicitly: `ssh -i ~/.ssh/id_ed25519 user@server`,
  or set `IdentityFile` in `~/.ssh/config`.

## See Also

- [`ssh-key-distribution.md`](ssh-key-distribution.md) — same idea across many nodes at once
- [`ssh-config.md`](ssh-config.md) — `~/.ssh/config` client options
- [`ssh-ca.md`](ssh-ca.md) — CA-signed certificates instead of per-host `authorized_keys` entries
- [`passwordless-sudo.md`](passwordless-sudo.md) — removing the *sudo* password prompt (separate topic)
- [`windows-key-permissions.md`](windows-key-permissions.md) — locking down the private key on a Windows client
