# `grep` guide  - Searching in Files

## Basic Syntax

```bash
grep [options] pattern [file...]
grep "word" file.txt
grep "word" file1.txt file2.txt
```

---

## Common Options

```bash
-i          # Case-insensitive match
-v          # Invert match (lines that do NOT match)
-n          # Show line numbers
-c          # Count matching lines
-l          # List only filenames with matches
-L          # List only filenames WITHOUT matches
-r          # Recursive search in directories
-R          # Recursive, follows symlinks
-w          # Match whole words only
-x          # Match whole lines only
-q          # Quiet mode (exit code only, no output)
-s          # Suppress error messages
```

---

## Output Control

```bash
-o          # Print only the matched part
-h          # Suppress filename prefix
-H          # Always print filename prefix
--color     # Highlight matches
-m 5        # Stop after 5 matches
```

---

## Context Lines

```bash
-A 3        # 3 lines After match
-B 3        # 3 lines Before match
-C 3        # 3 lines before and after (Context)
```

---

## Regex Modes

```bash
grep  "pattern"   # Basic regex (BRE) - default
grep -E "pattern" # Extended regex (ERE) - same as egrep
grep -P "pattern" # Perl-compatible regex (PCRE)
grep -F "pattern" # Fixed string (no regex) - same as fgrep
```

---

## Pattern Examples

```bash
grep "^start"          # Lines starting with "start"
grep "end$"            # Lines ending with "end"
grep "^$"              # Empty lines
grep "c.t"             # c + any char + t  (cat, cut, cot…)
grep "colou\?r"        # BRE: optional 'u'  (color or colour)
grep -E "colou?r"      # ERE: same
grep -E "cat|dog"      # Either "cat" or "dog"
grep -E "^(foo|bar)"   # Lines starting with foo or bar
grep -E "[0-9]{3}"     # Three consecutive digits
grep -E "\b\w{5}\b"    # Exactly 5-letter words
grep -P "\d{4}-\d{2}"  # PCRE: date-like pattern
```

---

## Recursive & File Filtering

```bash
grep -r "TODO" .                        # Search all files under current dir
grep -r "TODO" . --include="*.py"       # Only .py files
grep -r "TODO" . --exclude="*.log"      # Exclude .log files
grep -r "TODO" . --exclude-dir=".git"   # Exclude a directory
```

---

## Multiple Patterns

```bash
grep -e "foo" -e "bar" file.txt         # Match foo OR bar
grep -f patterns.txt file.txt           # Read patterns from file
```

---

## Decoding Combined Flags (`-Evo`, `-rEvo`, …)

Single-dash short options stack — `-Evo` is exactly the same as `-E -v -o`,
in any order (`-voE` behaves identically). There's no special meaning to a
combo beyond "each letter's own effect, applied together." Read a combo by
splitting it back into single letters and looking each one up individually.

```bash
grep -Evo "pattern" file    # = grep -E -v -o "pattern" file
grep -rEvo "pattern" .      # = grep -r -E -v -o "pattern" .
grep -Eno "pattern" file    # = grep -E -n -o "pattern" file
grep -rli "pattern" .       # = grep -r -l -i "pattern" .
```

**Letter-by-letter meaning of the ones you'll see stacked most:**

| Letter | Meaning |
|---|---|
| `E` | extended regex mode (lets you use `\|`, `+`, `?`, `{}` without escaping) |
| `v` | invert match — keep lines that do NOT match |
| `o` | print only the matched substring, not the whole line |
| `r` | recurse into directories |
| `i` | case-insensitive |
| `n` | show line numbers |
| `l` | filenames only (with a match) |
| `c` | count matching lines |
| `w` | whole-word match |
| `x` | whole-line match |
| `P` | Perl-compatible regex (PCRE) |

**Reading a few real combos:**

```bash
grep -Evo "^#.*"           # E: use regex alternation/groups freely
                            # v: keep lines that do NOT start with #
                            # o: print only the matched part (here, the whole non-comment line)

grep -rEvo "^$" . --include="*.txt"
                            # r: search recursively
                            # E: extended regex
                            # v: invert — keep non-empty lines
                            # o: print only the match (the line's content, since ^$ can't match a non-empty line anyway — v does the real work here)

grep -rli "error" /var/log  # r: recurse, l: filenames only, i: case-insensitive
                            # → "which log files mention 'error' or 'Error', case-insensitive"
```

**Gotcha:** an option that *takes a value* (like `-A 3`, `-m 5`, `-e pattern`)
breaks the stacking chain — it can still be glued onto the end of a combo
(`-rn3A` doesn't work, but `-rnA 3` does, since `-A` needs its own argument
right after it). When in doubt, keep value-taking flags separate from
letter-only stacks.

---

## Practical Combos

```bash
grep -rn "TODO" . --include="*.js"      # Find TODOs with line numbers in JS files
grep -v "^#" config.conf                # Strip comments
grep -c "" file.txt                     # Count all lines (like wc -l)
grep -rl "secret" /etc/                 # List files containing "secret"
grep -i "error" app.log | grep -v "404" # Errors excluding 404s
grep -Po '(?<=user=)\w+' file.txt       # Extract value after "user="
```

---

## Exit Codes

```bash
0   # Match found
1   # No match
2   # Error (bad option, file not found, etc.)
```

```bash
grep -q "pattern" file && echo "found" || echo "not found"
```

---

## Binary Files & Archives

`grep` has no concept of compression — it just matches bytes. Against a compressed
file (`.gz`, `.zip`, `.xz`, …) it detects binary content and prints
`binary file matches` instead of dumping garbage, since a regex pattern almost
never survives compression intact.

```bash
grep -a "pattern" file.gz     # force text search anyway (usually meaningless)
grep --binary-files=text ...  # same, more explicit
-I                            # opposite: skip binary files entirely (like --binary-files=without-match)
```

To search compressed files properly, decompress on the fly instead — either
manually or with the wrapper tools below.

```bash
zcat app.log.gz | grep "ERROR"   # manual equivalent of zgrep
```

---

## The `*grep` Family

Running `grep -r grep /usr/bin/ -l | grep -Eo "[a-z]*grep" | sort -u` on most
Linux boxes turns up a whole family of variants. They fall into three groups:

**Deprecated aliases (same binary, different regex mode)**
```bash
egrep "pattern"   # = grep -E   (extended regex)
fgrep "pattern"   # = grep -F   (fixed string, no regex)
```
Both print a deprecation warning in GNU grep — prefer `grep -E` / `grep -F` directly.

**Compressed-file wrappers** — decompress to a pipe, then grep the result:
```bash
zgrep "pattern" file.gz     # gzip
zegrep / zfgrep             # -E / -F versions for gzip
bzgrep "pattern" file.bz2   # bzip2
xzgrep "pattern" file.xz    # xz / lzma
zstdgrep "pattern" file.zst # zstd
zipgrep "pattern" file.zip  # unzip -p each member, then egrep
```

**Unrelated tools that just share the name**
```bash
pgrep -f nginx     # search running PROCESSES by name, not file contents
msggrep            # search gettext .po/.pot translation catalogs (i18n)
```

| Binary | Searches |
|---|---|
| grep, egrep, fgrep | plain text |
| zgrep, zegrep, zfgrep | `.gz` |
| bzgrep | `.bz2` |
| xzgrep | `.xz` / `.lzma` |
| zstdgrep | `.zst` |
| zipgrep | `.zip` contents (per member) |
| pgrep | process list (unrelated to file search) |
| msggrep | gettext catalogs (unrelated to file search) |

---

## `ripgrep` (`rg`) — Modern Alternative

Not part of base RHEL/Rocky — install from EPEL:

```bash
sudo dnf install epel-release
sudo dnf install ripgrep
```

`rg` behaves like `grep` but recursive and `.gitignore`-aware by default, and
noticeably faster on large trees. Most `grep` flags carry over unchanged.

```bash
rg "pattern"                  # recursive search from cwd, respects .gitignore
rg "pattern" -i               # case-insensitive
rg "pattern" -l               # filenames only
rg "pattern" -A 3 -B 3        # context lines, same as grep
rg "pattern" -g "*.yaml"      # only .yaml files (like --include)
rg "pattern" -g "!*.log"      # exclude .log files
rg -F "literal string"        # fixed-string mode
rg --hidden "pattern"         # also search dotfiles (skipped by default)
rg -uu "pattern"              # ignore .gitignore too (search everything)
```

Caveat: `rg` isn't preinstalled on bare RHEL/Rocky nodes (bastion, control
plane, workers in this repo's cluster) unless EPEL is added there too — plain
`grep -r` is still the fallback that's guaranteed to work when SSH'd into a
node with no extra packages.