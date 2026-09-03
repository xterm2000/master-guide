# Small Text Utilities

The single-purpose line / field / column / byte tools that show up mid-pipeline
and rarely get explained on their own. Start with the dispatch table — find your
situation, jump to the tool.

Verified on Rocky Linux 10.2: GNU coreutils 9.5, util-linux 2.40.2,
findutils 4.10.0, diffutils 3.10, gettext 0.22.5, glibc iconv 2.39,
dos2unix 7.5.2, binutils `strings` 2.41, `xxd` (vim) 2024-01-25.

The big three — `grep`, `sed`, `awk` — and the structured-data tools have their
own docs: [`grep.md`](grep.md) · [`sed.md`](sed.md) · [`awk.md`](awk.md) ·
[`jq-detailed.md`](jq-detailed.md) · [`yq-jq-bat.md`](yq-jq-bat.md). Worked
multi-tool pipelines: [`text-process-cookbook.md`](text-process-cookbook.md).

---

## If you need to…

### Fields & columns

| Situation | Reach for | § |
|---|---|---|
| Pull out fields by a single-char delimiter, or fixed character ranges | `cut` | [cut](#cut) |
| Same, but delimiter is whitespace / regex / you need to reorder fields | `awk` | [`awk.md`](awk.md) |
| Grab the **last** (or Nth-from-end) field without counting them | `rev` + `cut` + `rev`, or `awk '{print $NF}'` | [rev](#rev) |
| Line ragged output up into an aligned table | `column -t` | [column](#column) |
| Print a list in N newspaper-style columns, or files side by side | `pr` | [pr](#pr) |
| Number the lines (with control over format / which lines count) | `nl` (else `cat -n`) | [nl](#nl) |

### Combining & comparing files

| Situation | Reach for | § |
|---|---|---|
| Glue two files together as side-by-side columns | `paste` | [paste](#paste) |
| SQL-style join of two **sorted** files on a shared key | `join` | [join](#join) |
| Set operations (common / only-in-A / only-in-B) on two **sorted** lists | `comm` | [comm](#comm) |
| See what changed between two files | `diff -u` | [diff / sdiff / patch](#diff--sdiff--patch) |
| Merge two files hunk-by-hunk, choosing interactively | `sdiff -o` | [diff / sdiff / patch](#diff--sdiff--patch) |
| Apply a diff someone sent you | `patch` | [diff / sdiff / patch](#diff--sdiff--patch) |
| Compare two directory trees | `diff -rq` | [diff / sdiff / patch](#diff--sdiff--patch) |
| Compare the output of two commands | `diff <(a) <(b)` | [diff / sdiff / patch](#diff--sdiff--patch) |

### Reordering, dedup, sampling

| Situation | Reach for | § |
|---|---|---|
| Sort by a column / numerically / by version string / by 2K–5M–1G size | `sort -k` / `-n` / `-V` / `-h` | [sort](#sort) |
| Count how many times each line occurs | `sort \| uniq -c` | [uniq](#uniq) |
| Drop duplicate lines | `sort -u`, or `awk '!seen[$0]++'` (keeps order) | [uniq](#uniq) |
| Keep **only** the duplicated lines, or **only** the unique ones | `uniq -d` / `uniq -u` | [uniq](#uniq) |
| Reverse the order of lines | `tac` | [tac](#tac) |
| Shuffle lines, or pull a random sample | `shuf` | [shuf](#shuf) |
| Order items so dependencies come first ("X needs Y") | `tsort` | [tsort](#tsort) |
| Fast prefix lookup in a huge **sorted** wordlist/file | `look` | [look](#look) |

### Whitespace, case, wrapping

| Situation | Reach for | § |
|---|---|---|
| Translate / delete / squeeze characters; upper ↔ lower case | `tr` | [tr](#tr) |
| Hard-wrap long lines at a column width | `fold -s` | [fold / fmt](#fold--fmt) |
| Reflow prose paragraphs to a width | `fmt` | [fold / fmt](#fold--fmt) |
| Convert tabs to spaces, or spaces back to tabs | `expand` / `unexpand` | [expand / unexpand](#expand--unexpand) |
| Strip backspace-overstrike or control junk (e.g. `man` output) | `col -b` | [col](#col) |

### Generating & counting

| Situation | Reach for | § |
|---|---|---|
| A numeric sequence — loop counter, test data, zero-padded names | `seq` | [seq](#seq) |
| N random numbers, or a shuffled set of literals | `shuf -i` / `shuf -e` | [shuf](#shuf) |
| Humanize bytes (`1.5M`) or parse them back; thousands separators | `numfmt` | [numfmt](#numfmt) |

### Bytes, encoding, charsets

| Situation | Reach for | § |
|---|---|---|
| See the actual bytes / spot a stray non-printing character | `xxd`, `od -c`, `hexdump -C` | [xxd / od / hexdump](#xxd--od--hexdump) |
| Encode or decode base64 | `base64` / `base64 -d` | [base64](#base64) |
| Convert character encoding (Latin-1 ↔ UTF-8), or strip accents to ASCII | `iconv` | [iconv](#iconv) |
| Fix Windows CRLF ↔ Unix LF line endings | `dos2unix` / `unix2dos` | [dos2unix](#dos2unix) |
| Extract readable text from a binary or a blob | `strings` | [strings](#strings) |
| Fill `$VAR` placeholders in a template from the environment | `envsubst` | [envsubst](#envsubst) |

### Splitting one file into many

| Situation | Reach for | § |
|---|---|---|
| Split by size or line count | `split` | [split / csplit](#split--csplit) |
| Split at a pattern, or at given line numbers | `csplit` | [split / csplit](#split--csplit) |

### Turning text into commands

| Situation | Reach for | § |
|---|---|---|
| Run a command once per input line / item | `xargs -I{}` | [xargs](#xargs) |
| Run them in parallel | `xargs -P` | [xargs](#xargs) |
| Handle filenames with spaces/newlines safely | `find -print0 \| xargs -0` | [xargs](#xargs) |

---

# Fields & columns

## cut

Extract columns by **character position** (`-c`) or **single-char delimited
field** (`-d`/`-f`). Fast and terse.

```bash
cut -d: -f1,7 /etc/passwd            # fields 1 and 7
#   root:/bin/bash

cut -d: -f3- /etc/passwd             # field 3 to end
cut --complement -d: -f2 /etc/passwd # every field EXCEPT 2
cut -d: -f1,7 --output-delimiter=' => ' /etc/passwd
#   root => /bin/bash

echo "abcdefgh" | cut -c1-4          # characters, not fields  ->  abcd
```

**Limits:** delimiter is exactly one byte (no "any whitespace", no regex), output
order is always ascending (`-f3,1` still prints 1 then 3), no notion of quoted
CSV. Hit any of those → `awk`.

## rev

Reverses each line character-wise. Small alone; useful sandwiched.

```bash
echo "hello world" | rev            # dlrow olleh

# grab the LAST dot-field without knowing the count
echo "backup.2026-09-03.tar.gz" | rev | cut -d. -f1 | rev      # gz
echo "a.b.c.d"                   | rev | cut -d. -f2- | rev     # a.b.c
```

## paste

Merges lines **across** inputs instead of down one.

```bash
paste names.txt cities.txt          # two files -> two TAB-separated columns
printf 'a\nb\nc\n' | paste -d, -s   # -s serialize: many lines -> one:  a,b,c
paste -d'\n' odd.txt even.txt       # interleave two files line by line
paste -sd+ nums.txt | bc            # quick sum  (bc isn't on this host — see Recipes for the awk form)
```

## column

Aligns whitespace- or delimiter-separated input into a grid (`util-linux`;
options are richer on recent versions).

```bash
printf 'NAME AGE\nalice 30\nbob 7\n' | column -t
#   NAME   AGE
#   alice  30
#   bob    7

column -t -s: /etc/passwd            # tabulate a colon-delimited file
column -t -o ' | ' data.tsv          # custom output separator
printf 'a b\n1 2\n' | column -t -N COL1,COL2      # supply header names
column -t -J -N user,uid -s: /etc/passwd          # emit JSON instead of a grid
```

Cosmetic only — never parse `column` output; feed it the raw data.

## pr

Paginate / lay text out in columns. With `-t` (omit header/footer) it's a handy
multi-column formatter.

```bash
seq 1 6 | pr -t -3            # down 3 newspaper columns:  1  3  5 / 2  4  6 ...
pr -t -m file1 file2 file3    # -m: files as parallel columns, side by side
pr -t -w 100 -2 longlist.txt  # 2 columns, 100 cols wide
```

## nl

Numbers lines like `cat -n`, but you choose the format and which lines count.

```bash
printf 'x\n\ny\n' | nl                 # -bt default: blank lines NOT numbered
printf 'x\n\ny\n' | nl -ba -s': ' -w2   # -ba all lines, ': ' sep, width 2
#    1: x
#    2:
#    3: y
```

`-nrz` = right-justified zero-padded numbers.

---

# Combining & comparing files

## comm

Reads two **sorted** files, prints three columns: *only in 1*, *only in 2*,
*in both*. Suppress a column by its number.

```bash
comm -12 a.txt b.txt      # lines common to both
comm -23 a.txt b.txt      # only in a.txt
comm -13 a.txt b.txt      # only in b.txt

# which installed packages are not in my baseline
comm -23 <(rpm -qa | sort) <(sort baseline.txt)
```

Inputs must be sorted the same way — add `--check-order` to be told when they
aren't.

## join

The relational join: matches lines of two **sorted** files sharing a key field
and stitches them.

```bash
join -t: -1 1 -2 1 users.txt shells.txt          # join on field 1, ':'-delimited

join -a2 -e NULL -o auto left.txt right.txt       # left outer: keep unmatched
#   1 alice london
#   2 bob berlin
#   3 NULL paris        <- unmatched row from the right, padded with -e
```

`-a1`/`-a2` re-add unpairable lines from that file; `-e` sets the fill;
`-o auto` keeps a stable column layout. Sort both on the join field
(`sort -t: -k1,1`).

## diff / sdiff / patch

```bash
diff -u old new                  # unified diff (the format everyone reads / patch eats)
diff -y -W $COLUMNS old new       # side-by-side; ' | ' marks changed, '<' '>' added/removed
diff -rq dir1 dir2               # recursive, quiet: just names what differs
diff <(sort a) <(sort b)         # compare command output via process substitution
diff --color=always old new | less -R

sdiff old new                    # interleaved side-by-side
sdiff -o merged old new          # INTERACTIVE merge: l/r/e/q per hunk -> writes merged

diff -u old new > change.patch   # make a patch
patch < change.patch             # apply it (reads the filename from the header)
patch -p1 < change.patch         # strip one leading path component (git-style patches)
patch -R < change.patch          # reverse / undo a previously applied patch
```

For anything version-control-shaped use `git diff` (see [`../../git/`](../../git/));
`diff`/`patch` are for loose files and quick pipes.

---

# Reordering, dedup, sampling

## sort

```bash
sort -t: -k3 -n /etc/passwd       # by the 3rd ':'-field, numerically (uid)
sort -k2,2 -k1,1n file            # primary key: field 2; tie-break: field 1 numeric
sort -V versions.txt              # 1.2.0 < 1.9.0 < 1.10.0  (version-aware)
sort -h sizes.txt                 # 2K < 5M < 1G  (human numeric)
sort -u file                      # sort + drop duplicates in one pass
sort -R file                      # random order  (-R, not -r which is reverse!)
sort -s -k2,2 file               # stable: keep input order among equal keys
sort -c file                      # exit non-zero (and report) if not already sorted
sort -z                           # NUL-terminated records — pairs with find -print0
sort --debug -k2 file            # highlight exactly which bytes formed the key
```

Locale bites: `LC_ALL=C sort` is faster and gives byte order (often what you want
for code/paths). `-k2` means "field 2 **to end of line**" — use `-k2,2` to mean
just field 2.

## uniq

**Only collapses *adjacent* equal lines** — almost always preceded by `sort`.

```bash
sort f | uniq -c            # prefix each line with its count
sort f | uniq -c | sort -rn # ... and rank most-frequent first
sort f | uniq -d            # show only lines that were duplicated
sort f | uniq -u            # show only lines that appeared exactly once
uniq -f1 file               # ignore the first field when comparing
uniq -w8 file               # compare only the first 8 characters
uniq -i file                # case-insensitive
```

To dedup **without sorting** (preserve first-seen order): `awk '!seen[$0]++'` —
see [`text-process-cookbook.md`](text-process-cookbook.md).

## tac

`cat` backwards — reverses line order; `-s` reverses records split on a separator.

```bash
printf '1\n2\n3\n' | tac                    # 3 / 2 / 1
tac /var/log/messages | grep -m1 'started'  # most-recent match, stops early
echo "$PATH" | tr ':' '\n' | tac            # PATH entries, last-first
```

## shuf

Random permutation — the opposite of `sort`.

```bash
shuf -e red green blue        # shuffle these literal args
shuf -i 1-100 -n 5           # 5 distinct random ints from 1..100
shuf -n 20 access.log        # random 20-line sample of a file
shuf -e -n1 "${hosts[@]}"    # pick one at random
```

## tsort

Topological sort: given "X Y" pairs meaning *X must come before Y*, print a linear
order that respects all of them. Reports a cycle on stderr if one exists.

```bash
printf 'unpack build\nbuild test\nfetch unpack\n' | tsort
#   fetch
#   unpack
#   build
#   test

# order library builds by their dependency edges
tsort deps.txt | tac        # tac if your edges are "needs" rather than "before"
```

## look

Binary-searches a **sorted** file for lines with a given prefix — near-instant on
huge files where `grep '^foo'` would scan everything.

```bash
look pre /usr/share/dict/words     # every word starting "pre"
look -f Error big-sorted.log       # -f: case-insensitive
```

---

# Whitespace, case, wrapping

## tr

Translate, delete, or squeeze **characters** (not strings — for strings use
`sed`). Reads stdin only.

```bash
tr 'A-Z' 'a-z'  < f          # uppercase -> lowercase
tr -d '\r'      < f          # delete all CR (strip CRLF -> LF)
tr -s ' '                    # squeeze runs of spaces to one
tr -cd 'A-Za-z0-9_\n'        # -c complement + -d: keep only these, drop the rest
tr ' ' '\n'                  # spaces -> newlines (crude tokeniser)
tr -dc '[:print:]\n' < f     # strip non-printable bytes
echo $RANDOM | tr 0-9 a-j    # map digits to letters
```

`[:alpha:]`, `[:digit:]`, `[:space:]`, `[:punct:]`, `[:print:]` classes work
inside the sets.

## fold / fmt

Both wrap long lines; they differ in how much they understand the text.

```bash
echo "the quick brown fox jumped over" | fold -w 20 -s
#   the quick brown fox        <- -w hard width, -s break at spaces not mid-word
#   jumped over

echo "the quick brown fox jumped over the lazy dog again" | fmt -w 30
#   the quick brown fox jumped  <- fmt reflows whole PARAGRAPHS to the width
#   over the lazy dog again
```

`fold` = dumb character ruler (good for wrapping data / base64). `fmt` =
paragraph-aware (good for prose, comment blocks, commit messages).

## expand / unexpand

Tabs ↔ spaces.

```bash
expand -t4 Makefile | cat -A | head -1     # tabs -> 4 spaces  ($ marks EOL)
unexpand -a -t4 file.txt                   # -a: convert runs of spaces anywhere,
                                           #     not just leading indentation
```

Run one of these on both sides before a `diff` when the files disagree on
tabs vs spaces.

## col

`col -b` resolves backspace-overstrike (`char BS char`) — the classic use is
flattening `man` / `groff` output so you can grep or save it:

```bash
man ss | col -b > ss.txt          # plain text, no bold/underline control codes
tool --help 2>&1 | col -b          # strip stray control junk from help output
```

---

# Generating & counting

## seq

```bash
seq 1 5                  # 1..5, one per line
seq -s, 1 5              # 1,2,3,4,5
seq -w 8 10             # 08 09 10   (zero-pad to equal width)
seq 0 2 10              # step 2:  0 2 4 6 8 10
seq -f 'host%02g' 1 3   # host01 host02 host03
for i in $(seq -w 1 12); do mkdir "month-$i"; done
```

## numfmt

Convert between raw numbers and human units — the missing piece when `du -b` or a
JSON field hands you bytes.

```bash
echo 1536000 | numfmt --to=iec       # 1.5M   (powers of 1024)
echo 1.5M    | numfmt --from=iec     # 1572864
echo 1234567 | numfmt --grouping     # 1,234,567
echo 1500000 | numfmt --to=si        # 1.5M   (powers of 1000)

df -B1 --output=size,target / | tail -1 | numfmt --to=iec --field=1
```

---

# Bytes, encoding, charsets

## xxd / od / hexdump

Look at the actual bytes — spot a BOM, a stray `\r`, a NUL, an encoding problem.

```bash
printf 'A\tB\n' | xxd
#   00000000: 4109 420a                                A.B.
printf 'A\tB\n' | od -c            # 'C' notation:  A  \t  B  \n
printf 'ABCD'   | hexdump -C        # hex + ASCII gutter

xxd -p file          # plain hex, no offsets/gutter  (415243...)
xxd -p file | xxd -r -p > copy     # hex -> bytes: reconstruct the file
xxd file | head      # first lines of a binary, readable
```

`xxd` (ships with vim) is the friendliest; `od`/`hexdump` are always present on
minimal systems.

## base64

```bash
base64 < file            # encode  (wraps at 76 cols by default)
base64 -w0 < file        # encode, single line  (for env vars, k8s secrets)
base64 -d < file.b64     # decode
echo -n 'user:pass' | base64      # dSdXNlcjpwYXNz  (HTTP Basic header value)
```

## iconv

Character-set conversion. List targets with `iconv -l`.

```bash
iconv -f latin1 -t utf-8 legacy.txt > utf8.txt      # re-encode a Latin-1 file
iconv -f utf-8 -t ascii//TRANSLIT <<< 'café'        # -> cafe  (strip accents)
iconv -f utf-8 -t ascii//IGNORE  file               # drop anything non-ASCII
file -i suspect.txt                                 # guess the current encoding first
```

## dos2unix

Line-ending conversion (edits **in place** by default).

```bash
dos2unix script.sh            # CRLF -> LF
unix2dos README.txt           # LF -> CRLF
dos2unix -n in.txt out.txt     # write to a new file instead of in place
find . -name '*.sh' -print0 | xargs -0 dos2unix
```

`tr -d '\r'` or `sed -i 's/\r$//'` do the same with no extra package — see
[`text-process-cookbook.md`](text-process-cookbook.md).

## strings

Pull runs of printable characters out of a binary or blob.

```bash
strings -n 8 core.dump           # only sequences >= 8 chars
strings mystery.bin | grep -i version
strings -t x firmware.img        # -t x: prefix each hit with its hex offset
```

## envsubst

Substitute `$VAR` / `${VAR}` from the environment into a template. From
`gettext`. Only touches shell-style variable syntax — safe on config files full
of other `$`-looking things if you restrict it.

```bash
export DB_HOST=db.internal DB_PORT=5432
envsubst < app.conf.tmpl > app.conf

envsubst '$DB_HOST $DB_PORT' < app.conf.tmpl     # ONLY expand these two, leave the rest
```

---

# Splitting one file into many

## split / csplit

`split` divides by **size or count**; `csplit` divides at **content**.

```bash
split -l 1000 big.log part-        # 1000 lines each: part-aa, part-ab, ...
split -b 10M  big.bin part- -d     # 10 MB each, numeric suffixes
split -n l/4  big.log chunk-       # exactly 4 files, without splitting a line
seq 1 100 | split -l 25 --filter='wc -l'     # pipe each chunk to a command

csplit -z -f doc- manifests.yaml '/^---$/' '{*}'   # break at every '---' marker
#   -z   drop an empty leading piece
#   {*}  repeat the pattern for as many matches as there are
csplit -f part- report.txt 100 200          # split at line 100 and line 200
```

The "chunk a multi-GB file for parallel work" recipe is in
[`text-process-cookbook.md`](text-process-cookbook.md) Part E.

---

# Turning text into commands

## xargs

Builds and runs command lines from stdin. The bridge from a text pipeline to
actually *doing* something per item.

```bash
printf 'a\nb\nc\n' | xargs -I{} cp {} /backup/{}.bak   # one command per line
echo 1 2 3 4 | xargs -n2 echo                          # 2 args per invocation
find . -name '*.log' -print0 | xargs -0 rm             # spaces/newlines-safe
find . -name '*.jpg' -print0 | xargs -0 -P4 -n1 convert -resize 50% # 4 in parallel
some-pipeline | xargs -r systemctl restart             # -r: don't run at all if empty
git branch --merged | grep -v main | xargs -r git branch -d
```

Gotchas: default splitting is on whitespace **and** quotes — for real data use
`-0` with a `-print0` / `-z` producer, or `-d '\n'`. `-I{}` implies one line per
run (`-L1`), so it can't be combined with `-n`. `-P0` = as many parallel as the
system allows.

More shell-loop patterns (when `xargs` isn't the right shape):
[`../shell/bash-loops-cookbook.md`](../shell/bash-loops-cookbook.md).

---

# Recipes

Multi-tool one-liners built from the sections above. Every one was run on this
box. For grep/sed/awk-heavy log and config pipelines see
[`text-process-cookbook.md`](text-process-cookbook.md).

### Word-frequency count (the classic pipeline)

```bash
tr -cs 'A-Za-z' '\n' < text | tr 'A-Z' 'a-z' | sort | uniq -c | sort -rn | head
#         3 the
#         2 cat
#         1 sat
```

`tr -cs` turns every non-letter run into one newline; lowercase; count; rank.
**Tools:** [tr](#tr) · [sort](#sort) · [uniq](#uniq)

### Frequency table of a log field

```bash
cut -d' ' -f1 access.log | sort | uniq -c | sort -rn | head        # top request methods / IPs
```

**Tools:** [cut](#cut) · [sort](#sort) · [uniq](#uniq)

### What changed between two lists (order doesn't matter)

```bash
diff <(sort old.txt) <(sort new.txt)          # readable +/- view
comm -13 <(sort old.txt) <(sort new.txt)      # only the ADDED lines
comm -23 <(sort old.txt) <(sort new.txt)      # only the REMOVED lines
```

**Tools:** [diff](#diff--sdiff--patch) · [comm](#comm) · [sort](#sort)

### Which installed packages drifted from a baseline

```bash
comm -13 <(sort baseline.txt) <(rpm -qa | sort)     # added since baseline
```

**Tools:** [comm](#comm) · [sort](#sort)

### Attach a lookup table to a data file

```bash
# people.csv: id,name   loc.csv: id,city   -> id,name,city
join -t, -1 1 -2 1 <(sort -t, people.csv) <(sort -t, loc.csv)
#   1,alice,London
#   2,bob,Berlin
```

**Tools:** [join](#join) · [sort](#sort)

### Sum or average a column of numbers

```bash
awk '{s+=$1} END{print s}'  nums.txt          # sum   (bc: paste -sd+ nums.txt | bc)
awk '{s+=$1} END{print s/NR}' nums.txt        # mean
```

**Tools:** [paste](#paste) · [`awk.md`](awk.md)

### Disk usage: human-readable and sorted

```bash
du -b --max-depth=1 . | sort -rn | numfmt --to=iec --field=1 | column -t
#   1.0M  ./b
#   4.0K  ./a
```

**Tools:** [numfmt](#numfmt) · [sort](#sort) · [column](#column)

### Reverse a colon-delimited list (e.g. `$PATH`)

```bash
echo "$PATH" | tr ':' '\n' | tac | paste -sd:
#   /usr/local/bin:/bin:/usr/bin
```

**Tools:** [tr](#tr) · [tac](#tac) · [paste](#paste)

### Run a command per line — parallel, filename-safe

```bash
find . -name '*.png' -print0 | xargs -0 -P4 -n1 optipng
git branch --merged main | grep -v ' main$' | xargs -r git branch -d
```

**Tools:** [xargs](#xargs)

### Make N numbered things

```bash
seq -w 1 20 | xargs -I{} mkdir "env-{}"
```

**Tools:** [seq](#seq) · [xargs](#xargs)

### Split a multi-document YAML / concatenated PEM into files

```bash
csplit -z -s --suppress-matched -f doc- -b '%02d.yaml' all.yaml '/^---$/' '{*}'
#   --suppress-matched drops the '---' separator lines themselves
```

**Tools:** [csplit](#split--csplit)

### Chunk a huge file across parallel workers

```bash
split -n l/8 --filter='./process-batch' big.ndjson     # 8 line-preserving streams
```

**Tools:** [split](#split--csplit) · [xargs](#xargs)

### Base64 a cert into a one-line secret value

```bash
base64 -w0 tls.crt        # no line wrapping — paste straight into a k8s Secret
```

**Tools:** [base64](#base64)

### Fill a config template from the environment

```bash
export DB_HOST=db.internal DB_PORT=5432
envsubst < app.conf.tmpl > app.conf
envsubst '$DB_HOST $DB_PORT' < app.conf.tmpl > app.conf   # only these two vars
```

**Tools:** [envsubst](#envsubst)

### Find and fix a file with the wrong encoding / line endings

```bash
file -i *.txt | grep -v 'utf-8\|us-ascii'         # spot the odd one out
file badly.txt                                     # "... with CRLF line terminators"
iconv -f latin1 -t utf-8 legacy.txt | sponge legacy.txt   # or: > tmp && mv tmp legacy.txt
dos2unix badly.txt
```

**Tools:** [iconv](#iconv) · [dos2unix](#dos2unix) · [xxd / od / hexdump](#xxd--od--hexdump)

### Two-up checklist from a flat list

```bash
pr -t -2 -w 60 checklist.txt          # or:  paste - - < checklist.txt
```

**Tools:** [pr](#pr) · [paste](#paste)

### Order build steps by their dependency edges

```bash
printf 'fetch unpack\nunpack build\nbuild test\n' | tsort
#   fetch / unpack / build / test
```

`tsort` reads "A B" as *A before B* and prints a linear order; it reports a cycle
on stderr if the edges contradict.
**Tools:** [tsort](#tsort)

---

# Not installed here, but worth knowing

| Tool | Package | Why you'd want it |
|---|---|---|
| `datamash` | `datamash` | `groupby` / `sum` / `mean` / `median` / percentiles straight from the CLI — replaces a lot of hand-rolled `awk` aggregation |
| `mlr` (Miller) | `miller` | `awk`/`sed`/`cut` that actually understands CSV, TSV, and JSON — including quoted fields with embedded commas |
| `pv` | `pv` | pipe throughput / progress bar / ETA (`pv big.iso | ...`) |
| `sponge` | `moreutils` | soak up all stdin, *then* write the file — makes `grep x file | sponge file` safe |
| `ts` | `moreutils` | prefix every line with a timestamp (`./slow.sh | ts '%H:%M:%S'`) |
| `pee`, `vipe`, `combine` | `moreutils` | tee-to-commands, edit a pipe mid-stream, set ops on lines |

Without `sponge`: `grep x file > tmp && mv tmp file`, or `sed -i`.

---

## See Also

- [`text-process-cookbook.md`](text-process-cookbook.md) — grep/sed/awk-heavy log & config pipelines (this doc's Recipes cover the small-tool combinations)
- [`awk.md`](awk.md) — the escape hatch when `cut` / `paste` / `join` hit their limits
- [`sed.md`](sed.md) — string (not character) substitution, in-place edits
- [`grep.md`](grep.md), [`grep-regex-ref.md`](grep-regex-ref.md) — searching and regex
- [`../shell/bash-loops-cookbook.md`](../shell/bash-loops-cookbook.md) — `seq` / `shuf` / `xargs` feeding shell loops
- [`../../git/`](../../git/) — use `git diff` / `git apply` for anything version-controlled
