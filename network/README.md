# Networking

General networking diagnostics for the lab — DNS, iptables, connectivity
checks. SSH connection config and node-connect scripts live in
[`../linux/ssh/`](../linux/ssh/) (SSH-specific, not general networking).

| Topic | File |
|-------|------|
| kubelet DNS failure diagnosis (CoreDNS, resolv.conf, common failure modes) | `kubelet-DNS-error.md` |
| iptables reference + explainer script | `iptab.md`, `iptab-explain.sh` |
| General network diagnostics (routes, DNS resolution, connectivity) | `net-check.md` |
| Networking concepts/notes (short) | `network.md` |

## See Also

- [`../linux/ssh/ssh-config.md`](../linux/ssh/ssh-config.md) — `~/.ssh/config` reference (`ProxyJump`, `StrictHostKeyChecking`, etc.)
- [`../linux/ssh/node-connect.md`](../linux/ssh/node-connect.md) — connect script + node-IP map for reaching lab nodes
