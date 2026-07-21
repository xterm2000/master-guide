# AWS Infrastructure

Lab cluster infra via CloudFormation (VPC, EC2, NLB, Lambda scheduling), plus
scripts to start/stop it and inventory what's running. Topology: 1 Bastion
(public) + 1 Control Plane + 1 Worker (private), NLB on 80/443/6443.

| Topic | File |
|-------|------|
| CloudFormation templates (basic / automated / TLS variants) | `cluster-infrastracture/` |
| Cluster start/stop/status via Lambda | `cloudshell/cluster.sh` |
| AWS resource inventory | `cloudshell/services.sh` |
| Create/stop/start EC2 nodes directly via bash (no CloudFormation) | [`../k8s/k8s-cluster.md`](../k8s/k8s-cluster.md) |

## `cluster-infrastracture/` templates

- `basic-template.yml` / `basic-pods-services.yml` — minimal VPC + EC2 + NLB stack
- `automated-template.yaml` — adds Lambda-based scheduling
- `automated-template-for-tls.yaml` — adds HTTPS listener/target group for the TLS walkthrough in [`k8s/TLS-nginxF5-ingress/`](../k8s/TLS-nginxF5-ingress/)

**Gotcha:** a target group's `Port` is immutable in CloudFormation — changing a
NodePort requires renaming the resource's logical ID, or the update fails with
`AlreadyExists`.

## Scripts

```bash
./cloudshell/cluster.sh start | stop | status
./cloudshell/services.sh
```

- `cluster.sh` — Lambda function names default to `k8s-lab-startup`/`k8s-lab-shutdown`
  (override via `STARTUP_LAMBDA`/`SHUTDOWN_LAMBDA`), region defaults to `us-east-1`
  via `AWS_DEFAULT_REGION`.
- `services.sh` — has `us-east-1` hardcoded, not overridable via env var.

Note the directory is `aws/` (lowercase) and `cluster-infrastracture/` (typo preserved — matches the actual directory name on disk).
