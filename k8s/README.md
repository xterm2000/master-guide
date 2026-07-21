# Kubernetes

Manifests, runbooks, and debugging notes for the lab cluster (AWS-hosted, via
Kubespray — see [`../aws/`](../aws/) for the underlying infra). Learning/reference
implementation, not production.

## Cluster Setup & Lifecycle

| Topic | File |
|-------|------|
| Kubespray bootstrap on bastion via Podman | `kubespray-bastion-aws-ec2.md` |
| Create/stop/start EC2 nodes directly via bash | `k8s-cluster.md` |
| Add/remove worker nodes | `helper-scripts/scaling.sh` |
| Export full cluster state to YAML (`kubectl cluster-info dump`, log-stripping) | `kubernetes-dump-cluster.md` |
| Node cleanup manifest | `helper-scripts/node-cleanup.yaml` |
| Third-party YAML generators (bookmarks, not repo content) | `yaml-generators.md` |

## Debugging & Connectivity

| Topic | File |
|-------|------|
| Pod failures, taints, OOM, kubelet.conf | `helper-scripts/k8s-debugging.md` |
| Memory pressure diagnosis | `memory-pressure.md` |
| Inter-node connectivity probe | `helper-scripts/cluster-connectvity.sh` |
| API access via curl | `k8s-API.md` |
| In-cluster curl probing (pods/DaemonSet/`kcurl`) | `helper-scripts/curl-k8s.md` |
| kubectl aliases, autocomplete, `--dry-run` patterns | `kubectl-aliases.md`, `kubectl-autocomplete.md`, `kubectl-dry-run.md` |

## Ingress & Routing

| Topic | File |
|-------|------|
| F5 NGINX IC install checklist, path rewriting/redirects | `ingress/nginxf5/ingress-setup.md`, `ingress/ingress-routing.md` |
| Traefik v3 via Helm, 9-step troubleshooting checklist | `ingress/traefik/traefik-via-helm.md`, `troubleshooting-ingress.md` |
| Calico NetworkPolicy examples, Whisker UI debugging | `test-cluster/test-2/calico-policy.yaml`, `helper-scripts/whisker-debug.md` |

**Constraints worth knowing before you dig in:** every `VirtualServer` needs a
`host:` field or it's rejected; a `VirtualServer` owning a hostname blocks a
standard `Ingress` on it; F5 OSS has no `ExternalName` upstream support (needs
NGINX Plus); Calico VXLAN needs **UDP 4789** open between nodes or pod traffic
silently drops.

## TLS & PKI

cert-manager + Let's Encrypt DNS-01 via Route53 (HTTP-01 doesn't work with F5
NGINX IC). TLS terminates at the IC; pods get plain HTTP internally.

| Topic | File |
|-------|------|
| Full TLS walkthrough (cert-manager, DNS-01, CloudFormation HTTPS) | `TLS-nginxF5-ingress/openssl3-k8s-TLS-setup.md` |
| General-purpose OpenSSL/PKI reference (not k8s-specific) | [`../linux/tls-pki/`](../linux/tls-pki/) |

## Observability

Jaeger all-in-one in `monitor` namespace, exposed via F5 NGINX IC VirtualServer
— apply order and manifests in `tracing/`. `jaeger-proxy.yaml` (`ExternalName`)
is rejected by NGINX IC OSS; deploy Jaeger in the VirtualServer's own namespace
instead.

| Topic | File |
|-------|------|
| ElasticSearch backend issue notes | `tracing/jaeger-es-issue.md` |

## Example Manifests

- `test-cluster/test-1/` — VirtualServer/TLS/Deployments. `vs.yaml`/`vs-root.yaml`
  are the active VirtualServers; `ingress.yaml` is kept for reference only (see
  the Ingress constraint above).
- `test-cluster/test-2/` — multi-service routing, Calico Whisker, Headlamp,
  wildcard TLS. After standing up a fresh stack, update
  `hostedZoneID`/`accessKeyID`/email in `test-2/tls/cluster-issuer.yaml` and
  recreate the Route53 credentials secret before applying TLS manifests.
