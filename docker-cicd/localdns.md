# Local DNS Setup for Home Lab

## Overview

Goal: access local services by hostname from any device on the network, without editing `/etc/hosts` on every machine.

Two flavours:
- **With port** — e.g. `http://jenkins.home:8080` — Pi-hole only, no reverse proxy needed
- **Portless** — e.g. `http://jenkins.home` — Pi-hole + Traefik reverse proxy required

---

## Architecture

### With Port (Pi-hole only)

```
192.168.68.111 (your PC)
    ↓  DNS query: jenkins.home?
Pi-hole (192.168.68.200:53)
    ↓  answers: 192.168.68.200
Browser connects to 192.168.68.200:8080  ✅
```

### Portless (Pi-hole + Traefik)

```
192.168.68.111 (your PC)
    ↓  DNS query: jenkins.home?
Pi-hole (192.168.68.200:53)
    ↓  answers: 192.168.68.200
Browser connects to 192.168.68.200:80
    ↓  Host: jenkins.home
Traefik (port 80) → forwards to jenkins container:8080  ✅
```

---

## Services

All services run on VM `192.168.68.200`.

### Internal (container → container)
Always use Docker service names — no custom DNS needed:

| Service | Internal URL |
|---------|-------------|
| Jenkins | `http://jenkins:8080` |
| Nexus UI | `http://nexus:8081` |
| Nexus Docker registry | `http://nexus:8082` |
| Gitea | `http://gitea:3000` |
| pgAdmin | `http://pgadmin:80` |

### External — With Port

| Service | URL |
|---------|-----|
| Jenkins | `http://jenkins.home:8080` |
| Nexus UI | `http://nexus.home:8081` |
| Nexus Docker registry | `http://nexus.home:8082` |
| Gitea | `http://gitea.home:3000` |
| pgAdmin | `http://pgadmin.home` |

### External — Portless (requires Traefik)

| Service | URL |
|---------|-----|
| Jenkins | `http://jenkins.home` |
| Nexus UI | `http://nexus.home` |
| Gitea | `http://gitea.home` |
| pgAdmin | `http://pgadmin.home` |
| Pi-hole UI | `http://pihole.home` |

> pgAdmin is already portless in both scenarios since it runs on port 80.

---

## Why `.home` and not `.local`?

`.local` is reserved for **mDNS (Bonjour/Avahi)** and can cause subtle conflicts on Linux/macOS.

| TLD | Notes |
|-----|-------|
| `.home` | clean, intuitive |
| `.lan` | common convention |
| `.internal` | also common |

---

## Step 1 — Pi-hole Setup

Pi-hole runs as a container on the same VM (`192.168.68.200`), separate compose file.

```yaml
# /opt/devops/pihole/docker-compose.yml
services:
  pihole:
    container_name: piholeDNS
    image: pihole/pihole:latest
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "8053:80"        # web UI — avoids conflict with Traefik on :80
    environment:
      FTLCONF_webserver_api_password: 'yourpassword'
      TZ: 'Europe/Belgrade'
    volumes:
      - ./etc-pihole:/etc/pihole
      - ./etc-dnsmasq:/etc/dnsmasq.d
    restart: unless-stopped
```

```bash
# start
docker compose up -d

# web UI
http://192.168.68.200:8053/admin
```

---

## Step 2 — Custom DNS Records in Pi-hole

### Via web UI
**Local DNS → DNS Records** → add each entry.

### Via config file (survives restarts, version-controllable)

```bash
# ./etc-pihole/custom.list
192.168.68.200  jenkins.home
192.168.68.200  nexus.home
192.168.68.200  gitea.home
192.168.68.200  pgadmin.home
192.168.68.200  pihole.home

# apply changes
docker exec piholeDNS pihole reloaddns
```

---

## Step 3 — Who Uses Pi-hole for DNS?

### Option A — Specific PC only (selective, router untouched)

Configure DNS manually on each device you want:

**Linux** (`/etc/resolv.conf` or NetworkManager):
```bash
nameserver 192.168.68.200
```

**Windows:**
```
Network adapter → IPv4 → Preferred DNS: 192.168.68.200
                          Alternate DNS:  8.8.8.8
```

**Mac:**
```
System Settings → Network → DNS → add 192.168.68.200
```

**Implications:**
- ✅ Other devices completely unaffected
- ✅ Router untouched
- ❌ Must configure each device manually

---

### Option B — All LAN devices via Router DHCP

In your router admin UI (usually `http://192.168.68.1`):
```
Primary DNS:    192.168.68.200
Secondary DNS:  8.8.8.8
```

Router pushes this to every device automatically.

**Implications:**
- ✅ Zero per-device config
- ✅ `.home` names work everywhere
- ⚠️  If Pi-hole is down, `.home` names fail — internet still works via secondary `8.8.8.8`

---

### Secondary DNS — Important Clarification

Secondary DNS is **failover only**, not a query filter or load balancer.

```
Client resolves google.com:
  → tries Primary (Pi-hole) first
  → only falls back to Secondary (8.8.8.8) if Pi-hole is DOWN
  → never splits queries between the two
```

Pi-hole already forwards all non-.home queries upstream to `8.8.8.8` instantly —
there is no meaningful overhead in routing everything through it.

---

## Step 4 — Docker Daemon DNS (so containers resolve `.home`)

Containers use Docker's internal DNS (`127.0.0.11`) by default and know nothing about `.home`.
Fix this at the daemon level so all containers inherit it:

```bash
# /etc/docker/daemon.json on the VM
{
  "dns": ["192.168.68.200", "8.8.8.8"]
}
```

```bash
# apply
sudo systemctl restart docker
```

---

## Step 5 — Traefik (portless URLs only)

Skip this section if you're happy using ports.

Add Traefik to your existing `docker-compose.yml` and label each service.
Traefik listens on port 80 and routes by `Host` header.

```yaml
services:

  traefik:
    image: traefik:v3.0
    container_name: traefik
    ports:
      - "80:80"          # all .home HTTP traffic
      - "8888:8080"      # traefik dashboard
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped

  jenkins:
    # ... your existing config ...
    # remove the ports: section (Traefik handles routing)
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.jenkins.rule=Host('jenkins.home')"
      - "traefik.http.services.jenkins.loadbalancer.server.port=8080"

  nexus:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.nexus.rule=Host('nexus.home')"
      - "traefik.http.services.nexus.loadbalancer.server.port=8081"

  gitea:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.gitea.rule=Host('gitea.home')"
      - "traefik.http.services.gitea.loadbalancer.server.port=3000"

  pgadmin:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.pgadmin.rule=Host('pgadmin.home')"
      - "traefik.http.services.pgadmin.loadbalancer.server.port=80"
```

> Nexus Docker registries (ports 8082/8083) are TCP, not HTTP — they need separate
> TCP entrypoints in Traefik, not HTTP routers. Keep accessing them with ports for now.

---

## Fallback — `/etc/hosts` (no DNS server, single machine)

```
# Linux/Mac: /etc/hosts
# Windows:   C:\Windows\System32\drivers\etc\hosts  (as Administrator)

192.168.68.200  jenkins.home
192.168.68.200  nexus.home
192.168.68.200  gitea.home
192.168.68.200  pgadmin.home
```

---

## Decision Summary

| Want | Need |
|------|------|
| `jenkins.home:8080` on one PC | Pi-hole + manual DNS on that PC |
| `jenkins.home:8080` on all LAN devices | Pi-hole + router DNS |
| `jenkins.home` (portless) on all LAN devices | Pi-hole + router DNS + Traefik |
| Containers resolve `.home` names | Docker daemon DNS → Pi-hole |

## references:
[pihole docs](https://docs.pi-hole.net)

[traefik docs](https://doc.traefik.io/traefik/)
