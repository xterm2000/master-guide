# Ingress Troubleshooting Guide

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: main-ingress
  namespace: default
spec:
  ingressClassName: nginx
  rules:
  - host: <your-hostname>.us-east-1.amazonaws.com
    http:
      paths:
      - path: /foo
        pathType: Prefix
        backend:
          service:
            name: nginx2p-svc
            port:
              number: 80
      - path: /bar
        pathType: Prefix
        backend:
          service:
            name: nginx2p-svc
            port:
              number: 80
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-deployment-svc
            port:
              number: 80

```

## 1. Check pods and readiness

```bash
kubectl get pods -n default
# Look for non-Running status or restarts > 0

kubectl logs <pod-name>
# Common issue: "bind: permission denied" → app trying to bind to port < 1024 as non-root
# Fix: use port >= 1024 (e.g. 8080) in args, containerPort, and readinessProbe
```

## 2. Check service endpoints

```bash
kubectl get endpoints <service-name> -n default
# Empty endpoints () = service selector doesn't match pod labels
# Fix: align selector in Service with labels on pod template in Deployment

kubectl get pods -n default --show-labels
# Compare pod labels against service selector

kubectl get svc <service-name> -n default -o yaml | grep -A5 selector
# Shows what the service is selecting
```

## 3. Check ingress status

```bash
kubectl describe ingress <ingress-name> -n default
# Look for:
#   - Rejected events → F5 NGINX IC requires host: field (unlike community ingress-nginx)
#   - Empty backends () → endpoint issue (see step 2)
#   - Address field → ingress controller IP/hostname

kubectl get ingressclass
# Confirm the ingressClassName value to use in your Ingress spec
```

## 4. Check ingress controller

```bash
kubectl get svc -n nginx-ingress
# Shows NodePort or LoadBalancer and which ports to use

kubectl get pods -n nginx-ingress -o wide
# Shows which nodes the ingress pods are scheduled on

kubectl logs -n nginx-ingress deployment/nginx-ingress --tail=30
# 499 = client closed connection before backend responded (backend not reachable)
# 404 = no matching ingress rule (check host header and path)
```

## 5. Test connectivity layer by layer

```bash
# Test from ingress pod to backend pod on same node (bypasses VXLAN)
kubectl exec -n nginx-ingress <ingress-pod> -- curl http://<pod-ip>/<path>

# Test from ingress pod to backend pod on different node (uses VXLAN)
kubectl exec -n nginx-ingress <ingress-pod> -- curl http://<other-node-pod-ip>/<path>
# Hangs = cross-node networking broken (see step 7)

# Test service DNS from ingress pod (kube-proxy / ClusterIP path)
kubectl exec -n nginx-ingress <ingress-pod> -- curl http://<svc-name>.<namespace>.svc.cluster.local/<path>

# Test from curl DaemonSet (broad cluster connectivity check)
kubectl exec -n curl ds/curl -- curl http://<svc-name>.default.svc.cluster.local/<path>
```

## 6. Test ingress via NodePort

```bash
kubectl get nodes -o wide
# Get node internal IPs

kubectl get svc -n nginx-ingress
# Get NodePort number

# F5 NGINX IC requires Host header when host: is set in the Ingress rule
curl http://<node-ip>:<nodeport>/<path> -H "Host: myapp.local"
```

## 7. Diagnose cross-node networking (CNI)

```bash
kubectl get pods -n kube-system | grep -E "calico|flannel|cilium|weave"
# Identify CNI in use
# Many restarts = CNI instability

kubectl get ippool -o yaml | grep -E "ipipMode|vxlanMode"
# Calico: confirm encapsulation mode
# On AWS: vxlanMode: Always is required (BGP doesn't work without VPC config)

kubectl logs -n kube-system <calico-node-pod> --tail=30
# Look for errors related to VXLAN or BGP
```

## 8. Fix: AWS security group for Calico VXLAN

Calico VXLAN uses **UDP 4789** (not 8472 which is Flannel).
If the security group is missing this rule, cross-node pod traffic is silently dropped.

```bash
# Get security group ID
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=<worker-instance-name>" \
  --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" \
  --output text

# Add the missing rule
aws ec2 authorize-security-group-ingress \
  --group-id <sg-id> \
  --protocol udp \
  --port 4789 \
  --cidr 10.0.2.0/24
```

Or update the CloudFormation template and run:
```bash
aws cloudformation update-stack \
  --stack-name <stack-name> \
  --template-body file://fully-automated-cluster-template.yaml \
  --capabilities CAPABILITY_NAMED_IAM
```

## 9. Expose ingress via AWS NLB

### Set a static NodePort on the ingress controller
Dynamic NodePorts survive reboots but can change if the Service is deleted.
Lock it to a fixed value so the NLB target group always has the right port:

```bash
kubectl patch svc nginx-ingress -n nginx-ingress \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":30080}]'

kubectl get svc -n nginx-ingress
# confirm 80:30080/TCP
```

### CloudFormation target group - key settings
Point the NLB target group at the NodePort, not port 80:
```yaml
Port: 30080
HealthCheckPort: "30080"
Targets:
  - Id: !Ref WorkerInstance1
    Port: 30080
TargetGroupAttributes:
  - Key: preserve_client_ip.enabled
    Value: "false"   # NLB uses its own VPC IP as source → no SG changes needed
```

**Why `preserve_client_ip: false`:** NLB by default passes the real client IP to the
target. The worker SG only allows NodePort traffic from VpcCidr, so internet client IPs
are dropped. Disabling preservation makes the NLB use its own private IP (within VpcCidr),
which the existing SG rule already allows.

**Important:** changing `Port` on a target group is immutable - CloudFormation must
recreate it. Rename the target group (`Name:`) when changing the port to avoid the
`AlreadyExists` error during stack update.

### Ingress host field - F5 NGINX IC requirement
F5 NGINX IC (unlike community ingress-nginx) **requires** `host:` in every rule.
Set it to the NLB DNS name so curl sends it automatically as the Host header:

```yaml
spec:
  rules:
  - host: your-nlb-dns-name.amazonaws.com
    http:
      paths: ...
```

### Verify target health before testing
```bash
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --query "TargetGroups[?contains(TargetGroupName,'worker')].TargetGroupArn" \
    --output text) \
  --query "TargetHealthDescriptions[*].{ID:Target.Id,Port:Target.Port,Health:TargetHealth.State}" \
  --output table
# Both workers must show 'healthy' before NLB accepts connections
```

## Summary: symptom → cause mapping

| Symptom | Likely cause |
|---------|-------------|
| Readiness probe failed, connection refused | App port mismatch (containerPort ≠ listen port) |
| `bind: permission denied` in logs | App listening on port < 1024 as non-root |
| Service endpoints empty | Service selector ≠ pod labels |
| Ingress Rejected event | F5 NGINX IC requires `host:` field in rules |
| 404 from ingress | No matching host/path rule, or wrong `ingressClassName` |
| 499 from ingress | Backend unreachable (endpoint issue or network block) |
| ~50% requests timeout | One pod unhealthy + stale kube-proxy conntrack entries |
| Cross-node curl hangs | CNI VXLAN port blocked in AWS security group |
| NLB TCP connect timeout | Targets unhealthy, or SG blocks client IP (disable preserve_client_ip) |
| TG AlreadyExists on CF update | Port is immutable - rename the target group when changing it |
| F5 NGINX IC rejects ingress | `host:` field is required in every rule |
