# Traefik Setup Guide on Bare Metal Kubernetes

## Environment

|Component|Detail|
|---|---|
|Kubernetes version|v1.27.0|
|Traefik version|v3.7.1 (chart 40.2.0)|
|Cluster type|Bare metal, no load balancer|
|Control planes|3 nodes (100.99.229.66-68)|
|Workers|9 nodes (100.99.229.69-77)|
|Ingress entry point|100.99.229.69 (worker1)|

---

## Architecture

```
Client (/etc/hosts or DNS)
        ↓
100.99.229.69:30443 (any worker node)
        ↓
Traefik (NodePort, IngressRoute)
        ├-- Host: traefik.local → Traefik Dashboard
        └-- Host: nginx.local  → nginx service :80
```

---

## Step 1 - Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version
```

---

## Step 2 - Add Traefik Helm Repo

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
```

---

## Step 3 - Create Namespace

```bash
kubectl create namespace traefik
```

---

## Step 4 - Create values.yaml

```bash
cat > traefik-values.yaml << 'EOF'
service:
  type: NodePort

ports:
  web:
    nodePort: 30080
  websecure:
    nodePort: 30443

ingressRoute:
  dashboard:
    enabled: true
    matchRule: Host(`traefik.local`)
    entryPoints:
      - websecure
    tls:
      secretName: ""

additionalArguments:
  - "--serversTransport.insecureSkipVerify=true"

logs:
  general:
    level: INFO
EOF
```

---

## Step 5 - Install Traefik

```bash
helm install traefik traefik/traefik \
  --namespace traefik \
  --values traefik-values.yaml
```

Verify:

```bash
kubectl get all -n traefik
kubectl get ingressroute -n traefik
```

---

## Step 6 - Fix Service Type to NodePort

If service shows as `LoadBalancer` after install:

```bash
kubectl patch svc traefik -n traefik \
  -p '{"spec":{"type":"NodePort"}}'

kubectl get svc -n traefik
```

Expected output:

```
NAME      TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)                      AGE
traefik   NodePort   10.233.36.43   <none>        80:30080/TCP,443:30443/TCP   Xm
```

---

## Step 7 - Create Self-Signed TLS Secret

```bash
# Generate certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout traefik.key \
  -out traefik.crt \
  -subj "/CN=traefik.local/O=traefik.local" \
  -addext "subjectAltName=DNS:traefik.local,DNS:nginx.local"

# Create secret in traefik namespace
kubectl create secret tls traefik-tls \
  --cert=traefik.crt \
  --key=traefik.key \
  -n traefik

# Copy secret to default namespace (for app IngressRoutes)
kubectl get secret traefik-tls -n traefik -o yaml | \
  sed 's/namespace: traefik/namespace: default/' | \
  kubectl apply -f -
```

---

## Step 8 - Patch Dashboard IngressRoute with TLS Secret

```bash
kubectl patch ingressroute traefik-dashboard -n traefik \
  --type merge \
  -p '{"spec":{"tls":{"secretName":"traefik-tls"}}}'
```

Verify:

```bash
kubectl describe ingressroute traefik-dashboard -n traefik | grep -A2 Tls
```

Test:

```bash
curl -k -H "Host: traefik.local" https://100.99.229.69:30443/dashboard/
```

---

## Step 9 - Expose a Service via IngressRoute

### Example: nginx

Ensure service is ClusterIP on correct port:

```bash
kubectl patch svc nginx -p '{"spec":{"type":"ClusterIP"}}'
kubectl patch svc nginx -p '{"spec":{"ports":[{"name":"http","port":80,"targetPort":80}]}}'
```

Create IngressRoute:

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: nginx-ingress
  namespace: default
spec:
  entryPoints:
    - websecure
  routes:
    - kind: Rule
      match: Host(`nginx.local`)
      services:
        - name: nginx
          port: 80
  tls:
    secretName: traefik-tls
EOF
```

Test:

```bash
curl -k -H "Host: nginx.local" https://100.99.229.69:30443
```

---

## Step 10 - Configure /etc/hosts

### Linux / macOS

```bash
sudo nano /etc/hosts
```

### Windows (run Notepad as Administrator)

```
C:\Windows\System32\drivers\etc\hosts
```

Add:

```
100.99.229.69   traefik.local nginx.local
100.99.229.66   k8s.local
```

Flush DNS (Windows):

```cmd
ipconfig /flushdns
```

Access in browser:

```
https://traefik.local:30443/dashboard/
https://nginx.local:30443
```

> Accept the self-signed certificate warning in your browser.

---

## Important Notes

### Traefik Pod Scheduling

Traefik runs as a single pod by default and can be rescheduled to any worker node. If the node changes, your `/etc/hosts` entry may break.

**Interim fix** - run as DaemonSet (one pod per worker):

```bash
helm upgrade traefik traefik/traefik \
  --namespace traefik \
  --values traefik-values.yaml \
  --set deployment.kind=DaemonSet
```

**Long term fix** - set up a VIP with keepalived + haproxy on control plane nodes, point all traffic to the VIP.

### Adding New Services

For every new service, simply:

1. Ensure service is `ClusterIP`
2. Create an `IngressRoute` pointing to it
3. Add hostname to `/etc/hosts`

---

## Appendix - Helm Reference Commands

### Repo Management

```bash
# Add a repo
helm repo add traefik https://traefik.github.io/charts

# Update all repos
helm repo update

# List repos
helm repo list
```

### Inspect Charts

```bash
# Show all available values and defaults for a chart
helm show values traefik/traefik

# Show chart info
helm show chart traefik/traefik
```

### Install & Upgrade

```bash
# Install
helm install traefik traefik/traefik \
  --namespace traefik \
  --values traefik-values.yaml

# Upgrade existing release
helm upgrade traefik traefik/traefik \
  --namespace traefik \
  --values traefik-values.yaml

# Upgrade with additional set flags
helm upgrade traefik traefik/traefik \
  --namespace traefik \
  --values traefik-values.yaml \
  --set deployment.kind=DaemonSet
```

### Inspect Deployed Releases

```bash
# List all releases in a namespace
helm list -n traefik

# List all releases across all namespaces
helm list -A

# Show current values of a deployed release
helm get values traefik -n traefik

# Show full rendered manifests of deployed release
helm get manifest traefik -n traefik
```

### Preview / Dry Run

```bash
# Preview rendered manifests without deploying
helm template traefik traefik/traefik \
  --namespace traefik \
  --values traefik-values.yaml

# Dry run upgrade (validate without applying)
helm upgrade traefik traefik/traefik \
  --namespace traefik \
  --values traefik-values.yaml \
  --dry-run
```

### Rollback & Uninstall

```bash
# Show release history
helm history traefik -n traefik

# Rollback to previous revision
helm rollback traefik -n traefik

# Rollback to specific revision
helm rollback traefik 1 -n traefik

# Uninstall a release
helm uninstall traefik -n traefik
```
