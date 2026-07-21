

## fix for network issue DNS Search Line Limits Exceeded


This is a well-known Kubernetes/Linux limitation. Here's what's happening:

### Root Cause

Linux kernels impose a hard limit on `/etc/resolv.conf`:

- **Max 6 search domains**
- **Max 256 characters** in the search line

Your current search line has **6 domains** (right at the limit), and kubelet is generating a 7th by prepending the pod's namespace:

```
<namespace>.svc.cluster.local   ← kubelet adds this (pod-specific)
svc.cluster.local
cluster.local
tfayd.com
stg-tfayd.com
nbcuni.ge.com
              ↑ already 6 - so the namespace one gets DROPPED/omitted
```

The namespaces being affected from your logs:

- `p123`
- `opentelemetry-operator-system`
- `curl`

---

### Diagnosis Steps

**1. Check the node's base resolv.conf**

```bash
cat /etc/resolv.conf
# or the systemd-resolved stub
cat /run/systemd/resolve/resolv.conf
```

**2. Check how many search domains are defined there**

```bash
grep "^search" /etc/resolv.conf | tr ' ' '\n' | tail -n +2 | wc -l
```

**3. Inspect an affected pod's resolv.conf directly**

```bash
# find a pod in namespace p123
kubectl exec -n p123 <pod-name> -- cat /etc/resolv.conf
```

**4. Check if a DNSConfig is set cluster-wide or on affected pods**

```bash
kubectl get pod <pod-name> -n p123 -o jsonpath='{.spec.dnsConfig}'
```

---

### Fix Options

**Option A - Remove a search domain from the node (cleanest)**

Edit the node's `/etc/resolv.conf` (or its source, e.g. netplan/NetworkManager config) and drop one of the non-essential domains. You only have room for 3 after Kubernetes takes its 3 slots:

```
svc.cluster.local
cluster.local
<namespace>.svc.cluster.local   ← dynamic
```

So you can keep at most **3 custom domains**. Currently you have `tfayd.com`, `stg-tfayd.com`, `nbcuni.ge.com` - drop one if possible.

**Option B - Use `ndots` tuning to reduce search churn**

```yaml
# In pod spec or a mutating webhook
dnsConfig:
  options:
    - name: ndots
      value: "2"   # default is 5 - reduces unnecessary search lookups
```

**Option C - Use a NodeLocal DNSCache**

Reduces resolv.conf pressure by handling cluster DNS locally, and sidesteps some of the search domain cascading.

**Option D - Reduce Kubernetes internal search domains via kubelet config**

In `/var/lib/kubelet/config.yaml` or kubelet flags, you can set `clusterDomain` but you can't easily strip `svc.cluster.local` without breaking service discovery.


A few ways to investigate:

### 1. Check DNS queries from pods in real-time (best signal)

```bash
# Sniff DNS traffic on the node - port 53 to the cluster DNS
tcpdump -i any -nn port 53 2>/dev/null | grep -E "inbcu|awsc3"

# Or on the CoreDNS side
kubectl logs -n kube-system -l k8s-app=kube-dns --follow | grep -E "inbcu|awsc3"
```

### 2. Check app configs / env vars in pods for those domains

```bash
# Check env vars across all pods in a namespace
kubectl get pods -n p123 -o json | \
  jq -r '.items[].spec.containers[].env[]? | select(.value | test("inbcu|awsc3")) | .value'

# Check all namespaces
kubectl get pods -A -o json | \
  jq -r '.items[].spec.containers[].env[]? | select(.value | test("inbcu|awsc3")) | .value'
```

### 3. Check ConfigMaps and Secrets for references

```bash
kubectl get configmaps -A -o json | \
  jq -r '.. | strings | select(test("inbcu|awsc3"))' | sort -u

kubectl get secrets -A -o json | \
  jq -r '.. | strings | select(test("inbcu|awsc3"))' 2>/dev/null | sort -u
```

### 4. Check Ingress/Service definitions

```bash
kubectl get ingress -A -o json | \
  jq -r '.items[].spec.rules[]?.host | select(test("inbcu|awsc3"))' 
```

### 5. Ask NetworkManager why those domains are there

```bash
# See which connection is injecting them
nmcli con show --active | head
nmcli -f ipv4.dns-search con show <connection-name>

# Check if they come from DHCP
journalctl -u NetworkManager | grep -E "inbcu|awsc3"
```

---

**Start with `tcpdump` (#1)** - if you see zero DNS queries for those domains after watching for a few minutes across active pods, they're likely safe to remove. The jq checks (#2, #3) will tell you if they're hardcoded anywhere in your workload configs.

---

### Quick Check - What does your node's resolv.conf look like?

That'll confirm whether the 3 extra domains (`tfayd.com stg-tfayd.com nbcuni.ge.com`) are coming from the node config or injected elsewhere (e.g. a MutatingWebhookConfiguration or CoreDNS config).


```bash
# check kubelet dns errors - main symptom
journalctl -xeu kubelet --no-pager | grep -i "search line"

# check node resolv.conf - should show 3 domains after fix
cat /etc/resolv.conf

# check pod resolv.conf - should show 6 domains after fix
kubectl exec -n <namespace> <pod-name> -- cat /etc/resolv.conf

# check how many search domains are on the node
grep "^search" /etc/resolv.conf | tr ' ' '\n' | tail -n +2 | wc -l

# check nic config - source of truth for search domains
grep DOMAIN /etc/sysconfig/network-scripts/ifcfg-ens160

# check all nodes nic config
for node in "${NODES[@]}"; do
  echo "=== $node ==="
  ssh $node "grep DOMAIN /etc/sysconfig/network-scripts/ifcfg-ens160"
done

# check all nodes resolv.conf
for node in "${NODES[@]}"; do
  echo "=== $node ==="
  ssh $node "grep search /etc/resolv.conf"
done

# find ingresses using inbcu/awsc3 domains
kubectl get ingress -A -o json | \
  jq -r '.items[] | .metadata.namespace + "/" + .metadata.name + ": " + (.spec.rules[]?.host // "null")' | \
  grep -E "inbcu|awsc3"

# find pods with env vars referencing inbcu/awsc3
kubectl get pods -A -o json | \
  jq -r '.items[].spec.containers[].env[]? | select(.value | test("inbcu|awsc3")) | .value' | sort -u

# find configmaps referencing inbcu/awsc3
kubectl get configmaps -A -o json | \
  jq -r '.. | strings | select(test("inbcu|awsc3"))' | sort -u

# check if a domain resolves as fqdn (no search domain needed if yes)
dig oaapi.inbcu.com +short

# check dns resolution from inside a pod
kubectl exec -n <namespace> <pod-name> -- curl -s "https://oaapi.inbcu.com" -o /dev/null -w "%{http_code}"

# check per-pod dnsconfig overrides
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.dnsConfig}'

# watch kubelet dns errors live
journalctl -fu kubelet | grep -i dns
```

### identifying 
We came to it step by step:

**1. Identified the limit** - Linux hard cap is 6 search domains. Kubernetes always adds 3 (`<namespace>.svc.cluster.local`, `svc.cluster.local`, `cluster.local`), leaving only 3 slots for custom domains. Node had 5, so 2 were getting dropped.

**2. Found the source** - `/etc/sysconfig/network-scripts/ifcfg-ens160` had:

```
DOMAIN="tfayd.com stg-tfayd.com nbcuni.ge.com inbcu.com awsc3.com"
```

**3. Investigated each domain for actual usage:**

- `tfayd.com` - kept, it's the primary domain of the cluster itself
- `nbcuni.ge.com` - kept, referenced in workloads
- `stg-tfayd.com` - no ingresses, no configmaps, no pod env vars referencing it → **removed**
- `awsc3.com` - no ingresses, no configmaps, no pod env vars referencing it → **removed**
- `inbcu.com` - looked dangerous to remove because pods had `CMDLOADER_CALLBACK_URL=https://oaapi.inbcu.com/...` but then we confirmed `oaapi.inbcu.com` resolves as a **FQDN** directly without needing the search domain → **could be removed too**

Actually - we kept `inbcu.com` and removed `stg-tfayd.com` and `awsc3.com`. The final domain list was:

```
DOMAIN="tfayd.com nbcuni.ge.com inbcu.com"
```

The key insight was that FQDNs (with `ndots:5`) get tried as-is first, so `oaapi.inbcu.com` resolves without needing `inbcu.com` in the search list - but we kept it as a safety net since it takes one of the 3 available slots and costs nothing.

This one:

```bash
kubectl exec -n curl curl-6l26r -- \
  curl -s "https://oaapi.inbcu.com/onair-async-server-api/v0.0.1/onair/metadata/CallBack" \
  -o /dev/null -w "%{http_code}"
```

It returned **exit code 60** (SSL error) - not a DNS failure. If `inbcu.com` search domain was needed to resolve the hostname, it would have failed with a DNS/connection error instead. The fact that curl got all the way to an SSL handshake proved the FQDN resolved fine on its own.

And it was backed up by:

```bash
dig oaapi.inbcu.com +short
# returned 100.99.212.191 immediately
```

Which confirmed `oaapi.inbcu.com` is a proper FQDN in corporate DNS, not a short name that needs the search domain to be completed.


### fix
```bash
# verify current search domains on all nodes
for node in "${NODES[@]}"; do
  echo "=== $node ==="
  ssh $node "grep search /etc/resolv.conf"
done

# verify current DOMAIN in nic config on all nodes
for node in "${NODES[@]}"; do
  echo "=== $node ==="
  ssh $node "grep DOMAIN /etc/sysconfig/network-scripts/ifcfg-ens160"
done

# check kubelet dns errors
journalctl -u kubelet --no-pager | grep -i "search line"

# check pod resolv.conf
kubectl exec -n p123 <pod-name> -- cat /etc/resolv.conf

# fix - remove stg-tfayd.com and awsc3.com from all nodes
for node in "${NODES[@]}"; do
  echo "=== $node ==="
  ssh $node "
    sudo sed -i 's/DOMAIN=.*/DOMAIN=\"tfayd.com nbcuni.ge.com inbcu.com\"/' \
      /etc/sysconfig/network-scripts/ifcfg-ens160 &&
    sudo nmcli con reload &&
    sudo nmcli con up ens160 &&
    grep search /etc/resolv.conf
  "
done

# verify fix on all nodes - should show 3 domains only
for node in "${NODES[@]}"; do
  echo "=== $node ==="
  ssh $node "grep search /etc/resolv.conf"
done

# verify kubelet is clean after fix
journalctl -u kubelet --since "5 minutes ago" | grep -i "search line"

# rollback - restore original 5 search domains
for node in "${NODES[@]}"; do
  echo "=== $node ==="
  ssh $node "
    sudo sed -i 's/DOMAIN=.*/DOMAIN=\"tfayd.com stg-tfayd.com nbcuni.ge.com inbcu.com awsc3.com\"/' \
      /etc/sysconfig/network-scripts/ifcfg-ens160 &&
    sudo nmcli con reload &&
    sudo nmcli con up ens160 &&
    grep search /etc/resolv.conf
  "
done
```