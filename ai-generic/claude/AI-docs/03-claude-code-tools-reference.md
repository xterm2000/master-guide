# Claude Code Built-in Tools — Reference

Claude Code ships with ~35 built-in tools. Skill frontmatter (`allowed-tools`, `disallowed-tools`), subagent definitions (`tools`, `disallowedTools`), permission settings, and hook `matcher` fields all reference these exact names — so knowing the full list matters even if Claude usually picks the right one on its own.

## File I/O

|Tool|Does|
|---|---|
|`Read`|Read file contents. Handles plain text, images, PDFs (paged past 10 pages), Jupyter notebooks. Returns line numbers.|
|`Write`|Create or overwrite a file. Must `Read` an existing file first, or the write fails.|
|`Edit`|Exact string replacement (`old_string` → `new_string`). No regex. Requires prior `Read` and a unique match.|
|`NotebookEdit`|Cell-level edits to `.ipynb` files by `cell_id`: `replace`, `insert`, or `delete`.|
|`Glob`|Find files by name pattern (`**/*.ts`). Sorted by mtime, capped at 100 results.|
|`Grep`|ripgrep-backed content search. Modes: `files_with_matches`, `content`, `count`.|

```jsonc
// Skill frontmatter: pre-approve read-only tools, block writes
---
name: audit-only
allowed-tools: Read, Grep, Glob
disallowed-tools: Write, Edit, Bash
---
```

```bash
# Permission rules (settings.json or /permissions)
"allow": ["Read(src/**)", "Grep(src/**)"]
"deny": ["Edit(/secrets/**)", "Write(/secrets/**)"]
```

## Execution

|Tool|Does|
|---|---|
|`Bash`|Shell commands in a persistent session. 2-min default timeout (up to 10 min), 30k-char default output cap (up to 150k).|
|`PowerShell`|Native PowerShell. Auto on Windows without Git Bash; opt-in elsewhere via `CLAUDE_CODE_USE_POWERSHELL_TOOL=1`.|
|`LSP`|Language-server code intelligence: go-to-definition, find references, type errors, symbol search.|

```bash
# Bash permission rule — allow test/build commands, deny destructive ones
"allow": ["Bash(npm run test)", "Bash(npm run build)"]
"deny": ["Bash(rm -rf *)"]
```

```json
// settings.json — raise Bash timeout/output ceilings
{
  "env": {
    "BASH_DEFAULT_TIMEOUT_MS": "300000",
    "BASH_MAX_OUTPUT_LENGTH": "150000",
    "CLAUDE_CODE_USE_POWERSHELL_TOOL": "1"
  }
}
```

## Web

|Tool|Does|
|---|---|
|`WebFetch`|Fetch a URL + extraction prompt; runs a small model over the Markdown-converted page. Lossy by design — result reflects the prompt, not the raw page.|
|`WebSearch`|Query-only, returns titles/URLs, doesn't fetch pages. Up to 8 internal refinement searches per call.|

```jsonc
// Pre-approve a domain so WebFetch doesn't prompt
"allow": ["WebFetch(domain:docs.internal.co)"]
```

```text
# Typical two-step pattern Claude follows
WebSearch("latest React 19 breaking changes")
WebFetch(url="https://react.dev/blog/...", prompt="List breaking changes in React 19")
```

## Interaction / control flow

|Tool|Does|
|---|---|
|`AskUserQuestion`|Multiple-choice clarifying questions. No idle timeout by default; configurable via `askUserQuestionTimeout`.|
|`EnterPlanMode` / `ExitPlanMode`|Switch into read-only plan mode; present the plan for approval to exit.|
|`EnterWorktree` / `ExitWorktree`|Create/switch into an isolated git worktree, or return to the original directory.|

```javascript
// AskUserQuestion call shape
await AskUserQuestion({
  questions: [{
    question: "Which deployment strategy should we use?",
    header: "Strategy",
    options: [
      { label: "Blue-Green", description: "Zero-downtime, full infra duplication" },
      { label: "Rolling", description: "Gradual instance replacement" },
      { label: "Canary", description: "Deploy to a small subset first" }
    ],
    multiSelect: false
  }]
});
```

```json
// Auto-continue an idle AskUserQuestion dialog after 5 minutes
{ "askUserQuestionTimeout": "5m" }
```

## Sub-agents & orchestration

|Tool|Does|
|---|---|
|`Agent`|Spawn a subagent with its own context window (or a forked subagent that inherits the parent's). Cap turns with `maxTurns`.|
|`SendMessage`|Message an agent-team teammate, or resume a stopped subagent by ID/name.|
|`Workflow`|Run a dynamic workflow script that orchestrates many subagents in the background, returning one consolidated result.|

```javascript
// Launch a research subagent
{
  "subagent_type": "general-purpose",
  "description": "Find auth implementation",
  "prompt": "Search the codebase for where user authentication is implemented (login, JWT, sessions). Return file paths and a summary."
}
```

```yaml
# .claude/agents/reviewer.md frontmatter — restrict subagent tool access
---
name: reviewer
tools: Read, Grep, Glob
maxTurns: 15
---
```

## Task tracking

|Tool|Does|
|---|---|
|`TaskCreate` / `TaskGet` / `TaskList` / `TaskUpdate`|Structured task-list CRUD — the current default.|
|`TaskOutput` / `TaskStop`|Read output from, or stop, a running background task.|
|`TodoWrite`|Older flat checklist tool. **Disabled by default since v2.1.142** in favor of the `Task*` set. Re-enable with `CLAUDE_CODE_ENABLE_TASKS=0`.|

```javascript
// TaskCreate example
{ "title": "Refactor auth middleware", "status": "pending" }
```

```bash
# Re-enable legacy TodoWrite instead of Task* tools
CLAUDE_CODE_ENABLE_TASKS=0 claude
```

## Scheduling

|Tool|Does|
|---|---|
|`CronCreate` / `CronDelete` / `CronList`|Manage recurring or one-shot scheduled prompts within a session.|
|`ScheduleWakeup`|Reschedules the next iteration of a self-paced `/loop` (1 min–1 hr out), or stops the loop with `stop: true`.|

```javascript
// CronCreate — nightly dependency check
{ "schedule": "0 3 * * *", "prompt": "Run npm audit and report new vulnerabilities" }
```

## Monitoring

|Tool|Does|
|---|---|
|`Monitor`|Watches a background command's output line-by-line, or a WebSocket feed, and interjects on events. Not available on Bedrock/Vertex/Foundry.|

```javascript
// Tail a log and flag errors
{ "command": "tail -f server.log", "description": "Watch for errors" }

// Or watch a WebSocket feed
{ "ws": { "url": "wss://ci.example.com/events" } }
```

## Output/delivery

|Tool|Does|
|---|---|
|`Artifact`|Publish HTML/Markdown as a claude.ai artifact. Requires Pro/Max/Team/Enterprise + `/login`.|
|`SendUserFile`|Push a generated file to your device. Requires Remote Control or a managed cloud session.|
|`PushNotification`|Desktop notification, plus mobile push if Remote Control is connected.|
|`ShareOnboardingGuide`|Uploads `ONBOARDING.md`, returns a share link (called from `/team-onboarding`).|
|`RemoteTrigger`|Create/run/list Routines on claude.ai. Backs `/schedule`.|
|`ReportFindings`|Structured code-review findings (file, summary, failure scenario, optional `category`).|

```javascript
// SendUserFile with inline rendering
{ "path": "./report.pdf", "caption": "Q3 audit results", "display": "render" }
```

## MCP-related

|Tool|Does|
|---|---|
|`ListMcpResourcesTool` / `ReadMcpResourceTool`|List / read resources exposed by connected MCP servers.|
|`ToolSearch`|Lazily search and load deferred MCP tools when tool search is enabled.|
|`WaitForMcpServers`|Wait for MCP servers still connecting in the background (only shown when `ToolSearch` is off).|

## Meta

|Tool|Does|
|---|---|
|`Skill`|Executes a skill (including built-ins like `/code-review`) within the main conversation.|

```bash
# Skill permission rule — restrict which skills Claude can auto-invoke
"allow": ["Skill(commit)", "Skill(review-pr)"]
"deny": ["Skill(deploy *)"]   # force manual invocation only
```

## Permission rule format cheat sheet

|Rule format|Applies to|
|---|---|
|`Bash(npm run *)`|`Bash`, `Monitor`|
|`PowerShell(Get-ChildItem *)`|`PowerShell`|
|`Read(~/secrets/**)`|`Read`, `Grep`, `Glob`, `LSP`|
|`Edit(/src/**)`|`Edit`, `Write`, `NotebookEdit` (also grants matching `Read` access)|
|`Skill(deploy *)`|`Skill`|
|`Agent(Explore)`|`Agent`|
|`WebFetch(domain:example.com)`|`WebFetch`|
|`WebSearch`|`WebSearch` — no specifier, allow/deny as a whole|

Tools not listed above (e.g. `ExitPlanMode`, `ShareOnboardingGuide`) accept only the bare tool name, no specifier.

```bash
# Check what's actually loaded in your running session
> What tools do you have access to?
# For exact MCP tool names:
> /mcp
```

## Worked example: triaging an Oracle blocking session end-to-end

A user pastes `v$session` output showing a stuck SID and asks who's blocking whom. This walks that one request through seven tools across six categories — the same `oracle-lock-triage` skill from [claude-skills-reference.md](01-claude-skills-reference.md#worked-example-dummy-oracle-lock-triage-skill), traced through the tools it actually calls.

1. **`TaskCreate`** — track the investigation as a discrete unit of work.
    
    ```javascript
    { "title": "Triage blocking session SID 452 on instance 2", "status": "in_progress" }
    ```
    
2. **`Skill`** — the skill sets `disable-model-invocation: true`, so it has to be invoked by name, not auto-triggered.
    
    ```
    /oracle-lock-triage 452 2
    ```
    
3. **`Agent`** — the skill's `context: fork` runs it as an isolated subagent instead of inline.
    
    ```javascript
    {
      "subagent_type": "general-purpose",
      "description": "Diagnose SID 452 blocking chain",
      "prompt": "Query v$session/gv$session for SID 452 on instance 2, reconstruct the blocking chain, pull ASH/AWR if it already cleared."
    }
    ```
    
4. **`Bash`** — the subagent queries the database, but permission rules scoped to this skill keep it read-only.
    
    ```bash
    "allow": ["Bash(sqlplus -S /nolog @sql/diagnostics/*.sql)"]
    "deny": ["Bash(sqlplus -S /nolog @sql/prod/kill_session.sql)"]
    ```
    
5. **`Monitor`** — if the block is still active, tail the alert log instead of polling.
    
    ```javascript
    { "command": "tail -f /u01/app/oracle/diag/rdbms/prod/alert_prod.log", "description": "Watch for ORA-00060 deadlock entries" }
    ```
    
6. **`ReportFindings`** — once root cause is identified, return a structured result instead of prose.
    
    ```javascript
    {
      "file": "sql/diagnostics/blocking_chain.sql",
      "summary": "SID 452 blocked by SID 210 holding a TM lock from an unindexed FK on ORDERS",
      "failure_scenario": "Bulk delete on ORDERS without an index on the child FK column escalates to a full-table TM lock, blocking unrelated inserts"
    }
    ```
    
7. **`AskUserQuestion`** — before generating the kill script, get explicit sign-off on scope.
    
    ```javascript
    {
      "questions": [{
        "question": "SID 210 is the blocker. Kill it now or just hand you the script?",
        "header": "Remediation",
        "options": [
          { "label": "Kill it now", "description": "Runs ALTER SYSTEM KILL SESSION immediately" },
          { "label": "Just give me the script", "description": "Writes the script, you run it" }
        ],
        "multiSelect": false
      }]
    }
    ```
    

The two checkpoints that matter here are steps 2 and 7: `disable-model-invocation` stops Claude from deciding on its own that a session "looks stuck" and launching triage, and `AskUserQuestion` stops it from ever running a kill script without a second, explicit confirmation — diagnosis stays autonomous, the destructive action doesn't.

## Sources

- Claude Code Tools reference: code.claude.com/docs/en/tools-reference
