# TTY colors — ANSI escapes & piping

## Syntax

```
\033[<code>m ... \033[0m
```

`\033[` (or `\e[`, `\x1b[`) starts an escape sequence, `<code>` sets an attribute, and text after it stays styled until a reset (`\033[0m`). Nothing is "erased" — these are just bytes in the stream that a terminal emulator interprets as instructions instead of characters.

---

## Color Codes

|Code|Foreground|Code|Background|
|---|---|---|---|
|`30`|Black|`40`|Black|
|`31`|Red|`41`|Red|
|`32`|Green|`42`|Green|
|`33`|Yellow|`43`|Yellow|
|`34`|Blue|`44`|Blue|
|`35`|Magenta|`45`|Magenta|
|`36`|Cyan|`46`|Cyan|
|`37`|White|`47`|White|
|`90`-`97`|Bright variants|`100`-`107`|Bright variants|

|Attribute|Code|
|---|---|
|Reset|`0`|
|Bold|`1`|
|Dim|`2`|
|Underline|`4`|
|Blink|`5`|
|Reverse (swap fg/bg)|`7`|

---

## Color Modes — 8/16 vs 256 vs truecolor

There are three separate SGR syntaxes, not one scale with bigger numbers. Which one you can use depends on terminal support.

### 8/16-color (standard)

The table above. Single-number SGR code sets the color directly: `\033[32m` = green foreground, `\033[42m` = green background. Universally supported — this is the safe baseline for scripts that might run anywhere.

### 256-color (indexed/extended)

A different sequence shape — `5;` signals "indexed color follows":
```
\033[38;5;<N>m   # foreground, N = 0-255
\033[48;5;<N>m   # background, N = 0-255
```
The 256-entry palette is fixed and splits into three ranges:

|Index range|Meaning|
|---|---|
|`0-15`|Same 16 standard/bright colors, addressable through this syntax too|
|`16-231`|6×6×6 RGB color cube (216 colors): index `= 16 + 36r + 6g + b`, each of r,g,b in `0-5`|
|`232-255`|24-step grayscale ramp, near-black to near-white|

This is what the 256-color grid loop under "Printing Them" is walking — it just never explained the palette structure until now.

### 24-bit truecolor

`2;` instead of `5;` signals literal RGB, no palette lookup:
```
\033[38;2;<r>;<g>;<b>m   # foreground, r/g/b = 0-255 each
\033[48;2;<r>;<g>;<b>m   # background
```
Most modern terminal emulators (iTerm2, GNOME Terminal, Windows Terminal, kitty, alacritty) support this; some (older xterm, some TTYs/serial consoles, `screen` without patches) don't and will render garbage or fall back unpredictably. There's no reliable terminfo capability for this the way there is for 256-color — support is generally assumed from `$COLORTERM=truecolor` or `$COLORTERM=24bit`, not guaranteed.

### Checking what a terminal supports

```bash
echo $TERM              # e.g. xterm-256color implies 256-color support
tput colors              # prints the number of colors terminfo believes this terminal supports
echo $COLORTERM          # "truecolor" or "24bit" if the emulator advertises 24-bit support
```
`tput setaf <N>` (used below) only reliably covers `0-7` on every terminal; values up to 255 depend on `tput colors` reporting 256. There's no `tput` equivalent for 24-bit — truecolor always means hand-writing the `38;2;...` escape yourself.

---

## Shell Variables

```bash
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
MAGENTA=$'\033[35m'
CYAN=$'\033[36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'
```

`$'...'` is bash's ANSI-C quoting — it turns `\033` into the actual escape byte instead of a literal backslash-zero-three-three. Using plain `"..."` would print the escape sequence as text.

---

## Printing Them

```bash
# Print each foreground color with its own escape
for i in {30..37}; do
  printf "\033[%sm Color %s \033[0m\n" "$i" "$i"
done

# All 256 colors, compact grid
for i in {0..255}; do
  printf "\033[48;5;%sm%3d\033[0m " "$i" "$i"
  (( (i + 1) % 16 == 0 )) && printf "\n"
done

# 24-bit truecolor gradient — requires terminal support, no palette/tput equivalent
for i in {0..255}; do
  printf "\033[48;2;%d;0;%dm \033[0m" "$i" "$((255 - i))"
done
printf "\n"

# tput — terminfo-driven, portable alternative to raw codes (0-7 always safe)
tput setaf 1; echo "red text"; tput sgr0
tput bold; echo "bold text"; tput sgr0
```

`tput setaf <N>` sets foreground via terminfo instead of hardcoding ANSI numbers. `0-7` works on every terminal; higher values only work if `tput colors` reports enough colors (see "Color Modes" above). `tput sgr0` is the portable reset (equivalent to `\033[0m`).

---

## Colors In Piping — the rationale

Escape codes are ordinary bytes sitting in the middle of the text stream. Any program that isn't specifically built to recognize them just sees noise — they aren't a side channel, they're part of the payload.

**Why tools auto-disable color when piped**

Most color-capable tools (`git`, `ls`, `grep`, `rg`) default to `--color=auto`: they call `isatty(stdout)` and only emit escape codes if stdout is a real terminal. The moment output goes anywhere else — a pipe, a redirect, a file — they assume something is going to *parse* that text and switch color off automatically. That's why `git lg2 | head` comes out plain/uncolored: piping to `head` makes stdout a pipe, not a tty, so git's `isatty()` check fails and it never emits the escape codes in the first place. `head` isn't stripping anything — there's nothing to strip, git never sent it.

**What forces color back on**

`--color=always` (or equivalents: `grep --color=always`, `ls --color=always`) skips the tty check and emits codes unconditionally, regardless of what's downstream. Use this only when you know a human will eventually see the raw output rendered by a real terminal.

**What strips vs. passes through escape codes**

|Tool|Behavior|
|---|---|
|`head` / `tail` / `cat`|Pass bytes through untouched — including escape codes if present|
|`less` (no flags)|Escapes/shows codes literally as visible junk|
|`less -R`|Interprets ANSI color codes properly, passes them to the terminal|
|`grep`|Auto color, but matches on bytes — a code split mid-match can break matching or search for the code itself|
|`sed` / `awk`|Treat codes as literal characters — can break field splitting or pattern matching|
|`wc -c` / `wc -m`|Counts escape bytes as characters — inflates size/length|
|`> file` redirect|No terminal at all downstream — most tools auto-disable, writing garbage codes to a file only happens if you forced `--color=always`|

**When to force color on**

- Piping through something that only *relays* to a terminal and doesn't parse content: `head`, `tail`, `less -R`, `column`, a `tmux`/`screen` pane.
- You want colored output saved to a log file that will later be viewed with `less -R` or `cat` in a terminal (rare — usually undesired).

**When to leave color auto/off**

- Piping into `grep`, `awk`, `sed`, `wc`, `cut`, or anything that inspects/transforms the text — codes corrupt matches, field counts, and byte counts.
- Writing output to a file meant for another program to consume (CI logs, JSON, config).
- Any script whose output might itself be piped further downstream by someone else — don't force color in library/utility scripts, only in interactive one-liners.

---

## Practical Recipes

```bash
# Limit output instead of piping — no color loss, since stdout stays a tty
git lg2 -20

# Must pipe to head/tail? Force color so it survives the pipe
git lg2 --color=always | head -30

# Piping into a pager? Force color and tell the pager to render it, not escape it
git log --color=always | less -R

# grep on colored source without breaking the match: strip codes first
some_colored_command | sed -E 's/\x1b\[[0-9;]*m//g' | grep 'pattern'

# Or just tell the source tool not to color, if it supports it
grep --color=never 'pattern' file | sort
```
