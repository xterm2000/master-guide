# Claude Code Skills — Reference

## Skill directory structure

```
~/.claude/skills/                     # personal skills (all projects, this user only)
└── my-skill-name/
    ├── SKILL.md                      # required — YAML frontmatter + instructions
    ├── scripts/                      # optional — executable code
    │   ├── generate.py
    │   └── validate.sh
    ├── references/                   # optional — docs Claude reads on-demand
    │   ├── api-guide.md
    │   └── troubleshooting.md
    └── assets/                       # optional — templates, static files
        ├── component.tsx.template
        └── logo.png

.claude/skills/                       # project-level skills (this repo only, shared via git)
└── another-skill/
    └── SKILL.md
```

There are actually **four** discovery scopes, not two:

|Scope|Location|Shared with|
|---|---|---|
|Personal|`~/.claude/skills/`|Just you, across all projects|
|Project|`.claude/skills/` at repo root (and parent dirs up to repo root)|Team, via git|
|Plugin|Installed via Anthropic Marketplace or `/plugin add <url>`|Anyone who installs the plugin|
|Enterprise|Pushed by IT/admin via MDM policy|Org-wide, centrally managed|

Claude scans all four at session start. When names collide, there's an explicit override order: **enterprise > personal > project > bundled**. Any of these also overrides a bundled skill of the same name.

## Key rules

- **Filename must be exactly `SKILL.md`** — uppercase, no exceptions. This is scanned for literally, in both Claude Code and the open Agent Skills spec.
- **Folder name must match the `name` field** in the YAML frontmatter — kebab-case, lowercase letters/numbers/hyphens only. Mismatches rely on undocumented behavior.
- **No `README.md` inside a skill folder.** More precisely: Claude never reads a README as instructions — only `SKILL.md` and files it explicitly references get loaded. Put a human-facing readme at the repo root if you're distributing the skill publicly, not inside the skill directory.
- **Nested/scoped skills:** if the same unqualified name exists in multiple directories, Claude Code auto-invokes the project-root variant _and_ appends directory-qualified variants (e.g. `/apps/web:deploy`) that apply when working in that subdirectory. Every variant still needs its own `SKILL.md`.
- **Symlinks are supported**: a skill-name entry can symlink to a directory elsewhere on disk; Claude Code follows it and reads `SKILL.md` from the target. If the same target is reachable from multiple locations, it's only loaded once.
- **`disable-model-invocation: true`** — set this in frontmatter for skills that should never auto-fire (destructive operations like deploys/migrations). Without it, Claude may trigger any skill automatically if the prompt matches the `description`.
- **Progressive disclosure / token cost:** only `name` + `description` (~50–100 tokens) load into the system prompt at startup. The full `SKILL.md` body (typically <5k tokens) loads only when Claude decides it's relevant, or you invoke it directly with `/skill-name`. Bundled `scripts/`, `references/`, `assets/` cost nothing until actually read.
- **The `description` field is the trigger, not documentation.** Write it in third person, be specific about what the skill does _and_ when to use it — vague descriptions are the most common reason a skill never fires.

## Commands vs. skills — how they actually blend

**They are not two separate systems.** As of the current Claude Code docs: _"Custom commands have been merged into skills."_ A file at `.claude/commands/deploy.md` and a skill at `.claude/skills/deploy/SKILL.md` both create `/deploy` and behave the same way. Old `.claude/commands/` files keep working indefinitely — there's no forced migration, no deprecation timeline.

**What skills add that plain commands don't:**

- A directory for supporting files (`scripts/`, `references/`, `assets/`)
- Frontmatter controls (`disable-model-invocation`, `user-invocable`, `allowed-tools`, `paths`, `model`, `effort`)
- `context: fork` — run the skill in an isolated subagent instead of your main context
- Dynamic context injection (`` !`shell command` `` gets executed and its output inlined before Claude sees the prompt)

**Precedence when names collide:** enterprise > personal > project > bundled. A skill of any kind also overrides a bundled skill with the same name (e.g. a project `code-review` skill replaces the bundled `/code-review`). If a skill and a `.claude/commands/` file share a name, the skill wins. Plugin skills are namespaced (`plugin-name:skill-name`), so they never collide with anything.

### Two categories of "built-in" — don't conflate these

Claude Code ships with things that look identical from the `/` menu but work differently under the hood:

|Type|Examples|How it runs|
|---|---|---|
|**Built-in commands**|`/clear`, `/compact`, `/help`, `/model`, `/cost`|Fixed logic, hardcoded into the CLI itself. No prompt involved.|
|**Bundled skills**|`/doctor`, `/code-review`, `/batch`, `/debug`, `/loop`, `/run`, `/verify`|Prompt-based — Claude gets detailed instructions and orchestrates the work with tools, same as any skill you'd write yourself. Can be disabled via `disableBundledSkills`.|

### The real decision: not "command or skill" — it's invocation control

Since commands _are_ skills now, the actual design decision is which frontmatter mode to use:

|Mode|You can invoke|Claude can auto-invoke|Use for|
|---|---|---|---|
|Default (nothing set)|✅ `/name`|✅ auto, if description matches|General-purpose — most skills should be this|
|`disable-model-invocation: true`|✅ `/name` only|❌ never|Anything with side effects or where timing matters: `/deploy`, `/commit`, `/send-slack-message`, migrations. You don't want Claude deciding to deploy because your code "looks ready."|
|`user-invocable: false`|❌ hidden from menu|✅ auto only|Background knowledge that isn't a meaningful user action — e.g. a `legacy-system-context` skill explaining how an old subsystem works. Claude should know it; you'll never type `/legacy-system-context`.|

A practical mental model, in order of what to reach for:

1. **Something the human should explicitly kick off, especially if it has side effects (deploy, publish, delete, bill, contact an external service)** → skill with `disable-model-invocation: true`. Visible invocation is part of the safety model here, not just UX.
2. **A reusable procedure Claude should apply on its own when context matches** → default skill, well-written `description`.
3. **A short personal macro / shorthand for a prompt you paste often, no supporting files needed** → either a plain `.claude/commands/*.md` file or a skill with nothing but a description — genuinely doesn't matter which, the difference is trivial.
4. **A section of CLAUDE.md that's grown from "this is a fact about the project" into "here are five steps to do X"** → extract it into a skill. This is the single most common signal that something belongs in a skill: CLAUDE.md is paid for every turn; skill bodies load only when used.

### Other things worth knowing

- **Argument stacking:** as of v2.1.199, you can chain skills in one message — `/code-review /fix-issue 123` loads both and passes `123` as `$ARGUMENTS` to each.
- **Skill content persists in context** once invoked — Claude Code doesn't re-read the file on later turns. Write skill instructions as standing guidance, not "do this once" steps, if you want them to keep applying.
- **Auto-invocation isn't perfectly reliable.** If a skill needs to fire deterministically every time, back it with a [hook](https://code.claude.com/docs/en/hooks) rather than trusting the model to always notice the match.

### Full frontmatter field reference

Every field is optional; only `description` is recommended so Claude knows when to use the skill. All go between `---` markers at the top of `SKILL.md`.

|Field|What it does|
|---|---|
|`name`|Display name shown in skill listings. Defaults to the directory name. Does **not** change what you type after `/` — that comes from the folder path — except for a plugin-root `SKILL.md`, where `name` does set the command name since there's no skill directory to derive it from.|
|`description`|What the skill does and when to use it. This is the trigger text Claude matches your prompt against. If omitted, Claude falls back to the first paragraph of the markdown body. Put the key use case first — combined with `when_to_use`, it's truncated at 1,536 characters in the listing.|
|`when_to_use`|Extra trigger phrases/example requests, appended to `description` in the listing. Counts toward the same 1,536-char cap.|
|`argument-hint`|Autocomplete hint showing expected arguments, e.g. `[issue-number]` or `[filename] [format]`. Cosmetic only — doesn't enforce anything.|
|`arguments`|Named positional arguments for `$name` substitution (space-separated string or YAML list). E.g. `arguments: [issue, branch]` lets you write `$issue` and `$branch` in the body instead of `$0`/`$1`.|
|`disable-model-invocation`|Strips the description from context entirely — Claude can't see or auto-invoke the skill. Only manual `/name` works. Also blocks subagent preloading and (v2.1.196+) scheduled-task invocation. See full breakdown above.|
|`user-invocable`|Set `false` to hide from the `/` menu — only Claude can invoke it. Use for background knowledge that isn't a meaningful user action (e.g. "here's how our legacy billing system works"). Mirror image of the flag above; don't confuse the two.|
|`allowed-tools`|Tools Claude can use **without asking permission** while this skill is active (space/comma-separated string or YAML list). Doesn't restrict anything — every tool stays callable; this just pre-approves specific ones. For project-committed skills, only takes effect after you accept the workspace trust dialog.|
|`disallowed-tools`|The inverse: tools **removed** from Claude's available pool while the skill is active. Use for autonomous/background skills that should never, say, call `AskUserQuestion` mid-loop. Restriction clears on your next message.|
|`model`|Overrides which model runs while this skill is active (accepts same values as `/model`, or `inherit`). Applies only for the rest of the current turn — session model resumes after. Ignored if it's outside your org's `availableModels` allowlist.|
|`effort`|Reasoning effort level while the skill is active: `low`, `medium`, `high`, `xhigh`, `max` (availability depends on model). Overrides session-level effort for that turn.|
|`context`|Set to `fork` to run the skill in an isolated subagent context instead of your main conversation — it won't see your conversation history, only the rendered SKILL.md as its prompt.|
|`agent`|Which subagent type executes the skill when `context: fork` is set — built-ins are `Explore`, `Plan`, `general-purpose`, or any custom subagent from `.claude/agents/`. Defaults to `general-purpose` if omitted.|
|`hooks`|Hooks scoped to just this skill's lifecycle, rather than global hooks that fire regardless of what's active.|
|`paths`|Glob pattern(s) restricting when Claude will auto-load the skill — only activates when working with matching files. Same format as CLAUDE.md path-specific rules. Doesn't block manual `/name` invocation, just auto-triggering.|
|`shell`|Which shell runs `` !`command` `` and ` ```! ` inline-injection blocks in this skill. Defaults to `bash`; `powershell` requires `CLAUDE_CODE_USE_POWERSHELL_TOOL=1`.|

**Practical groupings, since 16 fields is a lot to hold in your head:**

- **Discovery/trigger:** `name`, `description`, `when_to_use`, `argument-hint`, `paths`
- **Who can invoke it:** `disable-model-invocation`, `user-invocable`
- **Runtime behavior:** `context`, `agent`, `model`, `effort`, `shell`
- **Tool access while active:** `allowed-tools`, `disallowed-tools`
- **Parameterization:** `arguments`
- **Automation glue:** `hooks`

**The one most people never touch but should:** `paths`. If a skill is genuinely relevant only to, say, `*.tsx` files or a `/backend` directory, scoping it with `paths` keeps it from firing (or cluttering the auto-invoke listing) on unrelated work — cheaper than writing an over-narrow `description` and hoping the model infers scope correctly from wording alone.

### Worked example: dummy `oracle-lock-triage` skill

A project skill at `.claude/skills/oracle-lock-triage/SKILL.md` that diagnoses Oracle blocking sessions. It's a good vehicle for showing most fields at once because it has everything that pushes on frontmatter: it takes arguments, it should only run with elevated care (it can generate kill-session scripts), it wants a narrower toolset than the default, and it's only relevant inside a `db/` directory.

```yaml
---
name: oracle-lock-triage
description: Diagnoses Oracle Database lock contention, blocking sessions, enq TX/TM waits, and hung transactions, including RAC/multi-instance clusters. Reconstructs blocking chains from ASH/AWR and writes kill-session and remediation scripts.
when_to_use: user reports hung sessions, a deadlock in prod, pastes v$session output with BLOCKING_SESSION set, or asks "who is blocking whom" in Oracle
argument-hint: "[sid] [instance]"
arguments: [sid, instance]
disable-model-invocation: true
allowed-tools: Bash, Read, Grep
disallowed-tools: Write, Edit
model: inherit
effort: high
context: fork
agent: general-purpose
paths: "db/**,sql/**"
shell: bash
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "echo 'oracle-lock-triage: confirm target is not PROD' >&2"
---

# Oracle Lock Triage

Diagnose the blocking chain for session `$sid` on instance `$instance`.

1. Query `v$session` / `gv$session` for the full blocker → waiter chain.
2. Pull ASH/AWR history if the block has already cleared.
3. Identify root cause (row lock, TM lock from an unindexed FK, library cache pin, etc.).
4. Only after confirming with the user, propose a `kill -9` / `ALTER SYSTEM KILL SESSION` script — never run it directly.
```

Why each field earns its place here:

- **`arguments`** turns `/oracle-lock-triage 452 2` into `$sid=452`, `$instance=2` inside the body instead of positional `$0`/`$1`.
- **`disable-model-invocation: true`** because this skill can produce kill-session scripts — the human should type `/oracle-lock-triage` on purpose, not have Claude decide a session "looks stuck."
- **`allowed-tools` / `disallowed-tools`** pre-approve read-only diagnosis (`Bash`, `Read`, `Grep`) while still requiring explicit permission for anything that edits files.
- **`context: fork` + `agent: general-purpose`** run the triage in an isolated subagent so a long ASH/AWR investigation doesn't bloat the main conversation.
- **`model: inherit` + `effort: high`** keep whatever model the session is already using, but push reasoning effort up for a diagnosis task that benefits from it.
- **`paths: "db/**,sql/**"`** stops it from cluttering the auto-invoke listing while working on, say, the frontend.
- **`hooks`** attaches a scoped `PreToolUse` guard that fires only while this skill is active, not globally.

## Sources

- Claude Code Skills docs: code.claude.com/docs/en/skills
- Agent Skills overview: platform.claude.com/docs/en/agents-and-tools/agent-skills/overview
- Agent Skills best practices: platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
