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
- **`User`** - username to connect as
- **`IdentitiesOnly yes`** - only use keys specified in config, not the SSH agent

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
- Run `ssh -vvv hostname` to debug which config values are actually being applied.
- Permissions matter: the file should be `chmod 600 ~/.ssh/config`.