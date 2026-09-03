# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

A personal DevOps/sysadmin reference repo, built around a Kubernetes lab cluster on AWS but grown to cover the surrounding toolchain: infra-as-code and K8s manifests for the lab (learning/reference implementation, not production), a Docker-based CI/CD homelab (Jenkins/Gitea/Nexus/Traefik), Linux/shell/git runbooks, and AI-tooling reference docs.

**`README.md` is the source of truth** for the top-level directory map — each directory has its own `README.md` with the actual index, architecture notes, and gotchas (immutable fields, silent failure modes, etc.). Read the root README first, then the relevant directory's README, before exploring. This file only covers what those don't: how to work in this repo with Claude Code.

## Scope Discipline

- When asked to "show", "look at", or "explain" a file, do NOT begin editing. Wait for an explicit edit/change/fix instruction before using Edit/Write tools.
- Confirm scope before proceeding when a request could be interpreted multiple ways (e.g., which template, which namespace, which target group).

## Documentation Style

- If a concept being documented is new to the repo (no prior doc covers it), explain the concept itself, not just the commands/syntax for it — don't assume the reader already has the mental model.
- When writing or editing documentation, verify each sentence matches the actual observed behavior; do not assume or invent behavior.
- Act as a documentation maintenance agent. Before making ANY edit, present a numbered plan of proposed changes and wait for my explicit approval. For every factual claim you write, verify it against the actual codebase behavior using Bash/Read and cite the file and command you checked. Never modify a file until I confirm or unless i explicitly ask. 

## Working with Large Output

- For large or iterative fetches from any source (web pages, API responses, command output, etc.), dump to a file first, then read/query the file — don't pull it directly into the conversation.
- When verifying multiple related bash commands (e.g. checking several flags/man pages before documenting them), write one script that runs them all and logs output (and exit codes) to a file, then run it once and read the log — rather than issuing many separate Bash calls.

## Common Gotchas

1. **`README.md` (root first, then the relevant directory's) is the source of truth** for structure and the real index — read it before exploring, and update it in the same change as any doc edit.
2. **Every command in a guide is verified against the locally installed tool version**, with the tested version noted in the guide.
3. **New guides match the sibling guide's conventions** — passphrase names, sample users, section ordering, index entry. Read one sibling first, once.
4. **Keep a guide a single file** unless explicitly asked for a split.
5. **This is a reference/learning repo, not production** — the AWS/K8s lab manifests are illustrative implementations, not a deployable system.
6. **Directory `README.md`s carry the load-bearing gotchas** (immutable fields, silent failure modes) — surface those when editing near the topic.
