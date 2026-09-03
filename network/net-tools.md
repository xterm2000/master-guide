# Small Network Tools

The single-purpose connectivity / name-resolution / socket / capture tools that
show up mid-debug and rarely get explained on their own. Start with the dispatch
table — find your situation, jump to the tool. Then the Recipes section chains
them into the questions you actually ask ("is it DNS or the route?").

Verified on Rocky Linux 10.2: iproute2 6.17.0 (`ip`, `ss`, `bridge`, `tc`,
`nstat`), BIND `dig` 9.18.33 / `host` / `nslookup`, iputils (`ping`, `arping`,
`tracepath`), nmap 7.92 (`nmap`, `ncat`), curl 8.12.1, wget 1.x, OpenSSL 3.5.5,
ethtool 6.15, NetworkManager 1.56 (`nmcli`), nftables 1.1.5, iptables 1.8.11
(nf_tables backend), systemd 257 (`resolvectl`).

Firewall rule syntax has its own doc: [`iptab.md`](iptab.md) (+
[`iptab-explain.sh`](iptab-explain.sh)). NAT / IP-forwarding lab checks:
[`net-check.md`](net-check.md). This doc covers the diagnostic tools around them.

All addresses, hostnames and MACs below are placeholders
(`198.51.100.0/24`, `example.com`, `aa:bb:cc:...`) — RFC 5737 / RFC 2606.

---

## If you need to…

### Interfaces, addresses, routes

| Situation | Reach for | § |
|---|---|---|
| List interfaces + their IPs, one line each | `ip -br addr` | [ip addr / link](#ip-addr--ip-link) |
| See link state, MAC, MTU, driver counters | `ip -s link`, `ethtool -i` | [ip addr / link](#ip-addr--ip-link) · [ethtool](#ethtool) |
| Show the routing table / **which** route a destination takes | `ip route`, `ip route get <ip>` | [ip route](#ip-route) |
| See the ARP / neighbour cache (is the MAC known?) | `ip neigh` | [ip neigh](#ip-neigh) |
| Machine-readable output for scripts | add `-j` (JSON) → pipe to `jq` | [ip route](#ip-route) |
| Manage the *persistent* config (DNS, addresses, autoconnect) | `nmcli` | [nmcli](#nmcli) |
| Inspect a Linux bridge (docker0, br-*) and its ports | `bridge link`, `ip -br link` | [bridge](#bridge) |

### Name resolution

| Situation | Reach for | § |
|---|---|---|
| Resolve a name **the way libc does** (nsswitch: hosts file + DNS) | `getent hosts <name>` | [getent hosts](#getent-hosts) |
| Query DNS directly, one record | `dig +short <name> [type]` | [dig](#dig) |
| Readable answer with TTLs | `dig +noall +answer <name>` | [dig](#dig) |
| Walk the delegation from the root (find the broken zone) | `dig +trace <name>` | [dig](#dig) |
| Ask a *specific* resolver, bypassing `/etc/resolv.conf` | `dig @<server> <name>` | [dig](#dig) |
| Quick MX / NS / TXT lookup | `host -t MX <name>` | [host / nslookup](#host--nslookup) |
| See what resolver(s) the system is actually using | `cat /etc/resolv.conf`, `resolvectl status` | [resolvectl](#resolvectl) |

### Can I reach it? (L3 / L4)

| Situation | Reach for | § |
|---|---|---|
| Is the host up / what's the RTT | `ping -c4 <ip>` | [ping](#ping) |
| Is a **TCP port** open (no payload sent) | `nc -zv -w2 <host> <port>` | [nc / ncat](#nc--ncat) |
| Sweep a subnet for live hosts | `nmap -sn <cidr>` | [nmap](#nmap) |
| Scan ports on one host | `nmap -Pn -p <ports> <host>` | [nmap](#nmap) |
| Trace the path hop by hop (also discovers path MTU) | `tracepath <ip>` | [tracepath](#tracepath) |
| Is the *gateway* alive at L2 (ARP, ignores IP filtering) | `arping -c3 -I <if> <gw>` | [arping](#arping) |
| Find the largest un-fragmented packet (MTU / VPN issues) | `ping -M do -s <size> <ip>` | [ping](#ping) |

### Can I reach it? (L7 — HTTP / TLS)

| Situation | Reach for | § |
|---|---|---|
| Fetch a URL, show request/response headers | `curl -v <url>` | [curl](#curl) |
| Just the status code | `curl -sS -o /dev/null -w '%{http_code}\n' <url>` | [curl](#curl) |
| **Where** the time goes (DNS vs connect vs TLS vs TTFB) | `curl -w` timing template | [curl](#curl) |
| Test one backend IP without touching DNS | `curl --resolve <host>:<port>:<ip> <url>` | [curl](#curl) |
| Inspect the served TLS cert / chain / expiry | `openssl s_client -connect <host>:443 -servername <host>` | [openssl s_client](#openssl-s_client) |
| Reachability only, no body download | `wget -qO- --spider <url>` | [wget](#wget) |

### What's listening / who owns a port

| Situation | Reach for | § |
|---|---|---|
| All listening TCP+UDP sockets + owning PID | `ss -tulpn` | [ss](#ss) |
| Established connections to/from a port | `ss -tnp '( dport = :443 or sport = :443 )'` | [ss](#ss) |
| Summary counts (estab / timewait / by transport) | `ss -s` | [ss](#ss) |
| Which process holds a port (alt to `ss`) | `lsof -i :<port>`, `fuser <port>/tcp` | [lsof -i / fuser](#lsof--i--fuser) |

### Watch traffic / counters

| Situation | Reach for | § |
|---|---|---|
| Per-protocol kernel counters (retransmits, drops, errors) | `nstat`, `nstat -az` | [nstat](#nstat) |
| Live socket list refresh | `watch -n1 'ss -tnp'` | [ss](#ss) |
| Full packet capture / decode | `tcpdump` *(not installed — see [below](#not-installed-here-but-worth-knowing))* | — |

### Move bytes / bend connections

| Situation | Reach for | § |
|---|---|---|
| One-off listener to test if traffic arrives | `ncat -lvk <port>` | [nc / ncat](#nc--ncat) |
| Send a raw line to a service and read the reply | `printf '...\r\n' \| ncat <host> <port>` | [nc / ncat](#nc--ncat) |
| Forward a local port through a jump host | `ssh -L <lport>:<target>:<tport> <jump>` | [ssh port-forward](#ssh-port-forwarding) |
| Reach a remote-only service via SOCKS | `ssh -D 1080 <host>` + `curl --socks5-hostname` | [ssh port-forward](#ssh-port-forwarding) |

### Firewall / kernel network state

| Situation | Reach for | § |
|---|---|---|
| Show the live ruleset | `sudo nft list ruleset` / `sudo iptables -S` | [nft / iptables](#nft--iptables) |
| Is forwarding on | `sysctl net.ipv4.ip_forward` | [sysctl net.*](#sysctl-net) |
| Reverse-path filter dropping asymmetric traffic? | `sysctl net.ipv4.conf.all.rp_filter` | [sysctl net.*](#sysctl-net) |
| Rule-writing reference | — | [`iptab.md`](iptab.md) |

---

# Interfaces, addresses, routes

## ip addr / ip link

`ip` is the one tool for everything L2/L3 on the host. `-br` (brief) gives one
line per interface; `-j` gives JSON.

```bash
ip -br addr                     # iface | state | addresses, one line each
ip -br link                     # iface | state | MAC | flags
ip addr show ens160             # full detail for one interface
ip -s link show ens160          # + RX/TX packets, errors, drops, overruns
ip -j addr | jq -r '.[].ifname' # scriptable

ip addr add 198.51.100.9/24 dev ens160   # transient (gone on reboot / NM resync)
ip link set ens160 mtu 1400              # transient
```

`ip` changes are **runtime only** — NetworkManager owns the persistent config
here, so use `nmcli` for anything that must survive a reboot.

Interface counters worth reading in `ip -s link`: **errors** (bad frames),
**dropped** (no buffer / no handler), **overrun** (kernel too slow). Non-zero and
climbing → cable / driver / ring-buffer problem, not a routing problem.

## ip route

```bash
ip route                        # the main table
ip route get 198.51.100.50      # EXACTLY which route+source IP this dest uses
ip route get 198.51.100.50 from 192.0.2.7   # test a specific source
ip -j route | jq -r '.[] | select(.dst=="default") | .gateway'

ip route add 10.10.0.0/16 via 198.51.100.1 dev ens160   # transient
ip rule                         # policy-routing rules (multi-table setups)
```

`ip route get` is the fast answer to "why is this traffic going out the wrong
interface" — it runs the actual kernel route lookup and prints the winner.

## ip neigh

The ARP (IPv4) / NDP (IPv6) cache — IP ↔ MAC on the local segment.

```bash
ip neigh                        # STALE / REACHABLE / DELAY / FAILED per entry
ip neigh show dev ens160
ip neigh flush dev ens160       # force re-resolution (needs privilege)
```

`FAILED` for a host on your subnet = L2 problem (host down, wrong VLAN, switch
port). `REACHABLE`/`STALE` with a MAC = ARP is fine, look higher up.

## bridge

Linux bridges (`docker0`, `br-*` from Docker networks, libvirt `virbr*`).

```bash
ip -br link | grep -E 'docker0|br-|virbr'   # the bridges
bridge link                                  # veth ports and their master bridge
bridge fdb show br docker0                    # MAC forwarding table of the bridge
```

Handy when a container can't talk out: confirm its `veth` is enslaved to the
bridge you think it is.

---

# Name resolution

## getent hosts

Resolves a name **exactly the way an application does** — through
`/etc/nsswitch.conf`, so it honours `/etc/hosts`, `dig` does not.

```bash
getent hosts example.com        # -> 198.51.100.4  example.com
getent hosts myserver           # picks up /etc/hosts entries and search domains
getent ahosts example.com       # all address families, with socket types
```

**If `getent` and `dig` disagree, the cause is `/etc/hosts`, nsswitch order, or a
local caching stub** — not the upstream DNS.

## dig

Talks straight to a DNS server. Does **not** read `/etc/hosts`.

```bash
dig +short example.com                 # just the answer data
dig +short example.com MX
dig +noall +answer example.com         # answer section with TTLs, no cruft
dig example.com A example.com AAAA      # multiple queries in one call

dig @8.8.8.8 example.com                # ask a specific resolver
dig @198.51.100.2 example.com           # e.g. the internal one directly

dig +trace example.com                  # walk root -> TLD -> authoritative
dig -x 198.51.100.4                      # reverse (PTR) lookup
dig +short CHAOS TXT version.bind @<ns>  # identify a nameserver
```

Reading the output:
- **`status: NOERROR`** + an ANSWER section → resolution works.
- **`status: NXDOMAIN`** → the name definitively does not exist.
- **`status: SERVFAIL`** → the resolver broke trying (DNSSEC failure, upstream
  timeout, broken forwarder). Retry with `+cd` (checking disabled) to test for
  DNSSEC; try `@8.8.8.8` to isolate *your* resolver vs the zone.
- **no ANSWER, only AUTHORITY (SOA)** → name exists in the zone but not that type.
- **`;; connection timed out; no servers could be reached`** → the resolver
  itself is unreachable — a routing/firewall problem, not DNS.

`+trace` is the tool for "resolves on 8.8.8.8 but SERVFAILs internally" — it
shows which delegation step fails.

## host / nslookup

Terser than `dig` for a quick check; `nslookup` is interactive-friendly and
familiar from other OSes.

```bash
host example.com                # A, AAAA, MX in one shot
host -t MX example.com
host 198.51.100.4               # reverse
nslookup example.com
nslookup example.com 8.8.8.8    # against a specific server
```

Prefer `dig` when you need to see flags, TTLs, or the section structure.

## resolvectl

Front-end to `systemd-resolved`. **Only meaningful when `systemd-resolved` is
running** (`systemctl is-active systemd-resolved`). On this box resolved is
inactive and `/etc/resolv.conf` is written directly by NetworkManager, so
`resolvectl status` errors out — read `/etc/resolv.conf` and use `nmcli` instead.

```bash
resolvectl status                       # per-link DNS servers, search domains, DNSSEC
resolvectl query example.com            # resolve via resolved (shows cache/link)
resolvectl statistics                   # cache hits/misses
resolvectl flush-caches
```

Always-valid alternative:

```bash
cat /etc/resolv.conf                    # the nameservers libc will use
nmcli dev show ens160 | grep -i dns     # what NM configured for the link
```

---

# Can I reach it?

## ping

```bash
ping -c4 198.51.100.1              # 4 packets then stop
ping -c1 -W1 198.51.100.1          # 1 packet, 1s timeout — scriptable liveness
ping -i 0.2 -c20 198.51.100.1      # faster interval (root for <0.2 in some builds)
ping -D 198.51.100.1              # timestamp each line

# Path-MTU / VPN / tunnel MSS problems: largest payload that gets through undivided
ping -M do -s 1472 -c1 198.51.100.1   # 1472 + 28 hdr = 1500; shrink until it passes
```

No reply ≠ down — many hosts and firewalls drop ICMP echo. Confirm with a TCP
check (`nc -z`) before concluding the host is offline.

## nc / ncat

`nc` here is **`ncat`** (from nmap). L4 reachability and ad-hoc sockets.

```bash
nc -zv -w2 example.com 443         # port open? -z = scan (no data), -v = report
nc -zv -w2 example.com 20-25       # small range
nc -zuv -w2 198.51.100.2 53        # UDP (less reliable — no handshake)

# talk to a service
printf 'GET / HTTP/1.0\r\nHost: example.com\r\n\r\n' | ncat example.com 80
ncat -C example.com 25 <<<'EHLO test'   # -C = send CRLF line endings

# listeners (quick "does traffic arrive here" test)
ncat -lvk 9999                     # -l listen, -v verbose, -k keep open after client
ncat -lvk --exec "/bin/cat" 9999   # echo server
```

`nc -z` exit status is 0 on connect, non-zero otherwise — good for scripts.

## nmap

Host discovery and port scanning. (Also `network.md`'s subnet-sweep snippets.)

```bash
nmap -sn 198.51.100.0/24                    # ping sweep, no port scan — live hosts
nmap -sn 198.51.100.0/24 | grep report      # just the addresses
nmap -sn 198.51.100.100-110                  # range

nmap -Pn -p 22,80,443 198.51.100.4           # scan ports, skip host-discovery
nmap -Pn -p- --min-rate 1000 198.51.100.4    # all 65535, faster
nmap -sV -p 443 198.51.100.4                  # probe service/version banners
nmap -sU -p 53,123,161 198.51.100.4          # UDP scan (slow, needs root)
```

`-Pn` matters on networks that block ping — without it nmap may skip a host it
thinks is down. Only scan networks you're allowed to.

## tracepath

Hop-by-hop path trace. `traceroute` and `mtr` are **not installed**; `tracepath`
ships with iputils and needs no privilege.

```bash
tracepath 198.51.100.50           # hops + per-hop RTT + path MTU discovery
tracepath -n 198.51.100.50        # numeric, skip reverse-DNS (faster)
tracepath -m 10 198.51.100.50     # cap hops
```

The final `Resume: pmtu NNNN` line is the discovered path MTU — a low value
explains "small requests work, large ones hang".

## arping

ARP-level probe: proves L2 connectivity even when ICMP/IP is filtered. Good for
"is the gateway there" and duplicate-IP detection.

```bash
IF=$(ip route show default | awk '{print $5; exit}')
GW=$(ip route show default | awk '{print $3; exit}')
arping -c3 -I "$IF" "$GW"          # unicast replies + MAC of the gateway
arping -D -c2 -I "$IF" 198.51.100.9   # -D: is this address already in use?
```

---

# Can I reach it? (L7)

## curl

The Swiss-army L7 client. Beyond fetching:

```bash
curl -v https://example.com                 # full request + response headers
curl -sS -o /dev/null -w '%{http_code}\n' https://example.com   # status only
curl -sSI https://example.com               # HEAD — response headers only
curl -sS -L -o /dev/null -w '%{url_effective}\n' https://example.com  # follow redirects, show final URL

# where does the time go?
curl -sS -o /dev/null -w \
 'dns=%{time_namelookup} conn=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer} total=%{time_total}\n' \
 https://example.com

# test one backend without changing DNS / /etc/hosts
curl -sS --resolve example.com:443:198.51.100.7 -o /dev/null -w '%{http_code}\n' https://example.com

curl -sS --connect-to ::proxy.internal: https://example.com   # route via a different host
curl -4 ... / curl -6 ...                    # force address family
curl --interface 192.0.2.7 https://example.com  # force source IP
curl -x http://proxy:3128 https://example.com   # via HTTP proxy
curl --socks5-hostname localhost:1080 https://example.com   # via SSH -D SOCKS
```

The timing template turns "the site is slow" into "TLS handshake is 4s" —
a specific, fixable statement.

## wget

```bash
wget -qO- --spider https://example.com      # exit 0 if reachable, no download
wget -qO- https://example.com | head        # body to stdout
wget --server-response --spider https://example.com  # show response headers
```

Use `curl` for diagnostics; `wget` shines for recursive/retry downloads.

## openssl s_client

Inspect the TLS a server actually presents.

```bash
# cert subject / issuer / validity as served for this SNI
echo | openssl s_client -connect example.com:443 -servername example.com 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

openssl s_client -connect example.com:443 -servername example.com -showcerts   # full chain
openssl s_client -connect example.com:443 -servername example.com < /dev/null  # verify-chain + return code line
openssl s_client -connect mail.example.com:25 -starttls smtp                   # STARTTLS protocols
openssl s_client -connect example.com:443 -tls1_2 / -tls1_3                     # pin a version
```

Key lines in the output: **`Verify return code:`** (0 = OK), the
**`Certificate chain`** list (missing intermediate = chain error only some
clients hit), and **`notAfter`** for expiry. Deeper PKI walkthrough:
[`../linux/tls-pki/`](../linux/tls-pki/).

---

# Sockets / who owns a port

## ss

The modern `netstat`. `-t` TCP, `-u` UDP, `-l` listening, `-n` numeric, `-p`
process, `-a` all.

```bash
ss -tulpn                         # every listening TCP+UDP socket + PID/program
ss -tnp                           # established TCP + owning process
ss -s                             # summary: totals, estab, timewait, per-transport

# filter expressions (quote them)
ss -tnp '( dport = :443 or sport = :443 )'
ss -tn state established '( dport = :443 )'
ss -tn state time-wait
ss -tnp 'dst 198.51.100.0/24'
ss -ti dst 198.51.100.7           # -i: per-socket TCP info (rtt, cwnd, retrans)
```

`ss -ti` retransmit / rtt fields expose a lossy or congested path on an
otherwise "connected" socket.

## lsof -i / fuser

Alternative angle — from the process side.

```bash
sudo ss -tulpn | grep :11434      # usual first check
sudo lsof -i :11434               # every process with a socket on that port
sudo lsof -i tcp:11434 -sTCP:LISTEN
sudo lsof -i @198.51.100.7        # connections to/from a host
sudo fuser 11434/tcp              # just the PID(s); fuser -k 11434/tcp kills them
```

`lsof` needs the `lsof` package (`dnf install lsof`); `ss` and `fuser` are always
present.

---

# Counters

## nstat

Per-protocol kernel SNMP counters — the numbers behind "the network feels off".

```bash
nstat                             # counters that changed since last run
nstat -az                         # all counters, absolute values, don't reset
nstat -az | grep -Ei 'retrans|drop|error|listen'
```

Watch for **`TcpRetransSegs`** climbing (loss), **`TcpExtListenDrops` /
`TcpExtListenOverflows`** (accept backlog too small), **`IpInAddrErrors`**
(packets for the wrong address — misrouting). Run it, generate traffic, run it
again to see deltas.

---

# Move bytes / bend connections

## ssh port-forwarding

Not a "small tool" but the everyday tunnel. Full reference:
[`../linux/ssh/ssh-config.md`](../linux/ssh/ssh-config.md).

```bash
ssh -L 5432:db.internal:5432 jump.example.com     # local:  localhost:5432 -> db via jump
ssh -R 8080:localhost:80 remote.example.com       # remote: remote:8080 -> my localhost:80
ssh -D 1080 jump.example.com                       # SOCKS proxy on localhost:1080
ssh -N -f -L 5432:db.internal:5432 jump.example.com  # -N no shell, -f background

curl --socks5-hostname localhost:1080 https://intranet.example.com  # use the -D proxy
```

`ncat` covers the no-SSH case for a single hop:
`ncat -lk 8080 -c 'ncat target 80'`.

---

# Firewall / kernel state

## nft / iptables

Read-only inspection here — rule authoring lives in [`iptab.md`](iptab.md).

```bash
sudo nft list ruleset                     # the whole nftables ruleset
sudo nft list table inet filter
sudo iptables -S                          # rules as the commands that made them
sudo iptables -L -n -v --line-numbers     # with packet/byte counters per rule
sudo iptables -t nat -L -n -v             # NAT table (MASQUERADE / DNAT)
```

Rising **packet counters** on a DROP rule = that rule is what's blocking you.
`iptables` on Rocky 10 is the `nf_tables` backend — `iptables -S` and
`nft list ruleset` show the same rules two ways.

## sysctl net.*

```bash
sysctl net.ipv4.ip_forward                        # 1 = this host routes between ifaces
sysctl net.ipv4.conf.all.rp_filter                # reverse-path filter (2 = loose, 1 = strict)
sysctl net.ipv4.conf.all.forwarding net.ipv6.conf.all.forwarding
sysctl -a --pattern 'net.ipv4.(tcp_syncookies|somaxconn)'
sysctl net.ipv4.icmp_echo_ignore_all              # 1 = host ignores ping
```

`rp_filter=1` silently drops replies that would leave via a different interface
than the request arrived on — a classic multi-homed / asymmetric-routing trap.
Persistent settings live in `/etc/sysctl.d/*.conf` (see
[`net-check.md`](net-check.md) for the forwarding checks).

---

# nmcli

NetworkManager is authoritative for persistent config on this box. `ip`/`sysctl`
changes are transient; `nmcli` changes stick.

```bash
nmcli dev status                          # devices + connection + state
nmcli -t -f NAME,DEVICE,TYPE con show --active
nmcli dev show ens160                     # IP4/IP6 addresses, gateway, DNS, routes
nmcli con show ens160                     # every setting on the profile

# persistent edits (then bounce the connection)
nmcli con mod ens160 ipv4.dns "198.51.100.2 8.8.8.8"
nmcli con mod ens160 +ipv4.routes "10.10.0.0/16 198.51.100.1"
nmcli con mod ens160 ipv4.addresses 192.0.2.7/24 ipv4.gateway 192.0.2.1 ipv4.method manual
nmcli con up ens160                       # apply
```

`nmcli dev show <if> | grep DNS` is the reliable "what DNS is really configured"
check when `resolvectl` isn't available.

---

# ethtool

Physical / driver-level link info and counters.

```bash
ethtool -i ens160                 # driver + version (here: vmxnet3 — a VM NIC)
ethtool ens160                    # link speed, duplex, auto-neg, link detected
ethtool -S ens160                 # driver stats: rx/tx errors, drops, no-buffer
ethtool -g ens160                 # ring buffer sizes (raise on high-throughput drops)
ethtool -k ens160                 # offload features (GRO/GSO/TSO/checksum)
```

On a physical host `Speed:`/`Duplex:` mismatches explain slow links;
`ethtool -S` drop counters explain packet loss under load. On this VM the NIC is
`vmxnet3`, so speed is virtual.

---

# Not installed here, but worth knowing

| Tool | Package | Why you'd want it |
|---|---|---|
| `tcpdump` | `tcpdump` | the packet capture / decoder — `tcpdump -ni ens160 host X and port 443`, `-w file.pcap` |
| `traceroute` | `traceroute` | UDP/TCP/ICMP traceroute with more knobs than `tracepath` (`-T -p 443`) |
| `mtr` | `mtr` | `traceroute` + `ping` combined, continuously updating per-hop loss — best "where's the loss" tool |
| `socat` | `socat` | `nc` on steroids: bidirectional relays between any two of TCP/UDP/UNIX/PTY/FILE/SSL |
| `iperf3` | `iperf3` | throughput benchmark between two hosts (`iperf3 -s` / `iperf3 -c host`) |
| `conntrack` | `conntrack-tools` | list/flush the kernel NAT/connection-tracking table (`conntrack -L`) — vital for NAT debugging |
| `fping` | `fping` | fast parallel ping sweep (`fping -a -g 198.51.100.0/24`) — used in `network.md` |
| `nethogs` | `nethogs` | bandwidth **per process** |
| `iftop` / `nload` / `bmon` | resp. | bandwidth per connection / per interface, live |
| `whois` | `whois` | registration / netblock ownership for a public IP or domain |
| `ipcalc` | `ipcalc` | subnet math — network/broadcast/host-range from a CIDR |
| `bpftrace` | `bpftrace` | ad-hoc kernel tracing (`tcp_retransmit_skb`, socket latency) when counters aren't enough |

Install with `sudo dnf install <package>`. `tcpdump`, `traceroute`, `mtr` and
`bpftrace` are in the base/AppStream repos; `iperf3`, `socat`, `fping`,
`nethogs`, `iftop` need EPEL.

---

# Recipes

### Is it DNS, the route, or the service?

```bash
getent hosts example.com                 # 1. does the name resolve (app's view)?
dig +short example.com @8.8.8.8           #    ... and via a known-good resolver?
ip route get "$(dig +short example.com | head -1)"   # 2. which iface/gw for that IP?
ping -c2 -W1 "$(ip route show default | awk '{print $3;exit}')"  # 3. gateway alive?
nc -zv -w2 example.com 443                # 4. TCP port open?
curl -sS -o /dev/null -w '%{http_code} %{time_total}s\n' https://example.com  # 5. L7 OK?
```

Stop at the first step that fails — that's the layer to fix.

### Where is the latency — DNS, connect, TLS, or the app?

```bash
curl -sS -o /dev/null -w \
 'dns=%{time_namelookup}\nconnect=%{time_connect}\ntls=%{time_appconnect}\nttfb=%{time_starttransfer}\ntotal=%{time_total}\n' \
 https://example.com
```

`dns` high → resolver slow. `connect` high → network RTT / packet loss.
`tls` high → handshake / OCSP. `ttfb - tls` high → the application.

### Prove (or disprove) a TLS chain / expiry problem

```bash
echo | openssl s_client -connect example.com:443 -servername example.com 2>/dev/null \
  | openssl x509 -noout -subject -issuer -enddate
# "unable to get local issuer certificate" from curl but browsers are fine
# => server isn't sending the intermediate:
echo | openssl s_client -connect example.com:443 -servername example.com -showcerts 2>/dev/null \
  | grep -c 'BEGIN CERTIFICATE'          # expect >= 2
```

### Compare resolution across two resolvers

```bash
diff <(dig +short example.com @198.51.100.2) <(dig +short example.com @8.8.8.8)
```

Different answers → split-horizon DNS or a stale/poisoned cache on one side.

### Which process is eating the port I need

```bash
sudo ss -tulpnH "sport = :8080" || sudo lsof -i :8080
```

### Find live hosts on a subnet, then scan one

```bash
nmap -sn 198.51.100.0/24 | awk '/report for/{print $NF}'
nmap -Pn -p 22,80,443,6443 198.51.100.42
```

### Is the path MTU smaller than 1500? (VPN / tunnel hangs)

```bash
for s in 1472 1400 1300 1200; do
  ping -M do -s $s -c1 -W1 8.8.8.8 >/dev/null 2>&1 \
    && { echo "OK at payload $s ($((s+28)) on wire)"; break; }
done
tracepath -n 8.8.8.8 | tail -1           # cross-check the discovered pmtu
```

### Watch retransmits while reproducing a slow transfer

```bash
nstat -n; : run the slow thing ; nstat | grep -Ei 'retrans|drop'
```

### Reach an internal-only service from this box

```bash
ssh -N -f -L 8443:internal.example.com:443 jump.example.com
curl -sS --resolve internal.example.com:8443:127.0.0.1 https://internal.example.com:8443/
```

### Quick listener to confirm a firewall change lets traffic in

```bash
ncat -lvk 9999                            # on the target
# from the other side:
nc -zv -w3 <target> 9999
```

### What's my egress IP / does egress even work

```bash
curl -sS -4 https://ifconfig.co ; echo
curl -sS -o /dev/null -w '%{http_code}\n' --max-time 8 https://registry-1.docker.io/v2/
```

(The lab's full NAT/forwarding verification is scripted in
[`net-check.md`](net-check.md).)

---

## See Also

- [`iptab.md`](iptab.md) — nftables/iptables rule syntax and the explainer script
- [`net-check.md`](net-check.md) — NAT / IP-forwarding lab verification script
- [`network.md`](network.md) — subnet-scan one-liners (`nmap -sn`, `fping`, bash loop)
- [`kubelet-DNS-error.md`](kubelet-DNS-error.md) — CoreDNS / `resolv.conf` failure modes
- [`../linux/ssh/ssh-config.md`](../linux/ssh/ssh-config.md) — `~/.ssh/config`, `ProxyJump`, tunnelling
- [`../linux/tls-pki/`](../linux/tls-pki/) — the deep TLS/PKI / `openssl` reference
- [`../linux/text-processing/small-tools.md`](../linux/text-processing/small-tools.md) — the text-side sibling of this doc
- [`../linux/text-processing/curl-text-logs.md`](../linux/text-processing/curl-text-logs.md) — `curl` for scraping / log pipelines
