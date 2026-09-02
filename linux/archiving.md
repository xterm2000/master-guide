# Archiving & Compression (tar, gzip, xz, zstd, zip)

Every command and output note below was run on this dev box — Rocky Linux 10.2,
GNU tar 1.35, gzip 1.13, bzip2 1.0.8, xz 5.6.2, zstd 1.5.5, Info-ZIP zip 3.0 /
unzip 6.00. Things that are *not* installed here are called out where they'd
otherwise be the obvious answer (`pigz`, `lz4`, `plzip`, `pv`).

---

## 1. The mental model: two separate steps

On Unix, **bundling many files into one** and **compressing a byte stream** are
two different jobs done by two different tools:

- **`tar`** ("tape archive") walks a set of paths and writes them — contents plus
  metadata (permissions, owner, timestamps, symlinks) — into one continuous
  stream. That stream is the *archive*. `tar` on its own does **no** compression.
- **`gzip` / `bzip2` / `xz` / `zstd`** each take one stream in and write one
  smaller stream out. They know nothing about files or directories.

`tar` calls a compressor for you when asked, which is why the canonical Linux
bundle carries **two** extensions — `.tar.gz`, `.tar.xz`, `.tar.zst` — one per
step. `.tgz` and `.txz` are just contractions of the same thing.

**`zip` is the exception:** it compresses each member individually *and* stores
the directory structure in a single file. That independence is why you can list
or extract one entry from a huge `.zip` instantly, but also why `.zip` compresses
a little worse than a solid `.tar.*` (it can't share redundancy across files).

---

## 2. Which format to use

| You want… | Use | Why |
|---|---|---|
| Linux → Linux, everyday backup/move | **`.tar.zst`** | zstd is nearly as small as `xz` at a fraction of the CPU; great decompress speed |
| Smallest possible artifact, distributed for download | **`.tar.xz`** | best ratio of the mainstream tools; slow to create, fine to decompress |
| Maximum compatibility / old systems / CI that predates zstd | **`.tar.gz`** | every machine since the 1990s can open it |
| Sending to a Windows user or someone unknown | **`.zip`** | opens with a double-click on Windows/macOS; no `tar` needed |
| A single already-bundled file (a DB dump, a log) | raw **`zstd`** or **`gzip`** | no `tar` layer needed for one file |
| Long-term archive you may open in 15 years | **`.tar.gz`** or **`.zip`** | boring, ubiquitous formats outlive clever ones |

Rough trade-off at default settings (same input): `gzip` fastest-but-biggest,
`zstd` ~gzip speed with ~`xz` size, `bzip2` slow and now largely obsolete, `xz`
smallest and slowest.

---

## 3. tar basics

One letter picks the mode, `-f` names the archive file (must come right before
the filename), everything else is a modifier.

```bash
# Create
tar -cf backup.tar  dir1 dir2 file.txt      # uncompressed
tar -czf backup.tar.gz   project/           # + gzip
tar -cJf backup.tar.xz   project/           # + xz
tar --zstd -cf backup.tar.zst project/      # + zstd (no short flag)

# List (no extraction) — always do this before extracting something you didn't make
tar -tf backup.tar.zst
tar -tvf backup.tar.zst                      # long listing: perms, size, mtime

# Extract
tar -xf backup.tar.zst                       # into current dir
tar -xf backup.tar.zst -C /target/dir        # into a specific dir (created must exist)
tar -xf backup.tar.zst path/inside/one.txt   # just one member
```

**Extension autodetect.** GNU tar picks the compressor from the output name if
you use `-a` (or the `caf` combo), and picks it automatically on *every* extract
regardless of extension:

```bash
tar -caf backup.tar.zst project/     # -a => "auto", chooses zstd from ".zst"
tar -xf  whatever.bin                # still detects xz/gzip/zstd from the data
```

Verified: `tar -caf x.tar.zst d` produces a real zstd stream; `tar -xf x.tar.xz`
works with no `-J`.

Useful modifiers:

| Flag | Effect |
|---|---|
| `-v` | list each file as processed |
| `-C DIR` | `cd` to `DIR` **before** handling the paths after it (order matters) |
| `--strip-components=N` | drop the first `N` path segments on extract (flatten a leading dir) |
| `-p` | restore permissions exactly (default when root; needs asking otherwise) |
| `--no-same-owner` | extract files owned by *you*, not by the UIDs in the archive |

---

## 4. Choosing and tuning the compressor

### Levels

Every compressor takes `-1`..`-9` (fast→small). Defaults: **gzip 6**, **zstd 3**,
**xz 6**. zstd goes further with `--ultra` up to `-22`.

```bash
tar -caf big.tar.xz  -I 'xz -9'          project/     # xz, max level
tar -caf big.tar.zst -I 'zstd -19'       project/     # zstd, high level
tar -caf big.tar.zst -I 'zstd --ultra -22 --long' project/   # squeeze harder
```

`-I 'prog args'` tells tar to pipe through an arbitrary compressor command —
the general escape hatch, and how you pass flags a short option can't.

### Environment knobs (no `-I` needed)

```bash
XZ_OPT=-9      tar -cJf big.tar.xz  project/
ZSTD_CLEVEL=19 tar --zstd -cf big.tar.zst project/
```

Both verified to take effect.

### Threads

```bash
tar -caf big.tar.zst -I 'zstd -T0' project/    # zstd: all cores
tar -caf big.tar.xz  -I 'xz -T0'   project/    # xz 5.6: -T0 = all cores
```

`xz --help` on 5.6.2 reports the `--threads` default as `0` (all cores), but
older xz defaults to single-threaded — pass `-T0` explicitly for portable
scripts. **`pigz` (parallel gzip) is not installed here**; if you need a fast
parallel option, zstd already is one.

---

## 5. Selecting and excluding content

```bash
# Exclude patterns (repeatable). Pattern matches the path as stored in the archive.
tar -caf src.tar.zst --exclude='project/node_modules' \
                     --exclude='*.log' \
                     --exclude-from=.tarignore \
                     project/

# Explicit file list instead of walking a tree
tar -caf pick.tar.zst -T files-to-include.txt

# Don't cross into other mounted filesystems
tar -caf root.tar.zst --one-file-system /

# Crude incremental: only files modified since a timestamp
tar -caf since.tar.zst --newer-mtime='2026-08-01' project/
```

Verified: `--exclude='demo/sub'` drops that directory and its contents; the
pattern is matched against the member path, so anchor it to how the paths appear
in `tar -tf`.

For real incremental backups (with deletions tracked) use
`tar --listed-incremental=snapshot.snar` — heavier, keeps a state file.

---

## 6. Preserving metadata

`tar` already stores owner, group, mode, mtime and **symlinks as symlinks**
(verified — a symlink member extracts back as a link, not a copy). Extra
attributes need explicit flags on **both** create and extract:

```bash
tar --acls --xattrs --selinux -caf full.tar.zst /etc
tar --acls --xattrs --selinux -xf  full.tar.zst -C /restore
```

| Flag | When you need it |
|---|---|
| `--acls` | POSIX ACLs are set (see `linux/sysadmin/acls.md`) |
| `--xattrs` | extended attributes / capabilities |
| `--selinux` | restoring files that must keep their SELinux context (`linux/sysadmin/selinux.md`) |
| `--numeric-owner` | restoring on a host where user/group names don't match — store/restore raw UIDs/GIDs |
| `--sparse` (`-S`) | archiving sparse files (VM images, DB files) without ballooning them |
| `-p` / `--same-permissions` | force exact mode restore even as non-root |

All of the above are present in `tar --help` on 1.35.

**Owner on extract:** as root, `tar` restores the archived UIDs/GIDs by default —
add `--no-same-owner` if you're unpacking someone else's archive and want it
owned by root instead of by whatever UID 1000 happened to be on their box.

**`zip` follows symlinks by default** — verified, a symlink got stored as a
6-byte regular file. Use `zip -y` to store links as links.

---

## 7. Streaming and pipelines

`tar` reads/writes stdin/stdout when the filename is `-`, so it composes:

```bash
# Copy a tree to another host, no intermediate file
tar -caf - project/ | ssh user@host 'tar -xf - -C /opt'

# Encrypt an archive (see linux/gpg/gpg-guide.md)
tar -caf - project/ | gpg -c -o project.tar.zst.gpg     # -c = symmetric

# Fan out: write compressed and count entries in one pass
tar -cf - project/ | tee >(zstd -q -o project.tar.zst) | tar -tf - | wc -l
```

### Multi-volume (split a huge archive, reassemble later)

```bash
# Split into 2 GiB parts
tar -caf - bigdir/ | split -b 2G - bigdir.tar.zst.part-

# Reassemble — order matters, the shell glob sorts correctly
cat bigdir.tar.zst.part-* | tar -xf -
```

Verified round-trip: `cat part-* | tar -xf -` restores the tree. (This is plain
`split`, unrelated to `tar --multi-volume`, which is for tape changes.)

---

## 8. Verifying integrity

```bash
# 1. Does the archive parse and list cleanly? (cheap, catches truncation)
tar -tf backup.tar.zst >/dev/null && echo OK

# 2. Does compression checksum verify? (each tool has -t / --test)
gzip -t  backup.tar.gz
xz   -t  backup.tar.xz
zstd -t  backup.tar.zst
bzip2 -t backup.tar.bz2

# 3. Does the archive still match the filesystem it came from?
tar --compare -f backup.tar.zst          # aka --diff, -d ; exit 0 = identical

# 4. For transfers: a checksum sidecar
sha256sum backup.tar.zst > backup.tar.zst.sha256
sha256sum -c backup.tar.zst.sha256       # on the far side
```

`tar --compare` verified to exit 0 against an unmodified tree.

---

## 9. zip / unzip

For handing files to someone not on Linux. Info-ZIP `zip` 3.0 / `unzip` 6.00
(the `unzip` release is from 2009 — still the system default).

```bash
zip -r  archive.zip  project/              # recurse
zip -r  archive.zip  project/ -x '*.log' -x 'project/tmp/*'   # excludes
zip -ry archive.zip  project/              # -y: keep symlinks as links
zip -r -9 archive.zip project/             # max deflate (small effect)

unzip -l archive.zip                       # list
unzip    archive.zip -d /target            # extract into dir
unzip -o archive.zip                       # overwrite without prompting
unzip -n archive.zip                       # never overwrite
zipinfo  archive.zip                       # detailed listing
zipsplit -n 5000000 archive.zip            # break into ~5 MB pieces
```

Caveats:

- **No zstd.** Info-ZIP `zip` only does *deflate* (same core algorithm as gzip);
  expect `.tar.xz`/`.tar.zst` to be noticeably smaller.
- **`zip -e` / `-P` encryption is legacy ZipCrypto** — weak, breakable, keep it
  only for trivial "don't peek" cases. For real protection pipe a `.tar` through
  `gpg` (§7) or use `7z` with AES (not installed here).
- **Filenames:** non-ASCII names can arrive mojibake'd on Windows depending on
  the code page; stick to ASCII names if the recipient is on Windows.
- Empty directories: `zip` stores them, `unzip` recreates them.

---

## 10. Compressing a single file

When there's nothing to bundle — one dump, one log:

```bash
zstd    data.sql            # -> data.sql.zst   (removes original unless -k)
zstd -k -19 data.sql        # keep original, high level
gzip -k data.sql            # -> data.sql.gz, keep original
xz   -k data.sql
zstd -d  data.sql.zst       # decompress
gunzip   data.sql.gz

gzip -l data.sql.gz         # show compressed/uncompressed size + ratio
```

`-k` (keep) matters: by default all four **delete the input** on success.

**Reading without decompressing** — the `z*` / `xz*` helper family:

```bash
zcat file.gz          zless file.xz         zgrep pattern file.gz
xzcat file.xz         zstdcat file.zst      xzgrep pattern file.xz
```

See `linux/text-processing/grep.md` for the `zgrep`/`xzgrep` variants in context.

---

## 11. Recipes

```bash
# Back up a directory, dated, excluding junk
tar -caf "home-$(date +%F).tar.zst" \
    --exclude='.cache' --exclude='*/node_modules' \
    -C /home me/

# Extract just one file from a big archive
tar -xf release.tar.gz --strip-components=1 project-1.4.2/bin/tool

# List an archive's contents without unpacking
tar -tvf mystery.tar.xz | less

# Repackage .tar.gz as .tar.zst without touching disk twice
gunzip -c old.tar.gz | zstd -19 -T0 -o new.tar.zst

# Flatten a leading top directory on extract
tar -xf project-main.tar.gz --strip-components=1 -C ./project

# Archive straight to a remote host
tar -caf - /var/www | ssh backup@nas 'cat > /backups/www-$(date +%F).tar.zst'
```

---

## 12. Gotchas

- **`bzip2` / `xz` with no filename read stdin.** `bzip2 --version` and
  `xz` alone will *hang waiting for input* rather than print and exit — always
  give them a file or redirect (`</dev/null`). This bit a script in this repo.
- **Leading `/` is stripped.** `tar -cf a.tar /etc/hostname` stores it as
  `etc/hostname` and prints `Removing leading '/' from member names`. Extraction
  is therefore relative to the current dir. Use `-P` / `--absolute-names` to keep
  absolute paths (rarely what you want).
- **`..` members are dropped** on extract by GNU tar unless `--absolute-names` —
  a safety measure against archives that try to escape the target dir. Still,
  **list an untrusted archive with `-tf` before extracting**, and consider
  `--keep-old-files` (`-k`) so a malicious archive can't overwrite existing files.
- **`-C` position matters.** `tar -xf a.tar -C /dst file` = `cd /dst` then extract
  `file`. `tar -xf a.tar file -C /dst` does *not* do what you want.
- **Extraction merges, it doesn't replace.** Unpacking over an existing directory
  overlays files; it won't delete entries that aren't in the archive.
- **`zip` follows symlinks** unless `-y`; `tar` never does.
- **Double-compressing wastes CPU.** `tar -czf x.tar.zst` gzips *and* mislabels;
  pick one compressor and the matching extension.

---

## See Also

- [`linux-commands.md`](linux-commands.md) — general sysadmin command reference
- [`shell/linux-aliases.md`](shell/linux-aliases.md) — `untar` / `ctar` convenience aliases and why aliasing `tar` itself is a trap
- [`text-processing/grep.md`](text-processing/grep.md) — `zgrep` / `xzgrep` for searching inside compressed files
- [`gpg/gpg-guide.md`](gpg/gpg-guide.md) — encrypting an archive with `gpg -c` or to a recipient key
- [`shell/process-substitution.md`](shell/process-substitution.md) — the `tee >(gzip …)` fan-out pattern
- [`sysadmin/acls.md`](sysadmin/acls.md) — what `tar --acls` is preserving
