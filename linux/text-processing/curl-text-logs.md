# curl guide — text & logs

## Syntax

```
curl [flags] <url>
```

---

## Request & Method

|Flag|Description|
|---|---|
|`-X POST`|Specify HTTP method (GET, POST, PUT, PATCH, DELETE)|
|`-d 'data'`|Request body (implies POST)|
|`-d @file.json`|Request body from file|
|`-F 'file=@path'`|Multipart form upload|
|`-G`|Force GET and append `-d` data as query string|

---

## Headers & Auth

|Flag|Description|
|---|---|
|`-H 'Key: Value'`|Add request header|
|`-u user:pass`|Basic auth|
|`-b 'name=val'`|Send cookie|
|`-c file`|Save cookies to file|
|`-A 'agent'`|Set User-Agent|

---

## Output

|Flag|Description|
|---|---|
|`-o file`|Save response to file|
|`-O`|Save with remote filename|
|`-s`|Silent (no progress/errors)|
|`-S`|Show errors even with `-s`|
|`-v`|Verbose (request + response headers)|
|`-I`|Fetch headers only (HEAD request)|
|`-D file`|Dump response headers to file|
|`-w 'format'`|Print custom info after transfer|

---

## Redirects & TLS

|Flag|Description|
|---|---|
|`-L`|Follow redirects|
|`--max-redirs N`|Limit number of redirects|
|`-k`|Skip TLS certificate verification|
|`--cacert file`|Use custom CA cert|
|`--cert file`|Use client certificate|

---

## Timeouts & Retries

|Flag|Description|
|---|---|
|`--connect-timeout N`|Time limit to establish connection (seconds)|
|`-m N` / `--max-time N`|Total time limit for entire operation (seconds)|
|`--retry N`|Retry on transient failure|
|`--retry-delay N`|Seconds between retries|
|`--retry-connrefused`|Also retry on connection refused|

---

## Transfer

|Flag|Description|
|---|---|
|`-C -`|Resume interrupted download|
|`--limit-rate 1M`|Throttle transfer speed|
|`-Z`|Parallel transfers (curl 7.66+)|
|`-T file`|Upload file (PUT)|
|`--compressed`|Request + decompress gzip response|

---

## Connection

|Flag|Description|
|---|---|
|`-x host:port`|Use a proxy|
|`--noproxy host`|Bypass proxy for host|
|`--resolve host:port:ip`|Force resolve to specific IP|
|`--interface eth0`|Use specific network interface|
|`-4` / `-6`|Force IPv4 / IPv6|

---

## -w Format Variables

### Timing (seconds)

|Variable|Description|
|---|---|
|`%{time_namelookup}`|DNS lookup|
|`%{time_connect}`|TCP connect|
|`%{time_starttransfer}`|Time to first byte (TTFB)|
|`%{time_pretransfer}`|Before transfer began|
|`%{time_redirect}`|Time spent on redirects|
|`%{time_total}`|Total time|

### HTTP

|Variable|Description|
|---|---|
|`%{http_code}`|Response status code|
|`%{http_version}`|HTTP version used|
|`%{method}`|HTTP method used|
|`%{num_redirects}`|Number of redirects followed|
|`%{redirect_url}`|URL curl would redirect to|
|`%{url_effective}`|Final URL after redirects|
|`%{content_type}`|Response Content-Type|

### Size & Speed

|Variable|Description|
|---|---|
|`%{size_download}`|Bytes downloaded|
|`%{size_upload}`|Bytes uploaded|
|`%{size_header}`|Bytes in response headers|
|`%{speed_download}`|Average download speed (bytes/sec)|
|`%{speed_upload}`|Average upload speed (bytes/sec)|

### Connection

|Variable|Description|
|---|---|
|`%{remote_ip}`|Server IP|
|`%{remote_port}`|Server port|
|`%{local_ip}`|Local IP used|
|`%{ssl_verify_result}`|TLS cert result (0 = ok)|

---

## Common Recipes

### JSON API call

```bash
curl -s -X POST https://api.example.com/endpoint \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer TOKEN' \
  -d '{"key":"value"}' \
  -w '\nStatus: %{http_code}\n'
```

### Timing breakdown

```bash
curl -s -o /dev/null -w "
DNS:     %{time_namelookup}s
Connect: %{time_connect}s
TTFB:    %{time_starttransfer}s
Total:   %{time_total}s
Status:  %{http_code}
Size:    %{size_download} bytes
IP:      %{remote_ip}
" https://example.com
```

### Download with resume

```bash
curl -L -C - -o file.zip https://example.com/file.zip
```

### Follow redirect, save final URL

```bash
curl -Ls -o /dev/null -w '%{url_effective}' https://short.url/abc
```

### Test with timeout and retry

```bash
curl --connect-timeout 10 -m 30 --retry 3 --retry-delay 2 https://example.com
```

### Send file upload

```bash
curl -F 'file=@photo.jpg' -F 'name=myfile' https://example.com/upload
```

### Check response headers only

```bash
curl -sI https://example.com
```

---

## Kubernetes

> Also kept as a standalone copy at `k8s/helper-scripts/curl-k8s.md` alongside `cluster-connectvity.sh`/`k8s-debugging.md`.

### Curl pod
#### metrics
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
#### with response 
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
#### k8s dns
```
# From within the same namespace (shortest)
nginx2p-svc

# From a different namespace
nginx2p-svc.lab

# Fully qualified (works from anywhere)
nginx2p-svc.lab.svc.cluster.local
```

#### curl Daemonset
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
#### Daemonset pod command 
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

#### kcurl function 
##### simple 
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
##### extended
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