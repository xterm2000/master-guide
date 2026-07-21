# Claude Code settings.json — Complete Reference

`settings.json` is where Claude Code's permission rules, hooks, environment, and behavior get configured — as opposed to `CLAUDE.md`/`AGENTS.md` (instructions the model reads) or skill/subagent frontmatter (scoped to one skill/agent). This doc covers the settings file itself: where it lives, how scopes combine, the full permission-rule syntax with its sharp edges, and hooks.

## File locations and precedence

| Scope | Path | Committed to git? |
|---|---|---|
| Managed (highest) | platform-specific, see below | No — admin-deployed |
| Local | `.claude/settings.local.json` | No — gitignored automatically |
| Project | `.claude/settings.json` | Yes |
| User (lowest) | `~/.claude/settings.json` | No |

Higher scopes win on conflicting scalar values, but **permission rules merge across scopes rather than override** — an `allow` rule in user settings and a `deny` rule in project settings both apply, and deny always wins regardless of which scope defined it (see precedence below).

`.claude/settings.local.json` resolves through git worktrees to the main checkout (as of v2.1.211) — an approval saved in a worktree session applies repo-wide, not just in that worktree. Outside a git repo, or when the repo root is your home directory, the rule saves in the directory you started Claude Code from instead.

Managed settings deployment mechanisms (all same JSON format, none of them overridable by user/project):

- Server-managed (delivered remotely by Anthropic or a self-hosted gateway)
- MDM/OS policy: macOS plist domain `com.anthropic.claudecode`, Windows registry `HKLM\SOFTWARE\Policies\ClaudeCode`
- File-based: `/Library/Application Support/ClaudeCode/` (macOS), `/etc/claude-code/` (Linux/WSL), `C:\Program Files\ClaudeCode\` (Windows)

## Full key reference, by category

```jsonc
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",

  // permissions
  "permissions": {
    "allow": ["Bash(npm run lint)"],
    "ask": ["Bash(git commit *)"],
    "deny": ["Bash(curl *)"]
  },
  "allowManagedPermissionRulesOnly": false,

  // model
  "model": "claude-sonnet-5",
  "fallbackModel": ["claude-sonnet-5", "claude-haiku-4-5"],
  "effortLevel": "high",

  // environment
  "env": { "CLAUDE_CODE_ENABLE_TELEMETRY": "1" },
  "apiKeyHelper": "/bin/generate_temp_api_key.sh",

  // memory
  "autoMemoryEnabled": true,
  "autoMemoryDirectory": "~/my-memory-dir",
  "claudeMd": "Always run make lint before committing.",

  // UI
  "defaultShell": "bash",
  "editorMode": "normal",
  "spinnerTipsEnabled": false,

  // hooks
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "prettier --write $CLAUDE_FILE_PATHS" }] }
    ]
  },

  // MCP
  "enabledMcpjsonServers": ["memory", "github"],
  "disabledMcpjsonServers": ["filesystem"]
}
```

The full key list is large (~60 keys spanning model selection, telemetry, plugins, marketplaces, remote control, etc.) — most of it isn't relevant day-to-day. The ones worth knowing:

| Key | Does |
|---|---|
| `permissions.allow` / `ask` / `deny` | the rule lists — see below, this is most of what you'll actually touch |
| `defaultMode` | sets the permission mode (`default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`) — see modes table below |
| `hooks` | commands that run around tool calls — see Hooks section |
| `env` | env vars applied to every session and subprocess |
| `additionalDirectories` | persist `--add-dir` grants without passing the flag every launch |
| `autoMemoryEnabled` / `autoMemoryDirectory` | this repo's memory system (`~/.claude/projects/<project>/memory/`) is controlled here |
| `spinnerTipsEnabled` | this repo's `.claude/settings.local.json` sets this `false` |
| `disableBundledSkills`, `disableSkillShellExecution` | strip or restrict skill capability |

Most keys reload on file change without restart. Two that don't: `model` and `outputStyle` — read once at startup, take effect on `/clear` or restart.

## Attribution — the Co-Authored-By trailer

By default, Claude Code appends attribution to commits it creates (`🤖 Generated with Claude Code` + a `Co-Authored-By: Claude` trailer) and to PR descriptions. Two settings control this, and **this repo's `.claude/settings.local.json` uses the older one**:

```json
{ "includeCoAuthoredBy": false }
```

`includeCoAuthoredBy` is a boolean — `false` suppresses attribution on both commits and PRs, all-or-nothing. It's **deprecated as of v2.0.62**, replaced by a finer-grained `attribution` object that lets commit and PR attribution be toggled independently:

```json
{
  "attribution": {
    "commit": "",
    "pr": ""
  }
}
```

`attribution.commit`/`attribution.pr` default to the `🤖 Generated with Claude Code` text and the Co-Authored-By line respectively; setting either to `""` removes just that one, or set custom text to replace it entirely (e.g. a company-specific attribution string). `attribution` takes precedence when both keys are present. The old key still functions — this repo's use of it is not broken, just legacy — but new configuration should prefer `attribution` for the independent commit/PR control.

## statusLine and subagentStatusLine

`statusLine` runs a script of your choosing and displays whatever it prints in place of the default status bar — this repo's user-level `~/.claude/settings.json` has one configured:

```json
{
  "statusLine": {
    "type": "command",
    "command": "python3 ~/.claude/statusline.py",
    "padding": 1
  }
}
```

Mechanics worth knowing:

- The script receives a JSON blob on **stdin** (model name, cwd, git info, `cost.total_cost_usd`, `context_window.used_percentage`, rate limits, etc. — dozens of fields) and whatever it prints to **stdout** becomes the status line.
- It reruns on: a new assistant message, `/compact` finishing, a permission-mode change, vim-mode toggling, and (if set) a `refreshInterval` timer — not continuously, so it's cheap.
- `padding` (this repo's config uses `1`) adds horizontal spacing in characters, in addition to the UI's own built-in spacing.
- It requires workspace trust to be accepted for the current folder — same trust gate as hooks, since it's an arbitrary shell command. If it stays blank, that's the first thing to check (`claude --debug` logs `workspace trust not accepted` explicitly).
- `subagentStatusLine` is the equivalent for the per-subagent rows in the agent panel — replaces the default `name · description · token count` line, one JSON object of visible tasks in, one `{"id":..., "content":...}` line out per row you want to override.

## theme and tui — a discrepancy worth flagging

This repo's user settings (`~/.claude/settings.json`) also sets:

```json
{ "tui": "fullscreen", "theme": "dark" }
```

`tui` is documented as a **boolean** (default `true`) controlling whether output renders in the fullscreen text-UI vs a simpler terminal mode — the observed value here is the *string* `"fullscreen"` rather than `true`/`false`, which doesn't match the documented type. `theme` doesn't appear in the public settings key table at all, despite being present and evidently functional in a real config (community reverse-engineering of `~/.claude/themes/*.json` color tokens suggests theme selection is a real, if under-documented, mechanism). Flagging both rather than asserting a confident explanation — take the documented `tui` boolean as the reference behavior, and treat `theme`/the string form of `tui` as observed-but-unverified against the public docs.

## Permission modes

Set via `defaultMode` in a settings file, or switched mid-session:

| Mode | Behavior |
|---|---|
| `default` (aka `manual`) | prompts on first use of each tool, standard interactive experience |
| `acceptEdits` | auto-accepts file edits (Edit/Write/NotebookEdit) plus common filesystem commands (`mkdir`, `touch`, `mv`, `cp`) inside the working directory |
| `plan` | read-only exploration — no edits, no non-read-only shell commands, until you exit plan mode |
| `auto` | auto-approves with a background safety classifier checking the action matches your request |
| `dontAsk` | auto-**denies** anything not pre-approved via `permissions.allow` — inverse of `bypassPermissions` |
| `bypassPermissions` | skips prompts entirely, except explicit `ask` rules and a hardcoded circuit-breaker for `rm -rf /` / `rm -rf ~` (including via `$(...)` substitution) |

`bypassPermissions` also skips prompts for writes to `.git`, `.claude`, `.vscode`, `.idea`, and similar tool-config directories — the docs explicitly warn to use it only in disposable/isolated environments (containers, VMs), never on a machine you care about.

## How rules are evaluated

**Order: deny → ask → allow.** First match wins; specificity doesn't matter. This means:

- A broad `deny` like `Bash(aws *)` blocks a narrower `allow` like `Bash(aws s3 ls)` — deny rules can't carry allowlist exceptions.
- A matching `ask` rule prompts even when a more specific `allow` rule also matches.
- A bare tool name in `deny` (e.g. `"Bash"`) removes the tool from Claude's context entirely — Claude never sees it exists. A scoped deny (`Bash(rm *)`) leaves the tool available but blocks that specific call.

**`EndConversation` is the one exception** — no deny or ask rule can remove it while any other tool remains; this is deliberate (it's a self-harm-only tool with no read/write capability, so the safeguard can't be disabled by the session it protects).

Permission rules are enforced by Claude Code itself, not by the model — instructions in a prompt or `CLAUDE.md` shape what Claude *tries* to do, but don't change what's actually allowed. To grant/revoke, use `/permissions`, these rule files, a permission mode, or a `PreToolUse` hook.

**`Ctrl+E` at a permission prompt** shows a risk explanation (Low/Med/High) of what the command does and why Claude is running it — generated on demand, not pre-computed for every prompt. Toggle off with `permissionExplainerEnabled: false` in `~/.claude.json` (note: that's `~/.claude.json`, not `~/.claude/settings.json`).

### Matching by input parameter, not just the command string

Deny/ask rules (not allow) can gate on any top-level scalar parameter a tool accepts, via `Tool(param:value)`:

```
Agent(model:opus)              deny/ask any subagent call requesting the Opus tier
Agent(isolation:worktree)      deny/ask any subagent call that requests a git worktree
Bash(run_in_background:true)   deny/ask any Bash call that backgrounds itself
```

Rules: one parameter per rule (no combining `model` and `isolation` in one), `*` wildcards the value, a parameter the model never sets is never matched (so `Agent(model:*)` doesn't catch an unset model), and matching happens on the literal value Claude sends *before* normalization — `Agent(model:opus)` matches the alias `opus`, not a resolved model ID.

This does **not** work for `command` (Bash/PowerShell), `file_path` (Read/Edit/Write), `path` (Grep/Glob), or `url` (WebFetch) — those already have dedicated specifier syntax, and Claude Code ignores a `Bash(command:rm *)`-style rule with a startup warning, since a compound command would trivially bypass it.

### Tool-name wildcards (deny/ask only)

```
"*"          matches every tool (deny: strips everything but EndConversation)
"mcp__*"     matches every MCP tool from every server
```

Allow rules can't use an unanchored glob like this — `mcp__puppeteer__*` (anchored to one named server) works as an allow rule, but a bare `"*"` or `"mcp__*"` allow is skipped with a warning and grants nothing. This asymmetry is deliberate: a broad deny is safe to auto-apply, a broad allow is not.

### Canonical name vs displayed label

A tool's name in the transcript/permission dialog can differ from the name a rule must use — e.g. the UI shows `Stop Task`, but the rule (and hook matcher) must say `TaskStop`. Writing a deny/ask rule for the displayed label instead of the canonical name produces a startup warning (typo detection), but only for deny/ask — always check the [tools reference](03-claude-code-tools-reference.md) for the real name.

## Bash rule syntax — the sharp edges

This repo's `.claude/settings.local.json` uses several of these patterns already (`Bash(git * master)`, `Bash(* --help *)`), so the nuances below directly affect how those rules behave.

### Wildcard positioning matters

```
Bash(ls *)     matches "ls -la"        NOT "lsof"     (space before * = word boundary)
Bash(ls*)      matches both "ls -la" AND "lsof"        (no space = no boundary)
Bash(ls:*)     equivalent to "Bash(ls *)" — :* is shorthand for a trailing " *"
```

`*` can appear anywhere and spans multiple arguments/spaces: `Bash(git * main)` matches both `git checkout main` and `git push origin main`.

### Compound commands are split and matched independently

Claude Code recognizes shell operators (`&&`, `||`, `;`, `|`, `|&`, `&`, newlines) — a rule for `safe-cmd *` does **not** implicitly authorize `safe-cmd && rm -rf /`. Every subcommand must match its own rule.

```json
// This does NOT grant "git status && npm test" as a whole —
// it only means npm test (as a standalone command) is pre-approved.
"allow": ["Bash(npm test *)"]
```

### Wrapper stripping

Before matching, Claude Code strips a fixed, non-configurable set of wrappers: `timeout`, `time`, `nice`, `nohup`, `stdbuf`, the shell builtins `command`/`builtin`, zsh's `noglob`, and bare `xargs` (only when it has no flags). So `Bash(npm test *)` also matches `timeout 30 npm test`.

**Not stripped**: `direnv exec`, `devbox run`, `mise exec`, `npx`, `docker exec` — these execute their argument as a command, so `Bash(devbox run *)` matches *anything* after `run`, including `devbox run rm -rf .`. Write the full compound instead: `Bash(devbox run npm test)`.

**Never auto-approvable by prefix**: `watch`, `setsid`, `ionice`, `flock`, and `find` with `-exec`/`-delete` — these always prompt regardless of a matching `*` rule; only an exact full-string match works.

### Read-only commands (never prompt, in every mode)

`ls`, `cat`, `echo`, `pwd`, `head`, `tail`, `grep`, `find`, `wc`, `which`, `diff`, `stat`, `du`, `cd`, and read-only `git` forms — hardcoded, not configurable via settings (add an explicit `ask`/`deny` rule to override for a specific one). This is why this repo's `Bash(grep *)` allow rule is actually redundant — `grep` already runs without a prompt.

### The curl/URL-filtering trap

Don't try to constrain a Bash rule to a specific URL or domain — it's fragile by construction:

```
Bash(curl http://github.com/ *)   # intended: restrict curl to GitHub
```

Bypassed trivially by: putting flags before the URL (`curl -X GET http://github.com/...`), switching protocol (`https://`), a redirecting shortlink, or `URL=http://github.com && curl $URL`. The documented fix is architectural, not a smarter pattern: deny `curl`/`wget` in Bash entirely and use `WebFetch(domain:github.com)` instead, since WebFetch's domain matching is a real check, not a string pattern on a mutable command line.

## PowerShell rule syntax

Same shape as Bash (`*` wildcards anywhere, `:*` trailing shorthand, bare `PowerShell` matches everything), but two real differences:

- **Alias-aware**: a rule written for the full cmdlet name also matches its aliases — `PowerShell(Get-ChildItem *)` matches `gci`, `ls`, and `dir` too, since Claude Code canonicalizes before matching.
- **Matching is case-insensitive** (Bash matching is case-sensitive, since shell commands are).
- Compound commands are split via a real PowerShell AST parse (pipeline `|`, statement `;`, and on PS7+ `&&`/`||`), not the heuristic operator-splitting Bash rules use — every subcommand still needs its own match.

```json
"allow": ["PowerShell(Get-ChildItem *)", "PowerShell(git commit *)"],
"deny": ["PowerShell(Remove-Item *)"]
```

## Read / Edit rule syntax — path anchoring

Both follow gitignore pattern semantics, with four anchor forms:

| Pattern | Anchors at | Example |
|---|---|---|
| `//path` | filesystem root (absolute) | `Read(//etc/**)` — this repo's settings use exactly this |
| `~/path` | home directory | `Read(~/Documents/*.pdf)` |
| `/path` | the settings **source file's** directory (not filesystem root!) | `Edit(/src/**)` in project settings → `<project root>/src/**` |
| `path` or `./path` | current working directory | `Read(*.env)` |

**The single-leading-slash gotcha**: `/Users/alice/file` is NOT an absolute path in this syntax — the single leading `/` anchors at the settings source, not the filesystem root. You need `//Users/alice/file` for that. This is exactly why this repo's rules use `//tmp/**` and `//etc/**` with the double slash.

A `/path` rule's anchor point depends on *where the rule is defined* — the same rule text resolves differently in project settings (`<project root>/path`) vs local settings (`<original cwd>/path`) vs user settings (`~/.claude/path`).

**Symlinks**: allow and deny rules treat them asymmetrically. An allow rule requires *both* the symlink path and its resolved target to match (a symlink pointing outside an allowed directory still prompts). A deny rule blocks if *either* the link or its target matches — so a symlink pointing at a denied file is denied even if the link itself lives somewhere unrestricted.

**`Edit` covers Write and NotebookEdit too** — one `Edit(docs/**)` rule governs all three file-modifying tools; a `Write(docs/**)` rule by itself is silently unmatched (Claude Code warns at startup) because file-permission checks only look at `Edit(path)`/`Read(path)` forms.

## WebFetch domain matching

```
WebFetch(domain:example.com)      matches example.com only
WebFetch(domain:*.example.com)    matches any subdomain (api.example.com, a.b.example.com) — NOT example.com itself
WebFetch(domain:example.*)        matches example.org (the * fills one label between dots) — NOT example.evil.com
```

That last rule is deliberate: outside a leading `*.` or a bare `*`, the wildcard can't cross a `.` — closing the loophole where an attacker registers `example.evil.com` to slip past a naive `example.*` rule.

## Agent, MCP, and Cd rules

```
Agent(Explore)                    matches the Explore subagent
Agent(my-custom-agent)            matches a custom subagent by name

mcp__puppeteer                    any tool from the puppeteer MCP server
mcp__puppeteer__puppeteer_navigate  one specific tool from that server
mcp__*                            (deny only) every MCP tool from every server

Cd(~/code/*)                      /cd may enter ~/code/app, not ~/code/app/src or ~/code itself
Cd(~/code/**)                     /cd may enter ~/code and anything under it
```

`Cd` rules are unusual: they only govern the `/cd` slash command you type yourself — Claude can never invoke `/cd`, so these rules aren't a model-facing restriction the way the others are.

## Hooks

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "markdownlint --fix $CLAUDE_FILE_PATHS || true" }
        ]
      }
    ]
  }
}
```

This is this repo's actual hook — runs `markdownlint --fix` on any file Claude edits or writes, matched by tool name (`Edit|Write`, a regex against the tool name, not a permission-rule pattern). `$CLAUDE_FILE_PATHS` is populated with the touched file path(s).

A **`PreToolUse`** hook can go further than a permission rule: it runs before the prompt and its exit code can force a block (exit 2) that overrides even a matching `allow` rule — the only mechanism that outranks `allow` besides an explicit `deny`. This is the documented pattern for "allow all Bash except a specific denylist enforced by logic a static pattern can't express."

## Workspace trust — why some allow rules don't apply until you click through a dialog

Project-level `permissions.allow` and `additionalDirectories` in `.claude/settings.json` (committed, so a repo you clone could weaponize them) only take effect after you accept the workspace trust dialog for that folder — Claude Code reads the rules but ignores them until then. `deny`/`ask` rules are unaffected, since they only restrict, never grant.

`.claude/settings.local.json` is normally exempt (it's your own file), **except** when it looks like the repository could have supplied it — committed to git, or `.claude` is a symlink — in which case it goes through the same trust check as project settings. Two things bypass the check entirely regardless: the directory isn't inside a git repo at all, or the session is running in your own config home (your actual home directory, or wherever `CLAUDE_CONFIG_DIR` points).

Trust is saved per git-repo-root (or per launch directory outside a repo). Trusting a parent directory does not extend to a nested project inside it.

## How permissions interact with sandboxing

Sandboxing (a separate, OS-level layer — see `/docs/en/sandboxing`) restricts Bash's filesystem/network access at the process level, independent of permission rules. The two combine:

- Sandbox filesystem restrictions merge with `Read`/`Edit` deny rules into one effective boundary.
- Sandbox network restrictions merge with `WebFetch` domain rules (`allowedDomains`/`deniedDomains`).
- With sandboxing on and `autoAllowBashIfSandboxed` at its default `true`, a sandboxed Bash command runs without prompting even under a bare `Bash` ask rule — the sandbox boundary substitutes for that prompt. **Exception**: in `plan` mode this substitution is skipped, so non-read-only shell commands still prompt even when sandboxed.
- Content-scoped `ask`/`deny` rules (`Bash(git push *)`) and the `rm -rf /`/home-directory circuit breaker still fire regardless of sandbox state.

## Working directories

- `--add-dir <path>` at startup, `/add-dir` mid-session, or `additionalDirectories` in settings — three ways to extend file access beyond the launch directory.
- Files under an additional directory get the same permission treatment as the original working directory (no-prompt reads, mode-governed edits).
- **Important distinction**: `additionalDirectories` in settings grants file access *only*. `--add-dir`/`/add-dir` additionally load skills and subagents (with live reload) from that directory's `.claude/` — settings-file-based additions don't.

## Practical recipes by workflow

Each of these is a full `permissions` block you could drop into `.claude/settings.local.json` for that kind of work. The shared pattern: `allow` covers pure inspection, `ask` covers state changes that are routine but should still get a human glance, `deny` covers the handful of things that should never happen without editing the file itself.

### System diagnostics / sysadmin (this repo's own use case)

Read-only investigation across firewalld, SELinux, systemd, and package state runs free; anything that mutates system state stops for a look:

```json
"allow": [
  "Bash(sudo firewall-cmd --get-*)",
  "Bash(sudo firewall-cmd --list-all)",
  "Bash(sudo semanage * -l)",
  "Bash(sudo getsebool -a)",
  "Bash(systemctl status *)",
  "Bash(systemctl show *)",
  "Bash(journalctl *)",
  "Bash(dnf repoquery *)",
  "Bash(rpm -q *)"
],
"ask": [
  "Bash(sudo firewall-cmd --add-*)",
  "Bash(sudo firewall-cmd --remove-*)",
  "Bash(sudo setenforce *)",
  "Bash(sudo setsebool *)",
  "Bash(systemctl start *)",
  "Bash(systemctl stop *)",
  "Bash(systemctl restart *)",
  "Bash(systemctl enable *)"
],
"deny": [
  "Bash(systemctl disable --now *)"
]
```

This is close to this repo's actual `.claude/settings.local.json` (see the firewalld/SELinux/systemd docs under `linux/sysadmin/`) — deny-first means even a broad future `allow` someone adds later can't silently reopen the `ask` gate on state changes, as long as the `ask` rule stays in place.

### General development (a typical app repo)

Optimized for the edit → test → commit loop; the two commands that leave the sandbox (`push`, arbitrary `curl`) always stop:

```json
"allow": [
  "Bash(npm run test *)",
  "Bash(npm run lint)",
  "Bash(npm run build)",
  "Bash(git status)",
  "Bash(git diff *)",
  "Bash(git log *)",
  "Edit(src/**)",
  "Edit(tests/**)"
],
"ask": [
  "Bash(git commit *)",
  "Bash(npm install *)",
  "Edit(package.json)",
  "Edit(.github/workflows/**)"
],
"deny": [
  "Bash(git push *)",
  "Bash(curl *)",
  "Read(.env)",
  "Read(**/.env)",
  "Read(secrets/**)"
]
```

`Read(.env)` (bare filename, gitignore semantics) blocks it at any depth in the project — pairs with `deny: ["Bash(curl *)"]` plus a `WebFetch(domain:...)` allowlist per the curl-filtering trap above, if network access is needed at all.

### Text processing / log analysis

Almost everything here is read-only by nature (grep/awk/sed on log files, no writes), so the rule set is mostly about not needing to babysit large multi-file scans:

```json
"allow": [
  "Bash(grep *)",
  "Bash(awk *)",
  "Bash(sed -n *)",
  "Bash(rg *)",
  "Bash(jq *)",
  "Bash(yq *)",
  "Read(logs/**)",
  "Read(//var/log/**)"
],
"ask": [
  "Bash(sed -i *)"
]
```

`grep`/`awk`(via `find`-style flags)/`sed -n` are read-only in intent, but `sed -i` (in-place edit) is a real write disguised as a text-processing command — worth an explicit `ask` since it's not in Claude Code's hardcoded read-only set and a mistyped regex can silently corrupt a file.

### Database management

The sharpest edge here isn't syntax, it's the blast radius difference between a `SELECT` and anything else — worth enforcing at the permission layer, not just trusting the prompt to behave:

```json
"allow": [
  "Bash(psql -c \"SELECT *)",
  "Bash(mysql -e \"SELECT *)"
],
"ask": [
  "Bash(psql *)",
  "Bash(mysql *)",
  "Bash(pg_dump *)"
],
"deny": [
  "Bash(psql -c \"DROP *)",
  "Bash(psql -c \"TRUNCATE *)",
  "Bash(mysql -e \"DROP *)"
]
```

Treat this pattern with real suspicion, though — the curl-filtering warning applies word-for-word here: `psql -c "SELECT ... ; DROP TABLE users"` in one string, or a wrapper script, walks straight past a naive prefix match. The documented, actually-safe version of this is a `PreToolUse` hook that parses the SQL and blocks by statement type, not a `Bash(psql -c "SELECT *)` string-prefix rule — treat the rule above as a speed bump for accidental mistakes, not a security boundary against a misbehaving or adversarial request.

## Sources

- Claude Code Settings reference: code.claude.com/docs/en/settings
- Claude Code Permissions reference: code.claude.com/docs/en/permissions
