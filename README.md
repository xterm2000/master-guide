# DevOps Reference Guide

Infrastructure, Kubernetes, CI/CD, networking, and Linux operations — runbooks, manifests, and configuration references. Files are self-descriptive; this index is a map, not a summary — open the file for detail.

---

## Contents

- [Infrastructure](#infrastructure)
- [Kubernetes](#kubernetes)
- [Ingress & Routing](#ingress--routing)
- [TLS & PKI](#tls--pki)
- [CI/CD](#cicd)
- [Observability](#observability)
- [Networking](#networking)
- [Linux, Shell & Git](#linux-shell--git)

---

## Infrastructure

AWS via CloudFormation (VPC, EC2, NLB, Lambda scheduling) or direct EC2 scripting. Topology: 1 Bastion (public) + 1 Control Plane + 1 Worker (private), NLB on 80/443/6443.

| Topic | File |
|-------|------|
| CloudFormation templates (basic / automated / TLS variants) | `aws/cluster-infrastracture/` |
| Cluster start/stop/status via Lambda, AWS resource inventory | `aws/cloudshell/cluster.sh`, `services.sh` |
| Create/stop/start EC2 nodes directly via bash | `k8s/k8s-cluster.md` |

`cluster.sh` defaults: Lambda names `k8s-lab-startup`/`k8s-lab-shutdown` (override via `STARTUP_LAMBDA`/`SHUTDOWN_LAMBDA`), region `us-east-1` via `AWS_DEFAULT_REGION`. `services.sh` has `us-east-1` hardcoded. Note the `aws/` directory is lowercase. CloudFormation target group `Port` is immutable — rename the resource's logical ID when changing a NodePort to avoid `AlreadyExists` errors.

---

## Kubernetes

| Topic | File |
|-------|------|
| Kubespray bootstrap on bastion via Podman | `k8s/kubespray-bastion-aws-ec2.md` |
| Add/remove worker nodes, export cluster to YAML | `k8s/helper-scripts/scaling.sh`, `k8s/kubernetes-dump-cluster.md` |
| Pod failures, taints, OOM, kubelet.conf, memory pressure | `k8s/helper-scripts/k8s-debugging.md`, `k8s/memory-pressure.md` |
| Inter-node connectivity probe, node cleanup, API access via curl, in-cluster curl probing (pods/Daemonset/`kcurl`) | `k8s/helper-scripts/cluster-connectvity.sh`, `node-cleanup.yaml`, `k8s/k8s-API.md`, `k8s/helper-scripts/curl-k8s.md` |
| kubectl aliases, autocomplete, `--dry-run` patterns | `k8s/kubectl-aliases.md`, `kubectl-autocomplete.md`, `kubectl-dry-run.md` |
| Example manifests: test-1 (VirtualServer/TLS/Deployments), test-2 (multi-service routing, Calico Whisker, Headlamp, wildcard TLS) | `k8s/test-cluster/test-1/`, `test-2/` |

In test-1, `vs.yaml`/`vs-root.yaml` are the active VirtualServers; `ingress.yaml` is kept for reference only (see Ingress constraint below). After standing up a fresh stack, update `hostedZoneID`/`accessKeyID`/email in `test-2/tls/cluster-issuer.yaml` and recreate the Route53 credentials secret before applying TLS manifests.

---

## Ingress & Routing

| Topic | File |
|-------|------|
| F5 NGINX IC install checklist, path rewriting/redirects | `k8s/ingress/nginxf5/ingress-setup.md`, `k8s/ingress/ingress-routing.md` |
| Traefik v3 via Helm, 9-step troubleshooting checklist | `k8s/ingress/traefik/traefik-via-helm.md`, `troubleshooting-ingress.md` |
| Calico NetworkPolicy examples, Whisker UI debugging | `k8s/test-cluster/test-2/calico-policy.yaml`, `k8s/helper-scripts/whisker-debug.md` |

**Constraints worth knowing before you dig in:** every `VirtualServer` needs a `host:` field or it's rejected; a `VirtualServer` owning a hostname blocks a standard `Ingress` on it; F5 OSS has no `ExternalName` upstream support (needs NGINX Plus); Calico VXLAN needs **UDP 4789** open between nodes or pod traffic silently drops.

---

## TLS & PKI

cert-manager + Let's Encrypt DNS-01 via Route53 (HTTP-01 doesn't work with F5 NGINX IC). TLS terminates at the IC; pods get plain HTTP internally.

| Topic | File |
|-------|------|
| Full TLS walkthrough (cert-manager, DNS-01, CloudFormation HTTPS) | `k8s/TLS-nginxF5-ingress/openssl3-k8s-TLS-setup.md` |
| PKI/OpenSSL reference, X.509 cert inspection | `linux/tls-pki/openssl-pki.md`, `ssl-server-key-checks.md` |

---

## CI/CD

Docker-based home-lab stack (Jenkins, Gitea, Nexus, Traefik, pgAdmin, Pi-hole) on a single VM: `Git push → Gitea webhook → Jenkins → Docker build → Nexus`. Traefik reads container metadata via a read-only `docker-socket-proxy`; Jenkins builds via Docker-in-Docker instead of mounting the host socket.

| Topic | File |
|-------|------|
| Full setup, pipeline wiring, troubleshooting | `docker-cicd/README.md` |
| Jenkins + Gitea + Nexus wiring, DNS options, socket-proxy vs DinD rationale | `docker-cicd/jenkins.md`, `localdns.md`, `docker-security.md` |

---

## Observability

Jaeger all-in-one in `monitor` namespace, exposed via F5 NGINX IC VirtualServer — apply order and manifests in `k8s/tracing/`. `jaeger-proxy.yaml` (ExternalName) is rejected by NGINX IC OSS; deploy Jaeger in the VirtualServer's own namespace instead.

| Topic | File |
|-------|------|
| ElasticSearch backend issue notes | `k8s/tracing/jaeger-es-issue.md` |

---

## Networking

| Topic | File |
|-------|------|
| SSH to private nodes (bastion ProxyJump), SSH config reference | `network/node-connect.md`, `network/ssh-config.md` |
| kubelet DNS failures, iptables reference + explainer, diagnostics | `network/kubelet-DNS-error.md`, `network/iptab*`, `network/net-check.md`, `network/network.md` |
| Passwordless SSH distribution, mass reboot script, node IP map | `linux/ssh/passwordless-login.md`, `reboot-machines.md`, `nodes.env` |

---

## Linux, Shell & Git

`linux/` is grouped by category — directory name tells you the topic.

| Directory | Contents |
|-----------|----------|
| `linux/linux-commands.md` | general sysadmin command reference (catch-all, kept at root) |
| `linux/text-processing/` | grep (+ regex/BRE/ERE/PCRE ref, k8s patterns), sed, awk, tr, curl (`curl-text-logs.md`), yq/jq/bat, ANSI color codes + piping rationale (`tty-colors.md`), real-world combined-pipeline cookbook (`text-process-cookbook.md`) |
| `linux/shell/` | aliases, arrays, heredocs, process substitution, bash loops cookbook, prompt, vim |
| `linux/ssh/` | passwordless login, mass reboot, node IP map, Windows key perms |
| `linux/tls-pki/` | OpenSSL/PKI reference, X.509 inspection |
| `linux/sysadmin/` | LVM/storage concepts + disk resize, ACLs, WSL setup, user/group administration, firewalld, cron/at, boot process & systemd, SELinux, install reference for tools used across this repo (`installations.md`) |
| `linux/version-control/` | SVN → Git comparison |
| `git/` | git guide, merging strategies, local-dev workflow, personal `.gitconfig`, global vs local config scopes (`git-config-scopes.md`) |
