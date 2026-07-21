# `sed` guide — Stream Editor

## Basic Syntax

```bash
sed [options] 'command' file
sed -i 's/old/new/' file          # in-place edit
echo "text" | sed 's/foo/bar/'
```

sed reads input **line by line** into a "pattern space," applies your commands to it, then prints the result (unless `-n` suppresses that).

---

## Common Options

```bash
-n          # suppress auto-print (use with 'p' to print only what you want)
-e          # add another expression (for multiple -e's on one command line)
-f file     # read script from a file
-i          # in-place edit (GNU: -i works bare; BSD/macOS: needs -i '' with an explicit arg)
-i.bak      # in-place edit, keep a .bak backup of the original
-r / -E     # extended regex (ERE) instead of default BRE — same flavor split as grep
-z          # NUL-separated records instead of newline-separated (for filenames, binary-safe)
```

`-z` swaps sed's record separator from `\n` to the NUL byte (`\0`) — the same separator `find -print0` and `xargs -0` use, specifically because filenames can legally contain newlines but never a NUL byte. Pairing `find -print0 | ... sed -z ...` is how you safely process a list of filenames with no ambiguity about where one ends and the next begins.

---

## The `s///` Substitution Command

```bash
sed 's/pattern/replacement/flags'
```

| Flag | Meaning |
|---|---|
| (none) | replace first match per line |
| `g` | replace **all** matches per line |
| `N` | replace only the Nth match |
| `Ng` | replace from the Nth match onward |
| `i` / `I` | case-insensitive match |
| `p` | print the result (useful with `-n`) |

```bash
sed 's/foo/bar/'      # first occurrence per line
sed 's/foo/bar/g'     # every occurrence
sed 's/foo/bar/2'     # only the 2nd occurrence
sed 's/foo/bar/2g'    # 2nd occurrence onward
```

### Delimiters don't have to be `/`

Any character works as the delimiter — pick one that isn't in your pattern to avoid a wall of escaped slashes:

```bash
sed 's#/etc/old/path#/etc/new/path#'   # paths — # avoids escaping every /
sed 's|foo|bar|'
```

---

## Backreferences & Capture Groups

Same BRE/ERE split as grep — see `grep-regex-ref.md` for the full flavor comparison.

```bash
sed 's/\(.*\)/[\1]/'                       # BRE: parens must be escaped to capture
sed -E 's/(\w+)@(\w+)/\2@\1/'              # ERE: swap two captured groups (user@host -> host@user)
sed -E 's/([0-9]+)-([0-9]+)/\2-\1/'        # swap two numbers around a dash
```

---

## Address / Line Selection

sed commands can be scoped to specific lines or a pattern range before running:

```bash
sed -n '3p'              # print only line 3
sed -n '2,5p'             # print lines 2-5
sed '2,5d'                # delete lines 2-5
sed '/pattern/d'          # delete every line matching pattern
sed '/start/,/end/d'      # delete everything from a "start" match to an "end" match (inclusive)
sed '$d'                  # delete the last line
sed -n '$p'               # print only the last line
sed -n '1!p'              # print everything EXCEPT line 1  ('!' negates the address)
sed -n '0~2p'             # GNU extension: print every 2nd line, starting at line 2
```

`/start/,/end/` ranges are **stateful per scan** — if "start" matches again later in the file, sed re-opens the range and starts deleting/printing again from there.

---

## Insert / Append / Change

```bash
sed '2i\Text inserted before line 2'
sed '2a\Text appended after line 2'
sed '2c\Replacement text for line 2'
```

GNU sed also accepts these without the trailing backslash-newline dance required by POSIX sed (`sed '2a Text'` works fine on GNU, but the classic form is more portable to BSD/POSIX sed). The classic (portable) form looks like this — the backslash escapes the newline so the shell and sed both treat the following line(s) as the text to insert:

```bash
sed '2a\
Text appended after line 2'
```

That's a real embedded newline between `\` and the text, not a literal `\n` — this is the same "backslash-continued line" mechanism referenced in the `\n`-in-replacement gotcha below.

---

## Multiple Commands

```bash
sed -e 's/foo/bar/' -e 's/baz/qux/'    # two separate -e expressions
sed 's/foo/bar/; s/baz/qux/'           # same thing, semicolon-joined in one expression
```

---

## In-Place Editing — Portability Gotcha

```bash
sed -i 's/foo/bar/' file          # GNU sed: fine, edits in place, no backup
sed -i.bak 's/foo/bar/' file      # GNU sed: edits in place, keeps file.bak
sed -i '' 's/foo/bar/' file       # BSD/macOS sed: REQUIRES the explicit '' argument
```

Running the GNU-style `sed -i 's/.../.../'  file` on macOS/BSD sed either errors out or (worse) silently treats `'s/.../.../.'` as the backup-suffix argument and clobbers your file with no output. Always test on a copy first when moving a sed one-liner between GNU and BSD systems.

---

## Practical Combos

```bash
sed -n '/ERROR/,/^$/p' log.txt              # print from an ERROR line to the next blank line
sed '/^#/d;/^$/d' config.conf                # strip comments and blank lines in one pass
sed -i 's/\r$//' file.txt                    # strip Windows CRLF line endings -> LF
sed -E 's/[[:space:]]+/ /g'                  # collapse repeated whitespace to a single space
sed -E 's/^[[:space:]]+|[[:space:]]+$//g'    # trim leading/trailing whitespace
sed -n '/pattern/p'                          # a clunkier grep "pattern" — good to recognize, rarely worth using
sed -n '/pattern/!p'                         # equivalent of grep -v "pattern"
```

---

## Gotchas / Side Cases

- **BRE by default** — `sed 's/(a)(b)/\2\1/'` does NOT capture groups; you need `\(a\)\(b\)` in BRE, or `-E`/`-r` to use bare parens like grep's `-E`.
- **Greedy matching only** — `.*` is greedy, and unlike PCRE (`grep -P`), sed has no lazy-quantifier mode at all, GNU or otherwise.
- **`s///g` doesn't handle overlapping matches** — once a match consumes characters, sed continues scanning *after* that match, never backtracking into it.
- **`\n` in the replacement** — GNU sed accepts `\n` literally in the replacement text since v4; POSIX/BSD sed generally does not, and needs an actual embedded newline via a backslash-continued line instead.
- **Line-oriented by design** — sed processes one line (pattern space) at a time by default. Multi-line matching needs `N` (pull in the next line), the `N;P;D` idiom, or `-z` mode — it's not a natural fit the way `grep -Pz` sort of is. The `N;P;D` idiom is a sliding two-line window: `N` appends the next line to the pattern space (so it now holds two lines), `P` prints just the first of the two, `D` deletes that first line and restarts the cycle on what's left — the net effect is a pattern space that always has "the current line plus a lookahead," which is how you match across line boundaries without `-z`:
  ```bash
  sed 'N;/foo\nbar/d;P;D'    # delete a "foo" line immediately followed by a "bar" line
  ```
- **No field awareness** — sed doesn't know about columns/fields; that's awk's job (see `awk.md`). Trying to "modify the 3rd field" in sed means writing a regex that captures around delimiters — awk does this natively.
- **Address ranges are sticky, not one-shot** — `/start/,/end/` can reopen multiple times per file if "start" matches again after a previous range closed.

---

## `tr` — Character Translation (Quick Reference)

`tr` works on individual **characters**, not lines or regex patterns — it translates, deletes, or squeezes characters from stdin. No filename argument exists at all: `tr` only ever takes SET1/SET2, so you must redirect input (`tr 'a' 'b' < file.txt`), never pass a filename directly.

```bash
tr 'a-z' 'A-Z'                       # lowercase -> uppercase
tr -d '[:digit:]'                    # delete all digits
tr -s ' '                            # squeeze repeated spaces into one
tr -c 'a-zA-Z\n' ' '                 # complement: replace everything NOT a letter with a space
tr -cd '[:print:]\n'                 # keep only printable chars + newlines, delete everything else
```

| Option | Meaning |
|---|---|
| `-d` | delete characters in SET1 |
| `-s` | squeeze consecutive repeats of SET1 chars into one |
| `-c` / `-C` | complement SET1 — operate on everything *not* in it |
| `-t` | truncate SET2 to SET1's length instead of extending it |

Character classes work like sed/grep's POSIX bracket classes: `[:alpha:]`, `[:digit:]`, `[:upper:]`, `[:lower:]`, `[:space:]`, `[:punct:]`, `[:print:]`, `[:cntrl:]`.

```bash
tr -d '\r' < winfile.txt > unixfile.txt    # strip CRLF -> LF (the tr equivalent of sed 's/\r$//')
tr -s '\n' < file                          # collapse repeated blank lines down to one
echo "a1b2c3" | tr -d '[:digit:]'          # -> abc
tr -cd '0-9\n' < file                      # keep only digits and newlines, strip everything else
```

**Gotchas:** `tr` has no regex — `a-z` is a literal character range, not a pattern, and its behavior can shift with locale (byte-order dependent); prefer `[:lower:]` when portability matters. If SET2 is shorter than SET1, GNU `tr` pads it by repeating SET2's last character rather than erroring — surprising unless you expect it.

---

## `sed` vs `grep` vs `awk` vs `tr` — when to reach for which

- **grep**: keep/remove whole lines based on a pattern — that's it.
- **sed**: line-oriented *transformation* — substitution, insertion, deletion, simple line-range edits.
- **awk**: field/column-oriented processing — when you need variables, arithmetic, arrays, or structured multi-column output. See `awk.md`.
- **tr**: character-level translation/deletion/squeezing — no regex, no lines/fields, just a character set mapped to another (or removed).
