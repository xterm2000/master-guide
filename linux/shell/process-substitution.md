# Process Substitution — `<(...)` vs `$(...)` vs a Pipe

## The short version

| Form | What it produces | What it expands to |
|---|---|---|
| `$(cmd)` | Captures `cmd`'s stdout as **text** | The literal output, substituted inline |
| `<(cmd)` | Runs `cmd`, exposes its stdout as a **file** | A filename (e.g. `/dev/fd/63`) |
| `cmd1 \| cmd2` | Connects `cmd1`'s stdout directly to `cmd2`'s stdin | Nothing — it's a pipe, not an expansion |

They look similar (`$(...)` vs `<(...)`) but answer different questions: "what did this command print" vs "give me something file-shaped that will produce this command's output when read."

---

## `$(...)` — Command Substitution

```bash
files=$(ls /tmp)          # captures the text, word-split unless quoted
echo "Today is $(date)"   # inline substitution into a string
```

The shell runs the command, waits for it to finish, and replaces `$(...)` with its stdout as a **string**. Unquoted, that string is then subject to word-splitting (on `$IFS`) and globbing — the same gotcha `for line in $(cat file)` runs into (see `bash-loops-cookbook.md`).

---

## `<(...)` — Process Substitution

```bash
diff <(sort file1.txt) <(sort file2.txt)
```

`<(cmd)` runs `cmd` in the background and replaces itself with a **path** the shell wires up to read `cmd`'s stdout — usually a named pipe or `/dev/fd/N`. `diff` never knows it isn't reading two ordinary files.

This solves a real problem: `diff`, `comm`, `paste`, and friends want **two file arguments**, but you often have two *command outputs*, not two files on disk. Without process substitution you'd need temp files:

```bash
# Without process substitution
sort file1.txt > /tmp/a
sort file2.txt > /tmp/b
diff /tmp/a /tmp/b
rm /tmp/a /tmp/b

# With process substitution — one line, no cleanup
diff <(sort file1.txt) <(sort file2.txt)
```

You can use more than one at a time — something a pipe can't do at all, since a pipe only has one upstream and one downstream:

```bash
paste <(cut -f1 a.tsv) <(cut -f2 b.tsv)   # combine columns from two different sources
```

---

## `< <(...)` — Feeding Process Substitution to `read`

```bash
count=0
while IFS= read -r line; do
    ((count++))
done < <(grep error /var/log/syslog)

echo "Found $count errors"   # this actually works
```

Note the two different `<`: the first is ordinary input redirection, the second is `<(...)` process substitution — `< <(cmd)` reads "redirect stdin from [this file-like thing]."

### Why not just pipe it?

```bash
count=0
grep error /var/log/syslog | while IFS= read -r line; do
    ((count++))
done
echo "Found $count errors"   # prints 0 — always
```

In bash, **every command in a pipeline runs in its own subshell** (except the last one, and only if `shopt -s lastpipe` is set and the pipeline isn't part of an interactive job-controlled shell). The `while` loop here is not the last command overall in a meaningful sense for variable purposes — it runs in a subshell, so `count` gets incremented inside a forked copy of the shell. When the loop ends, that subshell exits and takes its copy of `count` with it. Back in the parent shell, `count` is still `0`.

`< <(...)` avoids this entirely: there's no pipe, so no subshell — the `while` loop runs directly in your current shell, and `count` survives past `done`.

---

## `<(...)` vs `|` — When Each Wins

| | Pipe (`\|`) | Process substitution (`< <(...)`) |
|---|---|---|
| Number of sources | Exactly one upstream → one downstream | Any number, combine freely (`diff <(a) <(b)`) |
| Variables set inside survive | **No** (subshell) | **Yes** (no subshell) |
| Works with commands needing file *arguments*, not stdin (`diff`, `comm`) | No — needs `<(...)` or temp files anyway | Yes — this is its main use case |
| POSIX `/bin/sh` (dash) compatible | Yes | **No** — bash/zsh/ksh only |
| Readability for someone new to bash | High | Lower — `< <(...)` looks like a typo the first few times |
| Exit status handling | `${PIPESTATUS[@]}` gives you each stage's exit code | Exit status of the substituted command isn't directly visible to the parent shell |

**Rule of thumb:**
- Simple linear "A's output feeds B" → pipe. It's POSIX, obvious, and the standard idiom.
- Need to compare/combine two command outputs as if they were files → process substitution (`diff`, `comm`, `paste`).
- Looping and need the loop's variables to persist afterward (a counter, an accumulated array, anything set with `read`) → `< <(...)` instead of piping into the loop.
- Writing a script that must run under plain `/bin/sh` (some `#!/bin/sh` scripts, minimal containers, older systems) → avoid process substitution; it's a bash/ksh/zsh extension, not POSIX.

---

## Bonus: `>(...)` — Output Process Substitution

The write-side mirror, far less common:

```bash
command | tee >(gzip > log.gz) >(wc -l > count.txt) > /dev/null
```

`>(cmd)` expands to a filename that, when written to, feeds `cmd`'s stdin. Here `tee` fans one stream out to two separate commands' stdin simultaneously — one gzips it to disk, one counts lines — without temp files or a second manual pipe.

---

## See Also

- `bash-loops-cookbook.md` — the `while IFS= read -r line` idiom this pattern feeds into, and why it's preferred over `for line in $(...)`
- `heredocs.md` — another way this repo builds multi-line input without a temp file
