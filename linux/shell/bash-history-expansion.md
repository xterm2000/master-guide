# Bash History Expansion

History expansion (`!`) lets you re-run or reference pieces of previous
commands without retyping them. It's a shell feature, not a text-processing
tool, but it's a common gotcha *while* text-processing — a stray `!` inside a
double-quoted string (e.g. `echo "get admin!"`) triggers expansion at the
history layer before your text-processing command ever sees the string.

## Practical recipes

### Re-run the last command

```bash
sudo !!
```

`!!` expands to the entire previous command line. Classic use: you forgot
`sudo` and want to re-run exactly what you just typed, prefixed.

### Reuse the last argument

```bash
mkdir /tmp/new-dir
cd !$
```

`!$` expands to the last *argument* of the previous command (`/tmp/new-dir`
here), not the whole line. Saves retyping a long path you just used.

### Reuse all arguments

```bash
grep -n "TODO" file1.md file2.md file3.md
wc -l !:2-*
```

`!:2-*` expands to every word from the previous command starting at position
2 through the end — i.e. every argument, skipping the command name itself
(`!:0`). `!:1-$` and `!*` are equivalent ways to say "all arguments."

### Reference a specific word by position

```bash
cp source.txt dest.txt
chmod 644 !:1     # source.txt
chmod 644 !:2     # dest.txt
```

`!:N` pulls the Nth word (0-indexed, so `!:0` is the command itself, `!:1`
the first argument).

### Re-run a command by searching backward

```bash
!ssh          # re-runs the most recent command starting with "ssh"
!?prod?       # re-runs the most recent command containing "prod" anywhere
```

`!string` matches from the start of the command; `!?string?` matches anywhere
in the command line. Both are silent — they execute immediately, no
confirmation. Use `:p` (below) first if you're not sure which command it'll
pick.

### Preview before executing

```bash
!!:p
!ssh:p
```

Appending `:p` to any history-expansion form prints the expanded command
without running it, and adds it to your history so you can recall it with the
Up arrow. This is the safety check worth using any time you're not 100%
certain what `!string` or `!?string?` will match — history expansion has no
built-in confirmation prompt otherwise.

### Quick substitution on the last command

```bash
grep "old_pattern" access.log
^old_pattern^new_pattern^
```

`^old^new^` re-runs the immediately preceding command with the first
occurrence of `old` replaced by `new`. Equivalent to (and shorthand for)
`!!:s/old/new/`.

### Substitute across all words of the last command

```bash
grep "old_pattern" access.log
!!:gs/old_pattern/new_pattern/
```

The `g` flag makes the substitution apply to every matching word on the line,
not just the first — needed when the string to replace appears more than
once.

## Gotcha: `!` inside double quotes

```bash
echo "Access denied!"
bash: !": event not found
```

Bash expands `!` even inside double-quoted strings (only single quotes and a
preceding `\` suppress it). This bites most often when echoing or grepping
for literal `!` characters, or piecing together text that includes one.
Escape it (`\!`) or use single quotes for that portion of the string.

## Introspection: listing all shell variables and their values

```bash
compgen -v | while read -r v; do echo "$v=${!v}"; done
```

`compgen -v` lists the *names* of every variable currently visible in the
shell (no values). Piping each name through `${!v}` — indirect expansion —
resolves that name to its current value, giving a `name=value` dump
equivalent to `set` but restricted to variable names only (no functions,
no shell options). Handy for a quick "what's actually in scope right now"
check when debugging an env-dependent script.

## See Also

- `arrays.md` — indirect-expansion-adjacent array syntax (`${!arr[@]}` for
  keys, distinct from the `${!v}` indirection used above)
- `linux/text-processing/` — where the `!` gotcha above tends to actually bite
