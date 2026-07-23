# Git: Actually Purging Unreachable Objects (Not Just Unreferenced)

`git-guide.md` covers `filter-repo` and notes that rewritten objects "remain in the reflog until it expires or is pruned" — this doc is the missing other half: the concrete commands to force that expiry/prune immediately, and how to verify an object is truly gone rather than just unreachable from any branch.

Applies after **any** history-rewrite that's meant to remove a secret — `filter-repo`, an interactive rebase that drops a commit, a `reset --hard`, or a manual squash via orphan branch. In all of these, the old blob is not deleted the moment no branch points at it anymore; it's just unreachable, and still fully readable by hash until garbage collected.

---

## Why "unreachable" ≠ "gone"

Git defaults to safety over immediate cleanup:

- **The reflog holds objects alive.** Every ref update (commit, reset, branch delete, rebase) is logged, and anything reachable from a reflog entry survives — by default ~90 days for reachable entries, ~30 days for entries that only point at otherwise-unreachable commits (`gc.reflogExpire` / `gc.reflogExpireUnreachable`).
- **GC is not synchronous.** Git doesn't walk and delete unreferenced objects after every command — it runs opportunistically (`git gc --auto`, roughly every ~6700 loose objects) or when explicitly invoked.

Net effect: after a squash/rebase/filter-repo that's supposed to erase a secret from history, the old blob is very likely still sitting in `.git/objects`, retrievable with `git show <hash>`, until you force the cleanup below.

---

## Force-purge now

```bash
git reflog expire --expire=now --all      # drop reflog entries immediately, don't wait for the 90-day default
git gc --prune=now --aggressive           # actually delete now-unreferenced objects
```

`--aggressive` repacks more thoroughly (slower, smaller result) — worth it for a one-off cleanup, skip it for routine maintenance.

> This is **local only**. If the history was ever pushed, the same objects live in every remote and every clone/fork. Purging locally does nothing to a GitHub/GitLab copy — you still need `git push --force` (after the rewrite) to overwrite the remote ref, and the remote's own reflog/GC schedule (which you don't control) governs when *its* copy of the old objects actually disappears. Treat any secret that was ever pushed as compromised and rotate it — local purging is hygiene, not a fix for exposure that already happened.

---

## Verify it actually worked

```bash
git fsck --unreachable --no-reflogs    # should print nothing if the purge worked
git show <old-blob-hash>               # should fail with "unknown revision", not print the old content
```

If `fsck` still lists unreachable commits/blobs/trees after the expire+gc, something is still referencing them — check for other local branches, tags, stashes, or worktrees pointing at the old history before repeating.

---

## Quick reference

| Command | Effect |
|---|---|
| `git reflog` | Show what's kept alive and why |
| `git reflog expire --expire=now --all` | Immediately drop reflog protection on everything |
| `git gc --prune=now --aggressive` | Delete now-unreferenced objects for real |
| `git fsck --unreachable --no-reflogs` | List what's still recoverable-but-detached (should be empty after the above) |
| `git show <hash>` | Confirm a specific known-sensitive blob no longer resolves |

→ See also: [[git-guide#reflog — the safety net under all of the above]], [[git-guide#filter-repo — rewrite the entire history]]
