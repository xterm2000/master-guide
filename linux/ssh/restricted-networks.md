# Connecting Out Through a Restrictive Network

Public / hotel / corporate wifi that blocks or intercepts SSH. Distinct from
[`dynamic-ip-access.md`](dynamic-ip-access.md) (the *server's* address moved) —
here the server is fine and the network in front of *you* is the problem.

---

## 1. What's actually the risk on public wifi

SSH's own encryption already protects session contents from other people on the
network or a malicious access point — that is **not** the main concern. The
real risks are behavioural:

- overriding a host-key-changed warning without investigating (the classic
  MITM signature)
- using your private key from an untrusted / shared computer
- losing an unlocked or passphrase-less device
- shoulder-surfing

Keep a passphrase on the key, let `ssh-agent` hold it, and never click through
`REMOTE HOST IDENTIFICATION HAS CHANGED`.

---

## 2. Symptoms of a blocking / intercepting network

| Symptom | Meaning |
|---|---|
| `kex_exchange_identification: ... Not allowed at this time` (or any banner not starting `SSH-2.0-`) | A middlebox answered instead of the server. Real `sshd` **always** opens with `SSH-2.0-...`. Usually a captive portal or filtering proxy. |
| TCP connects, but the SSH banner exchange hangs / times out | Either nothing is listening on that forwarded port, **or** the network is doing deep packet inspection (DPI) and dropping traffic that doesn't look like TLS regardless of port. |
| Works on a phone hotspot, fails on the wifi | The network is the cause, not your config or the server. |

---

## 3. Diagnostic ladder

```bash
# 1. Rule out a captive portal. Open http://neverssl.com in a browser.
#    Redirected to a login/terms page -> authenticate there first, then retry.

# 2. Raw TCP reachability (does NOT prove SSH gets through).
#    Linux/macOS:
curl -sv telnet://SERVER:2222 </dev/null     # "Connected to ..." = TCP ok
#    Windows PowerShell:
#    Test-NetConnection -ComputerName SERVER -Port 2222

# 3. Confirm you're reaching REAL sshd, not a middlebox. `ssh -v` prints the
#    peer's version string as soon as the banner arrives:
ssh -v -o ConnectTimeout=5 -p 2222 user@SERVER 2>&1 | grep -i 'remote software version'
#    "remote software version OpenSSH_..."  -> real sshd, the network is fine.
#    "kex_exchange_identification: ... Not allowed at this time"  -> a middlebox
#      answered (see the table above).
#    Connection hangs after "Connecting to ..."  -> filtered / DPI-dropped.
#    Raw-banner alternative if netcat is present:  nc -v SERVER 2222  (first line
#      should start "SSH-2.0-").

# 4. Try a fallback port already forwarded to the server's :22.
#    Many networks leave 443 alone because it looks like HTTPS.
ssh -p 443 -v user@SERVER

# 5. Isolate the network: run the same command over a phone hotspot.

# 6. Known-good DPI test — a public SSH-over-443 endpoint that definitely works:
ssh -T -p 443 git@ssh.github.com
```

**Interpreting step 6:**

- Hangs / times out too → the network fingerprints and blocks SSH's protocol
  handshake itself, independent of port. No port change will help.
- Connects fine (`Hi <user>! You've successfully authenticated...` or a
  permission-denied that still came from GitHub) → the block is *not*
  protocol-level. The problem is local: the fallback-port forward on the router
  doesn't actually point at the server's `:22` yet, or something else already
  claims that external port.

---

## 4. Remedies when it's confirmed protocol-level (DPI)

| Approach | Why it gets through |
|---|---|
| **Tailscale / WireGuard** | UDP-based, no plaintext SSH banner to fingerprint; often passes filters that specifically target SSH's handshake. Also removes the need to expose SSH at all — see [`dynamic-ip-access.md`](dynamic-ip-access.md) Option B. |
| **`sslh` on the server** | Multiplexes real HTTPS and SSH on the same port, dispatching by the protocol it actually observes — SSH arrives wrapped in / alongside genuine TLS. |
| **`stunnel`** | Wraps the SSH stream inside a real TLS connection end to end. |
| **Cellular hotspot** | Zero-setup workaround for the moment. |

Provision at least one of these *before* travelling — a forwarded `:443`
fallback plus a mesh VPN covers almost every hostile network.

---

## See Also

- [`dynamic-ip-access.md`](dynamic-ip-access.md) — reaching a server whose public IP changes; mesh-VPN setup
- [`port-forwarding.md`](port-forwarding.md) — tunnelling services once you *are* connected
- [`passwordless-login.md`](passwordless-login.md) — §6 keeping a cert offered with no per-host config; keep a `:443` fallback forwarded
- [`ssh-scanning-triage.md`](ssh-scanning-triage.md) — the other side: checking an exposed server for scan / brute-force activity
