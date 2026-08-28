# Reaching a Host Whose Public IP Changes

Your home server (`shiva`) sits behind a consumer router. To SSH in from
outside the LAN you connect to the router's **public IP** and it port-forwards
to the box. The problem: that public IP is not stable.

## Why the IP changes

Residential ISPs lease you a public IP via DHCP rather than assigning a static
one. The lease renews periodically, and the address can change on:

- lease expiry (hours to days, ISP-dependent)
- modem/router reboot or power cut
- ISP-side maintenance or re-provisioning

When it changes, `ssh mitek@<old-ip>` just times out — nothing tells you the
new one. You need a **stable identifier** that tracks the moving IP, or a way
to bypass the public IP entirely.

Two approaches: **Dynamic DNS** (keep a hostname pointed at the current IP) or
a **mesh VPN** (give every machine a private address that never moves).

---

## Option A — Dynamic DNS (DDNS)

A hostname (`shiva.duckdns.org`) plus a small **updater** that pushes the
current public IP to the DNS provider whenever it changes. You then always
connect to the name; DNS resolves it to whatever the IP is now.

```bash
ssh -p 2222 mitek@shiva.duckdns.org
```

The name never changes, so this needs no SSH config at all — the hostname *is*
the address. Combine it with an agent-loaded cert
([`passwordless-login.md`](passwordless-login.md) §6) for fully config-free
login, or keep a 2-line `Host` block just to pin `User` / `Port`:

```
Host shiva
    HostName shiva.duckdns.org
    Port 2222
    User mitek
```

### Providers

| Provider | Notes |
|---|---|
| **DuckDNS** | Free, no account expiry, dead-simple HTTP update URL. Good default. |
| **No-IP** | Free tier requires confirming the hostname every 30 days. |
| **Cloudflare** | If you already own a domain on Cloudflare — update an `A` record via API. Most control, slightly more setup. |
| **FreeDNS (afraid.org)** | Free, many domains to pick from. |
| **Router built-in** | ASUS / Netgear / pfSense / OPNsense ship a DDNS client in the admin UI — nothing runs on the host at all. Check there first. |

### The updater — three forms

**1. Provider one-liner in cron** (DuckDNS shown; empty `ip=` means "use the
IP you see this request coming from"):

```bash
# crontab -e  on shiva
*/5 * * * * curl -fsS "https://www.duckdns.org/update?domains=shiva&token=<your-token>&ip=" >/dev/null
```

**2. `ddclient`** — a generic daemon that speaks all the major providers.
Install (`dnf install ddclient` / `apt install ddclient`), then
`/etc/ddclient.conf`:

```
daemon=300
use=web, web=checkip.dyndns.org
protocol=duckdns
password=<your-token>
shiva.duckdns.org
```
`systemctl enable --now ddclient`.

**3. systemd timer** — a `.service` running the curl one-liner plus a
`.timer` with `OnUnitActiveSec=5min`. Same effect as cron, better logging via
`journalctl -u <name>`.

### Gotchas

- **DNS TTL** — set the record's TTL low (60–300 s). A high TTL means clients
  cache the *old* IP for that long after a change. DuckDNS uses 60 s
  automatically; on Cloudflare set it explicitly.
- **CGNAT (carrier-grade NAT)** — some ISPs put you behind *their* NAT, so you
  have no real public IP and **no inbound connection works**, DDNS or not.
  Test: compare the WAN IP shown in your router's status page against
  `curl -s https://ifconfig.me` run from the LAN. If they differ (and the WAN
  IP is in `100.64.0.0/10`), you're behind CGNAT — use Option B, or ask the
  ISP for a real IP (often a paid add-on).
- **Port forward still required** — DDNS only fixes the *name*. The router
  still needs a forward rule: external `:2222` → `shiva:22` (or `:2222`).
- **Updater must see the real IP** — if the updater runs on a host behind a
  double NAT, `ip=` auto-detection still works (the provider sees the request's
  source), but `use=if` style local-interface detection would report a private
  address.

---

## Option B — Mesh VPN (Tailscale / WireGuard)

Install Tailscale (or hand-rolled WireGuard) on `shiva` and on each client.
Every machine joins a private overlay network and gets a **stable address**
(`100.x.y.z`) plus a name (`shiva` via MagicDNS) that never changes, no matter
what the ISP does to the public IP.

```bash
ssh mitek@shiva          # MagicDNS name, or 100.x.y.z — stable forever
```

Why this is often the better answer for a personal box:

- **No dynamic-IP problem** — the tailnet address is assigned by the VPN, not
  the ISP.
- **No internet exposure** — you can now **close port 2222 on the router
  entirely**. `sshd` only listens to the tailnet; the public internet can't
  reach it at all, which removes most of the hardening burden from
  [`passwordless-login.md`](passwordless-login.md) §5.
- **Works through CGNAT** — Tailscale uses NAT traversal / relays, so it
  connects even when neither side has a reachable public IP.
- **No updater, no port forward, no DDNS account.**

Tradeoff: every client machine must run the VPN client and be logged into the
tailnet. For "just me and a few devices" that's a one-time install per device.
Full VPN setup is out of scope here — this is just the pattern and why it fits.

---

## Which to use

| Situation | Pick |
|---|---|
| Only you + a handful of devices | **Tailscale** — kills the dynamic-IP *and* the exposure problem in one step |
| Need it reachable by arbitrary clients / other people, or from networks where you can't install a VPN client | **DDNS** + keep [`passwordless-login.md`](passwordless-login.md) §5 hardening |
| Behind CGNAT | **Tailscale** (DDNS can't help) |
| Router already has a DDNS client | Use it — zero host-side moving parts |

## See Also

- [`passwordless-login.md`](passwordless-login.md) — §5 server hardening, §6 CA certs + `ssh-agent` auto-offer
- [`ssh-config.md`](ssh-config.md) — `~/.ssh/config` `Host` blocks, `HostName`
- [`../network/`](../network/) — general DNS / networking reference
