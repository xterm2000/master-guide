# MCP Servers — Connecting Claude Code to External Tools

MCP (Model Context Protocol) is an open standard that lets Claude Code call out to
external tools, databases, and APIs as if they were built-in tools. A connected
MCP server exposes a set of callable tools (named `mcp__<server>__<tool>`), and
optionally prompts (`/mcp__server__prompt`) and resources (`@server:uri`).

Connect a server when you'd otherwise be copy-pasting data into chat from another
system — an issue tracker, a monitoring dashboard, a database. Once connected,
Claude reads and acts on that system directly.

## Transports

| Transport | Use for | Notes |
|---|---|---|
| `http` | Remote cloud services (recommended default) | Supports OAuth; `streamable-http` is an accepted alias for `type` |
| `sse` | Remote services that haven't migrated to `http` | **Deprecated** — prefer `http` where available |
| `stdio` | Local processes (scripts, CLI wrappers, local servers) | Runs as a subprocess; gets `CLAUDE_PROJECT_DIR` in its env |
| `ws` | Remote services that push unsolicited events | No OAuth, no `claude mcp add --transport` shortcut — must use `add-json` |

A JSON entry with a `url` but no `type` is a config error — Claude Code assumes
stdio and silently skips it, reporting `MCP server "<name>" has a "url" but no
"type"`.

## Adding servers

```bash
# Remote HTTP (recommended for cloud services)
claude mcp add --transport http notion https://mcp.notion.com/mcp
claude mcp add --transport http secure-api https://api.example.com/mcp \
  --header "Authorization: Bearer your-token"

# Local stdio — everything after `--` goes to the server untouched
claude mcp add --env AIRTABLE_API_KEY=YOUR_KEY --transport stdio airtable \
  -- npx -y airtable-mcp-server

# Remote WebSocket — no --transport shortcut, use add-json
claude mcp add-json events-server \
  '{"type":"ws","url":"wss://mcp.example.com/socket","headers":{"Authorization":"Bearer YOUR_TOKEN"}}'
```

**Gotcha — the `--` separator matters for stdio.** Without it, Claude Code tries
to parse the server's own flags as its own options:

```bash
claude mcp add --transport stdio myserver -- npx server        # runs `npx server`
claude mcp add --env KEY=value --transport stdio myserver \
  -- python server.py --port 8080                              # KEY=value in env, runs python server.py --port 8080
```

`--env` takes multiple `KEY=value` pairs — if the server name comes immediately
after `--env`, the CLI reads it as another pair and rejects it. Put at least one
other flag between `--env` and the name.

## Real example from this machine

`/home/mitek/dev/trading/market-db/.mcp.json` — a project-scoped stdio Postgres
server, checked into that project:

```json
{
  "mcpServers": {
    "postgres": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "mcp-postgres-server"],
      "env": {
        "PG_HOST": "192.168.68.200",
        "PG_PORT": "5432",
        "PG_USER": "market",
        "PG_PASSWORD": "market",
        "PG_DATABASE": "marketdb"
      }
    }
  }
}
```

**Gotcha:** this file embeds a plaintext password. Anything committed to
`.mcp.json` is shared with everyone who clones the repo — see
[Environment variable expansion](#environment-variable-expansion) below for the
fix (`${PG_PASSWORD}` instead of the literal value).

## Credential storage for self-built stdio servers

A self-built stdio MCP server needs somewhere to keep its OAuth credentials —
client secret, refresh token, access token. Don't put those in the project
repo the server is used from, even with a `.gitignore` entry: that only works
until someone runs a broad `git add`, switches tools, or the entry gets
dropped in a refactor.

Instead, give the server its own directory outside any repo:

```
~/.config/<server-name>/
```

Put the server's own code there too, alongside its credential files, rather
than inside the project. This isn't just tidiness — a server that lives in
`~/.config/<server-name>/` has no repo to accidentally commit its credentials
into in the first place, so it doesn't depend on `.gitignore` (or on
remembering to add one) to keep secrets out of git.

## Scopes

| Scope | Loads in | Shared with team | Stored in |
|---|---|---|---|
| `local` (default) | current project only | No | `~/.claude.json`, under that project's path |
| `project` | current project only | Yes, via `.mcp.json` in repo root | `.mcp.json` |
| `user` | all your projects | No | `~/.claude.json` |

```bash
claude mcp add --transport http paypal --scope project https://mcp.paypal.com/mcp
claude mcp add --transport http hubspot --scope user https://mcp.hubspot.com/anthropic
```

**Gotcha — "local" scope here is unrelated to `.claude/settings.local.json`.**
MCP "local scope" servers live in `~/.claude.json` (your home dir). Local
*settings* live in the project's `.claude/settings.local.json`. Same word,
different files, different mechanism.

**Precedence when the same server name is defined in more than one place**
(entries are not merged — the whole entry from the highest-precedence source wins):

1. Local scope
2. Project scope
3. User scope
4. Plugin-provided servers
5. claude.ai connectors

**Project-scoped servers from `.mcp.json` require your approval** the first time
— they show as `⏸ Pending approval` in `claude mcp list` until you run `claude`
interactively and accept. This is a deliberate speed bump: a cloned repo could
otherwise silently point you at an attacker-controlled MCP server. Reset stored
approvals with `claude mcp reset-project-choices`.

**Gotcha — untrusted folders.** In a folder you haven't run `claude` in and
trusted yet, `.mcp.json` approvals recorded in `.claude/settings.json` (if
committed to git) are ignored — the server stays pending. Approvals in an
*untracked* `.claude/settings.local.json` also wait for the trust dialog, unless
the folder is your own config home. User-scope (`~/.claude/settings.json`) and
managed-settings approvals apply regardless of trust state.

## Managing servers

```bash
claude mcp list                # all configured servers + health check
claude mcp get github          # detail view for one server
claude mcp remove github
/mcp                           # within a session: status, auth, tool counts
```

`/mcp` also shows tool counts per server and flags a server that advertises
tools but exposes none.

## Environment variable expansion

`.mcp.json` supports `${VAR}` and `${VAR:-default}` in `command`, `args`, `env`,
`url`, and `headers` — this is how you keep secrets and machine-specific paths
out of a file that's checked into git:

```json
{
  "mcpServers": {
    "postgres": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "mcp-postgres-server"],
      "env": {
        "PG_HOST": "${PG_HOST:-192.168.68.200}",
        "PG_PASSWORD": "${PG_PASSWORD}"
      }
    }
  }
}
```

**Gotcha:** if a referenced variable is unset and has no default, Claude Code
does **not** fail to load — it loads the server with the literal unexpanded
`${VAR}` text and reports a warning only in `claude mcp list` output. A server
silently misconfigured this way looks connected but fails oddly. Always give
secrets a real value via shell env, not by trusting the default to save you.

## Authentication

- **OAuth (HTTP/SSE only):** run `/mcp` inside a session, or `claude mcp login
  <name>` from the shell (v2.1.186+) to authenticate without opening a session.
  `claude mcp logout <name>` clears stored credentials.
- Claude Code auto-refreshes tokens and retries once on `401`; only flags the
  server as needing re-auth in `/mcp` if the retry also fails.
- **Fixed callback port**, when a server needs a pre-registered redirect URI:
  `--callback-port 8080`.
- **Pre-configured OAuth app** (server doesn't support Dynamic Client
  Registration): `--client-id` + `--client-secret` (prompts, masked input).
- **Custom auth schemes** (Kerberos, internal SSO, short-lived tokens) —
  `headersHelper`: a shell command Claude Code runs at connect time, whose
  stdout (a JSON object of header key/value pairs) gets merged into the request
  headers:

```json
{
  "mcpServers": {
    "internal-api": {
      "type": "http",
      "url": "https://mcp.internal.example.com",
      "headersHelper": "/opt/bin/get-mcp-auth-headers.sh"
    }
  }
}
```

**Gotcha:** `headersHelper` runs arbitrary shell on every connect/reconnect —
no caching, your script owns token reuse. At project/local scope it only runs
after you accept the workspace trust dialog. It also can't reference a
plugin's `${user_config.*}` values (the command is shell-parsed, not
substituted) — put those in the static `headers` field instead.

## Practical examples

```bash
# Sentry — monitor errors
claude mcp add --transport http sentry https://mcp.sentry.dev/mcp
# then in-session: /mcp  (complete OAuth), then ask:
#   "What are the most common errors in the last 24 hours?"

# GitHub — code review workflow
claude mcp add --transport http github https://api.githubcopilot.com/mcp/ \
  --header "Authorization: Bearer YOUR_GITHUB_PAT"
#   "Review PR #456 and suggest improvements"

# Postgres — read-only analytics access
claude mcp add --transport stdio db -- npx -y @bytebase/dbhub \
  --dsn "postgresql://readonly:pass@prod.db.com:5432/analytics"
#   "Show me the schema for the orders table"
```

**Gotcha:** `claude mcp add` does not validate credentials — a placeholder
token is accepted at add time and only fails when the server actually connects.
Always confirm with `/mcp` (should show `connected`, not `failed`).

## Combining with permission rules

MCP tools are ordinary tools for the permission system — see
[04-settings-json.md](04-settings-json.md) for full rule syntax. The tool name
form is `mcp__<server>__<tool>`, so you can scope rules per-server or per-tool:

```json
{
  "permissions": {
    "allow": ["mcp__postgres__query"],
    "ask": ["mcp__github__*"],
    "deny": ["mcp__*"]
  }
}
```

Deny/ask rules accept unanchored wildcards like `mcp__*`; **allow** rules need
the fully anchored `mcp__<server>__*` form (bare `mcp__*` won't work as an
allow rule — this mirrors the general tool-name wildcard asymmetry documented
in 04-settings-json.md).

## MCP output limits

- Warns above 10,000 tokens of tool output; hard caps at 25,000 by default.
- Raise with `MAX_MCP_OUTPUT_TOKENS=50000` — useful for servers that return
  full schemas, large log slices, or big datasets.
- A server author can exempt one tool from the environment-variable cap by
  setting `_meta["anthropic/maxResultSizeChars"]` in its `tools/list` entry
  (text content only, capped at 500,000 chars regardless).

## Tool search (context scaling)

With many MCP servers connected, tool *definitions* are deferred by default —
only names and server instructions load at session start, and Claude searches
for a tool's full schema when a task needs it. This is why adding more servers
doesn't blow up your context window. If a server's tools should always be
resident (used on nearly every turn), mark it in `.mcp.json`:

```json
{
  "mcpServers": {
    "core-tools": {
      "type": "http",
      "url": "https://mcp.example.com/mcp",
      "alwaysLoad": true
    }
  }
}
```

**Gotcha:** `alwaysLoad: true` blocks session startup until that server
connects (capped at 5s) — only use it for a small, genuinely always-needed set.

## Reserved server names

`workspace`, `claude-in-chrome`, `computer-use`, `Claude Preview`, and
`Claude Browser` are reserved for Claude Code's built-ins. `claude mcp add`
rejects these outright; a reserved name found in a config file is silently
skipped with a warning.

## Sources

- MCP reference: code.claude.com/docs/en/mcp
- MCP quickstart: code.claude.com/docs/en/mcp-quickstart
- Permissions reference: code.claude.com/docs/en/permissions
- Managed MCP configuration: code.claude.com/docs/en/managed-mcp
