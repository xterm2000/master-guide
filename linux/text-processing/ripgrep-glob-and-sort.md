# ripgrep: Glob Precedence, Anchoring, and Sort Performance

Companion to `ripgrep-example.md` (glob syntax breakdown) — these are three
separate gotchas verified against `rip-grep-manual.txt`, ripgrep's own
`--help`/man output shipped in this directory.

## Last matching glob wins

```bash
rg "TODO" -g "*.md" -g "!README.md"
```

When multiple `-g`/`--iglob` flags are given and more than one matches the
same file or directory, **the glob given later on the command line takes
precedence** (`rip-grep-manual.txt` lines 590-591, restated identically for
`--iglob` at lines 629-631). This is the mechanism behind include/exclude
combos like the one above: `-g "!README.md"` comes after `-g "*.md"`, so the
exclusion overrides the earlier inclusion for that one file.

Flip the order and the result flips too:

```bash
rg "TODO" -g "!README.md" -g "*.md"    # README.md IS searched — *.md now wins
```

There's no special-casing for `!` (negation) globs to always win — position
in the argument list is the only thing that decides precedence.

## Anchoring: a bare name doesn't match nested paths

```bash
rg "TODO" -g foo          # WRONG — does not match foo/bar.txt
rg "TODO" -g 'foo/**'     # correct — matches everything under foo/
```

The manual is explicit about this (lines 601-604): "if you only want to
search in a particular directory `foo`, then `-g foo` is incorrect because
`foo/bar` does not match the glob `foo`." A glob with no `/` in it matches
only a bare filename at any depth, not a directory prefix — you have to spell
out `foo/**` to anchor it as "this directory and everything below."

This is the same anchoring rule `.gitignore` uses (ripgrep's glob matching is
gitignore-compatible), so the fix transfers directly if you already know that
convention.

## `--sort=modified` forces single-threaded search

```bash
touch old-file.txt
sleep 1
touch new-file.txt
rg --sort=modified "TODO" .
```

`touch`ing a file updates its mtime, which is what `--sort=modified` orders
results by (manual lines 1267-1279). The performance-relevant part is easy to
miss: **every non-`none` sort value — `path`, `modified`, `accessed`,
`created` — forces ripgrep to abandon parallelism and run single-threaded**
(manual lines 1279-1293, restated for `--sortr` at lines 1327-1330). `none`
(the default) is explicitly called out as "Fastest. Can be multi-threaded."

So `--sort=modified` isn't just a display option — it's a deliberate
throughput trade: correct ordering in exchange for losing ripgrep's normal
parallel directory walk. On a large tree, expect a noticeably slower search
the moment any `--sort`/`--sortr` value other than `none` is set.

## See Also

- `ripgrep-example.md` — glob/iglob syntax breakdown (brace expansion, `**`,
  single-star-within-segment)
- `rip-grep-manual.txt` — full reference this file's claims are checked
  against
