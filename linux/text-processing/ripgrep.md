# `ripgrep` (`rg`) guide — the swiss-army-knife search tool

Verified against `rip-grep-manual.txt` (ripgrep 14.1.1, shipped in this
directory) and `rg --version` on this box. Companion docs for two narrower
gotchas: `ripgrep-example.md` (glob syntax broken down piece by piece) and
`ripgrep-glob-and-sort.md` (glob precedence, anchoring, `--sort` perf trap).

## Basic Syntax

```bash
rg [options] PATTERN [PATH ...]
rg -e PATTERN [PATH ...]        # -e lets PATTERN start with a dash
rg -f patternfile.txt [PATH]    # one pattern per line, from a file
command | rg PATTERN            # search stdin like grep
```

Unlike `grep`, no `-r`/`-R` needed — recursive search **is the default**, and
`rg` auto-skips `.gitignore`d files, hidden files, and binary files unless
told otherwise (see Filtering below).

---

## Common Options

```bash
-i          # Case-insensitive
-S          # Smart case: insensitive only if pattern is all-lowercase (rg default off; often aliased on)
-s          # Force case-sensitive (overrides -i/-S)
-v          # Invert match — lines that do NOT match
-n          # Line numbers (default when stdout is a tty)
-N          # Suppress line numbers
-c          # Count matching lines per file (not total matches — see --count-matches)
-l          # List only filenames with matches
--files-without-match   # List only filenames with ZERO matches
-w          # Match whole words only
-x          # Match whole lines only (entire line must match)
-F          # Fixed string, no regex — like grep -F/fgrep
-m NUM      # Stop after NUM matching lines per file
-q          # Quiet — exit code only, useful in scripts
```

---

## Output Control

```bash
-o                  # Print only the matched text, one per line
-r 'REPLACEMENT'    # Show what a substitution WOULD look like — never edits files
-A 3 / -B 3 / -C 3  # After / Before / Context lines, same meaning as grep
-H / -I             # Force-show / force-hide the filename prefix
--column            # 1-based column numbers (implies -n)
-b                  # Byte offset before each line
--heading           # File path as a heading above each file's matches (default on tty)
-p, --pretty        # Force colors+heading+line numbers even when piped
--json              # JSON Lines output — for editor/tool integration, not eyeballing
--vimgrep           # One line per match (not per matching line) — quickcfix-style
```

`-r/--replace` is preview-only. Nothing in ripgrep ever writes to files —
pipe to `sed`/`sd` if you actually want to edit in place.

---

## Filtering: what gets searched

```bash
-g '*.md'            # Include glob — gitignore syntax
-g '!README.md'      # Exclude glob (leading !)
-t py -t md          # Only these file TYPES (see --type-list)
-T py                # Exclude this file TYPE
--type-list          # Show every built-in type and its globs
-. , --hidden        # Also search dotfiles/dotdirs (off by default)
-u                   # Unrestricted: same as --no-ignore (repeat up to 3x, see below)
-uu                  # = --no-ignore --hidden
-uuu                 # = --no-ignore --hidden --binary (closest to "search literally everything")
--no-ignore          # Ignore .gitignore/.ignore/.rgignore entirely
-d, --max-depth NUM  # Limit recursion depth
-L, --follow         # Follow symlinks (off by default)
```

**Glob gotchas** (full writeup in `ripgrep-glob-and-sort.md`):
- A bare `-g foo` matches only a top-level file/dir named `foo`, not
  `foo/bar.txt` — anchor a whole subtree with `-g 'foo/**'`.
- Multiple `-g` flags: if more than one matches the same path, **the one
  given later on the command line wins** — order matters for include/exclude
  combos like `-g '*.md' -g '!README.md'`.
- Two separate `-g`/`-t` flags are OR'd together (matches either); one glob
  string with `{a,b,c}` brace expansion is AND'd against the rest of that
  pattern in one shot. Mixing these two mental models up is the #1 way a glob
  "should" match but doesn't — see `ripgrep-example.md`.

---

## Regex Notes

```bash
rg "cat|dog"          # Alternation works WITHOUT -E — rg regex is ERE-like by default
rg -F "a.b(c)"        # Literal string, no escaping needed
rg -P "(?<=foo)bar"   # PCRE2 engine — lookaround, backreferences
rg --engine=auto       # Let rg pick default vs PCRE2 per-pattern automatically
rg -U "foo\nbar"      # Multiline mode — lets a match span line breaks (see caveat below)
```

Two differences from `grep` worth internalizing:
- `rg`'s **default** regex engine already supports ERE-style alternation and
  `+`/`?`/`{n,m}` unescaped — there's no BRE-vs-ERE split like `grep` vs
  `grep -E`. Use `-P`/`--pcre2` only when you need lookaround or
  backreferences, which the default engine can't do.
- Case sensitivity precedence when flags conflict: `-s` overrides `-i` and
  `-S`; `-i` overrides `-s` and `-S`; `-S` (smart case) only applies when
  neither of the other two is given.

`-U`/`--multiline` caveat: `.` still does **not** match `\n` by default even
in multiline mode — you need `(?s)` inline or `--multiline-dotall` to make
`.` cross line boundaries. Multiline search also disables the normal
memory-mapped fast path, so it's slower on large trees.

---

## Sorting & Performance

```bash
--sort=path            # Alphabetical
--sort=modified         # By mtime, ascending
--sortr=modified        # By mtime, descending
```

**Any** `--sort`/`--sortr` value other than the default `none` forces `rg` to
abandon its parallel directory walk and run single-threaded — this is
explicit in the manual and easy to miss. Don't reach for `--sort=modified` on
a big tree unless you actually need the ordering; pipe to `sort` afterward if
you just want stable output for a script. Full detail in
`ripgrep-glob-and-sort.md`.

---

## Practical Recipes

```bash
rg --files | rg 'test.*\.py$'               # list files, filter path by name — no content search
rg --files -g '*.py'                        # same, but faster (glob is a filter, not a regex over paths)
rg -tpy -l "import requests"                # only .py files (rg's type, not a glob)
rg -A2 -B2 "ERROR" app.log                  # grep-style context lines on a single file
rg -i --stats "pattern"                     # add aggregate match/file/time stats to the output
```

Each of these is a one-liner where the flag *is* the whole recipe. The rest
of this section is for recipes where the payoff comes from **combining**
`rg` with another tool or flag in a way that isn't obvious from the flag
list above. Verified against ripgrep 14.1.1 in a scratch git repo.

---

## Cookbook

### Rank files by how many TODO/FIXME lines they contain

**Goal:** across a repo, find the worst offenders for leftover TODOs, most first.

```bash
rg -c -e 'TODO' -e 'FIXME' . | sort -t: -k2 -rn
```
```
./a.py:2
./sub/b.py:1
```

- **`-c` (count)** — `rg -c` reports matching **lines** per file as
  `path:count`, not a flat list of every hit — that shape is exactly what
  `sort -t: -k2 -rn` needs to rank by.
- **`-e 'TODO' -e 'FIXME'`** — two `-e` patterns are OR'd: a line counts if it
  matches *either*. Equivalent to `rg -c 'TODO|FIXME'`, but `-e` reads
  better once you have three or more terms.
- **`sort -t: -k2 -rn`** — same "rank by count" shape as
  `text-process-cookbook.md`'s log recipes, just fed by `rg -c` instead of
  `uniq -c`.

---

### Search only the files a `git diff` touched

**Goal:** after editing a batch of files, re-check just those files for a
leftover debug pattern — not the whole tree.

```bash
rg "console\.log" $(git diff --name-only)
```

- `git diff --name-only` prints changed paths, one per line; command
  substitution turns that into `rg`'s positional `PATH...` arguments.
- This bypasses `rg`'s own directory walk and gitignore filtering entirely —
  you're handing it an explicit file list, so even a gitignored file passed
  this way *would* get searched (positional paths override ignore rules,
  per the manual's PATH description).
- Swap in `git diff --name-only --cached` for staged-only, or `git diff
  --name-only main...HEAD` for "everything this branch changed."

---

### Preview a find-and-replace before actually editing

**Goal:** confirm a substitution looks right before running `sed -i` for real.

```bash
rg -o -r 'DONE' 'TODO' a.py
```
```
DONE
```

- `-r/--replace` only changes what `rg` **prints** — it can't and doesn't
  touch the file, which makes it a safe dry run.
- `-o` narrows the output to just the matched-and-replaced text; drop it to
  see the replacement in the context of the full line instead.
- Once the preview looks right, hand the same pattern to the tool that
  actually edits in place: `sed -i 's/TODO/DONE/' a.py` (see `sed.md`), or
  `sd` if it's installed.

---

### Feed matching filenames to another command, safely

**Goal:** run a second command against every file that matched, without
breaking on filenames containing spaces.

```bash
rg -l -0 "TODO" | xargs -0 -I{} echo "would touch: {}"
```
```
would touch: file with space.py
would touch: a.py
would touch: sub/b.py
```

- **`-l` (files-with-matches)** switches `rg` to filename-only output.
- **`-0`** NUL-terminates each printed filename instead of newline-terminating
  it — the same trick `find -print0` uses — so a name like `file with
  space.py` survives the pipe as one argument.
- **`xargs -0`** is the required matching half; without it, `xargs` still
  splits on whitespace and the NUL-termination buys nothing.

---

### Search everything, ignore rules and all, when a file is "missing"

**Goal:** you know a string is in the working tree somewhere, but plain `rg`
finds nothing — usually because the file is gitignored.

```bash
rg "leaked" .        # nothing — respects .gitignore by default
rg -uu "leaked" .    # --no-ignore --hidden — now it shows up
```

- Confirmed against a scratch repo with a `.gitignore`'d `secret.log`: the
  plain search exits `1` (no match, per ripgrep's exit-code convention), and
  `-uu` finds it.
- Reach for `-uu` before `-uuu` — `-uuu` additionally searches binary files,
  which is rarely what you want and can dump garbage to your terminal.

---

### Whole-word match to cut false positives

**Goal:** find calls to a short function name (`cat`) without matching it as
a substring of unrelated identifiers (`concatenate`).

```bash
rg "cat" words.txt      # matches both "cat" and "concatenate"
rg -w "cat" words.txt   # matches only the standalone word "cat"
```

- `-w` wraps the pattern in word-boundary assertions — the same fix as
  `grep -w`, and worth reaching for by default on short identifier searches
  across a codebase, where substring collisions are common (`id` inside
  `valid`, `is` inside `this`, etc).

---

## `rg` vs `grep` — quick translation

| Task | `grep` | `rg` |
|---|---|---|
| Recursive search | `grep -r` | `rg` (default) |
| Respect `.gitignore` | n/a | default behavior |
| Search everything, ignore included | `grep -r --exclude-dir=...` | `rg -uu` |
| Extended regex | `grep -E` | default engine (no flag needed) |
| PCRE | `grep -P` | `rg -P` (optional PCRE2 engine) |
| Filter by extension | `grep -r --include='*.py'` | `rg -tpy` or `rg -g '*.py'` |

---

## See Also

- `ripgrep-example.md` — one real `--iglob` command taken apart piece by
  piece, including the OR-vs-AND glob distinction
- `ripgrep-glob-and-sort.md` — glob precedence, anchoring, and the
  `--sort` single-thread perf trap, each cited against manual line numbers
- `rip-grep-manual.txt` — full `rg --help` text this guide is checked
  against (ripgrep 14.1.1)
