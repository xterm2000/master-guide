# Regex Reference: BRE, ERE, PCRE & grep Gotchas

## 1. The Three Regex Flavors

### BRE (Basic Regular Expressions)
The original POSIX standard. Default for `grep`, `sed`, `ed`.

- Metacharacters like `+ ? | ( ) { }` are **literal** unless escaped with `\`
- Grouping/alternation require backslashes: `\(...\)`, `\|`, `\+`, `\?`

```bash
grep 'colou\?r' file.txt      # matches "color" or "colour"
grep 'a\(b\)*c' file.txt      # grouping requires backslashes
```

### ERE (Extended Regular Expressions)
Extension of BRE that "unescapes" the special characters. Used by `egrep`, `grep -E`, `awk`, `sed -E`.

- `+ ? | ( ) { }` are metacharacters **by default** — no backslash needed
- Adds alternation (`|`) and grouping (`(...)`) directly
- Still lacks lazy quantifiers, lookaround, backreferences (in strict POSIX ERE)

```bash
grep -E 'colou?r' file.txt
grep -E 'cat|dog' file.txt
```

### PCRE (Perl-Compatible Regular Expressions)
A far more powerful flavor modeled on Perl's regex engine. Used by PHP, `grep -P`, many editors/libraries.

Supports everything ERE does, plus lazy quantifiers, lookaround, named groups, backreferences, shorthand classes, non-capturing groups, Unicode properties, conditionals, and recursion (all detailed in section 3 below).

```bash
grep -P '\d{3}-\d{4}' file.txt      # PCRE shorthand
grep -P '(?<=foo)bar' file.txt      # lookbehind
```

### Comparison Table

| Feature | BRE | ERE | PCRE |
|---|---|---|---|
| `+ ? \| ( ) { }` as metachars | needs `\` | native | native |
| Alternation `\|` | limited/none | yes | yes |
| Lazy quantifiers `*?` | no | no | yes |
| Lookahead/behind | no | no | yes |
| `\d \w \s` shorthands | no | no | yes |
| Named groups | no | no | yes |
| Typical tools | `grep`, `sed` | `grep -E`, `awk` | `grep -P`, Perl, PHP, many libraries |

**Rough progression:** BRE → ERE → PCRE = increasing power/modern syntax.

---

## 2. grep Gotchas

### The `-ev` bug: combined short options

`-e` **requires an argument** (the pattern). Writing `-ev` gets parsed as:

```
-ev  →  -e "v"
```

Everything after the `e` becomes the argument to `-e` — the `-v` flag is silently never set. Any leftover word on the command line then becomes a **filename** to search, not a second pattern — which is why `grep -e 'grep=' -ev "git"` failed with:

```
grep: git: Is a directory
```

**Fix:** keep flags separate, or put `-v` first.

```bash
alias | grep -e 'grep=' -e "git" -v
# or
alias | grep -v -e 'grep=' -e "git"
```

### A pattern starting with `-` gets mistaken for a flag

grep's argument parser scans every argument for anything starting with `-` and treats it as an option — regardless of quoting, position, or which grep variant you use (`grep`, `egrep`, `fgrep` all share this behavior; they're the same parser).

```bash
grep -r '--cached' .        # fails: "unrecognized option '--cached'"
grep -r "--cached" .        # same failure — quoting doesn't change how grep parses argv
```

Moving the pattern around, adding more flags, or switching quote style never fixes this — the pattern itself needs an explicit marker saying "this is not a flag":

```bash
grep -r -e '--cached' .     # -e explicitly marks what follows as the pattern
grep -r -- '--cached' .     # -- marks everything after it as positional (no more flags)
```

Either works. This is the same family of gotcha as the `-ev` bug above — grep's flag-parsing is happy to consume text you intended as data.

### `-e` patterns are OR'd, not AND'd

```bash
grep -e 'foo' -e 'bar'   # matches lines with foo OR bar, never AND
```
There is no `-e`-based way to express AND.

### How to express AND logic (match both patterns)

| Approach | Command | Notes |
|---|---|---|
| Double grep | `alias \| grep 'grep=' \| grep -v 'git'` | Simplest, most readable — chaining filters is idiomatic Unix |
| PCRE lookahead | `alias \| grep -P '^(?!.*git).*grep='` | One-liner, harder to read |
| awk | `alias \| awk '/grep=/ && !/git/'` | Clean once comfortable with awk syntax |

### Rule of thumb

- **AND** (must match both) → chain greps or `awk '/a/ && /b/'`
- **OR** (match either) → `grep -e pat1 -e pat2` or `grep -E 'pat1|pat2'`
- **NOT** (exclude) → `grep -v`, chained after the positive match

---

## 3. PCRE Features in Detail

### 3.1 Non-greedy / lazy quantifiers: `*?`, `+?`

Default quantifiers (`*`, `+`, `{n,m}`) are **greedy** — match as much as possible. Adding `?` makes them **lazy** — match as little as possible.

```
Input: <a><b>
Greedy:  <.+>     → matches "<a><b>"  (whole thing)
Lazy:    <.+?>    → matches "<a>"      (stops at first >)
```

```bash
echo '<a><b>' | grep -oP '<.+?>'
# <a>
# <b>
```

Lazy versions exist for all quantifiers: `*?`, `+?`, `??`, `{n,m}?`.

### 3.2 Lookahead / lookbehind (zero-width assertions)

Match a *position* based on surrounding text, without including that text in the match.

| Syntax | Name | Meaning |
|---|---|---|
| `(?=...)` | Positive lookahead | followed by ... |
| `(?!...)` | Negative lookahead | NOT followed by ... |
| `(?<=...)` | Positive lookbehind | preceded by ... |
| `(?<!...)` | Negative lookbehind | NOT preceded by ... |

```bash
# Positive lookahead — "foo" only if followed by "bar"
echo "foobar foobaz" | grep -oP 'foo(?=bar)'
# foo

# Negative lookahead — "foo" only if NOT followed by "bar"
echo "foobar foobaz" | grep -oP 'foo(?!bar)'
# foo   (the one before "baz")

# Positive lookbehind — number preceded by $
echo "price: $50, weight: 50kg" | grep -oP '(?<=\$)\d+'
# 50

# Negative lookbehind — number NOT preceded by $
echo "price: $50, weight: 50kg" | grep -oP '(?<!\$)\b\d+\b'
# 50   (the weight one)
```

Full-line "AND / NOT" trick from section 2:
```
^(?!.*git).*grep=
```
"From line start, assert the rest does NOT contain `git`, then match anything followed by `grep=`."

### 3.3 Named capture groups: `(?<name>...)`

Label groups instead of referencing them by number (`\1`, `\2`).

```bash
echo "2026-07-20" | grep -oP '(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})'
```
In Python/PHP you'd access `match.group('year')` — more readable and order-independent than numbered groups.

### 3.4 Backreferences: `\1`, `\2`

Reference a previously captured group later in the *same* pattern — useful for finding duplicated content.

```bash
# Find repeated words
echo "the the quick fox" | grep -oP '\b(\w+)\s+\1\b'
# the the
```
`(\w+)` captures a word into group 1; `\1` demands the exact same text again.

Matching quote pairs (open/close must match):
```
(['"]).*?\1
```

### 3.5 Character class shorthands

| Shorthand | Meaning | Equivalent |
|---|---|---|
| `\d` | digit | `[0-9]` |
| `\D` | non-digit | `[^0-9]` |
| `\w` | word char | `[A-Za-z0-9_]` |
| `\W` | non-word char | `[^A-Za-z0-9_]` |
| `\s` | whitespace | `[ \t\n\r\f\v]` |
| `\S` | non-whitespace | `[^ \t\n\r\f\v]` |
| `\b` | word boundary | zero-width, edge of a word |

```bash
echo "call 555-1234" | grep -oP '\d{3}-\d{4}'
# 555-1234

# \b prevents partial-word matches
echo "cat catalog category" | grep -oP '\bcat\b'
# cat   (not "catalog"/"category")
```

### 3.6 Non-capturing groups: `(?:...)`

Groups for structure/precedence only — no numbered capture created. Keeps backreference numbering clean.

```bash
echo "foobar foobaz" | grep -oP '(?:foo)(bar|baz)'
```
`(?:foo)` groups "foo" without capturing it — only `(bar|baz)` becomes group 1. Useful in `sed`/`awk` replacements where extra capture groups would otherwise shift `\1`, `\2` numbering.

### 3.7 Advanced / rare: Unicode properties, conditionals, recursion

**Unicode properties** — match by Unicode category instead of ASCII ranges:
```
\p{L}    any letter in any language (é, ñ, 中, etc.)
\p{N}    any numeric character
```
```bash
echo "café 日本語 123" | grep -oP '\p{L}+'
# café
# 日本語
```

**Conditional patterns** — `(?(1)yes|no)`: match differently depending on whether group 1 matched. Rare; used for things like optional parens: `\(?\d+(?(1)\))` requires a closing `)` only if an opening `(` was captured.

**Recursion** — `(?R)` or `(?1)`: lets a pattern reference itself, enabling matches of nested/balanced structures like `(a(b(c)d)e)` — something plain regex fundamentally can't do (matching balanced brackets normally requires a stack, which regex lacks; PCRE's recursion works around this).

---

## 4. Mental Model / Takeaways

- **BRE/ERE**: match literal structure — "this character, this many times, in this order"
- **PCRE shorthands** (`\d`, `\w`, non-capturing groups): same power as ERE, just more convenient syntax
- **PCRE lookaround, backreferences, recursion**: genuinely *more powerful* — some let PCRE match things a strict finite-automaton (BRE/ERE) mathematically cannot, because PCRE moves beyond regular expressions into a small parsing engine.
