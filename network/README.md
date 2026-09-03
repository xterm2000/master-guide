# Networking

General networking diagnostics for the lab — DNS, iptables, connectivity
checks. SSH connection config and node-connect scripts live in
[`../linux/ssh/`](../linux/ssh/) (SSH-specific, not general networking).

| Topic | File |
|-------|------|
| Small network-tool reference — `ip`/`ss`/`dig`/`getent`/`nc`/`nmap`/`curl`/`openssl s_client`/`tracepath`/`arping`/`nstat`/`ethtool`/`nmcli` etc., with a "which tool do I need" dispatch table + diagnostic recipes | `net-tools.md` |
| kubelet DNS failure diagnosis (CoreDNS, resolv.conf, common failure modes) | `kubelet-DNS-error.md` |
| iptables reference + explainer script | `iptab.md`, `iptab-explain.sh` |
| General network diagnostics (routes, DNS resolution, connectivity) | `net-check.md` |
| Networking concepts/notes (short) | `network.md` |

## See Also

- [`../linux/ssh/ssh-config.md`](../linux/ssh/ssh-config.md) — `~/.ssh/config` reference (`ProxyJump`, `StrictHostKeyChecking`, etc.)
- [`../linux/ssh/node-connect.md`](../linux/ssh/node-connect.md) — connect script + node-IP map for reaching lab nodes
