# Text Processing Cookbook

> Assumes you've already read `grep.md`, `sed.md`, `awk.md` for syntax. This file is not about syntax — it's about **the flow**: given a real end result, how do you decide which tool does which step, and in what order?

Every recipe below is organized by **the end result you want**, not by tool. Real text-processing work is almost never "use awk" — it's "get this outcome," and the outcome dictates a *chain* of small tools, each doing the one thing it's best at. The comments in each recipe call out three things every time:

1. **Read** — how the data enters the pipeline
2. **Extract / transform** — which tool pulls out or reshapes the fields, and *why that tool and not another one*
3. **Write back / conclude** — how the result lands (stdout, a new file, an in-place edit)

The recipes are grouped into six categories by the kind of end result, plus a closing section on where these tools **stop being the right tool at all** — knowing that boundary matters as much as knowing the tools.

## The core mental model

| If you need to... | Reach for... | Because... |
|---|---|---|
| Select whole lines matching a pattern | `grep` | It's a line filter — yes/no per line, nothing more |
| Pull out or rearrange specific *fields* on each line | `awk` | It's field-aware (`$1`, `$2`, ...) and can compute (counts, sums, conditionals) |
| Replace text *within* a line, in place | `sed` | It's a stream editor — substitution and light line-editing, not aggregation |
| Sort, dedupe, or count occurrences | `sort` / `uniq -c` | Purpose-built, faster and clearer than hand-rolling the same in `awk` |
| Join two files on a shared key | `join` (sorted input) or `awk` (unsorted, more control) | `join` is simplest when both sides are already sorted on the key |

Most recipes below are two or three of these chained with `|`, each stage doing only its one job. Once a shape (filter → extract → aggregate → rank; or flag-on/flag-off block capture; or group-by-sum in an array) shows up twice, you'll start recognizing it as *the* answer to a new problem before you've fully read the problem — that recognition is the actual skill this file is trying to build, more than any single command.

---

## Part A — Log & Monitoring Analysis

### Extract all errors from a log and count them per hour

**Goal:** given a mixed-severity application log, find how error volume is trending over time.

```bash
grep 'ERROR' app.log \
  | awk '{print $1, $2}' \
  | cut -c1-13 \
  | sort \
  | uniq -c \
  | sort -rn
```

- **Read + filter (`grep`)** — `grep 'ERROR'` throws away every line we don't care about *before* anything else touches it. Filtering first means every later stage processes less data — always filter as early in the pipeline as possible.
- **Extract (`awk`)** — the timestamp is the first two space-separated fields (`2026-07-21 14:32:07,123`). `awk '{print $1, $2}'` pulls just those out; we don't need the rest of the line for this question.
- **Truncate to the hour (`cut -c1-13`)** — `cut` on fixed character positions, not fields, because we want "date + hour" as a literal substring (`2026-07-21 14`), not a delimited field.
- **Aggregate (`sort | uniq -c | sort -rn`)** — `uniq -c` only counts *adjacent* duplicate lines, which is why the first `sort` has to come before it. The second `sort -rn` orders the hourly counts highest-first so the worst hour is at the top. This filter → sort → uniq -c → sort -rn shape is the single most reused pattern in this file — you'll see it again below with IPs, files, and process names, not just timestamps.

**Why not do the whole thing in one `awk` script?** You could (`awk` can accumulate counts in an associative array keyed by hour). Either is valid — the pipeline version reads more like a sentence ("filter, then extract, then bucket, then count, then rank"), which is usually worth the extra process spawns unless you're processing gigabytes and the overhead actually matters.

---

### Find the top-N noisiest IPs hitting your server

**Goal:** from an nginx/Apache access log, find which client IPs are generating the most requests.

```bash
awk '{print $1}' access.log \
  | sort \
  | uniq -c \
  | sort -rn \
  | head -10
```

- **Extract (`awk`)** — in Common Log Format the client IP is always field 1. `awk` over `cut -d' ' -f1` here mostly because `awk`'s field-splitting is more forgiving of repeated whitespace than `cut`'s, and it reads more clearly when a teammate has to modify it later (e.g., "now also print the status code" is just `print $1, $9`).
- **Aggregate + rank** — the exact same "count and rank anything" shape as the previous recipe.
- **`head -10`** — cut the list down to what a human actually reads. Leaving this off during development (so you can eyeball the full distribution) and adding it back for the final report is a normal iteration pattern.

**Variant — filter to a time window first:**

```bash
awk -v start="21/Jul/2026:14" '$4 ~ start' access.log \
  | awk '{print $1}' \
  | sort | uniq -c | sort -rn | head -10
```
Two `awk` calls back to back looks redundant, but each does a genuinely different job: the first is a **line filter** (keep/drop by timestamp match), the second is a **field extractor**. You *could* combine them into one `awk` script with an `if` — reasonable once the pipeline stops being "obviously readable" and starts feeling like a wall of pipes.

---

### Traffic volume per minute — extraction with `grep -o`

**Goal:** a quick view of request volume over time, without needing awk to parse the timestamp format at all.

```bash
grep -oP '(?<=\[)\d{2}/[A-Za-z]{3}/\d{4}:\d{2}:\d{2}' access.log \
  | sort | uniq -c
```

- **`grep -o`** — prints only the *matched portion* of each line, not the whole line. This is a different mode from every earlier `grep` use in this file (which filtered whole lines) — here `grep` is doing extraction, the job we'd otherwise hand to `awk`/`cut`. Reach for `grep -o` when the thing you want is identified by a *pattern* (a date shape) rather than a fixed field position.
- **`-P` (PCRE) + lookbehind `(?<=\[)`** — matches the timestamp without consuming or printing the literal `[` in front of it. Basic/extended regex (the default and `-E`) can't do lookbehind at all — see `grep-regex-ref.md` for which features need `-P`.
- Once the minute-precision timestamp is extracted, it's the familiar `sort | uniq -c` aggregation again.

---

### Which log file has the most errors, across many files

**Goal:** you have a directory of per-service log files and want to know which service is the noisiest, without opening each one.

```bash
grep -c 'ERROR' /var/log/app/*.log | sort -t: -k2 -rn
```

- **`grep -c` across multiple files** — when `grep` is given more than one filename, `-c` (count of matching lines) prefixes each result with `filename:`, e.g. `payments.log:412`. That prefix is what makes this a one-liner instead of a loop.
- **`sort -t: -k2 -rn`** — tell `sort` the field delimiter is `:` (`-t:`) and sort numerically, descending, on the second field (`-k2`) — i.e., sort by the count, not by the filename that happens to sit before it.

---

### Total, average, and percentile of a numeric field

**Goal:** you have a log of per-request latencies and need p50/p95/p99, not just an average — averages hide the slow tail that actually causes complaints.

```bash
awk '{print $NF}' response-times.log \
  | sort -n \
  | awk '{ a[NR]=$1 } END {
      print "p50:", a[int(NR*0.50)]
      print "p95:", a[int(NR*0.95)]
      print "p99:", a[int(NR*0.99)]
    }'
```

- **`sort -n` before the percentile `awk`** — percentiles are a position-in-sorted-order question ("the value at the 95th-percentile *position*"), so the data has to be numerically sorted first — `-n` matters, a plain `sort` would order `"9"` after `"10"` as text.
- **Loading into an array (`a[NR]=$1`)** — percentiles need random access by index ("give me the value at position `0.95 * count`"), which a single streaming pass can't do until it knows the total count — this is one of the few recipes in this file that *must* buffer the whole input, because the question genuinely needs it.
- **Simple average, for contrast** (when the tail doesn't matter): `awk '{sum+=$NF; n++} END{print sum/n}' response-times.log` — one pass, no sort, no buffering, because an average doesn't need order, only a running sum and a count.

---

### Watch a growing log for a pattern in real time

**Goal:** tail a live log and get notified only when something specific happens, with context.

```bash
tail -F app.log | grep --line-buffered 'CRITICAL' | while IFS= read -r line; do
    echo "ALERT: $line" | tee -a alerts.log
done
```

- **`tail -F`** (capital F) — follows the file across log rotation (reopens by name if the inode changes), unlike lowercase `-f` which keeps following the old, now-abandoned file descriptor after a rotate.
- **`grep --line-buffered`** — by default, `grep`'s output is block-buffered when its stdout isn't a terminal (i.e., when it's piped into something else), which delays lines from reaching the next stage in batches instead of immediately. `--line-buffered` forces it to flush per line — required for anything "real-time" downstream of `grep` in a pipe.
- **`while IFS= read -r line`** — the streaming-safe loop idiom; see `bash-loops-cookbook.md` for why this (not `for line in $(...)`) is the correct shape here, and why this loop must **not** be `tail -F | grep ... | while read` if you needed a *variable set inside the loop* to survive afterward (it doesn't, here, only side effects like `tee` do — see `process-substitution.md` for the subshell reason why).

---

### Extract multi-line stack traces out of a log

**Goal:** pull out full exception stack traces (a header line + N indented lines following it), not just the header.

```bash
awk '
/Exception/ { capture = 1 }
capture && /^[A-Za-z]/ && !/Exception/ { capture = 0 }
capture
' app.log
```

- **Why not `grep -A N`?** `grep -A 10` (print 10 lines after a match) works only when every trace is *exactly* the same length — real stack traces vary. This `awk` script instead uses a **state flag** (`capture`) that turns on at the exception line and turns off at the next line that looks like a new, non-indented log entry — it captures traces of any length.
- **Reading the script line by line:**
  - `/Exception/ { capture = 1 }` — turn capturing **on** the moment we see the trigger line.
  - `capture && /^[A-Za-z]/ && !/Exception/ { capture = 0 }` — turn it back **off** the moment we hit a new top-level log line (starts with a letter, i.e. not indented `\tat com.foo...`) that isn't itself another exception header.
  - `capture` (bare pattern, no action) — awk's implicit `{ print }`: while the flag is on, print the line.
- This is the general **range pattern** technique in `awk`: most "extract a multi-line block" problems reduce to "turn a flag on at the start marker, off at the end marker, print while it's on" — worth recognizing as a shape, not memorizing as one script. It reappears below for extracting a config block, with a simpler tool (`sed`) because that version doesn't need the "isn't itself another header" exception.

---

### Correlate every later line with the last-seen marker before it

**Goal:** attach the most recent `Deploying version X` line to every `ERROR` that follows it, so each error is traceable to the release that likely caused it.

```bash
awk '/Deploying version/ { v = $0 } /ERROR/ { print v " -> " $0 }' deploy.log
```

- **A plain variable as memory across lines** — `v` is simply overwritten every time a "Deploying version" line is seen, and read every time an `ERROR` line is seen; `awk` keeps ordinary variables alive for the whole run, so "remember the last X and use it later" needs nothing fancier than an assignment.
- **Why not `sed`?** This is the exact job hold space (`h`/`H`/`x`/`g`/`G`) exists for in `sed` — but `sed` has no ordinary variables, so "remember one earlier line, use it later" means shuffling data in and out of the hold space by hand. `awk`'s plain variable does the same job with far less ceremony — reach for `sed`'s hold space only when you're committed to a single `sed` invocation with no `awk` available, or when the job is *reordering* the stream itself, which a single variable can't do:

```bash
# The canonical hold-space idiom: reverse a file's line order (emulates `tac`)
sed -n '1!G;h;$p'
```
`1!G` appends the hold space onto every line except the first (building up an ever-larger reversed block); `h` then re-saves that growing block into hold space so the next line can build on it; `$p` prints only once, on the last line, once the block holds every line in reverse. If `tac` is installed, just use `tac` — this exists to show what hold space is actually *for*: carrying a growing, accumulated piece of state across an entire stream, which a plain `awk` variable (which holds one value, not a growing sequence) doesn't do as naturally.

---

## Part B — Config & File Editing

### Redact secrets in a config file before sharing/committing it

**Goal:** you need to paste a config file into a ticket or commit it to a repo, but it has real passwords/API keys in it.

```bash
sed -E 's/(password|api_key|token)=.*/\1=REDACTED/' config.env > config.redacted.env
```

- **Why `sed` and not `grep`/`awk`** — this is an in-place *text replacement* on matching lines, not a filter (we want to keep every line, just alter some of them) and not a field computation. That's `sed`'s whole job.
- **The capture group (`\1`)** — `(password|api_key|token)` is captured so the replacement can put the *original* key name back (`\1=REDACTED`) instead of hardcoding one name — one substitution handles all three keys.
- **Never redirect into the same file you're reading** (`sed ... config.env > config.env` truncates the file to empty before `sed` ever reads it, since the shell opens the redirect target first). Write to a new file, or use `sed -i` (which handles the safe temp-file-then-rename dance internally) — see `sed.md` for `-i` details and its BSD/GNU flag differences.

**Verify before you trust it — always diff a destructive-looking edit:**

```bash
diff config.env config.redacted.env
```
This is the "read the result before you act on it" habit that matters most for anything touching secrets: a regex that's slightly too loose (or too strict) fails silently, and you either leak a real key or corrupt an unrelated line. A one-line `diff` costs nothing and catches both.

---

### Bulk find-and-replace across many files, safely

**Goal:** a hostname/URL changed (e.g., `old.mydomain.com` → `new.mydomain.com`) and it's hardcoded across a directory of YAML manifests.

```bash
# 1. See what would change, before changing anything
grep -rl 'old.mydomain.com' k8s/

# 2. Preview the actual replacement, still without touching disk
grep -rl 'old.mydomain.com' k8s/ | xargs sed 's/old.mydomain.com/new.mydomain.com/g'

# 3. Only once the preview looks right, apply in place with backups
grep -rl 'old.mydomain.com' k8s/ | xargs sed -i.bak 's/old.mydomain.com/new.mydomain.com/g'
```

- **Discover scope first (`grep -rl`)** — `-l` prints only *filenames* that contain a match, not the matching lines. This answers "how many files am I about to touch" before committing to anything.
- **`xargs`** — pipes the filename list from `grep` into `sed` as arguments (`sed` needs filenames as args, not stdin, to edit files). This is the standard "list of things → run a command per/over them" bridge whenever the previous stage's output needs to become the next command's *arguments* rather than its stdin.
- **Dry run before `-i`** — step 2 is identical to step 3 minus `-i`, so the output goes to your terminal, not to disk. Reading that output before adding `-i` is the check that prevents "I regex-replaced something I didn't mean to across 40 files" — a genuinely hard mistake to walk back without it.
- **`-i.bak`** — GNU/BSD `sed` both support a backup suffix on `-i`; keeping `.bak` files during a risky bulk edit gives you a one-command revert (`for f in *.bak; do mv "$f" "${f%.bak}"; done`) if something's wrong, without needing git.

---

### Strip comments and blank lines from a config for a clean diff

**Goal:** compare two versions of a config file, ignoring commented-out lines and blank spacing that don't reflect an actual behavior change.

```bash
grep -Ev '^\s*(#|$)' httpd.conf
```

- **One filter, two conditions** — `^\s*#` matches a line that's a comment (allowing leading whitespace before the `#`); `^\s*$` matches a blank/whitespace-only line. Combining both inside one alternation (`#|$`) after a shared `^\s*` means a single `grep -v`-style pass handles both cases instead of two.
- **Real use:** `diff <(grep -Ev '^\s*(#|$)' old.conf) <(grep -Ev '^\s*(#|$)' new.conf)` — process substitution (see `process-substitution.md`) feeds two *cleaned* streams into `diff`, so the diff shows only meaningful changes, not comment churn.

---

### Only add a config line if it isn't already there (idempotent edit)

**Goal:** a provisioning script needs to ensure a setting exists in a config file — but running it twice must not duplicate the line.

```bash
grep -qxF 'net.ipv4.ip_forward = 1' /etc/sysctl.conf \
  || echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
```

- **`grep -q`** — "quiet": run the match, produce no output, only an exit status. This is `grep` used purely as a **condition** in `||`/`&&`, not as a text producer — a genuinely different role from every other `grep` use in this file.
- **`-x`** — match the *whole* line, not a substring, so `net.ipv4.ip_forward = 1` doesn't false-positive against a line that merely contains that text inside a longer one (e.g., inside a comment explaining it).
- **`-F`** — treat the search string as a literal, not a regex, since the string itself contains `.` (which is a regex "any character" wildcard) and we mean it literally here.
- **The pattern:** `grep -q ... || append` is the standard "make this idempotent" shape for scripts that might run more than once — worth recognizing on sight in other people's provisioning scripts.

---

### Extract a config block between two markers

**Goal:** pull just one `server { ... }` block out of an nginx config with many of them, or one `[Unit]` section out of a systemd file.

```bash
sed -n '/^server *{/,/^}/p' nginx.conf
```

- **`sed -n` + a range address (`/start/,/end/`) + `p`** — `-n` suppresses sed's normal "print every line" behavior; the range address selects only the lines from the first pattern match through the next matching line; `p` explicitly prints just that range. This is `sed`'s native version of the flag-on/flag-off `awk` technique from the stack-trace recipe above — same shape, simpler tool, because here the end marker (`^}`) can't be confused with the start marker the way an exception header could.
- **Known limitation:** this breaks if the block contains a *nested* `{ ... }` at the same brace depth as the outer one (the range ends at the first `}`, not the matching one) — fine for flat config sections, not safe for arbitrarily nested ones. A real parser (or a brace-counting `awk` script) is the correct tool once nesting is involved — see the limits section at the end of this file.

---

### A file "looks right" but nothing matches — check for CRLF line endings

**Goal:** a config or script edited on Windows (or checked out with the wrong git line-ending setting) breaks in ways that don't make sense at a glance — `grep '^word$'` doesn't match a line that visibly contains exactly `word`, or a script fails with `bad interpreter: /bin/bash^M: no such file or directory`.

```bash
file config.env          # "ASCII text, with CRLF line terminators" gives it away immediately
cat -A config.env | head -3   # CRLF lines show as ...text^M$ ; clean LF lines show as ...text$
```

- **Why `grep`/`sed` regex anchors misbehave** — every line secretly ends in `\r\n`, not just `\n`. A trailing `\r` is an ordinary, printable-adjacent character to these tools, not a line ending — so `$` (end-of-line anchor) matches *before* the `\r`, not after it, and `word$` silently fails against a line that's actually `word\r`.
- **`cat -A`** makes the invisible visible: `^M` is `cat`'s way of displaying a literal carriage-return byte, and `$` here is `cat`'s own end-of-line marker (not a regex anchor) — seeing `^M$` at the end of a line is the tell.

**Fix — strip the carriage returns:**

```bash
dos2unix config.env              # purpose-built, if installed
# or, with just sed (no extra package needed):
sed -i 's/\r$//' config.env
```
`sed`'s `\r` escape matches the literal carriage-return byte; anchoring it at `$` (end of line) means only a trailing `\r` is removed, never one that legitimately appears mid-line in binary-ish data. This is a cheap habit worth running on *any* file that came from a Windows editor, a Windows-side git clone, or a copy-pasted snippet before trusting a `grep`/`awk` pattern against it.

---

### Quick sanity check: are braces/quotes balanced?

**Goal:** before reloading a service, catch an obviously broken config (mismatched `{`/`}`) without a full config-parser.

```bash
echo "open: $(grep -o '{' app.conf | wc -l)  close: $(grep -o '}' app.conf | wc -l)"
```

- **`grep -o` + `wc -l`** — `grep -o '{'` prints one output line *per occurrence* of `{`, even multiple per source line, so piping that into `wc -l` counts total occurrences, not matching lines (that distinction — `grep -c` counts matching *lines*, `grep -o | wc -l` counts matching *occurrences* — is easy to get backwards).
- This is a smoke test, not a validator — mismatched counts prove something's wrong; matching counts don't prove the file is valid, only that this one obvious failure mode isn't present.

---

## Part C — Data Transformation (CSV/TSV, columns)

### Reformat a delimited export into a different shape

**Goal:** a CSV export has columns in the wrong order for whatever's consuming it next, and one column needs a unit conversion.

```bash
awk -F, 'BEGIN{OFS=","} NR>1 {print $3, $1, $2*1024}' export.csv
```

- **`-F,` / `OFS=","`** — input field separator and output field separator are independent in `awk`; setting both to `,` here means "parse CSV in, emit CSV out," but you could just as easily read comma-separated and emit tab-separated by changing only `OFS`.
- **`NR>1`** — skip the header row (record number 1) without a separate `tail -n +2` stage; once you're already in `awk`, small filtering conditions like this belong inline rather than as another pipeline stage.
- **`$3, $1, $2*1024`** — reordering is just naming fields in a new order; the arithmetic (`$2*1024`, e.g. MB → KB) is why this is an `awk` job and not a `cut`/`paste` job — `cut` can reorder and select columns but cannot compute.

---

### Merge two related files on a shared key (join)

**Goal:** you have `users.csv` (`id,name`) and `logins.csv` (`id,last_login`) and want one combined view.

```bash
# join requires both inputs sorted on the join field
join -t, -1 1 -2 1 <(sort -t, -k1,1 users.csv) <(sort -t, -k1,1 logins.csv)
```

- **Why `join` over `awk`** — when both files are keyed the same way and you just need a straight relational merge, `join` says exactly that in one line. Reach for `awk` instead once the merge needs conditionals, multiple keys, or one side needs to reformat during the merge — `join` is deliberately narrow.
- **`join` demands sorted input on the key** — hence `<(sort -t, -k1,1 ...)` on both sides: process substitution feeds `join` a live, sorted stream from each file without writing temp files (see `process-substitution.md` for why `<(...)` fits here instead of a plain pipe — `join` needs two file-like arguments, not one stdin stream).
- **`-t, -1 1 -2 1`** — comma-delimited (`-t,`), join on field 1 of file 1 and field 1 of file 2. Read this as configuration, not as something to memorize — every `join` call needs "what's the delimiter" and "which field on each side."

**When the files are small and one-off, `awk` alone is often simpler than reaching for `join` at all:**

```bash
awk -F, 'NR==FNR { name[$1]=$2; next } { print $1, name[$1], $2 }' users.csv logins.csv
```
`NR==FNR` is true only while reading the *first* file (`FNR` resets per file, `NR` doesn't) — a common `awk` idiom for "build a lookup table from file 1, then use it while scanning file 2," and it doesn't require either file to be pre-sorted. This "lookup table in an array, built during pass one" shape is the same one used below to sum a column per group — it's a general substitute for a database `JOIN`/`GROUP BY` when the data is small enough to fit in memory.

---

### What's only in one list, or in both — `comm`

**Goal:** you have a static inventory of hosts and the live list currently in the cluster, and need to know which hosts are in the inventory but no longer in the cluster (decommissioned, or never joined).

```bash
comm -23 <(sort inventory-hosts.txt) \
         <(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | sort)
```

- **`comm`** compares two *sorted* files and prints three columns by default: lines only in file 1, lines only in file 2, and lines common to both. `-2` and `-3` suppress the second and third columns, leaving only "in file 1 but not file 2" — exactly "in inventory, missing from the live cluster."
- **Why `comm` over `diff`** — `diff` answers "what changed, in order, line by line," which is the wrong question here (these are two *unordered sets* of hostnames, not two versions of the same sequence). `comm` treats them as sets, which is what they actually are.
- **Both inputs must already be sorted** — same requirement as `join` above, and solved the same way: `<(sort ...)` process substitution feeds `comm` a live sorted stream from each source without a temp file.
- **The reverse question** ("what's in the cluster but not in my inventory file — an unexpected node") is just `comm -13` on the same two streams — suppress column 1 instead of columns 2 and 3.

---

### Group-by aggregation — awk as a mini `GROUP BY SUM`

**Goal:** a CSV of `region,product,amount` sales rows — total sales per region.

```bash
awk -F, '{sum[$1]+=$3} END {for (region in sum) print region, sum[region]}' sales.csv | sort
```

- **`sum[$1]+=$3`** — an associative array keyed by the group column (`$1`, region), accumulating the value column (`$3`) into it. One pass, no sort needed beforehand (unlike the SQL mental model, `awk` doesn't need the input grouped/sorted first — the array does the grouping).
- **`for (region in sum)`** — iterates the array's keys after the whole file's been read (`END` block), printing one line per distinct group. Array iteration order isn't guaranteed, which is why the final `| sort` is there — if you need it ranked by total instead of alphabetically, swap in `| sort -k2 -rn` instead.
- This is the exact same "array as accumulator, keyed by whatever you're grouping on" shape as the per-hour error count and per-IP count earlier in this file — only the key and the thing being accumulated changed.

---

### Turn many lines into one, and back again

**Goal:** join a file's lines into a single comma-separated string (e.g., to build a shell list or a Slack message), and reverse it.

```bash
# lines -> one comma-separated line
paste -sd, list.txt

# comma-separated line -> one item per line
tr ',' '\n' <<< "$csv_line"
```

- **`paste -s`** — "serial" mode: instead of pasting multiple *files* side by side (its usual job), `-s` pastes all the *lines of one file* into a single line, joined by the `-d` delimiter (`,` here).
- **`tr ','  '\n'`** — the reverse direction is simpler than it looks: `tr` just swaps every `,` character for a newline, which is all "one item per line" means once you already have a flat delimited string.

---

### Sort things that look like versions, hostnames, or IPs correctly

**Goal:** a plain `sort` on `worker-1`, `worker-2`, `worker-10` puts `worker-10` right after `worker-1` — alphabetical, not numeric, ordering.

```bash
printf 'worker-1\nworker-10\nworker-2\n' | sort
# worker-1
# worker-10     <- wrong: this "10" sorts before "2" character-by-character
# worker-2

printf 'worker-1\nworker-10\nworker-2\n' | sort -V
# worker-1
# worker-2
# worker-10     <- correct: numeric runs compared by magnitude
```

- **`sort -V`** ("version sort") splits each line into runs of digits and runs of non-digits, then compares the digit runs *numerically* instead of character-by-character — the standard fix for any hostname, filename, or version string with an embedded number of varying length.
- **IPs are the one case `-V` doesn't reliably solve** — an IP has *four* separate numeric runs (octets), and `-V`'s heuristic isn't specified to handle that correctly across all `sort` implementations. For IPs specifically, sort each octet as its own numeric field instead:
  ```bash
  sort -t. -k1,1n -k2,2n -k3,3n -k4,4n ip-list.txt
  ```
  `-t.` sets the field delimiter to a literal dot; `-k1,1n` through `-k4,4n` sort by each octet in turn, each numerically (`n`) — the explicit, always-correct version of the same "don't compare these as plain text" idea `-V` handles for simple version-like strings.

---

### Know the limit: CSV with quoted fields

**Goal:** a CSV field itself contains the delimiter — `"Smith, John",42,"New York, NY"` — and `cut -d,`/`awk -F,` will misparse it.

```bash
# This silently breaks — it sees 5 fields instead of 3:
awk -F, '{print $1}' quoted.csv     # -> "Smith  (wrong! quoting isn't understood)
```

Neither `cut` nor plain `awk -F,` understand CSV quoting rules — they split on every literal delimiter character, whether or not it's inside quotes. This isn't a flag you're missing; it's outside what these tools model at all. Once a field might legitimately contain the delimiter, reach for a tool that actually parses CSV: `csvkit` (`csvcut`, `csvgrep`), `mlr` (Miller — also handles JSON/TSV in the same query language), or a few lines of Python's `csv` module. Recognizing *this specific shape* (delimiter-inside-a-quoted-field) as the trigger to switch tools — rather than writing an increasingly elaborate `sed` regex to fake quote-awareness — is the useful skill here, more than the alternate tool names themselves.

---

### Deduplicate a huge file while preserving first-seen order

**Goal:** `sort | uniq` removes duplicates but also reorders everything — sometimes you need "unique, but in the order they first appeared."

```bash
awk '!seen[$0]++' bigfile.log
```

- **Why not `sort -u`?** `sort -u` dedupes but the output is alphabetically sorted, destroying the original order — wrong if order carries meaning (e.g., chronological log entries).
- **Reading `!seen[$0]++`** — `seen` is an associative array keyed by the whole line (`$0`). The first time a line is seen, `seen[$0]` is `0` (falsy) *before* the post-increment runs, so `!seen[$0]` is true and the line prints (bare truthy expression = implicit print); the increment then makes every later repeat of that line falsy on the `!`. One array, one pass, no re-sort — and it streams, unlike `sort` which must buffer the whole input before it can output anything.

---

## Part D — System & Process Inspection

### Find processes over a CPU/memory threshold

**Goal:** from `ps aux`, list only processes using more than 50% CPU.

```bash
ps aux | awk '$3+0 > 50 {print $2, $3, $11}'
```

- **`$3+0`** — forces numeric context on the `%CPU` column. Without it, a stray non-numeric value (like the header row's literal text `%CPU`) is compared as a *string*, which can behave unexpectedly next to a number — adding `+0` guarantees a real numeric comparison and non-numeric input just becomes `0` (and fails the `> 50` test harmlessly instead of matching by accident).
- **`$2, $3, $11`** — PID, %CPU, COMMAND in `ps aux`'s fixed column layout. This is inherently a little fragile (column *count* can shift with long command lines) — for anything you'll run unattended, prefer `ps -eo pid,pcpu,comm` (custom output format) over parsing the human-oriented default layout.

---

### Total memory used per process name (group-by, applied to `ps`)

**Goal:** several worker processes share a name (e.g., multiple `node` processes) — find total RSS memory across all of them combined, not per-PID.

```bash
ps -eo comm,rss --no-headers \
  | awk '{sum[$1]+=$2} END{for (c in sum) print sum[c], c}' \
  | sort -rn | head
```

- **`ps -eo comm,rss --no-headers`** — explicit output format (command name, resident set size in KB), no header row to accidentally aggregate as if it were data.
- **Same accumulator shape as the CSV group-by-sum recipe above** — `sum[$1]+=$2` groups by process name and totals memory, proving the technique isn't CSV-specific; it's "group by column A, sum column B," and it applies to any field-shaped input, including `ps` output.

---

### Extract fields from a system config file (`/etc/passwd`-style)

**Goal:** list every human user account (UID 1000+) on a box, ignoring system/service accounts.

```bash
awk -F: '$3 >= 1000 {print $1, $3}' /etc/passwd
```

- **`-F:`** — `/etc/passwd` is colon-delimited (`username:x:uid:gid:comment:home:shell`); setting the field separator is the entire adaptation needed to point `awk` at a new file format.
- **`$3 >= 1000`** — numeric comparison directly on a field, no cast needed here because `$3` (the UID) never contains non-numeric junk the way a mixed human-facing column might — contrast with the `$3+0` guard in the `ps` recipe above, which existed specifically because that column's first row *wasn't* numeric.

---

## Part E — File & Batch Operations

### Split a huge file into manageable chunks

**Goal:** a multi-GB log needs to be broken into pieces (for upload size limits, parallel processing, or just to stop your editor from choking).

```bash
split -l 100000 --numeric-suffixes --suffix-length=3 huge.log chunk_
```

- **`-l 100000`** — split every 100,000 lines instead of by byte size (`-b`), which matters when downstream tooling wants complete lines per chunk rather than a byte cut that could land mid-line.
- **`--numeric-suffixes --suffix-length=3`** — output files come out `chunk_000`, `chunk_001`, ... rather than the default alphabetic suffixes (`chunk_aa`, `chunk_ab`, ...) — numeric sorts and scripts against more naturally once there are more than 26 pieces.

---

### Batch-rename files by pattern

**Goal:** a directory of files uses the wrong extension case (`*.LOG` instead of `*.log`) and needs fixing in bulk.

```bash
for f in *.LOG; do
    mv -- "$f" "${f%.LOG}.log"
done
```

- **`${f%.LOG}`** — bash parameter expansion that strips the trailing `.LOG` suffix, so `access.LOG` becomes `access`, then `.log` is appended back — no external text tool needed for this one, since the "pattern" here is a fixed suffix, not something regex-shaped.
- **`--` before `"$f"`** — guards against a filename that happens to start with `-` being misread as an `mv` flag; a habit worth keeping any time a loop variable becomes a command argument (see `bash-loops-cookbook.md`).
- **When the rename logic is genuinely regex-shaped** (not just a fixed suffix swap), pipe filenames through `sed` to compute the new name: `new=$(sed -E 's/pattern/replacement/' <<< "$f")`, then `mv -- "$f" "$new"` — same loop, `sed` doing the harder part of the transform.

---

### Normalize whitespace and case

**Goal:** clean up a messy, human-typed data file before further processing — collapse repeated spaces, trim edges, standardize case.

```bash
awk '{ $1=$1; print }' messy.txt          # collapse internal runs of whitespace to one space each
sed -E 's/^[ \t]+|[ \t]+$//g' messy.txt   # trim only leading/trailing whitespace, keep interior spacing
tr '[:lower:]' '[:upper:]' < names.txt    # uppercase everything
```

- **`$1=$1` as a collapsing trick** — assigning a field to itself doesn't change its value, but it forces `awk` to rebuild `$0` from the fields using `OFS` (default: single space) — the side effect is that any run of multiple spaces/tabs between fields collapses to exactly one. A well-known trick that looks like a no-op until you know why it isn't.
- **Trim vs. collapse are different jobs** — the `sed` version only removes whitespace at the very start/end of the line and leaves interior spacing untouched, which is what you want when internal spacing is meaningful (e.g., fixed-width data) and only the edges are messy.

---

## Part F — Bridging into Structured Data: `jsonpath` / `jq`

Everything above assumes flat, line-oriented text where `grep`/`awk`/`sed` can reason about lines and fields directly. The moment your source is **structured** (JSON, and by extension `kubectl`'s underlying data model), field position stops being reliable — the same object can serialize with fields in a different order, nested at variable depth, or as an array of variable length. Grepping/awk-ing that text directly is fragile and breaks the moment formatting shifts.

The fix isn't a new category of tool — it's a different **extraction stage** at the front of the exact same pipeline shape used above. `kubectl -o jsonpath=...` or `jq` replaces the role `awk '{print $N}'` played for flat text: "pull the field(s) I care about out, and hand me back flat text." Everything after that extraction is the same `sort | uniq -c | grep | awk` toolbox as every recipe above.

### Count pods per node

```bash
kubectl get pods -A -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' \
  | sort | uniq -c | sort -rn
```
- **`jsonpath`** is doing exactly what `awk '{print $1}'` did in the IP-ranking recipe — extracting one field per record, flattened to one-per-line — except the record is a JSON object graph instead of a whitespace-delimited line, so it needs `.spec.nodeName` addressing instead of `$1` positional addressing.
- **Everything after the first pipe is identical to that earlier recipe.** That's the point: once the data is flattened to plain text, the k8s-ness of the source is irrelevant to the rest of the pipeline.

### Find pods stuck in a bad state, with a reason

```bash
kubectl get pods -A -o json \
  | jq -r '.items[] | select(.status.phase != "Running") | "\(.metadata.namespace)/\(.metadata.name)\t\(.status.phase)"' \
  | sort
```
- **`jq` over `jsonpath` here** — `jsonpath` is fine for simple field pulls (recipe above), but `jq` has real filtering logic (`select(...)`) and string interpolation, so reach for it once the query needs a *condition*, not just a field path — the same "grep vs awk" decision from the mental-model table at the top, just one layer up in structured-data land.
- **`\t` in the `jq` output** — deliberately building a tab-separated line means the *output* of this structured-data stage is now flat, tool-friendly text again — pipeable into `column -t`, `awk -F'\t'`, or `sort -k2` exactly like any other recipe in this file.

### Extract a ConfigMap value and reuse it in a normal pipeline

```bash
kubectl get configmap app-config -o jsonpath='{.data.app\.properties}' \
  | grep -E '^(timeout|retries)=' \
  | sed 's/=/: /'
```
- The `jsonpath` stage's *only* job is reaching one level into the ConfigMap's structure (the `.data` map, keyed by filename) to get back a plain-text blob — a `.properties` file's raw contents.
- Once that blob is out, it's just a text file again: `grep` filters lines, `sed` reformats them. This is the whole lesson of this section — jsonpath/jq is a **bridge out of structure and back into flat text**, not a replacement for anything above.

### When a JSON value is itself an encoded JSON string

**Goal:** some exports (VS Code `.code-profile`, some API responses that wrap a sub-document) don't nest JSON as real objects — a field's *value* is a plain string that happens to contain JSON text, escaped like any other string:

```json
{ "settings": "{\"editor.fontSize\":14,\"theme\":\"dark\"}" }
```

`.settings` here is **not** an object — `jq '.settings | type'` reports `"string"`, and reaching into it directly fails:

```bash
jq '.settings.["editor.fontSize"]' file.json
# jq: error: Cannot index string with string "editor.fontSize"
```

**What works — parse it explicitly with `fromjson`:**

```bash
jq '.settings | fromjson' file.json
# {
#   "editor.fontSize": 14,
#   "theme": "dark"
# }
```

`fromjson` re-parses the string's *contents* as JSON and hands back a real object/array you can then index normally (`.settings | fromjson | ."editor.fontSize"`).

**What doesn't work — "cleaning up" the escaping with `sed`.** A tempting shortcut is to just strip backslashes out of the raw text before it's even JSON-parsed. This corrupts real data, because `sed` has no concept of "this backslash is JSON string-escaping" vs. "this backslash is meaningful content" — it can't tell them apart, only a real JSON parser can:

```bash
# naive: strip every backslash
sed 's/\\//g' file.json
# turns "line1\r\nline2" into "line1rnline2"   (CRLF markers glued into the text)
# turns "C:\\Users\\me" into "C:Usersme"        (a real Windows path, mangled)
```

`fromjson` doesn't have this problem, because it understands JSON escape sequences (`\"`, `\\`, `\r`, `\n`, …) as a grammar, not as literal characters to delete.

**When you don't know *which* fields are encoded — walk the tree and try `fromjson` on every string:**

```bash
jq 'def deep:
  . as $orig
  | if type == "string" then (try (fromjson | deep) catch $orig)
    elif type == "object" then map_values(deep)
    elif type == "array" then map(deep)
    else . end;
deep' file.json
```

- Every string is tried as JSON; if it parses, recurse into the result (in case it's *itself* double-encoded); if it doesn't parse, it's a genuine plain string — keep it as-is.
- **The gotcha to know cold:** inside a `catch` block, `.` is rebound to the *error* jq threw, not the original input. Writing `catch .` (instead of `catch $orig`) silently replaces every non-JSON string with jq's own parse-error message — output still looks plausible (it's valid JSON, just wrong), which makes it an easy bug to ship unnoticed. Capturing `. as $orig` before the `try` and falling back to `$orig` is the fix.

---

## Part G — Proximity & Structural Search (finding related words)

Everything in Part A used `grep`/`awk` to find lines matching *one* pattern. A different, common question is relational: "do these two words appear *near* each other" — within N words, in the same sentence, or in the same paragraph. This needs a different mental model: instead of "does this line match," it's "how much text counts as 'near,' and how do I make the tool see that much at once."

### Two words within N words of each other, in either order

**Goal:** find where `IFS` and `default` are mentioned close together — evidence they're being discussed as related, not two unrelated hits in a long file.

```bash
grep -noP '\bIFS\b(?:\W+\w+){0,20}\W+\bdefault\b|\bdefault\b(?:\W+\w+){0,20}\W+\bIFS\b' notes.md
```

- **Why both orders, as an alternation** — "within 20 words" is symmetric (`IFS ... default` should match the same as `default ... IFS`), but regex matching isn't symmetric on its own — a pattern written `word1 ... word2` won't match text where `word2` comes first. Hence the `A...B|B...A` alternation, one branch per order.
- **`(?:\W+\w+){0,20}`** — a *non-capturing* group (`(?:...)`), repeated 0 to 20 times, where each repetition is "a separator, then a word." That's "up to 20 words in between." Non-capturing groups and bounded repetition on a group like this need `-P` (PCRE) — plain `-E` doesn't support `(?:...)`.
- **`\b`** on both target words — without it, `IFS` would also match as a substring of some longer identifier; `\b` pins each match to a whole word.
- **`-n`** shows the line number of each hit, so you can jump straight to it in an editor.

### Two words in the same sentence

**Goal:** the same question, but "near" means "same sentence" rather than a fixed word count — more forgiving of a long or short sentence in between.

```bash
awk 'BEGIN{RS="[.!?]"}  /IFS/ && /default/' notes.md
```

- **`RS="[.!?]"`** — `awk`'s Record Separator is normally a newline (one line = one record), but GNU `awk` allows `RS` to be a *regex*. Setting it to a sentence-ending punctuation class turns each **sentence** into one record, regardless of line breaks.
- **`/IFS/ && /default/`** — once a "record" means "a sentence," this is just two ordinary pattern checks `&&`-ed together, evaluated against the *whole current record* (`$0`) — the exact same "does this chunk of text match both patterns" question as any earlier recipe, just with a bigger unit of "this chunk."

### Two words in the same paragraph

**Goal:** the loosest version of "near" — anywhere in the same paragraph, however many sentences that spans.

```bash
awk -v RS='' '/IFS/ && /default/' notes.md
```

- **`RS=''` (paragraph mode)** — this is a special case `awk` recognizes: an empty `RS` means "records are separated by one or more blank lines," i.e., one paragraph per record, and (as a bonus) newlines *within* a paragraph collapse to a single field separator automatically.
- **Same `/IFS/ && /default/` check** — reused verbatim from the sentence version above. This is the payoff of the record-separator technique: once you've decided what "near" means, the actual search logic doesn't change at all — only what one record *is* changes. That's a more reliable way to think about "proximity search" than tuning a single regex's word-count bound tighter or looser.

---

## Part H — Log Research (finding clutter, judging whether it's safe to clear)

A different flavor of log question than Part A: not "extract a signal from this log" but "is this log even worth keeping, and is it safe to touch." That needs three things in sequence — find what's big, find what's *actually* wrong (not just string-matching the word "error"), and confirm nothing live is still writing to it before you clear anything.

### Find the biggest logs on a box

**Goal:** survey `/var/log` for what's actually taking up space, before deciding what to do about any of it.

```bash
sudo find /var/log -type f -printf '%s\t%p\n' \
  | sort -rn \
  | head -30 \
  | awk -F'\t' '{printf "%10.1f KB  %s\n", $1/1024, $2}'
```

- **`find -printf '%s\t%p\n'`** — emit size and path as a tab-separated pair per file; `-printf` is the one `find` action that can format numeric metadata (size, mtime) alongside the path in one pass, instead of a second `stat` call per file.
- **`sort -rn` on the whole `size\tpath` line** — numeric sort naturally sorts on the leading field, so no `-k` is needed here (contrast with the `sort -t: -k2` recipe in Part A, which needed a specific field because the number wasn't first).
- **`awk -F'\t'` at the end** — purely cosmetic, turning raw byte counts into a readable `KB` column; this is `awk` used for formatting, not extraction — a smaller, common role for it beyond "pull out a field."

### A file "has thousands of errors" — check if that's real before acting

**Goal:** `grep -ic error somefile.log` returns a huge number. Is the underlying service actually broken, or is that just how the log talks?

```bash
sudo grep -i "error" suspicious.log | sort | uniq -c | sort -rn | head -15
```

- This is the exact filter → sort → uniq -c → sort -rn shape from Part A's "count per hour" recipe, reused for a different purpose: instead of counting *distinct values of a field*, it's counting *distinct whole lines* — which surfaces whether "2,000 errors" is actually one message repeated 2,000 times (usually harmless, noisy-by-design daemon behavior) or 2,000 genuinely different failures (worth reading individually).
- **Why this beats reading `grep -ic`'s count alone** — a bare count answers "how many," not "how many *kinds*." `uniq -c` turns a scary number into a small, readable list of what's actually recurring, which is what you need to decide whether to act.

### Confirm a log is a one-time snapshot, not ongoing activity

**Goal:** before touching anything, know whether a log directory reflects something that happened once (e.g., an OS install) or something still being written to right now.

```bash
stat -c '%n: %y' /var/log/anaconda/*.log | sort
```

- **`stat -c '%n: %y'`** — `%n` is the filename, `%y` is the human-readable modification time; formatting both in one `stat` call across a glob avoids a loop calling `stat` once per file.
- If every file in a directory shares the same modification timestamp down to the second, that's strong evidence they were all written by one process run and never touched again — a log directory frozen in time, not a live one. Feeding the result through `sort` groups identical timestamps visually so the pattern is obvious at a glance.

### Is anything still writing to this log — check before you clear it

**Goal:** before truncating a log, confirm whether its owning service is currently running. If it is, truncating is often still safe (most daemons write with `O_APPEND`, so a live file descriptor just keeps appending past the new empty file) — but you want to *know* that going in, not assume it.

```bash
for svc in auditd rsyslog crond sshd; do
    st=$(systemctl is-active "$svc" 2>&1)
    echo "$svc: $st"
done
```

- **Looping `systemctl is-active` over a short, explicit list** — `is-active` is deliberately quiet (prints just `active`/`inactive`/`failed`, exit code matches), which makes it the right primitive for a status *check* rather than `systemctl status` (built for a human to read, not a script to branch on).
- **For a one-shot CLI tool rather than a daemon** (e.g., `dnf`, which writes `/var/log/dnf.log` per invocation but has no persistent process), `systemctl is-active` doesn't apply — there's no unit to ask. Use `pgrep -a <name>` instead to check whether *any* process by that name is currently running:
  ```bash
  pgrep -a dnf || echo "no running process — safe, nothing is mid-write"
  ```

### Clear a log in place without breaking the file descriptor a live process is holding

**Goal:** actually empty a log, once you've confirmed it's safe — without deleting the file (a running process holding it open by inode would keep writing to the now-unlinked file forever, invisible to `ls`).

```bash
sudo truncate -s 0 /var/log/dnf.log /var/log/dnf.librepo.log
```

- **`truncate -s 0` over `rm` + recreate, or `> file`** — `truncate` resizes the existing file in place (same inode, same permissions, same open file descriptors still valid), whereas `rm` followed by a new empty file is a *different* inode — any process still writing to the old one keeps doing so into a file no longer reachable by that path. `> file` (shell redirection) also truncates in place and works fine too — `truncate` is just more explicit and doesn't require a subshell/redirect target to exist first.
- **Why this is generally safe even for an actively-written log** — most logging is append-only (`O_APPEND`), which always writes at the current end-of-file regardless of where the file descriptor's cursor nominally sits; truncating doesn't corrupt that, it just makes "current end-of-file" become byte 0 again.

---

## Known limits — when these tools are the wrong tool

Knowing when *not* to reach for `grep`/`sed`/`awk` is as important as knowing the recipes above. Forcing one of these tools past what it actually models produces something that *usually* works and then breaks silently on the one input you didn't think of.

| Situation | Why line/field tools struggle | Reach for instead |
|---|---|---|
| CSV/TSV with quoted fields containing the delimiter | `cut`/`awk -F` split on every literal delimiter char, quoted or not | `csvkit`, `mlr` (Miller), Python's `csv` module |
| JSON / YAML | No concept of nested structure, only lines and fields | `jq` / `yq` — see the bridge section above |
| XML / HTML | Not line-oriented; tags nest and can span lines unpredictably | `xmllint`, `xmlstarlet`, or a real parser library (`lxml`, `BeautifulSoup`) |
| Binary or mixed binary/text data | Regex engines assume text; binary bytes can corrupt matching or your terminal | `strings` to pull printable text out first, `xxd`/`hexdump` for byte-level inspection |
| Deeply nested config blocks (nested braces of the same shape) | `sed` range addresses and simple `awk` flags can't track nesting depth | A brace-counting `awk` script (tracking depth with `gsub` counts), or the tool's own parser/linter |
| Fuzzy/approximate matching ("close to this string") | Regex is exact-pattern matching only, with no concept of edit distance | `agrep`, `fzf` for interactive fuzzy selection, or a proper fuzzy-matching library |
| Correlating two logs by *approximate* time (same event, timestamps a few ms/sec apart) | `join`/`awk` lookup tables need an exact matching key, not "close enough" | Truncate both timestamps to a shared coarser bucket first (e.g., same second/minute) and join on that; for real cross-service correlation, prefer trace IDs and an actual observability stack over regex-gluing timestamps |

The common thread: these tools model **lines and delimited fields**, nothing more. The moment the real structure is nested, quoted, binary, or approximate, you're fighting the tool instead of using it — that friction itself is the signal to switch.

---

## See Also

- `grep.md`, `sed.md`, `awk.md` — syntax reference for the individual tools used throughout this cookbook
- `grep-regex-ref.md` — BRE/ERE/PCRE differences relevant to the patterns used above, including the `-P` lookbehind recipe
- `linux/shell/bash-loops-cookbook.md` — the `while IFS= read -r line` idiom used in the live-tail recipe, and safe loop-variable handling used in the batch-rename recipe
- `linux/shell/process-substitution.md` — the `<(...)` used in the join and clean-diff recipes, and why a pipe wouldn't work there
- `yq-jq-bat.md` — `jq`/`yq` syntax reference for the structured-data section above
