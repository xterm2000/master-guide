### save certs to files

```bash
k config view  --raw -o jsonpath={'.clusters[0].cluster.certificate-authority-data'} | base64 -d > ca.crt
k config view  --raw -o jsonpath={'.users[0].user.client-certificate-data'} | base64 -d > client.crt
k config view  --raw -o jsonpath={'.users[0].user.client-key-data'} | base64 -d > client.key
```

### sample API request using curl with certs
```bash
SERVER=$(k config view  --raw -o jsonpath={'.clusters[0].cluster.server'})
CERTS="-cacert ca.crt --cert client.crt --key client.key"
curl $CERTS $SERVER/api/v1/namespaces/default/pods
curl $CERTS $SERVER/api/v1/namespaces/default/pods -H "Accept: application/json"
curl $CERTS $SERVER/api/v1/namespaces/default/pods -H "Accept: application/json" -w "\nHTTP Status: %{http_code}\n"

curl $CERTS $SERVER/api/v1/namespaces/default/pods -H "Accept: application/json" -w "\nHTTP Status: %{http_code}\n" | jq '.items[] | {name: .metadata.name, status: .status.phase}'
```

### add a new ingress resource
```bash
curl $CERT -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "networking.k8s.io/v1",
    "kind": "Ingress",
    "metadata": {
      "name": "my-ingress",
      "namespace": "default"
    },
    "spec": {
      "rules": [{
        "host": "myapp.example.com",
        "http": {
          "paths": [{
            "path": "/",
            "pathType": "Prefix",
            "backend": {
              "service": {
                "name": "my-service",
                "port": { "number": 80 }
              }
            }
          }]
        }
      }]
    }
  }' \
  "$API/apis/networking.k8s.io/v1/namespaces/default/ingresses"
```

### temporary API access for a user - token expires after 1 hour by default
```bash
# Create a service account
kubectl create serviceaccount api-explorer

# For quick testing, give it cluster-admin (tighten this later)
kubectl create clusterrolebinding api-explorer-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=default:api-explorer

# Create a token (valid for 1 hour by default)
kubectl create token api-explorer

# Use the token to access the API server
API="https://10.0.2.55:6443"
TOKEN=$(kubectl create token api-explorer)
curl -k -H "Authorization: Bearer $TOKEN" $API/api/v1/nodes
```

### long lived tokens
```bash
# Create a secret-based token (no expiry)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: api-explorer-token
  annotations:
    kubernetes.io/service-account.name: api-explorer
type: kubernetes.io/service-account-token
EOF

# Get the token value
TOKEN=$(kubectl get secret api-explorer-token -o jsonpath='{.data.token}' | base64 -d)

```

## option two - create user from scratch and generate a client cert

### generate key
```bash
openssl genrsa -out kb-adm.key 2048

# Generate CSR - CN = username, O = group
openssl req -new \
  -key kb-adm.key \
  -out kb-adm.csr \
  -subj "/CN=kb-adm/O=dev-team"

#          CN becomes the username in k8s
#          O  becomes the group

```

---
### create a certificate signing request in k8s
```bash

CSR=$(cat kb-adm.csr | base64 | tr -d '\n')

kubectl apply -f - <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: kb-adm
spec:
  request: $CSR
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400   # 24h, increase as needed
  usages:
  - client auth
EOF

# Approve it
kubectl certificate approve kb-adm
```

### create cluster role binding for the user, and generate kubeconfig
```bash
# Option A - same as you (full cluster-admin)
kubectl create clusterrolebinding kb-adm-admin \
  --clusterrole=cluster-admin \
  --user=kb-adm
  
  
# Option C - read-only cluster-wide
kubectl create clusterrolebinding kb-adm-readonly \
  --clusterrole=view \
  --user=kb-adm  
  

SERVER=$(kubectl config view  -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

cat > kb-adm-kubeconfig.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $(cat ca.crt | base64 | tr -d '\n')
    server: $SERVER
  name: cluster.local
users:
- name: kb-adm
  user:
    client-certificate-data: $(cat kb-adm.crt | base64 | tr -d '\n')
    client-key-data: $(cat kb-adm.key | base64 | tr -d '\n')
contexts:
- context:
    cluster: cluster.local
    user: kb-adm
  name: kb-adm@cluster.local
current-context: kb-adm@cluster.local
EOF  
# note heredoc has no '' so variables are expanded, 
# and we base64 encode the certs inline to avoid newlines breaking the yaml format


# Give them the file - they put it at ~/.kube/config
# chown $(id -u):$(id -g) kb-adm-kubeconfig.yaml
# Test it works
kubectl --kubeconfig=kb-adm-kubeconfig.yaml get pods
kubectl --kubeconfig=kb-adm-kubeconfig.yaml auth whoami


```