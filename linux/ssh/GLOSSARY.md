# SSH Glossary

Terms and initialisms used across the `linux/ssh/` docs, each pointing to where
it's actually explained. Repo-wide terms (TLS/PKI, GPG, Kubernetes, networking)
are in the [root `GLOSSARY.md`](../../GLOSSARY.md).

## Files and trust stores

| Term | Meaning | See |
|------|---------|-----|
| **`authorized_keys`** | Server-side, per-user file listing public keys allowed to log in **as that user**. The "guest list". Must be `600`. | [`passwordless-login.md`](passwordless-login.md) |
| **`known_hosts`** | Client-side record of host keys this account has accepted before; drives the "authenticity of host" prompt. | [`passwordless-login.md`](passwordless-login.md) |
| **host key** | The server's own identity keypair (`/etc/ssh/ssh_host_*_key`) — what it presents to prove itself; what a client records in `known_hosts`. | [`ssh-ca.md`](ssh-ca.md) §9 |
| **`sshd_config` / `ssh_config`** | System-wide server rulebook / client defaults, in `/etc/ssh/`. `~/.ssh/config` overrides the client side per-user. | [`passwordless-login.md`](passwordless-login.md), [`ssh-config.md`](ssh-config.md) |
| **drop-in file** | A `*.conf` fragment in `/etc/ssh/sshd_config.d/`. On RHEL/Rocky it's `Include`d at the top, so "first obtained value wins" — a drop-in beats the defaults below it. | [`passwordless-login.md`](passwordless-login.md) §5 |
| **`ssh-agent`** | Per-session (Linux) or persistent (Windows) daemon that holds unlocked private keys — and their adjacent `*-cert.pub` certs — in memory. | [`passwordless-login.md`](passwordless-login.md) §6 |

## Authentication

| Term | Meaning | See |
|------|---------|-----|
| **passphrase vs password** | A *passphrase* unlocks a private key locally and is never sent; a *password* is authentication to the server. Key auth sends neither over the wire. | [`passwordless-login.md`](passwordless-login.md) |
| **`PasswordAuthentication` / `PubkeyAuthentication` / `KbdInteractiveAuthentication` / `GSSAPIAuthentication`** | Independent on/off toggles — enabling one never disables another; each unwanted method must be closed explicitly. | [`passwordless-login.md`](passwordless-login.md) §5 |
| **`MaxAuthTries`** | Server-side cap (default 6) on auth attempts per connection. A large agent can exhaust it before the right key is tried. | [`passwordless-login.md`](passwordless-login.md) §6 |
| **fingerprint** | A SHA256 hash identifying a key; the thing to compare out-of-band. Short key IDs are collidable — use the fingerprint. | [`ssh-ca.md`](ssh-ca.md) §8 |
| **TOFU** (Trust On First Use) | Accepting an unverified host key on first connect — the "authenticity of host … can't be established" prompt. A host CA removes it. | [`ssh-ca.md`](ssh-ca.md) §1 |

## Certificate authority

| Term | Meaning | See |
|------|---------|-----|
| **SSH CA** | An ordinary SSH keypair whose *private* half signs other public keys into certificates; its *public* half is the distributed trust anchor. Not X.509. | [`ssh-ca.md`](ssh-ca.md) §1 |
| **user certificate / host certificate** | A signed public key + metadata. A *user cert* is trusted by the server (replaces `authorized_keys` entries); a *host cert* is trusted by the client (replaces `known_hosts` TOFU). Use separate CAs for each. | [`ssh-ca.md`](ssh-ca.md) §1 |
| **principal** | A name baked into a cert that it's valid for — a username (user cert) or a hostname/IP (host cert). | [`ssh-ca.md`](ssh-ca.md) §2.3 |
| **key ID** (`-I`) | Free-text cert label, logged server-side on every login for audit. | [`ssh-ca.md`](ssh-ca.md) §2.3 |
| **`TrustedUserCAKeys`** | `sshd_config` directive naming the CA public-key file the server trusts to sign user certs. | [`ssh-ca.md`](ssh-ca.md) §5 |
| **`AuthorizedPrincipalsFile`** | `sshd_config` directive that decouples the accepted principal names from the target username. | [`ssh-ca.md`](ssh-ca.md) §5 |
| **`@cert-authority`** | A `known_hosts` line marker meaning "trust any host cert signed by this key" for hosts matching the pattern. | [`ssh-ca.md`](ssh-ca.md) §5 |
| **KRL** (Key Revocation List) | The SSH-CA equivalent of a TLS CRL — pulls a specific cert before its validity window ends. Built and queried with `ssh-keygen -k` / `-Q`. | [`ssh-ca.md`](ssh-ca.md) §4 |
| **critical option / extension** | Cert-embedded restrictions (`force-command`, `source-address`) vs. privileges (`permit-port-forwarding`, `permit-pty`). Set with repeated `-O`. | [`ssh-ca.md`](ssh-ca.md) §3 |

## Connecting through other hosts

| Term | Meaning | See |
|------|---------|-----|
| **bastion / jump host** | An intermediate host you connect *through* to reach a target that isn't directly reachable. | [`ssh-config.md`](ssh-config.md), [`node-connect.md`](node-connect.md) |
| **`ProxyJump`** (`-J`) | The modern `~/.ssh/config` directive / flag for routing a connection via one or more jump hosts. | [`ssh-config.md`](ssh-config.md) |
| **`ControlMaster` / multiplexing** | Reusing one already-open TCP connection for subsequent sessions to the same host, to skip repeated handshakes. | [`ssh-config.md`](ssh-config.md) |
| **`IdentitiesOnly`** | Send only the explicitly named key(s), not everything the agent holds. | [`ssh-config.md`](ssh-config.md) |

## Port forwarding

| Term | Meaning | See |
|------|---------|-----|
| **`LocalForward`** (`-L`) | Carry a connection from a port on your machine to a service reachable from the server. | [`port-forwarding.md`](port-forwarding.md) §2 |
| **`RemoteForward`** (`-R`) | The reverse — expose a service on your side at a port on the server. | [`port-forwarding.md`](port-forwarding.md) §3 |
| **`DynamicForward`** (`-D`) | Turn the SSH session into a **SOCKS proxy**; the application picks destinations at runtime. | [`port-forwarding.md`](port-forwarding.md) §4 |
| **`GatewayPorts`** | `sshd_config` setting controlling whether a forward's bind is reachable by hosts other than loopback. | [`port-forwarding.md`](port-forwarding.md) §3 |
| **`permitopen=`** | An `authorized_keys` restriction limiting a key to one forward destination. **Not** a certificate option. | [`port-forwarding.md`](port-forwarding.md) §5 |

## Reaching a host / being reached

| Term | Meaning | See |
|------|---------|-----|
| **DDNS** (Dynamic DNS) | A hostname kept pointed at a changing public IP by a small updater. | [`dynamic-ip-access.md`](dynamic-ip-access.md) |
| **CGNAT** (Carrier-Grade NAT) | The ISP shares one public IP across many customers — you have no real inbound address, so port-forwarding can't work. | [`dynamic-ip-access.md`](dynamic-ip-access.md) |
| **mesh VPN** (Tailscale / WireGuard / Headscale) | A private overlay network giving every machine a stable address that never moves, letting you close the public SSH port entirely. | [`dynamic-ip-access.md`](dynamic-ip-access.md) |
| **MagicDNS** | Tailscale's automatic name resolution for tailnet machines. | [`dynamic-ip-access.md`](dynamic-ip-access.md) |
| **DPI** (Deep Packet Inspection) | A network filtering traffic by protocol signature — can block SSH's handshake regardless of port. | [`restricted-networks.md`](restricted-networks.md) |
| **`kex_exchange_identification`** | The error you get when a middlebox answers instead of `sshd`; real `sshd` always opens with `SSH-2.0-…`. | [`restricted-networks.md`](restricted-networks.md) §2 |
| **captive portal** | A network that intercepts HTTP until you accept terms / log in — rule it out first when SSH won't connect. | [`restricted-networks.md`](restricted-networks.md) §3 |
| **`sslh` / `stunnel`** | Server-side tools that multiplex SSH with real HTTPS on one port, or wrap SSH inside genuine TLS — to defeat DPI. | [`restricted-networks.md`](restricted-networks.md) §4 |
| **fail2ban / jail** | A daemon that bans source IPs after repeated auth failures; a *jail* is one service's ban ruleset (`sshd`). | [`ssh-scanning-triage.md`](ssh-scanning-triage.md) §3 |

## See Also

- [root `GLOSSARY.md`](../../GLOSSARY.md) — repo-wide terms
- [`linux/README.md`](../README.md) — the `ssh/` file index
