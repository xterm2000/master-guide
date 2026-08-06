#dbms #scheduler #job 


Here's the full parameter list for `dbms_scheduler.create_job`, with the actual behavior, not just the doc gloss — including the parts where the docs undersell the gotchas.

## Full parameter list

```sql
DBMS_SCHEDULER.CREATE_JOB (
   job_name             VARCHAR2,
   job_type             VARCHAR2,
   job_action           VARCHAR2,
   number_of_arguments   NUMBER   DEFAULT 0,
   start_date            TIMESTAMP WITH TIME ZONE DEFAULT NULL,
   repeat_interval       VARCHAR2 DEFAULT NULL,
   end_date              TIMESTAMP WITH TIME ZONE DEFAULT NULL,
   job_class             VARCHAR2 DEFAULT 'DEFAULT_JOB_CLASS',
   enabled               BOOLEAN  DEFAULT FALSE,
   auto_drop             BOOLEAN  DEFAULT TRUE,
   comments              VARCHAR2 DEFAULT NULL,
   credential_name       VARCHAR2 DEFAULT NULL,
   destination_name      VARCHAR2 DEFAULT NULL
);
```

|Param|What it actually does|Where people get burned|
|---|---|---|
|`job_name`|Identifier for the job, up to 128 bytes (30 on pre-12.2 databases — check your version, this isn't universal). Unqualified = current schema.|Nobody checks the version limit until deployment fails on an older instance.|
|`job_type`|One of `PLSQL_BLOCK`, `STORED_PROCEDURE`, `EXECUTABLE`, `CHAIN`, `BACKUP_SCRIPT`. Dictates how `job_action` is parsed.|Mismatched `job_type`/`job_action` format (e.g. parentheses in a `STORED_PROCEDURE` action) fails silently at _run_ time, not creation time.|
|`job_action`|The actual code/target. For `PLSQL_BLOCK`: a full anonymous block as text. For `STORED_PROCEDURE`: schema-qualified name, no parens, no args inline. For `EXECUTABLE`: OS path, needs a `credential_name`.|People paste `MY_PROC(:a, :b)` into `job_action` for a stored-proc job — that's wrong, arguments go through `set_job_argument_value`, not inline.|
|`number_of_arguments`|Tells the scheduler how many placeholders to expect for `STORED_PROCEDURE`/`EXECUTABLE` jobs so you can call `set_job_argument_value` per position.|If you don't set this and then try to bind an argument at position 2, you get an error — this is _not_ auto-detected from the procedure's real signature.|
|`start_date`|When the job becomes eligible to run. `NULL` means immediately upon enable.|People assume it fires exactly at `start_date` — it fires at the next opportunity **on or after** it, which with a `repeat_interval` can matter for the first occurrence.|
|`repeat_interval`|A calendaring string (`FREQ=DAILY; BYHOUR=2;...`) or a PL/SQL expression returning a date/timestamp. `NULL` = one-time job.|Leaving this set for something meant to run once — job never disappears when you expect it to, or reruns unexpectedly.|
|`end_date`|Job stops generating new runs after this, but doesn't drop the job definition.|People conflate "end_date reached" with "job dropped" — it isn't, you still have to clean it up.|
|`job_class`|Controls resource allocation, priority, and which service the job runs under in RAC. Defaults to `DEFAULT_JOB_CLASS`.|In RAC, if you don't set this deliberately, job placement across instances is out of your control and can land somewhere inconvenient.|
|`enabled`|**Default is `FALSE`.** Job is created but scheduler will never run it until you call `enable()`.|This is the one most people get backwards — they assume `create_job` alone starts scheduling. It doesn't unless you pass `enabled => TRUE`.|
|`auto_drop`|For one-time jobs (no `repeat_interval`): if `TRUE` (default), job metadata is deleted right after it completes — you lose the row in `user_scheduler_jobs`, though run history in `user_scheduler_job_run_details` may still persist briefly depending on retention. For repeating jobs, `auto_drop` only matters after `end_date` passes.|People set `auto_drop => TRUE` then wonder why the job "disappeared" and they can't check `run_count` or last status.|
|`comments`|Free text, purely documentation. No functional effect.|—|
|`credential_name`|Required for `EXECUTABLE` job type (OS-level credential for running external scripts). Ignored for `PLSQL_BLOCK`/`STORED_PROCEDURE`.|Omitting it for an `EXECUTABLE` job fails immediately with ORA-27476 or similar.|
|`destination_name`|For remote/external jobs (running on a different host via scheduler agent). `NULL` = runs locally.|Rarely used — don't set this unless you actually have a remote agent configured, or the job creation errors out looking for a destination that doesn't exist.|

## Submitting disabled, then enabling later

This is genuinely the correct pattern when you need to bind arguments before the job can safely run — which is exactly your stored-procedure case from before.

```sql
BEGIN
  -- Step 1: create disabled
  dbms_scheduler.create_job(
    job_name        => 'ZZZ_PROC_JOB',
    job_type        => 'STORED_PROCEDURE',
    job_action      => 'MY_SCHEMA.MY_PROCEDURE',
    number_of_arguments => 2,
    start_date      => SYSTIMESTAMP + INTERVAL '2' MINUTE,
    repeat_interval => 'FREQ=DAILY; BYHOUR=2; BYMINUTE=0; BYSECOND=0',
    enabled         => FALSE,     -- explicit, don't rely on default even though FALSE is default
    auto_drop       => FALSE,
    comments        => 'Created disabled, args bound before enable'
  );

  -- Step 2: bind arguments (only possible while disabled, in practice — 
  -- binding after enable on some versions throws ORA-27477)
  dbms_scheduler.set_job_argument_value(
    job_name           => 'ZZZ_PROC_JOB',
    argument_position  => 1,
    argument_value     => 42
  );

  dbms_scheduler.set_job_argument_value(
    job_name           => 'ZZZ_PROC_JOB',
    argument_position  => 2,
    argument_value     => 'some_value'
  );

  -- Step 3: enable — job becomes eligible to run at/after start_date
  dbms_scheduler.enable('ZZZ_PROC_JOB');
END;
/
```

Checking it's actually enabled before you walk away:

```sql
SELECT job_name, enabled, state, start_date, next_run_date
FROM   user_scheduler_jobs
WHERE  job_name = 'ZZZ_PROC_JOB';
```

`enabled` should read `TRUE` and `state` should read `SCHEDULED` (not `DISABLED`). If `state` shows `RETRY_SCHEDULED` or `BROKEN` shortly after, your arguments didn't bind correctly against the real procedure signature — that's not a scheduler problem, it's a signature mismatch, and no amount of scheduler debugging fixes it. Go check `MY_PROCEDURE`'s actual parameter list against what you fed `set_job_argument_value`.

One thing I'm not going to assume: you still haven't told me whether `number_of_arguments` matches your actual procedure signature. If `MY_PROCEDURE` doesn't take exactly two args in that order and those types, everything above compiles and creates fine, and only blows up when the job tries to run. Is this a real procedure you have the signature for, or still a placeholder?

##### submit 
```sql
DECLARE
  i_job_frequency    VARCHAR2(250) := 'FREQ=DAILY; BYHOUR=2; BYMINUTE=0; BYSECOND=0';
  i_job_proc_name    VARCHAR2(250) := 'MY_SCHEMA.MY_PROCEDURE';
  i_job_plsql_block  VARCHAR2(1000) := 'BEGIN NULL; END;';
  i_job_start        TIMESTAMP := SYSTIMESTAMP + INTERVAL '2' MINUTE;

  i_job_param1       NUMBER := 1;
  i_job_param2       VARCHAR2(200) := 'some_value';
BEGIN

  ----------------------------------------------------------------
  -- Submit job with stored procedure (with arguments)
  ----------------------------------------------------------------
  dbms_scheduler.create_job(
    job_name        => 'ZZZ_PROC_JOB',
    job_type        => 'STORED_PROCEDURE',
    job_action      => i_job_proc_name,
    start_date      => i_job_start,
    repeat_interval => i_job_frequency,
    enabled         => FALSE,          -- keep disabled until args are bound
    auto_drop       => FALSE,
    comments        => 'Job calling stored procedure with arguments'
  );

  dbms_scheduler.set_job_argument_value(
    job_name  => 'ZZZ_PROC_JOB',
    argument_position => 1,
    argument_value     => i_job_param1
  );

  dbms_scheduler.set_job_argument_value(
    job_name  => 'ZZZ_PROC_JOB',
    argument_position => 2,
    argument_value     => i_job_param2
  );

  dbms_scheduler.enable('ZZZ_PROC_JOB');

  ----------------------------------------------------------------
  -- Submit job with anonymous PL/SQL block
  ----------------------------------------------------------------
  dbms_scheduler.create_job(
    job_name        => 'ZZZ_PLSQL_JOB',
    job_type        => 'PLSQL_BLOCK',
    job_action      => i_job_plsql_block,
    start_date      => i_job_start,
    repeat_interval => i_job_frequency,
    enabled         => TRUE,
    auto_drop       => FALSE,
    comments        => 'Job running inline PL/SQL block'
  );

END;
/

```
##### drop jobs
```sql
/* drop procedure */

DECLARE
  v_ddl   VARCHAR2(100);
  v_count NUMBER;

  PROCEDURE drop_job_safe(p_name IN VARCHAR2) IS
  BEGIN
    BEGIN
      dbms_scheduler.stop_job(p_name, force => TRUE);
    EXCEPTION
      WHEN OTHERS THEN
        NULL;
    END;
    BEGIN
      dbms_scheduler.drop_job(p_name, force => TRUE);
      dbms_output.put_line('Dropped job ' || p_name);
    EXCEPTION
      WHEN OTHERS THEN
        dbms_output.put_line('Job ' || p_name || ' not found (already dropped or never existed)');
    END;
  END drop_job_safe;
BEGIN

  BEGIN
  
    FOR rec IN (SELECT job_name,
                       enabled,
                       state,
                       run_count,
                       j.job_type,
                       j.event_condition,
					   j.JOB_ACTION,j.REPEAT_INTERVAL
                  FROM user_scheduler_jobs j
                 WHERE job_name LIKE 'ZZZ%') LOOP
    
      drop_job_safe(rec.job_name);
      dbms_scheduler.purge_log(job_name => rec.job_name);
    END LOOP;
  END;

END;

```