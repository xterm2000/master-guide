# Kubernetes Ingress Routing Strategy Guide

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [Host-Based Routing](#host-based-routing)
3. [Path-Based Routing](#path-based-routing)
4. [Path Rewriting](#path-rewriting)
5. [Choosing a Strategy](#choosing-a-strategy)
6. [Key Considerations](#key-considerations)
7. [DNS Records](#dns-records)
8. [Real-World Example: Multi-Environment Setup](#real-world-example-multi-environment-setup)

---

## Core Concepts

When traffic enters a Kubernetes cluster from the outside, it hits an **Ingress Controller** (NGINX, Traefik, etc.) which acts as a reverse proxy. That controller reads routing rules - either via standard `Ingress` objects or CRDs like NGINX's `VirtualServer` - and decides where to send the request.

There are two fundamental dimensions to that decision:

| Dimension | Mechanism | Example |
|---|---|---|
| **Which host?** | `Host:` HTTP header | `api.example.com` vs `admin.example.com` |
| **Which path?** | URL path prefix | `/api/` vs `/admin/` |

These can be combined, but understanding when to use each is the key design decision.

---

## Host-Based Routing

Each service (or environment) gets its own **fully qualified domain name**. The ingress controller reads the `Host` header from the incoming request and routes accordingly.

```
api.example.com      → Service A
admin.example.com    → Service B
metrics.example.com  → Service C
```

### NGINX VirtualServer example

```yaml
apiVersion: k8s.nginx.org/v1
kind: VirtualServer
metadata:
  name: api
  namespace: production
spec:
  host: api.example.com
  upstreams:
  - name: api-backend
    service: api-svc
    port: 8080
  routes:
  - path: /
    action:
      pass: api-backend
```

### Standard Ingress example

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api
  namespace: production
spec:
  ingressClassName: nginx
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-svc
            port:
              number: 8080
```

### When to use host-based routing

- Each service is a **distinct product or domain** (e.g. `api.`, `dashboard.`, `docs.`)
- Services belong to **different teams** with independent release cycles
- Services live in **different namespaces** (each namespace owns its VS)
- You need **per-host TLS certificates** (each host can have its own cert)
- Services have **incompatible path structures** (both use `/api/v1/`)
- You want clean, **user-facing URLs** without path prefixes

---

## Path-Based Routing

A single hostname serves multiple backends, differentiated by URL path prefix.

```
api.example.com/orders/    → Orders Service
api.example.com/payments/  → Payments Service
api.example.com/users/     → Users Service
```

### NGINX VirtualServer example

```yaml
apiVersion: k8s.nginx.org/v1
kind: VirtualServer
metadata:
  name: api-gateway
  namespace: production
spec:
  host: api.example.com
  upstreams:
  - name: orders
    service: orders-svc
    port: 8080
  - name: payments
    service: payments-svc
    port: 8080
  - name: users
    service: users-svc
    port: 8080
  routes:
  - path: /orders/
    action:
      proxy:
        upstream: orders
        rewritePath: /
  - path: /payments/
    action:
      proxy:
        upstream: payments
        rewritePath: /
  - path: /users/
    action:
      proxy:
        upstream: users
        rewritePath: /
```

### When to use path-based routing

- All services form **one logical API** consumed by one client
- You have a **limited number of hostnames** or wildcard DNS is unavailable
- Services are **internal/ops tools** that don't need clean URLs (Jaeger, Prometheus, etc.)
- You are **conserving TLS certificates** (one cert covers all paths)
- **Small cluster** where a single ingress point is sufficient
- Services are all in the **same namespace** (avoids ExternalName complexity)

---

## Path Rewriting

Path rewriting means the ingress controller modifies the URL path before forwarding the request to the upstream service. The client sends `/api/orders/123`; the backend receives `/orders/123`, or `/` - it never sees the routing prefix.

### Why rewriting is needed

When you route by path prefix, the prefix is a routing artifact - a label the ingress uses to pick the right service. The backend typically knows nothing about it. Without rewriting, the service receives the full original path and must handle the prefix itself, which usually breaks things.

| Client sends | Upstream sees (no rewrite) | Upstream sees (with rewrite) |
|---|---|---|
| `GET /api/orders/123` | `/api/orders/123` | `/orders/123` |
| `GET /jaeger/search` | `/jaeger/search` | `/search` |
| `GET /payments/v1/charge` | `/payments/v1/charge` | `/v1/charge` |

### Typical use cases

**1. Stripping the routing prefix from a service that has no base-path config**

The most common case. A service listens at `/` and has no way to tell it "you're mounted at `/orders/`." Rewriting strips the prefix so the service receives a path it understands.

```yaml
# Client:  GET /orders/123
# Backend: GET /123
routes:
- path: /orders/
  action:
    proxy:
      upstream: orders-svc
      rewritePath: /
```

Use this when: the service is a third-party binary, a legacy app, or any app that doesn't support a configurable base path.

**2. Ops and observability tools (Jaeger, Grafana, Prometheus, ArgoCD)**

These tools are often served under a prefix on a shared host (e.g. `dev.example.com/jaeger/`) so they don't each need their own subdomain. Most of them support a base-path flag *and* expect the rewrite to preserve their own sub-paths.

```yaml
# Client:  GET /jaeger/search?service=api
# Backend: GET /jaeger/search?service=api   ← prefix preserved because Jaeger owns /jaeger/
routes:
- path: /jaeger/
  action:
    proxy:
      upstream: jaeger-svc
      rewritePath: /jaeger/   # no strip - Jaeger was started with --query.base-path=/jaeger
```

Contrast with a service that strips its own prefix internally:

```yaml
# Client:  GET /grafana/dashboard
# Backend: GET /dashboard   ← Grafana was started with GF_SERVER_ROOT_URL=.../grafana
routes:
- path: /grafana/
  action:
    proxy:
      upstream: grafana-svc
      rewritePath: /
```

The rule: check whether the app's base-path flag already rewrites internally. If yes, strip at the ingress. If no, preserve the prefix.

**3. API versioning and migration**

During a `/v1/` → `/v2/` migration you may want to keep the old external URL working while routing to a new internal path.

```yaml
# Legacy clients still send /v1/users - route to the v2 service transparently
- path: /v1/
  action:
    proxy:
      upstream: users-v2-svc
      rewritePath: /v2/
```

This lets you decommission v1 pods without breaking old clients. Remove the rewrite rule once clients have migrated.

**4. Aggregating multiple upstream path schemes under one clean prefix**

Different services may use different internal path structures. Rewriting normalizes them to a consistent public API surface:

```yaml
# Internal: /svc-a/internal/resource
# Exposed:  /resources/
- path: /resources/
  action:
    proxy:
      upstream: svc-a
      rewritePath: /internal/resource/
```

Use this when you control the external API contract but not the internal service paths (e.g. integrating third-party services with their own URL schemes).

**5. Health check and readiness probe path normalization**

Some platforms expect a health check at `/health` but a service exposes it at `/api/health` or `/actuator/health`. A targeted rewrite handles this without changing the service:

```yaml
- path: /health
  action:
    proxy:
      upstream: app-svc
      rewritePath: /actuator/health
```

### When you do NOT need to rewrite

- The service already accepts requests at the full public path (e.g. it was built to handle `/api/orders/`)
- You're using host-based routing with `path: /` - the entire hostname maps to the service, no prefix to strip
- The app supports a `--base-path` or equivalent flag and handles the prefix internally; in that case preserve the prefix instead of stripping it

### NGINX VirtualServer - `rewritePath`

`rewritePath` replaces the matched path prefix with the given value and appends the remainder:

```yaml
routes:
- path: /payments/
  action:
    proxy:
      upstream: payments-svc
      rewritePath: /        # strip prefix: /payments/refund → /refund
```

```yaml
routes:
- path: /jaeger/
  action:
    proxy:
      upstream: jaeger-svc
      rewritePath: /jaeger/ # preserve prefix: /jaeger/search → /jaeger/search
```

The `path` field matches on prefix by default. A trailing slash in both `path` and `rewritePath` is significant - omitting it can cause the remainder to be appended without a separator.

### Standard Ingress - rewrite annotation

With the NGINX Ingress Controller (`kubernetes/ingress-nginx`), use capture groups:

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/use-regex: "true"
spec:
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /orders(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: orders-svc
            port:
              number: 8080
```

`$2` captures everything after the prefix, effectively stripping `/orders/`. The `(/|$)` guard ensures `/orders` and `/orders/` both match correctly.

### Common pitfalls

**Asset links break.** If the app renders `<script src="/static/app.js">` (absolute path), browsers request `/static/app.js`, which the ingress does not route under `/orders/`. Fix: configure `<base href="/orders/">` or use the app's base-path flag.

**Redirects point to the wrong path.** A service that issues a `302 Location: /login` redirect won't include the ingress prefix. The client follows it and gets a 404. Either configure the app's external URL, or use NGINX's `proxy_redirect` to rewrite redirect headers.

**Trailing slash inconsistency.** `path: /api` (no trailing slash) matches `/api`, `/api/`, and `/api/anything`. `path: /api/` is more precise. Decide on a convention and be consistent - mismatches cause double-slashes or missed matches.

**Cookie `Path` scope.** A service that sets `Set-Cookie: session=x; Path=/` scopes the cookie to `/`. When the client is under `/orders/`, the cookie may not be sent on subsequent requests. The fix is to set the cookie's `Path` to the public prefix, which usually means configuring it in the application.

---

## Choosing a Strategy

```
Is this a user-facing product with its own identity?
  YES → Host-based

Do services share a common API contract / single consumer?
  YES → Path-based

Are services in different namespaces?
  YES → Host-based preferred (avoids ExternalName workarounds with OSS NGINX)

Is the path structure unique per service (no collisions)?
  YES → Path-based is safe

Do you need independent TLS certs per service?
  YES → Host-based

Is it an internal ops/observability tool?
  YES → Path-based under an existing host (e.g. /jaeger/, /grafana/)
```

### Quick reference

| Factor | Host-based | Path-based |
|---|---|---|
| URL cleanliness | ✅ Clean | ⚠️ Has prefix |
| TLS flexibility | ✅ Per-host cert | ⚠️ Shared cert |
| DNS records needed | One per host | One total |
| Cross-namespace | ✅ Native | ⚠️ Needs workaround |
| Path collision risk | ✅ None | ⚠️ Must coordinate |
| Base path config in app | ✅ Not needed | ⚠️ Often required |
| Wildcard DNS friendly | ✅ Yes | ✅ Yes |
| NGINX OSS compatible | ✅ Full support | ✅ Full support |

---

## Key Considerations

### 1. Cross-namespace routing

This is the most common pain point. A VirtualServer in `default` cannot natively upstream to a service in `monitor`.

| Approach | Works with OSS NGINX? | Notes |
|---|---|---|
| ExternalName Service | ❌ No | NGINX Plus only |
| Manual Endpoints object | ✅ Yes | Hardcodes ClusterIP, fragile on restart |
| Move VS to same namespace | ✅ Yes | Cleanest solution |
| Host-based VS per namespace | ✅ Yes | Each namespace owns its VS and host |

**Best practice:** keep VirtualServer and its upstream services in the **same namespace**. Use host-based routing to give each namespace its own hostname.

### 2. App base path configuration

When a service is served under a path prefix, the application itself must know about it. Many apps hardcode asset links to `/`:

```html
<base href="/" />         <!-- breaks under /jaeger/ -->
<base href="/jaeger/" />  <!-- correct when --query.base-path=/jaeger is set -->
```

Always check whether your app supports a configurable base path before choosing path-based routing. Examples:

| App | Base path flag |
|---|---|
| Jaeger UI | `--query.base-path=/jaeger` |
| Grafana | `GF_SERVER_ROOT_URL=%(protocol)s://%(domain)s/grafana` |
| Prometheus | `--web.external-url=http://host/prometheus` |
| ArgoCD | `--rootpath=/argocd` |

### 3. TLS certificates

Each unique hostname needs a TLS certificate. Options:

```
Wildcard cert  *.example.com    → covers all subdomains, one cert
Per-host cert  api.example.com  → more granular, more certs to manage
cert-manager   automatic        → recommended, handles renewal
```

With **cert-manager + Let's Encrypt**, adding a new host is just an annotation:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts:
    - api.example.com
    secretName: api-tls
```

### 4. Ingress controller scope

By default, all Ingress/VirtualServer objects in all namespaces are processed by the controller. In multi-tenant clusters, scope it:

```yaml
# Restrict controller to specific namespaces
args:
- -watch-namespace=production,staging
```

Or use `IngressClass` to have multiple controllers:

```yaml
spec:
  ingressClassName: nginx-internal   # internal controller
  ingressClassName: nginx-external   # external-facing controller
```

### 5. Health checks and timeouts

Path-based proxying often needs tuned timeouts per upstream:

```yaml
upstreams:
- name: slow-service
  service: slow-svc
  port: 8080
  connect-timeout: 5s
  read-timeout: 60s      # longer for slow backends
  send-timeout: 60s
```

---

## DNS Records

Yes - DNS records must always be created manually (or via automation). The ingress controller does **not** create DNS records automatically unless you use **external-dns**.

### What record to create

Always create an **A record** pointing to your ingress controller's external IP:

```
api.example.com.      300  IN  A  203.0.113.10
admin.example.com.    300  IN  A  203.0.113.10
```

Both point to the **same IP** - the ingress controller. It differentiates between them using the `Host:` header, not the IP.

### Finding your ingress IP

```bash
kubectl get svc -n nginx-ingress
# Look for EXTERNAL-IP on the LoadBalancer service
```

### Wildcard DNS (recommended for multi-environment)

Instead of creating one record per subdomain, use a single wildcard:

```
*.example.com.    300  IN  A  203.0.113.10
```

This covers `api.example.com`, `dev.example.com`, `anything.example.com` - all resolved to the same ingress IP. The ingress controller then routes by host header.

### Route 53 example (AWS CLI)

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890 \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "api.example.com",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "203.0.113.10"}]
      }
    }]
  }'
```

### Automating DNS with external-dns

`external-dns` watches Ingress/VirtualServer objects and creates DNS records automatically in Route 53, Cloudflare, etc.:

```yaml
# external-dns automatically creates:
# dev.example.com → ingress IP
# when it sees a VirtualServer with host: dev.example.com
```

This is the gold standard for large clusters - no manual DNS management.

---

## Real-World Example: Multi-Environment Setup

### The scenario

Four environments, each with its own DNS record:

```
prod.test-api.com
dev.test-api.com
uat.test-api.com
qa.test-api.com
```

Each environment's pods live in their own namespace:

```
namespace: prod
namespace: dev
namespace: uat
namespace: qa
```

Not every service is reachable by path - some services are environment-wide, some are per-feature.

---

### DNS strategy

In Route 53, create **one wildcard record**:

```
*.test-api.com    300  IN  A  <ingress-external-ip>
```

This covers all four environments (and any future ones) with a single record. The ingress controller handles the rest via host headers.

---

### Namespace and VirtualServer layout

Each namespace owns its **own VirtualServer** with its own host. This avoids all cross-namespace routing problems.

```
namespace: prod  →  VirtualServer host: prod.test-api.com
namespace: dev   →  VirtualServer host: dev.test-api.com
namespace: uat   →  VirtualServer host: uat.test-api.com
namespace: qa    →  VirtualServer host: qa.test-api.com
```

#### Example: `dev` namespace VirtualServer

```yaml
apiVersion: k8s.nginx.org/v1
kind: VirtualServer
metadata:
  name: dev-vs
  namespace: dev
spec:
  host: dev.test-api.com
  tls:
    secret: dev-tls
    redirect:
      enable: true
  upstreams:
  - name: api
    service: api-svc
    port: 8080
  - name: auth
    service: auth-svc
    port: 8080
  - name: jaeger
    service: jaeger-svc      # lives in same namespace: dev
    port: 16686
  routes:
  - path: /api/
    action:
      proxy:
        upstream: api
        rewritePath: /
  - path: /auth/
    action:
      proxy:
        upstream: auth
        rewritePath: /
  - path: /jaeger/
    action:
      proxy:
        upstream: jaeger
        rewritePath: /jaeger/
  - path: /
    action:
      return:
        code: 404
        body: '{"error":"not found"}'
        type: application/json
```

Repeat the same pattern for `prod`, `uat`, `qa` - changing the `host:`, `namespace:`, and `tls.secret:` fields.

---

### TLS per environment

Each environment gets its own TLS secret, managed by cert-manager:

```yaml
# One per namespace, e.g. in namespace: dev
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: dev-tls
  namespace: dev
spec:
  secretName: dev-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - dev.test-api.com
```

---

### When a service is NOT reachable by path

Some services shouldn't be path-accessible from the shared host - for example, an internal metrics service, a database admin UI, or a service with an incompatible base path.

**Option 1: Give it its own subdomain**

```
metrics.dev.test-api.com   → metrics service (dev namespace)
```

Add a DNS record (or rely on wildcard `*.test-api.com` if you set that up), then create a separate VirtualServer in the `dev` namespace for that host.

**Option 2: Don't expose it via ingress at all**

Use `kubectl port-forward` for one-off access:

```bash
kubectl port-forward -n dev svc/metrics-svc 9090:9090
```

**Option 3: Restrict path access with allow-listing**

Expose it under a path but lock it down:

```yaml
routes:
- path: /internal-metrics/
  policies:
  - name: allow-internal-ips    # NGINX Policy CRD
  action:
    proxy:
      upstream: metrics
      rewritePath: /
```

---

### Full architecture diagram

```
Internet
    │
    ▼
Route 53: *.test-api.com → 203.0.113.10
    │
    ▼
Ingress Controller (nginx-ingress namespace)
    │
    ├-- Host: prod.test-api.com  →  VirtualServer (namespace: prod)
    │       ├-- /api/            →  api-svc:8080
    │       ├-- /auth/           →  auth-svc:8080
    │       └-- /jaeger/         →  jaeger-svc:16686
    │
    ├-- Host: dev.test-api.com   →  VirtualServer (namespace: dev)
    │       ├-- /api/            →  api-svc:8080
    │       ├-- /auth/           →  auth-svc:8080
    │       └-- /jaeger/         →  jaeger-svc:16686
    │
    ├-- Host: uat.test-api.com   →  VirtualServer (namespace: uat)
    │       └-- /api/            →  api-svc:8080
    │
    └-- Host: qa.test-api.com    →  VirtualServer (namespace: qa)
            └-- /api/            →  api-svc:8080
```

---

### Summary of decisions made

| Decision | Choice | Reason |
|---|---|---|
| Host vs path for environments | **Host-based** | Each env is isolated, different namespace, different team |
| Host vs path for services within env | **Path-based** | Same team, same namespace, single API surface |
| DNS | **Wildcard `*.test-api.com`** | Covers all envs with one record, scales to new envs for free |
| TLS | **cert-manager per namespace** | Each env has independent cert lifecycle |
| Cross-namespace routing | **Avoided** | Each VS lives in its env namespace |
| Non-path-accessible services | **Own subdomain or port-forward** | No ExternalName hacks needed |