# firewalld (RHEL-based)

firewalld is a dynamic firewall manager sitting on top of the kernel's netfilter — it's the default on RHEL/Rocky/Oracle since RHEL 7, replacing the old static `iptables` service. "Dynamic" here means changes can be applied without a full reload/reconnect-drop, and configuration is organized around **zones** rather than raw chain/rule editing.

```bash
sudo firewall-cmd --state
# running
```

## Zones — the core concept

A zone is a named trust level applied to a network interface (or source). Every packet is evaluated against whichever zone its incoming interface belongs to.

```bash
sudo firewall-cmd --get-zones
# block dmz docker drop external home internal nm-shared public trusted work
```

```bash
sudo firewall-cmd --get-default-zone
# public
sudo firewall-cmd --get-active-zones
# public
#   interfaces: ens160
```

`public` is the out-of-the-box default zone on this system — a reasonable default for machines exposed to less trusted networks; only explicitly-allowed services/ports get through. `trusted` allows everything; `drop` silently drops everything with no response.

## Runtime vs permanent — the most important distinction

Every change command applies to the **runtime** config by default — active immediately, gone on reload/reboot. Add `--permanent` to persist a change to disk instead, but a `--permanent` change does **not** take effect until you reload:

```bash
sudo firewall-cmd --zone=public --add-service=http            # runtime only, active now, lost on reload
sudo firewall-cmd --zone=public --add-service=http --permanent # written to disk, NOT active until reload
sudo firewall-cmd --reload                                     # re-reads permanent config into runtime, without dropping active connections
```

The standard pattern for a change you actually want to keep is to do **both** — runtime (so it's live immediately) and `--permanent` (so it survives a reload):

```bash
sudo firewall-cmd --zone=public --add-service=http
sudo firewall-cmd --zone=public --add-service=http --permanent
```

## Inspecting a zone

```bash
sudo firewall-cmd --zone=public --list-all
# public (default, active)
#   target: default
#   ...
#   interfaces: ens160
#   services: cockpit dhcpv6-client obsidian--27123 ollama-11434 ssh
#   ports:
#   protocols:
#   forward: yes
#   masquerade: no
#   rich rules:
```

`--list-services`, `--list-ports`, `--list-rich-rules` show just one field instead of the whole zone. Omitting `--zone` targets the default zone.

## Services vs ports

firewalld ships ~265 predefined **services** (`sudo firewall-cmd --get-services`) — named bundles of the ports/protocols a given daemon actually needs, e.g. `ssh` = TCP/22. Prefer opening by service name over raw ports where a definition exists — it's self-documenting and survives the daemon changing its port in a service definition update.

```bash
sudo firewall-cmd --zone=public --add-service=https --permanent
```

For anything without a predefined service, open the raw port/protocol:

```bash
sudo firewall-cmd --zone=public --add-port=8080/tcp --permanent
```

## Rich rules — when zones/services aren't granular enough

Rich rules let you match on source address, log, and allow/reject/drop in one line — useful for "allow this port, but only from this subnet" cases a plain service/port rule can't express:

```bash
sudo firewall-cmd --zone=public --add-rich-rule='rule family="ipv4" source address="10.0.0.0/24" port protocol="tcp" port="8080" accept' --permanent
sudo firewall-cmd --reload
```

## Panic mode

Immediately blocks all inbound and outbound traffic — an emergency kill switch, not a normal operating mode:

```bash
sudo firewall-cmd --panic-on
sudo firewall-cmd --query-panic
sudo firewall-cmd --panic-off
```

## Quick reference

| Task | Command |
|---|---|
| Check daemon state | `firewall-cmd --state` |
| Show default zone | `firewall-cmd --get-default-zone` |
| Show active zone(s) + interfaces | `firewall-cmd --get-active-zones` |
| List everything in a zone | `firewall-cmd --zone=ZONE --list-all` |
| Add a service (runtime) | `firewall-cmd --zone=ZONE --add-service=NAME` |
| Add a service (persist) | `firewall-cmd --zone=ZONE --add-service=NAME --permanent` |
| Add a raw port | `firewall-cmd --zone=ZONE --add-port=PORT/PROTO --permanent` |
| Apply permanent changes | `firewall-cmd --reload` |
| Remove a service | `firewall-cmd --zone=ZONE --remove-service=NAME [--permanent]` |

## Practical Recipes

### Lock down a bastion — allow only SSH from a management subnet, drop everything else on public

Rather than opening `ssh` to the whole `public` zone (any source), scope it to a specific subnet with a rich rule, and don't add the plain `ssh` service at all — the rich rule replaces it:

```bash
sudo firewall-cmd --zone=public --remove-service=ssh --permanent    # remove the blanket allow-from-anywhere
sudo firewall-cmd --zone=public --add-rich-rule='rule family="ipv4" source address="10.0.0.0/24" service name="ssh" accept' --permanent
sudo firewall-cmd --reload
sudo firewall-cmd --zone=public --list-all     # confirm: services no longer lists ssh, rich rules does
```

### Expose a Kubernetes NodePort range on a node

NodePort services default to the `30000-32767` range — open it as a single port range instead of 2700+ individual rules:

```bash
sudo firewall-cmd --zone=public --add-port=30000-32767/tcp --permanent
sudo firewall-cmd --reload
```

### Allow container traffic without fighting Docker's own iptables rules

Docker manages its own iptables chains and by default bypasses firewalld's zone restrictions for published container ports — this is a common "why can everyone reach my container despite firewalld" surprise. If you need firewalld to actually govern container traffic, put the Docker bridge interface (commonly `docker0`) into its own zone rather than relying on firewalld's default zone to catch it:

```bash
sudo firewall-cmd --zone=docker --change-interface=docker0 --permanent
sudo firewall-cmd --zone=docker --list-all
sudo firewall-cmd --reload
```

### Emergency lockout recovery

If you've applied a firewalld change over SSH and lost access, panic mode won't help (it blocks everything, including your own recovery path) — instead, keep a second open session before testing changes, or use `--timeout` to auto-revert an untested rule:

```bash
sudo firewall-cmd --zone=public --add-service=https --timeout=5m   # reverts automatically after 5 minutes if you don't make it permanent
```
