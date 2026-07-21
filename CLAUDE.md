# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

A personal DevOps/sysadmin reference repo, built around a Kubernetes lab cluster on AWS but grown to cover the surrounding toolchain: infra-as-code and K8s manifests for the lab (learning/reference implementation, not production), a Docker-based CI/CD homelab (Jenkins/Gitea/Nexus/Traefik), Linux/shell/git runbooks, and AI-tooling reference docs.

**`README.md` is the source of truth** for directory layout, architecture notes, and gotchas (immutable fields, silent failure modes, etc.) — read it before exploring. This file only covers what README doesn't: how to work in this repo with Claude Code.

## Scope Discipline

- When asked to "show", "look at", or "explain" a file, do NOT begin editing. Wait for an explicit edit/change/fix instruction before using Edit/Write tools.
- Confirm scope before proceeding when a request could be interpreted multiple ways (e.g., which template, which namespace, which target group).

## Documentation Style

- If a concept being documented is new to the repo (no prior doc covers it), explain the concept itself, not just the commands/syntax for it — don't assume the reader already has the mental model.
- When writing or editing documentation, verify each sentence matches the actual observed behavior; do not assume or invent behavior.
- Act as a documentation maintenance agent. Before making ANY edit, present a numbered plan of proposed changes and wait for my explicit approval. For every factual claim you write, verify it against the actual codebase behavior using Bash/Read and cite the file and command you checked. Never modify a file until I confirm or unless i explicitly ask. Start by scanning our docs and reporting inconsistencies you'd fix.

## Working with Large Output

- For large or iterative fetches from any source (web pages, API responses, command output, etc.), dump to a file first, then read/query the file — don't pull it directly into the conversation.

## Key Scripts

```bash
./aws/cloudshell/cluster.sh start | stop | status   # cluster lifecycle via Lambda
./aws/cloudshell/services.sh                         # AWS resource inventory (us-east-1)
```

See README.md's Infrastructure section for env var overrides and defaults.
