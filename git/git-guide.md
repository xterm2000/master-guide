# Git guide  — The Sophisticated Edition

> Plain English explanations + the commands you actually need.

---

## 1. The Basics (Done Right)

```bash
git init                        # Start a new repo in current directory
git clone <url>                 # Copy a remote repo locally
git clone <url> --depth 1       # Shallow clone — latest snapshot only (fast)

git status                      # What's changed / staged / untracked
git diff                        # Unstaged changes (what you haven't git-added yet)
git diff --staged               # Changes that ARE staged (ready to commit)

git add <file>                  # Stage one file
git add .                       # Stage everything in current directory
git add -p                      # Stage in patches — choose hunks interactively ← most useful
git add -i                      # Full interactive staging menu (TUI)

# git add -i opens a numbered menu:
#   1: status   2: update   3: revert   4: add untracked
#   5: patch    6: diff     7: quit     8: help
# Type the number to enter that sub-mode. Option 5 (patch) is the same as git add -p.
# Useful when you want to stage/unstage multiple files in one session.

git mv old-name new-name        # Rename/move a file — stages the change in one step
git rm file                     # Delete a tracked file from disk AND stage the deletion
git rm --cached file            # Untrack a file WITHOUT deleting it from disk (see below)

git commit -m "message"         # Commit with inline message
git commit --amend              # Edit the LAST commit (message or files) — before pushing only!
git commit --amend --no-edit    # Amend last commit without changing the message
git commit --amend -m "new msg" # Replace the commit message in one shot

git log --oneline --graph --all # Visual branch history — use this often
git log -n 10                   # Last 10 commits only
```

### `mv`/`rm` vs `git mv`/`git rm` — why bother with the git versions

Plain `mv`/`rm` work fine on disk, but leave git's index out of sync — a moved file shows up as one deletion + one untracked file until you `git add` both yourself; a deleted file shows as "missing" until you stage that too. `git mv`/`git rm` do the filesystem operation **and** stage it in one step, so `git status` immediately reflects what you intended. `git rm` also refuses to delete a file with uncommitted changes unless forced — a small safety net plain `rm` doesn't give you.

| Command | File on disk | Git index |
|---|---|---|
| `rm file` | deleted | still shows as tracked/"deleted" until staged |
| `git rm file` | deleted | staged as a deletion |
| `git rm --cached file` | **untouched** | staged as a deletion (git stops tracking it) |

`--cached` is the fix for "I already committed something that shouldn't be tracked" (a `.env` file, `node_modules/`, build output) — it retroactively untracks the file without touching your local copy:

```bash
git rm --cached .env
echo ".env" >> .gitignore
git commit -m "Stop tracking .env"
```
Adding to `.gitignore` alone only prevents git from tracking *new* files — it does nothing for a file already committed. `--cached` is the retroactive half of that fix.

---

## 2. Rewriting History

> These commands change commits that already exist — they rewrite the past. Safe on local-only work; dangerous once pushed to a shared branch.

### At a glance

| Tool | What it does | Scope | Safe after push? |
|---|---|---|---|
| `commit --amend` | Replace the last commit | 1 commit | No |
| `rebase -i` | Reorder, squash, rename, drop N commits | N commits | No |
| `reset --soft` | Move HEAD back, keep changes staged | N commits | No |
| `reset --mixed` | Move HEAD back, unstage changes | N commits | No |
| `reset --hard` | Move HEAD back, discard all changes | N commits | **Never** |
| `filter-repo` | Scrub a file/secret from entire history | Every commit ever | Coordinate with team |

> **The rule:** a commit hash that has been pushed and pulled by others is off-limits for rewriting. Changing it will diverge their history from yours. For safe undo of pushed commits use `git revert` instead — see [[git-guide#12. Undoing Things]].

---

### `commit --amend` — fix the last commit

`--amend` does **not** edit the commit in place. It replaces the last commit with a brand new one (new hash) and orphans the old one.

```
Before:
  ... → D → E        ← HEAD  (typo in message, or a file was forgotten)

After --amend:
  ... → D → E'       ← HEAD  (new hash, same parent D)
              E      ← orphaned, unreachable, garbage collected eventually
```

**What you can change:**
- The commit message
- The files in the commit (stage extra changes first)
- The author (`--author="Name <email>"`)
- Any combination of the above at once

```bash
git commit --amend -m "Correct message"                      # Fix a typo in the message
git add forgotten.txt && git commit --amend --no-edit        # Add a missing file, keep message
git commit --amend --author="Mitya <m@x.com>" --no-edit     # Fix wrong author
git add fix.py && git commit --amend -m "Add X with error handling"  # Files + new message
```

**If you already pushed and must amend anyway** (e.g. accidental secret commit):
```bash
git push --force-with-lease   # Safer than --force — fails if someone else pushed meanwhile
```
Then notify your team — they'll need to reset their local branch.

---

### `rebase -i` — rewrite any N commits

The Swiss army knife of history editing. Opens an editor listing N commits; you decide what to do with each line.

```bash
git rebase -i HEAD~4      # Edit the last 4 commits
git rebase -i <hash>      # Edit everything after a specific commit
```

| Editor command | Effect |
|---|---|
| `pick` | Keep as-is |
| `reword` | Keep, edit the message |
| `edit` | Keep, pause so you can amend files |
| `squash` | Merge into the commit above (keep message) |
| `fixup` | Merge into the commit above (drop message) |
| `drop` | Delete the commit entirely |
| `exec` | Run a shell command after this line |

→ Full squashing walkthrough with ASCII examples: [[git-guide#7. Squashing Commits]]
→ Full rebase reference (standard rebase, `--onto`, golden rules): [[git-guide#9. Rebasing]]

---

### `reset` — uncommit and move HEAD

```bash
git reset --soft HEAD~2    # Undo last 2 commits — changes stay staged (ready to recommit)
git reset --mixed HEAD~2   # Undo last 2 commits — changes go back to unstaged (default)
git reset --hard HEAD~2    # Undo last 2 commits — changes DISCARDED, cannot be recovered
```

```
Before:
  ... → D → E → F    ← HEAD

After  git reset --soft HEAD~2:
  ... → D             ← HEAD
        E+F changes   ← still staged

After  git reset --hard HEAD~2:
  ... → D             ← HEAD
        E and F       ← gone (use reflog within 90 days to recover)
```

→ Full reset vs revert comparison and recovery patterns: [[git-guide#12. Undoing Things]]

---

### `filter-repo` — rewrite the entire history

Use when a password, key, or large binary was committed and needs to be **erased from every commit ever**. This rewrites every hash in the repo.

> `git filter-repo` is not bundled with Git — install it first: `pip install git-filter-repo`

```bash
# Remove one file from all history:
git filter-repo --path secrets.env --invert-paths

# Remove a whole folder from all history:
git filter-repo --path config/private/ --invert-paths

# Rewrite an author email across all commits:
git filter-repo --email-callback 'return email.replace(b"old@corp.com", b"new@corp.com")'
```

After running: every commit hash changes. **Coordinate with the entire team first** — everyone must re-clone or hard-reset. Also rotate any exposed secrets immediately; they remaster in the remote's reflog until it expires or is pruned.

> The older `git filter-branch` is deprecated — use `git filter-repo` instead.

---

### `reflog` — the safety net under all of the above

Whatever you rewrote, reflog remembers where HEAD has been for the past 90 days. Nothing above is truly permanent as long as you act quickly.

```bash
git reflog                       # Full HEAD movement history
git switch -c recovery abc1234   # Branch off any reflog entry to get it back
```

→ [[git-guide#12. Undoing Things]]

---

## 3. Remote Info — What's Out There

> A **remote** is just a bookmark to another copy of the repo (usually on GitHub/GitLab/Bitbucket).

```bash
git remote -v                   # List remotes with their URLs (fetch + push)
git remote show origin          # Detailed info: remote branches, tracking status, stale refs

git remote add <name> <url>     # Add a new remote (e.g. git remote add upstream <url>)
git remote rename origin old    # Rename a remote
git remote remove <name>        # Delete a remote bookmark (doesn't delete anything on the server)

git fetch                       # Download changes from remote — does NOT touch your working files
git fetch --all                 # Fetch from ALL remotes
git fetch --prune               # Fetch + delete local refs to remote branches that no longer exist

git pull                        # Fetch + merge remote into current branch (shorthand)
git pull origin <branch>        # Pull a specific remote branch into current
git pull --rebase               # Fetch + rebase instead of merge — cleaner history (see §8)
git pull --rebase origin master   # Pull and rebase onto origin/master explicitly
git pull --ff-only              # Only pull if it's a fast-forward — fails safely if diverged
```

### `fetch` vs `pull` — what actually happens

| | `git fetch` | `git pull` |
|---|---|---|
| Downloads remote commits | Yes | Yes |
| Updates your working files | **No** | **Yes** |
| Updates your current branch | **No** | **Yes** |
| Safe to run anytime | Yes | Careful |
| Lets you inspect before merging | Yes | No |

**`git fetch` is always safe.** It updates your remote-tracking refs (`origin/master`, etc.) but leaves your actual branch and working directory completely untouched. You can then run `git log origin/master` or `git diff origin/master` to see what arrived before deciding what to do.

**`git pull` is `fetch` + `merge` in one step.** Convenient, but it immediately changes your branch. By default it creates a merge commit when histories have diverged — that merge commit adds noise to the log on a feature branch.

**The recommended workflow:**
```bash
git fetch                       # 1. Download — nothing changes locally
git log origin/master             # 2. Inspect what arrived
git diff HEAD..origin/master      # 3. See exactly what's new
git merge origin/master           # 4. Merge when you're ready
# — OR —
git pull --rebase origin master   # Fetch + rebase in one shot (preferred over plain pull)
```

**When plain `git pull` is fine:** on `master`/`master` where you don't have local-only commits and just want to fast-forward to the latest.

---

## 4. Branches — Local & Remote

```bash
# ── Local branches ──────────────────────────────────────────
git branch                      # List local branches (* = current)
git branch <name>               # Create a new branch (stays on current branch)
git switch <name>               # Switch to a branch (modern syntax)
git switch -c <name>            # Create AND switch in one shot
git branch -d <name>            # Delete a branch (safe — refuses if unmerged)
git branch -D <name>            # Force delete (even if unmerged)
git branch -m <old> <new>       # Rename a branch

# ── Remote branches ─────────────────────────────────────────
git branch -r                   # List remote-tracking branches
git branch -a                   # List ALL branches (local + remote)

git switch -c <name> origin/<name>  # Create a local branch that tracks a remote one

git push origin <branch>            # Push local branch to remote
git push -u origin <branch>         # Push AND set upstream (so future git push works alone)
git push origin --delete <branch>   # Delete a branch on the remote

# ── Tracking info ────────────────────────────────────────────
git branch -vv                  # Show local branches with their upstream tracking + ahead/behind count
```

**Example output of `git branch -vv`:**
```
  dev       a3f9c12 [origin/dev: behind 3] Fix config bug
* feature   8b21d4a [origin/feature: ahead 2] Add auth flow
  master      4c0e871 [origin/master] Merge PR #42
```
→ `feature` has 2 commits the remote doesn't have yet. `dev` is 3 commits behind remote.

---

## 5. Branch States — Fast-Forward, Diverged & Orphaned

### Fast-forward

The simplest possible merge. Your branch is **strictly ahead** of the target — the target hasn't moved since you branched off, so Git just slides the pointer forward. No merge commit is created.

```
Before:
  master:    A → B → C
                   ↑
  feature:         └→ D → E → F

git switch master
git merge feature
```
```
After (fast-forward):
  master:    A → B → C → D → E → F    ← pointer just moved, no new commit
```

History is perfectly linear. This is the "clean" case you always want for feature branches.

```bash
git merge --ff-only feature     # Succeed only if fast-forward is possible — fail otherwise (safe)
git merge --no-ff feature       # Force a merge commit even when FF would work
                                # (useful to preserve branch context in history)
git pull --ff-only              # Same idea for pull: refuse if not a clean fast-forward
```

---

### Diverged branches

Two branches have **diverged** when both have commits the other doesn't — they've each moved forward from a common ancestor independently. Git cannot fast-forward and won't do so silently.

```
Common ancestor: C

  master:    A → B → C → D → E      ← 2 commits added to master
  feature: A → B → C → X → Y      ← 2 commits added to feature
                   ↑
             (last shared point)
```

**How to detect divergence:**
```bash
git status                                          # "Your branch and 'origin/master' have diverged"
git branch -vv                                      # Shows [origin/master: ahead 2, behind 3]
git log --oneline --graph --all                     # Visual confirmation — branches split in the graph
git fetch && git log HEAD..origin/master --oneline    # Commits on remote you don't have yet
git fetch && git log origin/master..HEAD --oneline    # Your commits the remote doesn't have yet
```

You have two ways to resolve divergence:

#### Option 1 — Merge (preserves full history, adds a merge commit)

```bash
git switch master
git merge feature
```
```
Result:
  master:    A → B → C → D → E → M
                   ↑           ↑
  feature:         └→ X → Y ───┘
```
`M` is the merge commit — it has two parents and explicitly records when the branches joined. Good for long-lived branches or when you want a clear integration point in the log.

#### Option 2 — Rebase (rewrites history, keeps it linear)

```bash
git switch feature
git rebase master           # Replay X and Y on top of E
git switch master
git merge feature         # Now it's a fast-forward — no merge commit
```
```
Result:
  master:    A → B → C → D → E → X' → Y'   (linear, no merge commit)
```
X and Y are **replayed as new commits** (X', Y') with new hashes. History looks as if feature was always developed after D and E. Cleaner log, but rewrites history — safe only on branches you haven't shared yet.

> **Golden rule:** never rebase commits already pushed to a shared remote branch. Others who pulled those commits will have a diverged history. See §9 for the full rebase reference (interactive rebase, `--onto`, commands table).

---

### Orphaned branch

An orphaned branch has **no shared history with any other branch**. It starts at a completely blank root commit — a separate tree inside the same repository.

```
master:     A → B → C → D       ← normal history
gh-pages: P → Q → R            ← no connection whatsoever
```

```bash
git switch --orphan gh-pages    # Create an orphaned branch (working tree preserved)
git rm -rf .                    # Wipe the working tree — you're starting from nothing
# ... add your static site / built files ...
git add .
git commit -m "Initial gh-pages"
git push origin gh-pages
```

**Common uses:**
- `gh-pages` branch — GitHub Pages static site lives separately from source code
- Storing compiled artifacts or binaries that shouldn't pollute the code history
- Starting a clean-slate history in an existing repo without deleting it

> Don't confuse with an **abandoned branch** — a branch with stale commits but a normal history is just unused, not orphaned.

---

### Recommended workflows by scenario

#### Scenario A — Solo dev: feature branch

```bash
git switch -c feature/my-thing          # Branch from master
# ... work, commit freely ...
git fetch origin                        # See if master moved while you worked
git rebase origin/master                  # Replay your commits on top of latest master
# resolve any conflicts, then:
git switch master
git merge feature/my-thing             # Fast-forward (clean, no merge commit)
git push origin master
git branch -d feature/my-thing         # Clean up local branch
git push origin --delete feature/my-thing  # Clean up remote branch
```

#### Scenario B — Team: shared feature branch (others push to it too)

```bash
git fetch origin
git pull --rebase origin feature/team-thing    # Rebase YOUR commits on top of theirs
# resolve any conflicts per commit, then:
git push origin feature/team-thing
```
> Never plain `git pull` here — it creates a merge commit between teammates' work that clutters the log. Use `--rebase`.

#### Scenario C — Fork sync with upstream (open source)

```bash
# One-time setup:
git remote add upstream https://github.com/original/repo.git

# Regular sync:
git fetch upstream                              # Get upstream's changes (doesn't touch your files)
git switch master
git rebase upstream/master                        # Move your master on top of upstream's tip
git push origin master --force-with-lease        # Update your fork (safe force: fails if someone else pushed)
```

#### Scenario D — Hotfix while mid-feature

```bash
git stash                               # Save WIP without a commit
git switch master
git pull --ff-only                      # Confirm master is current (fail loudly if not)
git switch -c hotfix/critical-fix       # Branch from master tip
# ... fix, commit ...
git switch master
git merge hotfix/critical-fix           # Fast-forward
git push origin master
git tag v1.2.1                          # Optional: tag the release
git branch -d hotfix/critical-fix
git switch feature/my-thing
git stash pop                           # Restore your WIP
```

---

## 6. Commits — Inspect & Navigate

```bash
git show <hash>                 # Full diff + metadata for one commit
git show HEAD                   # Show the latest commit
git show HEAD~2                 # Show 2 commits before HEAD

git log --oneline               # Compact one-line history
git log --oneline --graph --all # Visual ASCII graph of all branches
git log --author="Mitya"        # Filter by author
git log --since="2 weeks ago"   # Filter by time
git log --follow <file>         # History of a specific file (even across renames)

git diff master..feature          # All changes between two branches
git diff HEAD~3..HEAD           # Last 3 commits worth of changes

git blame <file>                # Who wrote each line + which commit
git shortlog -sn                # Commit count per author (leaderboard)
```

---

## 7. Squashing Commits

### What is squashing?

You made 5 messy "WIP" commits while working on a feature. Squashing **combines them into one clean commit** before merging. Your history stays readable.

### Visual Example

**Before squashing:**
```
* f9a1c3e  fix typo again                ← HEAD
* 8b2d441  fix typo
* 3e7f902  WIP: still debugging
* a1c4d88  WIP: started auth feature
* 7d0f123  master: previous stable commit   ← you want to squash onto this
```

**Command:**
```bash
git rebase -i HEAD~4
```
> `-i` = interactive, `HEAD~4` = "go back 4 commits"

**The editor opens with:**
```
pick a1c4d88 WIP: started auth feature
pick 3e7f902 WIP: still debugging
pick 8b2d441 fix typo
pick f9a1c3e fix typo again
```

**Change to:**
```
pick a1c4d88 WIP: started auth feature   ← keep this one as the base
squash 3e7f902 WIP: still debugging      ← fold into above
squash 8b2d441 fix typo                  ← fold into above
squash f9a1c3e fix typo again            ← fold into above
```

Save and close. Git asks you to write a new combined commit message.

**After squashing:**
```
* d3f8a21  Add auth feature              ← HEAD (1 clean commit)
* 7d0f123  master: previous stable commit
```

> **Tip:** Use `fixup` instead of `squash` to merge commits silently (discards their messages).

```bash
git rebase -i HEAD~<N>          # Squash last N commits
git rebase -i <hash>            # Squash everything after a specific commit
```

---

## 8. Remote Got Ahead — Rebase Pull

### The scenario

You've been working on your branch. Meanwhile, teammates pushed 3 new commits to the same remote branch. Now if you try to push, Git refuses.

```
Remote:  A → B → C → D → E     (3 new commits you don't have)
Local:   A → B → C → X → Y     (your 2 new commits)
```

### The wrong way: plain `git pull`

A plain `git pull` does a **merge**, creating an ugly merge commit just to say "I synced." Avoid this on feature branches.

### The right way: `git pull --rebase`

```bash
git pull --rebase origin <branch>
```

**What it does under the hood:**
1. Fetches the remote's new commits (D, E)
2. Temporarily removes YOUR commits (X, Y)
3. Fast-forwards your branch to match the remote (A→B→C→D→E)
4. Replays YOUR commits on top (X', Y')

```
Before:
  Remote: A → B → C → D → E
  Local:  A → B → C → X → Y

After git pull --rebase:
  Local:  A → B → C → D → E → X' → Y'
```

Your work sits cleanly on top. No merge commit. History is linear.

```bash
git pull --rebase                       # Rebase pull from tracked upstream
git pull --rebase origin master           # Explicitly from origin/master

# If conflicts occur during rebase:
git status                              # See which files conflicted
# ... fix conflicts in your editor ...
git add <fixed-file>                    # Mark as resolved
git rebase --continue                   # Keep going
git rebase --abort                      # Bail out entirely, restore original state

# Set rebase as the default pull behavior (recommended):
git config --global pull.rebase true
```

---

## 9. Rebasing

### What is rebasing?

Rebasing **moves a branch** so it starts from a different point. Think of it as replanting a tree — you dig it up and replant it further along the trunk.

### Standard rebase: get master's latest changes into your feature branch

```bash
git switch feature
git rebase master
```

**Before:**
```
master:    A → B → C → D
                 ↑
feature:         └→ X → Y
```

**After `git rebase master`:**
```
master:    A → B → C → D
                         ↑
feature:                 └→ X' → Y'
```

Feature branch now starts from D (the tip of master) instead of C. X and Y are replayed as new commits X' and Y'.

### Rebase onto a specific commit

```bash
git rebase --onto <newbase> <upstream> <branch>
# Example: move feature so it starts from master's tip, excluding 'dev' commits
git rebase --onto master dev feature
```

### Interactive rebase (editing history)

```bash
git rebase -i HEAD~5            # Interactively edit last 5 commits
```

In the editor, commands per line:
| Command | What it does |
|---------|-------------|
| `pick`  | Keep commit as-is |
| `reword`| Keep commit, edit its message |
| `edit`  | Keep commit, pause to amend files |
| `squash`| Merge into previous commit (keeps message) |
| `fixup` | Merge into previous commit (drops message) |
| `drop`  | Delete the commit entirely |
| `exec`  | Run a shell command after this commit |

### Golden Rule of Rebasing

> **Never rebase commits that have already been pushed to a shared remote branch.**
>
> Rebasing rewrites commit hashes. If others pulled your old commits, their history will diverge from yours and cause chaos. Rebase only on local-only or personal feature branches.

---

## 10. Cherry-Picking

### What is cherry-picking?

You want ONE specific commit from another branch — not the whole branch. Cherry-pick copies that commit and applies it to your current branch.

```bash
git cherry-pick <hash>              # Apply one commit to current branch
git cherry-pick <hash1> <hash2>     # Apply multiple specific commits
git cherry-pick <hash1>..<hash2>    # Apply a range (exclusive start)
git cherry-pick <hash1>^..<hash2>   # Apply a range (inclusive start)

git cherry-pick -n <hash>           # Apply changes but DON'T commit yet (--no-commit)
git cherry-pick --abort             # Undo a cherry-pick in progress
git cherry-pick --continue          # Resume after resolving conflicts
```

### Example

```
master:    A → B → C → D → E
feature:              └→ F → G → H
```

You're on `master` and need the fix from commit `G` (bug fix buried in the feature branch):

```bash
git switch master
git cherry-pick G
```

```
master:    A → B → C → D → E → G'
feature:              └→ F → G → H
```

`G'` is a copy of G — same changes, new hash, applied on top of master.

### When to cherry-pick

- Backporting a bug fix to an older release branch
- Pulling one useful commit from a messy branch without taking everything
- Hotfixes: the fix was committed on the wrong branch

---

## 11. Stashing

> You're mid-work and need to switch branches without committing garbage.

```bash
git stash                           # Stash all uncommitted changes (tracked files)
git stash -u                        # Also stash untracked files
git stash push -m "my WIP message"  # Stash with a description

git stash list                      # See all stashes
git stash show -p stash@{0}         # See diff of most recent stash

git stash pop                       # Apply most recent stash + delete it from stash list
git stash apply stash@{2}           # Apply a specific stash (keep it in the list)
git stash drop stash@{0}            # Delete one stash
git stash clear                     # Delete ALL stashes

git stash branch <name>             # Create a new branch from a stash (very useful)
```

---

## 12. Undoing Things

```bash
# ── Undo staged changes (unstage, keep changes in working dir) ──
git restore --staged <file>         # Unstage a file
git restore --staged .              # Unstage everything

# ── Discard working directory changes (IRREVERSIBLE) ──────────
git restore <file>                  # Throw away unsaved changes in a file
git restore .                       # Throw away ALL unsaved changes

# ── Undo commits ──────────────────────────────────────────────
git revert <hash>                   # Create a NEW commit that undoes a commit (safe, shareable)
git reset --soft HEAD~1             # Undo last commit, keep changes staged
git reset --mixed HEAD~1            # Undo last commit, keep changes unstaged (default)
git reset --hard HEAD~1             # Undo last commit, DISCARD all changes (dangerous)

# ── Find a lost commit / go back in time ──────────────────────
git reflog                          # Full history of where HEAD has been — your safety net
git switch -c recovery <hash>       # Branch off any commit hash from reflog
```

**`reset` vs `revert`:**
- `git revert` is safe to push — it adds a new commit, doesn't rewrite history
- `git reset --hard` rewrites history — never use it on commits already pushed to shared branches

**Sync to remote — discard local changes:**
```bash
git fetch origin
git reset --hard origin/master      # Throw away ALL local changes and match remote exactly
```
> Destructive — staged, unstaged, and unpushed commits are gone. Use when you want a clean slate that matches the remote.

**Sync to remote — keep local changes:**
```bash
git stash                           # Temporarily shelve your local changes
git fetch origin
git reset --hard origin/master      # Fast-forward to remote
git stash pop                       # Re-apply your stashed changes on top
```
> If `stash pop` gets a conflict, resolve it then `git stash drop` to clear the stash entry.

---

## 13. Aliases Worth Keeping

Add these to your `~/.gitconfig` under `[alias]`:

```ini
[alias]
  lg    = log --oneline --graph --all --decorate
  st    = status -sb
  co    = switch
  br    = branch -vv
  undo  = reset --soft HEAD~1
  wip   = commit -am "WIP"
  pop   = stash pop
  oops  = commit --amend --no-edit
  gone  = !git fetch -p && git branch -vv | grep ': gone]' | awk '{print $1}' | xargs git branch -d
```

**Usage:**
```bash
git lg            # Beautiful branch graph
git st            # Compact status
git undo          # Undo last commit, keep changes
git gone          # Clean up local branches whose remote was deleted
```

---

## 14. `git config` — Identity, Behavior & Preferences

Git has three config scopes. Each overrides the one above it:

| Scope | Flag | File location | Applies to |
|---|---|---|---|
| System | `--system` | `/etc/gitconfig` | All users on the machine |
| Global | `--global` | `~/.gitconfig` | Your user, all repos |
| Local | `--local` | `.git/config` | This repo only |

### Identity — set this first on any new machine

```bash
git config --global user.name  "Mitya"
git config --global user.email "you@example.com"

# Override for a single repo (e.g. work laptop, personal project):
git config --local user.email "work@company.com"
```

### Essential behavior settings

```bash
# Default branch name for git init (modern default is master, not master)
git config --global init.defaultBranch master

# Make git pull rebase by default instead of merge (recommended)
git config --global pull.rebase true

# Push only the current branch by default (safe — avoids accidental multi-branch push)
git config --global push.default current

# Your preferred editor for commit messages, rebase editors, etc.
git config --global core.editor "vim"          # or nano, code --wait, etc.

# Windows: how Git handles line endings (CRLF on checkout, LF on commit)
git config --global core.autocrlf true         # Windows
git config --global core.autocrlf input        # Linux/macOS

# Always show color in output
git config --global color.ui auto
```

### More behavior settings worth knowing

```bash
# Don't error/warn on trailing whitespace or space-before-tab in diffs — flag them instead
git config --global core.whitespace trailing-space,space-before-tab

# Page long output through `less`, without wrapping (-S) and quitting immediately if it fits one screen (-F)
git config --global core.pager "less -FRX"

# When you fetch/pull, delete local remote-tracking branches whose upstream branch was deleted
# (keeps `git branch -a` and `git branch -vv` clean of stale "gone" branches)
git config --global fetch.prune true

# Automatically stash uncommitted changes before a rebase starts, and pop them back after —
# without this, `git pull --rebase` refuses to run at all on a dirty working tree
git config --global rebase.autoStash true

# In diffs, color a moved block of lines differently from a genuinely added/removed one
# ("zebra" alternates two colors per moved block, useful when several blocks moved at once)
git config --global diff.colorMoved zebra

# On merge conflict, show three-way markers (<<<< yours, |||| base, ==== theirs, >>>> )
# instead of git's default two-way (yours vs theirs) — the extra "base" section shows
# what the file looked like before either side changed it, which often makes the actual
# change each side made much easier to see
git config --global merge.conflictstyle diff3

# Rewrite one URL prefix to another transparently — e.g. always use SSH for GitHub even
# when you (or a tool) clone with an https:// URL
git config --global url."git@github.com:".insteadOf "https://github.com/"
```

### Inspecting your config

```bash
git config --list                       # Show all active settings (merged from all scopes)
git config --list --show-origin         # Same, but shows which file each setting comes from
git config --global --edit              # Open ~/.gitconfig directly in your editor
git config user.email                   # Read one specific key
git config --global --unset core.editor # Remove a setting
```

### What `~/.gitconfig` looks like

```ini
[user]
    name  = Mitya
    email = you@example.com

[init]
    defaultBranch = master

[pull]
    rebase = true

[push]
    default = current

[core]
    editor     = vim
    autocrlf   = input

[color]
    ui = auto

[alias]
    lg   = log --oneline --graph --all --decorate
    st   = status -sb
```

---

## 15. Authentication — No More Typing Passwords

### The two authentication methods

| Method | How it works | Best for |
|---|---|---|
| **HTTPS + credential manager** | Git stores a token in your OS keychain | GitHub, Gitea, any HTTPS remote |
| **SSH keys** | Cryptographic key pair, no passwords | GitHub, Gitea, any SSH-capable remote |

---

### Option A — Git Credential Manager (GCM)

GCM is the modern solution. It stores tokens in your **OS keychain** (Windows Credential Manager, macOS Keychain, or libsecret on Linux) — you authenticate once, then it's silent forever.

**Install:**
```bash
# Windows — bundled with Git for Windows (already installed)
# macOS
brew install git-credential-manager
# Linux
# Download from https://github.com/git-ecosystem/git-credential-manager/releases
```

**Configure:**
```bash
git config --global credential.helper manager          # Windows / GCM installed
git config --global credential.helper osxkeychain      # macOS built-in (simpler alternative)
git config --global credential.helper cache            # Linux: in-memory, 15 min TTL
git config --global credential.helper "cache --timeout=3600"  # Linux: 1 hour TTL
```

**First push triggers the login flow:**
```bash
git push origin master
# → browser opens (GitHub/Gitea OAuth) or prompts for token once
# → token saved to keychain — future pushes are silent
```

**For Gitea specifically** (no OAuth browser flow — use a Personal Access Token):
1. Gitea → Settings → Applications → Generate Token (give it `read:repo` + `write:repo`)
2. Clone or push — when prompted for password, paste the token instead of your password
3. GCM saves it; you won't be asked again

```bash
# Override the credential helper for one specific host:
git config --global credential.https://gitea.yourserver.com.helper manager
```

**Check or clear saved credentials:**
```bash
git credential-manager diagnose            # Check GCM status
git credential reject                      # Pipe a credential to invalidate it (forces re-login)

# Windows — view/delete in:  Control Panel → Credential Manager → Windows Credentials
# macOS   — view/delete in:  Keychain Access app
```

---

### Option B — SSH Keys (no tokens, no passwords)

SSH is the cleanest long-term setup: you generate a key pair once, add the public key to GitHub/Gitea, and all future operations are passwordless.

```bash
# 1. Generate a key (Ed25519 is modern and fast)
ssh-keygen -t ed25519 -C "you@example.com"
# Saves to ~/.ssh/id_ed25519 (private) and ~/.ssh/id_ed25519.pub (public)

# 2. Copy the public key
cat ~/.ssh/id_ed25519.pub
# → paste this into GitHub: Settings → SSH Keys → New SSH Key
# → paste this into Gitea:  Settings → SSH / GPG Keys → Add Key

# 3. Test the connection
ssh -T git@github.com        # Should print: "Hi Mitya! You've successfully authenticated"
ssh -T git@gitea.yourserver.com

# 4. Clone using the SSH URL (git@... not https://...)
git clone git@github.com:youruser/yourrepo.git
```

**Switch an existing repo from HTTPS to SSH:**
```bash
git remote set-url origin git@github.com:youruser/yourrepo.git
git remote -v    # Verify
```

**SSH agent — avoid typing your key passphrase repeatedly:**
```bash
eval "$(ssh-agent -s)"         # Start the agent
ssh-add ~/.ssh/id_ed25519      # Load your key (prompted for passphrase once per session)
```

> On macOS/Windows the SSH agent integrates with the OS keychain automatically — you only ever type the passphrase once total.

---

### Which should you use?

| | GCM + HTTPS | SSH |
|---|---|---|
| Setup effort | Low (one browser login) | Medium (key gen + upload) |
| Works with PAT (Gitea/self-hosted) | Yes | No — SSH is separate |
| Works behind strict firewalls | Yes (port 443) | Sometimes blocked (port 22) |
| No browser needed | — | Yes |
| Expires / revocable | Token-based | Until you remove the key |

**Rule of thumb:** use **SSH** for GitHub where you'll work long-term. Use **GCM + PAT** for Gitea or any self-hosted server.

---

## 16. `git checkout` vs `git switch` vs `git restore`

### Why three commands?

`git checkout` is a legacy command that does **three completely unrelated things** depending on what you pass it. Git 2.23 (2019) split it into two focused commands to reduce confusion.

| Old (`git checkout`) | New — what it actually is |
|---|---|
| `git checkout <branch>` | **`git switch <branch>`** — navigate between branches |
| `git checkout -b <branch>` | **`git switch -c <branch>`** — create + switch |
| `git checkout -- <file>` | **`git restore <file>`** — discard file changes |
| `git checkout <hash> -- <file>` | **`git restore --source <hash> <file>`** — restore file from a commit |

The old `git checkout` forms still work — they were not removed. But the new commands are clearer because you can't accidentally discard file changes when you meant to switch branches.

---

### `git switch` — for branches only

```bash
git switch master                     # Switch to an existing branch
git switch -c feature/login         # Create a new branch and switch to it
git switch -c hotfix origin/hotfix  # Create local branch tracking a remote one
git switch -                        # Switch back to the previous branch (like cd -)
git switch --detach <hash>          # Detach HEAD at a specific commit (read-only explore)
```

> `git switch` will **refuse** to switch if you have uncommitted changes that would be overwritten. Stash or commit first.

---

### `git restore` — for files only

```bash
git restore <file>                  # Discard working-directory changes (dangerous — irreversible)
git restore .                       # Discard ALL unstaged changes in the repo

git restore --staged <file>         # Unstage a file (keep changes in working dir)
git restore --staged .              # Unstage everything

git restore --source HEAD~2 <file>  # Pull a file's content from 2 commits ago
git restore --source <hash> <file>  # Pull a file's content from any commit
```

`git restore` **only touches files** — it never changes which branch you're on.

---

### Mental model

```
git switch    →  moves HEAD (changes branch / commit you're on)
git restore   →  moves file content (changes what's in your working tree or index)
git checkout  →  did both, depending on arguments — that's why it was confusing
```

**Recommendation:** use `git switch` and `git restore` for new work. Reserve `git checkout` for old muscle memory or scripts that predate Git 2.23.

---

## 17. Log Recipes — Answering Specific Questions

`git log` is one command with dozens of flags — think of each flag as answering one question. SVN's `log` just dumps a linear list; git's is a query language once you learn the flags below.

### Your four examples, checked

```bash
git log origin/main..main --oneline
```
Correct as written (assuming your remote-tracking branch is actually `origin/main` — this repo uses `master`, so it'd be `origin/master..master`). The `..` range means "commits reachable from the right side, not reachable from the left" — so this shows **commits you have locally that you haven't pushed yet**. Flip the sides (`main..origin/main`) to see commits the remote has that you don't.

```bash
git log --deleted_file.txt
```
This isn't valid syntax — `--deleted_file.txt` looks like a flag (leading `--`), so git tries to parse it as one and fails. Two different things you might actually want:
```bash
git log --all --full-history -- deleted_file.txt   # full commit history of a path, including after it was deleted
git log --diff-filter=D --summary                  # every commit that deleted *some* file (scan the output for the name)
```
The `--` before a path is the same "everything after this is a path, not a flag" marker as `grep -- '--cached'` from the grep guide — same underlying rule, different command.

```bash
git log --date=relative
```
Correct, and genuinely useful — dates print as "3 days ago", "2 weeks ago" instead of a timestamp. Other `--date=` styles: `short` (`2026-07-20`), `iso`, `local` (your timezone instead of the commit's).

```bash
git log --graph --oneline --decorate --stat
```
Correct — a strong "what happened and where" combo: `--graph` draws the branch topology in ASCII, `--decorate` labels commits with branch/tag names, `--stat` appends a per-commit summary of files changed + lines added/removed. This is `lg` from §13 with `--stat` bolted on.

---

### "Who did what" — authorship

```bash
git shortlog -sn                    # commit count per author, sorted, whole current branch
git shortlog -sn --all              # same, across every branch
git log --author="Mitya"            # only commits by one author (substring match)
git log --author="Mitya\|Alex"      # multiple authors (regex OR)
git blame <file>                    # who last touched each *line* of a file — not commits, lines
```
SVN equivalent: closest thing SVN has is `svn blame`/`svn log --search`, but there's no per-author commit tally without scripting — `shortlog -sn` is a genuine git-only convenience.

### "How many" — counting

```bash
git rev-list --count HEAD                 # total commits in this branch's history
git rev-list --count origin/master..master  # how many commits you're ahead of remote
git log --oneline | wc -l                 # same as rev-list --count, less efficient, easy to remember
```

### "What changed" — diff-level detail per commit

```bash
git log --stat            # files touched + lines +/- per commit (readable summary)
git log --shortstat       # just the totals line, no per-file breakdown
git log -p                # full diff for every commit — verbose, use with -n or a path filter
git log -p -- <file>      # full diff, but only for one file's changes across history
git log --numstat         # machine-readable +/- counts per file (good for piping into awk)
```

### File-specific history

```bash
git log --follow -- <file>     # history of a file, tracking through renames (SVN can't do this at all)
git log -- <file>              # history of a path — stops at a rename unless you add --follow
git log --diff-filter=D --summary       # find commits that deleted files
```

### Searching commit content — the pickaxe

```bash
git log --grep="fix login"          # search commit MESSAGES for a string
git log -S"someFunction"            # search for commits where a STRING's occurrence count changed (added or removed)
git log -G"some.*regex"             # like -S but matches a regex against the actual diff content
```
`-S`/`-G` ("pickaxe") answer "which commit introduced or removed this exact code," which is a much sharper question than `--grep` (message text) or a blind `git log -p | grep`.

### Comparing branches

```bash
git log branchA..branchB                    # commits in B not in A
git log --left-right --oneline branchA...branchB   # commits unique to EACH side, marked < or >
git cherry -v master feature                # commits on feature not yet applied to master (survives rebases better than log ranges)
```

### Time-based

```bash
git log --since="2 weeks ago"
git log --until="2026-01-01"
git log --since="9am" --until="5pm" --author="Mitya"   # "what did I do today"
```

### Custom one-line formats (for scripting/aliases)

```bash
git log --pretty=format:"%h %an %ad %s" --date=short
# %h short hash, %an author name, %ad author date, %s subject
```

### Candidates worth turning into aliases later

You mentioned maybe aliasing some of these — good candidates for `~/.gitconfig [alias]` alongside §13's list:
```ini
who     = shortlog -sn
count   = rev-list --count HEAD
mine    = log --author
filelog = log --follow --
find    = log -S
today   = log --since=midnight --oneline --author
```

---

## Quick Reference Card

| Goal | Command |
|------|---------|
| See remote details | `git remote show origin` |
| See branch tracking | `git branch -vv` |
| Download remote changes (inspect first) | `git fetch` |
| Download + apply (fast-forward only, safe) | `git pull --ff-only` |
| Get remote changes, rebase on top | `git pull --rebase` |
| Check if branch has diverged | `git log --oneline --graph --all` |
| See what remote has that you don't | `git fetch && git log HEAD..origin/master --oneline` |
| Merge only if fast-forward possible | `git merge --ff-only <branch>` |
| Create a branch with no shared history | `git switch --orphan <branch>` |
| Squash last N commits | `git rebase -i HEAD~N` |
| Move feature branch to latest master | `git switch feature && git rebase master` |
| Copy one commit to current branch | `git cherry-pick <hash>` |
| Undo last commit (keep changes) | `git reset --soft HEAD~1` |
| Safely undo a pushed commit | `git revert <hash>` |
| Find anything you "lost" | `git reflog` |
| Delete merged remote branches locally | `git fetch --prune` |

---

*Git 2.23+ assumed. See §16 for the full `git checkout` → `git switch` / `git restore` breakdown.*
