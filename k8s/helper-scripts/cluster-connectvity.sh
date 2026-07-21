#!/usr/bin/env bash
# Full inter-cluster connectivity check using curl probe pods.
set -euo pipefail

PASS=0; FAIL=0
ERRORS=()

hdr() { echo ""; echo "=== $1 ==="; }
ok()  { echo "  [OK]  $*"; ((PASS+=1)); }
fail(){ echo "  [FAIL] $*"; ((FAIL+=1)); ERRORS+=("$*"); }

# -- Gather pod inventory -----------------------------------------------------
hdr "Deploying curl-probe DaemonSet"
kubectl apply -f - <<'YAML' >/dev/null
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: curl-probe
  namespace: default
  labels:
    app: curl-probe
spec:
  selector:
    matchLabels:
      app: curl-probe
  template:
    metadata:
      labels:
        app: curl-probe
    spec:
      tolerations:
      - operator: Exists
      containers:
      - name: curl
        image: curlimages/curl:latest
        command: ["sleep", "3600"]
        resources:
          requests:
            cpu: "10m"
            memory: "16Mi"
YAML

kubectl rollout status daemonset/curl-probe --timeout=120s >/dev/null
echo "  DaemonSet ready."

hdr "Deploying echo-server"
kubectl apply -f - <<'YAML' >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-server
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: echo-server
  template:
    metadata:
      labels:
        app: echo-server
    spec:
      containers:
      - name: echo
        image: hashicorp/http-echo:latest
        args: ["-text=hello-from-echo"]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: echo-svc
  namespace: default
spec:
  selector:
    app: echo-server
  ports:
  - port: 80
    targetPort: 5678
YAML

kubectl wait deployment/echo-server --for=condition=Available --timeout=90s >/dev/null
echo "  echo-server ready."

mapfile -t PODS      < <(kubectl get pods -l app=curl-probe -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
mapfile -t POD_IPS   < <(kubectl get pods -l app=curl-probe -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}')
mapfile -t NODE_LIST < <(kubectl get pods -l app=curl-probe -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}')

echo ""
echo "  Probes:"
for i in "${!PODS[@]}"; do
  printf "    %-40s ip=%-16s node=%s\n" "${PODS[$i]}" "${POD_IPS[$i]}" "${NODE_LIST[$i]}"
done

# -- DNS ----------------------------------------------------------------------
hdr "DNS resolution"
POD="${PODS[0]}"
if kubectl exec "$POD" -- curl -sf --max-time 5 -k https://kubernetes.default.svc.cluster.local/healthz 2>/dev/null | grep -q ok; then
  ok "API server DNS (kubernetes.default.svc.cluster.local)"
else
  fail "API server DNS"
fi

if kubectl exec "$POD" -- curl -sf --max-time 5 http://echo-svc.default.svc.cluster.local 2>/dev/null | grep -q hello-from-echo; then
  ok "Service DNS (echo-svc.default.svc.cluster.local)"
else
  fail "Service DNS"
fi

if kubectl exec "$POD" -- curl -sf --max-time 5 http://echo-svc 2>/dev/null | grep -q hello-from-echo; then
  ok "Short-name DNS (echo-svc)"
else
  fail "Short-name DNS"
fi

# -- ClusterIP service reachability from every node --------------------------
hdr "ClusterIP service reachability"
for i in "${!PODS[@]}"; do
  if kubectl exec "${PODS[$i]}" -- curl -sf --max-time 5 http://echo-svc.default.svc.cluster.local 2>/dev/null | grep -q hello-from-echo; then
    ok "${PODS[$i]} (${NODE_LIST[$i]}) → echo-svc"
  else
    fail "${PODS[$i]} (${NODE_LIST[$i]}) → echo-svc"
  fi
done

# -- Kubernetes API reachability from every pod -------------------------------
hdr "Kubernetes API reachability"
for i in "${!PODS[@]}"; do
  if kubectl exec "${PODS[$i]}" -- curl -sf --max-time 5 -k https://kubernetes.default.svc/healthz 2>/dev/null | grep -q ok; then
    ok "${PODS[$i]} (${NODE_LIST[$i]}) → API server"
  else
    fail "${PODS[$i]} (${NODE_LIST[$i]}) → API server"
  fi
done

# -- External egress ----------------------------------------------------------
hdr "External egress (HTTPS)"
for i in "${!PODS[@]}"; do
  CODE=$(kubectl exec "${PODS[$i]}" -- curl -sf -o /dev/null -w "%{http_code}" --max-time 10 https://ifconfig.me 2>/dev/null || true)
  if [[ "$CODE" == "200" ]]; then
    ok "${PODS[$i]} (${NODE_LIST[$i]}) → internet (HTTP $CODE)"
  else
    fail "${PODS[$i]} (${NODE_LIST[$i]}) → internet (HTTP $CODE)"
  fi
done

# -- Summary -------------------------------------------------------------------
echo ""
echo "============================================"
echo "  TOTAL: $PASS passed, $FAIL failed"
echo "============================================"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "  Failed checks:"
  for e in "${ERRORS[@]}"; do echo "    - $e"; done
  echo ""
fi

# -- Cleanup -------------------------------------------------------------------
hdr "Cleanup"
kubectl delete daemonset curl-probe --ignore-not-found >/dev/null
kubectl delete deployment echo-server --ignore-not-found >/dev/null
kubectl delete service echo-svc --ignore-not-found >/dev/null
echo "  Removed curl-probe, echo-server, echo-svc."

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
