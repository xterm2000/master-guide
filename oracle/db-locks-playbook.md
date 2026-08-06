# Oracle Database Lock Contention: Step-by-Step Triage Playbook

_Consolidated from `db-locks-final.md` and `db-locks-rac.md`. This version is deliberately **root-cause agnostic**: the earlier docs were written around one incident (an invalid `NBC_APPS` trigger caused by a permissions reset) and treated that as *the* cause. Permissions were fixed, the trigger recompiled clean — and the locks came back anyway. So this guide walks the general "what's blocking what, and why" path first, and only branches into trigger/permission checks as **one possible finding**, not the starting assumption._

All queries:
- Use `gv$` (global) views instead of `v$`. On RAC this shows locks/sessions/SQL across every instance in the cluster; on a single-instance database `gv$` behaves identically to `v$` (just with an extra `inst_id` column), so it's a safe default everywhere. This also means it's the RAC version — there's no separate non-RAC variant to maintain.
- Use short table aliases (`s`, `o`, `lo`, `p`, `t`, `q`, `h`, `e`...) instead of full names in column references, so you can type `alias.` and let autocomplete show you the available columns instead of guessing exact names.
- Join `inst_id` explicitly wherever a `gv$` view is joined to another `gv$` view — `sid` alone is **not** unique cluster-wide, only `(inst_id, sid)` is. This was missing in the earlier RAC doc's join conditions; on a cluster with more than one instance it can silently mismatch rows.

---

## Table of Contents

1. [[#1. Triage: Is There a Lock Problem Right Now?|Triage: Is There a Lock Problem Right Now?]]
2. [[#2. Who's Locked, Who's Blocking?|Who's Locked, Who's Blocking?]]
3. [[#3. What Is the Blocker Actually Running?|What Is the Blocker Actually Running?]]
4. [[#4. Trace an Unknown SQL_ID Back to Its Source|Trace an Unknown SQL_ID Back to Its Source]]
5. [[#5. Branch: Why Is the Blocker Holding the Lock?|Branch: Why Is the Blocker Holding the Lock?]]
6. [[#6. Reconstructing a Past Incident (ASH)|Reconstructing a Past Incident (ASH)]]
7. [[#7. Remediation, by Root Cause|Remediation, by Root Cause]]
8. [[#8. Verification|Verification]]
9. [[#9. Executive Summary Query|Executive Summary Query]]
10. [[#10. Appendix: The NBC_APPS/ONAIR Case Study|Appendix: The NBC_APPS/ONAIR Case Study]]

---

## 1. Triage: Is There a Lock Problem Right Now?

Start here, every time. This tells you whether you're even looking at a lock problem before you go hunting for one.

```sql
-- What's happening RIGHT NOW?
SELECT s.event,
       s.wait_class,
       COUNT(*)                          AS num_sessions,
       ROUND(AVG(s.seconds_in_wait), 2)  AS avg_wait_sec,
       MAX(s.seconds_in_wait)            AS max_wait_sec
  FROM gv$session s
 WHERE s.wait_class != 'Idle'
   AND s.type       = 'USER'
 GROUP BY s.event, s.wait_class
 ORDER BY num_sessions DESC;
```

**What to look for:**

- `wait_class = 'Concurrency'` or `'Application'` with a big `num_sessions` → lock contention (`enq: TX`, `enq: TM`, `library cache pin`, `library cache lock` all fall here).
- Don't assume it's row-lock contention specifically — `library cache` waits point at object compilation, not row locks, and need a different fix.
- High `avg_wait_sec` relative to `max_wait_sec` means it's sustained across many sessions, not one outlier.

If this comes back clean (no `Concurrency`/`Application` wait classes with real volume), the problem isn't a lock — look at `wait_class = 'User I/O'` or CPU instead.

---

## 2. Who's Locked, Who's Blocking?

**Query: Currently Locked Objects**

```sql
SELECT o.owner,
       o.object_name,
       lo.object_id,
       s.inst_id,
       s.sid,
       s.username,
       s.osuser,
       p.spid,
       s.event,
       s.seconds_in_wait
  FROM sys.dba_objects       o,
       sys.gv_$locked_object lo,
       sys.gv_$session       s,
       sys.gv_$process       p
 WHERE o.object_id = lo.object_id
   AND s.sid       = lo.session_id
   AND s.inst_id   = lo.inst_id
   AND p.addr      = s.paddr
   AND p.inst_id   = s.inst_id
 ORDER BY s.seconds_in_wait DESC;
```

**What to look for:**

- `seconds_in_wait > 60` on a session that's blocking others = worth investigating now.
- Same `username`/`sid` locking many objects = batch job, trigger cascade, or a single long transaction.

**Query: Lock Summary by User**

For a quick "who's the worst offender" rollup instead of reading every row above.

```sql
WITH lock_details AS (
  SELECT o.object_name,
         s.sid,
         s.username,
         s.event,
         s.seconds_in_wait
    FROM sys.dba_objects       o,
         sys.gv_$locked_object lo,
         sys.gv_$session       s
   WHERE o.object_id = lo.object_id
     AND s.sid       = lo.session_id
     AND s.inst_id   = lo.inst_id
)
SELECT d.username,
       COUNT(DISTINCT d.sid)                                                        AS num_sessions,
       COUNT(DISTINCT d.object_name)                                                AS num_objects_locked,
       LISTAGG(DISTINCT d.object_name, ', ') WITHIN GROUP (ORDER BY d.object_name)   AS objects_locked,
       MAX(d.seconds_in_wait)                                                       AS max_wait_sec,
       MAX(d.event) KEEP (DENSE_RANK LAST ORDER BY d.seconds_in_wait)                AS event_at_max_wait
  FROM lock_details d
 GROUP BY d.username
 ORDER BY num_sessions DESC, max_wait_sec DESC;
```

The earlier version of this query used `MAX(event)` to show "the" event a user's sessions were waiting on — but `MAX()` on a string picks whichever event sorts alphabetically last, not the one associated with the longest wait. `KEEP (DENSE_RANK LAST ORDER BY seconds_in_wait)` actually ties the event to the row with the max wait time.

**Query: Blocking Chain — Who Blocks Whom?**

Generalized from the earlier version — it no longer hardcodes `enq: TX - row lock contention`, so it also catches `library cache` and `TM` blocking, which is exactly the kind of thing the earlier trigger incident produced upstream of the row lock.

```sql
SELECT b.inst_id           AS blocker_inst,
       b.sid               AS blocker_sid,
       b.username          AS blocker_user,
       b.machine           AS blocker_machine,
       b.seconds_in_wait   AS blocker_hold_time_sec,
       w.inst_id           AS blocked_inst,
       w.sid               AS blocked_sid,
       w.username          AS blocked_user,
       w.seconds_in_wait   AS blocked_wait_sec,
       w.event             AS blocked_on_event
  FROM gv$session b,
       gv$session w
 WHERE b.sid       = w.blocking_session
   AND b.inst_id   = w.blocking_instance
   AND w.wait_class != 'Idle'
 ORDER BY b.seconds_in_wait DESC;
```

**What to look for:**

- One `blocker_sid` appearing repeatedly with many distinct `blocked_sid` rows = root blocker.
- Check `blocked_on_event` — if it varies (`enq: TX`, `library cache pin`, `cursor: pin S`), the blocker is choking multiple subsystems at once, which usually means an object compile/invalidate event, not plain row contention.

**Query: What Object/Row Is Each Blocked Session Actually Waiting On?**

`gv$locked_object` only shows objects a session currently *holds* a lock on — it says nothing about what a *blocked* session is waiting to acquire. `row_wait_obj#`/`row_wait_row#` on the blocked session itself answers that directly, and is often the fastest way to find the true root blocker in a multi-hop chain (a session can appear to be "blocking" one thing while itself waiting on a lock held further upstream — join `gv$session` to itself repeatedly to walk that chain, or just check whether the apparent blocker has `blocking_session IS NOT NULL` too).

```sql
SELECT w.inst_id,
       w.sid                AS blocked_sid,
       w.blocking_session,
       w.blocking_instance,
       w.row_wait_obj#,
       o.owner              AS waited_on_owner,
       o.object_name        AS waited_on_object,
       w.row_wait_row#,
       w.seconds_in_wait
  FROM gv$session w
  LEFT JOIN dba_objects o ON o.object_id = w.row_wait_obj#
 WHERE w.event = 'enq: TX - row lock contention'
 ORDER BY w.seconds_in_wait DESC;
```

**What to look for:**

- `waited_on_owner` belonging to a *different* schema than the blocked session's own username — that's the tell for a cross-schema dependency (e.g. an app session on schema A queued up on a row it never explicitly touched, because something fired against schema B's table inside the same call).
- If the session named in `blocking_session`/`blocking_instance` for that row itself shows `blocking_session IS NOT NULL` elsewhere in this same result set, it isn't the root — walk up the chain until you find the session with `blocking_session IS NULL`. That's the one actually holding the lock everyone else is waiting on; killing an intermediate link just reshuffles the queue.

---

## 3. What Is the Blocker Actually Running?

Once you have the blocker's `sid`/`inst_id`, find its SQL.

**Query: Find Running Query by Session/User**

```sql
SELECT s.inst_id,
       s.sid,
       s.serial#,
       s.username,
       s.sql_id,
       s.sql_child_number,
       s.sql_exec_start,
       q.optimizer_mode,
       q.sql_text
  FROM gv$session s
  JOIN gv$sql q
    ON q.sql_id       = s.sql_id
   AND q.child_number = s.sql_child_number
   AND q.inst_id      = s.inst_id
 WHERE s.username = :username;   -- swap in the suspect username, or drop the filter to see everyone cluster-wide
```

Joins on `sql_id` + `child_number` (the exact cursor Oracle is running) instead of `hash_value`/`address` — that pairing is the pre-10g way of identifying a cursor and both columns are only guaranteed unique together with `inst_id` on RAC; `sql_id`/`child_number` is the direct, indexed identifier and also avoids matching the wrong child cursor when a statement has multiple execution plans.

**Query: Lock Detail by SID, With SQL Text**

For when you already have candidate SIDs from Section 2 and want tables + SQL in one shot.

```sql
WITH lock_details AS (
  SELECT s.inst_id,
         s.sid,
         s.serial#,
         s.username,
         s.event,
         s.seconds_in_wait,
         s.sql_id,
         s.command,
         lo.object_id,
         o.object_name
    FROM gv$locked_object    lo,
         gv$session          s,
         sys.dba_objects     o
   WHERE s.sid     = lo.session_id
     AND s.inst_id = lo.inst_id
     AND o.object_id = lo.object_id
)
SELECT d.inst_id,
       d.sid,
       d.sql_id,
       MAX(q.sql_text)                  AS sql_statement,
       d.command,
       COUNT(DISTINCT d.object_name)    AS num_tables_locked,
       MAX(d.seconds_in_wait)           AS max_wait_sec,
       d.event
  FROM lock_details d
  LEFT JOIN gv$sql q
    ON q.sql_id       = d.sql_id
   AND q.inst_id      = d.inst_id
   AND q.child_number = 0
 GROUP BY d.inst_id, d.sid, d.sql_id, d.command, d.event
 ORDER BY max_wait_sec DESC;
```

The original version pulled `sql_text` via a `ROWNUM = 1` correlated subquery per output row — that's a nested-loop probe of `gv$sql` for every group, with no `ORDER BY` so it's picking an arbitrary child cursor. The `LEFT JOIN ... child_number = 0` version is set-based (one hash join against `gv$sql`, not one execution per row) and deterministic about which child cursor's text it reads.

If `sql_text` is `NULL` here, the SQL has already aged out of the shared pool — jump to [[#6. Reconstructing a Past Incident (ASH)|Section 6]] to pull it from AWR/ASH history instead.

**Query: Is This the Blocker's Normal Plan? (SQL Profile / Plan Stability Check)**

Finding the blocker's SQL text is not enough — the same `sql_id` can run under different execution plans over time, and a stale `DBMS_SQLTUNE`-style SQL Profile snapping back into effect can silently swap a cheap plan for an expensive one, turning a normally-instant statement into one that holds its lock for minutes. Always check this once you have a suspect `sql_id`, even if the query "looks fine."

```sql
-- Is a SQL Profile attached, and when was it last touched?
SELECT p.name, p.category, p.status, p.created, p.last_modified
  FROM dba_sql_profiles p
 WHERE p.signature IN (SELECT q.exact_matching_signature
                          FROM gv$sql q
                         WHERE q.sql_id = :sql_id);

-- Has the plan flipped over time? Multiple plan_hash_values = plan instability.
SELECT h.plan_hash_value, COUNT(*) cnt, MIN(h.timestamp) first_seen, MAX(h.timestamp) last_seen
  FROM dba_hist_sql_plan h
 WHERE h.sql_id = :sql_id
 GROUP BY h.plan_hash_value
 ORDER BY last_seen DESC;

-- Current cursor: which plan is it on right now, and how expensive is each execution?
SELECT s.sql_id, s.plan_hash_value, s.executions,
       s.buffer_gets, ROUND(s.buffer_gets / NULLIF(s.executions,0)) gets_per_exec,
       s.elapsed_time/1000000 elapsed_sec, s.last_load_time
  FROM gv$sql s
 WHERE s.sql_id = :sql_id;
```

What to look for:
- A profile whose `last_modified` lands right at (or just before) the incident window is a strong signal — something (an SPM evolve task, a re-run tuning script, a DBA re-applying an old fix) just re-pinned a plan.
- Compare `plan_hash_value` counts/date ranges from the second query against the pinned plan from the first. If the *unpinned* plan has been running for months with a low `gets_per_exec` and the *profile's* plan hasn't been seen since it was created, the profile was effectively dormant — until it wasn't.
- A pinned plan that was fine when created can become a liability months later once data volumes grow (e.g. a `HASH JOIN` full-scan over a table that's since grown from thousands to millions of rows) — a SQL Profile has no expiry and does not adapt to volume growth the way a fresh hard parse would.
- Don't stop at "a cross-schema trigger wrote to the locked object" — confirm the trigger's own query is running its *normal* plan. A trigger that's always been slow is a design problem; a trigger that suddenly got 100x slower today is very likely a plan regression, and the trigger is just the messenger.

---

## 4. Trace an Unknown SQL_ID Back to Its Source

Use this when the blocking SQL isn't obviously "yours" — you don't recognize it as belonging to a known app, script, or trigger.

**Step 1 — Session metadata.** Oracle records the client program, machine, and app module against every session.

```sql
SELECT s.sql_id, s.program, s.module, s.action, s.machine, s.osuser
  FROM gv$session s
 WHERE s.sql_id = '&sql_id';
```

If it already flushed out of `gv$session`, go historical:

```sql
SELECT DISTINCT h.sql_id, h.program, h.module, h.action, h.machine
  FROM dba_hist_active_sess_history h
 WHERE h.sql_id = '&sql_id';
```

`program` tells you the literal client (`w3wp.exe`, `java.exe`, `plsqldev.exe`...). `module`/`action` are populated by frameworks (Hibernate, .NET, Oracle Forms) with the class/page/function name.

**Step 2 — Native SQL or PL/SQL object?**

```sql
SELECT q.sql_id, q.program_id, q.program_line#
  FROM gv$sql q
 WHERE q.sql_id = '&sql_id';
```

- `program_id = 0` → SQL comes straight from outside the database (hardcoded in app code, or ad hoc). Go to Step 4.
- `program_id > 0` → SQL is embedded in a database object. Go to Step 3.

**Step 3 — Identify the object.**

```sql
SELECT o.owner, o.object_name, o.object_type
  FROM dba_objects o
 WHERE o.object_id = &program_id;
```

- `object_type = TRIGGER` → fired by a trigger hook.
- `object_type = PACKAGE BODY` / `PROCEDURE` → jump to `program_line#` from Step 2 in that object's source.

**Step 4 — Text search (if `program_id` was 0).**

Pull a unique fragment of the SQL text and grep your app repos:

```
git grep "unique_sql_fragment"
grep -ri "unique_sql_fragment" /path/to/your/apps/
```

```
[Find Rogue SQL_ID]
        │
        ▼
[Query GV$SESSION / ASH] ──► Inspect MACHINE, PROGRAM, MODULE
        │
        ▼
  [Check GV$SQL] ──► Is PROGRAM_ID > 0?
        │
        ├──► YES ──► Query DBA_OBJECTS → Trigger / Procedure / Package name → Section 5
        │
        └──► NO  ──► Grep app/Git repos for a unique text fragment
```

---

## 5. Branch: Why Is the Blocker Holding the Lock?

This is the step the earlier docs skipped past — they jumped straight to "it's the trigger." Once you know *what* is blocking (Section 3/4), work out *why it's still holding the lock* before you touch anything. Common causes, roughly in order of how often they show up:

**A. The blocking object is invalid or erroring** (this was the original incident's cause)

```sql
SELECT o.owner, o.object_name, o.object_type, o.status, o.last_ddl_time
  FROM dba_objects o
 WHERE o.object_id = &program_id;   -- from Section 4, Step 3

SELECT e.owner, e.name, e.type, e.line, e.position, e.text
  FROM dba_errors e
 WHERE e.owner = :owner
   AND e.name  = :object_name
 ORDER BY e.line;
```

`status = 'INVALID'` + rows in `dba_errors` mentioning "insufficient privileges" → check grants next.

**B. Missing/changed privileges** on objects the blocker's code touches

```sql
SELECT p.grantee, p.owner AS table_owner, p.table_name, p.privilege
  FROM dba_tab_privs p
 WHERE p.grantee = :grantee
   AND p.owner   = :table_owner
 ORDER BY p.table_name, p.privilege;
```

`dba_tab_privs` has no `table_owner` column — the table's schema is just `owner`. Alias it as `table_owner` in the output if that's the label you want, but filter/join on `owner`.

Empty or partial result for tables the object's source references (see the source-dump query below) = privilege gap.

```sql
SELECT s.owner, s.name, s.line, s.text
  FROM dba_source s
 WHERE s.owner = :owner
   AND s.name  = :object_name
   AND s.type  = :object_type   -- e.g. 'TRIGGER', 'PACKAGE BODY'
 ORDER BY s.line;
```

**C. A session is sitting on an open transaction without committing/rolling back** — this is the pattern that bit the original incident even *after* the trigger was fixed: the client got an error and never issued `ROLLBACK`.

```sql
SELECT s.inst_id,
       s.sid,
       s.username,
       s.status,
       s.last_call_et                                              AS idle_sec,
       t.start_time                                                AS txn_start,
       ROUND((SYSDATE - TO_DATE(t.start_time, 'MM/DD/RR HH24:MI:SS')) * 86400)  AS txn_age_sec,
       t.used_ublk,
       t.used_urec
  FROM gv$session     s
  JOIN gv$transaction t
    ON t.ses_addr = s.saddr
   AND t.inst_id  = s.inst_id
 ORDER BY txn_age_sec DESC;
```

`gv$transaction.start_time` is a formatted string, not a `DATE` — sorting by it directly (as the original did) sorts lexically, so `'10/01/24 ...'` incorrectly comes before `'02/15/24 ...'` once the month crosses into double digits. Converting with `TO_DATE` and deriving `txn_age_sec` gives both a correct sort and the actual elapsed time, instead of making you eyeball a timestamp string.

`status = 'INACTIVE'` with a large `idle_sec` and a large `txn_age_sec` = client-side bug (app didn't commit/rollback, connection pool leaked a transaction, or a developer left a session open). This has nothing to do with the object being valid or not.

**E. A cross-schema trigger is writing to the locked object on the caller's behalf** — the blocker's own SQL text (Section 3) won't mention the locked object at all if this is what's happening, because the calling session never explicitly touches it; a trigger owned by a *different* schema does, riding along inside the caller's transaction. This is easy to miss because every query up to this point still looks like "session X is stuck," not "session X is unknowingly holding schema Y's lock."

```sql
-- Confirm: does the blocker's own statement reference the locked object at all?
-- (Compare against the sql_text pulled in Section 3 — if it's silent on the object
-- from Section 2's row_wait_obj# query, something else is writing to it.)

-- Find what writes to the locked object, regardless of who owns the caller's code
SELECT d.owner, d.name, d.type, d.referenced_owner, d.referenced_name
  FROM dba_dependencies d
 WHERE d.referenced_name  = :locked_object_name
   AND d.referenced_owner = :locked_object_owner
   AND d.type IN ('TRIGGER','PROCEDURE','PACKAGE BODY','FUNCTION')
 ORDER BY d.owner, d.type, d.name;

-- For any TRIGGER hits: find what table it actually fires on (often a table in the
-- CALLER's schema, not the locked object's schema — that's the synchronous coupling)
SELECT t.owner, t.trigger_name, t.table_owner, t.table_name, t.triggering_event, t.status
  FROM dba_triggers t
 WHERE t.owner = :trigger_owner
   AND t.trigger_name = :trigger_name;

-- Read the trigger body to confirm it writes the locked object, and check whether
-- it has its own commit boundary (PRAGMA AUTONOMOUS_TRANSACTION) or just inherits
-- whatever transaction the firing table's DML happened to be part of
SELECT s.line, s.text
  FROM dba_source s
 WHERE s.owner = :trigger_owner
   AND s.name  = :trigger_name
 ORDER BY s.line;
```

**What to look for:**

- `dba_dependencies` returns a `TRIGGER` owned by a schema other than the one the blocked/blocking session connects as, and `dba_triggers` shows that trigger's `table_owner`/`table_name` sitting in the *caller's* schema — that's proof the write to the locked object is a side effect of the caller's own DML, not something the caller's code does directly. Cite the three results together (locked object from Section 2, trigger firing table matching the caller's actual statement from Section 3, trigger body containing a write to the locked object) as the causal chain — each one alone is circumstantial, together they're conclusive.
- No `PRAGMA AUTONOMOUS_TRANSACTION` in the trigger body means it holds the caller's row lock for as long as the caller's transaction stays open afterward, regardless of what the trigger itself does — a caller doing unrelated work after the triggering DML (another query, a report, anything) before committing extends the lock accordingly, even though nothing is wrong with the trigger itself.
- If the object was recently recreated (check `dba_objects.created`/`last_ddl_time` on the locked object), also verify its indexes/constraints came back intact (`dba_indexes`/`dba_constraints`) and that stats aren't stale (`dba_tab_statistics.last_analyzed`) — a rebuild that silently dropped an index turns the trigger's normally-instant write into a full scan held under lock for the whole scan duration.

**D. Legitimate contention, no bug** — many sessions genuinely racing to update the same row/block (hot row). Look at whether the blocked sessions are all different users hitting the same key (e.g., a shared sequence/counter row) rather than one blocker cascading. This is a data-model/capacity issue, not something recompiling a trigger will fix.

**F. The trigger's lock is fine — the caller's transaction just won't close because a *later, unrelated* statement in the same session regressed.** This is the trap E's last bullet warns about, made concrete: proving a cross-schema trigger wrote the locked row only explains how the lock got there, not why it's still held five minutes later. Don't stop at E — confirm what the blocking session is doing *right now*, even if it has nothing to do with the locked object.

```sql
-- What is the blocking session executing at this exact moment? (reuse Section 3's query,
-- but the point here is to run it again *after* confirming cause E, not instead of it)
SELECT s.inst_id, s.sid, s.serial#, s.sql_id, s.sql_exec_start, s.program,
       ROUND((SYSDATE - s.sql_exec_start) * 86400) AS running_sec
  FROM gv$session s
 WHERE s.sid = :blocker_sid AND s.inst_id = :blocker_inst_id;

-- Then run Section 3's SQL Profile / Plan Stability Check against THAT sql_id,
-- regardless of whether it touches the locked table. A session's row locks live
-- for the life of the transaction, not the life of the statement that acquired them.
```

**What to look for:**

- The `sql_id` currently running in the blocker has been executing far longer (`running_sec`) than its own history would suggest — cross-check against Section 3's plan-stability query even if this statement never references the locked object at all.
- If the current SQL is a reporting/aggregate/companion query (e.g. against `TMP_`/GTT staging tables) that looks unrelated to the incident, resist the urge to file it as a separate, lower-priority observation — in the *same session*, it is not separate. It is the reason the transaction, and therefore the trigger's lock from cause E, hasn't committed yet.
- Don't treat "what wrote to the locked row" (cause E) and "why hasn't this transaction ended" (cause F) as the same question — they need different evidence (trigger dependency chain vs. current-statement plan/duration) and a real incident can need both before the chain of custody is complete.

Don't stop at the first plausible cause — confirm with data (B fixed the compile error last time, but C is what let the locks recur with a *healthy* trigger). Re-run Section 1's triage query after any fix to see whether the wait profile actually changed before declaring victory.

---

## 6. Reconstructing a Past Incident (ASH)

Use when you're investigating something that already happened — `gv$session`/`gv$sql` have already flushed the live state.

```sql
SELECT h.event, h.session_state, COUNT(*) AS total_samples
  FROM gv$active_session_history h
 WHERE h.sample_time BETWEEN TO_TIMESTAMP(:window_start, 'YYYY-MM-DD HH24:MI:SS')
                          AND TO_TIMESTAMP(:window_end,   'YYYY-MM-DD HH24:MI:SS')
 GROUP BY h.event, h.session_state
 ORDER BY total_samples DESC;
```

```sql
SELECT h.sample_time,
       h.inst_id,
       h.session_id,
       h.session_state,
       h.event,
       h.time_waited,
       h.blocking_session,
       h.blocking_inst_id,
       h.sql_id
  FROM gv$active_session_history h
 WHERE h.sample_time BETWEEN TO_TIMESTAMP(:narrow_start, 'YYYY-MM-DD HH24:MI:SS')
                          AND TO_TIMESTAMP(:narrow_end,   'YYYY-MM-DD HH24:MI:SS')
 ORDER BY h.sample_time DESC;
```

```sql
-- Recover query text that has already aged out of gv$sql
SELECT t.sql_text
  FROM dba_hist_sqltext t
 WHERE t.sql_id = '&sql_id';
```

Feed the resulting `sql_id` and `blocking_session`/`blocking_inst_id` back into Sections 3–5.

---

## 7. Remediation, by Root Cause

Pick the branch that matches what Section 5 found. Don't run all of these reflexively — e.g. recompiling triggers does nothing for cause C or D.

**If cause A/B (invalid object / missing privileges):**

```sql
-- Grant what's missing (fill in from the privilege-gap query)
GRANT SELECT, INSERT, UPDATE, DELETE ON :schema.:table TO :grantee;
GRANT EXECUTE ON :schema.:procedure TO :grantee;
```

```sql
-- Recompile only objects that actually have errors
DECLARE
  v_cmd VARCHAR2(200);
BEGIN
  FOR rec IN (
    SELECT DISTINCT e.owner, e.name, e.type
      FROM dba_errors e
     WHERE e.owner = :owner
  ) LOOP
    v_cmd := 'ALTER ' || rec.type || ' ' || rec.owner || '.' || rec.name || ' COMPILE';
    EXECUTE IMMEDIATE v_cmd;
    DBMS_OUTPUT.PUT_LINE('Compiled: ' || rec.owner || '.' || rec.name);
  END LOOP;
END;
/
```

**If cause C (stuck/idle transaction):**

```sql
-- Confirm before killing: is this really idle-in-transaction, not just slow?
SELECT s.inst_id, s.sid, s.serial#, s.username, s.last_call_et, t.start_time
  FROM gv$session s
  JOIN gv$transaction t ON t.ses_addr = s.saddr AND t.inst_id = s.inst_id
 WHERE s.sid = :sid AND s.inst_id = :inst_id;

-- Then, only if confirmed stuck:
ALTER SYSTEM KILL SESSION ':sid,:serial#,@:inst_id';
```

**Generate kill candidates in bulk (any cause) — review before executing, don't pipe straight to execution:**

```sql
SELECT 'ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.serial# || ',@' || s.inst_id || ''';' AS kill_cmd,
       s.username,
       o.object_name,
       s.seconds_in_wait
  FROM sys.dba_objects       o,
       sys.gv_$locked_object lo,
       sys.gv_$session       s,
       sys.gv_$process       p
 WHERE o.object_id = lo.object_id
   AND s.sid       = lo.session_id
   AND s.inst_id   = lo.inst_id
   AND p.addr      = s.paddr
   AND p.inst_id   = s.inst_id
   AND s.seconds_in_wait > 300   -- 5+ minutes; adjust to taste
 ORDER BY s.seconds_in_wait DESC;
```

**If cause D (legitimate hot-row contention):** this isn't a "fix the trigger" problem — options are reducing transaction scope/duration in the app, batching updates, or redesigning the hot key (e.g., sequence-based counters instead of a single summary row). Don't kill sessions here; you'll just shift the queue.

**Architectural option, if a cross-schema trigger keeps recurring as the trigger point (cause A/B pattern repeating):**

```sql
-- Decouple: let the downstream schema poll instead of firing synchronously in your transaction path
CREATE MATERIALIZED VIEW LOG ON :owning_schema.:table WITH PRIMARY KEY;
```

The consuming schema builds a materialized view against the log and polls on its own schedule. If its grants break again, its poll fails quietly on its own side — it can no longer stall your session's row locks.

---

## 8. Verification

`gv$system_event` is cumulative/historical — don't use it to check "is it fixed now." Use live state:

```sql
SELECT COUNT(*) AS active_locks_right_now FROM gv$locked_object;
-- 0 = clean
```

```sql
SELECT COUNT(*) AS sessions_blocked_right_now
  FROM gv$session s
 WHERE s.wait_class != 'Idle'
   AND s.blocking_session IS NOT NULL;
-- 0 = no one waiting on a blocker
```

```sql
SELECT COUNT(*) AS active_blocker_sessions
  FROM (SELECT DISTINCT b.sid, b.inst_id
          FROM gv$session b
          JOIN gv$session w
            ON w.blocking_session  = b.sid
           AND w.blocking_instance = b.inst_id);
-- 0 = no one is holding a lock others are waiting on
```

```sql
-- Re-run Section 1's triage query — the wait_class/event mix should look like baseline, not the incident profile
```

If cause A/B was the fix, also re-run the `dba_errors` query from Section 5 and confirm 0 rows. If any of these are still non-zero, go back to Section 5 rather than assuming the same fix needs repeating — a recurrence with a *different* cause looks identical from Section 1/2 alone.

---

## 9. Executive Summary Query

Parametrized version for a one-shot report — fill in `:owner`/`:consumer_schema`/`:target_schema` for whatever cross-schema relationship you're investigating (not hardcoded to any one schema pair).

```sql
WITH session_snapshot AS (
  -- Single scan of gv$session (a cluster-wide fetch on RAC), reused below instead of
  -- re-querying it once per CTE
  SELECT s.inst_id, s.sid, s.username, s.event, s.wait_class,
         s.seconds_in_wait, s.blocking_session, s.blocking_instance
    FROM gv$session s
   WHERE s.type = 'USER'
),
blocked_summary AS (
  SELECT b.username                      AS blocker_user,
         COUNT(DISTINCT b.sid)           AS blocker_sessions,
         COUNT(DISTINCT w.sid)           AS blocked_sessions,
         MAX(w.seconds_in_wait)          AS max_blocked_wait_sec,
         MAX(b.seconds_in_wait)          AS blocker_hold_time_sec
    FROM session_snapshot b, session_snapshot w
   WHERE b.sid     = w.blocking_session
     AND b.inst_id = w.blocking_instance
     AND w.wait_class != 'Idle'
   GROUP BY b.username
),
object_health AS (
  SELECT o.owner, o.object_name, o.object_type, o.status,
         COUNT(e.line) AS error_count
    FROM dba_objects o
    LEFT JOIN dba_errors e
           ON e.owner = o.owner AND e.name = o.object_name AND e.type = o.object_type
   WHERE o.owner = :consumer_schema
   GROUP BY o.owner, o.object_name, o.object_type, o.status
),
privilege_check AS (
  SELECT :consumer_schema                                                  AS grantee,
         COUNT(DISTINCT p.table_name)                                       AS tables_granted,
         COUNT(DISTINCT CASE WHEN p.privilege IN ('SELECT','INSERT','UPDATE','DELETE')
                              THEN p.table_name END)                        AS tables_with_dml
    FROM dba_tab_privs p
   WHERE p.grantee = :consumer_schema
     AND p.owner   = :target_schema
),
wait_events_summary AS (
  SELECT s.event,
         COUNT(*)                                              AS num_sessions,
         ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)       AS pct_of_total,
         ROUND(AVG(s.seconds_in_wait), 2)                       AS avg_wait_sec,
         MAX(s.seconds_in_wait)                                 AS max_wait_sec
    FROM session_snapshot s
   WHERE s.wait_class != 'Idle'
   GROUP BY s.event
)
SELECT '1. ACTIVE BLOCKERS' AS section, bs.blocker_user AS detail,
       bs.blocker_sessions || ' blocker / ' || bs.blocked_sessions || ' blocked' AS metric,
       'Held ' || bs.blocker_hold_time_sec || 's, worst wait ' || bs.max_blocked_wait_sec || 's' AS value
  FROM blocked_summary bs
UNION ALL
SELECT '2. OBJECT HEALTH', oh.object_name,
       oh.status || ' (' || oh.object_type || ')',
       CASE WHEN oh.error_count > 0 THEN oh.error_count || ' compile errors' ELSE 'OK' END
  FROM object_health oh
UNION ALL
SELECT '3. PRIVILEGE COVERAGE', pc.grantee,
       pc.tables_granted || ' tables granted',
       pc.tables_with_dml || ' with DML'
  FROM privilege_check pc
UNION ALL
SELECT '4. WAIT PROFILE', wes.event,
       wes.num_sessions || ' (' || wes.pct_of_total || '%)',
       'avg ' || wes.avg_wait_sec || 's / max ' || wes.max_wait_sec || 's'
  FROM wait_events_summary wes
 ORDER BY section;
```

---

## 10. Appendix: The NBC_APPS/ONAIR Case Study

Kept for reference — this is the incident that originally motivated this playbook, not a template to apply blindly to the next one.

**What happened:** a database maintenance window reset cross-schema grants, which invalidated `NBC_APPS.TRG_MS_ACCOUNTING` (a synchronous trigger firing on `ONAIR.ACCOUNTING` DML). Oracle detected the trigger was `INVALID` but still `ENABLED`, forced a synchronous recompile on the calling `ONAIR` session's thread, and that recompile failed with a privilege error (`ORA-01031`/`ORA-04098`) *before* the trigger's own `EXCEPTION WHEN OTHERS` handler ever loaded into memory — so the handler couldn't swallow the error like it was designed to. The app layer then failed to issue an immediate `ROLLBACK`, so the row locks it already held stayed open, and downstream `ONAIR` sessions queued up behind it (cause A + C, stacked).

**Why the autonomous-transaction handler didn't save it:** autonomous transactions decouple `COMMIT`/`ROLLBACK` scope, not execution thread — they still run synchronously on the calling session. A stall inside one (like the forced recompile here) still blocks the parent session and its row locks.

**Why it recurred after the grants were fixed:** fixing the grants addressed cause A/B, but not the underlying pattern that a synchronous cross-schema trigger can still stall the `ONAIR` session's thread for other reasons (recompiles, network calls inside the trigger, contention on whatever the trigger itself writes to) — and cause C (app not rolling back promptly on error) was never addressed. That's why the architectural option in Section 7 (materialized view log + polling) was recommended as the durable fix: it removes the synchronous coupling entirely, so `NBC_APPS` breaking on its own end can no longer stall `ONAIR`'s session, regardless of which specific cause trips it next time.

---

### Case Study 2 (08-JUL-26): Cause F — the trigger was innocent, a later statement in the same transaction regressed

**What happened:** `CmdLoader.exe` (session on ONAIR/NBC_CUST) ran its normal DML, the `NBC_APPS` trigger fired synchronously and took its row lock on `TBL_MS_ADVERTISER` as designed (cause E, nothing wrong here) — then, still inside the *same transaction*, CmdLoader went on to call `ONAIR.SCH_INVENTORY_PKG` (traced via Section 4: `sql_id 49wffw1jrjy4y` → `program_id` → `dba_objects` → package body, line 5897), a GTT-heavy rollup query that had needed hand-tuning before (inline `cardinality()` hints in the source, plus a standing `DBMS_SQLTUNE` SQL Profile from 29-SEP-25). That morning the profile's `last_modified` flipped and it re-pinned an old plan (`HASH JOIN` + full scans, cost 53) over the plan that had actually been running well for ~9 months (nested loops + index scans, cost 5) — see Section 3's SQL Profile / Plan Stability Check. The query went from milliseconds to minutes; because it shared the trigger's transaction, the trigger's row lock stayed held for the entire regression, cascading into the same `enq: TX - row lock contention` symptom as Case Study 1.

**Why it looked identical to a trigger problem at first:** the blocking chain, `row_wait_obj#`, and `dba_dependencies` chain all pointed at the trigger and the locked table exactly as they should — that evidence was correct, just incomplete. It proves *what put the lock there*, not *why it's still there*. The session's current SQL (`49wffw1jrjy4y`) never referenced the locked table at all, which made it easy to file as an unrelated, pre-existing ONAIR performance quirk instead of the thing actually keeping the transaction open. Cause E and cause F both had to be checked before the picture was complete.

**Fix:** re-tune or drop/recreate the stale SQL Profile so the optimizer picks the plan that matches current data volumes (or replace it with a SQL Plan Baseline that can evolve); no NBC_APPS-side change was needed for this incident.
