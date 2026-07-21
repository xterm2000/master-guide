# Jenkins + Gitea CI/CD Setup Guide

## Overview

```
Git push → Gitea webhook → Jenkins pipeline → Docker build (DinD) → Nexus registry
```

### Infrastructure (docker-compose)

All services are on `devops_net`. Traefik routes by hostname — no bare ports needed for UI access.

| Service               | URL                         | Notes                            |
|-----------------------|-----------------------------|----------------------------------|
| Jenkins               | http://jenkins.home         | via Traefik                      |
| Gitea                 | http://gitea.home           | via Traefik                      |
| Nexus UI              | http://nexus.home           | via Traefik                      |
| Nexus Docker registry | `nexus:8082` (internal)     | direct port — not behind Traefik |
|                       | `<host-ip>:8082` (external) | for K8s nodes pulling images     |
| Traefik dashboard     | http://\<host-ip\>:8888     | direct port                      |

> Jenkins has **no host port for 8080** — access is via Traefik only. Port 50000 is mapped for agent communication.

---

## Repo Structure

```
my-app/
├── app1/
│   ├── app1.py
│   ├── Dockerfile
│   └── requirements.txt
├── app2/
│   ├── app2.py
│   ├── Dockerfile
│   └── requirements.txt
├── k8s/
│   ├── app1.yaml
│   ├── app2.yaml
│   └── jaeger.yaml
└── README.md
```

Each app has its own `Dockerfile`. Jenkins builds each independently via separate pipelines.

---

## Step 1 — Nexus: Enable Docker Registry

### 1.1 Enable Docker Bearer Token Realm

1. Log into Nexus at `http://nexus.home`
2. **Administration** → **Security** → **Realms**
3. Move **Docker Bearer Token Realm** from Available → Active
4. Save

### 1.2 Create Docker Hosted Repository

1. **Administration** → **Repositories** → **Create repository**
2. Choose **docker (hosted)**
3. Fill in:
   - Name: `docker-hosted`
   - HTTP port: `8082`
4. Save

---

## Step 2 — Gitea: Create Repo and Push Code

### 2.1 Create repository

1. Log into Gitea at `http://gitea.home`
2. **+** → **New Repository** → name it `my-app` → **Create**

### 2.2 Push local code

```bash
git init
git add .
git commit -m "initial commit"
git remote add origin http://gitea.home/<user>/my-app.git
git push -u origin master
```

---

## Step 3 — DinD: Allow Insecure Registry

Jenkins uses a **DinD (Docker-in-Docker) sidecar** instead of the host Docker socket — so the insecure registry is configured inside DinD, not on the host.

Add `--insecure-registry` to the `dind` service command in `docker-compose.yaml`:

```yaml
dind:
  image: docker:dind
  container_name: dind
  privileged: true
  environment:
    DOCKER_TLS_CERTDIR: ""
  command: ["dockerd", "--host=tcp://0.0.0.0:2376", "--insecure-registry=nexus:8082"]
  volumes:
    - dind-storage:/var/lib/docker
  networks:
    - devops_net
```

Alternatively, mount a `daemon.json` file:

```bash
# create file
cat > ./dind-daemon.json <<EOF
{
  "insecure-registries": ["nexus:8082"]
}
EOF
```

```yaml
# in dind service
volumes:
  - dind-storage:/var/lib/docker
  - ./dind-daemon.json:/etc/docker/daemon.json:ro
```

Recreate DinD after changing:

```bash
docker compose --profile ci up -d dind
```

> **No changes needed on the host's `/etc/docker/daemon.json`** — the host Docker daemon is not involved in CI builds.

> **K8s nodes pulling images** still need the host IP: add `<host-ip>:8082` to each node's `/etc/docker/daemon.json` or equivalent (containerd: `/etc/containerd/config.toml`).

---

## Step 4 — Jenkins: Credentials

1. **Manage Jenkins** → **Credentials** → **System** → **Global credentials** → **Add Credentials**
2. Fill in:
   - Kind: **Username with password**
   - Username: Nexus admin username
   - Password: Nexus admin password
   - ID: `nexus-docker-creds`
3. Save

---

## Step 5 — Jenkins: Install Plugins

**Manage Jenkins** → **Plugins** → **Available plugins**, install:

- **Generic Webhook Trigger**

Restart Jenkins after install.

---

## Step 6 — Jenkins: Create Pipelines

Create two **Pipeline** jobs: `app1-pipeline` and `app2-pipeline`.

### app1-pipeline

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
        NEXUS_HOST  = "nexus:8082"        // DinD resolves via devops_net
        IMAGE_NAME  = "app1"
        IMAGE_TAG   = "${BUILD_NUMBER}"
        FULL_IMAGE  = "${NEXUS_HOST}/${IMAGE_NAME}:${IMAGE_TAG}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scmGit(
                    branches: [[name: '*/master']],
                    userRemoteConfigs: [[
                        url: 'http://gitea:3000/<user>/my-app.git'  // internal devops_net name
                    ]]
                )
            }
        }

        stage('Build Docker Image') {
            steps {
                sh "docker build -t ${FULL_IMAGE} ./app1"
            }
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

    post {
        always {
            sh "docker rmi ${FULL_IMAGE} || true"
        }
    }
}
```

### app2-pipeline

Same as above with two changes:
- `IMAGE_NAME = "app2"`
- `docker build -t ${FULL_IMAGE} ./app2`
- `token: 'app2-token'`

---

## Step 7 — Gitea: Allow Webhook Outbound Calls

By default Gitea blocks webhooks to local IPs. The `docker-compose.yaml` already wires this via `.env`:

```yaml
environment:
  - GITEA__webhook__ALLOWED_HOST_LIST=${ALLOWED_WEBHOOK_HOST}
```

Set in `.env`:

```env
ALLOWED_WEBHOOK_HOST=jenkins
```

> Use the Docker service name `jenkins` — Gitea and Jenkins are both on `devops_net` so internal DNS resolves it. No IP needed.

Restart Gitea:

```bash
docker compose --profile scm restart gitea
```

---

## Step 8 — Gitea: Add Webhooks

Go to `http://gitea.home/<user>/my-app` → **Settings** → **Webhooks** → **Add Webhook** → **Gitea**

Add two webhooks — use the **internal Jenkins address** (Gitea calls Jenkins within devops_net):

| Field        | Webhook 1 (app1)                                                          | Webhook 2 (app2)                                                          |
|--------------|---------------------------------------------------------------------------|---------------------------------------------------------------------------|
| Target URL   | `http://jenkins:8080/generic-webhook-trigger/invoke?token=app1-token`    | `http://jenkins:8080/generic-webhook-trigger/invoke?token=app2-token`    |
| Content Type | `application/json`                                                        | `application/json`                                                        |
| Trigger      | Push events                                                               | Push events                                                               |

Click **Test Delivery** — both should return HTTP 200.

---

## Testing

```bash
echo "test" >> README.md
git add . && git commit -m "test webhook trigger"
git push origin master
```

Both `app1-pipeline` and `app2-pipeline` should trigger automatically within seconds.

---

## Verifying Images in Nexus

1. Go to `http://nexus.home`
2. **Browse** → `docker-hosted`
3. You should see `app1` and `app2` with build number tags

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `docker push` fails with HTTP error | DinD missing insecure-registry | Step 3 |
| `docker: not found` in Jenkins | DinD not running or DOCKER_HOST wrong | Check `dind` container is up; env var `DOCKER_HOST=tcp://dind:2376` |
| Webhook returns connection refused | Gitea blocking local IPs | Step 7 |
| `GenericTrigger` compilation error | Plugin not installed | Step 5 |
| Pipeline doesn't trigger on push | Webhook not configured | Step 8 |
| Nexus login returns 401 | Docker Bearer Token Realm not active | Step 1.1 |
| Jenkins not reachable at jenkins.home | Traefik or hosts file missing | Add `<host-ip> jenkins.home` to `/etc/hosts` on your machine |
| Gitea clone fails in pipeline | Wrong URL (using external hostname) | Use `http://gitea:3000/...` — internal devops_net name |
