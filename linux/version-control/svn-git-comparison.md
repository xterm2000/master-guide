# SVN ↔ Git Comparison — For TortoiseSVN Users

> You already know Git. This doc maps SVN concepts and TortoiseSVN actions to their Git equivalents, explains the key differences, and flags the gotchas that will surprise you.

---

## 1. The Fundamental Difference — Architecture

This is the single biggest thing. Everything else flows from it.

### Git — Distributed

```
 Your Machine              Teammate's Machine
┌─────────────────┐        ┌─────────────────┐
│  Full repository │        │  Full repository │
│  (entire history)│        │  (entire history)│
│                 │        │                 │
│  local commits  │        │  local commits  │
└────────┬────────┘        └────────┬────────┘
         │  push/pull               │  push/pull
         ▼                          ▼
  ┌─────────────┐
  │  GitHub /   │
  │  GitLab /   │   ← "origin" — just another full copy
  │  Gitea etc  │
  └─────────────┘
```

Every developer has the **complete repository** including the full history. Commits are local until you push. You can work, commit, branch, and inspect history with no network access at all.

### SVN — Centralized

```
  Your Machine              Teammate's Machine
┌──────────────────┐       ┌──────────────────┐
│  Working Copy    │       │  Working Copy     │
│  (current files  │       │  (current files   │
│  only, no full   │       │  only, no full    │
│  history)        │       │  history)         │
└────────┬─────────┘       └────────┬──────────┘
         │  commit / update          │  commit / update
         ▼                           ▼
  ┌──────────────────────────────────────┐
  │          SVN Server                  │
  │  (the ONE repository — all history,  │
  │   all branches, the source of truth) │
  └──────────────────────────────────────┘
```

There is exactly **one repository** — on the server. Your working copy is just a checked-out snapshot. Every commit goes directly to the server. No network = no commit.

### Consequence table

| Question | Git answer | SVN answer |
|---|---|---|
| Where is the full history? | Locally on every machine | Only on the server |
| Can I commit without network? | Yes — commit is local | No — commit requires server |
| Can I browse old history offline? | Yes | No |
| What is a "commit"? | A local snapshot | A published change on the server |
| What identifies a commit? | SHA-1 hash (e.g. `a3f9c12`) | Sequential integer (e.g. `r1042`) |
| Can two people have the same revision number mean different things? | No — hash is content-based | No — revision numbers are global |

---

## 2. Terminology Mapping

| SVN term | Git equivalent | Notes |
|---|---|---|
| Repository | Repository + remote | SVN repo lives on server only; Git repo is local + remote |
| Working copy | Working tree | Your local checked-out files |
| `trunk` | `main` / `master` branch | SVN `trunk` is a convention, not a special object |
| `branches/feature-x` | `feature-x` branch | SVN branch = a directory copy; Git branch = a pointer |
| `tags/v1.0` | `v1.0` tag | SVN tag = a directory copy (by convention read-only); Git tag = a lightweight or annotated object |
| Revision (r1042) | Commit hash (a3f9c12) | SVN revisions are sequential integers across the whole repo |
| Checkout | Clone (first time) | SVN checkout = initial download of working copy |
| Update | Pull (fetch + merge) | SVN update = get latest from server into your working copy |
| Commit | Add + Commit + Push | SVN commit immediately publishes to server |
| Revert | Restore / Reset | Discard local changes |
| Switch | Checkout / Switch branch | Point working copy at a different branch/tag |
| Merge | Merge / Rebase | Integrate changes from another branch |
| Lock | (no direct equivalent) | SVN exclusive file lock — Git has no equivalent |
| Externals | Submodules | Reference to another repo/path |
| `svn:ignore` property | `.gitignore` | Ignore patterns |

---

## 3. Daily Workflow — TortoiseSVN vs Git

### Getting a repository for the first time

| Action | TortoiseSVN | Git equivalent |
|---|---|---|
| Get a copy of the repo | Right-click empty folder → **SVN Checkout** → enter repo URL | `git clone <url>` |
| What you get | Working copy of `trunk` (or chosen path) | Full repo clone with all history |

> **Key difference:** SVN checkout downloads only the files at the revision you specify, not the full history. The history stays on the server. Git clone downloads everything.

---

### The daily loop

```
SVN daily loop:                     Git daily loop:

  svn update (get server changes)     git fetch (see what's there)
        ↓                                   ↓
   edit files                          edit files
        ↓                                   ↓
  svn commit (publish immediately)     git add → git commit (local)
                                             ↓
                                        git push (publish when ready)
```

| Action | TortoiseSVN | Git equivalent |
|---|---|---|
| Get latest changes | Right-click → **SVN Update** | `git pull` (or `git fetch` + `git merge`) |
| See what's changed locally | Right-click → **TortoiseSVN → Check for Modifications** | `git status` + `git diff` |
| Stage/select files to commit | The commit dialog lets you check/uncheck files | `git add <file>` or `git add -p` |
| Commit | Right-click → **SVN Commit** → write message → OK | `git commit -m "..."` + `git push` |
| Discard local changes | Right-click → **TortoiseSVN → Revert** | `git restore <file>` |
| See history | Right-click → **TortoiseSVN → Show Log** | `git log --oneline --graph` |
| See diff of a file | Right-click → **TortoiseSVN → Diff** | `git diff <file>` |
| See diff of a revision | In Show Log → select revision → Show Changes | `git show <hash>` |
| Annotate / blame | Right-click → **TortoiseSVN → Blame** | `git blame <file>` |

> **The biggest gotcha:** In SVN, clicking **Commit** is the same as `git commit` + `git push` combined. There are no local-only commits. If the server is down, you cannot commit.

---

### Checking what changed before you update

In Git you run `git fetch` first, then inspect before merging. SVN has no direct equivalent — update just applies immediately. To preview:

- In TortoiseSVN: Right-click → **TortoiseSVN → Check for Modifications** → tick "Show unversioned files" and "Show remote changes"
- Or in Show Log: compare your working copy revision vs the HEAD revision on server

---

## 4. Branching and Tagging

### How SVN branches work — directory copies

In SVN, **a branch is just a copy of a directory** on the server. By convention:

```
Repository root
├── trunk/           ← main development line
├── branches/
│   ├── feature-x/  ← copy of trunk at r500
│   └── hotfix-1/   ← copy of trunk at r612
└── tags/
    ├── v1.0/        ← copy of trunk at r400 (read-only by convention)
    └── v1.1/        ← copy of trunk at r590
```

Nothing enforces this structure — it's a community convention. A tag is technically the same as a branch (a directory copy); people just don't commit to it.

### How Git branches work — pointers

In Git, a branch is a **lightweight pointer** to a commit. Creating a branch is instant and uses almost no disk space:

```
main:    A → B → C → D → E    ← branch pointer
                        ↑
feature:                └→ X → Y   ← another pointer
```

### Branch operations

| Action | TortoiseSVN | Git equivalent |
|---|---|---|
| Create a branch | Right-click → **TortoiseSVN → Branch/Tag** → set destination path under `branches/` | `git switch -c feature-x` |
| Switch to a branch | Right-click → **TortoiseSVN → Switch** → enter branch URL | `git switch feature-x` |
| List branches | Browse repository (Repo-browser) and look under `branches/` | `git branch -a` |
| Delete a branch | In Repo-browser, delete the `branches/feature-x` folder | `git branch -d feature-x` |
| Create a tag | Right-click → **Branch/Tag** → set destination under `tags/` | `git tag v1.0` |

### Structural comparison

```
SVN (directories):                  Git (pointers):

  repo/                               main ──────────→ [commit E]
  ├── trunk/         ← active                            ↑
  ├── branches/                       feature-x ──→ [commit Y]
  │   └── feature-x/ ← active copy                  /
  └── tags/                         [A]→[B]→[C]→[D]→[E]
      └── v1.0/      ← frozen copy              └→[X]→[Y]
```

> **Key difference:** Switching branches in SVN re-downloads files from the server and repoints your working copy. In Git it's an instant local operation — you can switch 10 times per second.

---

## 5. Merging

### SVN merge — tracking via revision ranges

SVN tracks merges using a special property (`svn:mergeinfo`) stored on directories. You must tell it which revision range to merge.

| Action | TortoiseSVN | Git equivalent |
|---|---|---|
| Merge a branch into trunk | Switch to trunk → right-click → **TortoiseSVN → Merge** → choose branch + revision range | `git merge feature-x` |
| Merge all unmerged changes | Merge dialog → "Merge a range of revisions" → leave range empty (auto-detect) | `git merge feature-x` |
| Preview what will be merged | Merge dialog → **Dry Run** button | `git diff main..feature-x` |
| After merge, commit it | Merge dialog applies changes to working copy; you still must **SVN Commit** | `git push` (merge commit already local) |

### Merge flow comparison

```
SVN merge flow:                         Git merge flow:

  switch working copy to trunk            git switch main
        ↓                                       ↓
  TortoiseSVN → Merge                     git merge feature-x
  (downloads diff from server,                  ↓
   applies to working copy)             resolve conflicts (if any)
        ↓                                       ↓
  resolve conflicts                       git push
        ↓
  SVN Commit (publishes merge)
```

> **SVN merge quirk:** if you forget to merge or merge the wrong revision range, `svn:mergeinfo` can get out of sync, causing duplicate changes or missed merges. Git tracks merges through commit graph ancestry — it's automatic and exact.

---

## 6. History and Revisions

### SVN revision numbers

SVN uses **sequential global revision numbers**. Every commit to the repo — across all branches and directories — increments one shared counter.

```
r1001  Add login page         (trunk)
r1002  Fix typo               (trunk)
r1003  Create branch feature-x (branches/feature-x)
r1004  WIP on feature-x       (branches/feature-x)
r1005  Fix header bug         (trunk)
```

Revision numbers are meaningful globally: "what was in trunk at r1002" is unambiguous.

### Git commit hashes

Git uses **content-addressed SHA-1 hashes** (e.g. `a3f9c12b`). Each hash is derived from the commit's content, author, timestamp, and parent hash — not a counter. Two different repos can have commits with the same hash only if they contain identical content.

| | SVN | Git |
|---|---|---|
| Identifier | `r1042` (integer) | `a3f9c12` (hash) |
| Sequential? | Yes — global counter | No — content-derived |
| Same number on two machines? | Yes — shared counter | Hashes are globally unique |
| Reference "3 revisions ago" | `r1039` (math) | `HEAD~3` (relative) |
| Reference a range | `r1000:r1005` | `HEAD~5..HEAD` |

### Viewing history in TortoiseSVN

| Goal | TortoiseSVN | Git equivalent |
|---|---|---|
| Full log | Right-click → **Show Log** | `git log --oneline --graph` |
| Log for one file | Right-click file → **Show Log** | `git log --follow <file>` |
| Compare two revisions | Show Log → select two revisions → Compare Revisions | `git diff <hash1>..<hash2>` |
| Who changed a line | Right-click → **Blame** | `git blame <file>` |
| Find when a line appeared | Blame → hover shows revision + author | `git log -S "text" <file>` |

---

## 7. Conflicts

Conflicts happen the same way in both systems — two people edited the same lines. The resolution workflow is similar but the timing differs.

### When conflicts occur

| Scenario | SVN | Git |
|---|---|---|
| Two people edit same file | On **SVN Update** — conflict appears in your working copy | On `git merge` or `git pull` |
| Conflict markers | Same `<<<<<<<` / `=======` / `>>>>>>>` format | Same format |

### Resolving in TortoiseSVN

1. After an **SVN Update** with conflicts, conflicted files show a red exclamation icon
2. Right-click the conflicted file → **TortoiseSVN → Edit Conflicts** → opens TortoiseMerge (3-panel diff)
3. In TortoiseMerge: pick "theirs", "mine", or edit manually → save
4. Right-click → **TortoiseSVN → Resolved** (marks the file as resolved)
5. **SVN Commit** the resolved file

| Step | TortoiseSVN | Git equivalent |
|---|---|---|
| Trigger conflict | SVN Update with conflicting changes | `git merge` / `git pull` |
| Open merge tool | Right-click → Edit Conflicts | `git mergetool` or open in editor |
| Mark as resolved | Right-click → Resolved | `git add <file>` |
| Complete the merge | SVN Commit | `git merge --continue` or `git commit` |
| Abort and go back | TortoiseSVN → Revert (on conflicted files) | `git merge --abort` |

---

## 8. Locking — SVN-Only Feature

SVN supports **exclusive file locks**. When you lock a file, nobody else can commit changes to it until you release the lock. Git has no equivalent (Git assumes non-exclusive collaboration).

Useful for **binary files** (images, PSD, Office docs) where merging is impossible.

| Action | TortoiseSVN |
|---|---|
| Lock a file | Right-click → **TortoiseSVN → Get Lock** |
| See who holds a lock | Right-click → **Check for Modifications** — shows lock owner |
| Release your lock | Right-click → **TortoiseSVN → Release Lock** |
| Steal someone else's lock | Get Lock → check "Steal the lock" (use carefully) |

> **In Git:** the closest pattern is communicating via issues/PRs ("I'm working on this file"). Git-LFS has a file-locking extension for binary assets, but it's not built into vanilla Git.

---

## 9. Ignoring Files

| | SVN | Git |
|---|---|---|
| Ignore mechanism | `svn:ignore` property set on a directory | `.gitignore` file in the directory |
| Where it lives | Stored as a directory property on the server | A plain text file committed to the repo |
| Set via TortoiseSVN | Right-click file/folder → **TortoiseSVN → Add to ignore list** | Edit `.gitignore` manually |
| Global ignores | `%APPDATA%\Subversion\config` — `global-ignores` key | `~/.gitignore_global` + `git config --global core.excludesFile` |

> **Key difference:** `.gitignore` is a normal file you commit, so all team members automatically share the same ignore rules. SVN's `svn:ignore` is a directory property — if someone forgets to commit it, others don't get it.

---

## 10. SVN Externals vs Git Submodules

Both allow embedding another repository (or path) inside your working copy.

| | SVN Externals | Git Submodules |
|---|---|---|
| Definition | `svn:externals` property on a directory | `.gitmodules` file + submodule ref |
| Can point to a specific revision | Yes | Yes (pinned to a commit hash) |
| Auto-updated on checkout/update | Yes — externals are fetched automatically | No — must `git submodule update --init` |
| Can point to a subdirectory of another repo | Yes | No — must clone the whole repo |
| TortoiseSVN support | Shown in working copy like normal folders | TortoiseGit has submodule support |

---

## 11. Key Gotchas — Coming from Git to SVN

These are the things that will surprise you most:

### 1. Commit = Publish (no local commits)
In Git you commit locally and push when ready. In SVN, **Commit** immediately goes to the server. There is no staging area and no local-only commits. If you want to save a WIP state, your only options are:
- Don't commit yet (keep editing)
- Use a branch (create one first)
- Use a patch (TortoiseSVN → Create Patch — saves a `.patch` file locally)

### 2. You update before you commit, not after
In Git: edit → commit → pull → push (deal with conflicts on push).
In SVN: **update first**, resolve conflicts, then commit. If someone committed while you were editing, SVN Update will try to merge their changes into your working copy before you can commit.

```
SVN workflow (correct order):
  edit files
      ↓
  SVN Update        ← get latest, resolve conflicts HERE
      ↓
  SVN Commit        ← now you can publish cleanly
```

### 3. Revision numbers are repo-wide, not branch-scoped
`r1050` might be a commit on `branches/feature-x` — it doesn't mean `trunk` changed at r1050. Revision numbers don't tell you which branch was touched.

### 4. Branching is slow and directory-based
Creating a branch in SVN copies a directory on the server (using a cheap server-side copy, but still a network operation). It shows up in the repo browser as a real folder. Deleting a branch means deleting that folder.

### 5. You can checkout a subdirectory
SVN allows checking out just `trunk/src/app/` without getting the whole repo. In Git you always clone the entire repository (sparse checkout exists but is complex and rarely used).

### 6. Tags are not enforced
A SVN tag is a directory copy under `tags/`. Nothing stops anyone from committing to it — the "don't touch tags" rule is purely a team convention. Git tags can be signed and are not directories.

### 7. No `git stash` equivalent
SVN has no built-in stash. Options when you need to "save WIP and switch context":
- Create a patch file (TortoiseSVN → Create Patch), revert, then apply the patch later
- Commit to a personal branch
- Keep a separate working copy for the other task

### 8. `svn:ignore` must be committed
If you add an ignore pattern via TortoiseSVN, it modifies the `svn:ignore` property. You must then **SVN Commit** that property change or teammates won't see it.

---

## 12. Quick Comparison Reference

| Goal | TortoiseSVN | Git |
|---|---|---|
| Get a repo for the first time | SVN Checkout | `git clone` |
| Get latest changes | SVN Update | `git pull` |
| See local changes | Check for Modifications | `git status` / `git diff` |
| Publish changes | SVN Commit | `git add` + `git commit` + `git push` |
| Undo local edits | Revert | `git restore` |
| View history | Show Log | `git log` |
| Compare versions | Diff | `git diff` / `git show` |
| Create a branch | Branch/Tag → under `branches/` | `git switch -c <name>` |
| Switch branches | Switch → enter branch URL | `git switch <name>` |
| Merge a branch | Merge (revision range) | `git merge <branch>` |
| Resolve conflicts | Edit Conflicts → Resolved | fix file → `git add` |
| Lock a file | Get Lock | (no equivalent) |
| Ignore a file | Add to ignore list | edit `.gitignore` |
| Save WIP locally | Create Patch | `git stash` |
| See who wrote a line | Blame | `git blame` |
| Browse repo structure | Repo-Browser | `git log --graph` / GitHub UI |

---

*SVN 1.8+ assumed. TortoiseSVN 1.14+ on Windows.*
*Git comparisons reference Git 2.23+ with `git switch` / `git restore` syntax — see `git-guide.md` for the full Git reference.*
