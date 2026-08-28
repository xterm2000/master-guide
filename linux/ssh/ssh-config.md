The `~/.ssh/config` file lets you define per-host SSH settings so you don't have to type long options every time. Here are the most common parameters:

---

## Basic Structure

```
Host <alias>
    Parameter value
    Parameter value
```

---

## Most Common Parameters

### Identity & Authentication

- **`IdentityFile`** - path to the private key (`~/.ssh/id_rsa`, `~/.ssh/id_ed25519`)
- **`CertificateFile`** - path to a CA-signed cert (`~/.ssh/id_ed25519-cert.pub`); usually auto-detected when it sits beside `IdentityFile` with the matching basename, explicit here for clarity
- **`User`** - username to connect as
- **`IdentitiesOnly yes`** - only use keys specified in config, not the SSH agent. An agent-loaded key is otherwise offered to **every** host; pair this with an explicit `IdentityFile` to send only the named key (and to stay under the server's `MaxAuthTries` when the agent holds many keys)
- **`AddKeysToAgent yes`** - `ssh` adds the key to a running `ssh-agent` on first use, "as if by ssh-add(1)" - type a passphrase once per boot, and the matching `*-cert.pub` is pulled in alongside it. `ask` / `confirm` prompt first

### Connection

- **`HostName`** - the actual hostname or IP (when your `Host` alias differs)
- **`Port`** - remote port (default: 22)
- **`ProxyJump`** - jump through a bastion host (`user@bastion.example.com`)
- **`ProxyCommand`** - older alternative to ProxyJump for custom proxy commands

### Keep-Alive & Stability

- **`ServerAliveInterval`** - seconds between keep-alive pings (e.g. `60`)
- **`ServerAliveCountMax`** - how many missed pings before disconnect (e.g. `3`)
- **`TCPKeepAlive yes`** - enables TCP-level keep-alives

### Multiplexing (speeds up repeated connections)

- **`ControlMaster auto`** - reuse existing connections
- **`ControlPath ~/.ssh/cm-%r@%h:%p`** - socket path for shared connections
- **`ControlPersist 10m`** - keep master connection open for 10 minutes after last use

### Host Checking

- **`StrictHostKeyChecking ask`** - prompt on unknown hosts (`yes` / `no` / `ask`)
- **`UserKnownHostsFile`** - custom known_hosts file path

### Forwarding

- **`ForwardAgent yes`** - forward your SSH agent (use cautiously)
- **`ForwardX11 yes`** - enable X11 GUI forwarding
- **`LocalForward`** - tunnel a local port to a remote one (`8080 localhost:80`)
- **`RemoteForward`** - expose a local port on the remote side

---

## Practical Example

```ssh-config
# Default settings for all hosts
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    IdentitiesOnly yes
    AddKeysToAgent yes

# Personal GitHub
Host github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github

# Work server via bastion
Host work-app
    HostName 10.0.1.50
    User deploy
    Port 22
    IdentityFile ~/.ssh/id_rsa_work
    ProxyJump bastion.work.com
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m

# Local dev VM
Host devbox
    HostName 192.168.1.100
    User vagrant
    Port 2222
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

---

### A few tips

- `Host *` applies to **all** connections and is great for global defaults.
- More specific `Host` blocks override `Host *` - order matters, first match wins per parameter.
- A `Host <alias>` block matches only the **literal string** you pass to `ssh`.
  `ssh myhost` matches `Host myhost`; `ssh 192.0.2.10` or `ssh box.example.com`
  does **not** - so that block's `IdentityFile` / `User` / `Port` silently
  don't apply. Connect via the alias, or pass `-i` / `-p` / `user@` explicitly.
- Run `ssh -vvv hostname` to debug which config values are actually being applied.
- Permissions matter: the file should be `chmod 600 ~/.ssh/config`.

## See Also

This file covers *connection* config (host aliases, jump hosts, keep-alive).
For key generation/distribution and passwordless sudo, see:

- [`ssh-key-distribution.md`](ssh-key-distribution.md)
- [`passwordless-sudo.md`](passwordless-sudo.md)
- [`node-connect.md`](node-connect.md) — this repo's node-map + connect script, which pairs with `ProxyJump`/`Host` blocks defined here
- [`dynamic-ip-access.md`](dynamic-ip-access.md) — DDNS / mesh VPN for a host whose public IP changes
- [`passwordless-login.md`](passwordless-login.md) §6 — offering a CA cert with no per-host config via `ssh-agent`