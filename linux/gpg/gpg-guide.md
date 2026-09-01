# GnuPG (GPG) — Complete Guide

A practical reference for GnuPG: key creation (including production-grade certify-only-primary identities and offline-primary storage), certifying other keys, signing/verifying, encrypting/decrypting, batch/unattended usage, the pinentry issues that show up most often on headless boxes (this repo's lab VM `shiva` included — see below), OpenSSL interop, and reusable shell helper functions.

Verified against `gpg (GnuPG) 2.4.5` on this host (`gpg --version`).

---

## 1. Concepts

### Keypair

A GPG identity is an RSA (or ECC) keypair, generated together:

- **Primary key** — by default capable of Sign, Certify, Encrypt, and Auth (`[SCEA]`). Certify (`C`) is the important one: it's what lets this key sign *other* keys/UIDs, which is how the web-of-trust works. Losing the primary key means losing the ability to certify or revoke — keep it offline/backed-up for anything beyond a throwaway key.
- **Subkey** — a second keypair bound to the primary, normally used for day-to-day Sign/Encrypt/Auth operations (`[SEA]`) so the primary key's certify capability doesn't need to be online. GPG creates one automatically during interactive `--full-generate-key` and can be told to during batch generation too.

Confirmed with a real key:
```
pub   rsa3072 2026-08-20 [SCEAR] [expires: 2027-08-20]
      0C44CF721D68EBC7DC3D635DE75DA6ADA6464074
uid           [ultimate] Test User <test@example.local>
sub   rsa3072 2026-08-20 [SEA] [expires: 2027-08-20]
```

### Keyring / `GNUPGHOME`

GPG stores keys, trust data, and agent sockets under `~/.gnupg` (override with `GNUPGHOME` env var — useful for testing without touching your real keyring, as done for every example on this page). The directory must be mode `700`.

- `pubring.kbx` — public keys (keybox format in modern GPG)
- private key material lives under `private-keys-v1.d/`, never exported unencrypted by `--list-keys`
- `trustdb.gpg` — your local trust decisions about other people's keys

### `gpg-agent`

A background daemon that holds unlocked private keys and passphrases in memory (with a cache timeout) so you don't retype a passphrase for every operation in a session. It's also the component responsible for popping the passphrase-entry dialog (**pinentry**, see §7). `gpg` talks to it automatically; you rarely invoke `gpg-agent` directly, though `gpgconf --kill gpg-agent` (restart it) and `gpgconf --reload gpg-agent` are common troubleshooting commands.

### Trust model

Encrypting to someone's key or accepting a signature as "fully" valid depends on GPG's trust database, not just whether the key is imported. A freshly imported public key is untrusted by default — `gpg --encrypt` to it will interactively ask "Use this key anyway?" unless you either sign the key (`gpg --sign-key`), set trust explicitly (`gpg --edit-key <id>` → `trust`), or override the check per-command with `--trust-model always` (fine for scripts/CI, not a substitute for real trust). Actually certifying a key so it's usable without that override is §2a.

---

## 2. Creating Keys

### Interactive (normal usage)

```bash
gpg --full-generate-key
```
Walks through: key type (RSA and RSA is the safe default), key size (3072 or 4096), expiration, and identity (name/email/comment). Set an expiration — a key with no expiry that gets lost or compromised has no automatic way to age out; you'd rely entirely on publishing a revocation certificate.

### Batch / unattended generation

For scripting (CI, provisioning, automated test fixtures). Verified working:

```bash
cat > keyparams.txt <<'EOF'
%echo Generating key
Key-Type: RSA
Key-Length: 3072
Subkey-Type: RSA
Subkey-Length: 3072
Name-Real: Test User
Name-Email: test@example.local
Expire-Date: 1y
Passphrase: testpass123
%commit
%echo done
EOF

gpg --batch --gen-key keyparams.txt
```

Output on success:
```
gpg: Generating key
gpg: keybox '.../pubring.kbx' created
gpg: trustdb created
gpg: directory '.../openpgp-revocs.d' created
gpg: revocation certificate stored as '.../openpgp-revocs.d/<FPR>.rev'
gpg: done
```

GPG also writes a **revocation certificate** automatically at generation time — back that file up separately from the key itself. It's the only way to mark a key revoked if you lose the private key entirely and never generated one manually.

To generate a passphrase-less key for pure automation (e.g. a CI signing key stored in a secrets manager that itself handles access control), omit `Passphrase:` and add `%no-protection`:
```
%no-protection
```

Back up the auto-generated revocation certificate as its own entry, separate from where you store the key/passphrase (e.g. its own KeePass entry, or an offline copy) — a single leaked entry then can't hand over both the key and its kill switch. Set a calendar reminder to rotate/extend before the key's expiration date too.

A workable password-manager layout:

- One "crypto identity" group holding the private key, the public key / cert, the passphrase, and the expiration date together — everything needed to *use* the key.
- The **revocation certificate as a separate entry** (or an offline-only copy) — never in the same group as the key. A single leaked group then can't hand over both the key and the means to revoke it.
- A calendar reminder to extend or rotate before the expiration date.

### Production identity: certify-only primary + per-purpose subkeys

The single combined-subkey key above (`[SEA]` on one subkey) is fine for throwaway/test keys, but a personal identity you intend to keep for years is better built as a **certify-only primary** with three separate subkeys, one per purpose. Each subkey can then be rotated or revoked independently without changing your fingerprint, and the primary key's Certify capability — the one thing that can mint new subkeys or certifications — only ever needs to come out for key maintenance, not daily signing/encrypting.

Verified working (ed25519/cv25519 — GPG's default modern ECC pairing):
```bash
gpg --batch --passphrase testpass123 --pinentry-mode loopback \
    --quick-generate-key "Dana Test <dana@example.local>" ed25519 cert 1y

FPR=$(gpg --list-secret-keys --with-colons dana@example.local | awk -F: '/^fpr:/{print $10; exit}')

gpg --batch --passphrase testpass123 --pinentry-mode loopback --quick-add-key "$FPR" ed25519 sign 1y
gpg --batch --passphrase testpass123 --pinentry-mode loopback --quick-add-key "$FPR" cv25519 encrypt 1y
gpg --batch --passphrase testpass123 --pinentry-mode loopback --quick-add-key "$FPR" ed25519 auth 1y
```
Result (confirmed):
```
sec   ed25519/63C6047FF91E33B6 2026-08-26 [C] [expires: 2027-08-26]
uid                 [ultimate] Dana Test <dana@example.local>
ssb   ed25519/B31D8E1E0D541264 2026-08-26 [S] [expires: 2027-08-26]
ssb   cv25519/F6EB298B3427D990 2026-08-26 [E] [expires: 2027-08-26]
ssb   ed25519/5B3E14AFFC392B75 2026-08-26 [A] [expires: 2027-08-26]
```
The primary shows only `[C]` — no S/E/A — exactly the point of the pattern.

**Curve constraint, not a policy choice:** `cv25519` (X25519/ECDH) is encrypt-only math — GPG refuses to give it sign or auth usage. Confirmed:
```
$ gpg --quick-add-key "$FPR" cv25519 sign 1y
gpg: Key generation failed: Wrong key usage
```
Use `ed25519`/EdDSA for sign and auth subkeys, `cv25519` for the encrypt subkey — they're different curves for a reason, not interchangeable.

**RSA alternative** (uniform key type throughout, no curve juggling — useful when a downstream tool doesn't yet support ed25519/cv25519):
```
%echo Generating RSA identity
Key-Type: RSA
Key-Length: 4096
Key-Usage: cert
Subkey-Type: RSA
Subkey-Length: 4096
Subkey-Usage: sign
Name-Real: Dana Test
Name-Email: dana@example.local
Expire-Date: 1y
Passphrase: testpass123
%commit
```
```bash
gpg --batch --gen-key keyparams.txt
```
Note: the classic `%commit` parameter-file format only supports a primary + **one** subkey per file (there's no `Subkey2-Type:` field) — that's why the multi-subkey identity above uses `--quick-add-key` scripting for the encrypt/auth subkeys instead of one parameter file. Add them the same way: `gpg --batch --passphrase testpass123 --pinentry-mode loopback --quick-add-key "$FPR" rsa4096 encrypt 1y` (and `auth 1y`).

### Taking the primary key offline

Once the per-purpose subkeys exist, the certify-capable primary secret key doesn't need to stay on the day-to-day working machine at all — export just the subkeys, delete the primary secret from the working keyring, and keep the primary (plus the revocation certificate) offline (USB stick, KeePass vault). A full compromise of the working machine then can't forge new certifications or mint new subkeys under your identity, only misuse the already-issued sign/encrypt/auth subkeys (which you can revoke).

Verified sequence:
```bash
gpg --batch --passphrase testpass123 --pinentry-mode loopback \
    --export-secret-subkeys "$FPR" > subkeys-only.gpg
gpg --batch --yes --delete-secret-keys "$FPR"
gpg --batch --yes --pinentry-mode loopback --passphrase testpass123 --import subkeys-only.gpg
```
(The `--pinentry-mode loopback --passphrase` on that last `--import` is needed on any host without a `pinentry` binary installed — see §8 — since importing secret key material still requires unlocking it.)

`--list-secret-keys` afterward shows `sec#` (the `#` marks a stub — the primary secret key is *not* present, only its public half) with the subkeys still listed as plain `ssb`:
```
sec#  ed25519/63C6047FF91E33B6 2026-08-26 [C] [expires: 2027-08-26]
uid                 [ultimate] Dana Test <dana@example.local>
ssb   ed25519/B31D8E1E0D541264 2026-08-26 [S] [expires: 2027-08-26]
ssb   cv25519/F6EB298B3427D990 2026-08-26 [E] [expires: 2027-08-26]
ssb   ed25519/5B3E14AFFC392B75 2026-08-26 [A] [expires: 2027-08-26]
```
Day-to-day signing/encrypting works exactly as before with this stub keyring — but two things now require the *offline* copy with the real primary: `--gen-revoke` (fails immediately with `gpg: can't do this in batch mode`, and further fails with `no secret key` against a `sec#` stub — it needs the real primary), and `--quick-sign-key`/`--quick-lsign-key` (certifying other people's keys, §2a — also needs Certify capability). Also worth knowing: once the primary is a stub, GPG's automatic key selection for signing can get confused — pass `-u <fingerprint>` explicitly (`gpg -u "$FPR" --detach-sign ...`) rather than relying on the default, confirmed necessary in testing (`gpg: no default secret key: Unusable secret key` without it).

---

## 2a. Certifying Other Keys (Web of Trust)

Importing someone's public key just makes GPG *aware* of it — it doesn't vouch that the key really belongs to the name/email on it. **Certifying** a key is you using your own key's Certify (`C`) capability to sign someone else's key, asserting "I've verified this key belongs to this person" (checked a fingerprint over a trusted channel, met them in person, etc.). This is distinct from *encrypting to* a key, which only needs the key to exist.

Verified end-to-end with two separate keyrings — Alice certifying Bob's key, which she only has as an imported public key (no secret key, unlike the single-keyring examples elsewhere on this page).

### Before certifying: an unverified key can't be used in batch mode

```bash
$ echo test | gpg --batch -r bob@example.local --encrypt -o out.gpg
gpg: 2FDAE744980DD842: There is no assurance this key belongs to the named user
gpg: [stdin]: encryption failed: Unusable public key
```
`gpg --list-keys bob@example.local` shows the uid as `[ unknown ]`. (`--trust-model always`, §6, is the blunt workaround; certifying is the real fix.)

### Certify (exportable) — you're willing to vouch for this key publicly

```bash
gpg --batch --yes --pinentry-mode loopback --passphrase <your-passphrase> \
    --quick-sign-key <fingerprint-of-key-to-certify>
```
Verified: this alone flips the certified key's uid straight from `[ unknown ]` to `[ full ]` — no separate `--edit-key` → `trust` step needed, because GPG derives validity from certifications made by keys *your own keyring already trusts ultimately* (your own key, by definition). After certifying, the same `--encrypt` command above succeeds without `--trust-model always`.

`--list-sigs bob@example.local` then shows the new certification alongside the self-signature:
```
uid           [  full  ] Bob Test <bob@example.local>
sig 3        2FDAE744980DD842 2026-08-20  [self-signature]
sig          C3D6A9EE2D4DE1E2 2026-08-20  Alice Test <alice@example.local>
```
This signature is exportable — if you `--send-keys` or hand this pubkey to someone else, your certification travels with it and contributes to *their* trust calculation too (that's the "web" in web of trust).

### Locally sign (non-exportable) — trust it for yourself, don't vouch for it publicly

```bash
gpg --batch --yes --pinentry-mode loopback --passphrase <your-passphrase> \
    --quick-lsign-key <fingerprint-of-key-to-certify>
```
GPG prints `The signature will be marked as non-exportable.` and `--list-sigs` shows it with an `L` flag:
```
sig   L      C3D6A9EE2D4DE1E2 2026-08-20  Alice Test <alice@example.local>
```
Verified by packet-dumping an `--export` of the key afterward: the local signature's keyid is absent from the exported output — only self-signatures survive. Use this for "I've decided to trust this key for my own encryption/verification needs" without publicly attesting to its identity — e.g. certifying a coworker's key you verified informally, without that certification becoming a public claim under your name.

### Revoking a certification

```bash
gpg --batch --yes --pinentry-mode loopback --passphrase <your-passphrase> \
    --quick-revoke-sig <fingerprint-of-key-you-certified> <your-own-uid-or-email>
```
Verified: adds a `rev` entry in `--list-sigs` and drops the target key's validity back to `[ unknown ]`. Needed if you decide a certification was made in error, or the person's control of the key/identity is now in doubt.

### Interactive equivalent

All of the above has an interactive form via `gpg --edit-key <id>`, which drops into a `gpg>` prompt accepting `sign` / `lsign` / `trust` / `revsig` / `save` — useful when you want GPG to show you the fingerprint and ask "Really sign?" interactively rather than trusting a script-supplied fingerprint blindly.

---

## 3. Listing & Inspecting Keys

```bash
gpg --list-keys                              # public keys
gpg --list-secret-keys --keyid-format=long   # private keys, long key IDs
gpg --fingerprint test@example.local         # full fingerprint, for out-of-band verification
```

Fingerprint output:
```
pub   rsa3072 2026-08-20 [SCEAR] [expires: 2027-08-20]
      0C44 CF72 1D68 EBC7 DC3D  635D E75D A6AD A646 4074
uid           [ultimate] Test User <test@example.local>
sub   rsa3072 2026-08-20 [SEA] [expires: 2027-08-20]
```
The fingerprint (not the short key ID) is what you should read over the phone / publish on a business card / compare against when verifying someone's identity — short key IDs (last 8 hex chars) are practically collidable.

---

## 4. Exporting & Importing Keys

```bash
# Public key — safe to share, publish, email
gpg --armor --export test@example.local > pub.asc

# Private key — NEVER share; only for your own backup/transfer, encrypted transport only
gpg --batch --yes --pinentry-mode loopback --passphrase testpass123 \
    --armor --export-secret-keys test@example.local > sec.asc

# Import a public key someone sent you
gpg --import pub.asc
```
`--armor` produces ASCII text (`-----BEGIN PGP PUBLIC KEY BLOCK-----…`) suitable for pasting into a web form (Gitea/GitHub "Add GPG Key" fields) or emailing; omit it for compact binary output.

---

## 5. Signing & Verifying

Three signature forms, verified against a real key:

### Detached signature — original file untouched, separate `.sig`
```bash
gpg --batch --yes --pinentry-mode loopback --passphrase testpass123 \
    --detach-sign --armor -o msg.txt.sig msg.txt

gpg --verify msg.txt.sig msg.txt
```
```
gpg: Signature made Thu 20 Aug 2026 14:16:59 EDT
gpg:                using RSA key 081A857A...93DBA72102013478
gpg: Good signature from "Test User <test@example.local>" [ultimate]
```
This is the form used for release artifacts (`myapp.tar.gz` + `myapp.tar.gz.sig`) — the archive stays a plain, unmodified tarball. A tampered file fails verification with `BAD signature` (confirmed by appending a byte to `msg.txt` and re-running `--verify`).

### Clearsign — human-readable text with an inline signature block
```bash
gpg --batch --yes --pinentry-mode loopback --passphrase testpass123 --clearsign msg.txt
```
Produces `msg.txt.asc`:
```
-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA256

hello world, this is a test file
-----BEGIN PGP SIGNATURE-----
...
-----END PGP SIGNATURE-----
```
Good for emails/plain-text postings where the reader should be able to read the message without a GPG tool, but verify it if they have one. Note: `gpg --verify msg.txt.asc` alone verifies the embedded content; running `gpg --verify msg.txt.asc msg.txt` (passing the *original* file too) prints `WARNING: not a detached signature; file 'msg.txt' was NOT verified!` — clearsign is self-contained, don't pass a second file to it.

### Inline/normal sign — signature + compressed content combined, decodes back to the original
```bash
gpg --sign -o msg.txt.gpg msg.txt      # binary, signed+compressed
gpg --decrypt msg.txt.gpg               # recovers original content, verifies signature as a side effect
```
Less commonly used directly; this is the building block `--encrypt --sign` composes with (§6).

---

## 6. Encrypting & Decrypting

### Asymmetric (to a recipient's public key)
```bash
gpg --trust-model always --armor --recipient test@example.local --encrypt -o secret.txt.asc secret.txt
gpg --batch --yes --pinentry-mode loopback --passphrase testpass123 --decrypt secret.txt.asc
```
`--trust-model always` skips the "key is not certified" prompt — appropriate for scripted/CI use where you've already verified the key's fingerprint out of band; don't reach for it as a default for interactive use.

Omit `--armor` for compact binary output (`.gpg` extension by convention) — file(1) correctly identifies it:
```
$ gpg --encrypt -o secret.gpg -r test@example.local secret.txt && file secret.gpg
secret.gpg: PGP RSA encrypted session key - keyid: 93DBA721 02013478 RSA (Encrypt or Sign) 3072b
```

### Symmetric (passphrase only, no keypair involved)
```bash
gpg --batch --yes --pinentry-mode loopback --passphrase 'sharedsecret' --symmetric --armor -o backup.tar.gz.asc backup.tar.gz
gpg --batch --yes --pinentry-mode loopback --passphrase 'sharedsecret' --decrypt backup.tar.gz.asc
```
Useful when there's no recipient keypair at all — e.g. encrypting a local backup only you will ever decrypt, or sharing a file with someone via a passphrase communicated through a different channel (phone call, Signal). Verified: `gpg: AES256.CFB encrypted data` / `gpg: encrypted with 1 passphrase`.

### stdin / stdout piping
GPG reads/writes stdin/stdout when no file arg or `-o -` is given, so it composes in pipelines:
```bash
echo "piped secret" | gpg --trust-model always --armor -r test@example.local --encrypt \
  | gpg --batch --yes --pinentry-mode loopback --passphrase testpass123 --decrypt
```
Verified round-trip: prints `piped secret` after decrypt. Useful for encrypting command output directly (`pg_dump ... | gpg --encrypt -r backup-key -o dump.sql.gpg`) without writing an unencrypted intermediate file to disk.

### Sign *and* encrypt together
```bash
gpg --trust-model always --armor -r test@example.local --sign --encrypt -o msg.asc msg.txt
```
Proves both confidentiality (only the recipient can decrypt) and authenticity (signed by you) in one file. `--decrypt` on the other end reports both the encryption recipient and the signature status.

---

## 7. Batch Mode & Scripting

Flags that matter for any non-interactive use:

| Flag | Effect |
|---|---|
| `--batch` | Never prompt for confirmation; fail instead of asking. Required for cron/CI. |
| `--yes` | Assume yes to "overwrite file?" style prompts. |
| `--pinentry-mode loopback` | Get the passphrase from `--passphrase`/`--passphrase-file`/`--passphrase-fd` instead of popping a pinentry dialog. Required in `--batch` mode if the key is passphrase-protected. |
| `--passphrase <string>` | Passphrase on the command line — **visible in `ps`/shell history**, fine for throwaway test keys (as used throughout this doc), avoid for anything real. |
| `--passphrase-file <path>` | Read passphrase from a file's first line. |
| `--passphrase-fd <n>` | Read passphrase from an already-open file descriptor — the safest of the three for scripts, since nothing touches disk or `ps`. |

`--passphrase-fd` example, verified working:
```bash
echo "hello" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
  --sign --armor -o out.sig 3<<<"testpass123"
```

If you give `--batch --pinentry-mode loopback` but *no* passphrase source at all, GPG fails immediately rather than hanging (verified):
```
gpg: Sorry, we are in batchmode - can't get input
```
That's actually the desired failure mode for CI — no risk of a job hanging forever waiting on a TTY that doesn't exist.

A script that ends up handling a passphrase in a plaintext file (e.g. a parameter file for `--batch --gen-key`) should shred it afterward rather than just `rm` it:
```bash
shred -u keyparams.txt
```

### Persistent loopback config (skip `--pinentry-mode loopback` on every invocation)

Passing `--pinentry-mode loopback` on every single command gets old fast for a host that's always non-interactive. Set it once instead — verified working on this host (Rocky Linux 10.2):

`~/.gnupg/gpg-agent.conf`:
```
allow-loopback-pinentry
default-cache-ttl 3600
max-cache-ttl 7200
```
`~/.gnupg/gpg.conf`:
```
pinentry-mode loopback
```
```bash
gpgconf --kill gpg-agent    # pick up the new config
```
Confirmed: with these two files in place, `gpg --batch --passphrase testpass123 --sign ...` succeeds without `--pinentry-mode loopback` on the command line at all — `gpg.conf`'s setting is enough. Still combine this with `--batch --passphrase`/`--passphrase-fd` per-command as above; the config file only removes the need to also repeat `--pinentry-mode loopback` every time.

---

## 8. Pinentry Issues

This is the single most common GPG headache, especially on headless/SSH/CI hosts — signing or decrypting works fine at a desk but hangs or errors over SSH or in a script.

### `gpg: signing failed: No pinentry` / agent can't find a pinentry program

Means no `pinentry` binary is installed at all. **Confirmed on this host** — `which pinentry pinentry-curses pinentry-tty` all return nothing, and attempting an interactive-mode sign with no cached passphrase fails with exactly this error:
```
$ echo hello | gpg --batch --yes --sign -o /dev/null
gpg: signing failed: No pinentry
```
Fix — install one. On this RHEL-family host:
```bash
sudo dnf install pinentry pinentry-tty     # pinentry-tty works over plain SSH with no X/Wayland
```
`pinentry-curses`/`pinentry-tty` are the right choice for a headless VM like `shiva`; `pinentry-gnome3`/`pinentry-qt` need a desktop session and will otherwise themselves fail to find a display.

### `gpg: signing failed: Inability to communicate with agent` / stuck agent socket

Usually a stale `gpg-agent` left over from a killed session, a home directory that moved, or a socket path mismatch after `GNUPGHOME` changed. Fix:
```bash
gpgconf --kill gpg-agent     # verified: exits 0, agent respawns on next gpg invocation
```

### `Inappropriate ioctl for device` / pinentry can't find a TTY (interactive mode, not `--batch`)

Happens when `gpg --sign` is run from a shell where `GPG_TTY` isn't set to the current terminal — common right after switching terminals/tmux panes, or in a subshell. Fix:
```bash
export GPG_TTY=$(tty)
gpgconf --kill gpg-agent    # so it picks up the new TTY
```
Put the `export GPG_TTY=$(tty)` line in `~/.bashrc`/`~/.zshrc` so it's always current, not just set once per session.

### Scripts/CI: skip pinentry entirely

For anything non-interactive, don't fight pinentry at all — use `--pinentry-mode loopback` with `--passphrase-fd` (§7), or a `--no-protection` passphrase-less key generated specifically for automation (§2) with the private key itself protected by filesystem permissions / a secrets manager instead of a GPG passphrase.

---

## 9. Use Cases — Worked Examples

### Encrypt a backup file for yourself
```bash
tar czf - /etc/important-config | gpg --symmetric --armor -o config-backup-$(date +%F).tar.gz.asc
# restore:
gpg --decrypt config-backup-2026-08-20.tar.gz.asc | tar xzf -
```

### Sign a release artifact so users can verify it
```bash
gpg --detach-sign --armor -o myapp-1.0.tar.gz.asc myapp-1.0.tar.gz
# publish both files; consumer does:
gpg --verify myapp-1.0.tar.gz.asc myapp-1.0.tar.gz
```

### Verify a downloaded package against a published key
```bash
gpg --import vendor-signing-key.asc         # or: gpg --recv-keys <KEYID> --keyserver keys.openpgp.org
gpg --verify package.tar.gz.sig package.tar.gz
```

### Send someone an encrypted file when you only have their public key
```bash
gpg --import their-pubkey.asc
gpg --trust-model always --armor -r their-email@example.com --encrypt -o file.txt.asc file.txt
# they run: gpg --decrypt file.txt.asc
```

### Sign git commits/tags with a GPG key
```bash
git config --global user.signingkey <KEYID>     # from: gpg --list-secret-keys --keyid-format=long
git config --global commit.gpgsign true
git commit -S -m "signed commit"                # -S forces signing on one commit if gpgsign isn't global
```
Add the exported public key (`gpg --armor --export <KEYID>`) under Gitea/GitHub's *Settings → SSH / GPG Keys* — same UI location referenced for SSH keys in [`../../git/git-guide.md`](../../git/git-guide.md), separate key type. GitHub/Gitea then shows commits as "Verified".

### Encrypt a database dump piped straight from the source command
```bash
pg_dump mydb | gpg --trust-model always -r backup-key --encrypt -o mydb-$(date +%F).sql.gpg
```
Nothing unencrypted ever touches disk.

---

## 10. GPG + OpenSSL Interop

GPG (OpenPGP packet format) and OpenSSL (X.509/PKCS/CMS) use incompatible container formats — there's no native cross-verification between them. But nothing stops chaining them as separate pipeline stages, since signing/encryption just operates on whatever bytes it's handed.

### OpenSSL identity (for the X.509 side of a pipeline)
```bash
# Encrypted-at-rest private key (verified: ED25519 works with openssl genpkey)
openssl genpkey -algorithm ED25519 -aes256 -pass pass:testpass123 -out private.pem
# Use RSA-3072/4096 instead of ED25519 if the cert needs to work with S/MIME/Outlook — ED25519 support there is inconsistent.

# Self-signed cert (fine for personal use; get a CA-issued S/MIME cert — e.g. Actalis, which issues free personal certs — if others need to verify without manually importing yours)
openssl req -new -x509 -key private.pem -passin pass:testpass123 -out cert.pem -days 730 -subj "/CN=Dana Test"
```

### Chaining: OpenSSL encrypts, GPG signs the ciphertext
```bash
openssl enc -aes-256-cbc -pbkdf2 -pass pass:testpass123 -in file.txt -out file.enc
gpg --detach-sign --armor file.enc
```
Verify/decrypt on the other end:
```bash
gpg --verify file.enc.asc file.enc
openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:testpass123 -in file.enc
```
Verified end-to-end on this host. One gotcha hit during testing: if the signing identity's primary key is an offline-primary stub (§2), `gpg --detach-sign` with no `-u` fails with `gpg: no default secret key: Unusable secret key` — pass `-u <fingerprint>` to select the sign *subkey* explicitly.

### Use cases for combining them
- Bulk/streaming encryption (OpenSSL AES) + identity/authenticity (GPG signature) — e.g. backup pipelines to third parties.
- Bridging ecosystems: internal GPG trust for your own team, external X.509/S-MIME handoff for a partner org.
- A TLS cert (OpenSSL) distributed to a teammate via a GPG-encrypted/signed channel.
- CI/CD: OpenSSL for checksums/encryption, GPG detached signature for the release artifact end users actually verify (§9).
- Legacy/compliance interop where S/MIME is mandated on one leg of a workflow and GPG is already standard on another.

See [`../tls-pki/openssl-pki.md`](../tls-pki/openssl-pki.md) for the OpenSSL/X.509 side in depth — it's a genuinely different trust model (CA hierarchy vs. GPG's web-of-trust), not just different syntax for the same idea.

---

## 11. Shell Helper Functions (stdin pipelines)

Thin wrappers around the stdin/stdout piping shown in §6, for dropping into `.bashrc`/`.zshrc` so common GPG operations become one-word pipeline stages. All verified working against a real key on this host.

```bash
# Encrypt stdin to a recipient, armored
gpgenc() { gpg --armor --encrypt --recipient "$1"; }

# Decrypt stdin
gpgdec() { gpg --batch --pinentry-mode loopback --decrypt; }

# Clear-sign stdin
gpgsign() { gpg --batch --pinentry-mode loopback --clearsign; }

# Detached-sign stdin, armored signature only
gpgsigndetach() { gpg --batch --pinentry-mode loopback --armor --detach-sign; }

# Verify stdin
gpgverify() { gpg --verify; }

# Import a key from stdin
gpgimport() { gpg --import; }

# Symmetric (password-based) encrypt
gpgencsym() { gpg --batch --pinentry-mode loopback --symmetric --armor --cipher-algo AES256; }
```
These rely on `gpg-agent`/`gpg.conf` already having a cached passphrase or the persistent loopback config from §7 — none of them pass `--passphrase` inline, unlike most examples elsewhere on this page, so add `--passphrase "$GPG_PASS"` (or similar) to `gpgdec`/`gpgsign`/`gpgsigndetach`/`gpgencsym` if you're not relying on agent caching.

### Auto-detect input type (sniffs the PGP armor header)
```bash
gpgauto() {
    local input
    input=$(cat)
    if echo "$input" | grep -q "BEGIN PGP MESSAGE"; then
        echo "$input" | gpg --batch --pinentry-mode loopback --decrypt
    elif echo "$input" | grep -q "BEGIN PGP SIGNED MESSAGE"; then
        echo "$input" | gpg --verify
    elif echo "$input" | grep -q "BEGIN PGP PUBLIC KEY BLOCK"; then
        echo "$input" | gpg --import
    elif echo "$input" | grep -q "BEGIN PGP SIGNATURE"; then
        echo "$input" | gpg --verify
    else
        echo "No recognizable PGP block found." >&2
        return 1
    fi
}
```
Verified all four branches: encrypted message, clearsigned message, and public-key-block import all round-trip correctly. **Caveat found in testing:** the detached-signature branch (`BEGIN PGP SIGNATURE` alone, no `BEGIN PGP MESSAGE`) can't actually succeed piped through `gpgauto` as written — a detached signature has nothing to verify against without the original file as a second argument, so `gpg --verify` on just the signature fails with `gpg: no signed data`. That branch is only useful for a syntactically-recognized-but-unverifiable input; verifying a real detached signature still needs the two-argument form from §5 (`gpg --verify msg.txt.sig msg.txt`), not this function.

### Clipboard integration (Wayland/X11)
```bash
# Wayland (wl-clipboard)
gpgclip() { wl-paste | gpgauto | tee >(wl-copy); }

# X11 (xclip)
# gpgclip() { xclip -o -selection clipboard | gpgauto | tee >(xclip -selection clipboard); }
```
Not executed in testing — this shell has no live Wayland/X11 display session to verify against. Treat as an unverified convenience wrapper around the already-verified `gpgauto` above; the risky part (`gpgauto`'s branches) is confirmed, the clipboard plumbing itself is standard `wl-copy`/`xclip` usage.

---

## See Also

- [`../tls-pki/openssl-pki.md`](../tls-pki/openssl-pki.md) — OpenSSL/X.509 PKI; a different trust model (CA hierarchy) from GPG's web-of-trust, don't conflate the two
- [`../../git/git-guide.md`](../../git/git-guide.md) — SSH key setup for git auth (separate from GPG commit signing above)
- [`../ssh/`](../ssh/) — SSH key generation/distribution, if you're here for keys in general rather than GPG specifically
