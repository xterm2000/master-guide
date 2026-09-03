# wget guide — downloads & mirroring

`wget` is the non-interactive downloader: it shines where `curl` is awkward —
**unattended** transfers that must survive flaky links, **recursive** site
mirrors, and **batch** URL lists. For API calls, custom methods, header
inspection and `-w` timing, use [`curl-text-logs.md`](curl-text-logs.md) instead;
the [wget vs curl](#wget-vs-curl) table below says which to reach for.

Verified on Rocky Linux 10.2, GNU Wget 1.24.5 (`+https +ipv6 +iri`, `-metalink`).

```
wget [options] <url>...
```

---

## Output & logging

|Flag|Description|
|---|---|
|`-O file`|Write to `file` (`-O -` = stdout). Forces a single output name even with `-r`.|
|`-P dir`|Save under `dir/` (prefix), keeping remote paths.|
|`-nd`|No directories — flatten everything into one dir (with `-r`).|
|`-q`|Quiet — no output at all.|
|`-nv`|Non-verbose — one line per file (`URL:… -> "file" [bytes]`), errors still shown. Best for scripts/cron.|
|`-o log`|Write messages to `log` (overwrite).|
|`-a log`|Append messages to `log`.|
|`-b`|Go to background; messages to `wget-log` (or `-o`).|
|`-S`|Print the server response headers.|
|`--spider`|Don't download — just check the URL exists (like `curl -I`). Exit 0 if reachable.|

---

## Robust unattended download

|Flag|Description|
|---|---|
|`-c`|Continue a partially-downloaded file (HTTP range resume).|
|`--tries=N`|Retry each file up to N times (`0`/`inf` = forever). Default 20.|
|`--timeout=S`|Set DNS + connect + read timeout to S seconds.|
|`--connect-timeout=S` / `--read-timeout=S`|Set them individually.|
|`--waitretry=S`|Wait up to S seconds (linear backoff) between retries.|
|`--retry-connrefused`|Treat "connection refused" as transient and keep retrying.|
|`--retry-on-http-error=503,429`|Also retry on these status codes.|
|`-N` / `--timestamping`|Only re-download if the remote file is newer than the local copy.|
|`--limit-rate=2m`|Cap bandwidth (`k`/`m` suffix).|
|`--wait=S` / `--random-wait`|Pause between files — be polite to the server.|
|`--no-dns-cache`|Re-resolve each time (long-running jobs behind changing DNS).|

A cron/CI-safe pattern:

```bash
wget -nv --tries=5 --timeout=15 --waitretry=10 --retry-connrefused \
     -N -P /srv/mirror https://example.com/artifact.tar.gz
```

---

## Batch (URL lists)

|Flag|Description|
|---|---|
|`-i file`|Read URLs to fetch from `file` (`-i -` = stdin), one per line.|
|`-B url`|Resolve relative URLs in `-i` against this base.|
|`--content-disposition`|Honour the server's `Content-Disposition` filename instead of the URL tail.|
|`--trust-server-names`|On a redirect, name the file from the final URL, not the first.|

> Gotcha: multiple URLs that all end `/` (or all serve `index.html`) collide —
> wget writes `index.html`, `index.html.1`, `index.html.2`… Use
> `--content-disposition`, `-O`, or a recursive mirror instead.

---

## Recursive mirroring

|Flag|Description|
|---|---|
|`-r`|Recurse into linked pages.|
|`-l N`|Max recursion depth (`-l inf` = unlimited; default 5).|
|`-np`|**No parent** — never ascend above the start URL's directory. Almost always want this.|
|`-k` / `--convert-links`|Rewrite links in saved pages to point at the local copies (offline browsing).|
|`-K`|Keep the original file as `*.orig` alongside the converted one.|
|`-p` / `--page-requisites`|Also fetch CSS/JS/images a page needs to render.|
|`-m` / `--mirror`|Shorthand for `-r -N -l inf --no-remove-listing` (a "keep it in sync" mirror).|
|`-A list` / `-R list`|Accept / reject by comma-separated suffix or glob (`-A 'html,pdf'`).|
|`-D list` / `--span-hosts` `-H`|Restrict / allow crossing to other hosts.|
|`-e robots=off`|Ignore `robots.txt` / robots meta tags (use judiciously — your own sites, mirrors).|
|`--no-check-certificate`|Skip TLS verification. Prefer `--ca-certificate=FILE` / `--ca-directory=DIR`.|

Mirror a docs subtree for offline use:

```bash
wget -r -np -k -p -l 3 -A 'html,css,js,png,svg' \
     -P ./offline https://docs.example.com/guide/
```

---

## Auth, headers, TLS

|Flag|Description|
|---|---|
|`--user=U --password=P`|HTTP/FTP auth (also `--http-user` / `--http-password`).|
|`--header='K: V'`|Add a request header (repeatable) — e.g. `--header='Authorization: Bearer …'`.|
|`--load-cookies f` / `--save-cookies f` / `--keep-session-cookies`|Cookie jar handling.|
|`--post-data='a=b'` / `--post-file=f`|Send a POST body (limited — use `curl` for real API work).|
|`--max-redirect=N`|Cap redirects (`0` = don't follow).|
|`--ca-certificate=f` / `--ca-directory=d`|Trust a specific CA bundle.|
|`--certificate=f --private-key=f`|Client-cert (mTLS).|
|`-e use_proxy=yes` + `http_proxy` / `https_proxy` / `no_proxy` env|Proxy control (or set in `.wgetrc`).|

---

## `.wgetrc`

Defaults live in `~/.wgetrc` (or `/etc/wgetrc`); every long option has a config
form (`--tries=5` → `tries = 5`). Useful baseline:

```ini
tries          = 5
timeout        = 20
waitretry      = 10
retry_connrefused = on
robots         = off
# ca_certificate = /etc/pki/tls/certs/ca-bundle.crt
```

Override a config setting for one run with `-e`: `wget -e robots=on …`.

---

## Common Recipes

### Reachability check (no download)

```bash
wget -q --spider https://example.com && echo up || echo down
wget -S --spider -q https://example.com     # + show response headers
```

### Only fetch if changed (idempotent sync)

```bash
wget -N -P /srv/cache https://example.com/data.json   # -N compares timestamps
```

### Resume a big interrupted download

```bash
wget -c -O big.iso https://example.com/big.iso        # picks up where it stopped
```

### Download a list of URLs into a directory

```bash
wget -nv --content-disposition -i urls.txt -P downloads/
```

### Mirror a site section for offline reading

```bash
wget -r -np -k -p -l 2 -P ./site https://example.com/docs/
```

### Background a long job and watch it

```bash
wget -b -o dl.log -c https://example.com/big.tar.gz
tail -f dl.log
```

### Pull an artifact in a Dockerfile / CI step

```bash
wget -nv --tries=3 --timeout=15 --retry-connrefused \
     -O /tmp/tool.tgz https://example.com/tool-1.2.3.tgz
```

### Grab all PDFs linked from a page

```bash
wget -r -np -l 1 -A pdf -e robots=off -P pdfs/ https://example.com/reports/
```

---

## wget vs curl

| Task | Tool | Why |
|---|---|---|
| Recursive site / directory mirror | **wget** | `-r -np -k -p`, `--mirror` — curl has no recursion |
| Unattended download, flaky link | **wget** | `-c`, `--tries`, `--waitretry`, `--retry-connrefused` built in |
| "Only if newer" sync | **wget** | `-N` / `--timestamping` |
| Batch a file of URLs | **wget** | `-i file` (curl needs `xargs` or `-K` config) |
| Simple "save this URL" | either | `wget -O` / `curl -O` |
| REST API call, JSON body, custom method | **curl** | `-X`, `-d @file`, `-F`, proper `--data-*` handling |
| Inspect / dump headers, follow one redirect | **curl** | `-I`, `-D`, `-v`, `-L` |
| Latency breakdown (DNS/connect/TLS/TTFB) | **curl** | `-w '%{time_*}'` — wget has nothing equivalent |
| Upload a file | **curl** | `-T` / `-F`; wget's POST support is minimal |
| Unix-pipe friendliness / scripting | **curl** | writes to stdout by default, cleaner exit codes |
| Already installed on a minimal box | usually **curl** | but wget is in most base images too |

Rule of thumb: **curl talks to APIs, wget collects files.**

---

## See Also

- [`curl-text-logs.md`](curl-text-logs.md) — curl reference (`-w` timing, headers, auth, k8s recipes)
- [`small-tools.md`](small-tools.md) — the single-purpose text/file utilities around a download
- [`../../network/net-tools.md`](../../network/net-tools.md) — reachability / DNS / TLS diagnostics if a download won't connect
- [`../../network/networking-guide.md`](../../network/networking-guide.md) — the "is it DNS, the route, or the service?" method
- [`../tls-pki/`](../tls-pki/) — CA bundles, `--ca-certificate`, why `--no-check-certificate` is a last resort
