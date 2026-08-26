# GPG commands

## Installation

|Distro|Command|
|---|---|
|Debian / Ubuntu|`sudo apt update && sudo apt install gnupg`|
|Fedora / RHEL / CentOS|`sudo dnf install gnupg2`|
|Arch Linux|`sudo pacman -S gnupg`|

Verify: `gpg --version`

---

## Key Management

### Generate a key pair

```bash
gpg --full-generate-key
```

Recommended options: RSA 4096-bit or ECC Curve 25519, with an expiry (e.g. `1y`).

### List keys

```bash
gpg --list-keys               # public keys
gpg --list-secret-keys        # private keys
```

### Export keys

```bash
# Public key (share this)
gpg --armor --export you@example.com > public_key.asc

# Private key (keep this safe!)
gpg --armor --export-secret-keys you@example.com > private_key.asc
```

### Import a key

```bash
gpg --import keyfile.asc
```

### Delete a key

```bash
gpg --delete-key you@example.com           # public key
gpg --delete-secret-key you@example.com    # private key
```

### Edit / extend key expiry

```bash
gpg --edit-key you@example.com
# then type: expire -> set new date -> save
```

---

## Encrypting & Decrypting

### Encrypt a message

```bash
# From stdin
echo "Secret message" | gpg --armor --encrypt --recipient you@example.com

# From a file
gpg --armor --encrypt --recipient you@example.com message.txt
# Output: message.txt.asc
```

### Encrypt for multiple recipients

```bash
gpg --armor --encrypt \
  --recipient alice@example.com \
  --recipient bob@example.com \
  message.txt
```

### Decrypt

```bash
gpg --decrypt message.txt.asc

# Save output to file
gpg --output decrypted.txt --decrypt message.txt.asc
```

### Quick end-to-end test

```bash
echo "Hello!" | gpg --armor --encrypt --recipient you@example.com | gpg --decrypt
```

---

## Signing & Verifying

### Sign a file (detached signature)

```bash
gpg --armor --detach-sign file.txt
# Output: file.txt.asc
```

### Sign and encrypt together

```bash
gpg --armor --sign --encrypt --recipient you@example.com message.txt
```

### Verify a signature

```bash
gpg --verify file.txt.asc file.txt
```

### Clearsign a message (signature wrapped around text)

```bash
gpg --clearsign message.txt
# Output: message.txt.asc (human-readable + signature)
```

---

## Keyservers

### Upload your public key

```bash
gpg --keyserver keys.openpgp.org --send-keys YOUR_KEY_ID
```

### Search for someone's key

```bash
gpg --keyserver keys.openpgp.org --search-keys alice@example.com
```

### Fetch a key by ID

```bash
gpg --keyserver keys.openpgp.org --recv-keys KEY_ID
```

---

## Revocation

### Generate a revocation certificate (do this right after key creation!)

```bash
gpg --output revoke.asc --gen-revoke you@example.com
```

> Auto-generated certs are stored in `~/.gnupg/openpgp-revocs.d/`

### Revoke a key

```bash
gpg --import revoke.asc
gpg --keyserver keys.openpgp.org --send-keys YOUR_KEY_ID
```

---

## Useful Flags

|Flag|Description|
|---|---|
|`--armor`|ASCII output instead of binary|
|`--recipient` / `-r`|Specify recipient by email or key ID|
|`--output` / `-o`|Write output to a file|
|`--sign` / `-s`|Sign the data|
|`--encrypt` / `-e`|Encrypt the data|
|`--decrypt` / `-d`|Decrypt the data|
|`--verify`|Verify a signature|
|`--fingerprint`|Show key fingerprint|

---

## Key File Locations

|Path|Contents|
|---|---|
|`~/.gnupg/`|GPG home directory|
|`~/.gnupg/pubring.kbx`|Public keyring|
|`~/.gnupg/private-keys-v1.d/`|Private keys|
|`~/.gnupg/openpgp-revocs.d/`|Revocation certificates|
