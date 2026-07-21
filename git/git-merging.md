# Git Merge Strategy — git-training repo

## Branch Overview

Three branches all diverge from commit `75e3b27` (first code files):

| Branch | Commits | Files touched |
|--------|---------|---------------|
| `master` | `292bcd9` main addidtion v2, `41879bb` misc2 on master | `main.cpp`, `misc2.txt` |
| `feat1` | `87ea9a8` feat 1, `ceb3332` misc.txt | `main.cpp`, `misc.txt` |
| `feat2` | `3733fb8` feat 2 | `main.cpp` |

---

## Current State (diagram)

```
5cf42dc ── 75e3b27 ──────────── 292bcd9 ── 41879bb   (master)
                  \
                   ├── 87ea9a8 ── ceb3332              (feat1)
                   \
                    └── 3733fb8                        (feat2)
```

---

## Conflict Analysis

All three branches touch `main.cpp`:

| Branch | What it did |
|--------|-------------|
| `master` | Renames `first` → `f`, adds "master add" block |
| `feat1` | Same rename `first` → `f`, adds "feat1" block |
| `feat2` | Keeps `first`, adds new `f2` variable and block |

`misc.txt` and `misc2.txt` are new files with no conflicts.

---

## Recommended Strategy: Rebase + `--no-ff` merge

**Order:** `feat2` first, then `feat1`.

**Rationale:**
- `feat2` is the simpler conflict (no rename, just adds code) — resolve it first
- `feat1` shares the same rename as `master`, so after rebasing, the rename may auto-resolve and only the block ordering needs manual attention
- `--no-ff` preserves the fact these were feature branches in the history
- Rebase produces a clean linear history that is easy to read and `git bisect`

### Commands

```bash
# Step 1 — integrate feat2
git checkout feat2
git rebase master          # resolve main.cpp: keep `f` rename + add feat2 block
git checkout master
git merge --no-ff feat2

# Step 2 — integrate feat1
git checkout feat1
git rebase master          # resolve main.cpp: feat1 block ordering
git checkout master
git merge --no-ff feat1
```

### After (diagram)

```
5cf42dc ── 75e3b27 ── 292bcd9 ── 41879bb ── 3733fb8' ── M2 ── 87ea9a8' ── ceb3332' ── M1
                                             (feat2       ↑     (feat1                   ↑
                                             rebased) merge2    rebased)             merge1
```

> Primed commits (`'`) are rebased versions — same changes, new position on the timeline.

---

## Why Not Plain Merge?

```
MESSY (plain merges)          CLEAN (rebase + --no-ff)

master ──●──────────●         master ──●──●──●'──M──●'──●'──M
         |\        /|
         | ●──────● |         Linear. Bisectable. No crossing lines.
         |  feat2   |
         ●──────────●
            feat1
```

---

## Analysis Commands (how to reach this decision)

### 1. See the branch shape
```bash
git log --all --oneline --graph --decorate
```

### 2. What commits are in each branch but not master?
```bash
git log master..feat1 --oneline
git log master..feat2 --oneline
```

### 3. Which files does each branch touch?
```bash
git diff --stat master...feat1
git diff --stat master...feat2
```
> `...` (three dots) compares from the common ancestor — essential for branch analysis.

### 4. See the actual content differences
```bash
git diff master...feat1
git diff master...feat2
```
Use this to spot overlapping edits on the same lines.

### 5. Dry-run a merge to detect conflicts
```bash
git merge --no-commit --no-ff feat1
git merge --abort            # always abort after inspection
```

### 6. Find the common ancestor
```bash
git merge-base master feat1
git merge-base master feat2
```

---

## Decision Checklist

| What you observe | Decision |
|-----------------|----------|
| No overlapping files | Plain `merge --no-ff`, no conflicts expected |
| Same file, different sections | Likely auto-resolvable — `rebase` for clean history |
| Same file, same lines | Manual conflict — `rebase` to resolve once per branch |
| One branch is strictly behind master | Just `merge --no-ff`, no rebase needed |
