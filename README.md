# DevOps Reference Guide

Infrastructure, Kubernetes, CI/CD, networking, and Linux operations — runbooks,
manifests, and configuration references. This is a map, not a summary: each
directory has its own `README.md` with the actual index; open the directory
you need.

## Directories

| Directory | Covers | README |
|-----------|--------|--------|
| `aws/` | CloudFormation lab infra, cluster lifecycle scripts | [`aws/README.md`](aws/README.md) |
| `k8s/` | Cluster setup, debugging, ingress/routing, TLS/PKI, observability, example manifests | [`k8s/README.md`](k8s/README.md) |
| `docker-cicd/` | Docker-based CI/CD home lab (Jenkins/Gitea/Nexus/Traefik/Pi-hole) | [`docker-cicd/README.md`](docker-cicd/README.md) |
| `network/` | DNS, iptables, general connectivity diagnostics | [`network/README.md`](network/README.md) |
| `linux/` | Sysadmin commands, text processing, shell, SSH, TLS/PKI reference, LVM/ACLs/etc. | [`linux/README.md`](linux/README.md) |
| `git/` | Git guide, merge strategies, local-dev workflow, config scopes | [`git/README.md`](git/README.md) |
| `ai-generic/` | Claude Code reference docs, Ollama setup | [`ai-generic/README.md`](ai-generic/README.md) |
| `scripts/` | Repo-maintenance tooling (link checker) | [`scripts/README.md`](scripts/README.md) |

## Cross-cutting notes

- **Lab topology:** AWS-hosted K8s cluster — 1 Bastion (public) + 1 Control Plane
  + 1 Worker (private), NLB on 80/443/6443. Infra in `aws/`, cluster ops in `k8s/`.
- **TLS:** cert-manager + Let's Encrypt DNS-01 via Route53 (HTTP-01 doesn't work
  with F5 NGINX IC). Full walkthrough in `k8s/README.md`.
- **`linux/ssh/`** holds SSH-specific config (keys, `~/.ssh/config`, node-connect
  script); `network/` holds general networking (DNS, iptables) — see
  `network/README.md` for why the split.
