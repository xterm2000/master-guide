# Kubernetes Regex guide (Linux Shell)

A practical reference for using regex with `kubectl`, `grep`, `sed`, `awk`, and other shell tools in Kubernetes workflows.

---

## Pod & Resource Names

```bash
# Match a valid k8s resource name (lowercase alphanumeric + hyphens)
^[a-z0-9][a-z0-9\-]{0,61}[a-z0-9]$

# Match pod name with generated suffix (e.g. my-app-7d9f4b6c8-xkj2p)
^[a-z0-9\-]+-[a-z0-9]{8,10}-[a-z0-9]{5}$

# Extract pod name from kubectl output
grep -oP '^[a-z0-9][a-z0-9\-]+'

# Match pods belonging to a specific deployment
kubectl get pods | grep -P '^my-deployment-[a-z0-9]+-[a-z0-9]+'
```

---

## Namespaces

```bash
# Match a valid namespace name
^[a-z0-9][a-z0-9\-]{0,61}[a-z0-9]$

# List pods in namespaces matching a pattern (e.g. team-*)
kubectl get pods --all-namespaces | grep -P '\bteam-\w+'

# Extract namespace from kubectl output column
kubectl get pods -A | awk '{print $1}' | grep -P '^prod-'
```

---

## Container Images

```bash
# Match a Docker image reference (image:tag)
^[\w.\-/]+(:[\w.\-]+)?$

# Extract image name and tag separately
grep -oP '[\w.\-/]+(?=:)'   # image name
grep -oP '(?<=:)[\w.\-]+'   # tag

# Find pods using a specific image version
kubectl get pods -o yaml | grep -P 'image:\s+nginx:1\.\d+\.\d+'

# Match a digest-based image reference (sha256)
grep -P 'image:.*@sha256:[a-f0-9]{64}'

# Find images NOT using 'latest' tag
kubectl get pods -o yaml | grep 'image:' | grep -vP ':latest\s*$'
```

---

## IP Addresses

```bash
# Match an IPv4 address
\b(\d{1,3}\.){3}\d{1,3}\b

# Match a pod/node IP in kubectl output
kubectl get pods -o wide | grep -oP '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'

# Match a CIDR block (e.g. 10.0.0.0/16)
\b\d{1,3}(\.\d{1,3}){3}/\d{1,2}\b

# Match IPv6 address (simplified)
([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}
```

---

## Ports

```bash
# Match a valid port number (1–65535)
\b([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])\b

# Match port mapping (hostPort:containerPort)
grep -oP '\d{2,5}:\d{2,5}'

# Find services exposing port 443
kubectl get svc -A | grep -P '\b443\b'

# Match containerPort definitions in YAML
grep -P 'containerPort:\s+\d+'
```

---

## Kubernetes Labels & Selectors

```bash
# Match a valid label key (prefix/name)
^([a-z0-9\-\.]+/)?[a-zA-Z0-9][a-zA-Z0-9\-_.]{0,62}$

# Match label key=value pair
grep -oP '[a-zA-Z0-9\-_./]+=[\w\-.]+'

# Find resources with a specific label value
kubectl get pods --show-labels | grep -P 'env=prod'

# Match annotation keys
grep -P '^\s+[a-zA-Z0-9\-_.]+/[a-zA-Z0-9\-_.]+:'
```

---

## Resource Limits & Requests

```bash
# Match CPU value (e.g. 500m, 1, 2.5)
\b\d+(\.\d+)?m?\b

# Match memory value (e.g. 128Mi, 2Gi, 512M)
\b\d+(\.\d+)?(Ki|Mi|Gi|Ti|K|M|G|T)?\b

# Find pods with memory limit defined
kubectl get pods -o yaml | grep -P 'memory:\s+\d+\w+'

# Find high CPU limits (>= 2 cores)
kubectl get pods -o yaml | grep -P 'cpu:\s+[2-9]\b'
```

---

## Logs

```bash
# Match a timestamp in k8s log format (RFC3339)
\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z

# Filter ERROR or WARN log lines
kubectl logs my-pod | grep -P '\b(ERROR|WARN|FATAL)\b'

# Extract log level from structured logs
grep -oP '(?<="level":")[^"]+'

# Match OOMKilled events in logs
kubectl get events -A | grep -P 'OOMKill'

# Match CrashLoopBackOff pods
kubectl get pods -A | grep -P 'CrashLoopBackOff'

# Match pod restart count > 0
kubectl get pods -A | grep -P '\s+[1-9]\d*\s+\d+[smhd]'
```

---

## Events

```bash
# Match Warning events only
kubectl get events -A | grep -P '^\S+\s+\S+\s+Warning'

# Match events for a specific reason
kubectl get events | grep -P 'Reason:\s+(OOMKilling|Backoff|Failed)'

# Extract event message field
kubectl get events -o yaml | grep -P 'message:\s+.+'
```

---

## YAML / Manifest Parsing

```bash
# Match any key: value line in YAML
grep -P '^\s+\w[\w\-]*:\s+\S+'

# Match a YAML key with a numeric value
grep -P '^\s+\w+:\s+\d+'

# Find all image lines in a manifest
grep -P '^\s+image:\s+\S+'

# Find environment variable definitions
grep -P '^\s+- name:\s+\w+'

# Match secret references
grep -P 'secretKeyRef|secretName'

# Find hardcoded passwords/tokens in manifests (security audit)
grep -iP '(password|secret|token|api[_-]?key)\s*:\s*\S+'
```

---

## Nodes

```bash
# Match node status (Ready / NotReady)
kubectl get nodes | grep -P '\b(Ready|NotReady)\b'

# Match node name with region/zone pattern (e.g. node-us-east-1a)
grep -P 'node-[a-z]+-[a-z]+-\d[a-z]'

# Find nodes with a taint
kubectl get nodes -o yaml | grep -P 'taints:' -A 5

# Match node capacity (CPU count)
kubectl get nodes -o yaml | grep -P 'cpu:\s+"\d+"'
```

---

## Contexts & Config

```bash
# Match a kubeconfig context name
grep -oP '(?<=name: )\S+' ~/.kube/config

# Switch context matching a pattern
kubectl config get-contexts | grep -P 'prod-'

# Match cluster server URL
grep -P 'server:\s+https://[\w.\-:/?=]+'
```

---

## Useful Shell One-liners

```bash
# Get all image names across all pods
kubectl get pods -A -o yaml | grep -oP '(?<=image: )\S+' | sort -u

# Find all pods NOT in Running state
kubectl get pods -A | grep -vP '\bRunning\b'

# Extract all env var names from a deployment
kubectl get deploy my-app -o yaml | grep -oP '(?<=- name: )\w+'

# Find pods older than a timestamp pattern
kubectl get pods -A | grep -P '^\S+\s+\S+\s+\S+\s+\S+\s+[2-9][0-9]+[mhd]'

# Watch logs for specific error pattern
kubectl logs -f my-pod | grep --line-buffered -P 'ERROR|Exception|panic'
```

---

## Quick Reference: Common Patterns

| What | Regex |
|---|---|
| Pod name | `^[a-z0-9][a-z0-9\-]+-[a-z0-9]{5}$` |
| Image with tag | `[\w./\-]+:[\w.\-]+` |
| IPv4 address | `\b(\d{1,3}\.){3}\d{1,3}\b` |
| CIDR block | `\b\d{1,3}(\.\d{1,3}){3}/\d{1,2}\b` |
| Port number | `\b\d{2,5}\b` |
| Memory value | `\d+(\.\d+)?(Ki\|Mi\|Gi)` |
| CPU value (millicores) | `\d+m` |
| RFC3339 timestamp | `\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z` |
| Log level | `\b(DEBUG\|INFO\|WARN\|ERROR\|FATAL)\b` |
| SHA256 digest | `sha256:[a-f0-9]{64}` |
| Label key=value | `[\w\-./]+=[\w\-.]+` |
| Env var name | `[A-Z][A-Z0-9_]+` |

---

> **Tip:** Use `grep -P` for Perl-compatible regex (supports `\b`, lookaheads, etc.) on Linux.  
> For `sed`, use `sed -E` for extended regex or `sed -r` on older systems.