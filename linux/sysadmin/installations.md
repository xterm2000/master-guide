# Installations Reference

All install commands for tools used across this repo. RHEL 9/10 family (Rocky, Oracle Linux) — dnf.

---

## System Prerequisites

### EPEL Repository (required for many packages)

```bash
# Rocky Linux / AlmaLinux
sudo dnf install epel-release -y

# RHEL 8
sudo dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm -y

# RHEL 9
sudo dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm -y
```

### CodeReady Builder (CRB) — needed by some EPEL packages

```bash
# Rocky Linux / AlmaLinux
sudo dnf config-manager --set-enabled crb

# RHEL 8
sudo subscription-manager repos --enable codeready-builder-for-rhel-8-x86_64-rpms

# RHEL 9
sudo subscription-manager repos --enable codeready-builder-for-rhel-9-x86_64-rpms
```

CRB mostly holds `-devel` and `-static` packages for libraries that AppStream
doesn't already cover — needed for building/rebuilding software from source,
not for running it. Verified against this box's `crb` repo metadata
(`dnf repoquery --repo=crb`, ~1,290 packages): most mainstream toolchain
packages (`gcc`, `cmake`, `make`, `python3-devel`, `glibc-devel`,
`openssl-devel`) are already in AppStream/BaseOS and don't need CRB. What
CRB actually adds includes static-linking variants (`glibc-static`,
`libstdc++-static`), less common library headers (`gpgme-devel`,
`boost-mpich-devel`, `boost-openmpi-devel`, `criu-devel`), and
desktop/niche-library `-devel` packages most servers never touch.

---

## Core System Tools

```bash
# Base networking + utilities
sudo dnf install -y net-tools nmap mlocate

# SSH client + server
sudo dnf install -y openssh-clients openssh-server

# Compiler / debugger toolchain
sudo dnf install -y gcc gcc-c++ gdb make

# Podman (also installed by the Kubespray bootstrap in Kubernetes > Kubespray, below)
sudo dnf install -y podman

# Common lab tools (all-in-one for bastion node)
sudo dnf install -y git vim jq nc bind-utils

# Shell completion
sudo dnf install -y bash-completion
```

---

## DNS / Proxy / Load Balancer (node-level)

```bash
# dnsmasq — lightweight DNS/DHCP
sudo dnf install -y dnsmasq
sudo systemctl enable --now dnsmasq

# NGINX — reverse proxy / web server
sudo dnf install -y nginx
sudo systemctl enable --now nginx

# HAProxy — TCP/HTTP load balancer
sudo dnf install -y haproxy
sudo systemctl enable --now haproxy
```

---

## Network / DNS Tools

```bash
# DNS lookup tools (nslookup, dig)
sudo dnf install -y bind-utils

# Multi-target ping scanner (EPEL)
sudo dnf install -y fping

# ARP scanner (EPEL on RHEL/Rocky 9; not yet available in EL10 EPEL as of this writing)
sudo dnf install -y arp-scan

# Network map / port scanner
sudo dnf install -y nmap
```

---

## Text Processing / CLI Utilities

```bash
# Syntax-highlighted cat replacement (EPEL)
sudo dnf install -y bat

# sponge command (write to a file after reading it in a pipe) (EPEL)
sudo dnf install -y moreutils

# ripgrep — fast grep replacement (EPEL)
sudo dnf install -y ripgrep

# smem — memory usage per process (EPEL on RHEL/Rocky 9; not yet available in EL10 EPEL as of this writing)
sudo dnf install -y smem

# icdiff — side-by-side diff (Python)
pip3 install icdiff --user

# yq — YAML processor (binary install; no dnf package)
sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
sudo chmod +x /usr/local/bin/yq
```

---

## Git Utilities

```bash
# git-filter-repo — rewrite/filter git history
pip3 install git-filter-repo --user
```

---

## Kubernetes

### kubectl

```bash
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

### kubectl tab completion

```bash
sudo dnf install -y bash-completion
echo 'source <(kubectl completion bash)' >> ~/.bashrc
source ~/.bashrc
```

### Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

### Ingress Controllers

#### F5 NGINX Ingress Controller (via Helm)

```bash
helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update
helm upgrade --install nginx-ingress nginx-stable/nginx-ingress \
  --namespace nginx-ingress \
  --create-namespace \
  --set controller.kind=deployment \
  --set controller.replicaCount=1
```

#### F5 NGINX Ingress Controller (via manifest / git clone)

```bash
git clone https://github.com/nginx/kubernetes-ingress.git --branch v5.4.3
cd kubernetes-ingress

kubectl apply -f deployments/common/ns-and-sa.yaml
kubectl apply -f deployments/rbac/rbac.yaml
kubectl apply -f deployments/common/nginx-config.yaml
kubectl apply -f deployments/common/ingress-class.yaml
kubectl apply -f https://raw.githubusercontent.com/nginx/kubernetes-ingress/v5.4.3/deploy/crds.yaml
kubectl apply -f deployments/daemon-set/nginx-ingress.yaml
kubectl create -f deployments/service/nodeport.yaml
```

#### Traefik (via Helm)

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Initial install
helm install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --values k8s/ingress/traefik/traefik-values.yaml

# Upgrade / switch to DaemonSet
helm upgrade traefik traefik/traefik \
  --namespace traefik \
  --values k8s/ingress/traefik/traefik-values.yaml \
  --set deployment.kind=DaemonSet
```

### cert-manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

# Verify pods are running
kubectl get pods -n cert-manager
```

### Kubespray (Kubernetes cluster bootstrap)

```bash
# Install Podman first
sudo dnf install -y podman git

# Clone Kubespray
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray

# Run via Podman container
podman run --rm -it \
  -v ~/.ssh:/root/.ssh:ro \
  -v ./inventory:/inventory \
  quay.io/kubespray/kubespray:v2.31.0 bash

# Inside container — deploy cluster
ansible-playbook -i /inventory/hosts.yaml cluster.yml \
  -b -v \
  --private-key=~/.ssh/id_rsa \
  -e kube_version=1.35.0
```

---

## Docker + Docker Compose

```bash
# Add Docker CE repo
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo

# Install Docker CE
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl enable --now docker

# Add current user to docker group (re-login required)
sudo usermod -aG docker $USER
```

### Nexus insecure registry (required for local Docker registry on HTTP)

```bash
# /etc/docker/daemon.json
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "insecure-registries": ["<VM_IP>:8082"],
  "dns": ["<VM_IP>", "8.8.8.8"]
}
EOF

sudo systemctl restart docker
```

---

## CI/CD Stack (Docker Compose)

Jenkins + Gitea + Nexus + Traefik + Postgres + Pi-hole — deployed via Docker Compose profiles, no individual package installs needed.

```bash
cd docker-cicd

# Create host data directories
chmod +x data-dirs.sh && sudo ./data-dirs.sh

# Copy Postgres init scripts
sudo cp pg-init-scripts/*.sql /opt/devops/postgres/initdb/

# Configure environment
cp .env.example .env
# Edit .env — set passwords

# Start the full stack
docker compose --profile ci --profile scm --profile db --profile tracing up -d

# Start Pi-hole (separate compose)
cd pihole && docker compose up -d
```
