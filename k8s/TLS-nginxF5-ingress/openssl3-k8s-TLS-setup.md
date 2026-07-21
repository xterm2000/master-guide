# Kubernetes TLS - Complete Setup Guide

cert-manager + Let's Encrypt + NGINX Ingress Controller (VirtualServer mode) on AWS/NLB.


---

## 1. Architecture

### Infrastructure

```
Internet
   │
   ▼
NLB (public, internet-facing)   44.205.201.26
   ├-- :80  ------------------► Worker nodes :30080  (HTTP → redirect to HTTPS)
   └-- :443 ------------------► Worker nodes :30091  (HTTPS, TLS terminates here)
                                      │
                               Private subnet
                         ┌----------------------------┐
                         │  NGINX Ingress Controller   │
                         │  (NodePort 30080 / 30091)   │
                         └----------------------------┘
                                      │
                    ┌-----------------┼------------------┐
                    ▼                 ▼                  ▼
               nginx pods        hashi pods         (other upstreams)
```

### TLS termination flow

```
Browser
  │  HTTPS :443
  ▼
NLB :443  --►  Worker :30091
                    │
                    ▼
           NGINX Ingress Controller
           decrypts TLS using myapp-tls secret
                    │
                    ▼
           pods (plain HTTP internally - fine)
```

### cert-manager + DNS-01 renewal flow

```
cert-manager (every 60 days)
      │
      │  Route53 API (HTTPS outbound)
      ▼
Creates TXT record: _acme-challenge.api.example.com
      │
      ▼
Let's Encrypt queries DNS → verified → issues cert
      │
      ▼
cert-manager updates myapp-tls Secret
      │
      ▼
NGINX ingress hot-reloads the new cert automatically
```

---

## 2. Prerequisites

```bash
# Confirm ingress controller is running
kubectl get pods -n nginx-ingress
kubectl get svc -n nginx-ingress

# Note the NodePorts - you need these in the NLB target groups
# nginx-ingress   NodePort   80:30080/TCP,443:30091/TCP
```

NLB must have two listeners:

- `:80` → Target Group → Worker nodes `:30080`
- `:443` → Target Group → Worker nodes `:30091`

Domain must resolve to the NLB public IP:

```bash
nslookup api.example.com
# Address: 44.205.201.26
```

---

## 3. Install cert-manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
```

Wait for all three pods to be running:

```bash
kubectl get pods -n cert-manager --watch
# cert-manager-xxxxx                Running  ✓
# cert-manager-cainjector-xxxxx     Running  ✓
# cert-manager-webhook-xxxxx        Running  ✓
```

---

## 4. HTTP-01 Challenge - and Why It Fails with VirtualServer

### What HTTP-01 does

```
cert-manager asks Let's Encrypt for a cert
      │
      ▼
Let's Encrypt: "prove you own api.example.com"
      │
      ▼
cert-manager creates:
  - a solver Pod listening on :8089
  - a Service (NodePort) pointing to that pod
  - an Ingress rule for /.well-known/acme-challenge/*
      │
      ▼
Let's Encrypt fetches http://api.example.com/.well-known/acme-challenge/<token>
      │
      ▼
Token verified → cert issued
```

### Why it fails with VirtualServer

cert-manager creates a standard `Ingress` object for the challenge route. But when using `VirtualServer`, the NGINX Ingress Controller rejects any `Ingress` that tries to claim a hostname already owned by a `VirtualServer`:

```
Warning  Rejected  nginx-ingress-controller  All hosts are taken by other resources
```

Additionally, the `tls.redirect.enable: true` setting in the VirtualServer causes HTTP → HTTPS redirect to fire **before** the challenge route is reached:

```bash
curl http://api.example.com/.well-known/acme-challenge/<token>
# < HTTP/1.1 301 Moved Permanently   ← kills the challenge
```

---

## 5. The HTTP-01 Workaround - Manual VirtualServer Routing

> **Note:** This workaround was used during initial setup. DNS-01 (Section 6) is the permanent solution. This section documents what was done for reference.

### The problem in sequence

1. cert-manager creates `cm-acme-http-solver-<random>` Service and Pod
2. cert-manager creates an Ingress for `/.well-known/acme-challenge/*`
3. NGINX rejects the Ingress → challenge never gets served
4. Let's Encrypt can't verify → cert never issues

### The fix - add the solver as an upstream in VirtualServer

**Step 1 - get the solver service name and token (move fast - they expire)**

```bash
# Solver service name - changes every attempt
kubectl get svc -n default | grep acme
# cm-acme-http-solver-ms9ql   NodePort   10.233.36.59   8089:31246/TCP

# Current challenge token
kubectl get challenge -n default -o yaml | grep token:
#   token: bLs7Ir_DHBrdDFy-We7nzv2c2j7Jt_smvASVoWOWhh8

# Full challenge status
kubectl describe challenge -n default
```

**Step 2 - disable TLS redirect temporarily**

The redirect intercepts HTTP before the challenge can be served. Set `redirect.enable: false` in the VirtualServer while the challenge is pending.

**Step 3 - add acme-solver upstream and route to VirtualServer**

```yaml
apiVersion: k8s.nginx.org/v1
kind: VirtualServer
metadata:
  name: myapp-vs
spec:
  host: api.example.com
  tls:
    secret: myapp-tls
    redirect:
      enable: false                    # disabled during challenge
  upstreams:
  - name: nginx-api
    service: nginx3-svc
    port: 80
  - name: hashi
    service: hashi-svc
    port: 80
  - name: acme-solver                          # add this
    service: cm-acme-http-solver-ms9ql         # exact service name from above
    port: 8089
  routes:
  - path: /.well-known/acme-challenge          # must be FIRST
    action:
      pass: acme-solver
  - path: /api/
    action:
      proxy:
        upstream: nginx-api
        rewritePath: /
  - path: /hashi
    action:
      pass: hashi
  - path: /
    action:
      pass: hashi
```

```bash
kubectl apply -f vs.yaml
```

**Step 4 - verify the token is being served**

```bash
curl http://api.example.com/.well-known/acme-challenge/bLs7Ir_DHBrdDFy-We7nzv2c2j7Jt_smvASVoWOWhh8
# Must return the full key string:
# bLs7Ir_DHBrdDFy-We7nzv2c2j7Jt_smvASVoWOWhh8.yC20anT6uvEPP6JcZRuOqJTg-0yDexpetp7tzr1vS1c
```

If it returns `301` → redirect is still on, disable it. If it returns your app response → route order is wrong, move acme route first. If it returns `404` → solver pod isn't responding.

**Step 5 - watch the challenge resolve**

```bash
kubectl get challenge -n default --watch
# api.example.com: pending → valid
# No resources found  ← cert-manager deletes challenges after success
```

**Step 6 - verify cert issued**

```bash
kubectl get certificate -n default
# NAME           READY   SECRET        AGE
# myapp-cert   True    myapp-tls   Xm
```

### Why this approach is not sustainable

- The solver service name (`cm-acme-http-solver-<random>`) is randomly generated and changes on every renewal attempt
- You must update the VirtualServer with the new name before the challenge times out (a few minutes window)
- Auto-renewal every 60 days would require manual intervention every time

**Solution: DNS-01 (Section 6)**

---

## 6. DNS-01 Challenge - the Proper Solution

DNS-01 proves domain ownership by creating a TXT record in Route53. No HTTP routing involved. Works for wildcard certs. Fully automatic.

### Step 1 - create IAM policy

Save as `cert-manager-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "route53:GetChange",
      "Resource": "arn:aws:route53:::change/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/YOUR_ZONE_ID"
    },
    {
      "Effect": "Allow",
      "Action": "route53:ListHostedZonesByName",
      "Resource": "*"
    }
  ]
}
```

```bash
aws iam create-policy \
  --policy-name cert-manager-route53 \
  --policy-document file://cert-manager-policy.json
```

### Step 2 - create IAM user and attach policy

```bash
aws iam create-user --user-name cert-manager-route53

aws iam attach-user-policy \
  --user-name cert-manager-route53 \
  --policy-arn arn:aws:iam::<account-id>:policy/cert-manager-route53

# Verify attachment (note: attach-user-policy = managed policy)
aws iam list-attached-user-policies --user-name cert-manager-route53
```

### Step 3 - create access key

```bash
aws iam create-access-key --user-name cert-manager-route53
# Save AccessKeyId and SecretAccessKey - secret shown only once
```

### Step 4 - find your hosted zone ID

```bash
aws route53 list-hosted-zones \
  --query "HostedZones[*].{Name:Name,Id:Id}" \
  --output json | jq
# "Id": "/hostedzone/<YOUR-ZONE-ID>"
```

### Step 5 - create Kubernetes Secret with IAM credentials

```bash
# Use single quotes - secret key may contain +, /, = characters
kubectl create secret generic route53-credentials \
  --namespace cert-manager \
  --from-literal=secret-access-key='YOUR_SECRET_ACCESS_KEY'
```

### Step 6 - update ClusterIssuer to use DNS-01

```yaml
# clusterissuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - dns01:
        route53:
          region: us-east-1
          hostedZoneID: <YOUR-ZONE-ID>
          accessKeyID: <YOUR-ACCESS-KEY-ID>
          secretAccessKeySecretRef:
            name: route53-credentials
            key: secret-access-key
```

```bash
kubectl apply -f clusterissuer.yaml

kubectl get clusterissuer letsencrypt-prod
# READY = True
```

### Step 7 - Certificate resource

```yaml
# certificate.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-cert
  namespace: default
spec:
  secretName: myapp-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - api.example.com
  - example.com              # bare domain included
```

```bash
kubectl apply -f certificate.yaml
```

### Step 8 - force renewal to test DNS-01 end to end

```bash
# Delete the secret - cert-manager detects it's missing and reissues
kubectl delete secret myapp-tls -n default
```

### Step 9 - watch it work

```bash
# Terminal 1 - watch certificate status
kubectl get certificate -n default --watch

# Terminal 2 - watch TXT record appear/disappear in DNS (purely observational)
watch -n5 "dig +short TXT _acme-challenge.api.example.com @8.8.8.8"
```

Expected certificate output:

```
NAME           READY   SECRET        AGE
myapp-cert   False   myapp-tls   10s
myapp-cert   True    myapp-tls   15s   ← done
```

Describe the cert to confirm:

```bash
kubectl describe certificate myapp-cert -n default
# Status: Ready = True
# Renewal Time: <60 days from now>
# Issuing: The certificate has been successfully issued
```

---

## 7. VirtualServer - Final Clean Config

After DNS-01 is working, remove the acme-solver upstream and route, and re-enable the TLS redirect:

```yaml
# vs.yaml
apiVersion: k8s.nginx.org/v1
kind: VirtualServer
metadata:
  name: myapp-vs
spec:
  host: api.example.com
  tls:
    secret: myapp-tls
    redirect:
      enable: true             # HTTP → HTTPS redirect back on
  upstreams:
  - name: nginx-api
    service: nginx3-svc
    port: 80
  - name: hashi
    service: hashi-svc
    port: 80
  routes:
  - path: /api/
    action:
      proxy:
        upstream: nginx-api
        rewritePath: /
  - path: /hashi
    action:
      pass: hashi
  - path: /
    action:
      pass: hashi
```

```bash
kubectl apply -f vs.yaml

kubectl get vs myapp-vs
# State: Valid  (no warnings)
```

---

## 8. Adding the Bare Domain

`example.com` needs its own VirtualServer - `host:` takes a single value. The `myapp-tls` secret already covers it (it's in `dnsNames`).

### Option A - redirect to api.example.com

```yaml
# myapp-root-vs.yaml
apiVersion: k8s.nginx.org/v1
kind: VirtualServer
metadata:
  name: myapp-root-vs
spec:
  host: example.com
  tls:
    secret: myapp-tls
    redirect:
      enable: true
  upstreams:
  - name: hashi
    service: hashi-svc
    port: 80
  routes:
  - path: /
    action:
      redirect:
        url: https://api.example.com${request_uri}   # curly braces required
        code: 301
```

> **Note:** Variables in VirtualServer redirect URLs must use `${var}` not `$var`. `$request_uri` will be rejected - `${request_uri}` is correct.

### Option B - serve the same app

```yaml
apiVersion: k8s.nginx.org/v1
kind: VirtualServer
metadata:
  name: myapp-root-vs
spec:
  host: example.com
  tls:
    secret: myapp-tls
    redirect:
      enable: true
  upstreams:
  - name: nginx-api
    service: nginx3-svc
    port: 80
  - name: hashi
    service: hashi-svc
    port: 80
  routes:
  - path: /api/
    action:
      proxy:
        upstream: nginx-api
        rewritePath: /
  - path: /hashi
    action:
      pass: hashi
  - path: /
    action:
      pass: hashi
```

```bash
kubectl apply -f myapp-root-vs.yaml
kubectl get vs
```

---

## 9. Verification Commands

### HTTPS is working

```bash
curl https://api.example.com/status
curl https://api.example.com/health
curl https://api.example.com/hashi
```

### HTTP redirects to HTTPS

```bash
curl -v http://api.example.com/status 2>&1 | grep "< HTTP\|Location"
# < HTTP/1.1 301 Moved Permanently
# < Location: https://api.example.com/status
```

### Inspect the TLS certificate

```bash
curl -vvv https://api.example.com/status 2>&1 | grep -A10 "Server certificate"
# *  subject: CN=api.example.com
# *  issuer: C=US; O=Let's Encrypt; CN=R13
# *  subjectAltName: host "api.example.com" matched cert's "api.example.com"
# *  SSL certificate verify ok.
```

### cert-manager state

```bash
# Certificate status
kubectl get certificate -n default
kubectl describe certificate myapp-cert -n default

# Secret exists
kubectl get secret myapp-tls -n default

# ClusterIssuer is ready
kubectl get clusterissuer letsencrypt-prod

# No pending challenges (good - means everything resolved)
kubectl get challenge -n default

# Certificate request history
kubectl describe certificaterequest -n default
```

### VirtualServer state

```bash
kubectl get vs
# State should be Valid, not Warning

kubectl describe vs myapp-vs
```

### Debugging a stuck challenge

```bash
# Full challenge details including error reason
kubectl describe challenge -n default

# Check the order
kubectl get order -n default
kubectl describe order -n default

# cert-manager logs
kubectl logs -n cert-manager deploy/cert-manager | tail -50

# Force a full retry (nuclear option)
kubectl delete challenge -n default --all
kubectl delete order -n default --all
kubectl delete certificaterequest -n default --all
# cert-manager recreates everything automatically
```

### Test DNS-01 TXT record (observational only)

```bash
# Watch for _acme-challenge TXT record during renewal
watch -n5 "dig +short TXT _acme-challenge.api.example.com @8.8.8.8"
# Briefly shows the challenge token during issuance, then empty after
```

---

## 10. How Auto-Renewal Works

cert-manager renews certificates **30 days before expiry** (at `Renewal Time` in the certificate status). For a 90-day Let's Encrypt cert, renewal happens at day 60.

```
Day 60 - cert-manager wakes up
      │
      ▼
Creates TXT record in Route53
(IAM credentials from route53-credentials secret)
      │
      ▼
Let's Encrypt verifies DNS → issues new cert
      │
      ▼
cert-manager updates myapp-tls Secret in-place
      │
      ▼
NGINX Ingress hot-reloads → new cert served
      │
      ▼
Zero downtime. Zero manual steps.
```

Check when your cert renews:

```bash
kubectl get certificate myapp-cert -n default -o jsonpath='{.status.renewalTime}'
# 2026-07-22T14:09:47Z
```

The only thing that can break auto-renewal:

- IAM credentials rotated or deleted
- Route53 hosted zone ID changed
- `route53-credentials` secret deleted from `cert-manager` namespace
- cert-manager pods not running