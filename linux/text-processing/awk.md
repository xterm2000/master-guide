# `awk` guide — Field/Record Processing

## Basic Syntax

```bash
awk 'pattern { action }' file
awk '{ print }' file
awk -F: '{ print $1 }' /etc/passwd
```

awk reads input **record by record** (lines, by default), splits each record into **fields** (whitespace-delimited, by default), and runs `{ action }` for every record where `pattern` matches (an empty pattern matches every record).

---

## Records & Fields — The Built-in Variables

| Variable | Meaning |
|---|---|
| `$0` | the whole current record (line) |
| `$1`, `$2`, ... | individual fields |
| `NF` | number of fields in the current record |
| `NR` | current record number (running total across all input files) |
| `FNR` | current record number **within the current file** (resets per file) |
| `FS` | input field separator (default: any run of whitespace) |
| `OFS` | output field separator (default: single space) |
| `RS` / `ORS` | input/output record separator (default: newline) |
| `FILENAME` | name of the file currently being read |

```bash
awk '{ print $1, $3 }' file            # print columns 1 and 3
awk -F, '{ print $2 }' file.csv        # comma-delimited field 2
awk '{ print $NF }' file               # last field, regardless of field count
awk '{ print $(NF-1) }' file           # second-to-last field
```

---

## Patterns — Selecting Which Records to Act On

```bash
awk 'NR==3' file              # print only line 3 (bare pattern = implicit { print })
awk 'NR>=2 && NR<=5' file     # line range
awk '/ERROR/' file            # lines matching a regex (like grep)
awk '!/ERROR/' file           # invert match (like grep -v)
awk 'length($0) > 80' file    # lines longer than 80 chars
awk '$3 > 100' file           # numeric comparison on a field
```

A bare pattern with no `{ action }` defaults to `{ print }` — that's why `awk 'NR==3' file` alone works as a one-liner.

---

## BEGIN / END Blocks

Run once before any input is read / once after all input is processed — useful for setup and totals:

```bash
awk 'BEGIN{ print "start" } { print } END{ print "end" }' file
awk '{ sum += $1 } END{ print sum }' file            # sum a column
awk 'BEGIN{ FS="," } { print $2 }' file               # set FS before reading
```

`NR`/`NF` are meaningless inside `BEGIN` — no record has been read yet.

---

## Rebuilding `$0` — the `OFS` Gotcha

Modifying a field (`$2 = "x"`) does **not** immediately re-render `$0` using `OFS` — you have to force a rebuild by reassigning any field (commonly `$1=$1`), or `$0` stays byte-for-byte as it was, spacing and all:

```bash
awk 'BEGIN{ OFS="\t" } { $1=$1; print }' file    # reformat with tabs, forcing a rebuild
awk -F, 'BEGIN{ OFS="," } { $3=""; print }' file  # blank out field 3, keep commas
```

Without the `$1=$1` trick, changing `OFS` alone does nothing visible, because `$0` was never rebuilt.

---

## String Functions

```bash
length($0)                    # length of a string
substr(s, m, n)                # substring from position m, length n
split(s, arr, sep)             # split s into array arr[] on sep, returns count
sub(/re/, "repl")              # replace FIRST match in $0 (or a given var), in place
gsub(/re/, "repl")             # replace ALL matches, in place — returns count of replacements
match(s, /re/)                 # returns index of first match (0 if none); also sets RSTART/RLENGTH as a side effect
index(s, "substr")             # position of a literal substring (no regex)
toupper(s) / tolower(s)        # case conversion
sprintf(fmt, ...)              # like printf but returns a string instead of printing
```

```bash
awk '{ gsub(/foo/, "bar"); print }' file            # global replace, like sed 's/foo/bar/g'
awk '{ print toupper($0) }' file
awk '{ n = split($0, arr, ":"); print arr[1] }' file
awk '{ if (match($0, /[0-9]+/)) print substr($0, RSTART, RLENGTH) }' file   # extract the matched text itself
```

`match()` only tells you *whether* and *where* a match happened — `RSTART` (starting position) and `RLENGTH` (match length) are how you then pull the actual matched substring back out with `substr()`, since `match()` itself has no return-the-text option the way `grep -o` does.

---

## Arrays (Associative — Keyed by String)

"Associative" just means the index doesn't have to be a sequential integer (`arr[0]`, `arr[1]`, ...) — any string can be a key, the way a Python `dict` or a bash associative array (`arrays.md`) works. `count[$1]++` below uses whatever text is in field 1 as the key directly, with no separate indexing step.

```bash
awk '{ count[$1]++ } END{ for (k in count) print k, count[k] }' file   # frequency count per field
awk '!seen[$0]++' file                                                  # dedupe lines, preserve order (no sort needed)
```

`!seen[$0]++` is a classic idiom: `seen[$0]` starts at 0 (falsy) the first time a line appears, so `!seen[$0]` is true and the line prints; the `++` then bumps it, so every repeat is falsy and gets skipped.

---

## Regex in awk

awk's regex flavor is **ERE**-like (same family as `grep -E`), no PCRE lookaround/backreferences in POSIX awk. gawk adds a few GNU extensions (e.g. `gensub()` with backreferences), but not lookaround.

`gensub()` is gawk-only (not in POSIX awk/mawk) and, unlike `sub`/`gsub`, doesn't mutate in place — it returns a new string, and its replacement text can reference captured groups with `\1`, `\2`, same as sed's `-E`:

```bash
awk '{ print gensub(/([0-9]+)-([0-9]+)/, "\\2-\\1", "g") }' file   # swap two numbers around a dash, non-destructively
```
The third argument (`"g"` here, or a number like `"1"` for just the first match) is mandatory — it plays the same role as sed's `g` flag.

```bash
awk '$0 ~ /pattern/'                          # field/record matches regex
awk '$1 !~ /pattern/'                         # field does NOT match
awk -F: '$1 ~ /^root|^admin/ { print }' /etc/passwd
```

---

## `printf` Formatting

```bash
awk '{ printf "%-10s %5d\n", $1, $2 }' file   # left-pad name, right-pad number
```
Unlike `print`, `printf` doesn't auto-append a newline or `OFS` — you control formatting and spacing entirely yourself.

---

## Multiple Files — `NR` vs `FNR`

```bash
awk 'FNR==1{ print FILENAME }' file1 file2    # print the filename at the start of each file
```
`NR` keeps counting across every file in sequence; `FNR` resets to 1 at the start of each new file. `FNR==NR` is only true while awk is still reading the *first* file (since both counters climb in lockstep there) — once the second file starts, `FNR` resets to 1 but `NR` keeps climbing, so they diverge. That's the switch used in the classic two-file "join" pattern: stash data from file 1 while `FNR==NR`, then look it up while processing file 2:

```bash
awk 'FNR==NR { price[$1]=$2; next } { print $1, price[$1] }' prices.txt orders.txt
# prices.txt: sku -> price, loaded into an array while reading file 1 ('next' skips to next record, never reaching the second block)
# orders.txt: sku -> looked up against the array built from file 1
```

---

## Practical Combos

```bash
awk -F: '{ print $1 }' /etc/passwd | sort                  # list usernames
df -h | awk '$5+0 > 80 { print $1, $5 }'                    # disks over 80% (+0 coerces "83%" to a number)
ps aux | awk '$3 > 50 { print $2, $3, $11 }'                # high-CPU processes (PID, %CPU, command)
kubectl get pods | awk 'NR>1{ print $1 }'                   # skip header line, print pod names
awk 'BEGIN{ srand(); print int(rand()*100) }'               # random int 0-99
netstat -tn | awk '{ print $6 }' | sort | uniq -c | sort -rn  # count connections by state
```

---

## Gotchas / Side Cases

- **`FS` of one char is literal; more than one char is a regex.** `FS="."` is treated as regex "any character," not a literal dot — you need `FS="\\."` (or `FS="[.]"`) to split on an actual period.
- **Default `FS` collapses whitespace runs** — unlike `cut -d' '`, awk's default field splitting treats any run of spaces/tabs as one delimiter, so ragged-column input still splits cleanly.
- **Fields beyond `NF` are empty, not errors** — `awk '{ print $10 }'` on a 3-field line silently prints a blank line, never fails.
- **String vs numeric comparison is heuristic.** awk guesses "looks like a number" from context. `"10" > "9"` compares numerically if both look numeric (10 > 9, true), but zero-padded fields like `"007"` vs `"8"` can trip this up if one side is forced to string context — be explicit with `+0` when you need numeric coercion.
- **`printf "%d"` truncates, it doesn't round.** `awk 'BEGIN{printf "%d\n", 3.9}'` prints `3`, not `4`.
- **`gsub`/`sub` mutate their target in place** and *also* return the count of replacements made — useful for "did this line have a match" checks without a separate `match()` call.
- **Uninitialized variables are `""` or `0`** depending on context, which is why `sum += $1` works with no `sum=0` initializer beforehand.
- **`BEGIN`/`END` each run exactly once**, regardless of how many input files are given — not once per file (that's what `FNR==1` /  end-of-file tricks are for).

---

## `awk` vs `sed` vs `grep` vs `tr` — when to reach for which

- **grep**: keep/remove whole lines based on a pattern.
- **sed**: line-oriented transformation — substitution, insertion, simple range edits.
- **awk**: field/column-oriented processing — arithmetic, arrays, structured multi-column reports, anything needing real variables or logic.
- **tr**: character-level translation/deletion — no regex, no lines/fields, just character sets. See `sed.md` (which also covers `tr`), `grep.md`, and `grep-regex-ref.md` for the others.
