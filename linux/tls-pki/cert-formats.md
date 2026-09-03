# Certificate & Key Formats — PEM, DER, and the X.509 Family

Why a TLS certificate looks the way it does, what PEM actually is, and how it
relates to (and differs from) SSH keys. This is the "what am I holding and why"
companion to [`openssl-pki.md`](openssl-pki.md) (which builds a CA) and
[`ssl-server-key-checks.md`](ssl-server-key-checks.md) (which inspects certs).

*Commands verified against OpenSSL 3.5.5 (the version on this box).*

---

## 1. The short answer

"SSL/TLS certs" feel like their own species because they are the visible tip of
a lineage **completely separate** from SSH keys:

| | SSH | TLS |
|---|---|---|
| Origin | Unix, 1995 — a self-contained `telnet`/`rlogin` replacement | **X.509**, from the ITU-T **X.500 directory** standards, 1988 |
| Identity format | its own minimal one-line key format (`ssh-ed25519 AAAA…`) | ASN.1-structured record with issuer/subject/extensions |
| Default trust | **TOFU** — accept a host key on first sight ([`../ssh/GLOSSARY.md`](../ssh/GLOSSARY.md)) | a **CA hierarchy** verified automatically, no human in the loop |
| Certificates | a deliberately tiny signed blob ([`../ssh/ssh-ca.md`](../ssh/ssh-ca.md)) | full X.509 with chains, path limits, CRL/OCSP pointers |

The one-sentence version: **SSH never needed X.500's machinery, so it never
adopted X.500's format.** TLS inherited the whole thing.

A "PEM cert" conflates three separate layers. Unpacking them explains almost
every format question.

---

## 2. Layer 1 — the data model: X.509 / ASN.1

A TLS certificate is a **structured record**, not free text. Its schema, in
**ASN.1** (Abstract Syntax Notation One — a schema language from the same X.500
world):

```asn1
Certificate ::= SEQUENCE {
    tbsCertificate       TBSCertificate,      -- the "to be signed" body
    signatureAlgorithm   AlgorithmIdentifier,
    signatureValue       BIT STRING           -- CA's signature over tbsCertificate
}

TBSCertificate ::= SEQUENCE {
    version              [0] INTEGER,
    serialNumber             INTEGER,
    issuer                   Name,             -- the CA's Distinguished Name
    validity                 SEQUENCE { notBefore, notAfter },
    subject                  Name,             -- who this cert identifies
    subjectPublicKeyInfo     SEQUENCE { algorithm, publicKey },
    extensions           [3] SEQUENCE OF Extension   -- SANs, key usage, CRL URLs…
}
```

This is exactly the "three things bundled with a CA's signature over all of
them" from [`openssl-pki.md`](openssl-pki.md) §1: a public key, identity
information (the subject DN), and the CA's signature.

**Why so elaborate?** Because automated chain verification needs it:

| Requirement | Field / extension |
|---|---|
| Verify a chain with zero human input | `issuer` / `subject` DNs link leaf → intermediate → root |
| One key, many hostnames | `subjectAltName` (SAN) — the CN is legacy |
| "May sign other certs" vs "is a leaf" | `basicConstraints` (`CA:TRUE` / `CA:FALSE`) |
| Limit how deep a sub-CA can delegate | `basicConstraints` path length |
| Constrain what the key may do | `keyUsage` / `extendedKeyUsage` (`serverAuth`, `keyCertSign`…) |
| Revoke before expiry | `crlDistributionPoints`, `authorityInfoAccess` (OCSP) |
| Time-box validity | `validity` |

SSH's original model (TOFU) has none of these needs — a human checks a
fingerprint once, there is no hierarchy — so its key format carries none of this
structure. That is the whole "why their own kind" story.

---

## 3. Layer 2 — the byte encoding: DER

ASN.1 says *what fields exist*; **DER** (Distinguished Encoding Rules) says how
to serialise them to bytes: every element is `[type tag][length][value]`,
nested recursively (TLV encoding).

"**Distinguished**" means there is exactly **one** valid byte string for a given
structure. That matters because the bytes get signed — any re-encoding would
invalidate the signature.

DER is **binary**. A DER file is what the `.der` extension denotes.

```bash
file cert.der          # -> "cert.der: Certificate, Version=3"
openssl x509 -in cert.der -inform der -noout -text
```

---

## 4. Layer 3 — the transport wrapper: PEM

Binary DER does not survive being pasted into an email, a YAML file, a k8s
`Secret`, or a terminal. So:

> **PEM = Base64(DER), wrapped at 64 columns, between `-----BEGIN X-----` and
> `-----END X-----` lines.**

```
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIJAJC1HiIAZAiIMA0GCSqGSIb3DQ...   <- base64 of the DER bytes
-----END CERTIFICATE-----
```

Four facts that clear up most PEM confusion:

1. **PEM is a container, not a content type.** The `BEGIN` label says what is
   inside: `CERTIFICATE`, `CERTIFICATE REQUEST` (a CSR), `PRIVATE KEY`,
   `RSA PRIVATE KEY`, `EC PRIVATE KEY`, `ENCRYPTED PRIVATE KEY`, `PUBLIC KEY`,
   `X509 CRL`, … Always read the first line.

2. **The name is a fossil.** "PEM" = **Privacy-Enhanced Mail**, a failed
   early-1990s secure-email standard (RFCs 1421–1424). The email system died;
   its Base64 armour was scavenged and is now standardised on its own as
   RFC 7468.

3. **PEM blocks concatenate.** That is why
   `cat intermediate.crt root.crt > chain.crt` works — a "chain" / "fullchain"
   file is just several PEM certs stacked. DER cannot do this; it has no
   delimiters.

4. **`.pem`, `.crt`, `.cer`, `.key` are the same thing when PEM-encoded** — the
   extension is convention, not format. `openssl x509 -in file -text` reads it
   regardless of extension. `.cer` is the genuinely ambiguous one (Windows uses
   it for both PEM and DER).

---

## 5. The format zoo (what everything past plain PEM is for)

The extra formats all exist to **bundle multiple objects into one file**:

| Format | Extension | Contents | Why it exists |
|---|---|---|---|
| **PKCS#1** | `-----BEGIN RSA PRIVATE KEY-----` | RSA private key only | The original (1993), RSA-specific |
| **PKCS#8** | `-----BEGIN PRIVATE KEY-----` / `ENCRYPTED PRIVATE KEY` | Any private key (RSA, EC, Ed25519 — all identical outer shape) | One parser for every algorithm; **OpenSSL 3.x default** |
| **SPKI** | `-----BEGIN PUBLIC KEY-----` | A bare public key + its algorithm | Sharing a public key with no cert |
| **PKCS#10** | `-----BEGIN CERTIFICATE REQUEST-----` | A CSR (public key + requested identity + self-signature) | What you send a CA |
| **PKCS#7** | `.p7b` / `.p7c` | A cert **chain**, no private key | "Here are all the CA certs" — common from Windows CAs |
| **PKCS#12** | `.p12` / `.pfx` | **leaf cert + private key + chain, in one passphrase-encrypted binary blob** | Moving a whole identity between machines; what browsers / Windows / Java import. Binary only. |

SSH has none of these — one key per file, and that is the end of it.

---

## 6. Identify what you're holding

```bash
head -1 file                                   # read the -----BEGIN----- label
file file                                       # "PEM certificate" vs "data" (= DER/PKCS12)

openssl x509  -in file -noout -text              # parse as a certificate
openssl pkey  -in file -noout -text              # parse as a private key (any algorithm)
openssl req   -in file -noout -text              # parse as a CSR
openssl crl   -in file -noout -text              # parse as a CRL
openssl pkcs12 -in file.pfx -info -noout         # inspect a PKCS#12 bundle
openssl asn1parse -in file                       # raw ASN.1 structure of anything DER/PEM
```

Add `-inform der` when the file is binary.

> **libmagic quirk:** `file` on a PKCS#8 PEM key (`-----BEGIN PRIVATE KEY-----`)
> may report `OpenSSH private key` — because OpenSSH's own newer key format
> reuses that exact header line. Trust `openssl pkey`, not `file`, for keys.

---

## 7. Convert between formats

```bash
# PEM  <->  DER  (certificate)
openssl x509 -in cert.pem -outform der -out cert.der
openssl x509 -in cert.der -inform der  -out cert.pem

# PEM  <->  DER  (private key)
openssl pkey -in key.pem -outform der -out key.der
openssl pkey -in key.der -inform der  -out key.pem

# PKCS#1  ->  PKCS#8   (legacy RSA header -> modern algorithm-agnostic)
openssl pkey -in pkcs1.key -out pkcs8.key

# Bundle everything into PKCS#12 (for a browser / Windows / Java keystore)
openssl pkcs12 -export -in cert.pem -inkey key.pem -certfile chain.pem -out bundle.pfx

# Explode a PKCS#12 back to PEM
openssl pkcs12 -in bundle.pfx -nodes -out everything.pem      # -nodes = leave key unencrypted

# PKCS#7 chain  ->  PEM certs
openssl pkcs7 -in chain.p7b -print_certs -out chain.pem
```

---

## 8. Mental model

```
ASN.1 schema     "a cert is a SEQUENCE of {serial, issuer, subject, pubkey, extensions…}"
   │   (X.509, inherited from the X.500 directory standards — this is the "own kind")
   ▼
DER encoding     deterministic binary TLV bytes  → the exact bytes that get signed
   │
   ├── stays binary  →  .der / .cer
   │
   ▼
PEM armour       base64(DER) + "-----BEGIN CERTIFICATE-----"   →  .pem / .crt / .key
   │   (concatenate freely  →  chain.pem, fullchain.pem)
   │
   ▼
bundling         PKCS#7  (certs only)   ·   PKCS#12 / .pfx  (cert + key + chain, encrypted)
```

**SSH sits entirely outside this diagram** — its own one-line key format, its
own certificate format ([`../ssh/ssh-ca.md`](../ssh/ssh-ca.md)), its own agent
([`../ssh/ssh-agent.md`](../ssh/ssh-agent.md)), TOFU instead of a CA by default.
Two ecosystems that both do public-key crypto and share almost no file formats.

---

## See Also

- [`openssl-pki.md`](openssl-pki.md) — build a full CA hierarchy; §1 concepts, §2 algorithms
- [`ssl-server-key-checks.md`](ssl-server-key-checks.md) — inspect and validate certs, match key ↔ cert
- [`../ssh/ssh-ca.md`](../ssh/ssh-ca.md) — SSH's own (non-X.509) certificate system, for contrast
- [`../../GLOSSARY.md`](../../GLOSSARY.md) — PKI / CA / PEM / DER / PKCS vocabulary
