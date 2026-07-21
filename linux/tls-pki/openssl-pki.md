# OpenSSL PKI — Complete Guide

A comprehensive reference for OpenSSL: building a full CA hierarchy, individual command usage, format conversion, TLS analysis, and configuration deep-dives.

---

## 1. Concepts

### The trust hierarchy

```
Root CA  (self-signed, offline, trust anchor)
  └── Intermediate CA  (online, issues leaf certs)
        ├── Server cert   (TLS server auth)
        └── Client cert   (TLS client auth / mTLS)
```

**Why an intermediate?**
The Root CA private key is the crown jewel — if it's compromised, your entire PKI is dead. By keeping the Root offline and only using it to sign an Intermediate, you limit exposure. The Intermediate does day-to-day signing. If it's ever compromised you revoke it and issue a new one from the Root, without touching the Root key at all.

### Private Key

A private key is a large random number (or a point on an elliptic curve) that only you ever see. It has two jobs:

- **Decryption** — data encrypted with the matching public key can only be unlocked with the private key.
- **Signing** — a cryptographic signature produced by running data through the private key. Anyone with the public key can verify it came from you, but nobody can forge it without the private key.

```
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA3Tz2mr7SZiAMfQyuvBjM9Oi...
-----END RSA PRIVATE KEY-----
```

Protect this file. File permissions `400`, passphrase encryption (`-aes256`), or a hardware security module (HSM).

### Certificate (`.crt` / `.pem`)

A certificate is a public document. It bundles three things together with a CA's signature over all of them:

1. **A public key** — the counterpart to your private key, safe to share.
2. **Identity information** — the subject Distinguished Name (DN): country, organisation, Common Name, etc.
3. **Constraints and permissions** — X.509 extensions that say what the certificate may be used for, how long it is valid, which hostnames it covers (SANs), etc.

```
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIJAJC1HiIAZAiIMA0GCSqGSIb3DQ...
-----END CERTIFICATE-----
```

### Certificate Signing Request (`.csr`)

A CSR is the form you hand to a CA asking it to issue you a certificate. It contains:

1. **Your public key** — so the CA can embed it in the issued certificate.
2. **Requested identity fields** — subject DN, SANs, extensions you want.
3. **A self-signature** — proves you actually hold the private key whose public half you are submitting.

```
-----BEGIN CERTIFICATE REQUEST-----
MIICijCCAXICAQAwJTEjMCEGA1UEAwwaYWNtZS5leGFtcGxl...
-----END CERTIFICATE REQUEST-----
```

### How the three fit together

```
Your machine                        CA
--------------------------------    ----------------------------------
1. Generate private key (secret)
2. Derive public key from it
3. Bundle public key + identity
   + self-signature → CSR  ──────────────────────────────→
                                    4. Verify self-signature on CSR
                                    5. Apply policy, add extensions
                                    6. Sign with CA's private key
                           ←────────────────────────────── 7. Return certificate
8. Deploy: certificate (public)
           + private key (secret)
```

The private key never leaves your machine. Together the cert and key let your server prove its identity during a TLS handshake.

### Key files you will produce

| File | Type | Created by |
|---|---|---|
| `*.key` | Private key — never leaves the entity that owns it | `openssl genrsa` |
| `*.csr` | Certificate Signing Request — public key + identity, sent to CA | `openssl req -new` |
| `*.crt` | Signed certificate — public key + identity + CA's signature | `openssl ca` or `openssl x509` |
| `chain.crt` | Concatenation of intermediate + root | `cat` |

### File extensions you will encounter

| Extension | Encoding | Typical contents |
|---|---|---|
| `.pem` | Base64 (ASCII) | Any of the above; look at the `-----BEGIN ...-----` header |
| `.crt` | Usually PEM | Certificate |
| `.cer` | PEM or DER | Certificate (Windows convention) |
| `.key` | PEM | Private key |
| `.csr` | PEM | Certificate signing request |
| `.der` | Binary | Certificate or key in raw DER encoding |
| `.p12` / `.pfx` | Binary | PKCS#12 bundle: certificate + private key + optional chain |
| `.p7b` / `.p7c` | PEM or DER | PKCS#7 certificate chain (no private key) |

### The three OpenSSL subcommands you use most

| Command | What it does |
|---|---|
| `openssl genrsa` | Generate an RSA private key |
| `openssl req` | Create a CSR, or self-sign a cert (`-x509`) |
| `openssl ca` | CA signs a CSR → produces a signed cert, updates `index.txt` and `serial` |

---

## 2. Algorithms Reference

### Asymmetric algorithms (key pairs)

#### RSA

The classic algorithm. Security rests on the difficulty of factoring large integers.

| Key size | Security level | Use today? |
|---|---|---|
| 1024 bit | ~80 bit — broken | No |
| 2048 bit | ~112 bit | Minimum acceptable |
| 3072 bit | ~128 bit | Recommended if staying with RSA |
| 4096 bit | ~140 bit | Recommended for CA keys |

Larger RSA keys make signing and decryption noticeably slower. 4096-bit is suitable for CA certificates (signed rarely) but may be overkill for high-traffic TLS leaf certificates.

```bash
openssl genrsa -aes256 -out ca.key 4096   # CA key — large, encrypted
openssl genrsa -out server.key 2048        # Leaf — smaller, faster handshakes
```

#### ECDSA (Elliptic Curve DSA)

Equivalent security to RSA at a fraction of the key size. Preferred for new deployments.

| Curve | Equivalent RSA | Notes |
|---|---|---|
| `prime256v1` (P-256) | ~3072-bit RSA | Fast, universally supported, default in TLS 1.3 |
| `secp384r1` (P-384) | ~7680-bit RSA | NSA Suite B; slightly slower |
| `secp521r1` (P-521) | >15360-bit RSA | Maximum security; rare in practice |
| `X25519` | ~3072-bit RSA | Key exchange only (not signing); fastest, used in TLS 1.3 |

```bash
openssl ecparam -name prime256v1 -genkey -noout -out ec.key
openssl ecparam -name secp384r1  -genkey -noout -out ec384.key
```

#### EdDSA (Ed25519, Ed448)

A newer elliptic curve scheme with no random nonce required per signature — immune to a class of implementation bugs that caused real-world key leaks (e.g. the Sony PlayStation 3 incident).

```bash
openssl genpkey -algorithm Ed25519 -out ed25519.key
openssl genpkey -algorithm Ed448   -out ed448.key
```

Ed25519 is increasingly supported in TLS 1.3 and SSH. Excellent choice for new internal PKIs.

### Symmetric algorithms (key-at-rest encryption and TLS session data)

| Algorithm | Key size | Notes |
|---|---|---|
| AES-128-GCM | 128 bit | Fast, authenticated, standard |
| AES-256-GCM | 256 bit | Stronger; use for sensitive key storage |
| AES-256-CBC | 256 bit | Older mode; no built-in authentication tag |
| ChaCha20-Poly1305 | 256 bit | Faster than AES on CPUs without AES-NI; common in TLS 1.3 |
| 3DES | 112 bit effective | Legacy only — deprecated in TLS 1.3 |
| DES | 56 bit — broken | Never use |

When you pass `-aes256` to `openssl genrsa`, the private key file is encrypted with AES-256-CBC using a passphrase-derived key.

### Digest / hash algorithms

| Algorithm | Output | Use today? |
|---|---|---|
| MD5 | 128 bit | No — collision attacks demonstrated |
| SHA-1 | 160 bit | No — deprecated by all browsers since 2017 |
| SHA-256 | 256 bit | Yes — standard baseline |
| SHA-384 | 384 bit | Yes — pair with P-384 keys |
| SHA-512 | 512 bit | Yes — rarely necessary |
| SHA3-256/512 | 256/512 bit | OpenSSL 1.1.1+; not yet mainstream in PKI |

Always specify `-sha256` or stronger. Never let OpenSSL default to SHA-1.

### Algorithm selection guide 

| Use case | Recommended choice |
|---|---|
| Root CA key | RSA-4096 or P-384 |
| Intermediate CA key | RSA-4096 or P-384 |
| TLS server leaf key | P-256 (ECDSA) or RSA-2048 |
| mTLS client key | P-256 or Ed25519 |
| Certificate digest | SHA-256 minimum; SHA-384 for P-384 keys |
| Key-at-rest encryption | AES-256 |
| Avoid entirely | MD5, SHA-1, DES, 3DES, RSA-1024 |

---

## 3. Key Generation

### RSA private key

```bash
openssl genrsa \
  -aes256 \       # Encrypt the key at rest using AES-256. Prompts for a passphrase.
                  # Omit this flag to produce an unencrypted key.
  -out ca.key \   # Write the key to this file.
  4096            # Key size in bits. 4096 for CAs; 2048 is the practical minimum for leaves.
```

### EC (elliptic curve) private key

```bash
openssl ecparam \
  -name prime256v1 \  # Named curve. prime256v1 = NIST P-256. Also: secp384r1, secp521r1.
  -genkey \           # Generate a key using the selected curve.
  -noout \            # Do not print the curve parameters — only the key.
  -out ec.key
```

### EdDSA key

```bash
openssl genpkey -algorithm Ed25519 -out ed25519.key
openssl genpkey -algorithm Ed448   -out ed448.key
```

### Strip a passphrase from an existing key

```bash
openssl rsa \
  -in encrypted.key \   # Passphrase-protected key.
  -out plain.key        # Decrypted key. Prompted for the current passphrase.
```

### Add a passphrase to an existing key

```bash
openssl rsa -in root.key -aes256 -out root.key.enc
```

---

## 4. Certificate Signing Requests (CSR)

### Generate a CSR from an existing key

```bash
openssl req \
  -new \                  # Create a new CSR (not a self-signed cert).
  -key server.key \       # Use this private key. The public key is embedded in the CSR.
  -out server.csr \
  -sha256 \               # Sign the CSR itself with SHA-256.
  -subj "/C=DE/ST=Bavaria/L=Munich/O=Acme Corp/OU=Ops/CN=acme.example.com"
  #        C  : Country code (2-letter ISO 3166-1 alpha-2)
  #        ST : State or province (full name)
  #        L  : Locality (city)
  #        O  : Organization name
  #        OU : Organizational unit
  #        CN : Common Name — primary hostname or identity being certified
```

### Generate a key and CSR in one step

```bash
openssl req \
  -newkey rsa:4096 \      # Generate a new RSA-4096 key at the same time.
  -keyout server.key \    # Write the newly generated key here.
  -nodes \                # No DES — do NOT encrypt the private key.
                          # Useful for servers that must start without a passphrase prompt.
  -out server.csr \
  -sha256 \
  -subj "/CN=acme.example.com"
```

### Add Subject Alternative Names (SAN) to a CSR

```bash
openssl req \
  -new \
  -key server.key \
  -out server.csr \
  -sha256 \
  -config san.cnf         # Config file with [req] and [req_ext] sections defining SANs.
```

---

## 5. Self-Signed Certificates

### Quick self-signed certificate (dev/testing only)

```bash
openssl req \
  -x509 \                 # Output a self-signed X.509 certificate instead of a CSR.
  -newkey rsa:4096 \
  -keyout self.key \
  -out self.crt \
  -days 365 \
  -nodes \
  -sha256 \
  -subj "/CN=localhost"
```

### Self-signed cert with SANs

```bash
openssl req \
  -x509 \
  -newkey rsa:4096 \
  -keyout self.key \
  -out self.crt \
  -days 365 \
  -nodes \
  -sha256 \
  -extensions v3_req \    # Apply the [v3_req] section from the config.
  -config san.cnf
```

---

## 6. The Config File — Deep Dive

Save this as `openssl.cnf` in your working directory. Every `openssl` command in the PKI walkthrough passes `-config openssl.cnf`.

```ini
# ============================================================
# [ ca ] — Entry point for the `openssl ca` subcommand
# ============================================================
[ ca ]
default_ca = CA_default
# OpenSSL reserved: `default_ca` tells `openssl ca` which section
# contains the actual CA settings. Must point to a section in this file.

# ============================================================
# [ CA_default ] — Main CA configuration
# ============================================================
[ CA_default ]
dir               = .
# `dir` is an OpenSSL macro variable. Reference it below as $dir.
# Here it means "current directory". For production use a full path
# like /etc/pki/ca instead of `.`

database          = $dir/index.txt
# Reserved: path to the CA's certificate database (flat text file).
# Must exist and be EMPTY before first use. `openssl ca` reads
# and writes this file on every signing operation.

serial            = $dir/serial
# Reserved: file containing the next serial number in hex.
# OpenSSL increments this after each signing.

new_certs_dir     = $dir
# Reserved: where `openssl ca` writes a copy of each signed cert,
# named <serial>.pem. Must be a writable directory.

certificate       = $dir/root.crt
# Reserved: the CA's own certificate. Used to stamp the issuer field.

private_key       = $dir/root.key
# Reserved: the CA's private key. Must match `certificate`.

default_md        = sha256
# Reserved: default message digest algorithm.

default_days      = 365
# Reserved: how many days a signed cert is valid for.

default_crl_days  = 30
# How many days until the next CRL must be issued.

policy            = policy_loose
# Reserved: points to a [ policy_* ] section.

copy_extensions   = copy
# Reserved: copies X.509v3 extensions from the CSR into the signed cert.
# Required for SANs submitted in the CSR to survive signing.
# Values: none | copy | copyall
# WARNING: only use "copy" if you control the CSRs — it copies ALL
# extensions, including potentially dangerous ones like basicConstraints.

preserve          = no
# "no" = use the DN field order defined in policy (recommended for strict CAs).

email_in_dn       = no
# Email in the DN is deprecated; suppresses the warning.

name_opt          = ca_default
# How to format the subject DN in output.

cert_opt          = ca_default
# How to display certificate fields in output.

# x509_extensions = usr_cert
# Uncomment to set a default extension section for all signed certs.
# Overridden per-signing with -extensions on the command line.

# ============================================================
# [ policy_strict ] — For signing intermediate CAs
# Requires subject fields to match the signing CA.
# ============================================================
[ policy_strict ]
countryName             = match     # Must match the CA's own country.
stateOrProvinceName     = match     # Must match the CA's state.
organizationName        = match     # Must match the CA's org.
organizationalUnitName  = optional
commonName              = supplied  # Must be present in the CSR.
emailAddress            = optional

# ============================================================
# [ policy_loose ] — For signing end-entity (leaf) certificates
# ============================================================
[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
commonName              = supplied
# `supplied` means the field MUST be present in the CSR.
# `optional` means it may or may not be present.
# `match` means it must equal the CA's own field.
emailAddress            = optional

# ============================================================
# [ req ] — Configuration for `openssl req` (CSR / self-sign)
# ============================================================
[ req ]
default_bits        = 2048
# Key size when generating a key inline with `openssl req`. Fallback only —
# we use `openssl genrsa` separately.

default_md          = sha256

distinguished_name  = req_distinguished_name
# Reserved: points to the section defining DN fields.

prompt              = no
# Reserved: when `no`, OpenSSL reads DN values from the config.
# Set to `yes` for interactive prompts.

string_mask         = utf8only
# Only allow UTF-8 strings in DNs (recommended).

req_extensions      = v3_req
# Extensions to embed in CSRs. The CA may or may not honour these
# depending on its copy_extensions setting.

# ============================================================
# [ req_distinguished_name ] — Default DN for CSRs
# ============================================================
[ req_distinguished_name ]
C  = US
ST = New Jersey
O  = Operative Inc
CN = Operative Inc. CA
# These are the X.509 Distinguished Name attributes used when prompt=no.
# Override per-command with -subj "/C=US/CN=myserver.local"

# ============================================================
# [ v3_ca ] — X.509v3 extensions for the Root CA cert
# ============================================================
[ v3_ca ]
subjectKeyIdentifier   = hash
# Fingerprint of the public key. For a self-signed root, points to itself.

authorityKeyIdentifier = keyid:always,issuer
# Points back to the key that signed this cert.

basicConstraints       = critical, CA:true
# THE most important extension. CA:true means this cert may sign other certs.
# `critical` means clients MUST understand and enforce this.

keyUsage               = critical, digitalSignature, keyCertSign, cRLSign
# keyCertSign: allowed to sign certificates.
# cRLSign: allowed to sign Certificate Revocation Lists.
# digitalSignature: for OCSP responses and similar.

# ============================================================
# [ v3_intermediate_ca ] — Extensions for Intermediate CA
# ============================================================
[ v3_intermediate_ca ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints       = critical, CA:true, pathlen:0
# pathlen:0 means this CA can sign end-entity certs but CANNOT
# sign another CA cert below it. Prevents rogue sub-CAs.
keyUsage               = critical, digitalSignature, keyCertSign, cRLSign

# ============================================================
# [ server_cert ] — Extensions for server (TLS) certificates
# ============================================================
[ server_cert ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
basicConstraints       = CA:false
# Explicitly marks this as a leaf cert — cannot sign other certs.

keyUsage               = critical, digitalSignature, keyEncipherment
# digitalSignature: used in TLS handshake (TLS 1.3, ECDHE cipher suites).
# keyEncipherment: used in RSA key exchange (TLS 1.2 and older).

extendedKeyUsage       = serverAuth
# Restricts to TLS server authentication. Browsers and TLS clients enforce this.

subjectAltName         = @alt_names
# Modern TLS ignores CN for hostname validation — SANs are mandatory.
# Without a matching SAN, browsers reject the cert.

[ alt_names ]
DNS.1 = myserver.local
DNS.2 = www.myserver.local
# Add more: DNS.3 = ..., IP.1 = 192.168.1.10

# ============================================================
# [ client_cert ] — Extensions for client certificates (mTLS)
# ============================================================
[ client_cert ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
basicConstraints       = CA:false
keyUsage               = critical, digitalSignature
# Client certs only need digitalSignature — no keyEncipherment.

extendedKeyUsage       = clientAuth
# Restricts to TLS client authentication. Servers check for this EKU in mTLS.

# ============================================================
# [ v3_req ] — Extensions embedded in CSRs
# ============================================================
[ v3_req ]
# Embedded in CSRs. The CA may or may not honour these when signing.
basicConstraints       = CA:false
keyUsage               = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName         = @alt_names   # Requires copy_extensions=copy on the CA side.
```

---

## 7. OpenSSL Config Syntax — Reserved Words

### Section headers

```ini
[ section_name ]
```

Square brackets define a named section. Commands look up specific sections by convention (`[ ca ]`, `[ req ]`). Your own sections (like `[ alt_names ]`) are referenced by other sections with `@section_name`.

### Variable substitution

```ini
dir = /etc/pki
certificate = $dir/ca.crt    # expands to /etc/pki/ca.crt
```

`$variable` or `${variable}` expands a previously defined key in the same section. `$ENV::HOME` reads environment variables.

### Top-level reserved section names

| Section | Used by command | Purpose |
|---|---|---|
| `[ ca ]` | `openssl ca` | Entry point; must define `default_ca` |
| `[ req ]` | `openssl req` | Controls CSR and self-sign behavior |
| `[ tsa ]` | `openssl ts` | Timestamp authority (not covered here) |
| `[ ocsp ]` | `openssl ocsp` | OCSP responder config |

### Reserved keys inside `[ CA_default ]`

| Key | Type | Meaning |
|---|---|---|
| `dir` | path | Base directory, usable as `$dir` |
| `database` | path | `index.txt` — CA cert database |
| `serial` | path | Hex serial counter file |
| `new_certs_dir` | path | Where signed certs are copied as `<serial>.pem` |
| `certificate` | path | CA's own cert |
| `private_key` | path | CA's private key |
| `default_md` | string | Hash algorithm: `sha256`, `sha384`, `sha512` |
| `default_days` | int | Cert validity period |
| `default_crl_days` | int | Days until next CRL is due |
| `policy` | section ref | Points to a `[ policy_* ]` section |
| `copy_extensions` | enum | `none` / `copy` / `copyall` |
| `x509_extensions` | section ref | Default extension section for signed certs |
| `preserve` | bool | Preserve DN field order from CSR |
| `email_in_dn` | bool | Whether to include email in the DN |
| `unique_subject` | bool | `no` allows re-issuing certs for the same CN |

### Reserved keys inside `[ req ]`

| Key | Meaning |
|---|---|
| `default_bits` | RSA key size |
| `default_md` | Digest algorithm |
| `distinguished_name` | Points to DN section |
| `prompt` | `yes` = interactive, `no` = read from config |
| `req_extensions` | Extension section to embed in the CSR |
| `x509_extensions` | Extensions for self-signed certs (`-x509` flag) |
| `string_mask` | Character encoding: `utf8only` recommended |

### Policy field values

| Value | Meaning |
|---|---|
| `match` | CSR field must equal the CA's own field |
| `supplied` | CSR field must be present (any value) |
| `optional` | CSR field may be absent |

### X.509v3 extension critical flag

Prefixing any extension value with `critical,` means:

> Any client that does not understand this extension MUST reject the certificate.

Use it on `basicConstraints` and `keyUsage`. Do not use it on `subjectAltName` — older clients might not understand it.

### keyUsage values

| Value | Meaning |
|---|---|
| `digitalSignature` | Sign data (TLS handshake, code signing) |
| `keyEncipherment` | Encrypt a key (RSA key exchange) |
| `dataEncipherment` | Encrypt data directly (rare) |
| `keyAgreement` | Used in ECDH |
| `keyCertSign` | Sign certificates — CA only |
| `cRLSign` | Sign revocation lists — CA only |
| `nonRepudiation` | Legal/audit use |

### extendedKeyUsage values

| Value | OID shorthand | Meaning |
|---|---|---|
| `serverAuth` | 1.3.6.1.5.5.7.3.1 | TLS server |
| `clientAuth` | 1.3.6.1.5.5.7.3.2 | TLS client |
| `codeSigning` | 1.3.6.1.5.5.7.3.3 | Code signing |
| `emailProtection` | 1.3.6.1.5.5.7.3.4 | S/MIME email |
| `timeStamping` | 1.3.6.1.5.5.7.3.8 | Timestamp authority |
| `OCSPSigning` | 1.3.6.1.5.5.7.3.9 | OCSP responder |

---

## 8. Bootstrap

```bash
# Create and enter your working directory — everything lives flat here
mkdir ~/pki && cd ~/pki

# CA bookkeeping files
touch index.txt       # must be empty — not even a newline
echo 1000 > serial    # starting serial in hex
```

`index.txt` is a tab-delimited database of every cert ever signed by this CA. Each row: `status expiry revocation_date serial filename DN`

`serial` is read before each signing and incremented after. OpenSSL writes a copy of the signed cert to `./<serial>.pem` automatically.

---

## 9. Root CA

### 9.1 Generate the Root CA private key

```bash
openssl genrsa -out root.key 4096
```

4096 bits for the Root — it has a 10-year lifetime so the extra strength matters. For leaf certs 2048 is fine and faster.

### 9.2 Self-sign the Root CA certificate

```bash
openssl req -config openssl.cnf \
  -key root.key \
  -new -x509 \
  -days 3650 \
  -extensions v3_ca \
  -out root.crt
```

| Flag | Meaning |
|---|---|
| `-x509` | Produce a self-signed cert directly instead of a CSR |
| `-days 3650` | 10 years — root CAs live long |
| `-extensions v3_ca` | Apply the `[ v3_ca ]` extension block |

### 9.3 Inspect the Root CA cert

```bash
openssl x509 -in root.crt -noout -text | grep -A4 "Basic Constraints"
# Expect: CA:TRUE

openssl x509 -in root.crt -noout -subject -issuer
# subject and issuer should be identical — it's self-signed
```

---

## 10. Intermediate CA

### 10.1 Generate the Intermediate private key

```bash
openssl genrsa -out intermediate.key 4096
```

### 10.2 Create a CSR for the Intermediate

```bash
openssl req -config openssl.cnf \
  -subj "/C=US/ST=New Jersey/O=Operative Inc/CN=Operative INC intermediate CA" \
  -key intermediate.key \
  -new \
  -out intermediate.csr
```

`-subj` overrides the DN from the config inline — useful when a single config file serves multiple entities with different names.

### 10.3 Root CA signs the Intermediate

```bash
openssl ca -config openssl.cnf \
  -extensions v3_intermediate_ca \
  -days 1825 \
  -notext \
  -in intermediate.csr \
  -out intermediate.crt
```

| Flag | Meaning |
|---|---|
| `-extensions v3_intermediate_ca` | Apply pathlen:0 and CA:true |
| `-days 1825` | 5 years — shorter than root, longer than leaf |
| `-notext` | Don't prepend human-readable text to the cert file |

OpenSSL will ask:

```
Sign the certificate? [y/n]: y
1 out of 1 certificate requests certified, commit? [y/n]: y
```

### 10.4 Verify the Intermediate

```bash
openssl verify -CAfile root.crt intermediate.crt
# intermediate.crt: OK

openssl x509 -in intermediate.crt -noout -text | grep -A4 "Basic Constraints"
# Expect: CA:TRUE, pathlen:0
```

### 10.5 Build the chain file

```bash
cat intermediate.crt root.crt > chain.crt
```

The chain file is served by TLS servers alongside the leaf cert so clients can build the trust path without fetching intermediate certs separately. Order matters: leaf-issuer first, root last.

---

## 11. Server Certificate

### 11.1 Generate the server private key

```bash
openssl genrsa -out server.key 2048
```

### 11.2 Create the CSR

```bash
openssl req -config openssl.cnf \
  -subj "/C=US/ST=Alabama/O=Operative INC/CN=myserver.local" \
  -key server.key \
  -new \
  -out server.csr
```

> **SANs note:** If you need SANs different from what's in `[ alt_names ]`, edit `[ alt_names ]` before running this command, or pass a separate extensions config via `-reqexts`.

### 11.3 Intermediate CA signs the server cert

```bash
openssl ca -config openssl.cnf \
  -cert intermediate.crt \
  -keyfile intermediate.key \
  -extensions server_cert \
  -days 365 \
  -notext \
  -in server.csr \
  -out server.crt
```

`-cert` and `-keyfile` override the `certificate` and `private_key` values from `[ CA_default ]`, letting the Intermediate act as CA without changing the config file.

### 11.4 Verify the server cert

```bash
# Full chain verification
openssl verify -CAfile root.crt -untrusted intermediate.crt server.crt
# server.crt: OK

# Check extensions
openssl x509 -in server.crt -noout -text | grep -A3 "Extended Key Usage"
# TLS Web Server Authentication

openssl x509 -in server.crt -noout -text | grep -A4 "Subject Alternative"
# DNS:myserver.local

# Confirm key matches cert (hashes must be identical)
openssl x509 -noout -modulus -in server.crt | openssl md5
openssl rsa  -noout -modulus -in server.key | openssl md5
```

---

## 12. Client Certificate

### 12.1 Generate client key and CSR

```bash
openssl genrsa -out client.key 2048

openssl req -config openssl.cnf \
  -subj "/C=RU/ST=Moscow/O=KGB/CN=KGB clients" \
  -key client.key \
  -new \
  -out client.csr
```

### 12.2 Intermediate CA signs the client cert

```bash
openssl ca -config openssl.cnf \
  -cert intermediate.crt \
  -keyfile intermediate.key \
  -extensions client_cert \
  -days 365 \
  -notext \
  -in client.csr \
  -out client.crt
```

### 12.3 Verify the client cert

```bash
openssl verify -CAfile root.crt -untrusted intermediate.crt client.crt
# client.crt: OK

openssl x509 -in client.crt -noout -text | grep -A3 "Extended Key Usage"
# TLS Web Client Authentication
```

---

## 13. Additional CA Operations

### Sign with a one-liner (no CA database)

```bash
openssl x509 \
  -req \                    # Input is a CSR, not an existing cert.
  -in server.csr \
  -CA ca.crt \              # CA certificate.
  -CAkey ca.key \           # CA private key.
  -CAcreateserial \         # Create a serial file (ca.srl) if it doesn't exist.
                            # The serial increments automatically on each signing.
  -out server.crt \
  -days 365 \
  -sha256 \
  -extfile ext.cnf \        # File containing X.509 extensions to embed.
  -extensions server_cert
```

Use this for simple one-off signing without maintaining an `index.txt` database.

### Sign non-interactively

```bash
openssl ca -config openssl.cnf \
  -in server.csr \
  -out server.crt \
  -days 365 \
  -notext \
  -md sha256 \
  -extensions server_cert \
  -batch                    # Skip "Sign the certificate? [y/n]" prompt.
```

### Revoke a certificate and update the CRL

```bash
# Revoke
openssl ca \
  -config openssl.cnf \
  -revoke server.crt \
  -crl_reason keyCompromise
  # Reason codes: unspecified, keyCompromise, CACompromise,
  # affiliationChanged, superseded, cessationOfOperation,
  # certificateHold, removeFromCRL

# Generate a new CRL
openssl ca \
  -config openssl.cnf \
  -gencrl \
  -out ca.crl \
  -crldays 30
```

---

## 14. Inspecting Certificates and Keys

### Inspect a certificate

```bash
openssl x509 -in server.crt -noout -text
```

### Print specific fields only

```bash
openssl x509 -in server.crt -noout -subject
openssl x509 -in server.crt -noout -issuer
openssl x509 -in server.crt -noout -dates
openssl x509 -in server.crt -noout -serial
openssl x509 -in server.crt -noout -fingerprint -sha256
```

### Inspect a CSR

```bash
openssl req -in server.csr -noout -text
# Prints subject, public key, and requested extensions.
```

### Inspect a private key

```bash
openssl rsa \
  -in server.key \
  -noout \
  -text \     # Print modulus, exponents, and primes.
  -check      # Verify the key's internal consistency.
```

### Check that a key, CSR, and certificate all match

```bash
# All three hashes must be identical:
openssl rsa  -noout -modulus -in server.key | openssl md5
openssl req  -noout -modulus -in server.csr | openssl md5
openssl x509 -noout -modulus -in server.crt | openssl md5
```

---

## 15. Format Conversion

### PEM → DER (binary)

```bash
openssl x509 -in server.crt -out server.der -outform DER
```

### DER → PEM

```bash
openssl x509 -in server.der -inform DER -out server.crt -outform PEM
```

### PEM certificate + key → PKCS#12 (for browsers, Java, Windows)

```bash
openssl pkcs12 \
  -export \
  -out bundle.p12 \
  -inkey server.key \
  -in server.crt \
  -certfile ca.crt \          # Optional: include the CA chain.
  -name "My Server Cert"      # Friendly name visible in certificate managers.
  # Prompted for an export password.
```

### PKCS#12 → PEM (extract certificate and key)

```bash
openssl pkcs12 -in bundle.p12 -nokeys -out server.crt
openssl pkcs12 -in bundle.p12 -nocerts -nodes -out server.key
```

---

## 16. Verification

### 16.1 The verify command — how it works

```bash
openssl verify -CAfile <trust-anchor> [-untrusted <intermediate>] <cert>
```

| Flag | Role |
|---|---|
| `-CAfile` | The **trust anchor** — what you ultimately trust. Must be the root. |
| `-untrusted` | Certs used to **build the chain** but not blindly trusted. Typically the intermediate. The word "untrusted" means "not a trust anchor", not "invalid". |

OpenSSL walks the chain upward:

```
cert → signed by intermediate? ✓
intermediate → signed by root? ✓
root → in -CAfile? ✓
→ OK
```

If any link is missing it fails with `unable to get issuer certificate`, even if the links it could verify were valid.

### 16.2 Common verify commands

```bash
# Verify intermediate against root
openssl verify -CAfile root.crt intermediate.crt

# Verify a leaf cert against the full chain
openssl verify -CAfile root.crt -untrusted intermediate.crt server.crt
openssl verify -CAfile root.crt -untrusted intermediate.crt client.crt

# Verify using the pre-built chain file
openssl verify -CAfile chain.crt server.crt

# WRONG — intermediate can't verify itself
openssl verify -CAfile intermediate.crt client.crt
```

### 16.3 Inspect the full chain at once

```bash
openssl crl2pkcs7 -nocrl \
  -certfile chain.crt \
  -certfile server.crt \
  -certfile client.crt | \
  openssl pkcs7 -print_certs -noout
```

Expected output — subjects and issuers form an unbroken chain:

```
subject=... intermediate CA    issuer=... Root CA
subject=... Root CA            issuer=... Root CA    ← self-signed
subject=... server             issuer=... intermediate CA
subject=... client             issuer=... intermediate CA
```

### 16.4 Confirm a key matches its certificate

```bash
openssl x509 -noout -modulus -in server.crt | openssl md5
openssl rsa  -noout -modulus -in server.key | openssl md5
```

If they differ, the key and cert were not generated together — the cert is unusable.

### 16.5 Test a live mTLS connection

```bash
# Terminal 1 — spin up a TLS server
openssl s_server \
  -cert server.crt \
  -key server.key \
  -CAfile root.crt \
  -chainfile chain.crt \
  -Verify 1 \           # Require and verify a client cert (mTLS)
  -port 4433

# Terminal 2 — connect as a client presenting the client cert
openssl s_client \
  -connect localhost:4433 \
  -cert client.crt \
  -key client.key \
  -CAfile root.crt
```

### 16.6 Test a live server with SNI

```bash
openssl s_client \
  -connect acme.example.com:443 \
  -servername acme.example.com \    # SNI hostname sent in the TLS ClientHello.
  -CAfile ca.crt \                  # Trust anchor. Omit to use system CAs.
  -showcerts \                      # Print the full certificate chain.
  -verify_return_error              # Exit non-zero if verification fails.
```

### 16.7 Check certificate expiry on a live server

```bash
echo | openssl s_client \
  -connect acme.example.com:443 \
  -servername acme.example.com 2>/dev/null \
| openssl x509 -noout -dates
```

### 16.8 Test SMTP with STARTTLS

```bash
openssl s_client \
  -connect mail.example.com:587 \
  -starttls smtp \    # Negotiate STARTTLS before going encrypted.
  -crlf               # Translate LF to CRLF (required by SMTP).
```

### 16.9 Generate a random secret / token

```bash
openssl rand -hex 32       # 32 bytes = 256 bits, hex output
openssl rand -base64 32    # Base64 output
```

### 16.10 Benchmark digest performance

```bash
openssl speed sha256 rsa2048
```

---

## 17. TLS Analysis & Certificate Trust Setup for Internal APIs

### Overview

This section covers how to:
1. Analyze TLS termination from curl verbose output
2. Inspect the certificate chain
3. Extract and save the chain
4. Make curl trust an internal corporate CA

### 17.1 Analyzing TLS from curl Verbose Output

When working with internal APIs behind a reverse proxy, `curl -vvv` (or `-v`) gives enough information to understand the full TLS picture without needing a packet capture.

#### Running a verbose request

```bash
curl -k -v -X POST 'https://api.internal.example.com/auth-api/v1/generate-token' \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/x-www-form-urlencoded'
```

The `-k` flag skips certificate verification initially — useful for exploration before trusting the CA.

#### What to look for

**TLS stack (client OS)**
```
# Linux/OpenSSL
SSL connection using TLSv1.3 / TLS_AES_128_GCM_SHA256 / X25519 / RSASSA-PSS
CAfile: /etc/pki/tls/certs/ca-bundle.crt

# Windows/schannel
schannel: disabled automatic use of client certificate
```

**Where TLS is terminated**
```
* Connected to api.internal.example.com (10.x.x.x) port 443
* X-Application-Context: backend-service:profile:PORT
```

If the resolved IP is shared across multiple subdomains (dev, qa, stg, prod), and a backend context header leaks the internal port, TLS is being terminated at a **reverse proxy / load balancer**, not at the application itself. The proxy decrypts HTTPS and forwards plain HTTP internally.

**ALPN negotiation**
```
ALPN: curl offers h2,http/1.1
ALPN: server did not agree on a protocol. Uses default.
```
The proxy accepts TLS but doesn't support HTTP/2 — it falls back to HTTP/1.1. Typical of older load balancers not configured for h2.

**Backend latency**
Compare the timestamp when the request is sent vs when the first response byte arrives. A gap of several seconds with a fast TLS handshake (~120ms) points to a slow backend, not a network issue.

#### Environment comparison

By running the same request against multiple environments (dev, qa, stg) and comparing verbose output:

| Signal | What it tells you |
|---|---|
| Same resolved IP across subdomains | Shared proxy fronts all environments |
| Same certificate SAN list | One cert covers all environments, SNI-based routing |
| HSTS present on some endpoints but not others | Header injected by backend app, not proxy |
| `X-Application-Context` header | Backend app name and internal port |
| `Transfer-Encoding: chunked` vs `Content-Length` | Different backend apps, different response strategies |

#### HSTS inconsistency — a security note

If a data API endpoint returns `Strict-Transport-Security` but an auth endpoint on the same host does not, the header is likely being set by the **backend application**, not the proxy. The auth endpoint (where credentials travel) arguably needs HSTS more than the data API.

---

### 17.2 Inspecting the Certificate Chain

#### View the full chain from the server

```bash
openssl s_client -connect api.internal.example.com:443 -showcerts 2>/dev/null < /dev/null
```

A typical internal PKI chain looks like:

```
Certificate level 0 (leaf):         CN=api.internal.example.com
Certificate level 1 (intermediate): CN=Corp Enterprise TLS Issuing CA
Certificate level 2 (root):         CN=Corp Enterprise Root CA
```

#### Check subject and issuer quickly

```bash
openssl s_client -connect api.internal.example.com:443 -showcerts 2>/dev/null < /dev/null \
  | grep -E "subject|issuer"
```

#### Key things to check

- **SAN (Subject Alternative Names):** confirms which hostnames the cert is valid for
- **Validity window:** check `start date` / `expire date`
- **Issuer chain:** determines whether this is a public CA or internal PKI
- **Self-signed warning:** `self-signed certificate in certificate chain (19)` means the root CA is not in your system trust store — not that the leaf cert itself is self-signed

---

### 17.3 Extracting and Saving the Chain

#### Pull all certs into a single bundle file

```bash
openssl s_client -connect api.internal.example.com:443 \
  -showcerts 2>/dev/null < /dev/null \
  | awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' \
  > corp-chain.pem
```

Saves the full chain (leaf + intermediate + root) concatenated into one PEM file.

#### Split into individual files (optional, for inspection)

```bash
openssl s_client -connect api.internal.example.com:443 \
  -showcerts 2>/dev/null < /dev/null \
  | csplit - '/END CERTIFICATE/+1' '{*}' --prefix=cert --suffix-format='%02d.pem' 2>/dev/null
# Produces cert00.pem (leaf), cert01.pem (intermediate), cert02.pem (root)
```

#### Inspect a specific cert

```bash
openssl x509 -in cert02.pem -text -noout | grep -E "Subject|Issuer|Not Before|Not After|DNS:"
```

---

### 17.4 Making curl Trust the Bundle

#### Why system cert stores may not work

On **Cygwin**, curl typically ignores the Windows certificate store entirely and uses its own CA bundle. Installing a cert into Windows (`certutil` or MMC) has no effect on Cygwin curl. The same applies to many other bundled curl builds — they ship with their own CA bundle path.

#### Find where your curl looks for CAs

```bash
curl-config --ca
# e.g. /etc/pki/tls/certs/ca-bundle.crt
```

#### Option A — Point curl at your bundle per request

```bash
curl --cacert corp-chain.pem https://api.internal.example.com/...
```

#### Option B — Set for the session

```bash
export CURL_CA_BUNDLE=/path/to/corp-chain.pem
```

#### Option C — Make it permanent (append to curl's default bundle)

```bash
cat corp-chain.pem >> $(curl-config --ca)
```

After this, curl verifies the internal API without `-k` or `--cacert` in any future request.

#### Verifying it worked

Drop the `-k` flag and look for:

```
* subjectAltName: host "api.internal.example.com" matched cert's "api.internal.example.com"
* SSL certificate verify ok.
```

Instead of the previous:
```
* SSL certificate verify result: self-signed certificate in certificate chain (19)
```

---

### Summary

```
curl -vvv (with -k)
    → Reveals: proxy IP, TLS version, ALPN, backend headers, latency
    → Reveals: cert subject, issuer, SANs, chain depth

openssl s_client -showcerts
    → Extracts: full chain PEM

awk / csplit
    → Saves: individual cert files for inspection

curl --cacert / CURL_CA_BUNDLE / append to bundle
    → Trusts: internal CA without -k
```

---

## 18. File Reference

### What you have after following the PKI walkthrough

```
pki/
├── openssl.cnf         Config file — drives everything
├── index.txt           CA database — updated by openssl ca
├── serial              Hex serial counter
├── 1000.pem            Auto-copy of first signed cert (intermediate)
├── 1001.pem            Auto-copy of second signed cert (server)
├── 1002.pem            Auto-copy of third signed cert (client)
│
├── root.key            Root CA private key — keep offline/encrypted
├── root.crt            Root CA certificate — distribute as trust anchor
│
├── intermediate.key    Intermediate CA private key
├── intermediate.crt    Intermediate CA certificate
├── intermediate.csr    Intermediate CA signing request (can be deleted)
│
├── chain.crt           intermediate.crt + root.crt concatenated
│
├── server.key          Server private key
├── server.csr          Server CSR (can be deleted after signing)
├── server.crt          Signed server certificate
│
├── client.key          Client private key
├── client.csr          Client CSR (can be deleted after signing)
└── client.crt          Signed client certificate
```

### Protecting private keys

In production, encrypt private keys with a passphrase:

```bash
openssl genrsa -aes256 -out root.key 4096
# Prompted for a passphrase — required on every use of the key
```

Or encrypt an existing key after the fact:

```bash
openssl rsa -in root.key -aes256 -out root.key.enc
```

The Root CA key should be stored offline (USB, HSM) and only connected when issuing or revoking Intermediate CA certificates.

---

## 19. Appendix: openssl x509 Print Flags

The `-subject -issuer -dates -serial` flags are shortcuts. Full list of individual print flags:

#### Identity fields

```bash
openssl x509 -in intermediate.crt -noout \
  -subject \        # CN, O, C, ST etc
  -issuer \         # who signed it
  -serial \         # hex serial number
  -email \          # email in subject (if any)
  -hash \           # subject name hash (used for symlink trust stores)
  -issuer_hash      # issuer name hash
```

#### Validity

```bash
openssl x509 -in intermediate.crt -noout \
  -dates \          # notBefore + notAfter together
  -startdate \      # notBefore only
  -enddate          # notAfter only
```

#### Key info

```bash
openssl x509 -in intermediate.crt -noout \
  -pubkey \         # prints the full public key in PEM
  -modulus \        # RSA modulus (use with | openssl md5 to compare with key)
  -fingerprint      # SHA1 fingerprint by default
```

Fingerprint with a specific digest:

```bash
openssl x509 -in intermediate.crt -noout -fingerprint -sha256
openssl x509 -in intermediate.crt -noout -fingerprint -sha1
```

#### Extensions

```bash
openssl x509 -in intermediate.crt -noout \
  -purpose          # lists what the cert is valid for (CA, SSL server, etc)
```

#### The nuclear option — everything

```bash
openssl x509 -in intermediate.crt -noout -text
```

#### Practical combo — the useful summary

```bash
openssl x509 -in intermediate.crt -noout \
  -subject -issuer -serial -dates -fingerprint -sha256
```

Output:

```
subject=C=US, ST=New Jersey, O=Operative Inc, CN=Operative INC intermediate CA
issuer=C=US, ST=New York, O=Operative Inc., CN=Operative Inc. CA
serial=1000
notBefore=May 23 11:00:00 2026 GMT
notAfter=May 23 11:00:00 2031 GMT
SHA256 Fingerprint=3A:F1:...
```

#### Loop over a directory of keys

```bash
for key in *.key; do
  echo "=== $key ==="
  openssl pkey -in "$key" -noout -text 2>&1 | head -3
done
```

---

### Quickstart: Minimal CA Setup Checklist

```bash
# 1. Create directory structure
mkdir -p /etc/pki/ca/{certs,crl,newcerts,private}
chmod 700 /etc/pki/ca/private

# 2. Initialise database files
touch /etc/pki/ca/index.txt
echo 1000 > /etc/pki/ca/serial
echo 00   > /etc/pki/ca/crlnumber

# 3. Generate the CA key (encrypt it)
openssl genrsa -aes256 -out /etc/pki/ca/private/ca.key 4096
chmod 400 /etc/pki/ca/private/ca.key

# 4. Create the self-signed root CA certificate
openssl req -config openssl.cnf \
  -key /etc/pki/ca/private/ca.key \
  -new -x509 -days 3650 -sha256 \
  -extensions v3_ca \
  -out /etc/pki/ca/ca.crt

# 5. Generate a server key and CSR
openssl genrsa -out server.key 4096
openssl req -config openssl.cnf -new -sha256 \
  -key server.key -out server.csr

# 6. Sign the CSR
openssl ca -config openssl.cnf \
  -extensions server_cert -days 365 \
  -notext -md sha256 -batch \
  -in server.csr -out server.crt

# 7. Verify the result
openssl verify -CAfile /etc/pki/ca/ca.crt server.crt
```
