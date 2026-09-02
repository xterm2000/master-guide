# firewalld (RHEL-based)

`firewalld` is the default host firewall manager on RHEL / Rocky / Alma / Oracle
Linux since RHEL 7, and on Fedora. It is a long-running D-Bus daemon that
compiles a high-level, zone-based configuration down into kernel packet-filter
rules and applies them **without flushing existing connections** — the "dynamic"
in the name. You talk to it with `firewall-cmd` (live daemon),
`firewall-offline-cmd` (daemon stopped / kickstart), or `firewall-config` (GUI).

Every read-only command and its output below was run on this box:

```bash
sudo firewall-cmd --version    # 2.4.3   (firewalld-2.4.3-4.el10_2, Rocky Linux 10.2)
sudo firewall-cmd --state      # running
```

Rule-changing commands (`--add-*`, `--remove-*`, `--set-*`) are shown as syntax —
they were **not** executed against this live host — and are drawn from the man
pages (`firewall-cmd(1)`, `firewalld.zone(5)`, `firewalld.policy(5)`,
`firewalld.richlanguage(5)`).

---

## 1. What firewalld sits on

firewalld is a front end, not a packet filter itself. Its backend is selected in
`/etc/firewalld/firewalld.conf`:

```
FirewallBackend=nftables      # default on RHEL 9/10, Fedora
```

With the `nftables` backend, `firewall-cmd` writes a single nftables table that
you can read directly — useful when a rule "isn't working" and you want to see
what actually landed:

```bash
sudo nft list tables
#   table inet firewalld        <- everything firewalld generates
#   table ip nat / ip filter / ip6 nat / ...   <- legacy compat + other tools

sudo nft list table inet firewalld | grep 'chain '
#   chain filter_INPUT / filter_FORWARD / filter_OUTPUT
#   chain filter_INPUT_POLICIES / filter_FORWARD_POLICIES / ...
#   chain filter_IN_public / filter_IN_public_pre / _log / _deny / _allow / _post
#   ...
```

The older `iptables` backend produces `iptables`/`ip6tables` rules instead; the
firewalld commands are identical either way. **Don't hand-edit the nftables table
or run `iptables` alongside firewalld** — the next `--reload` overwrites your
changes. If you need raw rules, add them *through* firewalld (§10, direct rules)
or in a separate nftables table firewalld won't touch.

Other relevant `firewalld.conf` settings on this host:

```
DefaultZone=public
IPv6_rpfilter=strict                                  # drop spoofed IPv6 (reverse-path)
LogDenied=off                                         # see §9
FlushAllOnReload=yes
ReloadPolicy=INPUT:DROP,FORWARD:DROP,OUTPUT:DROP      # see §4
```

---

## 2. The model in one picture

```
                    ┌───────────────────────────────────────────┐
   packet in ──▶    │  which ZONE?                               │
                    │   1. source address bound to a zone?  ─────┼──▶ that zone
                    │   2. else: incoming interface's zone?  ─────┼──▶ that zone
                    │   3. else: the default zone            ─────┼──▶ public
                    └───────────────────────────────────────────┘
                                     │
              ┌──────────────────────┴───────────────────────┐
      addressed TO this host                        being FORWARDED through
              │                                              │
        the ZONE decides                          a POLICY decides
   (services, ports, rich rules,                (ingress-zone → egress-zone,
    then the zone target)                        priority-ordered, then target)
```

Two things to take from this:

- **Source binding beats interface binding.** A zone attached to a source
  address/subnet is consulted before the zone attached to the interface the
  packet arrived on. This is how you carve out "these IPs are treated as
  trusted/hostile regardless of which NIC they come in on".
- **Zones only cover traffic terminating on the host.** Routed/forwarded traffic
  (a gateway, a VM host, a Kubernetes node forwarding pod traffic) is governed by
  **policy objects** — §8. If you've only ever configured zones, you've only
  configured the host's own inbound traffic.

---

## 3. Zones

A **zone** is a named trust level. It bundles: a set of allowed services/ports, an
optional set of rich rules, and a **target** — the verdict for any packet that
matched none of the above.

```bash
sudo firewall-cmd --get-zones
#   block dmz docker drop external home internal nm-shared public trusted work
```

The ten shipped zones, by target (from `firewall-cmd --list-all-zones` on this
host):

| Zone | Target | Behaviour for unmatched inbound | Preloaded services |
|---|---|---|---|
| `drop` | `DROP` | dropped, no reply | — |
| `block` | `%%REJECT%%` | rejected with an ICMP/RST | — |
| `public` | *default* | rejected (ICMP allowed) | cockpit, dhcpv6-client, ssh (+ custom) |
| `external` | *default* | rejected; **masquerade on** | ssh |
| `dmz` | *default* | rejected | ssh |
| `work` | *default* | rejected | cockpit, dhcpv6-client, ssh |
| `home` / `internal` | *default* | rejected | cockpit, dhcpv6-client, mdns, samba-client, ssh |
| `nm-shared` | `ACCEPT` | for NetworkManager connection sharing — accepts forwarding + a few services, with a built-in low-priority `reject` catch-all | dhcp, dns, ssh |
| `trusted` | `ACCEPT` | accepted — allow everything | — |
| `docker` | `ACCEPT` | accepted — created by Docker, see §12 | — |

"*default*" as a target means: accept ICMP, **reject everything else**. It's the
sane public-facing posture and why `public` is the out-of-the-box default.

### The active picture on this host

```bash
sudo firewall-cmd --get-default-zone
#   public

sudo firewall-cmd --get-active-zones
#   docker
#     interfaces: br-7780958748c4 br-7cff06c2c272 br-43c1abfc0beb docker0 br-e19c3777dde7
#   public (default)
#     interfaces: ens160
```

### Reading a zone

```bash
sudo firewall-cmd --zone=public --list-all
#   public (default, active)
#     target: default
#     ingress-priority: 0        egress-priority: 0     <- tie-break when >1 zone could match (recent firewalld)
#     icmp-block-inversion: no
#     interfaces: ens160
#     sources:
#     services: cockpit dhcpv6-client obsidian--27123 ollama-11434 ssh
#     ports:
#     protocols:
#     forward: yes              <- intra-zone forwarding (default-on since firewalld 1.0)
#     masquerade: no
#     forward-ports:
#     source-ports:
#     icmp-blocks:
#     rich rules:
```

`--list-services`, `--list-ports`, `--list-rich-rules`, `--list-interfaces` print
a single field. Omitting `--zone` targets the default zone. Add `--permanent` to
read the on-disk config instead of the running one (they can differ — §4).

---

## 4. Runtime vs permanent — the distinction that trips everyone

Every change command applies to the **runtime** configuration: live immediately,
**gone on `--reload` or reboot**. `--permanent` writes to disk (`/etc/firewalld/`)
but does **not** touch the running firewall until you reload.

```bash
sudo firewall-cmd --add-service=http                 # live now, lost on reload
sudo firewall-cmd --permanent --add-service=http      # on disk, NOT live yet
sudo firewall-cmd --reload                            # merge permanent -> runtime
```

Three ways to make a lasting change:

| Approach | When |
|---|---|
| `--permanent` then `--reload` | The textbook way. One caveat: `--reload` briefly drops all non-established traffic (see `ReloadPolicy` below). |
| Run the command twice — once plain, once `--permanent` | Live instantly *and* persisted, no reload. Fine for one or two changes; tedious and error-prone for many. |
| Make all changes in runtime, verify, then **`--runtime-to-permanent`** | The clean way for a batch: experiment freely, and when it works, snapshot the whole runtime state to disk in one shot. |

```bash
sudo firewall-cmd --add-service=http
sudo firewall-cmd --add-port=8443/tcp
sudo firewall-cmd --add-rich-rule='rule family="ipv4" source address="10.0.0.0/24" service name="ssh" accept'
# ... test that you can still get in ...
sudo firewall-cmd --runtime-to-permanent           # persist everything at once
```

### reload vs complete-reload

```bash
sudo firewall-cmd --reload            # re-read permanent config; keep connection state
sudo firewall-cmd --complete-reload   # also flush conntrack — needed after a backend
                                      # change or to forcibly break existing connections
```

`ReloadPolicy` (in `firewalld.conf`) controls what happens *during* a reload.
Default `INPUT:DROP,FORWARD:DROP,OUTPUT:DROP` — everything except established
connections is dropped for the reload window, so a reload can't briefly expose a
port. Your SSH session survives (it's established); a *new* connection attempt
mid-reload may not.

### On-disk layout

```
/usr/lib/firewalld/       shipped defaults — DO NOT EDIT (rewritten on package update)
  zones/  services/  policies/  icmptypes/  helpers/  ipsets/
/etc/firewalld/           your overrides — these win
  firewalld.conf
  zones/     public.xml           <- customised zone
  zones/     public.xml.old       <- firewalld's automatic backup of the previous version
  services/  ollama-11434.xml     <- a custom service (§6)
  policies/  docker-forwarding.xml
```

A file in `/etc/firewalld/zones/` shadows the same-named file under
`/usr/lib/firewalld/zones/`. Deleting the `/etc` copy reverts to the shipped
default. `firewall-cmd --check-config` validates every file:

```bash
sudo firewall-cmd --check-config      # success
```

---

## 5. Binding interfaces and sources to zones

```bash
# By interface (runtime + permanent)
sudo firewall-cmd --zone=internal --change-interface=ens192
sudo firewall-cmd --zone=internal --change-interface=ens192 --permanent

# By source — CIDR, a single IP, a MAC, or a named ipset
sudo firewall-cmd --zone=trusted  --add-source=10.0.0.0/24 --permanent
sudo firewall-cmd --zone=drop     --add-source=203.0.113.66 --permanent
sudo firewall-cmd --zone=work     --add-source=ipset:office-nets --permanent
```

`--change-interface` moves an interface between zones (use it rather than
`--add-interface`, which errors if the interface is already placed).

Check where something currently lands:

```bash
sudo firewall-cmd --get-zone-of-interface=ens160    # public
sudo firewall-cmd --get-zone-of-interface=ens192    # no zone   (falls to default)
sudo firewall-cmd --get-zone-of-source=10.0.0.0/24  # no zone
```

### Persisting via NetworkManager

On a NetworkManager-managed system the durable binding is a property of the
**connection**, not firewalld:

```bash
sudo nmcli connection modify "System ens192" connection.zone internal
sudo nmcli connection up "System ens192"
```

If a connection's `connection.zone` is empty (the case for `ens160` here),
NetworkManager hands the interface to firewalld's `DefaultZone`. A
`firewall-cmd --permanent --change-interface` and an `nmcli connection.zone` that
disagree is a classic "why did my interface move after a network restart" bug —
pick one mechanism per interface.

---

## 6. Opening things: services vs ports

firewalld ships **265** predefined *services* — named bundles of the ports,
protocols, and any kernel helper a daemon needs:

```bash
sudo firewall-cmd --get-services | wc -w          # 265
sudo firewall-cmd --info-service=ssh
#   ssh
#     ports: 22/tcp
#     protocols:
#     ...
```

Prefer the service name over a raw port where one exists — it's self-documenting
and survives a service definition being updated.

```bash
sudo firewall-cmd --zone=public --add-service=https --permanent
sudo firewall-cmd --zone=public --add-port=8080/tcp --permanent
sudo firewall-cmd --zone=public --add-port=30000-32767/tcp --permanent   # a range
sudo firewall-cmd --zone=public --add-protocol=gre --permanent           # a bare protocol

sudo firewall-cmd --zone=public --query-service=https     # yes / no, exit 0 / 1
sudo firewall-cmd --zone=public --remove-service=https --permanent
```

### Defining a custom service

The simplest form is a two-line XML file in `/etc/firewalld/services/`. This one
is live on this host:

```xml
<!-- /etc/firewalld/services/ollama-11434.xml -->
<?xml version="1.0" encoding="utf-8"?>
<service>
  <description>ollama port</description>
  <port port="11434" protocol="tcp"/>
</service>
```

After creating the file: `sudo firewall-cmd --reload`, then it's usable as
`--add-service=ollama-11434`. The equivalent without touching files:

```bash
sudo firewall-cmd --permanent --new-service=ollama-11434
sudo firewall-cmd --permanent --service=ollama-11434 --set-description="ollama port"
sudo firewall-cmd --permanent --service=ollama-11434 --add-port=11434/tcp
sudo firewall-cmd --reload
```

---

## 7. Rich rules

When a plain service/port (all-or-nothing) isn't enough — "this port, but only
from that subnet", "log then drop", "reject with a specific ICMP type". From
`firewalld.richlanguage(5)`:

```
rule
  [source ...] [destination ...]
  service|port|protocol|icmp-block|icmp-type|masquerade|forward-port|source-port
  [log|nflog] [audit]
  [accept|reject|drop|mark]
```

**Within a zone, the first matching rule wins**; if none match, the zone target
applies.

```bash
# Allow 8080/tcp only from a subnet
sudo firewall-cmd --permanent --zone=public --add-rich-rule=\
'rule family="ipv4" source address="10.0.0.0/24" port port="8080" protocol="tcp" accept'

# Log (rate-limited) and drop everything from one host
sudo firewall-cmd --permanent --zone=public --add-rich-rule=\
'rule family="ipv4" source address="203.0.113.66" log prefix="banned " level="info" limit value="3/m" drop'

# Reject a service from a subnet with an explicit ICMP type
sudo firewall-cmd --permanent --zone=public --add-rich-rule=\
'rule family="ipv4" source address="192.0.2.0/24" service name="mysql" reject type="icmp-port-unreachable"'

# Give a rule an explicit ordering slot (lower = earlier; negatives allowed)
sudo firewall-cmd --permanent --zone=public --add-rich-rule=\
'rule priority="-100" family="ipv4" source address="10.0.0.0/8" drop'
```

Element options go **immediately after** their element (`port port="8080"
protocol="tcp"`, not `port port="8080" ... protocol="tcp"` further along) or
firewalld misparses the rule.

---

## 8. Policies — the forwarded-traffic layer

Zones answer "what may reach *this host*". **Policy objects** (firewalld 0.9+)
answer "what may pass *between* zones" — i.e. routed/forwarded traffic. If the box
is a gateway, router, VPN concentrator, VM host, or Kubernetes node, this is the
half that matters.

A policy binds a set of **ingress zones** to a set of **egress zones** and then
carries the same vocabulary as a zone (services, ports, rich rules, masquerade,
forward-ports) plus a **priority** and a **target**:

| Policy target | Meaning |
|---|---|
| `CONTINUE` | fall through to the next policy / the zone's own handling |
| `ACCEPT` | allow matched forwarded traffic |
| `REJECT` / `DROP` | block it |

Two symbolic zones exist only for policies: **`HOST`** (traffic to/from the local
machine) and **`ANY`** (every zone).

```bash
sudo firewall-cmd --get-policies
#   allow-host-ipv6 docker-forwarding gateway-dmz-to-HOST gateway-lan-to-HOST
#   gateway-lan-to-work gateway-lan-to-world gateway-world-to-HOST

sudo firewall-cmd --get-active-policies
#   allow-host-ipv6
#     ingress-zones: ANY
#     egress-zones: HOST
#   docker-forwarding
#     ingress-zones: ANY
#     egress-zones: docker

sudo firewall-cmd --info-policy=docker-forwarding
#   docker-forwarding (active)
#     priority: -1
#     target: ACCEPT
#     ingress-zones: ANY
#     egress-zones: docker
```

Policies are evaluated in **priority order, lowest first** (negative = earliest).
`allow-host-ipv6` runs at `-15000` with target `CONTINUE` — it whitelists IPv6
neighbour discovery / MLD ICMP into `HOST` and then lets normal processing
proceed.

### Creating a policy (host acting as a router: LAN → WAN)

```bash
sudo firewall-cmd --permanent --new-policy=lan-to-wan
sudo firewall-cmd --permanent --policy=lan-to-wan --add-ingress-zone=internal
sudo firewall-cmd --permanent --policy=lan-to-wan --add-egress-zone=public
sudo firewall-cmd --permanent --policy=lan-to-wan --set-target=ACCEPT
sudo firewall-cmd --permanent --policy=lan-to-wan --add-masquerade
sudo firewall-cmd --reload
```

### The zone-target shortcut, and its catch

A zone with `target="ACCEPT"` (like `trusted` or `docker`) forwards any packet
**not addressed to the host** straight to its destination — *bypassing the
`forward` setting and any policy attached to that zone* (per
`firewalld.zone(5)`). Convenient, blunt: you lose the ability to filter that
forwarded traffic with a policy. Prefer an explicit policy when you need control.

---

## 9. NAT: masquerade and forward-ports

```bash
# Source NAT — rewrite outgoing packets to the host's address (share one public IP)
sudo firewall-cmd --zone=external --add-masquerade --permanent

# Destination NAT — publish an internal service
sudo firewall-cmd --zone=public --permanent --add-forward-port=\
port=443:proto=tcp:toport=8443                       # same host, different port
sudo firewall-cmd --zone=public --permanent --add-forward-port=\
port=443:proto=tcp:toport=443:toaddr=10.0.0.10       # to another host (needs masquerade
                                                     # on the return path, or a route back)
```

Masquerade implies IP forwarding for that path; firewalld enables the needed
`net.ipv4.ip_forward` when a masquerade or forward-port is active. The
`external` zone ships with masquerade already on. `StrictForwardPorts=no` in
`firewalld.conf` (the current default) keeps the pre-2.1 behaviour where a
forward-port doesn't also require an explicit matching filter allow.

---

## 10. Logging and inspecting

```bash
sudo firewall-cmd --get-log-denied          # off  (on this host)
sudo firewall-cmd --set-log-denied=unicast  # log dropped/rejected unicast packets
                                            # values: all | unicast | broadcast | multicast | off
```

Denied-packet logs go to the kernel ring buffer → `journalctl -k` /
`/var/log/messages`, prefixed by chain (`filter_IN_public_DROP`).

See exactly what firewalld generated:

```bash
sudo nft list table inet firewalld          # the whole compiled ruleset
sudo firewall-cmd --list-all-zones           # every zone, one screen
sudo firewall-cmd --list-all-policies
```

### Direct rules (escape hatch)

For a rule the rich language can't express, inject raw backend rules that
firewalld will preserve across reloads:

```bash
sudo firewall-cmd --permanent --direct --add-rule inet filter FORWARD 0 \
  -i eth0 -o eth1 -p tcp --dport 3306 -j ACCEPT
sudo firewall-cmd --direct --get-all-rules      # (empty on this host)
```

Use sparingly — direct rules sidestep the zone/policy model and are ordered only
by the integer priority you give them.

---

## 11. Panic mode and safe remote changes

```bash
sudo firewall-cmd --panic-on       # drop ALL traffic in and out — emergency kill switch
sudo firewall-cmd --query-panic    # yes / no
sudo firewall-cmd --panic-off
```

Panic mode is not a recovery tool — it severs your SSH session too.

**The real protection for editing a firewall over SSH** is `--timeout`: any
option marked `[T]` in `firewall-cmd --help` can be added for a limited time and
auto-reverts.

```bash
# Try a change; if it locks you out, it undoes itself in 2 minutes
sudo firewall-cmd --zone=public --add-rich-rule=\
'rule family="ipv4" source address="10.0.0.0/24" service name="ssh" accept' --timeout=2m

# Still connected and happy? Persist it for real:
sudo firewall-cmd --permanent --zone=public --add-rich-rule=\
'rule family="ipv4" source address="10.0.0.0/24" service name="ssh" accept'
sudo firewall-cmd --reload
```

Also: keep a second SSH session open and idle while you test — an established
connection survives both a bad rule and a `--reload`.

---

## 12. Docker and firewalld

On a current Docker + firewalld system (this host), Docker integrates itself
automatically — you do **not** manually move `docker0` into a zone:

```bash
sudo firewall-cmd --get-active-zones
#   docker
#     interfaces: docker0 br-7780958748c4 br-...      <- Docker put every bridge here

sudo firewall-cmd --info-zone=docker | head -3
#   docker (active)
#     target: ACCEPT                                  <- forwards container traffic freely

sudo firewall-cmd --info-policy=docker-forwarding
#   priority: -1   target: ACCEPT   ingress-zones: ANY   egress-zones: docker
```

Consequences:

- **Published ports (`-p 8080:80`) bypass your `public` zone rules by design.**
  The `docker` zone's `ACCEPT` target plus the `docker-forwarding` policy mean a
  container port is reachable from anywhere the host is, regardless of what
  `public` allows. This is the usual "why can the internet reach my container"
  surprise.
- To restrict container exposure, do it on the Docker side (bind published ports
  to `127.0.0.1`, use the `DOCKER-USER` chain / Docker 28+ `nftables` rules), or
  add source restrictions to the `docker` zone / a custom policy — not to
  `public`.
- If Docker did **not** create the zone (older Docker, or
  `"iptables": false`), then the old advice applies: put `docker0` in its own
  zone and manage it explicitly.

See [`../../docker-cicd/README.md`](../../docker-cicd/README.md) for the CI/CD lab's
container-network setup.

---

## 13. Quick reference

| Task | Command |
|---|---|
| Daemon state / version | `firewall-cmd --state` / `--version` |
| Default / active zones | `firewall-cmd --get-default-zone` / `--get-active-zones` |
| Everything in a zone | `firewall-cmd --zone=Z --list-all` (`--permanent` for on-disk) |
| Add service / port (live) | `firewall-cmd --zone=Z --add-service=NAME` / `--add-port=8080/tcp` |
| Persist current runtime | `firewall-cmd --runtime-to-permanent` |
| Persist one change | add `--permanent`, then `firewall-cmd --reload` |
| Reload (keep state) / hard reload | `firewall-cmd --reload` / `--complete-reload` |
| Remove | `firewall-cmd --zone=Z --remove-service=NAME [--permanent]` |
| Query (scriptable, exit 0/1) | `firewall-cmd --zone=Z --query-service=NAME` |
| Bind interface / source | `firewall-cmd --zone=Z --change-interface=IF` / `--add-source=CIDR` |
| Rich rule | `firewall-cmd --zone=Z --add-rich-rule='rule ...' [--timeout=2m]` |
| Policies | `firewall-cmd --get-policies` / `--info-policy=P` / `--list-all-policies` |
| Log denied packets | `firewall-cmd --set-log-denied=unicast` |
| Show compiled ruleset | `nft list table inet firewalld` |
| Validate config files | `firewall-cmd --check-config` |
| Emergency stop / release | `firewall-cmd --panic-on` / `--panic-off` |

---

## 14. Recipes

### Lock a bastion down to SSH from a management subnet only

Don't add the blanket `ssh` service; express the whole allow as a scoped rich
rule so nothing else can reach 22.

```bash
sudo firewall-cmd --permanent --zone=public --remove-service=ssh
sudo firewall-cmd --permanent --zone=public --add-rich-rule=\
'rule family="ipv4" source address="10.0.0.0/24" service name="ssh" accept'
sudo firewall-cmd --reload
sudo firewall-cmd --zone=public --list-all       # services: no ssh;  rich rules: the scoped allow
```

Test from an allowed *and* a disallowed source before you close the second
session. See [`../ssh/`](../ssh/) for not locking yourself out.

### Expose a Kubernetes NodePort range on a worker

```bash
sudo firewall-cmd --permanent --zone=public --add-port=30000-32767/tcp
sudo firewall-cmd --reload
```

One range rule, not 2768 individual ones. Narrow it to the cluster/LB subnet with
a rich rule if the node faces an untrusted network.

### Host as a router: NAT a LAN out to the WAN

```bash
sudo firewall-cmd --permanent --new-policy=lan-to-wan
sudo firewall-cmd --permanent --policy=lan-to-wan --add-ingress-zone=internal
sudo firewall-cmd --permanent --policy=lan-to-wan --add-egress-zone=public
sudo firewall-cmd --permanent --policy=lan-to-wan --set-target=ACCEPT
sudo firewall-cmd --permanent --policy=lan-to-wan --add-masquerade
sudo firewall-cmd --reload
```

### Block an abusive IP immediately, persist later

```bash
sudo firewall-cmd --zone=drop --add-source=203.0.113.66          # live now
sudo firewall-cmd --permanent --zone=drop --add-source=203.0.113.66   # keep it
```

`drop` gives no reply at all; use `block` if you want the source to get an ICMP
reject.

### A change you're not sure about, over SSH

```bash
sudo firewall-cmd --zone=public --add-service=https --timeout=5m
# reverts by itself in 5 minutes; re-issue with --permanent once confirmed
```

---

## 15. Files and See Also

- `/etc/firewalld/firewalld.conf` — backend, default zone, `LogDenied`, `ReloadPolicy`
- `/etc/firewalld/{zones,services,policies,ipsets}/*.xml` — your definitions (win over `/usr/lib/firewalld/`)
- `firewall-offline-cmd` — same interface, for when the daemon is stopped (kickstart `%post`, image builds)
- `man firewall-cmd`, `man firewalld.zone`, `man firewalld.policy`, `man firewalld.richlanguage`

- [`../../network/README.md`](../../network/README.md) — raw `iptables` / `nftables` and general connectivity diagnostics
- [`../ssh/`](../ssh/) — SSH access, and how not to lock yourself out with a firewall change
- [`../../docker-cicd/README.md`](../../docker-cicd/README.md) — the container CI/CD lab whose networking rides on this
- [`scheduling.md`](scheduling.md), [`selinux.md`](selinux.md) — the other host-hardening pieces
