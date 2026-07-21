## kubectl `--dry-run` Quick Guide

### What is `--dry-run`?

`--dry-run` lets you **simulate** a kubectl command without actually applying changes to the cluster. Useful for validation, generating manifests, and CI/CD checks.

---

### Two Modes

|Mode|Flag|Where validation runs|
|---|---|---|
|Client-side|`--dry-run=client`|Locally, no API call|
|Server-side|`--dry-run=server`|On the API server, full admission checks|

---

### `--dry-run=client`

Validates syntax locally. **No contact with the cluster.**

```bash
# Preview a deployment manifest
kubectl create deployment nginx --image=nginx --dry-run=client -o yaml

# Validate a local file without applying
kubectl apply -f pod.yaml --dry-run=client

# Generate a ConfigMap manifest
kubectl create configmap my-config --from-literal=key=val --dry-run=client -o yaml
```

**Use when:** generating boilerplate YAML, quick syntax checks, offline work.

---

### `--dry-run=server`

Sends the request to the API server but doesn't persist it. Runs **admission controllers, webhooks, and validation**.

```bash
# Full server-side validation
kubectl apply -f deployment.yaml --dry-run=server

# Check if a namespace name is taken
kubectl create namespace prod --dry-run=server

# Validate against admission webhooks
kubectl apply -f pod-security.yaml --dry-run=server
```

**Use when:** you need to catch webhook/policy rejections, quota issues, or RBAC errors before real apply.

---

### Combined with `-o yaml` - The Power Pattern

Generate clean manifests from imperative commands:

```bash
# Deployment
kubectl create deployment api --image=myapp:v1 --replicas=3 \
  --dry-run=client -o yaml > deployment.yaml

# Service
kubectl expose deployment api --port=80 --target-port=8080 \
  --dry-run=client -o yaml > service.yaml

# Job
kubectl create job db-migrate --image=migrate:latest \
  --dry-run=client -o yaml

# Secret
kubectl create secret generic db-creds \
  --from-literal=password=s3cr3t \
  --dry-run=client -o yaml
```

---

### Client vs Server - When It Matters

```bash
# This passes client-side (syntax OK)...
kubectl apply -f pod.yaml --dry-run=client  ✅

# ...but fails server-side (e.g. PodSecurity policy blocks it)
kubectl apply -f pod.yaml --dry-run=server  ❌ Error from admission webhook
```

Server-side also catches:

- Resource quota exceeded
- Invalid image pull policy for the cluster
- Namespace doesn't exist
- Custom CRD validation rules

---

### Aliases

Yes - absolutely. Here are practical aliases to add to your `~/.bashrc` or `~/.zshrc`:

```bash
# Dry-run helpers
alias kdrc='kubectl --dry-run=client -o yaml'
alias kdrs='kubectl --dry-run=server -o yaml'

# Common generators
alias kgdep='kubectl create deployment --dry-run=client -o yaml'
alias kgsvc='kubectl expose --dry-run=client -o yaml'
alias kgcm='kubectl create configmap --dry-run=client -o yaml'
alias kgsec='kubectl create secret generic --dry-run=client -o yaml'
alias kgjob='kubectl create job --dry-run=client -o yaml'
```

Usage after sourcing:

```bash
kgdep nginx --image=nginx:alpine --replicas=2
kgsec db-creds --from-literal=user=admin --from-literal=pass=s3cr3t
```

Or with a function for full flexibility:

```bash
# Pipe any imperative command to a file
kdry() {
  kubectl "$@" --dry-run=client -o yaml
}

# Usage:
kdry create deployment nginx --image=nginx > nginx-deploy.yaml
kdry create configmap app-config --from-file=./config/
```

Reload with `source ~/.bashrc` (or `~/.zshrc`).

---

### Quick Reference

```
--dry-run=client   → fast, offline, syntax only
--dry-run=server   → full validation, needs cluster access
-o yaml            → dump the resulting manifest
```