# Bash Loops Cookbook

> Assumes you already know `for`/`while`/`until` syntax. This is about which *idiom* to reach for and why — the daily-use patterns, not the grammar.

---

## `while IFS= read -r line; do ... done` — and why not `for line in $(...)`

This is the single most common "why do it like this" question in bash, so it gets the long answer.

```bash
while IFS= read -r line; do
    echo "Got: $line"
done < file.txt
```

vs. the tempting shortcut:

```bash
for line in $(cat file.txt); do
    echo "Got: $line"
done
```

The `for` version is broken in three separate ways, all at once:

1. **It splits on words, not lines.** `$(cat file.txt)` is command substitution — its output gets word-split on `$IFS` (default: space/tab/newline) before the `for` loop ever sees it. A line `hello world` becomes *two* loop iterations (`hello`, then `world`), not one. There is no way to get "one iteration per line" out of unquoted `$(...)`.
2. **It globs.** After word-splitting, each word is checked against filename patterns. A line containing `*.txt` gets expanded against files in your current directory before your loop body ever runs.
3. **It loads the whole file into memory first.** `$(cat file.txt)` fully materializes before the loop starts — fine for a 10-line config, bad for a multi-GB log.

`while IFS= read -r line` avoids all three because `read` is built specifically to consume **one line at a time** from a stream, with two extra flags doing the real work:

- **`read -r`** ("raw") — without it, `read` treats a trailing backslash (`\`) in the line as an escape/continuation character and eats it, silently mangling any line that happens to contain one (Windows paths, regex patterns, `\n` literals in data). `-r` disables that — what's in the file is what you get.
- **`IFS=` (prefixed, empty)** — `read` itself also uses `$IFS` to trim leading/trailing whitespace from what it reads by default. Setting `IFS=` for just this one command (see the scoping note below) means leading/trailing spaces and tabs in a line are preserved exactly instead of silently stripped. Skip this if you actually *want* whitespace trimmed (rare, but sometimes true for user-typed input).

**Bottom line:** `while IFS= read -r line; do ... done < file` is a streaming, line-exact, whitespace-preserving, non-globbing way to process a file — `for line in $(cat file)` is none of those things and only happens to work by accident on trivial input (no spaces, no glob chars, small file).

---

## `IFS` — what it actually is and how to scope it safely

`IFS` (Internal Field Separator) is the shell variable that controls **where word-splitting happens** — during unquoted variable/command-substitution expansion, in `for word in $var`, and as the field delimiter for `read`. Default value: space, tab, newline (`$' \t\n'`).

### The problem with changing it globally

```bash
IFS=','
read -ra parts <<< "a,b,c"
echo "${parts[1]}"     # b
# ... 50 lines later, completely unrelated code ...
for word in $some_sentence; do   # now silently splits on commas, not spaces!
    echo "$word"
done
```

`IFS` is a normal shell variable — setting it changes behavior for **everything** in the current shell from that point on, not just the line you meant it for. That's exactly the "needs to be reset after manipulations" problem you ran into: it's easy to set it for one job and forget it's still active three commands later, causing a bug that looks unrelated to the actual cause.

### The fix: scope it to a single command with a prefix assignment

```bash
IFS=',' read -ra parts <<< "a,b,c"    # IFS=',' applies ONLY to this one `read` invocation
echo "${parts[1]}"                     # b
echo "$IFS"                            # unchanged — still the default, no reset needed
```

`VAR=value command` (no semicolon, no `export`) sets `VAR` in the environment of *that single command only* — it never touches the shell's own `IFS` at all. This is strictly better than the "set it, do the thing, manually set it back" pattern for any case where the IFS change only needs to apply to one command (which is most cases, including every example in this file). Reach for a manual save/restore only when you need the custom `IFS` to persist across *multiple* commands in a row — and even then, prefer wrapping those commands in a function or subshell rather than mutating the outer shell's `IFS`.

### Common use cases for a non-default `IFS`

```bash
# Parsing CSV-style lines
IFS=',' read -ra fields <<< "web-1,10.0.1.5,running"
echo "${fields[0]} -> ${fields[1]}"

# Parsing a colon-separated list (PATH-style)
IFS=':' read -ra dirs <<< "$PATH"
printf '%s\n' "${dirs[@]}"

# Splitting "key=value" config lines
while IFS='=' read -r key value; do
    echo "$key is $value"
done < config.env

# Joining an array back into a string with a custom separator (the reverse direction)
arr=(a b c)
( IFS=,; echo "${arr[*]}" )    # a,b,c — note: IFS only affects `${arr[*]}`, and is scoped to the subshell (...) here
```

---

## Cookbook

### Read a file line-by-line (the default-safe pattern)

```bash
while IFS= read -r line; do
    echo "$line"
done < file.txt
```

### Read null-delimited output — safe for filenames with spaces/newlines

```bash
find . -type f -print0 | while IFS= read -r -d '' file; do
    echo "$file"
done
```
`-print0`/`read -d ''` use a NUL byte as the separator instead of newline — the only byte that can't legally appear in a filename. Necessary if you ever expect filenames containing spaces or literal newlines; `find | while read -r file` (newline-delimited) silently breaks on both.

### Read from a command's output without losing loop variables

```bash
count=0
while IFS= read -r line; do
    ((count++))
done < <(grep -c '' /var/log/syslog)
echo "$count"
```
See `process-substitution.md` for why `< <(cmd)` is used here instead of `cmd | while read ...` — piping into the loop runs it in a subshell, silently discarding `count` once the loop ends.

### Loop body needs its own stdin (e.g. `ssh`) — don't let it eat the file

```bash
while IFS= read -r host; do
    ssh "$host" uptime </dev/null
done < hosts.txt
```
Without `</dev/null` on the `ssh` call, `ssh` inherits the loop's stdin (the same file descriptor `read` is consuming) and can silently swallow the rest of `hosts.txt`, ending the loop early after the first host. Redirecting the inner command's stdin from `/dev/null` keeps the outer `read` and the inner command from fighting over the same descriptor. (See `linux/ssh/` for real remote-loop scripts.)

### C-style counting loop

```bash
for ((i = 0; i < 10; i++)); do
    echo "$i"
done
```
Use this over `for i in {0..9}` when the bound is a variable — brace expansion (`{0..$n}`) does **not** expand variables, only literal ranges.

### `until` — retry/poll until something succeeds

```bash
until curl -sf http://api.mydomain.com/health > /dev/null; do
    echo "waiting for API..."
    sleep 2
done
echo "API is up"
```
The daily-use pattern for "block until a service/node/pod is ready" — inverse of `while`: keep looping *while the condition is false* (i.e., until the command succeeds, exit code 0).

### Infinite loop for polling/watch-style scripts

```bash
while true; do
    kubectl get pods -n monitor
    sleep 5
done
```
Ctrl-C to stop. Prefer this over a `watch kubectl get pods` one-liner only when you need extra logic per iteration (conditionals, logging, alerting) that `watch` can't do.

### Loop over an array safely

```bash
for node in "${NODES[@]}"; do
    echo "$node"
done
```
Always quote `"${arr[@]}"` — unquoted `${arr[@]}` re-triggers word-splitting/globbing on each element, the same class of bug as `for line in $(cat file)` above.

### Break/continue out of nested loops

```bash
for outer in a b c; do
    for inner in 1 2 3; do
        [[ "$inner" == 2 ]] && continue 2   # skip rest of inner AND outer's current iteration
        echo "$outer-$inner"
    done
done
```
`break N`/`continue N` act on the Nth enclosing loop, counting from the innermost as `1`. Easy to forget the number exists at all since single-loop `break`/`continue` never need it.

### Read all lines into an array at once (when you don't need streaming)

```bash
mapfile -t lines < file.txt
echo "${#lines[@]} lines"
echo "${lines[0]}"
```
`mapfile`/`readarray` (same command, two names) load an entire file into an array, one element per line, in one step — reach for this instead of `while read` when you need random access to lines (by index) rather than sequential processing, and the file is small enough to hold in memory comfortably.

### Run iterations in parallel

```bash
for url in "${urls[@]}"; do
    curl -s "$url" -o "$(basename "$url")" &
done
wait
```
`&` backgrounds each iteration; `wait` (no args) blocks until all backgrounded jobs finish. Fine for a handful of items — for large lists, `xargs -P N` or GNU `parallel` give you a concurrency cap this pattern doesn't.

---

## See Also

- `process-substitution.md` — `< <(...)` vs `$(...)` vs a pipe, and why it fixes the subshell-variable-loss problem in the "read from a command" recipe above
- `arrays.md` — array declaration/indexing basics referenced throughout this cookbook
- `heredocs.md` — related "feed a block of text to a command" patterns that aren't loops
