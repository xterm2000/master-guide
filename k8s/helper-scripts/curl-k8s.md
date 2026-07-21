# curl in Kubernetes — in-cluster probing

> Split out of `linux/text-processing/curl-text-logs.md` — this is Kubernetes debugging technique (probing Services from inside the cluster), not general curl reference. Pairs with `cluster-connectvity.sh` and `k8s-debugging.md` in this directory.

## Curl pod
### metrics
```bash
kubectl run curl-probe --image=curlimages/curl:latest --rm -it --restart=Never -- \
  curl -s -o /dev/null -w "
DNS:     %{time_namelookup}s
Connect: %{time_connect}s
TTFB:    %{time_starttransfer}s
Total:   %{time_total}s
Status:  %{http_code}
Size:    %{size_download} bytes
IP:      %{remote_ip}
" https://your-target-url.com
```
### with response 
```bash
kubectl run curl-probe --image=curlimages/curl:latest --rm -it --restart=Never --   curl -s -w "
DNS:     %{time_namelookup}s
Connect: %{time_connect}s
TTFB:    %{time_starttransfer}s
Total:   %{time_total}s
Status:  %{http_code}
Size:    %{size_download} bytes
IP:      %{remote_ip}
" nginx2p-svc.lab.svc.cluster.local:8080/foo
```
### k8s dns
```
# From within the same namespace (shortest)
nginx2p-svc

# From a different namespace
nginx2p-svc.lab

# Fully qualified (works from anywhere)
nginx2p-svc.lab.svc.cluster.local
```

### curl Daemonset
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: curl
---  
apiVersion: apps/v1
kind: DaemonSet  
metadata:
  name: curl
  namespace: curl
  labels:
    app: curl
spec:
  selector:
    matchLabels:
      app: curl
  template:
    metadata:
      labels:
        app: curl   
        name: curl 
    spec:
      tolerations:
      - key: "node.kubernetes.io/control-plane"
        operator: "Exists"
        effect: NoSchedule
      containers:
      - name: curl-pod
        image: curlimages/curl:latest
        command: ["sleep", "infinity"]
        resources:                        # ← good practice
          requests:
            cpu: "10m"
            memory: "16Mi"
          limits:
            cpu: "100m"
            memory: "64Mi"        
        

```
### Daemonset pod command 
```bash
kubectl exec -it -n curl <pod-name> -- \
curl -s -o /dev/null -w " 
DNS: %{time_namelookup}s 
Connect: %{time_connect}s 
TTFB: %{time_starttransfer}s 
Total: %{time_total}s 
Status: %{http_code} 
Size: %{size_download} 
bytes IP: %{remote_ip}
" http://nginx2p-svc.lab.svc.cluster.local
```

### kcurl function 
#### simple 
```bash
kcurl() {
  if [[ $# -ne 2 ]]; then
    echo "Usage: kcurl <pod-name> <svc.namespace:port>"
    echo "Example: kcurl curl-abc123 nginx2p-svc.lab.svc.cluster.local:80"
    return 1
  fi

  local pod=$1
  local target=$2

  echo "→ Curling http://$target from pod $pod"

  kubectl exec -it -n curl "$pod" -- \
    curl --connect-timeout 5 --max-time 10 \
    -s -w "
DNS:     %{time_namelookup}s
Connect: %{time_connect}s
TTFB:    %{time_starttransfer}s
Total:   %{time_total}s
Status:  %{http_code}
Size:    %{size_download} bytes
IP:      %{remote_ip}
" "http://$target"
}
```
#### extended
```bash
kcurl() {
  local verbose=""
  local output="-o /dev/null"

  # parse flags manually
  while [[ $# -gt 0 ]]; do
    case $1 in
      -v) verbose="-v";  shift ;;
      -o) output="";     shift ;;
      *)  break ;;          # stop at first non-flag arg
    esac
  done

  if [[ $# -ne 2 ]]; then
    echo "Usage: kcurl [-v] [-o] <pod-name> <svc:port>"
    echo "  -v   verbose curl output"
    echo "  -o   print response body to stdout"
    echo ""
    echo "Examples:"
    echo "  kcurl curl-abc123 nginx2p-svc.lab.svc.cluster.local:8080"
    echo "  kcurl -v curl-abc123 nginx2p-svc.lab.svc.cluster.local:8080"
    echo "  kcurl -o curl-abc123 nginx2p-svc.lab.svc.cluster.local:8080"
    echo "  kcurl -v -o curl-abc123 nginx2p-svc.lab.svc.cluster.local:8080"
    return 1
  fi

  local pod=$1
  local target=${2#http://}
  target=${target#https://}

  echo "→ Curling http://$target from pod $pod"

  kubectl exec -it -n curl "$pod" -- \
    curl --connect-timeout 5 --max-time 10 \
    $verbose $output -w "
DNS:     %{time_namelookup}s
Connect: %{time_connect}s
TTFB:    %{time_starttransfer}s
Total:   %{time_total}s
Status:  %{http_code}
Size:    %{size_download} bytes
IP:      %{remote_ip}
" "http://$target"
}
```
