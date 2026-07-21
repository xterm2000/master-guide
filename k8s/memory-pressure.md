# K8s Memory Pressure Runbook

> Diagnosing and fixing scheduler `Insufficient memory` errors caused by over-requested pods.

---

## 1. Diagnose

### Check node eviction thresholds vs actual usage

Start a proxy once, loop all nodes for eviction config, then compare with `top`:

```bash
kubectl proxy --port=8001 &
PROXY_PID=$!
sleep 1

for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== $node ==="
  curl -s http://localhost:8001/api/v1/nodes/$node/proxy/configz \
    | jq '.kubeletconfig.evictionHard'
done

kill $PROXY_PID
```

```bash
kubectl top nodes
```

### Check node allocatable vs capacity

What the scheduler actually sees (not physical RAM):

```bash
kubectl get nodes -o custom-columns='NODE:.metadata.name,ALLOC_CPU:.status.allocatable.cpu,ALLOC_MEM:.status.allocatable.memory,CAP_CPU:.status.capacity.cpu,CAP_MEM:.status.capacity.memory'
```
```bash
kubectl get nodes -o jsonpath='{range .items[*]}{"Node: "}{.metadata.name}{"\n"}{"  Allocatable - CPU: "}{.status.allocatable.cpu}{"  Mem: "}{.status.allocatable.memory}{"\n"}{"  Capacity    - CPU: "}{.status.capacity.cpu}{"  Mem: "}{.status.capacity.memory}{"\n\n"}{end}'
```
### Check committed (requested) memory per node

This is the key metric - scheduler blocks on requests, not actual usage:

```bash
kubectl get pods -A --field-selector=status.phase=Running -o json | jq -r '
  .items[] |
  .spec.nodeName as $node |
  .spec.containers[] |
  select(.resources.requests.memory != null) |
  [$node, .resources.requests.memory] | @tsv
' | awk '{
  node=$1; mem=$2;
  if (mem ~ /Mi$/) { gsub(/Mi/,"",mem); total[node]+=mem }
  else if (mem ~ /Gi$/) { gsub(/Gi/,"",mem); total[node]+=mem*1024 }
  else if (mem ~ /Ki$/) { gsub(/Ki/,"",mem); total[node]+=mem/1024 }
} END {
  for (n in total) printf "%-45s %8.0f Mi  (%4.1f%%)\n", n, total[n], total[n]/21474*100
}' | sort -k2 -rn
```

> If nodes show 95-100%+ committed while `kubectl top` shows 45-60% actual usage, the problem is **over-requested pods**.

### Find pending pods and their requests

```bash
kubectl get pods -A --field-selector=status.phase=Pending

kubectl get pods -A --field-selector=status.phase=Pending -o json | jq -r '
  .items[] |
  [.metadata.namespace, .metadata.name,
   (.spec.containers[].resources.requests.memory // "none")] | @tsv'
```

### Check actual vs requested across all env namespaces

```bash
kubectl top pods -A --sort-by=memory --no-headers | while read ns pod cpu mem; do
  req=$(kubectl get pod $pod -n $ns -o jsonpath=\
    '{.spec.containers[0].resources.requests.memory}' 2>/dev/null)
  echo "$ns $pod actual:$mem requested:$req"
done
```

---

## 2. Fix

### Patch all over-requested deployments across env namespaces

Based on observed actual usage (~300-615Mi) vs inflated requests (768Mi–2500Mi). Each `kubectl set resources` triggers a rolling restart - pods stay up.

```bash
NAMESPACES="q123 s123 i124 d124 u123 g124"

# 2500Mi → 700Mi  (async-server, plan-api in larger envs)
for ns in $NAMESPACES; do
  for deploy in $(kubectl get deployments -n $ns -o json 2>/dev/null | jq -r '
    .items[] |
    select(.spec.template.spec.containers[].resources.requests.memory == "2500Mi") |
    .metadata.name'); do
    echo "[$ns] Patching $deploy: 2500Mi → 700Mi"
    kubectl set resources deployment $deploy -n $ns \
      --requests=memory=700Mi --limits=memory=1200Mi
  done
done

# 1500Mi → 700Mi
for ns in $NAMESPACES; do
  for deploy in $(kubectl get deployments -n $ns -o json 2>/dev/null | jq -r '
    .items[] |
    select(.spec.template.spec.containers[].resources.requests.memory == "1500Mi") |
    .metadata.name'); do
    echo "[$ns] Patching $deploy: 1500Mi → 700Mi"
    kubectl set resources deployment $deploy -n $ns \
      --requests=memory=700Mi --limits=memory=1200Mi
  done
done

# 1Gi → 650Mi
for ns in $NAMESPACES; do
  for deploy in $(kubectl get deployments -n $ns -o json 2>/dev/null | jq -r '
    .items[] |
    select(.spec.template.spec.containers[].resources.requests.memory == "1Gi") |
    .metadata.name'); do
    echo "[$ns] Patching $deploy: 1Gi → 650Mi"
    kubectl set resources deployment $deploy -n $ns \
      --requests=memory=650Mi --limits=memory=1100Mi
  done
done

# 768Mi → 400Mi  (standard APIs, actual usage ~300Mi)
for ns in $NAMESPACES; do
  for deploy in $(kubectl get deployments -n $ns -o json 2>/dev/null | jq -r '
    .items[] |
    select(.spec.template.spec.containers[].resources.requests.memory == "768Mi") |
    .metadata.name'); do
    echo "[$ns] Patching $deploy: 768Mi → 400Mi"
    kubectl set resources deployment $deploy -n $ns \
      --requests=memory=400Mi --limits=memory=700Mi
  done
done

# 512Mi → 300Mi  (spring-admin)
for ns in $NAMESPACES; do
  for deploy in $(kubectl get deployments -n $ns -o json 2>/dev/null | jq -r '
    .items[] |
    select(.spec.template.spec.containers[].resources.requests.memory == "512Mi") |
    .metadata.name'); do
    echo "[$ns] Patching $deploy: 512Mi → 300Mi"
    kubectl set resources deployment $deploy -n $ns \
      --requests=memory=300Mi --limits=memory=600Mi
  done
done
```

---

## 3. Post-fix Checks

### Confirm no pending pods remain

```bash
kubectl get pods -A --field-selector=status.phase=Pending
```

### Verify committed memory dropped across nodes

```bash
kubectl get pods -A --field-selector=status.phase=Running -o json | jq -r '
  .items[] |
  .spec.nodeName as $node |
  .spec.containers[] |
  select(.resources.requests.memory != null) |
  [$node, .resources.requests.memory] | @tsv
' | awk '{
  node=$1; mem=$2;
  if (mem ~ /Mi$/) { gsub(/Mi/,"",mem); total[node]+=mem }
  else if (mem ~ /Gi$/) { gsub(/Gi/,"",mem); total[node]+=mem*1024 }
  else if (mem ~ /Ki$/) { gsub(/Ki/,"",mem); total[node]+=mem/1024 }
} END {
  for (n in total) printf "%-45s %8.0f Mi  (%4.1f%%)\n", n, total[n], total[n]/21474*100
}' | sort -k2 -rn
```

> Target: nodes at 40-65% committed, leaving headroom for scaling and new deployments.

### Check for OOM events

```bash
kubectl get events -A --field-selector reason=OOMKilling
kubectl get events -A --field-selector reason=Evicted
```

---

## 4. Prevention

### Set LimitRange per namespace

Enforces minimum requests on all new pods - prevents future request inflation:

```bash
for ns in q123 s123 i124 d124 u123 g124; do
kubectl apply -f - <<EOF
apiVersion: v1
kind: LimitRange
metadata:
  name: memory-defaults
  namespace: $ns
spec:
  limits:
  - type: Container
    default:
      memory: 700Mi
    defaultRequest:
      memory: 400Mi
    max:
      memory: 2Gi
EOF
done
```

### Quick node pressure check (bookmark this)

```bash
kubectl get nodes -o custom-columns=\
'NODE:.metadata.name,\
MEM_PRESSURE:.status.conditions[?(@.type=="MemoryPressure")].status,\
DISK_PRESSURE:.status.conditions[?(@.type=="DiskPressure")].status'
```

### misc 

**PODS Check actual usage:**
```bash
# get pods per node 
kubectl get pods -A --field-selector=spec.nodeName=eclapls00074le.tfayd.com
# with memory 
kubectl get pods -A --field-selector=spec.nodeName=eclapls00074le.tfayd.com -o json | jq -r '
  .items[] | 
  [.metadata.namespace, .metadata.name, (.spec.containers[].resources.requests.memory // "none")] | 
  @tsv'
```

```bash
kubectl top pods -A --sort-by=memory | head -30
```
```bash
kubectl describe node eclapls00074le.tfayd.com | grep -A10 "Labels:"
```

**Find pods with inflated requests vs actual usage on the eligible nodes:** 
```bash
kubectl top pods -A --sort-by=memory --no-headers | while read ns pod cpu mem; do
  req=$(kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.requests.memory}' 2>/dev/null)
  echo "$ns $pod actual:$mem requested:$req"
done
```
