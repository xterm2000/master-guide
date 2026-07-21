# Docker Security Guide — Home Lab

## Overview

Two common patterns in home lab docker-compose setups carry significant security implications:
- Mounting `/var/run/docker.sock`
- Running containers as `privileged: true` / `user: root`

---

## The Docker Socket — `/var/run/docker.sock`

### What It Is

The Unix socket that the Docker CLI uses to talk to the Docker daemon.
Mounting it into a container gives that container **full control over the Docker daemon on the host**.
The daemon runs as root — so socket access = root access.

```bash
# what any process inside a container with the socket can do:
docker run -v /:/host --rm -it alpine chroot /host sh
# ↑ full root shell on the VM host
```

### Who Uses It in This Stack

| Container | Why | Risk |
|-----------|-----|------|
| Traefik | Reads container labels to auto-discover routes | Lower — read-only, passive |
| Jenkins | Builds and pushes Docker images in pipelines | **Higher** — runs arbitrary build code |

---

## `privileged: true` + `user: root`

### What They Do

| Flag | Effect |
|------|--------|
| `privileged: true` | Gives container ALL Linux kernel capabilities — nearly identical to running on bare host |
| `user: root` | Process inside container runs as root |

Together with the socket and Docker binary mounted, the container is **indistinguishable from the host** in what it can do.

### Jenkins Config (current)

```yaml
jenkins:
  image: jenkins/jenkins:lts
  privileged: true                              # full kernel capabilities
  user: root                                    # root inside container
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock # full daemon access
    - /usr/bin/docker:/usr/bin/docker           # docker CLI available
```

Any `Jenkinsfile` in any repo Jenkins builds can exploit this:

```
Malicious/compromised Jenkinsfile
    ↓
Runs docker CLI (available in container)
    ↓
Spawns privileged container mounting host filesystem
    ↓
Full root shell on VM host
```

---

## Mitigations

### [[#Option A — Docker Socket Proxy]]
### [[#Option B — Docker-in-Docker Sidecar]]

---

## Option A — Docker Socket Proxy

Run a **read-only proxy** (`tecnativa/docker-socket-proxy`) in front of the real socket.
Only whitelisted API calls are allowed through — cannot spawn containers, cannot mount host filesystem.

Works for both Traefik and Jenkins.

```yaml
services:

  socket-proxy:
    image: tecnativa/docker-socket-proxy
    container_name: socket-proxy
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      # set to 1 to allow, 0 to deny
      CONTAINERS: 1   # Traefik needs this
      IMAGES:     1   # Jenkins needs this to build
      BUILD:      1   # Jenkins needs this
      INFO:       1   # Traefik needs this to route to the right containers
      NETWORKS:   0   # Traefik doesn't need this
      SERVICES:   0   # swarm mode only
      TASKS:      0   # swarm mode only
      NODES:      0   # swarm mode only
      SWARM:      0   # swarm mode only
    restart: unless-stopped
    networks:
      - devops_net

  traefik:
    image: traefik:v3.0
    # remove: /var/run/docker.sock volume
    command:
      - "--providers.docker.endpoint=tcp://socket-proxy:2375"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
    networks:
      - devops_net

  jenkins:
    image: jenkins/jenkins:lts
    # remove: privileged, socket volume, docker binary volume
    # keep: user: root (needed to talk to proxy)
    environment:
      DOCKER_HOST: tcp://socket-proxy:2375
    volumes:
      - /opt/devops/jenkins/home:/var/jenkins_home
    networks:
      - devops_net
```

**Result:** Jenkins can still build and push images — but cannot escape to the host.

---

## Option B — Docker-in-Docker Sidecar (best isolation)

Jenkins gets its own **isolated Docker daemon** (DinD container).
Completely separate from the host Docker — builds cannot reach the host at all.

```yaml
# named volume  Docker itself creates and manages the volume, 
# so Compose needs to know about it upfront to create it 
# before any container tries to use it
volumes: 
  dind-storage:

services:

  dind:
    image: docker:dind
    container_name: dind
    privileged: true          # DinD requires this — but isolated from host Docker
    environment:
      DOCKER_TLS_CERTDIR: ""  # disable TLS for simplicity on home LAN
    volumes:
      - dind-storage:/var/lib/docker
    networks:
      - devops_net
    restart: unless-stopped

  jenkins:
    image: jenkins/jenkins:lts
    container_name: jenkins
    user: root
    depends_on:
      - dind
    environment:
      DOCKER_HOST: tcp://dind:2376
      JAVA_OPTS: -Djenkins.install.runSetupWizard=true
    volumes:
      - /opt/devops/jenkins/home:/var/jenkins_home
      # no socket mount, no docker binary mount
    ports:
      - "8080:8080"
      - "50000:50000"
    networks:
      - devops_net
    restart: unless-stopped

volumes:
  dind-storage:
```

**Result:** A compromised build escapes to the DinD container only — host is untouched.

---

## Risk Comparison

| Setup | Compromised build / container can... |
|-------|--------------------------------------|
| Current (socket + privileged + root) | Full root access to VM host |
| Socket proxy | Build images, read containers — cannot escape to host |
| DinD sidecar | Escape to DinD container only — host Docker and filesystem untouched |

---

## Traefik — Socket Access Only

Traefik is lower risk than Jenkins since it only **reads** container metadata passively.
The socket proxy is still the right call — limits blast radius if Traefik itself is compromised.

```yaml
  traefik:
    image: traefik:v3.0
    container_name: traefik
    ports:
      - "80:80"
      - "8888:8080"   # dashboard
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.endpoint=tcp://socket-proxy:2375"
      - "--entrypoints.web.address=:80"
    # no socket volume needed — talks to socket-proxy instead
    networks:
      - devops_net
    restart: unless-stopped
```

---

## Bottom Line

| Concern | Recommendation |
|---------|---------------|
| Quick, home lab, low exposure | Current setup is acceptable — just be aware |
| Want basic hardening, keep Docker builds | Socket proxy (Option A) |
| Want proper isolation for Jenkins builds | DinD sidecar (Option B) |
| Both Traefik + Jenkins hardened | Socket proxy for Traefik + DinD for Jenkins |

## references:
[dind](https://www.docker.com/resources/docker-in-docker-containerized-ci-workflows-dockercon-2023/)

[socket-proxy](https://github.com/tecnativa/docker-socket-proxy)
