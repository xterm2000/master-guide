# Bash History: Controlling What Gets Saved

History *expansion* (`!!`, `!$`) is about recalling past commands — see
[`bash-history-expansion.md`](bash-history-expansion.md). This file is the
other half: the shell variables and `history` subcommands that decide **which
commands get recorded in the first place**, and how to prune the ones that
slipped through.

Bash keeps two histories: an in-memory list for the current session, and the
on-disk `~/.bash_history`, written when the shell exits (or on demand with
`history -w`). The variables below are read as each command is entered, so
put them in `~/.bashrc` to make them stick.

Commands and syntax verified against **GNU bash 5.2.26** on shiva.

## `HISTCONTROL` — filter duplicates and space-prefixed commands

```bash
export HISTCONTROL=ignoreboth
```

Colon-separated list of:

- `ignorespace` — a command starting with a space is not saved. Prefix any
  throwaway or sensitive one-off with a space to keep it out of history.
- `ignoredups` — don't save a command identical to the immediately previous
  one.
- `ignoreboth` — shorthand for `ignorespace:ignoredups`.
- `erasedups` — remove *all* earlier copies of the command line from the
  history list before saving the new one (more aggressive than `ignoredups`,
  which only checks the previous entry).

## `HISTIGNORE` — exclude specific command patterns

```bash
export HISTIGNORE="ls:ls -la:cd:cd -:pwd:exit:clear:history*:bg:fg:jobs"
```

Colon-separated list of glob patterns (`*` and `?` work). Each pattern is
matched against the whole command line; a match means "don't record it." Use
it to drop navigation and status noise. Note each pattern must match the
*entire* line, so `history*` catches `history`, `history -c`, etc., but `ls`
alone does **not** catch `ls -la` — list both, or use `ls*` (which also
matches `lsof`, so be deliberate).

## `HISTSIZE` / `HISTFILESIZE` — how much to keep

```bash
export HISTSIZE=5000        # commands kept in memory for the session
export HISTFILESIZE=10000   # lines kept in ~/.bash_history on disk
```

Set either to a negative number for "unlimited"; set to `0` to disable
history entirely.

## `HISTTIMEFORMAT` — timestamp each entry

```bash
export HISTTIMEFORMAT='%F %T  '
```

Makes `history` print a date/time before each command, and causes the
timestamps to be written to `~/.bash_history` (as `#<epoch>` comment lines).

## `shopt -s histappend` — don't clobber history between shells

```bash
shopt -s histappend
```

By default the last shell to exit overwrites `~/.bash_history` with its own
session list, losing everything from other concurrent shells. `histappend`
makes each shell *append* its session instead. To flush after every command
rather than only at exit:

```bash
export PROMPT_COMMAND='history -a'
```

`history -a` appends just the new in-memory lines to the file immediately.

## Pruning what's already there

- `history -d <n>` — delete entry number `<n>` from the current session list
  (numbers as shown by `history`). A range works too: `history -d 512-518`.
- `history -d -1` — delete the last entry (e.g. the command that pasted a
  secret, run before it hits disk).
- `history -c` — clear the entire in-memory list. Does not touch
  `~/.bash_history` until the shell exits or you run `history -w`.
- `history -w` — write the current in-memory list to `~/.bash_history` now,
  overwriting it. Pair with `history -c` to hard-reset: `history -c && history -w`.
- `history -r` — reload from the file, discarding unsaved session entries.

## Keeping a curated snippet file instead

Shell history is a log, not a knowledge base. For "commands worth keeping,"
append them to a dedicated file:

```bash
save_cmd() {           # add to ~/.bashrc
  fc -ln -1 | sed 's/^\s*//' >> ~/useful-commands.sh
}
```

Run `save_cmd` right after a command you want to keep — `fc -ln -1` prints
the previous command line without its number, and the `sed` strips the
leading whitespace `fc` indents with. Then `grep` that file when you need it.

## See Also

- [`bash-history-expansion.md`](bash-history-expansion.md) — the recall side:
  `!!`, `!$`, `^old^new^`, and the `!`-in-double-quotes gotcha
- [`linux-aliases.md`](linux-aliases.md) — where a curated `save_cmd` /
  snippet-file workflow tends to live alongside your aliases
- [`prompt.sh`](prompt.sh) — `PROMPT_COMMAND` is also where prompt setup runs;
  chain with `;` if you use both
