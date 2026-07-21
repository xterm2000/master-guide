# Whisker Dashboard Debugging Summary

## Goal
Expose the Calico Whisker dashboard via NGINX Ingress (F5 NGINX free tier) on `whisker.mydomain.com`.

---

## Issue 1 — VirtualServerRoute Ignored (Name Mismatch)

**Symptom:** VSR status showed `Ignored`, `Referenced By` was empty.

**Cause:** The VirtualServer referenced `calico-system/whisker` but the VSR was named `calico-vsr`.

**Fix:**
```yaml
# Wrong
route: calico-system/whisker

# Correct
route: calico-system/calico-vsr
```

---

## Issue 2 — 504 Gateway Timeout

**Symptom:** After fixing the name, hitting `/whisker` returned 504.

**Investigation:**
- NGINX ingress logs showed requests not reaching the whisker pod
- `curl` from control node to whisker pod IP worked locally
- `curl` from worker node timed out → cross-node connectivity issue
- `calico-node -bird-live` returned not ready (BIRD not live — but this was a red herring; cluster uses iptables + VXLAN, not BGP)
- `tcpdump` confirmed VXLAN packets arriving at control node
- SYN packets reaching whisker pod interface but no SYN-ACK response

**Root cause:** Calico `default-deny` NetworkPolicy in `calico-system` tier was blocking all ingress to the whisker pod. The operator-managed `calico-system.whisker` policy had **no ingress rules**.

**Fix:** Create a new Calico NetworkPolicy allowing ingress from nginx-ingress namespace:
```yaml
apiVersion: projectcalico.org/v3
kind: NetworkPolicy
metadata:
  name: calico-system.allow-nginx-to-whisker
  namespace: calico-system
spec:
  tier: calico-system
  selector: k8s-app == 'whisker'
  types:
  - Ingress
  ingress:
  - action: Allow
    protocol: TCP
    source:
      namespaceSelector: kubernetes.io/metadata.name == 'nginx-ingress'
    destination:
      ports:
      - 8081
```

> Note: `projectcalico.org/name` label was absent from the nginx-ingress namespace; use `kubernetes.io/metadata.name` instead.

---

## Issue 3 — Subpath Hosting React App (`/whisker`)

**Symptom:** Dashboard loaded but assets (`/static/js/...`) returned 403.

**Cause:** Whisker's React app uses absolute paths (`/static`, `/whisker-backend`, `/config`). Serving it under `/whisker` subpath caused asset requests to hit the catch-all 403 route.

**Fix:** Abandon subpath approach. Use a dedicated subdomain instead.

---

## Final Architecture — Dedicated Subdomain

Since a wildcard DNS record `*.mydomain.com → NLB` already existed, no DNS changes were needed.

**Copy TLS secret to calico-system namespace:**
```bash
k get secret route53 -n default -o yaml | sed 's/namespace: default/namespace: calico-system/' | k apply -f -
```

**VirtualServer in calico-system namespace:**
```yaml
apiVersion: k8s.nginx.org/v1
kind: VirtualServer
metadata:
  name: whisker-vs
  namespace: calico-system
spec:
  host: whisker.mydomain.com
  tls:
    redirect:
      enable: true
    secret: route53
  upstreams:
  - name: whisker
    service: whisker
    port: 8081
  routes:
  - path: /
    action:
      pass: whisker
```

> Cross-namespace upstreams are not supported in NGINX F5 free tier. ExternalName services are also not supported. Deploying the VS in the same namespace as the service is the only option.

---

## Issue 4 — No Flow Logs (DNS Timeout)

**Symptom:** Dashboard loaded but showed no flow logs. whisker-backend logs showed:
```
dns: A record lookup error: lookup goldmane.calico-system.svc.cluster.local
on 169.254.25.10:53: dial udp 169.254.25.10:53: i/o timeout
```

**Cause:** Node-local DNS (`169.254.25.10`) uses `NOTRACK` in iptables, bypassing conntrack. This meant:
- DNS egress from whisker was allowed by policy
- But DNS **responses** from `169.254.25.10:53` didn't match `ctstate RELATED,ESTABLISHED`
- Responses were dropped by the ingress default-deny

**Fix:** Add explicit ingress + egress rules for node-local DNS in the policy:
```yaml
apiVersion: projectcalico.org/v3
kind: NetworkPolicy
metadata:
  name: calico-system.allow-whisker-nodelocaldns
  namespace: calico-system
spec:
  tier: calico-system
  selector: k8s-app == 'whisker'
  types:
  - Ingress
  - Egress
  ingress:
  - action: Allow
    protocol: UDP
    source:
      nets:
      - 169.254.25.10/32
      ports:
      - 53
  - action: Allow
    protocol: TCP
    source:
      nets:
      - 169.254.25.10/32
      ports:
      - 53
  egress:
  - action: Allow
    protocol: UDP
    destination:
      nets:
      - 169.254.25.10/32
      ports:
      - 53
  - action: Allow
    protocol: TCP
    destination:
      nets:
      - 169.254.25.10/32
      ports:
      - 53
```

---

## Final State

| Component | Status |
|---|---|
| `whisker.mydomain.com` | ✅ Accessible |
| Whisker dashboard | ✅ Rendering |
| Flow logs | ✅ Working |
| TLS | ✅ Wildcard cert via route53 secret |

## Key Lessons

- **Use a dedicated subdomain** for React apps — subpath hosting requires the app to be built with a base path, which Whisker is not.
- **Wildcard DNS + wildcard cert** = zero extra config for new subdomains.
- **Calico default-deny tiers** block everything including DNS responses when `NOTRACK` is in play — always add explicit ingress rules for node-local DNS responses.
- **Operator-managed policies** (tigera-operator) will be overwritten if edited — always create separate policies.
- **NGINX F5 free tier** does not support cross-namespace upstreams or ExternalName services.