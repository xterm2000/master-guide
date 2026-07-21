# AGENTS.md — Reference

## What AGENTS.md does

**AGENTS.md is not a Claude Code file.** It's an open, tool-agnostic standard (maintained by the Agentic AI Foundation) that other AI coding tools — OpenAI Codex, Cursor, GitHub Copilot, Gemini CLI, etc. — read for project-level context: build commands, code style, test commands, project structure, boundaries.

**Claude Code does not read AGENTS.md natively.** It reads `CLAUDE.md` instead, loaded automatically at the start of every session by walking up the directory tree from your working directory and concatenating every `CLAUDE.md` it finds (closer files take precedence).

If you maintain both files, or work across multiple AI tools, there are two workarounds — pick one, don't duplicate content by hand:

1. **Import (recommended if AGENTS.md is your source of truth):**
    
    ```
    # CLAUDE.md
    @AGENTS.md
    
    ## Claude-specific rules
    Use plan mode for changes under src/billing/.
    ```
    
    Claude Code expands the import at session start, then appends anything after it.
    
2. **Symlink (if the files are meant to be identical):**
    
    ```
    ln -s CLAUDE.md AGENTS.md
    ```
    

## CLAUDE.md vs AGENTS.md vs SKILL.md — don't conflate these

|File|Loaded|Scope|Read by|
|---|---|---|---|
|`CLAUDE.md`|Every session, always in context|Project or personal|Claude Code only|
|`AGENTS.md`|Every session (that tool's equivalent of CLAUDE.md)|Project|Codex, Cursor, Copilot, etc. — not Claude Code natively|
|`SKILL.md`|Only when Claude decides it's relevant, or invoked with `/skill-name`|Personal/project/plugin/enterprise|Claude Code (and other tools supporting the open Agent Skills spec)|

The practical distinction: CLAUDE.md/AGENTS.md are **always-loaded facts and conventions** ("we use pnpm," "test command is `make test-integration`"). If a CLAUDE.md section grows into a multi-step _procedure_ rather than a fact, that's the signal to extract it into a skill instead — keeps CLAUDE.md short (official guidance: aim under ~200 lines) since it's paid for on every single turn whether relevant or not. See [claude-skills-reference.md](01-claude-skills-reference.md) for skill details.

### Worked example: the `oracle-db-tools` project

Say this repo ships an internal CLI that other teams also drive with Cursor/Codex, so AGENTS.md is the shared source of truth and CLAUDE.md imports it:

```
# AGENTS.md
## Build & test
- Build: `mvn -pl oracle-db-tools package`
- Test: `mvn -pl oracle-db-tools test`

## Conventions
- All SQL lives under `sql/`, one file per script.
- Never commit a kill-session script — those are generated on demand, not stored.
```

```
# CLAUDE.md
@AGENTS.md

## Claude-specific rules
Use plan mode for anything under `sql/prod/`.
```

At session start Claude Code expands `@AGENTS.md` inline, so the shared build/test facts and the Claude-only plan-mode rule both end up in context — written once, in one file, instead of copy-pasted into two.

This is also where the "fact vs. procedure" line from above gets tested concretely. Early on, CLAUDE.md might have had a paragraph like: _"When a session looks stuck, query `v$session`/`gv$session` for the blocking chain, pull ASH/AWR if it already cleared, and don't run a kill script until root cause is confirmed."_ That's no longer a fact about the project — it's a multi-step procedure paid for on every single turn even when nobody's debugging a lock. That's exactly the signal to extract it into the `oracle-lock-triage` skill described in [claude-skills-reference.md](01-claude-skills-reference.md#worked-example-dummy-oracle-lock-triage-skill): CLAUDE.md shrinks back to one line — "Oracle lock issues: see `/oracle-lock-triage`" — and the procedure only loads tokens when actually invoked.

## Sources

- Claude Code Skills docs: code.claude.com/docs/en/skills
