# `ssh-agent` & `ssh-add`

`ssh-agent` is a small background daemon that holds your **decrypted** private
keys in memory and does the signing for every SSH client you run, so you type a
key's passphrase once per session instead of once per connection. `ssh-add`
is the command that loads, lists, and removes keys from it.

Verified on Rocky Linux 10.2, OpenSSH_9.9p1.

---

## What it actually does

1. You start `ssh-agent`. It creates a Unix-domain socket and prints the path
   in `SSH_AUTH_SOCK` (plus its PID in `SSH_AGENT_PID`).
2. `ssh-add ~/.ssh/id_ed25519` reads the key file, prompts once for its
   passphrase, and hands the **unlocked** key to the agent. The key now lives
   only in the agent's memory.
3. Any `ssh` / `scp` / `sftp` / `git` / `rsync -e ssh` / `ansible` process that
   inherits `SSH_AUTH_SOCK` asks the agent to authenticate. When a server sends
   its challenge, `ssh` forwards it to the agent, the agent signs it with the
   in-memory key, and `ssh` relays the signature back.

The private key material never leaves the agent — clients only ever get
signatures. That is also why **agent forwarding is risky** (see below): anyone
who can reach the socket can ask it to sign, even though they can't read the key.

`ssh-add` also loads the matching certificate: "after loading a private key,
ssh-add will try to load corresponding certificate information from the filename
obtained by appending `-cert.pub`" (`ssh-add(1)`). So `id_shiva` +
`id_shiva-cert.pub` come in together — confirm with `ssh-add -L`, where a cert
shows as `ssh-ed25519-cert-v01@openssh.com`.

---

## Use cases

| You want to… | The agent gives you |
|---|---|
| Stop typing a key passphrase on every `ssh` / `git push` | Keep a passphrase on the key (good practice), unlock it once per boot |
| Reach a private host *through* a bastion without putting keys on the bastion | Agent forwarding, or better, `ProxyJump` (below) |
| Use a CA private key to sign certs without decrypting the file each time | `ssh-add ~/.ssh/ca_user_key`, then `ssh-keygen -Us …` / `ssh-keygen -Y sign` — see [`ssh-ca.md`](ssh-ca.md) §3 (`-U` — CA key held in ssh-agent) |
| Offer a CA-signed cert to hosts with no per-host `~/.ssh/config` block | Agent auto-offers every loaded identity — see [`passwordless-login.md`](passwordless-login.md) §6 |
| Hardware-backed keys (FIDO / smartcard) | `ssh-add -K` (resident FIDO keys), `ssh-add -s <pkcs11.so>` (smartcard) |

---

## Starting the agent

### Linux — per-session by default

The agent dies with your login session; keys do not survive a reboot.

- **`AddKeysToAgent yes` in `~/.ssh/config`** — the low-effort path. `ssh` adds a
  key to a running agent the first time it uses it, "as if by ssh-add(1)"
  (`ssh_config(5)`). You still need an agent running (most desktops start one;
  headless boxes usually don't).
- **`eval "$(ssh-agent)"`** in your shell rc — starts one and exports
  `SSH_AUTH_SOCK` / `SSH_AGENT_PID` into the shell. Downside: one agent per
  shell unless you cache the socket path.
- **`systemd --user` service** — one agent for the whole user session, survives
  individual shells:

  ```ini
  # ~/.config/systemd/user/ssh-agent.service
  [Service]
  ExecStart=/usr/bin/ssh-agent -D -a %t/ssh-agent.socket
  [Install]
  WantedBy=default.target
  ```

  ```bash
  systemctl --user enable --now ssh-agent
  # add to ~/.ssh/config or shell rc:
  #   export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"
  ```

### Windows — persistent service

The `ssh-agent` service ships **disabled**; once enabled it persists keys across
reboots in the registry (unlike Linux):

```powershell
Set-Service ssh-agent -StartupType Automatic
Start-Service ssh-agent
ssh-add C:\Users\<user>\.ssh\id_ed25519
```

See [`passwordless-login.md`](passwordless-login.md) §6 for the full Windows
walk-through.

### Kill an agent

```bash
ssh-agent -k        # kills the one named by $SSH_AGENT_PID
pkill ssh-agent     # blunt: all of them for this user
```

---

## `ssh-add` reference

| Command | Effect |
|---|---|
| `ssh-add` | Add the default keys (`~/.ssh/id_rsa`, `id_ecdsa`, `id_ed25519`, `id_ecdsa_sk`, `id_ed25519_sk`) |
| `ssh-add ~/.ssh/id_shiva` | Add a specific key (and its `-cert.pub`) |
| `ssh-add -l` | List loaded identities by **fingerprint** |
| `ssh-add -L` | List loaded identities as full public keys / certs (paste-able into `authorized_keys`) |
| `ssh-add -d ~/.ssh/id_shiva` | Remove one key from the agent |
| `ssh-add -D` | Remove **all** keys |
| `ssh-add -t 1h ~/.ssh/id_shiva` | Add with a max lifetime — agent forgets it after the interval (seconds, or `30m` / `1h30m` / `1d`) |
| `ssh-add -c ~/.ssh/id_shiva` | Require confirmation (via `ssh-askpass`) on **every use** of the key |
| `ssh-add -x` / `-X` | Lock / unlock the whole agent with a password (keys stay loaded but unusable) |
| `ssh-add -T ~/.ssh/id_shiva.pub` | Test that the agent can actually sign with this key |
| `ssh-add -K` | Load resident keys from a FIDO authenticator |
| `ssh-add -s /usr/lib/…/opensc-pkcs11.so` | Load keys from a PKCS#11 smartcard; `-e` to unload |

`ssh-agent -t <life>` sets a **default** lifetime for everything added; a
per-key `ssh-add -t` overrides it. Without either, keys live until the agent dies.

**Destination-constrained keys** (`ssh-add -h`, OpenSSH ≥ 8.9): pin a key so the
agent will only sign for a named host — e.g.
`ssh-add -h bastion -h "bastion>internal-db" ~/.ssh/id_shiva` limits use to the
origin→bastion hop and the bastion→internal-db hop. Useful with forwarding.

---

## Agent forwarding

`ForwardAgent yes` (or `ssh -A`) makes your local agent's socket reachable
**from the remote host**, so a second `ssh` hop from there authenticates with
your local keys — without the keys ever being on the intermediate host.

**The risk:** "Users with the ability to bypass file permissions on the remote
host … can access the local agent through the forwarded connection"
(`ssh_config(5)`). Root on the jump host can't steal the key, but they can use
it to log in *as you* anywhere it's accepted, for as long as your session is open.

**Prefer `ProxyJump`.** It routes the connection *through* the bastion at the
TCP level; the bastion never sees your agent at all:

```ssh-config
Host internal-db
    HostName 10.0.5.12
    ProxyJump bastion
```

Only reach for `ForwardAgent` when you genuinely need to *run* `ssh`/`git` **on**
the remote host with your identity. When you do, scope it:

- turn it on per-host, never in `Host *`;
- constrain the key with `ssh-add -h` (above);
- for CA certs, mint them with `ssh-keygen -O no-agent-forwarding` — see
  [`ssh-ca.md`](ssh-ca.md).

`IdentityAgent` picks *which* agent a host uses (or `none` to ignore the agent
for that host); it overrides `SSH_AUTH_SOCK`.

---

## Scoping what the agent offers

Every loaded identity is offered to **every** host you connect to. A server that
doesn't recognise a key just ignores it — but each offer counts against the
server's `MaxAuthTries` (default 6), so a fat agent can get you disconnected
*before* the right key is tried.

Fix: `IdentitiesOnly yes` plus an explicit `IdentityFile` per `Host` block, so
`ssh` sends only the named key even when the agent holds more. Covered in
[`ssh-config.md`](ssh-config.md) and [`passwordless-login.md`](passwordless-login.md) §6.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Could not open a connection to your authentication agent` | No agent running, or `SSH_AUTH_SOCK` unset / stale (points at a dead socket). Start one, or fix the export. |
| Keys "disappear" after a reboot (Linux) | Expected — the agent is per-session. Use `AddKeysToAgent` or a `systemd --user` unit. |
| `ssh` still prompts for the passphrase | Key not loaded (`ssh-add -l`), or the host has `IdentitiesOnly yes` with an `IdentityFile` that isn't the loaded key. |
| `Too many authentication failures` | Agent offered too many keys — see "Scoping" above. `ssh -v host` shows which identities are offered and in what order. |
| Multiple orphan `ssh-agent` processes | Each `eval "$(ssh-agent)"` without cleanup leaves one. `pkill ssh-agent` and switch to a single shared agent. |

---

## See Also

- [`passwordless-login.md`](passwordless-login.md) §6 — agent + CA cert, Windows service setup
- [`ssh-config.md`](ssh-config.md) — `AddKeysToAgent`, `IdentitiesOnly`, `ForwardAgent`, `ProxyJump`
- [`ssh-ca.md`](ssh-ca.md) — holding a CA key in the agent; `no-agent-forwarding` cert option
- [`port-forwarding.md`](port-forwarding.md) — `ProxyJump` vs. port tunnels
- [`GLOSSARY.md`](GLOSSARY.md) — SSH vocabulary
