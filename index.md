# Index — Every Document in This Repo

The file-level index. [`README.md`](README.md) is the directory map and stays the
source of truth for *structure*; each directory's own `README.md` carries the
architecture notes and gotchas. This page is the flat catalogue: every `.md` in
the repo, one line each, so you can find a topic without knowing which directory
it landed in.

Non-`.md` assets (CloudFormation templates, k8s manifests, compose files, shell
scripts) are summarised per directory rather than listed file-by-file — open the
directory's `README.md` for those.

- Repo-wide vocabulary: [`GLOSSARY.md`](GLOSSARY.md) · SSH's deeper one: [`linux/ssh/GLOSSARY.md`](linux/ssh/GLOSSARY.md)
- Working in this repo with Claude Code: [`CLAUDE.md`](CLAUDE.md)

---

## Root

| File | What it covers |
|---|---|
| [`README.md`](README.md) | Top-level directory map, lab topology, TLS summary |
| [`GLOSSARY.md`](GLOSSARY.md) | Initialisms and jargon used repo-wide, each linked to the doc that explains it |
| [`index.md`](index.md) | This page |
| [`CLAUDE.md`](CLAUDE.md) | How to work in this repo with Claude Code (scope discipline, doc style) |

## `aws/` — lab infrastructure

| File | What it covers |
|---|---|
| [`aws/README.md`](aws/README.md) | CloudFormation lab infra, cluster lifecycle scripts, stack parameters |

Also here: `cluster-infrastracture/*.yaml` (CloudFormation templates, with and
without TLS), `cloudshell/cluster.sh` + `services.sh` (lifecycle helpers).

## `k8s/` — cluster setup, debugging, ingress, TLS, observability

| File | What it covers |
|---|---|
| [`k8s/README.md`](k8s/README.md) | Cluster index, architecture notes, immutable-field / silent-failure gotchas |
| [`k8s/kubespray-bastion-aws-ec2.md`](k8s/kubespray-bastion-aws-ec2.md) | Full cluster build: bastion, Kubespray, NAT gateway, HAProxy, AWS-specific steps |
| [`k8s/k8s-cluster.md`](k8s/k8s-cluster.md) | `k8s-cluster.sh` — bare-metal-sim cluster on AWS |
| [`k8s/k8s-API.md`](k8s/k8s-API.md) | Talking to the API server directly: service accounts, extracting certs, raw `curl` |
| [`k8s/memory-pressure.md`](k8s/memory-pressure.md) | Memory-pressure runbook — eviction thresholds, diagnosis, remediation |
| [`k8s/kubectl-aliases.md`](k8s/kubectl-aliases.md) | `kubectl` alias set |
| [`k8s/kubectl-autocomplete.md`](k8s/kubectl-autocomplete.md) | bash-completion setup for `kubectl` |
| [`k8s/kubectl-dry-run.md`](k8s/kubectl-dry-run.md) | Generating and previewing manifests with `--dry-run=client -o yaml` |
| [`k8s/kubernetes-dump-cluster.md`](k8s/kubernetes-dump-cluster.md) | `cluster-info dump` with the log noise stripped |
| [`k8s/yaml-generators.md`](k8s/yaml-generators.md) | Online manifest generators worth knowing |
| [`k8s/ingress/ingress-routing.md`](k8s/ingress/ingress-routing.md) | Ingress routing strategy — path vs host, controller choice |
| [`k8s/ingress/nginxf5/ingress-setup.md`](k8s/ingress/nginxf5/ingress-setup.md) | F5 NGINX Ingress Controller setup checklist |
| [`k8s/ingress/traefik/traefik-via-helm.md`](k8s/ingress/traefik/traefik-via-helm.md) | Traefik on bare-metal Kubernetes via Helm |
| [`k8s/ingress/traefik/troubleshooting-ingress.md`](k8s/ingress/traefik/troubleshooting-ingress.md) | Ingress troubleshooting — routing, TLS, backend reachability |
| [`k8s/TLS-nginxF5-ingress/openssl3-k8s-TLS-setup.md`](k8s/TLS-nginxF5-ingress/openssl3-k8s-TLS-setup.md) | End-to-end cluster TLS with OpenSSL 3 + cert-manager (the k8s-specific companion to `linux/tls-pki/`) |
| [`k8s/tracing/jaeger-es-issue.md`](k8s/tracing/jaeger-es-issue.md) | Jaeger + Elasticsearch debugging runbook |
| [`k8s/helper-scripts/curl-k8s.md`](k8s/helper-scripts/curl-k8s.md) | In-cluster probing with `curl` from a throwaway pod |
| [`k8s/helper-scripts/k8s-debugging.md`](k8s/helper-scripts/k8s-debugging.md) | Debug one-liners — failed pods, stripping manifests down to essentials |
| [`k8s/helper-scripts/whisker-debug.md`](k8s/helper-scripts/whisker-debug.md) | Calico Whisker dashboard debugging |

Also here: `test-cluster/test-1/`, `test-cluster/test-2/` (example manifests —
deployments, services, VirtualServers, cert-manager issuers, Calico policy),
`tracing/*.yaml` (Jaeger stack), `helper-scripts/*.sh`.

## `docker-cicd/` — Docker CI/CD home lab

| File | What it covers |
|---|---|
| [`docker-cicd/README.md`](docker-cicd/README.md) | Stack overview — Jenkins, Gitea, Nexus, Traefik, Pi-hole, Postgres |
| [`docker-cicd/jenkins.md`](docker-cicd/jenkins.md) | Jenkins + Gitea CI/CD setup |
| [`docker-cicd/docker-security.md`](docker-cicd/docker-security.md) | Hardening the home-lab Docker host |
| [`docker-cicd/localdns.md`](docker-cicd/localdns.md) | Local DNS for the lab (Pi-hole), config-file approach that survives restarts |

Also here: `docker-compose.yaml`, `jenkins/Dockerfile`, `pg-init-scripts/*.sql`,
`pihole/docker-compose.yaml`, `homepage/index.html`, `data-dirs.sh`.

## `network/` — networking concepts and diagnostics

| File | What it covers |
|---|---|
| [`network/README.md`](network/README.md) | Networking index and the `network/` vs `linux/ssh/` split |
| [`network/networking-guide.md`](network/networking-guide.md) | The mental model: layer ladder, CIDR/subnets, routing, NAT, DNS, DHCP, MTU; planning home/corporate/cloud; security; a bottom-up diagnostic method |
| [`network/net-tools.md`](network/net-tools.md) | Tool reference + dispatch table — `ip`, `ss`, `dig`, `nc`, `nmap`, `openssl s_client`, `tracepath`, `nstat`, `ethtool`, `nmcli`, with diagnostic recipes |
| [`network/net-check.md`](network/net-check.md) | `verify-nat-setup.sh` — NAT / IP-forwarding checks for the lab |
| [`network/iptab.md`](network/iptab.md) | iptables reference (paired with `iptab-explain.sh`) |
| [`network/kubelet-DNS-error.md`](network/kubelet-DNS-error.md) | kubelet DNS failures — CoreDNS, `resolv.conf` search-line limits |
| [`network/network.md`](network/network.md) | Short notes — port scanning, listening sockets |

## `linux/` — sysadmin, shell, text processing, SSH, TLS

| File | What it covers |
|---|---|
| [`linux/README.md`](linux/README.md) | Linux index by category |
| [`linux/linux-commands.md`](linux/linux-commands.md) | General sysadmin command reference (the catch-all) |
| [`linux/archiving.md`](linux/archiving.md) | `tar`, `gzip`/`xz`/`zstd`, `zip` — format choice, tuning, metadata, streaming/split, integrity |

### `linux/text-processing/`

| File | What it covers |
|---|---|
| [`grep.md`](linux/text-processing/grep.md) | `grep` reference |
| [`grep-regex-ref.md`](linux/text-processing/grep-regex-ref.md) | BRE vs ERE vs PCRE, and the gotchas between them |
| [`grep-regex-k8s.md`](linux/text-processing/grep-regex-k8s.md) | Regex patterns for Kubernetes output |
| [`sed.md`](linux/text-processing/sed.md) | `sed` — stream editing |
| [`awk.md`](linux/text-processing/awk.md) | `awk` — field/record processing |
| [`small-tools.md`](linux/text-processing/small-tools.md) | `cut`/`rev`/`paste`/`column`/`comm`/`join`/`sort`/`uniq`/`tr`/`xargs`/`diff`/`xxd`/`iconv`/`split` etc. — dispatch table + recipes |
| [`text-process-cookbook.md`](linux/text-processing/text-process-cookbook.md) | Real-world combined pipelines |
| [`curl-text-logs.md`](linux/text-processing/curl-text-logs.md) | `curl` — APIs, headers, auth, `-w` timing, k8s recipes |
| [`wget.md`](linux/text-processing/wget.md) | `wget` — unattended downloads, resume/retry, mirroring, batch lists, wget vs curl |
| [`jq-detailed.md`](linux/text-processing/jq-detailed.md) | `jq` reference |
| [`yq-jq-bat.md`](linux/text-processing/yq-jq-bat.md) | `yq` / `jq` / `bat` / `icdiff` — install and use |
| [`ripgrep-example.md`](linux/text-processing/ripgrep-example.md) | A ripgrep glob command taken apart piece by piece |
| [`ripgrep-glob-and-sort.md`](linux/text-processing/ripgrep-glob-and-sort.md) | Glob precedence, anchoring, and sort performance |
| [`tty-colors.md`](linux/text-processing/tty-colors.md) | ANSI escapes, and why colour dies in a pipe |

### `linux/shell/`

| File | What it covers |
|---|---|
| [`arrays.md`](linux/shell/arrays.md) | Bash arrays, indexed and associative |
| [`bash-loops-cookbook.md`](linux/shell/bash-loops-cookbook.md) | Loop patterns |
| [`bash-history-expansion.md`](linux/shell/bash-history-expansion.md) | `!!`/`!$` history expansion, `compgen -v` introspection |
| [`heredocs.md`](linux/shell/heredocs.md) | Heredocs and here-strings |
| [`process-substitution.md`](linux/shell/process-substitution.md) | `<(...)` vs `$(...)` vs a pipe |
| [`linux-aliases.md`](linux/shell/linux-aliases.md) | Alias definitions worth keeping |
| [`hosts.md`](linux/shell/hosts.md) | Looping over a `hosts.txt` |
| [`vim-guide.md`](linux/shell/vim-guide.md) | Vim navigation and editing |

Also here: `prompt.sh`, `prompt-aurora.sh`, `example-vimrc.txt`, `vimrc-example-2.txt`.

### `linux/ssh/`

| File | What it covers |
|---|---|
| [`GLOSSARY.md`](linux/ssh/GLOSSARY.md) | SSH vocabulary — keys, CA, forwarding, agent |
| [`passwordless-login.md`](linux/ssh/passwordless-login.md) | Single-host passwordless login from scratch, plus server hardening |
| [`ssh-key-distribution.md`](linux/ssh/ssh-key-distribution.md) | Key generation and distribution across hosts |
| [`ssh-agent.md`](linux/ssh/ssh-agent.md) | `ssh-agent` / `ssh-add` — signing model, lifetimes, agent forwarding vs `ProxyJump` |
| [`ssh-ca.md`](linux/ssh/ssh-ca.md) | SSH certificate authority — signing, KRL revocation, CA-key protection, host-key lifecycle |
| [`ssh-config.md`](linux/ssh/ssh-config.md) | `~/.ssh/config` parameters |
| [`port-forwarding.md`](linux/ssh/port-forwarding.md) | Local/remote/dynamic forwarding and service tunnelling |
| [`dynamic-ip-access.md`](linux/ssh/dynamic-ip-access.md) | Reaching a host whose public IP changes — DDNS, mesh VPN, CGNAT |
| [`restricted-networks.md`](linux/ssh/restricted-networks.md) | Getting out through a network that blocks or intercepts SSH |
| [`ssh-scanning-triage.md`](linux/ssh/ssh-scanning-triage.md) | Is an exposed host being scanned / brute-forced? |
| [`passwordless-sudo.md`](linux/ssh/passwordless-sudo.md) | `sudoers` drop-in for unattended commands |
| [`node-connect.md`](linux/ssh/node-connect.md) | `nodes.env` node-IP map + connect script |
| [`reboot-machines.md`](linux/ssh/reboot-machines.md) | Role-keyed mass reboot across the lab nodes |
| [`windows-key-permissions.md`](linux/ssh/windows-key-permissions.md) | Fixing key ACLs on Windows |

Also here: `nodes.env`, `report.sh` (SSH posture report).

### `linux/tls-pki/`

| File | What it covers |
|---|---|
| [`cert-formats.md`](linux/tls-pki/cert-formats.md) | PEM/DER/X.509/ASN.1 layering, the PKCS zoo, identify/convert recipes, why TLS ≠ SSH keys |
| [`openssl-pki.md`](linux/tls-pki/openssl-pki.md) | Building a CA hierarchy with OpenSSL |
| [`ssl-server-key-checks.md`](linux/tls-pki/ssl-server-key-checks.md) | Inspecting certs, matching key ↔ cert, checking a served chain |

### `linux/gpg/`

| File | What it covers |
|---|---|
| [`gpg-guide.md`](linux/gpg/gpg-guide.md) | GnuPG — key creation, sign/verify, encrypt/decrypt, batch mode, pinentry troubleshooting |
| [`gpg-commands.md`](linux/gpg/gpg-commands.md) | GPG command quick reference |

Also here: `gpg-func.sh`, `gpg-keys.sh`, `openssl.conf`.

### `linux/sysadmin/`

| File | What it covers |
|---|---|
| [`installations.md`](linux/sysadmin/installations.md) | Install reference for the tools used across this repo |
| [`users-groups.md`](linux/sysadmin/users-groups.md) | User and group administration |
| [`acls.md`](linux/sysadmin/acls.md) | POSIX ACLs beyond `chmod` |
| [`lvm-storage.md`](linux/sysadmin/lvm-storage.md) | Storage and LVM concepts |
| [`RL-disk-resize.md`](linux/sysadmin/RL-disk-resize.md) | Growing a Rocky Linux VM disk (VMware, LVM + XFS) |
| [`firewalld.md`](linux/sysadmin/firewalld.md) | firewalld — zones, services, rich rules, direct rules |
| [`selinux.md`](linux/sysadmin/selinux.md) | SELinux contexts, booleans, denials |
| [`boot-systemd.md`](linux/sysadmin/boot-systemd.md) | Boot process, systemd units and services |
| [`scheduling.md`](linux/sysadmin/scheduling.md) | `cron`, `at`, systemd timers |
| [`sdkman-setup.md`](linux/sysadmin/sdkman-setup.md) | System-wide shared SDKMAN install |
| [`wsl-setup.md`](linux/sysadmin/wsl-setup.md) | WSL setup on Windows |

## `git/`

| File | What it covers |
|---|---|
| [`git/README.md`](git/README.md) | Git index |
| [`git/git-guide.md`](git/git-guide.md) | The main git guide |
| [`git/git-merging.md`](git/git-merging.md) | Merge strategies, worked on the `git-training` repo |
| [`git/git-config-scopes.md`](git/git-config-scopes.md) | Global vs local config precedence |
| [`git/git-local-dev.md`](git/git-local-dev.md) | Gitea local setup and tracking workflow |
| [`git/git-append.md`](git/git-append.md) | Actually purging unreachable objects (not just unreferencing them) |
| [`git/svn-git-comparison.md`](git/svn-git-comparison.md) | SVN ↔ Git mental model, for TortoiseSVN users |

## `oracle/` — Oracle DB reference

| File | What it covers |
|---|---|
| [`oracle/db-locks-playbook.md`](oracle/db-locks-playbook.md) | Lock-contention triage playbook — blocking chains, `enq TX`/`TM`, remediation |
| [`oracle/check db lock.md`](<oracle/check db lock.md>) | Lock-check queries |
| [`oracle/dba queries.md`](<oracle/dba queries.md>) | Everyday DBA queries |
| [`oracle/db trace.md`](<oracle/db trace.md>) | Enabling and reading session traces |
| [`oracle/dbms_scheduler jobs.md`](<oracle/dbms_scheduler jobs.md>) | Running work as `DBMS_SCHEDULER` jobs |
| [`oracle/running sql by user.md`](<oracle/running sql by user.md>) | What a given user is running right now |
| [`oracle/collections.md`](oracle/collections.md) | PL/SQL collections reference |
| [`oracle/cursors.md`](oracle/cursors.md) | PL/SQL cursors |

Also here: `space/*.sql` (segment / space-usage queries), `mysql-short.sh`.

## `powershell/`

| File | What it covers |
|---|---|
| [`powershell/commands.md`](powershell/commands.md) | PowerShell commands ↔ aliases ↔ bash equivalents |

Also here: `ripgrep.ps1`.

## `ai-generic/` — AI tooling

| File | What it covers |
|---|---|
| [`ai-generic/README.md`](ai-generic/README.md) | AI tooling index |
| [`ai-generic/claude/AI-docs/00-index.md`](ai-generic/claude/AI-docs/00-index.md) | Index of the Claude Code reference set |
| [`ai-generic/claude/AI-docs/01-claude-skills-reference.md`](ai-generic/claude/AI-docs/01-claude-skills-reference.md) | Skills and `AGENTS.md` reference |
| [`ai-generic/claude/AI-docs/02-agents-md-reference.md`](ai-generic/claude/AI-docs/02-agents-md-reference.md) | `AGENTS.md` reference |
| [`ai-generic/claude/AI-docs/03-claude-code-tools-reference.md`](ai-generic/claude/AI-docs/03-claude-code-tools-reference.md) | Built-in tools reference |
| [`ai-generic/claude/AI-docs/04-settings-json.md`](ai-generic/claude/AI-docs/04-settings-json.md) | `settings.json` complete reference |
| [`ai-generic/claude/AI-docs/05-mcp-servers.md`](ai-generic/claude/AI-docs/05-mcp-servers.md) | MCP servers — connecting Claude Code to external tools |
| [`ai-generic/claude/AI-docs/claude-skills/database/SKILL_db.md`](ai-generic/claude/AI-docs/claude-skills/database/SKILL_db.md) | Example skill definition (Oracle DB expertise) |
| [`ai-generic/ollama/linux-install.md`](ai-generic/ollama/linux-install.md) | Ollama on Linux — install and docs index |

Also here: `claude/statusline.py`, `ollama/quick-remove.sh`.

## `scripts/` — repo maintenance

| File | What it covers |
|---|---|
| [`scripts/README.md`](scripts/README.md) | Maintenance tooling index |
| `scripts/check-links.py` | Checks markdown links and repo-rooted backtick paths across all `.md` files; exits 1 on a broken reference |
