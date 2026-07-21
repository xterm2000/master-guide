# Scripts

Repo-maintenance tooling — not lab/infra scripts (those live next to the docs
they operate on, e.g. `aws/cloudshell/`, `k8s/helper-scripts/`).

| Script | Purpose |
|--------|---------|
| `check-links.py` | Checks markdown links and repo-rooted backtick paths (e.g. a top-level-dir-prefixed path in backticks) across all `.md` files for broken references. Exits 1 if any are found — safe to wire into a pre-commit hook or CI. Deliberately does *not* flag bare filename mentions (`SKILL.md`, `CLAUDE.md` in prose) — that heuristic produced too many false positives against real prose; see the script's docstring. |

```bash
python3 scripts/check-links.py
```
