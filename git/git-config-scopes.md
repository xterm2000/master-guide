# Git Config Scopes — Global vs Local

Git reads config from three layers, each overriding the last: **system** (rare, machine-wide) → **global** (`~/.gitconfig`, per-user) → **local** (`.git/config`, per-repo). This doc uses `git/.gitconfig` (this repo's reference copy) as the working example and sorts each setting into "belongs in global" or "belongs in local/project."

---

## The three scopes

| Scope | File | Applies to | Set with |
|-------|------|-----------|----------|
| System | `/etc/gitconfig` | Every user on the machine | `git config --system ...` |
| Global | `~/.gitconfig` | Every repo for this user | `git config --global ...` |
| Local | `<repo>/.git/config` | Just this one repo | `git config --local ...` (or plain `git config ...`) |

Precedence: **local wins over global, global wins over system.** A repo-specific `.git/config` entry silently shadows whatever `~/.gitconfig` says for that same key — this is the mechanism, not an edge case, for the local overrides below.

Check where a value is actually coming from:

```bash
git config --list --show-origin        # every effective setting + which file set it
git config --show-origin user.email    # just one key
```

---

## What belongs in `~/.gitconfig` (global) — identity and personal habits

These describe **you**, not any one project. They should be true everywhere you run `git`, regardless of which repo you're in.

| Setting (from `git/.gitconfig`) | What it does | Why global |
|---|---|---|
| `[user] email`, `[user] name` | Identity attached to every commit you author | Same person commits everywhere *(caveat below)* |
| `[core] editor` | Editor opened for commit messages, interactive rebase, etc. | Personal tool preference, not project-dependent |
| `[core] pager` | How long output (log/diff) is paged (`less -FRX`: no wrap, quit-if-fits) | Personal viewing preference |
| `[core] autocrlf` | Line-ending conversion between working tree and repo (`input` = LF on commit, leave as-is on checkout) | Personal OS/line-ending habit |
| `[core] whitespace` | Which whitespace problems (`trailing-space`, `space-before-tab`) `git diff`/`apply` flag | Personal hygiene preference |
| `[init] defaultBranch` | Default branch name (`master`) for repos created with `git init` | Your default for repos *you* create |
| `[pull] rebase` | `git pull` rebases instead of merging | Your preferred workflow, applies to any repo you touch |
| `[fetch] prune` | Deletes local remote-tracking branches whose remote branch is gone | Same — keeps every repo's branch list clean |
| `[rebase] autoStash` | Auto-stashes/pops uncommitted changes around a rebase, so a dirty tree doesn't block `pull --rebase` | Same — a workflow safety net you always want |
| `[push] default` | `git push` with no args pushes only the current branch | Your push habit |
| `[diff] tool`, `[merge] tool` | External tool launched by `git difftool`/`mergetool` (`vimdiff`) | Your preferred external tooling |
| `[diff] colorMoved` | Colors a moved block of lines differently from an add/remove (`zebra` = alternating colors per block) | Cosmetic, personal |
| `[merge] conflictstyle` | Conflict marker format (`diff3` adds the common-ancestor section, not just yours/theirs) | Personal conflict-resolution preference |
| `[color]` (all sections) | Terminal color scheme for status/diff/branch output | Terminal cosmetics — purely personal |
| `[alias]` (all of them — `lg`, `st`, `ca`, `sync`, etc.) | Shorthand commands | Your muscle memory — you want `git st` to work in every repo, not just some |
| `[url "git@github.com:"] insteadOf` | Rewrites `https://github.com/` URLs to SSH transparently | Your auth preference (SSH over HTTPS) for a whole host, not one repo |
| `[credential] helper` | Where git caches/stores auth credentials (keychain, cache, store) | Your credential storage mechanism, machine-wide |

**Caveat on `[user]`:** this is the one entry worth revisiting per-project even though it *looks* global. If you commit to a work repo with a personal email (or vice versa), that's the most common config-scope mistake people make. See "the `user` exception" below.

---

## What belongs in `.git/config` (local) — anything project-specific

Local config should hold settings that are **true for this repo and would be wrong somewhere else.**

| Setting | Why local, not global |
|---|---|
| `[user] email` / `name` override | Work project needs `you@company.com`; personal projects need your personal address. A global default + local override per work repo is the standard pattern. |
| `[remote "origin"] url`, `[branch "x"] remote/merge` | Every repo has different remotes/tracking — these are already local by default (git writes them there automatically on `clone`/`checkout -b`) |
| `[core] sshCommand` (if a repo needs a different SSH key/identity file) | Per-repo credential routing, not a global habit |
| `[url "…"] insteadOf` rewrites that only make sense for one host used by one project | Global `insteadOf` applies everywhere; scope it locally if it's a one-off for a single repo's private mirror |
| Repo-specific `[filter]`/`[hooks]`-adjacent settings (e.g. LFS config git writes into `.git/config`) | Tied to what that repo actually needs (LFS, submodule behavior) |
| Any setting a `.gitattributes` or CI system expects a specific repo to have (e.g. `core.hooksPath` pointing at a repo-local hooks dir) | Behavior specific to this project's tooling |

---

## The `user` exception in practice

The cleanest setup: put your usual identity in `~/.gitconfig`, then override per-repo where needed.

```bash
# ~/.gitconfig — your default identity
git config --global user.name "xterm2000"
git config --global user.email "mitek@gmail.com"

# inside one specific work repo — override locally
cd ~/work/some-repo
git config --local user.email "mitek@company.com"
```

Better still, if you have a consistent split (e.g. everything under `~/work/` uses the work email), use `includeIf` in `~/.gitconfig` so you never have to remember to override manually:

```ini
# ~/.gitconfig
[includeIf "gitdir:~/work/"]
    path = ~/.gitconfig-work
```

```ini
# ~/.gitconfig-work
[user]
    email = mitek@company.com
```

Any directory under `~/work/` then picks up the work email automatically — no per-repo manual step, no risk of forgetting and leaking a personal commit into a work repo (or vice versa).

---

## Quick rule of thumb

- **"Would I want this in every repo I ever touch?"** → global (`--global`).
- **"Is this true only because of who owns this repo / what this repo needs?"** → local (`--local`, or just edit `.git/config` directly, or let `git` write it there itself via `clone`/`remote add`/`branch`).
- When in doubt, set it global — local config is cheap to add later the moment you hit a real conflict (e.g. the wrong email lands in a commit).

---

## See Also

- `git/.gitconfig` — this repo's example config, annotated inline, used as the source for the tables above
- `git/git-guide.md` §14 — elaborated explanation of what each setting above actually does (this file only covers *where* to put it)
- `git/git-local-dev.md` — local-dev workflow this identity/config setup supports
