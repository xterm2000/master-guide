#!/usr/bin/env python3
"""Check cross-references between markdown files in this repo.

Two checks, both mirroring real gaps found by hand during a manual audit:

1. Markdown links `[text](path)` — resolved relative to the file they're in.
2. Backtick paths rooted at a top-level repo directory, e.g. `linux/foo/bar.md`
   — resolved relative to the repo root. Supports a trailing `*` glob.

Deliberately does NOT flag bare backtick filenames like `bar.md` with no
directory — docs in this repo legitimately name files in running prose
(`SKILL.md`, `CLAUDE.md`, cross-directory "See Also" mentions) without that
meaning "resolve relative to the current file," so that heuristic produces
mostly false positives and isn't worth the noise.

Exits 1 if anything is broken, 0 otherwise — safe to wire into a pre-commit
hook or CI.
"""

import glob
import os
import re
import sys

TOP_LEVEL_DIRS = (
    "linux", "k8s", "git", "network", "docker-cicd", "aws", "ai-generic",
)

MD_LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
ROOTED_PATH_RE = re.compile(
    r"`((?:" + "|".join(TOP_LEVEL_DIRS) + r")/[A-Za-z0-9_./*-]+\.[A-Za-z0-9]+)`"
)


def find_markdown_files(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for name in filenames:
            if name.endswith(".md"):
                yield os.path.join(dirpath, name)


def check_file(path, repo_root):
    problems = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        content = fh.read()
    file_dir = os.path.dirname(path)

    for target in MD_LINK_RE.findall(content):
        if target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        clean = target.split("#", 1)[0]
        if not clean:
            continue
        resolved = os.path.normpath(os.path.join(file_dir, clean))
        if not os.path.exists(resolved):
            problems.append(f"markdown link -> {target}  (resolved: {resolved})")

    for target in ROOTED_PATH_RE.findall(content):
        resolved = os.path.normpath(os.path.join(repo_root, target))
        if "*" in target:
            if not glob.glob(resolved):
                problems.append(f"rooted path -> `{target}`  (glob matched nothing)")
        elif not os.path.exists(resolved):
            problems.append(f"rooted path -> `{target}`  (resolved: {resolved})")

    return problems


def main():
    repo_root = os.path.abspath(
        sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..")
    )
    total_problems = 0
    for path in sorted(find_markdown_files(repo_root)):
        rel = os.path.relpath(path, repo_root)
        for problem in check_file(path, repo_root):
            print(f"{rel}: {problem}")
            total_problems += 1

    if total_problems:
        print(f"\n{total_problems} broken reference(s) found.")
        return 1
    print("No broken references found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
