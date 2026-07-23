# Linux, Shell & Sysadmin

Grouped by category — directory name tells you the topic. Files are
self-descriptive; open the file for detail.

| Directory | Contents |
|-----------|----------|
| `linux-commands.md` | General sysadmin command reference (catch-all, kept at this root) |
| `text-processing/` | grep (+ regex/BRE/ERE/PCRE ref, k8s patterns), sed, awk, tr, curl (`curl-text-logs.md`), yq/jq/bat, ANSI color codes + piping rationale (`tty-colors.md`), real-world combined-pipeline cookbook (`text-process-cookbook.md`), ripgrep glob syntax (`ripgrep-example.md`) and glob precedence/anchoring/sort performance (`ripgrep-glob-and-sort.md`) |
| `shell/` | aliases, arrays, heredocs, process substitution, bash loops cookbook, prompt, vim, history expansion + `compgen -v` introspection (`bash-history-expansion.md`) |
| `ssh/` | key generation/distribution, passwordless sudo, mass reboot, node IP map, SSH client config, node-connect script, Windows key perms — see [`ssh/`](ssh/) |
| `tls-pki/` | OpenSSL/PKI reference, X.509 cert inspection |
| `sysadmin/` | LVM/storage concepts + disk resize, ACLs, WSL setup, user/group administration, firewalld, cron/at, boot process & systemd, SELinux, install reference for tools used across this repo (`installations.md`) |
| `version-control/` | SVN → Git comparison |

## See Also

- [`../git/`](../git/) — git command guide, merge strategies, local-dev workflow (separate top-level dir, not nested under `linux/`)
- [`../network/`](../network/) — general networking (DNS, iptables) vs. `ssh/`'s SSH-specific config
- [`../k8s/TLS-nginxF5-ingress/openssl3-k8s-TLS-setup.md`](../k8s/TLS-nginxF5-ingress/openssl3-k8s-TLS-setup.md) — the k8s-specific TLS walkthrough that `tls-pki/` is the general-purpose OpenSSL reference for
