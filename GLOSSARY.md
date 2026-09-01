# Glossary

Initialisms and jargon used across this repo, each pointing to the doc that
actually explains it. This is a lookup aid, not a teaching doc — follow the
link for the real explanation.

SSH has its own deeper glossary: [`linux/ssh/GLOSSARY.md`](linux/ssh/GLOSSARY.md).

---

## TLS / PKI / X.509

| Term | Meaning | See |
|------|---------|-----|
| **PKI** | Public Key Infrastructure — the CA hierarchy, certs, and trust stores that let parties verify each other's identity. | [`linux/tls-pki/openssl-pki.md`](linux/tls-pki/openssl-pki.md) §1 |
| **CA** | Certificate Authority — an entity whose key signs other certs. A **Root CA** is self-signed and kept offline; an **Intermediate CA** does day-to-day signing and can be revoked without touching the root. | [`linux/tls-pki/openssl-pki.md`](linux/tls-pki/openssl-pki.md) §1 |
| **leaf / end-entity cert** | The cert at the bottom of the chain — for an actual server or client, not allowed to sign others. | [`linux/tls-pki/openssl-pki.md`](linux/tls-pki/openssl-pki.md) §1 |
| **chain of trust** | Root → Intermediate → leaf; a verifier trusts the leaf because it trusts the root that (transitively) signed it. | [`linux/tls-pki/openssl-pki.md`](linux/tls-pki/openssl-pki.md) §1 |
| **CSR** | Certificate Signing Request — a public key + identity details, sent to a CA to be signed into a cert. | [`linux/tls-pki/openssl-pki.md`](linux/tls-pki/openssl-pki.md) §1 |
| **self-signed cert** | A cert signed by its own key — fine for personal/internal use, but every verifier must import it manually. | [`linux/tls-pki/openssl-pki.md`](linux/tls-pki/openssl-pki.md) §1 |
| **CRL** | Certificate Revocation List — a CA-published list of certs pulled before expiry (SSH's equivalent is a KRL). | [`linux/tls-pki/openssl-pki.md`](linux/tls-pki/openssl-pki.md) §13 |
| **mTLS** | Mutual TLS — both ends present a cert, so the server authenticates the client too. | [`linux/tls-pki/openssl-pki.md`](linux/tls-pki/openssl-pki.md) §12 |
| **SAN** | Subject Alternative Name — the cert field listing the hostnames/IPs it's actually valid for (the CN is legacy). | [`linux/tls-pki/ssl-server-key-checks.md`](linux/tls-pki/ssl-server-key-checks.md) §6 |
| **key usage / extended key usage** | Cert extensions that constrain what a key may do (`keyCertSign`, `digitalSignature`, `serverAuth`, …). | [`linux/tls-pki/openssl-pki.md`](linux/tls-pki/openssl-pki.md) §6 |
| **PEM / DER** | Cert/key encodings — PEM is Base64 text with `-----BEGIN …-----` headers; DER is the raw binary. | [`linux/tls-pki/openssl-pki.md`](linux/tls-pki/openssl-pki.md) §1 |
| **PKCS#12** (`.p12` / `.pfx`) | A binary bundle of cert + private key + optional chain, e.g. for import into Windows/browsers. | [`linux/tls-pki/openssl-pki.md`](linux/tls-pki/openssl-pki.md) §1 |
| **PKCS#7** (`.p7b`) | A cert-chain bundle with no private key. | [`linux/tls-pki/openssl-pki.md`](linux/tls-pki/openssl-pki.md) §1 |
| **RSA / EC / EdDSA / Ed25519 / Curve25519** | Asymmetric algorithms. Ed25519 (sign/verify) and Curve25519 / X25519 (key agreement) are the modern ECC default pair. | [`linux/tls-pki/openssl-pki.md`](linux/tls-pki/openssl-pki.md) §2 |

## Certificate automation (Kubernetes)

| Term | Meaning | See |
|------|---------|-----|
| **ACME** | The protocol Let's Encrypt uses to issue certs automatically after a domain-control challenge. | [`k8s/TLS-nginxF5-ingress/openssl3-k8s-TLS-setup.md`](k8s/TLS-nginxF5-ingress/openssl3-k8s-TLS-setup.md) |
| **DNS-01 / HTTP-01** | ACME challenge types — DNS-01 proves control via a TXT record (works for wildcards, no HTTP routing); HTTP-01 serves a token over HTTP. | [`k8s/TLS-nginxF5-ingress/openssl3-k8s-TLS-setup.md`](k8s/TLS-nginxF5-ingress/openssl3-k8s-TLS-setup.md) |
| **cert-manager** | The Kubernetes controller that requests, renews, and stores ACME certs as Secrets. | [`k8s/README.md`](k8s/README.md) |

## GPG / OpenPGP

| Term | Meaning | See |
|------|---------|-----|
| **web of trust** | GPG's decentralised trust model — validity comes from certifications made by keys you already trust, not from a CA hierarchy. | [`linux/gpg/gpg-guide.md`](linux/gpg/gpg-guide.md) §2a |
| **certify-only primary + subkeys** | A production identity pattern: the primary key only certifies (kept offline); separate sign / encrypt / auth subkeys do daily work and rotate independently. | [`linux/gpg/gpg-guide.md`](linux/gpg/gpg-guide.md) §2 |
| **revocation certificate** | A pre-made "this key is dead" statement, generated at key creation and stored *separately* — the only way to revoke if the private key is lost. | [`linux/gpg/gpg-guide.md`](linux/gpg/gpg-guide.md) §2 |
| **clearsign / detached signature** | Clearsign wraps a readable message in an inline signature block; a detached signature is a separate `.sig` file leaving the original byte-identical. | [`linux/gpg/gpg-guide.md`](linux/gpg/gpg-guide.md) §5 |
| **pinentry** | The passphrase-prompt helper `gpg-agent` invokes. On headless hosts install `pinentry-tty`, or bypass it with loopback mode. | [`linux/gpg/gpg-guide.md`](linux/gpg/gpg-guide.md) §8 |
| **loopback pinentry** | `--pinentry-mode loopback` — take the passphrase from `--passphrase*` instead of a dialog; required for batch/CI use. | [`linux/gpg/gpg-guide.md`](linux/gpg/gpg-guide.md) §7 |

## Kubernetes / lab infrastructure

| Term | Meaning | See |
|------|---------|-----|
| **the lab / lab cluster** | This repo's reference cluster: AWS-hosted, 1 public Bastion + 1 Control Plane + 1 Worker (private), NLB on 80/443/6443. | [`README.md`](README.md), [`k8s/README.md`](k8s/README.md) |
| **bastion** | A public jump host that fronts otherwise-private nodes; you SSH through it to reach the control plane and workers. | [`k8s/kubespray-bastion-aws-ec2.md`](k8s/kubespray-bastion-aws-ec2.md) |
| **kubespray** | The Ansible-based Kubernetes installer used to build the lab cluster. | [`k8s/kubespray-bastion-aws-ec2.md`](k8s/kubespray-bastion-aws-ec2.md) |
| **NLB** | Network Load Balancer — the AWS L4 load balancer fronting the cluster's 80/443/6443. | [`aws/README.md`](aws/README.md) |
| **Ingress / Ingress Controller (IC)** | The Kubernetes object mapping external hostnames/paths to Services, and the proxy (F5 NGINX IC, Traefik) that implements it. | [`k8s/README.md`](k8s/README.md), [`k8s/ingress/ingress-routing.md`](k8s/ingress/ingress-routing.md) |
| **VirtualServer** | F5 NGINX IC's CRD alternative to a plain `Ingress`; needs a `host:` field and takes exclusive ownership of that hostname. | [`k8s/README.md`](k8s/README.md), [`k8s/ingress/nginxf5/ingress-setup.md`](k8s/ingress/nginxf5/ingress-setup.md) |
| **NodePort** | A Service type that exposes a port in the `30000-32767` range on every node. | [`k8s/README.md`](k8s/README.md), [`linux/sysadmin/firewalld.md`](linux/sysadmin/firewalld.md) |
| **NetworkPolicy** | Pod-level firewall rules; enforced here by Calico. | [`k8s/README.md`](k8s/README.md) |
| **VXLAN / UDP 4789** | Calico's overlay encapsulation — UDP 4789 must be open between nodes or pod traffic silently drops. | [`k8s/README.md`](k8s/README.md) |

## Networking

| Term | Meaning | See |
|------|---------|-----|
| **NAT** | Network Address Translation — rewriting source/destination addresses at a boundary, e.g. a home router sharing one public IP. | [`network/net-check.md`](network/net-check.md) |
| **CGNAT** | Carrier-Grade NAT — the ISP itself NATs you, so you have no real public IP and nothing inbound works. | [`linux/ssh/dynamic-ip-access.md`](linux/ssh/dynamic-ip-access.md) |
| **DDNS** | Dynamic DNS — a hostname kept pointed at a changing public IP by an updater. | [`linux/ssh/dynamic-ip-access.md`](linux/ssh/dynamic-ip-access.md) |
| **DPI** | Deep Packet Inspection — filtering by protocol signature rather than port; can block SSH regardless of which port it's on. | [`linux/ssh/restricted-networks.md`](linux/ssh/restricted-networks.md) |
| **DNS TTL** | How long resolvers cache a record; keep it low (60–300 s) for a record that tracks a moving IP. | [`linux/ssh/dynamic-ip-access.md`](linux/ssh/dynamic-ip-access.md) |

## Linux / systemd / RHEL

| Term | Meaning | See |
|------|---------|-----|
| **drop-in file** | A config fragment in a `*.d/` directory (`sshd_config.d/`, `cron.d/`, systemd unit `.d/`) merged into a base config instead of editing it directly. | [`linux/sysadmin/scheduling.md`](linux/sysadmin/scheduling.md), [`linux/ssh/passwordless-login.md`](linux/ssh/passwordless-login.md) §5 |
| **systemd timer** | A `.timer` unit that triggers a `.service` on a schedule — a cron alternative with better logging (`journalctl -u`). | [`linux/sysadmin/scheduling.md`](linux/sysadmin/scheduling.md) |
| **firewalld zone** | A named trust level (`public`, `trusted`, `drop`, …) bound to interfaces/sources, each with its own allowed services/ports. | [`linux/sysadmin/firewalld.md`](linux/sysadmin/firewalld.md) |
| **rich rule** | A firewalld rule that matches on source address, logs, or rejects/drops — more granular than a plain service/port entry. | [`linux/sysadmin/firewalld.md`](linux/sysadmin/firewalld.md) |
| **masquerade** | Source-NAT on a firewalld zone — rewrites outgoing packets' source to the host's address (needed for routing/forwarding). | [`linux/sysadmin/firewalld.md`](linux/sysadmin/firewalld.md) |
| **runtime vs permanent** | firewalld holds two rule sets — `--permanent` changes need `--reload` to take effect; runtime changes are lost on reload. | [`linux/sysadmin/firewalld.md`](linux/sysadmin/firewalld.md) |
| **SELinux context** | The `user:role:type:level` label on every file/process; access is decided by policy on the *type*, e.g. `httpd_sys_content_t`. | [`linux/sysadmin/selinux.md`](linux/sysadmin/selinux.md) |
| **`restorecon` vs `chcon`** | `restorecon` resets a file's context to what policy says it should be; `chcon` sets it manually (lost on relabel). | [`linux/sysadmin/selinux.md`](linux/sysadmin/selinux.md) |
| **ACL** | POSIX Access Control Lists — per-user/group permissions beyond the owner/group/other bits (`getfacl` / `setfacl`). | [`linux/sysadmin/acls.md`](linux/sysadmin/acls.md) |
| **LVM** | Logical Volume Manager — the PV → VG → LV abstraction that lets you resize/span filesystems across disks. | [`linux/sysadmin/lvm-storage.md`](linux/sysadmin/lvm-storage.md) |

## Git

| Term | Meaning | See |
|------|---------|-----|
| **fast-forward / diverged / orphaned** | Branch states — FF: target is strictly ahead; diverged: both sides have unique commits; orphaned: no shared history. | [`git/git-guide.md`](git/git-guide.md) §5 |
| **reflog** | Git's local log of where `HEAD` and branches have pointed — the safety net for recovering after a bad reset/rebase. | [`git/git-guide.md`](git/git-guide.md) §2 |
| **`filter-repo`** | The tool for rewriting entire history (remove a file/folder from every commit, rewrite author emails). | [`git/git-guide.md`](git/git-guide.md) §2 |
| **config scopes** | `--system` / `--global` / `--local` / `--worktree` — where a git setting is stored and which overrides which. | [`git/git-config-scopes.md`](git/git-config-scopes.md) |

---

## See Also

- [`linux/ssh/GLOSSARY.md`](linux/ssh/GLOSSARY.md) — deeper SSH-specific vocabulary
- [`README.md`](README.md) — top-level directory map
