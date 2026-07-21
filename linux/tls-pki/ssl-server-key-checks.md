# OpenSSL Certificate Inspection Guide

A practical reference for inspecting, parsing, and validating X.509 certificates using `openssl`.

---

## 1. Inspecting a Single Certificate

### Print subject, issuer, and validity dates
```bash
openssl x509 -in cert.crt -noout -subject -issuer -dates -serial
```

### Full human-readable dump
```bash
openssl x509 -in cert.crt -noout -text
```

---

## 2. Looping Over a Certificate Bundle

A `.crt` bundle may contain multiple PEM-encoded certificates. Use these patterns to iterate over each one.

### Loop with a bash while-read block
```bash
while IFS= read -r line; do
  cert_block+="$line"$'\n'
  if [[ "$line" == "-----END CERTIFICATE-----" ]]; then
    echo "=== Certificate ==="
    echo "$cert_block" | openssl x509 -noout -subject -issuer -dates -fingerprint
    echo
    cert_block=""
  fi
done < bundle.crt
```

### Split with awk, then loop
```bash
awk 'BEGIN {c=0} /-----BEGIN CERTIFICATE-----/{c++} {print > "/tmp/cert_" c ".pem"}' bundle.crt

for f in /tmp/cert_*.pem; do
  echo "=== $f ==="
  openssl x509 -in "$f" -noout -subject -issuer -dates -serial
  echo
done
```

### Split with csplit
```bash
csplit -z -f /tmp/cert_ bundle.crt '/-----BEGIN CERTIFICATE-----/' '{*}' 2>/dev/null

for f in /tmp/cert_*; do
  echo "=== $(basename $f) ==="
  openssl x509 -in "$f" -noout -text | grep -E "Subject:|Issuer:|Not Before:|Not After :|Serial"
  echo
done
```

---

## 3. Checking Expiry Across a Bundle

Sort all certificates by expiry date - useful for spotting what is about to expire:

```bash
while IFS= read -r line; do
  cert_block+="$line"$'\n'
  if [[ "$line" == "-----END CERTIFICATE-----" ]]; then
    expiry=$(echo "$cert_block" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    subj=$(echo "$cert_block" | openssl x509 -noout -subject 2>/dev/null | sed 's/subject=//')
    echo "$expiry | $subj"
    cert_block=""
  fi
done < bundle.crt | sort
```

---

## 4. Grepping OpenSSL Help

OpenSSL writes help text to **stderr**, so redirect it before piping:

```bash
openssl x509 -help 2>&1 | grep -i 'print'
openssl x509 -help 2>&1 | grep -i 'ext'
```

As a reusable shell function:
```bash
grep_ssl() { openssl x509 -help 2>&1 | grep -i "$1"; }
grep_ssl print
```

---

## 5. Checking a Hostname Against a Certificate

`-checkhost` validates whether the cert covers the hostname **you supply**. It checks the CN and all SAN `DNS:` entries.

```bash
openssl x509 -in cert.crt -noout -checkhost example.com
```

**Output:**
```
Hostname example.com does match certificate
# or
Hostname example.com does NOT match certificate
```

### Related hostname/IP/email checks

| Flag | What it checks |
|------|----------------|
| `-checkhost <name>` | DNS hostname (CN + SAN DNS entries) |
| `-checkip <ip>` | IP address (SAN IP entries) |
| `-checkemail <addr>` | Email address (SAN email entries) |

### Use in a bundle loop
```bash
while IFS= read -r line; do
  cert_block+="$line"$'\n'
  if [[ "$line" == "-----END CERTIFICATE-----" ]]; then
    echo "=== Check ==="
    echo "$cert_block" | openssl x509 -noout -checkhost myapp.example.com
    cert_block=""
  fi
done < bundle.crt
```

---

## 6. Extracting SAN / DNS Names

### OpenSSL 1.1.1+ (supports `-ext`)
```bash
openssl x509 -in cert.crt -noout -ext subjectAltName
```

### Older OpenSSL (use `-text` + grep)
```bash
openssl x509 -in cert.crt -noout -text \
  | grep -A1 'Subject Alternative Name'
```

### Just the DNS names, clean (no prefix)
```bash
openssl x509 -in cert.crt -noout -text \
  | grep -A1 'Subject Alternative Name' \
  | grep -oP '(?<=DNS:)[^,\s]+'
```

### In a bundle loop
```bash
while IFS= read -r line; do
  cert_block+="$line"$'\n'
  if [[ "$line" == "-----END CERTIFICATE-----" ]]; then
    echo "=== SANs ==="
    echo "$cert_block" | openssl x509 -noout -text \
      | grep -A1 'Subject Alternative Name' \
      | grep -oP '(?<=DNS:)[^,\s]+'
    cert_block=""
  fi
done < bundle.crt
```

> **Note:** Check your version with `openssl version`. The `-ext` flag requires OpenSSL 1.1.1+.

---

## 7. Testing a Live TLS Connection

### Full handshake with a specific CA bundle
```bash
openssl s_client -connect example.com:443 -CAfile /etc/pki/tls/certs/ca-bundle.crt
```

### Quick verify check
```bash
openssl s_client -connect example.com:443 2>&1 | grep -E 'Verify|subject|issuer'
```

### Show the full certificate chain
```bash
openssl s_client -connect example.com:443 -showcerts 2>/dev/null
```

---

## 8. Understanding the System CA Bundle (`/etc/pki`)

| Path | Purpose |
|------|---------|
| `/etc/pki/tls/certs/ca-bundle.crt` | System-wide trusted CA roots |
| `/etc/pki/ca-trust/` | CA trust anchors (RHEL/CentOS trust framework) |
| `/etc/pki/tls/cert.pem` | Usually a symlink to the bundle above |

The bundle is **not tested against any hostname**. It is the list of trusted Certificate Authorities the system uses to verify remote server certificates. The hostname check is done separately by the TLS client (curl, openssl s_client, your app).

---

## 9. Understanding the Certificate Chain

A typical corporate PKI chain looks like this:

```
your-server.example.com          ← leaf cert (depth 0)
    ↑ signed by
NBCU Enterprise TLS Issuing CA   ← intermediate CA (depth 1)
    ↑ signed by
NBCU Enterprise Root CA 1        ← root CA, self-signed (depth 2)
```

- The root CA is **always self-signed** - it signs itself because there is no authority above it.
- `verify error:num=19: self signed certificate in certificate chain` is **expected and normal** when the root is a private/corporate CA not present in the system bundle.
- Self-signed at **depth 0** (the leaf cert itself) is the problematic case.

### Adding a private root CA to system trust (RHEL/CentOS)
```bash
cp nbcu-root-ca.crt /etc/pki/ca-trust/source/anchors/
update-ca-trust

# Verify
openssl s_client -connect oaapi.inbcu.com:443 2>&1 | grep 'Verify return'
# Expected: Verify return code: 0 (ok)
```

---

## 10. Extracting the Root CA from a Live Connection

Extract the root cert (last in the chain) directly from the TLS handshake:

```bash
openssl s_client -connect oaapi.inbcu.com:443 -showcerts 2>/dev/null \
  | awk '/-----BEGIN CERTIFICATE-----/{c++} c==3{print} /-----END CERTIFICATE-----/ && c==3{exit}' \
  > nbcu-root-ca.crt
```

> Adjust `c==3` to match the depth of the root in your chain (3 certs = root is cert #3).

### Verify it is self-signed (subject == issuer)
```bash
openssl x509 -in nbcu-root-ca.crt -noout -subject -issuer
```

**Expected output:**
```
subject= /C=US/O=NBCUniversal Media LLC/CN=NBCU Enterprise Root CA 1
issuer=  /C=US/O=NBCUniversal Media LLC/CN=NBCU Enterprise Root CA 1
```

### Extract all chain certs to separate files, then inspect
```bash
openssl s_client -connect oaapi.inbcu.com:443 -showcerts 2>/dev/null \
  | awk 'BEGIN{c=0} /-----BEGIN CERTIFICATE-----/{c++; file="/tmp/chain_"c".crt"} file{print > file}'

for f in /tmp/chain_*.crt; do
  echo "=== $f ==="
  openssl x509 -in "$f" -noout -subject -issuer
  echo
done
```

---

## Quick Reference - Common Flags

| Flag | Description |
|------|-------------|
| `-in <file>` | Input certificate file |
| `-noout` | Suppress raw certificate output |
| `-text` | Full human-readable certificate dump |
| `-subject` | Subject DN |
| `-issuer` | Issuer DN |
| `-dates` | `notBefore` and `notAfter` validity dates |
| `-serial` | Serial number |
| `-fingerprint` | SHA1 fingerprint |
| `-ext subjectAltName` | SANs (OpenSSL 1.1.1+ only) |
| `-checkhost <name>` | Validate hostname against cert |
| `-checkip <ip>` | Validate IP against cert |
| `-checkemail <addr>` | Validate email against cert |
| `-showcerts` | Show full chain in `s_client` |
| `-CAfile <path>` | Specify CA bundle for verification |