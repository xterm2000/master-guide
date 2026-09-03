# SSH Certificate Authority (`ssh-keygen -s`)

A way to mint many SSH identities (user or host) from one root of trust,
instead of distributing individual public keys to every `authorized_keys`
or `known_hosts` file. Distinct from the x.509/TLS PKI in
[`../tls-pki/openssl-pki.md`](../tls-pki/openssl-pki.md) — SSH certificates
are a separate OpenSSH-native mechanism, not X.509.
[`../tls-pki/cert-formats.md`](../tls-pki/cert-formats.md) §1 lays out why the
two ecosystems have entirely different formats and trust models.

All commands here were run and verified on this machine
(`ssh -V` → OpenSSH, see `linux/tls-pki/` sibling doc for the TLS equivalent
workflow).

---

## 1. Concept

- One **CA keypair** — an ordinary SSH keypair, nothing special about its
  format. Its *private* key **signs** other people's SSH public keys; its
  *public* key gets distributed to whoever needs to **trust** those
  signatures.
- Signing a key produces a **certificate** (`<name>-cert.pub`): the original
  public key, plus metadata (identity, validity window, allowed principals,
  restrictions), plus the CA's signature over all of it.
- A server (or client) that trusts the CA's public key accepts *any*
  certificate signed by it, without that specific key ever being added to
  `authorized_keys` (or `known_hosts`) individually.

Two certificate types:

| Type | Signs | Trusted by | Replaces |
|---|---|---|---|
| **User cert** | a user's SSH public key | the **server** (`sshd`) | per-key entries in `authorized_keys` |
| **Host cert** | a server's SSH host key | the **client** | manual fingerprint checking / `known_hosts` TOFU prompts |

Use **separate CA keypairs** for user certs and host certs — a compromised
host-signing key shouldn't also be able to mint user login certs.

Keep the CA **private** key off any internet-exposed host — signing happens on
a workstation or an offline box; only the CA *public* key is distributed.

`ssh-keygen` itself takes no config file — every option is a CLI flag. Config
files only enter the picture on the *trust* side (`sshd_config`,
`~/.ssh/config`, `known_hosts`) — see §5.

---

## 2. Step by step

### 2.1 Generate the CA keypair (once)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/ca_user_key -C "personal-ssh-ca"
# -t ed25519 : modern, fast, small — good default for a CA key
# -f         : output path; produces ca_user_key (private) + ca_user_key.pub
# -C         : comment embedded in the pubkey, cosmetic only
# You'll be prompted for a passphrase. Protect this like a TLS root.key —
# whoever holds it can mint a trusted login for any principal.
```

### 2.2 Generate a subkey (one per device/purpose)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_laptop -C "laptop"
# Ordinary SSH keypair, nothing CA-specific yet.
```

### 2.3 CA signs the subkey → produces a user certificate

```bash
ssh-keygen -s ~/.ssh/ca_user_key \   # -s: sign with this CA private key
  -I "alice-laptop" \                # -I: key ID — free-text label, logged server-side on login (audit trail)
  -n "alice" \                       # -n: principals — usernames this cert may log in as
  -V +52w \                          # -V: validity window (1 year here). Omit = forever (not recommended)
  -z 1 \                             # -z: numeric serial — needed to revoke this specific cert later (§4)
  ~/.ssh/id_laptop.pub
# Produces: ~/.ssh/id_laptop-cert.pub
```
Verified output on signing:
```
Signed user key id_laptop-cert.pub: id "alice-laptop" serial 1 for alice valid from ... to ...
```

### 2.4 Inspect the certificate

```bash
ssh-keygen -L -f ~/.ssh/id_laptop-cert.pub
# Prints type, key ID, serial, principals, validity, signing-CA fingerprint,
# and any critical options / extensions (§3).
```

### 2.5 Use it to log in

```bash
ssh -i ~/.ssh/id_laptop user@host
# ssh auto-loads id_laptop-cert.pub sitting next to the private key — no
# extra flag needed as long as both files share the base name.
```

---

## 2a. Protecting the CA private key

The CA private key is more sensitive than any individual host or user key —
whoever holds it can mint a trusted login for any principal. It must never live
on a machine it is used to authenticate *to*.

- **Always passphrase-protect it** (`ssh-keygen` prompts — don't skip with
  `-N ""`).
- A password manager synced to cloud storage is a reasonable **at-rest backup**:
  the manager's own encryption plus the key's passphrase are two independent
  secrets.
- For day-to-day signing without repeated extract/decrypt friction, a
  **dedicated signing box** (a small persistent VM) is a sound pattern:
  - **Host-only virtual network** — no route to the LAN or the internet — is the
    actual isolation boundary. Verify with `ip route`, and confirm a `ping` to
    the LAN gateway fails from inside it.
  - Full-disk encryption (LUKS), since the key now lives at rest on that disk.
  - Passphrase on the CA key file *as well as* the disk encryption.
  - Snapshot after setup as a rollback point.
  - Back up the VM disk carefully — it is now a second durable copy of the CA
    key; don't let backups land somewhere unencrypted.
  - Normal host hardening still applies (key-only SSH, patched, minimal package
    footprint).

  This is a **persistent appliance**, not a wipe-after-every-session model — the
  key stays resident so signing is just "ssh in, run `ssh-keygen -s`, copy the
  cert out," with the password-manager copy serving only as disaster recovery.

Use `-U` (§3) to keep even the signing box's on-disk exposure to the CA
*public* key only, with the private key loaded into its `ssh-agent`.

---

## 3. Extended `-s` parameters

Beyond `-I` / `-n` / `-V`, confirmed by direct testing:

### `-z <serial>` — numeric serial

```bash
ssh-keygen -s ca_user_key -I test-id -n testuser -V +1d -z 1 id_test.pub
```
Required if you ever want to revoke this exact certificate by serial number
via a KRL (§4) rather than by key ID or full public key.

### `-O <option>` — restrictions and extensions (repeatable)

```bash
ssh-keygen -s ca_user_key -I alice-laptop -n alice -V +52w -z 2 \
  -O no-port-forwarding \
  -O no-agent-forwarding \
  -O no-x11-forwarding \
  -O no-pty \
  -O "force-command=/usr/local/bin/backup.sh" \
  -O "source-address=10.0.0.0/24" \
  id_laptop.pub
```

Verified via `ssh-keygen -L` on a cert signed with `force-command` +
`source-address`:
```
Critical Options:
        force-command /bin/true
        source-address 127.0.0.1
```

Common `-O` values:

| Option | Effect |
|---|---|
| `no-port-forwarding` | disallow `-L`/`-R`/`-D` tunneling |
| `no-agent-forwarding` | disallow forwarding the local ssh-agent |
| `no-x11-forwarding` | disallow X11 forwarding |
| `no-pty` | disallow allocating a terminal (force non-interactive use) |
| `permit-pty` | explicitly allow a pty (needed if a default template disables it) |
| `force-command=<cmd>` | run only `<cmd>` regardless of what the client requested |
| `source-address=<CIDR>` | cert only valid when the client connects from this network |
| `clear` | clear all default permissions before applying subsequent `-O` flags |

Without any `-O` flags, a signed cert defaults to `permit-user-rc` and no
restrictions (confirmed: an unrestricted sign showed `Extensions:
permit-user-rc` and no `Critical Options` block).

### Batch signing — multiple pubkeys in one invocation

```bash
ssh-keygen -s ca_user_key -I batch-id -n alice -V +1d id_a.pub id_b.pub
# Signs both, producing id_a-cert.pub and id_b-cert.pub with the same
# key ID / principals / validity.
```
Note: without `-z`, batch-signed certs all get serial `0` — pass distinct
`-z` values per-invocation if you need to revoke them individually later.

### `-h` — host certificate instead of user certificate

```bash
ssh-keygen -t ed25519 -f host_key -N ""
ssh-keygen -s ca_host_key -I host-web01 -h \
  -n "web01.example.com,192.168.1.10" \   # principals = hostnames/IPs this cert covers
  -V +52w \
  host_key.pub
```
Verified: `Signed host key host_key-cert.pub: id "host-test" ... for
myhost.example.com ...`. Use a CA keypair dedicated to host signing, separate
from the user-signing CA (see §1).

### `-U` — CA key held in ssh-agent

```bash
ssh-add ~/.ssh/ca_user_key
ssh-keygen -Us ca_user_key.pub -I id -n user -V +1d id_laptop.pub
# -U tells ssh-keygen the CA private key is in the agent — only the CA's
# *public* key needs to be on disk/passed to -s. Useful for keeping the CA
# private key off disk on the signing workstation.
```

---

## 4. Revocation (KRL)

The SSH-CA equivalent of a TLS CRL. Verified end-to-end:

```bash
# 1. Write a revocation spec — NOT stdin, a real file passed positionally.
cat > revoke.spec <<'EOF'
serial: 1
EOF

# 2. Build the KRL. -s here takes the CA's PUBLIC key (verifies the serial
#    namespace belongs to that CA) — the spec file is a positional arg.
ssh-keygen -k -f revoked.krl -s ca_user_key.pub revoke.spec

# 3. Query it against a cert.
ssh-keygen -Q -f revoked.krl id_test-cert.pub
```
Verified output: `id_test-cert.pub (test-subkey): REVOKED`, exit code `1`.
An unrevoked cert would print `... ok`, exit code `0`.

Other spec-file directives (from `ssh-keygen(1)`, `KEY REVOCATION LISTS`):

| Directive | Revokes |
|---|---|
| `serial: N` or `serial: N-M` | one serial, or an inclusive range |
| `id: <key-id>` | by the `-I` key ID string |
| `key: <public_key>` | a specific plain public key |
| `sha256: <public_key>` | by SHA256 hash of the key (OpenSSH ≥ 7.9) |

Update an existing KRL instead of rebuilding it:
```bash
ssh-keygen -u -k -f revoked.krl -s ca_user_key.pub another.spec
```

Deploy the KRL server-side via `RevokedKeys` in `sshd_config` (§5).

### Renewal vs revocation

Letting a cert **expire** (short `-V`) needs no server-side action at all — the
server trusts the CA, not the individual cert. To renew, re-sign the *same*
public key from the *same* CA with a fresh `-V` and replace the `-cert.pub`
file on the client:

```bash
ssh-keygen -s ca_user_key -I "alice-laptop" -n alice -V +52w -z 3 id_laptop.pub
```

Revocation (a KRL) is only for pulling a cert *before* its validity window
ends — a lost laptop, a leaked key.

---

## 5. Trust-side configuration

`ssh-keygen` stays config-free; these are the files that make a signed cert
actually grant (or deny) access. Directive text below is quoted from
`sshd_config(5)` / `ssh_config(5)` as installed on this machine.

### Server — `/etc/ssh/sshd_config` (trusts user certs)

```
TrustedUserCAKeys /etc/ssh/ca_user_key.pub
# "Specifies a file containing public keys of certificate authorities that
#  are trusted to sign user certificates for authentication... If a
#  certificate is presented ... and has its signing CA key listed in this
#  file, then it may be used for authentication for any user listed in the
#  certificate's principals list." Path is the CA's PUBLIC key only.
# The filename is arbitrary (ca_user_key.pub is only a convention). Three
# things must agree: this file on disk, the path named here, and the cert's
# "Signing CA" fingerprint (ssh-keygen -L -f <cert>). A renamed or stale file
# = every cert silently rejected. The file must also be world-readable (644)
# or sshd can't read it after dropping privileges.

AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u
# "Specifies a file that lists principal names that are accepted for
#  certificate authentication... this file lists names, one of which must
#  appear in the certificate for it to be accepted." Optional — without it,
#  the target username itself must be in the cert's principals list.
# %u expands to the local username being logged in as.

RevokedKeys /etc/ssh/revoked_user_keys.krl
# "Specifies revoked public keys file... Keys may be specified as a text
#  file, listing one public key per line, or as an OpenSSH Key Revocation
#  List (KRL) as generated by ssh-keygen(1)." NOTE: if this file exists but
#  is unreadable, sshd refuses ALL public-key auth for ALL users — keep
#  permissions correct.
```
Both `TrustedUserCAKeys` and `RevokedKeys` are also valid inside a `Match`
block (confirmed in the man page's per-directive keyword list), so you can
scope trust to specific users/groups/hosts rather than globally.

Restart/reload `sshd` after editing.

### Client — `~/.ssh/known_hosts` (trusts host certs)

```
@cert-authority *.example.com,192.168.1.0/24 ssh-ed25519 AAAA...ca_host_key_pubkey...
# @cert-authority marks this line as "trust any host cert signed by this
# key, for hosts matching this pattern" instead of "this exact host key is
# known good" (the normal known_hosts behavior).
```

### Client — `~/.ssh/config` (optional convenience)

```
Host web01
    HostName web01.example.com
    User alice
    IdentityFile ~/.ssh/id_laptop
    CertificateFile ~/.ssh/id_laptop-cert.pub   # usually auto-detected; explicit here for clarity
```

---

## 6. Use cases beyond "replace my authorized_keys"

- **Time-boxed contractor/bastion access** — issue a cert with `-V
  +2w` instead of adding then remembering to remove a key from
  `authorized_keys`. Access expires itself; no offboarding step to forget.
- **CI/CD pipelines** (e.g. GitHub Actions runners) — issue a short-lived
  cert per job run instead of storing a static long-lived deploy key as a
  secret. Nothing persists to leak if a runner is compromised after the job
  ends.
- **Fleet-wide host-cert rollout** — sign every server's host key once with
  a host CA, push `@cert-authority` to clients' `known_hosts`. Eliminates
  per-host TOFU ("authenticity of host ... can't be established") prompts
  across an entire fleet, and rotating a host key no longer requires
  updating every client's `known_hosts`.
- **Scoped automation/Ansible control-node access** — sign a cert restricted
  with `-O force-command=... -O source-address=<controller-ip>` so the key
  can only run one thing, from one place, instead of a broad
  `authorized_keys` entry.
- **Break-glass emergency access** — keep a CA key offline (paper/HSM/vault)
  and only sign a very-short-`-V` cert when actually needed, rather than
  maintaining a permanently-live "emergency" keypair on disk somewhere.
- **Production-scale automated issuance** — HashiCorp Vault's SSH secrets
  engine (and similar tools) automate exactly this signing step behind an
  API/auth flow, generating one-time client certs on demand. Worth knowing
  the underlying `ssh-keygen -s` mechanics before reaching for that.

---

## 7. Summary vs the TLS/x509 CA

| | x.509 PKI ([`openssl-pki.md`](../tls-pki/openssl-pki.md)) | SSH CA |
|---|---|---|
| CA output | `root.crt` (self-signed cert) | `ca_user_key.pub` (plain pubkey, no self-cert) |
| Spawn a subkey | `genrsa` → `req -new` → `x509 -req -CA` | `ssh-keygen` → `ssh-keygen -s` |
| Distributed trust anchor | `root.crt` in a trust store | CA pubkey in `sshd_config` / `known_hosts` |
| Revocation | CRL (`openssl ca -revoke`) | KRL (`ssh-keygen -k` / `-Q`), or just short `-V` windows |
| Config file | `openssl.cnf` (or none, via `x509 -req`) | none for signing; `sshd_config`/`ssh_config` for trust |

---

## 8. Troubleshooting

Symptom: cert is offered (`ssh -v` shows
`Offering public key: ... ED25519-CERT`) but the server responds
`Authentications that can continue: publickey,...,password` and login falls
through to a password prompt. Work the chain, on the **server**:

```bash
# 1. Is CA trust configured at all?
sudo sshd -T | grep -Ei 'trusteduserca|pubkeyauth|authorizedprincipalsfile|revokedkeys'
#   trustedusercakeys empty            -> CA not trusted; cert can't work
#   pubkeyauthentication no            -> key auth disabled entirely
#   revokedkeys -> unreadable file     -> sshd rejects ALL pubkey auth for everyone

# 2. Inspect the cert.
ssh-keygen -L -f id_laptop-cert.pub
#   Principals: must contain the LOGIN username when authorizedprincipalsfile
#     is "none" (no AuthorizedPrincipalsFile). A cert signed with -n for a
#     different name is rejected.
#   Valid: window must bracket the current time. A test cert signed -V +1d is
#     dead the next day. Check the server clock too (`date`).
#   Type: must be "user certificate", not "host certificate".

# 3. Does the trusted CA actually match the cert's signer?
sudo ssh-keygen -l -f "$(sudo sshd -T | awk '/^trustedusercakeys/{print $2}')"
#   This fingerprint MUST equal the cert's "Signing CA" line from step 2.
#   Mismatch = the server trusts a different (or renamed/stale) CA file.

# 4. The log states the real reason.
sudo journalctl -u sshd --since "10 min ago" | grep -iE 'cert|principal|invalid|revoked|signature'
#   e.g. "Certificate invalid: name is not a listed principal"
#        "Certificate invalid: expired"
#        (nothing at all) -> CA not trusted / wrong config file in effect

# 5. Right daemon? A non-standard port may be a container or a second sshd
#    with its own config that never saw TrustedUserCAKeys.
sudo ss -tlnp | grep <port>
#   `sshd -T` with no -f reads only the default /etc/ssh/sshd_config.
```

---

## 9. Host key lifecycle (plain host keys, no CA)

Separate from cert renewal (§4). A server's `/etc/ssh/ssh_host_*_key` pair is
its identity to clients — recorded in `known_hosts` on first connect (or
vouched for by a host cert — §3 (`-h`) and §5).

### When to regenerate

| Regenerate | Don't |
|---|---|
| VM was cloned from a template or snapshot (it shares another machine's host key / identity) | Routine maintenance or OS updates with no specific trigger |
| Suspected compromise (rebuild the host first, *then* rotate) | After an IP or hostname change — host keys aren't tied to network identity |
| Deprecating a key algorithm (e.g. dropping RSA) | "For hygiene" on a schedule — host keys are not passwords |
| The private key file was exposed (a backup, a git repo, a shared drive) | |

Check whether an existing VM's host key predates the VM itself (a sign it was
baked into the image):

```bash
sudo stat /etc/ssh/ssh_host_ed25519_key      # compare mtime against the VM's creation date
```

The file should be mode `0600`, owned by root.

### Consequences of regenerating

- `sshd` needs at least one host key pair to start — removing all of them
  without regenerating makes the service fail to start.
- Every client that has connected before gets
  `REMOTE HOST IDENTIFICATION HAS CHANGED` on the next connect and must clear
  the stale entry first:

  ```bash
  ssh-keygen -R <host-or-ip>
  ```

- A **host CA** avoids this churn entirely: sign each server's host key once,
  push `@cert-authority` to clients' `known_hosts` (§5), and rotating a host
  key no longer touches any client.
