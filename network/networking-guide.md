# Networking: Concepts, Planning, and Diagnostics

A top-down mental model for the networking in this repo — how packets actually
move, how to lay out addresses, how home / corporate / cloud networks differ,
where the security lines are, and a **method** (not a tool list) for diagnosing
"it can't connect".

This doc stays conceptual. For the commands, see
[`net-tools.md`](net-tools.md) (the tool reference) and
[`net-check.md`](net-check.md) / [`iptab.md`](iptab.md) (the lab's NAT + firewall
scripts). Terms in **bold** on first use are collected in
[`../GLOSSARY.md`](../GLOSSARY.md) § Networking.

Verified on Rocky Linux 10.2; the commands in §6 are the same ones
[`net-tools.md`](net-tools.md) pins tool versions for.

Example addresses throughout use the RFC 5737 documentation blocks
(`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`) for "public" and RFC 1918
(`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) for "private". MAC addresses
are fictional (`aa:bb:cc:…`).

### Example topology (assumed by §1–2 and §6)

Unless a section says otherwise, the examples assume **this host** on a small
flat LAN behind a NAT router:

| Thing | Value | Notes |
|---|---|---|
| Interface | `ens160` | systemd predictable name |
| This host's address | `10.1.2.50/24` | static or DHCP-reserved |
| This host's MAC | `aa:bb:cc:11:22:33` | |
| Subnet / broadcast domain | `10.1.2.0/24` | 254 usable, `.1`–`.254` |
| Default gateway | `10.1.2.1` | the NAT router / firewall |
| Gateway MAC (from `ip neigh`) | `aa:bb:cc:00:00:01` | |
| DNS resolver | `10.1.2.1` | the router forwards upstream (or a local resolver) |
| Router's WAN / public address | `198.51.100.7` | what outbound traffic is SNAT'd to |
| A remote host we test against | `198.51.100.50`, `example.com` | "the internet" |

§3 (planning) switches to a **greenfield `10.0.0.0/16`** to show subnet carving —
a separate scenario, called out where it starts.

---

## 1. How to think about a network

### 1.1 The layer ladder

Every network problem lives at one layer. You diagnose **bottom-up** because a
lower layer failing makes everything above it fail too — no point testing DNS if
the cable is unplugged.

Test from the bottom up — stop at the first layer that fails, that's the bug:

| # | Layer | What you're testing | Tool | If it fails, suspect |
|---|---|---|---|---|
| 7 | Application / TLS | HTTP responds, cert valid | `curl -v`, `openssl s_client` | app config, TLS chain/expiry |
| — | Name resolution | name → address | `getent hosts`, `dig` | DNS (resolver, record, `/etc/hosts`) |
| 4 | Transport (TCP/UDP) | port open, handshake completes | `nc -z`, `ss` | firewall, service down / not listening |
| 3 | Network (IP) | a route to the destination exists | `ip route get`, `ping` | routing table, wrong subnet |
| 3 | — gateway reachable | the default gateway answers | `ping <gw>`, `arping` | gateway down, netmask/VLAN wrong |
| 2 | Link (Ethernet/Wi-Fi) | interface up, has a MAC | `ip link`, `ethtool` | cable, driver, switch port, Wi-Fi auth |
| 1 | Physical | carrier detected | `ethtool` ("Link detected: yes") | hardware, unplugged |

(This is the TCP/IP stack. The OSI numbers 5–6 — session/presentation — are where
name resolution and TLS sit; people quote the numbers loosely. "Layer 8" is the
joke name for the user / politics.)

### 1.2 Addresses and subnets

An **IP address** identifies an interface. A **subnet** is a contiguous block of
addresses that share a **broadcast domain** — hosts in the same subnet talk
directly (via **ARP** → MAC); anything else goes through a **router**.

**CIDR notation** `10.1.2.0/24` = "the first 24 bits are the network, the
remaining 8 identify hosts". The `/24` is the **prefix length** / netmask.

```
  10.1.2.0/24   netmask 255.255.255.0
  ┌─────────────────────────────────────────────┐
  │ 10.1.2.0     network address  (not usable)   │
  │ 10.1.2.1     …                               │  ← 254 usable host addresses
  │ 10.1.2.254   …                               │     (.1 is conventionally the gateway)
  │ 10.1.2.255   broadcast address (not usable)  │
  └─────────────────────────────────────────────┘
```

| Prefix | Netmask | Usable hosts | Typical use |
|---|---|---|---|
| `/30` | `255.255.255.252` | 2 | point-to-point link between two routers |
| `/29` | `255.255.255.248` | 6 | tiny DMZ |
| `/24` | `255.255.255.0` | 254 | a normal LAN segment |
| `/23` | `255.255.254.0` | 510 | a LAN that outgrew `/24` |
| `/16` | `255.255.0.0` | 65534 | a whole site (usually subdivided) |
| `/8` | `255.0.0.0` | ~16.7M | an RFC 1918 allocation to carve up |

Rule of thumb: **usable hosts = 2^(32 − prefix) − 2** (minus network + broadcast).
Two addresses in the same subnet iff `(A & mask) == (B & mask)`.

**Why subnet at all?** Three reasons, and you're always trading them off:

1. **Broadcast containment** — ARP, DHCP discovery, mDNS are broadcast/multicast;
   a flat /16 with 4000 devices floods every NIC with junk.
2. **Routing boundary** — a subnet is the unit a router (and a firewall) reasons
   about. You can't filter "the printers" unless the printers are a subnet.
3. **Security segmentation** — blast radius. A compromised IoT bulb on its own
   `/24` with a default-deny rule to everything else can't pivot to your NAS.

### 1.3 The reserved ranges you must recognise

| Block | Name | Meaning |
|---|---|---|
| `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` | **RFC 1918 private** | Not routable on the internet. Use freely inside; NAT to leave. |
| `100.64.0.0/10` | **CGNAT** (RFC 6598) | ISP-side NAT space. If your "public" IP is in here you have **no real public IP** — inbound is impossible without a relay/VPN. Also what Tailscale uses. |
| `169.254.0.0/16` | **link-local** (APIPA) | Self-assigned when DHCP fails. Seeing this = "no DHCP answer". |
| `127.0.0.0/8` | **loopback** | The host talking to itself. |
| `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24` | **documentation** (RFC 5737) | Reserved for examples — like this doc. Never real. |
| `224.0.0.0/4` | **multicast** | One-to-many (routing protocols, mDNS, streaming). |
| `0.0.0.0/0` | **default route** | "everything not matched by a more specific route". |

### 1.4 The four questions every packet answers

When host `A` sends to address `D`:

1. **Is `D` on my subnet?** `(D & mymask) == (myaddr & mymask)` → yes: ARP for
   `D`'s MAC, send directly. Done.
2. **If not, who's my gateway?** Look up the **routing table**; the most specific
   matching route wins (**longest-prefix match**), falling back to the
   **default gateway** (`0.0.0.0/0`).
3. **Does the gateway know the way onward?** Its routing table, its upstream,
   possibly several hops of this.
4. **Will the reply get back?** The return path must also exist, and any
   **stateful firewall** or **NAT** box in the middle must still hold the
   connection's state. Asymmetric routing (request out via path X, reply via
   path Y) breaks NAT and trips **reverse-path filtering**.

Most "weird" network bugs are question 3 or 4 — a missing return route, a NAT box
that dropped the state, an MTU mismatch that only bites large packets.

---

## 2. The building blocks

### 2.1 Switch vs router vs firewall vs load balancer

| Device | Operates at | Decides |
|---|---|---|
| **Switch** | L2 (MAC) | which physical port a frame goes out, within one subnet/VLAN |
| **Router** | L3 (IP) | which next-hop / interface a packet takes between subnets |
| **Firewall** | L3–L4 (+L7) | whether a packet/connection is *allowed* (by addr, port, state, app) |
| **Load balancer** | L4 or L7 | which backend server a new connection/request goes to |
| **NAT gateway** | L3–L4 | rewrites addresses/ports at a boundary (see 2.4) |

In practice one box (a "home router", a Linux host, a cloud VPC router) does
several of these at once. The value of the table is knowing **which function** is
misbehaving.

### 2.2 Routing

A **routing table** is a list of `destination-prefix → next-hop / interface`.
Forwarding a packet = find the longest prefix that matches the destination, send
to its next-hop.

```
  a border router's table (a plain host's is just the first line + a default):

  destination        next-hop        note
  10.1.2.0/24        (on-link)       directly connected — ARP, no gateway
  10.1.0.0/16        10.1.2.1        the rest of the site, via the core router
  0.0.0.0/0          198.51.100.1    default — everything else, toward the ISP
```

This host (per § Example topology) has only:
`10.1.2.0/24` on-link, and `0.0.0.0/0` via `10.1.2.1`.

- **Static routing** — you type the routes. Fine for small/stable networks.
- **Dynamic routing** (OSPF, BGP) — routers advertise reachability to each other.
  BGP is what glues the internet together and what a cloud VPC peering uses under
  the hood. You rarely run it in a homelab.
- `ip route get <ip>` runs this exact lookup and tells you the winner — the first
  thing to check for "traffic leaving the wrong interface".

### 2.3 DNS as infrastructure

DNS turns names into addresses. Two very different roles:

- **Authoritative server** — holds the actual records for a zone
  (`example.com`'s nameservers).
- **Recursive resolver** (a.k.a. caching resolver) — what your clients point at
  (`/etc/resolv.conf`). It walks root → TLD → authoritative on a **cache miss**,
  caches the answer for its **TTL**, and serves everyone else from cache.

Concepts that bite:

- **Search domains** — `ping web` becomes `web.corp.example.com` via the search
  list. Great until two search domains both have a `web`.
- **Split-horizon / split-brain DNS** — the same name resolves differently
  inside vs outside (internal `10.x`, external public IP). A laptop on VPN that
  keeps the café's resolver gets the wrong answer.
- **Negative caching** — `NXDOMAIN` is cached too; a record you *just* created
  can "not exist" for a few minutes.
- **`SERVFAIL` vs `NXDOMAIN`** — `NXDOMAIN` = authoritative "no such name";
  `SERVFAIL` = the resolver broke trying (DNSSEC failure, dead forwarder,
  timeout). Different fixes.
- `getent hosts` = what applications see (honours `/etc/hosts` + nsswitch);
  `dig` = raw DNS only. If they disagree, the cause is local.

### 2.4 NAT, properly

**NAT** rewrites addresses (and usually ports) as packets cross a boundary, and
keeps a **connection-tracking** table so replies can be un-rewritten.

| Flavour | Also called | Does | Used for |
|---|---|---|---|
| **SNAT** | source NAT, **masquerade** | rewrites the *source* to the gateway's address | many private hosts sharing one public IP (outbound) |
| **DNAT** | destination NAT, **port forward** | rewrites the *destination* to an inside host | exposing one inside service to the outside |
| **PAT** | NAPT, "overload" | SNAT + track by port so many hosts fit behind one IP | the normal home-router case |

```
  outbound (SNAT / masquerade)

  10.1.2.50:51000  ──►  [ router ]  ──►  198.51.100.7:51000  ──►  internet
                         rewrites src,
                         remembers: 198.51.100.7:51000 ⇄ 10.1.2.50:51000
  reply comes back to 198.51.100.7:51000, router rewrites dst back to 10.1.2.50
```

What this means in practice:

- **Outbound "just works"; inbound does not.** There's no state for a connection
  nobody started, so unsolicited inbound is dropped. To accept inbound you need
  an explicit **DNAT / port-forward**, or a host with a real routable address, or
  a reverse tunnel / VPN.
- **CGNAT** = your ISP does the SNAT, you don't control the box, port-forwarding
  is impossible. Fix: outbound tunnel (WireGuard to a VPS, Tailscale, `ssh -R`,
  Cloudflare Tunnel).
- **NAT is not a firewall.** It happens to hide inside hosts, but that's a
  side-effect, not a policy. IPv6 typically has *no* NAT — every host is
  globally addressable — so you need an actual stateful firewall, not "we're
  behind NAT so we're fine".
- **Hairpin / NAT reflection** — an inside host hitting your *public* IP to reach
  another inside host. Many routers don't handle it; use split-horizon DNS so the
  inside name resolves to the inside address.
- **Conntrack table full** — a busy NAT box drops new connections when the
  tracking table fills (`nf_conntrack: table full, dropping packet` in dmesg).
  Symptom: intermittent connection failures under load.

### 2.5 DHCP — what a lease hands you

When a client boots it broadcasts for a **DHCP** lease and gets back, typically:

- an **address** + prefix (`10.1.2.50/24`)
- the **default gateway** (`10.1.2.1`)
- **DNS servers** and **search domains**
- often **NTP**, **MTU**, PXE boot info, vendor options

Consequences: a rogue/second DHCP server hands out a wrong gateway or DNS and
half your clients break randomly. A device showing a `169.254.x.x` address got
**no** DHCP answer. For servers, prefer a **DHCP reservation** (lease pinned to
the MAC) over a hand-typed static — the address is still managed centrally.

### 2.6 MTU, MSS, and why "large requests hang"

**MTU** = the biggest frame a link will carry (1500 bytes on classic Ethernet;
less inside VPNs/tunnels because they add headers — WireGuard ~1420, PPPoE 1492).

**MSS** = the largest TCP *payload*, negotiated from MTU at handshake.

The classic failure: small requests (a `ping`, a login) work; large ones (a file
upload, a TLS cert exchange, an API POST) **hang with no error**. Cause: a link
in the path has a smaller MTU, the "fragmentation needed" ICMP that should tell
the sender is being dropped by a mis-configured firewall → **PMTU black hole**.

Diagnose: `ping -M do -s 1472 <host>` and shrink `-s` until it passes
(`payload + 28 = wire size`); `tracepath` prints the discovered path MTU.
Fix: correct the MTU on the tunnel interface, or **MSS clamping** on the router
(`--set-mss` / `--clamp-mss-to-pmtu`).

---

## 3. Planning a network

### 3.1 Principles (all scales)

1. **Pick one private block and never overlap it** — not with your VPN, not with
   a site you might peer with, not with a cloud VPC, not with Docker's default
   pools. Overlap means you can never route between them cleanly.
2. **Leave headroom** — allocate `/24`s out of a `/16`, not out of a `/22`. You
   will add segments.
3. **Segment by function and trust, not by convenience** — servers, clients,
   management, IoT, guests, DMZ. Each segment is a firewall boundary.
4. **Addresses encode meaning** — reserve low addresses for infrastructure
   (`.1` gateway, `.2–.9` switches/APs, `.10–.49` servers), a DHCP pool in the
   middle, high addresses for static oddities.
5. **One authoritative source for DNS and DHCP** per segment.

### 3.2 Worked example — a homelab out of `10.0.0.0/16`

> **Scenario (separate from §1–2):** greenfield homelab, one router/firewall, one
> managed switch with VLAN support, ~40 devices growing. Supernet chosen:
> `10.0.0.0/16`. ISP hands the router a single dynamic public address.

```
  10.0.0.0/16  site supernet (gives 256 × /24)

  10.0.0.0/24    infrastructure   router, switches, APs, hypervisor mgmt, IPMI
  10.0.10.0/24   servers          NAS, hypervisor guests, CI, databases
  10.0.20.0/24   workstations     DHCP pool .100–.199, reservations below .100
  10.0.30.0/24   IoT / cameras    default-deny egress, no lateral, no inbound
  10.0.40.0/24   guest Wi-Fi      internet only, isolated from everything
  10.0.50.0/24   DMZ              anything you port-forward to from the internet
  10.0.90.0/24   VPN clients      WireGuard hands out from here
  10.0.99.0/24   lab / burn       throwaway experiments

  # per subnet: .1 = gateway (the router/firewall), .2–.9 = L2 gear,
  # .10–.99 = static servers, .100–.199 = DHCP, .200–.254 = static misc
```

Firewall intent (default-deny between segments, allow-list the exceptions):

```
  workstations → servers   : allow specific ports (SMB, HTTPS, SSH-to-jump)
  workstations → internet  : allow
  IoT          → anywhere  : DENY, except DNS+NTP to the router and HTTPS out
  guest        → RFC 1918  : DENY  (internet only)
  DMZ          → servers   : DENY  (DMZ is assumed hostile)
  any          → infra mgmt: DENY, except from a single admin host / VPN
```

### 3.3 Corporate

Same ideas, more discipline:

- **Hierarchical addressing** — allocate per site/region so routes **summarise**
  (`10.20.0.0/16` = Berlin, `10.30.0.0/16` = NYC); the core carries a handful of
  aggregate routes instead of thousands.
- **IPAM** — an IP Address Management system is the source of truth; spreadsheets
  don't survive.
- **Non-overlap is a policy** — a central team hands out blocks so a future
  acquisition / VPN / cloud peering doesn't collide.
- **VLANs** carry many subnets over one trunk; a switch port is either an
  **access port** (one VLAN, untagged, for an endpoint) or a **trunk** (many
  VLANs, tagged, between switches/to a hypervisor).
- **IPv6** — corporate and cloud increasingly dual-stack. No NAT; every host has
  a global address; firewalling and **ULA** (`fd00::/8`, the IPv6 equivalent of
  RFC 1918) matter.
- **Remote access** is VPN or **ZTNA**, never port-forwards.

### 3.4 Cloud (AWS-flavoured — ties to [`../aws/`](../aws/))

The same primitives with cloud names:

| Concept | On-prem | AWS |
|---|---|---|
| your address space | the RFC 1918 block you chose | **VPC CIDR** (e.g. `10.42.0.0/16`) |
| a segment | VLAN + subnet | **subnet**, pinned to one **Availability Zone** |
| routing table | the router's | a **route table** attached to subnets |
| internet access (in+out) | public IP on the firewall | **Internet Gateway** + a public IP/EIP |
| outbound-only for private hosts | SNAT on the router | **NAT Gateway** (managed SNAT) |
| stateful firewall | the firewall appliance | **Security Group** (stateful, allow-only, per-ENI) |
| stateless ACL | router ACL | **Network ACL** (stateless, allow+deny, per-subnet) |
| site-to-site link | IPsec tunnel | **VPC peering** / Transit Gateway / VPN / Direct Connect |

Cloud-specific gotchas:

- A **public subnet** is just a subnet whose route table has `0.0.0.0/0 → IGW`.
  "Public" is a routing fact, not a checkbox.
- A private host reaches the internet **only** through a NAT Gateway (or a VPC
  endpoint for AWS services) — and NAT Gateways cost money per hour + per GB.
- **Security Groups are stateful** (return traffic auto-allowed); **NACLs are
  stateless** (you must allow ephemeral return ports explicitly) — a classic
  "why is the response blocked" cause.
- **Do not overlap the VPC CIDR** with on-prem or other VPCs you'll ever peer —
  peering with overlapping ranges is unroutable.
- The lab in `aws/` is a minimal version of this: VPC + public subnet (bastion) +
  private subnets (control-plane, workers) + NLB.

---

## 4. Private vs corporate vs cloud — how the concerns shift

| | Home / lab | Corporate | Cloud |
|---|---|---|---|
| **Trust model** | flat, mostly trusted; segment IoT/guest | zero-trust trending; segment everything | per-workload SGs; assume the subnet is hostile |
| **Who runs DNS/DHCP** | the router (or one Pi) | AD / dedicated appliances, redundant | provider-managed (Route 53, `.2` resolver) + your own |
| **Segmentation** | a few VLANs if you bother | many VLANs, 802.1X, NAC | SG per tier, NACL per subnet, separate VPCs/accounts |
| **Remote access** | port-forward or WireGuard/Tailscale | corporate VPN / ZTNA, MFA | SSM Session Manager / bastion / ZTNA — no inbound SSH |
| **Public exposure** | one port-forward to a DMZ box | published via WAF + LB + DMZ | ALB/NLB + WAF + SG; instances have no public IP |
| **Logging / audit** | maybe the router logs | SIEM, NetFlow, full retention, change control | VPC Flow Logs, CloudTrail, config rules |
| **Change control** | you, on a whim | ticket + CAB + maintenance window | IaC (CloudFormation/Terraform) PR + review |
| **IP management** | in your head | IPAM system, allocation policy | IaC defines CIDRs; tags; no overlap policy |

The through-line: as you move right, **the network stops being a trusted
substrate and becomes an enforcement point**, and manual changes give way to
code review.

---

## 5. Security implications and modern practice

### 5.1 Perimeter is dead; segment instead

The old model: hard shell (one firewall at the edge), soft centre (flat trusted
LAN). One phished laptop or one vulnerable IoT device and the attacker is inside
the trusted zone with free lateral movement.

Modern model — **zero trust / assume breach**:

- **Segment for blast radius.** Every segment is a firewall boundary with
  **default-deny** between segments and an explicit allow-list. IoT, guests,
  cameras, printers, and "the one vendor appliance" each get their own segment.
- **Least privilege on the wire.** A web server needs `:443` in and `:5432` to
  exactly one database out — nothing else, in *either* direction.
- **Microsegmentation** — in cloud/k8s, policy per workload (Security Groups,
  `NetworkPolicy`) not per subnet.
- **Identity-aware access (ZTNA)** — access a service by authenticating the
  *user + device*, not by being on a privileged network. Replaces "VPN in and
  you're trusted".

### 5.2 Egress filtering, not just ingress

Almost everyone allow-lists inbound and lets *all* outbound go. But outbound is
how malware calls home, how data exfiltrates, how a compromised box pulls stage
2. Restrict egress to what each segment actually needs (DNS to your resolver,
NTP, HTTPS to known destinations). At minimum, log it and know what "normal"
looks like so anomalies stand out.

### 5.3 Protect the management plane

- Router/switch/hypervisor/IPMI admin interfaces go on a **dedicated management
  segment** reachable only from a jump host or the VPN — never from the user LAN,
  never from the internet.
- **Bastion / jump host** — one hardened, logged, MFA'd entry point; everything
  else has no inbound SSH at all. (This repo's lab: `linux/ssh/ssh-config.md`
  `ProxyJump`, `aws/` bastion.)
- No credentials in configs; key-based SSH, short-lived certs
  (`linux/ssh/ssh-ca.md`).

### 5.4 DNS security

- **DoT / DoH** (DNS over TLS/HTTPS) — encrypts client↔resolver so the path can't
  snoop or tamper. Run your own resolver doing DoT upstream rather than sending
  every lookup to a third party in plaintext.
- **DNSSEC** — authenticates records so a resolver can detect forged answers.
  Validate on your resolver; a `SERVFAIL` that only happens for one zone is often
  a DNSSEC failure.
- **Split-horizon** — don't leak internal names/addresses in public DNS.
- **DNS rebinding protection** — a resolver should refuse to return RFC 1918
  addresses for public names (many routers/`dnsmasq` have `--stop-dns-rebind`).

### 5.5 NAT ≠ security; IPv6 changes the assumption

"We're behind NAT so nothing can reach us" is an accident of SNAT, not a control,
and it evaporates the moment you (a) enable IPv6 (global addresses, no NAT),
(b) run a port-forward, or (c) have a host that opens an outbound tunnel. Run an
actual **stateful firewall** with an explicit inbound policy on both address
families.

### 5.6 Encrypt in transit, everywhere

- TLS for anything over a network, including "internal" — internal networks get
  breached. See [`../linux/tls-pki/`](../linux/tls-pki/).
- **mTLS** for service-to-service (both ends present certs) — the network-level
  version of zero trust; a service mesh or an internal CA issues the certs.
- WireGuard for site-to-site and remote access — small, fast, modern crypto,
  easy to audit.

### 5.7 Observability

You can't spot abnormal traffic if you never looked at normal.

- **Flow logs / NetFlow** (VPC Flow Logs in cloud) — who talked to whom, how
  much. The first thing you want during an incident.
- **Kernel counters** (`nstat`, `ip -s link`, `ethtool -S`) — retransmits,
  drops, errors trending up.
- Baseline your egress destinations and DNS query volume.

---

## 6. Diagnostics: a method

### 6.1 Walk the ladder bottom-up

"Can't reach `service.example.com`" — don't guess, narrow it:

```
  1. LINK      ip -br link              interface UP? has carrier?
               ethtool <if>             "Link detected: yes"?
                 └─ down → cable / switchport / driver / Wi-Fi auth

  2. ADDRESS   ip -br addr              got a real address? (not 169.254.x = no DHCP)
               ip route                 is there a default route?

  3. GATEWAY   ping -c2 <gateway>       gateway answers?
               arping -I <if> <gw>      …at L2, if it filters ICMP?
                 └─ no → wrong subnet/mask, VLAN mismatch, gateway down

  4. ROUTE     ip route get <dstIP>     which iface + next-hop? expected?
                 └─ wrong iface → route table / metric / policy-routing

  5. PATH      tracepath <dstIP>        where does it stop? path MTU sane?
                 └─ stops early → routing hole / firewall mid-path
                 └─ pmtu < 1500 → MTU black hole (see 2.6)

  6. DNS       getent hosts <name>      app's view resolves?
               dig +short <name> @8.8.8.8   resolves via a known-good server?
               dig +short <name>        …via the configured resolver?
                 └─ getent ok, dig fails → /etc/hosts (fine or stale)
                 └─ @8.8.8.8 ok, local fails → your resolver is broken
                 └─ both fail → the record / zone is broken

  7. TRANSPORT nc -zv -w2 <host> <port>  TCP port open?
               ss -tnp                   is a local proxy/tunnel involved?
                 └─ refused → service down / wrong port / bound to 127.0.0.1
                 └─ timeout → firewall dropping (silent), or return path broken

  8. APP/TLS   curl -v https://<host>/   HTTP status? redirect loop?
               curl -w timing template   where's the latency?
               openssl s_client …        cert valid? chain complete? expired?
```

Stop at the first step that fails — that layer is the bug. Everything above it
was a red herring.

### 6.2 Failure-signature quick reference

| Symptom | Likely cause | Confirm | Layer |
|---|---|---|---|
| Address is `169.254.x.x` | no DHCP answer | `journalctl -u NetworkManager`; check DHCP server / VLAN | 2 |
| Ping to gateway fails, address looks right | wrong netmask / VLAN, gateway down | `ip -br addr`, `arping` | 2–3 |
| Small requests OK, large ones hang | **PMTU black hole** / tunnel MTU | `ping -M do -s 1472`; `tracepath` | 3 |
| Works one direction only / random drops | **asymmetric routing** + `rp_filter` | `sysctl net.ipv4.conf.all.rp_filter`; check both route tables | 3 |
| Resolves externally, `SERVFAIL` internally | broken forwarder / DNSSEC / split-horizon | `dig +trace`, `dig +cd`, `dig @<internal-ns>` | DNS |
| `getent` and `dig` give different answers | `/etc/hosts`, nsswitch order, local stub | `cat /etc/hosts`, `/etc/nsswitch.conf` | DNS |
| Name has stale IP for minutes | DNS **TTL** / negative caching | check record TTL; `resolvectl flush-caches` | DNS |
| TCP connect **refused** (fast) | service down, or bound to `127.0.0.1` only | `ss -tlnp` on the server | 4 |
| TCP connect **times out** (slow) | firewall silently dropping, or no return route | check firewall counters; `ip route` on the far side | 3–4 |
| Outbound from private hosts stopped working | **MASQUERADE/SNAT** rule gone, `ip_forward=0` | `sudo nft list ruleset`; `sysctl net.ipv4.ip_forward`; [`net-check.md`](net-check.md) | 3 |
| Inbound port-forward stopped | DNAT rule gone, ISP moved you to **CGNAT** | `dig +short myip.opendns.com @resolver1.opendns.com` vs the WAN IP | 3 |
| Intermittent failures under load | **conntrack table full** | `dmesg | grep conntrack`; `sysctl net.netfilter.nf_conntrack_count max` | 3–4 |
| Inside host can't reach another via the public IP | **hairpin NAT** not supported | use split-horizon DNS → inside address | 3 |
| curl works, browser fails (or vice-versa) | missing TLS **intermediate** cert | `openssl s_client -showcerts` → expect ≥ 2 certs | 7 |
| Cert "expired" only on some clients | clock skew, or cross-signed chain change | check `notAfter`, client trust store | 7 |
| IPv6-preferred host slow to connect | broken IPv6, waiting to fall back to v4 | `curl -6`, `ip -6 route`; **Happy Eyeballs** masks it | 3 |

### 6.3 Before you dig in

- **What changed?** New firmware, a config push, a cert rotation, an ISP notice,
  a cloud change-set. Most breakage is a change, not entropy.
- **Scope it.** One host or all? One destination or all? One protocol or all?
  Inbound, outbound, or both? Each answer removes half the ladder.
- **Reproduce minimally.** `nc -z`, `dig`, one `curl` — not "the app is down".

---

## See Also

- [`net-tools.md`](net-tools.md) — the command reference for every tool named here
- [`net-check.md`](net-check.md) — scripted NAT / IP-forwarding verification for the lab
- [`iptab.md`](iptab.md) — iptables/nftables rule syntax + explainer script
- [`network.md`](network.md) — subnet-scan one-liners
- [`kubelet-DNS-error.md`](kubelet-DNS-error.md) — a worked DNS failure diagnosis (CoreDNS)
- [`../linux/sysadmin/firewalld.md`](../linux/sysadmin/firewalld.md) — zone-based firewall, masquerade, rich rules
- [`../linux/ssh/ssh-config.md`](../linux/ssh/ssh-config.md) · [`../linux/ssh/port-forwarding.md`](../linux/ssh/port-forwarding.md) — jump hosts, tunnels, SOCKS
- [`../linux/ssh/dynamic-ip-access.md`](../linux/ssh/dynamic-ip-access.md) — CGNAT, DDNS, reaching a box with no public IP
- [`../linux/ssh/restricted-networks.md`](../linux/ssh/restricted-networks.md) — DPI, egress restrictions, tunnelling out
- [`../linux/tls-pki/`](../linux/tls-pki/) — TLS/PKI, cert chains, mTLS
- [`../aws/`](../aws/) — the VPC / subnet / NLB lab this guide's §3.4 describes
- [`../k8s/README.md`](../k8s/README.md) — cluster networking, ingress, NetworkPolicy
- [`../GLOSSARY.md`](../GLOSSARY.md) — initialisms used here
