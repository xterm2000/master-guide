# F5 NGINX Ingress Controller - Setup Checklist

This checklist covers a full installation of the F5 NGINX Ingress Controller (OSS) on this cluster:
NLB → NodePort (30080/30091) → NGINX IC → VirtualServer → pods.

---

## Phase 1 - Prerequisites

- [ ] Cluster is up and nodes are `Ready`
  ```bash
  kubectl get nodes
  ```
- [ ] `kubectl` is configured and pointing at the correct cluster
  ```bash
  kubectl cluster-info
  ```
- [ ] Helm is installed (v3+)
  ```bash
  helm version
  ```
- [ ] NLB is deployed (via CloudFormation) and target groups are configured:
  - Port `30080` → HTTP target group
  - Port `30091` → HTTPS target group

---

## Phase 2 - Install the Controller

- [ ] Add the NGINX Helm repo
  ```bash
  helm repo add nginx-stable https://helm.nginx.com/stable
  helm repo update
  ```
- [ ] Create the namespace
  ```bash
  kubectl create namespace nginx-ingress
  ```
- [ ] Install via Helm
  ```bash
  helm upgrade --install nginx-ingress nginx-stable/nginx-ingress \
    --namespace nginx-ingress \
    --set controller.kind=deployment \
    --set controller.replicaCount=1
  ```
- [ ] Verify controller pod is `Running`
  ```bash
  kubectl get pods -n nginx-ingress
  ```

---

## Phase 3 - NodePort Service

- [ ] Create (or apply) the NodePort Service with fixed ports matching the NLB target groups:
  ```yaml
  apiVersion: v1
  kind: Service
  metadata:
    name: nginx-ingress
    namespace: nginx-ingress
  spec:
    type: NodePort
    ports:
    - port: 80
      targetPort: 80
      nodePort: 30080       # must match NLB TGWorkerHTTP
      protocol: TCP
      name: http
    - port: 443
      targetPort: 443
      nodePort: 30091       # must match NLB TGWorkerHTTPS
      protocol: TCP
      name: https
    selector:
      app: nginx-ingress    # must match controller pod label
  ```
  ```bash
  kubectl apply -f <service-file>.yaml
  ```
- [ ] Confirm the service exists with the correct NodePorts
  ```bash
  kubectl get svc -n nginx-ingress
  ```
- [ ] Check NLB health checks pass (green in AWS Console → EC2 → Target Groups for both 30080 and 30091)

---

## Phase 4 - Install cert-manager

- [ ] Install cert-manager (required for TLS automation)
  ```bash
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
  ```
- [ ] Wait for cert-manager pods to be `Running`
  ```bash
  kubectl get pods -n cert-manager
  ```

---

## Phase 5 - Route53 Credentials Secret

- [ ] Create the `route53-credentials` secret (used by ClusterIssuer for DNS01 challenge)
  ```bash
  kubectl create secret generic route53-credentials \
    --namespace cert-manager \
    --from-literal=secret-access-key=<YOUR_AWS_SECRET_KEY>
  ```
  > The IAM user needs `route53:ChangeResourceRecordSets` and `route53:ListHostedZones` permissions.

---

## Phase 6 - ClusterIssuer

- [ ] Edit `modules/cluster-issuer.yaml` - fill in:
  - `email` - your real email (Let's Encrypt expiry notices)
  - `hostedZoneID` - from Route53 hosted zone
  - `accessKeyID` - IAM access key ID
- [ ] Apply it
  ```bash
  kubectl apply -f modules/cluster-issuer.yaml
  ```
- [ ] Verify it is `Ready`
  ```bash
  kubectl get clusterissuer letsencrypt-prod
  # READY column should show True
  ```

---

## Phase 7 - Certificate

- [ ] Edit `modules/certificate.yaml` - update `dnsNames` to your actual domain(s)
- [ ] Apply it
  ```bash
  kubectl apply -f modules/certificate.yaml
  ```
- [ ] Watch the certificate until it is `Ready: True` (can take 1–3 min for DNS01 challenge)
  ```bash
  kubectl get certificate
  kubectl describe certificate myapp-cert   # check Events for errors
  ```
- [ ] Confirm the TLS secret was created
  ```bash
  kubectl get secret myapp-tls
  ```

---

## Phase 8 - DNS

- [ ] Get the NLB DNS name from CloudFormation Outputs or:
  ```bash
  aws elbv2 describe-load-balancers --query 'LoadBalancers[*].DNSName' --output text
  ```
- [ ] In Route53, create a CNAME (or alias A) record pointing your domain to the NLB DNS name
  ```
  api.example.com  CNAME  <nlb-dns>.us-east-1.elb.amazonaws.com
  ```
  > Tip: a wildcard record `*.example.com` covers all subdomains at once.

---

## Phase 9 - VirtualServer

> F5 NGINX IC uses `VirtualServer` CRDs (`k8s.nginx.org/v1`), not standard `Ingress` objects.
> A `host:` field is **required** - the controller rejects a VS without one.

- [ ] Edit `modules/vs.yaml` - update:
  - `host:` - your domain (must match the certificate dnsNames)
  - `tls.secret:` - name of the TLS secret (`myapp-tls`)
  - `upstreams[].service` - name of your backend Service
- [ ] Apply it
  ```bash
  kubectl apply -f modules/vs.yaml
  ```
- [ ] Check VS status
  ```bash
  kubectl get virtualserver
  # STATE should be Valid
  kubectl describe virtualserver myapp-vs   # check Events for rejection reasons
  ```

---

## Phase 10 - End-to-End Smoke Test

- [ ] HTTP redirects to HTTPS
  ```bash
  curl -I http://<your-domain>/
  # Expect: 301 → https://
  ```
- [ ] HTTPS responds with a valid cert
  ```bash
  curl -v https://<your-domain>/
  # Expect: 200, no cert errors
  ```
- [ ] Routes reach the correct backends
  ```bash
  curl https://<your-domain>/hashi
  curl https://<your-domain>/api/
  ```
- [ ] Check NGINX IC logs for errors
  ```bash
  kubectl logs -n nginx-ingress -l app=nginx-ingress --tail=50
  ```

---

## Quick Reference - Port Flow

```
Client
  │
  ▼
NLB :80   → NodePort 30080 → NGINX IC :80  → HTTP→HTTPS redirect
NLB :443  → NodePort 30091 → NGINX IC :443 → VirtualServer → pod :80
```

## Common Pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| VS state `Invalid` | Missing `host:` field | Add `host:` to the VirtualServer spec |
| VS rejected despite valid spec | Standard `Ingress` exists for same hostname | Delete the conflicting `Ingress` object |
| NLB health check unhealthy | NodePort mismatch | Verify service nodePort matches target group port |
| Certificate stuck `False` | Wrong hostedZoneID or IAM perms | Check `kubectl describe certificaterequest` |
| 502 from NLB | Controller pod not running | `kubectl get pods -n nginx-ingress` |
