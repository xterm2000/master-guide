# SSH Port Forwarding & Tunnelling

Carrying a TCP connection inside an existing SSH session, so a service that is
**not** exposed to the network can still be reached — or so traffic exits from
the remote end. Three directions: local (`-L`), remote (`-R`), dynamic (`-D`).

The companion topics: [`ssh-config.md`](ssh-config.md) (the `~/.ssh/config`
directives named below), [`ssh-ca.md`](ssh-ca.md) (restricting a CA cert to a
tunnel), [`passwordless-login.md`](passwordless-login.md) §5 (hardening the one
port you *do* expose).

---

## 1. Why tunnel instead of exposing the port

A port forward means only **SSH** is reachable from outside; everything else
stays bound to `localhost` on the server and is reached *through* the SSH
session.

- **A database is a categorically worse thing to expose than a web server.**
  Its wire protocol and default auth model assume a trusted network in front of
  it, automated scanners specifically target database ports for weak
  credentials and known CVEs, and a compromise usually means direct access to
  all the data — there is no application layer in the way. Keep Postgres/MySQL/
  Redis/etc. on `localhost` and tunnel.
- Internal web UIs, admin consoles, metrics endpoints — same reasoning, lower
  stakes. If the general public doesn't need it, don't forward it.
- The forward is per-session and authenticated by your SSH key: nothing is
  listening on the public internet for a scanner to find.

---

## 2. Local forward (`-L`) — reach a remote-side service from your machine

`-L [bind:]localport:targethost:targetport`

```bash
# Postgres on the server, bound to its localhost, reached on your localhost:5432
ssh -L 5432:localhost:5432 -p 2222 user@server

# Several ports in one session
ssh -L 5432:localhost:5432 -L 8080:localhost:80 -p 2222 user@server

# Use the server as a jump point to a DIFFERENT host on its LAN.
# targethost is resolved from the SERVER's network, not yours.
ssh -L 5432:192.168.1.50:5432 -p 2222 user@server
```

`targethost` is `localhost` when the service runs on the SSH server itself;
it's another address when the server is only a gateway to it.

By default the local end binds to `127.0.0.1` only. Prefix an address (or use
`-g` / `GatewayPorts`) to let other machines use your tunnel — rarely what you
want.

### In `~/.ssh/config`

```
Host db
    HostName server.example.com
    Port 2222
    User user
    LocalForward 5432 localhost:5432
    LocalForward 8080 localhost:80
```

Then `ssh db` opens both tunnels. `LocalForward` takes the same
`localport targethost:targetport` split, space-separated.

---

## 3. Remote forward (`-R`) — expose a local service on the remote side

`-R [bind:]remoteport:targethost:targetport`

```bash
# Make your laptop's :3000 reachable as server:8000 (server-local by default)
ssh -R 8000:localhost:3000 user@server
```

Config directive: `RemoteForward 8000 localhost:3000`. For the remote bind to
listen on anything other than the server's loopback, the server needs
`GatewayPorts clientspecified` (or `yes`) in `sshd_config`.

---

## 4. Dynamic forward (`-D`) — SOCKS proxy

`-D [bind:]port` turns the SSH session into a SOCKS5 proxy; the application
picks destinations at runtime, so it's one tunnel for arbitrary hosts.

```bash
ssh -D 1080 user@server
# then point a browser / curl at socks5h://localhost:1080
curl --proxy socks5h://localhost:1080 https://internal.example.com
```

Config directive: `DynamicForward 1080`.

---

## 5. Scoping a key or certificate to *only* a tunnel

So a stolen key can open the DB tunnel and nothing else — no shell, no other
forwards.

### Plain `authorized_keys`

`authorized_keys` supports a per-line `permitopen=` restriction:

```
restrict,port-forwarding,permitopen="localhost:5432" ssh-ed25519 AAAA... tunnel-only
```

`restrict` removes every privilege (pty, agent/X11 forwarding, …); the
following options add back just what's listed.

### CA certificate

**`permitopen=` is an `authorized_keys` option, not a certificate option** —
`ssh-keygen -s … -O permitopen=…` is rejected with
`Unsupported certificate option` (verified, OpenSSH 9.9p1). For a cert,
restrict with the extension set instead:

```bash
ssh-keygen -s ca_user_key -I db-tunnel -n tunneluser -V +8h \
  -O clear -O permit-port-forwarding \
  -O source-address="203.0.113.0/24" \
  id_ed25519.pub
```

`-O clear` drops all default extensions; `-O permit-port-forwarding` adds back
only forwarding — no `permit-pty`, so no interactive shell. Verified: the
resulting cert shows `Extensions: permit-port-forwarding` and nothing else.
Add `-O source-address=` (a Critical Option) to also pin the client network.
See [`ssh-ca.md`](ssh-ca.md) §3 for the full `-O` table.

Per-destination locking (`permitopen`-style) for a cert has to be done
server-side — an `AuthorizedPrincipalsFile` entry with its own `permitopen=`,
or a `Match` block — not baked into the cert.

---

## 6. Troubleshooting

```bash
# See what the forward actually did — verbose shows each channel open/refused
ssh -v -L 5432:localhost:5432 -p 2222 user@server

# "channel N: open failed: connect failed: Connection refused"
#   -> nothing is listening on targethost:targetport FROM THE SERVER'S VIEW.
#      Check on the server:  ss -tlnp | grep 5432
#      A service bound to 127.0.0.1 is fine for -L localhost:5432; one bound to
#      a container/other namespace may need the container IP as targethost.

# "bind: Address already in use"
#   -> your chosen localport is taken. Pick another, or find the holder:
ss -tlnp | grep 5432

# Forward set up but the app can't connect
#   -> app is pointed at the wrong end. It must connect to localhost:<localport>
#      on YOUR machine, not to the server.
```

Keep-alives matter for long-lived tunnels — a silently dropped session leaves a
dead forward. Set `ServerAliveInterval 60` / `ServerAliveCountMax 3` (see
[`ssh-config.md`](ssh-config.md)).

---

## See Also

- [`ssh-config.md`](ssh-config.md) — `LocalForward` / `RemoteForward` / `DynamicForward`, keep-alive, multiplexing
- [`ssh-ca.md`](ssh-ca.md) — §3 certificate restriction options
- [`passwordless-login.md`](passwordless-login.md) — §5 hardening the exposed SSH port
- [`restricted-networks.md`](restricted-networks.md) — when the SSH port itself is blocked on the network you're connecting from
