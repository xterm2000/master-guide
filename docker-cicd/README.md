# Docker CI/CD Home Lab

A self-contained CI/CD stack running on a single VM, with portless hostnames via Pi-hole DNS + Traefik reverse proxy.

```
Git push → Gitea webhook → Jenkins pipeline → Docker build → Nexus registry
```

## Stack

| Service   | Role                          | Portless URL          | Direct URL                    |
|-----------|-------------------------------|-----------------------|-------------------------------|
| Traefik   | Reverse proxy + dashboard     | —                     | `http://<VM>:8888`            |
| Jenkins   | CI/CD pipelines               | `http://jenkins.home` | `http://<VM>:8080` (no label) |
| Nexus     | Artifact + Docker image repo  | `http://nexus.home`   | `http://<VM>:8081` (no label) |
| Gitea     | Git hosting + webhooks        | `http://gitea.home`   | `http://<VM>:8085` (no label) |
| pgAdmin   | PostgreSQL GUI                | `http://pgadmin.home` | —                             |
| Jaeger    | Distributed tracing UI        | —                     | `http://<VM>:16686`           |
| Pi-hole   | Local DNS (separate compose)  | —                     | `http://<VM>:8053/admin`      |
| Homepage  | Dashboard (Traefik fallback)  | `http://<VM>`         | —                             |

> Nexus Docker registries `:8082` (hosted) and `:8083` (proxy) are TCP — access them with ports directly, Traefik HTTP routing does not apply.

---

## Architecture

```
Client
  │
  └─► Pi-hole :53 — resolves *.home → VM IP
         │
         └─► Traefik :80 — routes by Host header
                │
                ├─► jenkins:8080
                ├─► nexus:8081
                ├─► gitea:3000
                └─► pgadmin:80

Jenkins ──────────────────────────────────────────► DinD sidecar (docker:dind)
  │  builds images via tcp://dind:2376                │
  └──► pushes to Nexus :8082                          └─ isolated Docker daemon

Traefik ──────────────────────────────────────────► socket-proxy (read-only)
  │  reads container labels via tcp://socket-proxy:2375
```

**Security model:** Traefik reads container metadata through `tecnativa/docker-socket-proxy` (read-only, no POST). Jenkins builds images via a Docker-in-Docker sidecar (`docker:dind`) instead of mounting the host socket — the DinD daemon is isolated in a named volume.

---

## Prerequisites

- Linux VM with Docker + Docker Compose v2
- VM IP: `192.168.68.200` (update Pi-hole DNS records and `.env` if yours differs)
- Ports open on VM: `53` (Pi-hole), `80`, `8053`, `8080`, `8081`, `8082`, `8083`, `8085`, `8888`, `16686`, `222`

---

## Quick Start

### 1 — Create host data directories

```bash
chmod +x data-dirs.sh && sudo ./data-dirs.sh
```

This creates and chowns:

| Path                          | Owner       | Service  |
|-------------------------------|-------------|----------|
| `/opt/devops/postgres/data`   | root        | Postgres |
| `/opt/devops/postgres/initdb` | root        | Postgres |
| `/opt/devops/pgadmin/data`    | 5050:5050   | pgAdmin  |
| `/opt/devops/jenkins/home`    | root        | Jenkins  |
| `/opt/devops/nexus/home`      | 200:200     | Nexus    |
| `/opt/devops/gitea/data`      | root        | Gitea    |

### 2 — Copy init scripts to Postgres

```bash
sudo cp pg-init-scripts/*.sql /opt/devops/postgres/initdb/
```

These run once on first `postgres` container start and create:
- `admin` superuser (password from `.env`)
- `gitea` user + `gitea` database (Gitea's backend)
- `mitek` user + `dbviz` database with `onair` schema (optional tooling DB)

### 3 — Configure environment

```bash
cp .env.example .env
# edit .env — set passwords at minimum
```

Key variables:

```env
POSTGRES_PASSWORD=<strong password>
GITEA_DB_PASS=<strong password>
ALLOWED_WEBHOOK_HOST=192.168.68.200   # your VM IP
PGADMIN_DEFAULT_EMAIL=admin@local.dev
PGADMIN_DEFAULT_PASSWORD=<password>
```

### 4 — Start the stack

Traefik and socket-proxy always start (no profile). Use profiles for everything else:

```bash
# Everything at once
docker compose --profile ci --profile scm --profile db --profile tracing up -d

# Or selectively — CI chain only
docker compose --profile ci --profile scm --profile db up -d
```

Profile map:

| Profile    | Services started                    |
|------------|-------------------------------------|
| `ci`       | Jenkins, DinD, Nexus                |
| `scm`      | Gitea (requires `db` profile)       |
| `db`       | Postgres, pgAdmin                   |
| `tracing`  | Jaeger                              |
| *(none)*   | Traefik, socket-proxy, homepage     |

### 5 — Start Pi-hole (separate compose)

```bash
cd pihole
docker compose up -d
cd ..
```

Pi-hole UI: `http://<VM>:8053/admin` — default password is `changeme` (set via `FTLCONF_webserver_api_password` in `pihole/docker-compose.yaml`).

DNS records are pre-configured in the compose via `FTLCONF_dns_hosts` — all `*.home` names point to `192.168.68.200`.

### 6 — Point your machine at Pi-hole for DNS

**Windows:** Network adapter → IPv4 → Preferred DNS: `192.168.68.200`, Alternate: `8.8.8.8`

**Linux** (`/etc/resolv.conf` or NetworkManager): `nameserver 192.168.68.200`

**Router DHCP** (affects all LAN devices): set Primary DNS to `192.168.68.200`, Secondary `8.8.8.8`.

After this, `http://jenkins.home` and all other `.home` names resolve from any device on the LAN.

### 7 — Configure Docker daemon to allow Nexus insecure registry

On the VM host:

```bash
# /etc/docker/daemon.json
{
  "insecure-registries": ["192.168.68.200:8082"],
  "dns": ["192.168.68.200", "8.8.8.8"]
}

sudo systemctl restart docker
docker compose --profile ci --profile scm --profile db up -d   # restart after daemon restart
```

The `dns` entry lets containers resolve `.home` names (e.g., Gitea webhook calling `http://jenkins.home`).

---

## First-Time Service Setup

### Nexus — Enable Docker Registry

1. Log in at `http://nexus.home` — default credentials: `admin` / (initial password in `/opt/devops/nexus/home/admin.password`)
2. **Administration → Security → Realms** — move **Docker Bearer Token Realm** to Active → Save
3. **Administration → Repositories → Create repository** → `docker (hosted)` → name: `docker-hosted`, HTTP port: `8082` → Save

### Jenkins — Credentials + Plugin

1. Log in at `http://jenkins.home` — follow setup wizard, install suggested plugins
2. **Manage Jenkins → Plugins → Available** — install **Generic Webhook Trigger** → restart
3. **Manage Jenkins → Credentials → System → Global → Add Credentials**:
   - Kind: Username with password
   - Username: `admin` (Nexus admin)
   - Password: Nexus admin password
   - ID: `nexus-docker-creds`

### Gitea — Initial Setup

1. First visit to `http://gitea.home` triggers the install wizard
2. Database settings are pre-configured via environment variables — just confirm and create the admin account
3. Create a repository (e.g., `my-app`)
4. Push your code:

```bash
git remote add origin http://gitea.home/<user>/my-app.git
git push -u origin master
```

### pgAdmin — First Login

1. `http://pgadmin.home` — log in with `PGADMIN_DEFAULT_EMAIL` / `PGADMIN_DEFAULT_PASSWORD` from `.env`
2. Add server: host `db`, port `5432`, user/password from `.env`

---

## CI/CD Pipeline Wiring

### Jenkins Pipeline (per app)

Create a **Pipeline** job in Jenkins. Paste this Groovy script — one job per app, change `app1` → `app2` / `app1-token` → `app2-token` for the second:

```groovy
pipeline {
    agent any

    triggers {
        GenericTrigger(
            causeString: 'Triggered by Gitea push',
            token: 'app1-token'
        )
    }

    environment {
        NEXUS_HOST  = "192.168.68.200:8082"
        IMAGE_NAME  = "app1"
        IMAGE_TAG   = "${BUILD_NUMBER}"
        FULL_IMAGE  = "${NEXUS_HOST}/${IMAGE_NAME}:${IMAGE_TAG}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scmGit(
                    branches: [[name: '*/master']],
                    userRemoteConfigs: [[url: 'http://gitea.home/<user>/my-app.git']]
                )
            }
        }
        stage('Build Docker Image') {
            steps { sh "docker build -t ${FULL_IMAGE} ./app1" }
        }
        stage('Push to Nexus') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'nexus-docker-creds',
                    usernameVariable: 'NEXUS_USER',
                    passwordVariable: 'NEXUS_PASS'
                )]) {
                    sh """
                        echo "${NEXUS_PASS}" | docker login ${NEXUS_HOST} -u ${NEXUS_USER} --password-stdin
                        docker push ${FULL_IMAGE}
                        docker logout ${NEXUS_HOST}
                    """
                }
            }
        }
    }
    post { always { sh "docker rmi ${FULL_IMAGE} || true" } }
}
```

### Gitea Webhooks

In Gitea: **Repository → Settings → Webhooks → Add Webhook → Gitea**

| Field        | app1                                                                  | app2                                                                  |
|--------------|-----------------------------------------------------------------------|-----------------------------------------------------------------------|
| Target URL   | `http://jenkins.home/generic-webhook-trigger/invoke?token=app1-token` | `http://jenkins.home/generic-webhook-trigger/invoke?token=app2-token` |
| Content Type | `application/json`                                                    | `application/json`                                                    |
| Trigger      | Push events                                                           | Push events                                                           |

Click **Test Delivery** — should return HTTP 200.

> If containers can't reach `jenkins.home`, verify the Docker daemon `dns` setting from Step 7.

### Verify Images Land in Nexus

`http://nexus.home` → **Browse → docker-hosted** — images appear with build-number tags after each push.

---

## Repository Layout

```
docker-cicd/
├── .env                    # active secrets (gitignored)
├── .env.example            # template — copy to .env
├── data-dirs.sh            # creates /opt/devops/* host directories
├── docker-compose.yaml     # main stack (profiles: ci, scm, db, tracing)
├── docker-compose-old.yaml # reference: pre-DinD, pre-Traefik version
├── homepage/
│   └── index.html          # dashboard served by Traefik fallback route
├── pg-init-scripts/
│   ├── 01_admin.sql        # rename/set superuser password
│   ├── 02_gitea.sql        # gitea user + database
│   └── 03_dbviz.sql        # optional tooling database
├── pihole/
│   └── docker-compose.yaml # Pi-hole DNS — run separately
├── docker-security.md      # socket proxy vs DinD security rationale
├── jenkins.md              # detailed Jenkins + Gitea + Nexus setup guide
└── localdns.md             # Pi-hole + Traefik DNS options and decision guide
```

---

## Detailed Guides

- **[jenkins.md](jenkins.md)** — full step-by-step CI/CD wiring with troubleshooting table
- **[localdns.md](localdns.md)** — DNS options (with/without ports), router vs per-device, Docker daemon DNS
- **[docker-security.md](docker-security.md)** — socket mounting risks, socket-proxy and DinD security model

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `docker push` to Nexus fails with HTTP error | Insecure registry not allowed | Add to `/etc/docker/daemon.json`, restart Docker |
| Nexus login returns 401 | Docker Bearer Token Realm inactive | Nexus → Security → Realms |
| Webhook returns connection refused | Containers can't resolve `.home` | Add `dns` to `/etc/docker/daemon.json` |
| Gitea webhook blocked | Local IP blocked by default | `GITEA__webhook__ALLOWED_HOST_LIST` in compose (already set) |
| `GenericTrigger` compile error in Jenkins | Plugin not installed | Install Generic Webhook Trigger, restart |
| Pi-hole won't bind port 53 | Host `systemd-resolved` holds :53 | `sudo systemctl stop systemd-resolved` and disable stub listener |
| Services don't resolve `*.home` from browser | Device not using Pi-hole DNS | Set DNS on device or router |
| Nexus slow to start | JVM startup | Wait ~2 min; check with `docker logs nexus` |

### Reset everything

```bash
# stop and remove containers
docker compose --profile ci --profile scm --profile db --profile tracing down

# nuke data (WARNING: destroys all state)
sudo rm -rf /opt/devops/postgres /opt/devops/pgadmin /opt/devops/jenkins /opt/devops/nexus /opt/devops/gitea

# re-init
sudo ./data-dirs.sh
sudo cp pg-init-scripts/*.sql /opt/devops/postgres/initdb/
docker compose --profile ci --profile scm --profile db up -d
```
