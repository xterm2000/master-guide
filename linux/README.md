# Linux, Shell & Sysadmin

Grouped by category — directory name tells you the topic. Files are
self-descriptive; open the file for detail.

| Directory | Contents |
|-----------|----------|
| `linux-commands.md` | General sysadmin command reference (catch-all, kept at this root) |
| `archiving.md` | Archiving & compression — `tar`, `gzip`/`xz`/`zstd`, `zip`/`unzip`: format choice, tuning, metadata preservation, streaming/split, integrity checks, gotchas |
| `text-processing/` | grep (+ regex/BRE/ERE/PCRE ref, k8s patterns), sed, awk, curl (`curl-text-logs.md`), wget — downloads/mirroring/batch + wget-vs-curl (`wget.md`), yq/jq/bat, ANSI color codes + piping rationale (`tty-colors.md`), real-world combined-pipeline cookbook (`text-process-cookbook.md`), ripgrep glob syntax (`ripgrep-example.md`) and glob precedence/anchoring/sort performance (`ripgrep-glob-and-sort.md`), small text-utility reference + recipes — `cut`/`rev`/`paste`/`column`/`comm`/`join`/`sort`/`uniq`/`tr`/`xargs`/`diff`/`xxd`/`iconv`/`split` etc., with a "which tool do I need" dispatch table (`small-tools.md`) |
| `shell/` | aliases, arrays, heredocs, process substitution, bash loops cookbook, prompt, vim, history expansion + `compgen -v` introspection (`bash-history-expansion.md`), controlling what history saves — `HISTCONTROL`/`HISTIGNORE`/`histappend`, pruning, curated snippet file (`bash-history-config.md`) |
| `ssh/` | single-host passwordless login (`passwordless-login.md`), the SSH agent + `ssh-add` — passphrase caching, lifetimes, agent forwarding vs `ProxyJump` (`ssh-agent.md`), key generation/distribution, SSH certificate authority (`ssh-keygen -s`, KRL revocation, CA-key protection, host-key lifecycle — `ssh-ca.md`), port forwarding / service tunnelling (`port-forwarding.md`), reaching a host with a changing public IP (`dynamic-ip-access.md` — DDNS, mesh VPN), connecting out through a network that blocks/intercepts SSH (`restricted-networks.md`), triaging scan/brute-force activity on an exposed host (`ssh-scanning-triage.md`), passwordless sudo, mass reboot, node IP map, SSH client config, node-connect script, Windows key perms — see [`ssh/`](ssh/) |
| `tls-pki/` | OpenSSL/PKI reference (`openssl-pki.md`), X.509 cert inspection (`ssl-server-key-checks.md`), cert/key format explainer — PEM/DER/X.509/ASN.1, the PKCS zoo, why TLS certs differ from SSH keys (`cert-formats.md`) |
| `gpg/` | GnuPG reference — key creation, signing/verifying, encrypt/decrypt, batch mode, pinentry troubleshooting |
| `sysadmin/` | LVM/storage concepts + disk resize, ACLs, WSL setup, user/group administration, firewalld, cron/at/systemd timers (`scheduling.md`), boot process & systemd, SELinux, install reference for tools used across this repo (`installations.md`), system-wide shared SDKMAN setup (`sdkman-setup.md`) |

## Glossary

- [`ssh/GLOSSARY.md`](ssh/GLOSSARY.md) — SSH vocabulary (keys, CA, forwarding, reaching a host). Repo-wide terms: [root `GLOSSARY.md`](../GLOSSARY.md).

## See Also

- [`../git/`](../git/) — git command guide, merge strategies, local-dev workflow, SVN → Git comparison (separate top-level dir, not nested under `linux/`)
- [`../network/`](../network/) — general networking (DNS, iptables) vs. `ssh/`'s SSH-specific config
- [`../k8s/TLS-nginxF5-ingress/openssl3-k8s-TLS-setup.md`](../k8s/TLS-nginxF5-ingress/openssl3-k8s-TLS-setup.md) — the k8s-specific TLS walkthrough that `tls-pki/` is the general-purpose OpenSSL reference for
