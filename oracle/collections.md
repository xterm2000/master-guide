# Oracle PL/SQL Collections — Comprehensive Reference

## Table of Contents

- [[#Overview]]
    - [[#Sparse vs Dense]]
- [[#Collection Types Comparison]]
- [[#Associative Arrays (INDEX BY)]]
    - [[#%ROWTYPE Associative Array — Keyed Cache]]
- [[#Nested Tables]]
    - [[#%ROWTYPE Nested Table — Bulk Load and Field Access]]
    - [[#%ROWTYPE Nested Table — Modify Fields In-Place]]
- [[#VARRAYs]]
- [[#Initialization]]
- [[#Common Operations & Iteration]]
- [[#BULK COLLECT]]
    - [[#BULK COLLECT from DML with RETURNING]]
- [[#FORALL]]
- [[#Use Cases]]
- [[#Limitations & Gotchas]]

---

## Overview

PL/SQL collections are single-dimensional, ordered data structures — similar to arrays in other languages — that allow you to store and manipulate multiple values of the same type in memory. They are essential for high-performance PL/SQL, especially when working with large datasets via **BULK COLLECT** and **FORALL**.

There are three collection types in Oracle PL/SQL:

|Feature|Associative Array|Nested Table|VARRAY|
|---|---|---|---|
|Also Called|Index-by table, PL/SQL table|—|Variable-size array|
|Storage|PL/SQL memory only|In-DB column or PL/SQL|In-DB column or PL/SQL|
|Index Type|`PLS_INTEGER` or `VARCHAR2`|`INTEGER` (always 1-based)|`INTEGER` (always 1-based)|
|Sparse?|Yes|Yes (after deletes)|No|
|Max Size|Unbounded|Unbounded|Fixed at declaration|
|Must Initialize?|No|Yes (`type()`)|Yes (`type()`)|
|Can be a Column Type?|No|Yes|Yes|
|Can use `TABLE()` in SQL?|No|Yes|Yes|
|Supports `DELETE(n)`?|Yes|Yes|No|

### Sparse vs Dense

A collection is **dense** when every index from 1 to the last element exists — no gaps. It is **sparse** when some indices are missing.

```
Dense:   1→10   2→20   3→30   4→40   5→50
Sparse:  1→10   2→20           4→40   5→50   (index 3 deleted)
```

A freshly populated Nested Table or VARRAY is always dense. A Nested Table becomes sparse when you call `.DELETE(n)` — the slot disappears but surrounding indices don't shift to fill the gap. Associative arrays are sparse by design; you assign whatever indices you want.

**Why it matters:** iterating a sparse collection with a naive `FOR i IN 1..COUNT` loop crashes at the first gap with `ORA-01403 / NO_DATA_FOUND`, because `COUNT` no longer equals `LAST`.

```sql
l_n := t_n(10, 20, 30, 40, 50);
l_n.DELETE(3);
-- COUNT=4, LAST=5 — loop runs i=1,2,3,4 but index 3 is gone → crash at i=3
FOR i IN 1 .. l_n.COUNT LOOP ...  -- UNSAFE on sparse
```

Always use one of the safe patterns on collections that may have gaps:

```sql
-- Option 1: EXISTS guard
FOR i IN 1 .. l_n.LAST LOOP
    IF l_n.EXISTS(i) THEN ... END IF;
END LOOP;

-- Option 2: FIRST/NEXT — skips gaps automatically
i := l_n.FIRST;
WHILE i IS NOT NULL LOOP
    ...
    i := l_n.NEXT(i);
END LOOP;
```

|Collection|Can be sparse?|Simple `FOR i IN 1..COUNT` safe?|
|---|---|---|
|Associative Array|Yes — by design|Only if you control the indices|
|Nested Table|Yes — after `.DELETE(n)`|Only if no deletes have happened|
|VARRAY|Never|Always safe|

---

## Collection Types Comparison

```
Associative Array  →  Best for PL/SQL-only lookups, sparse data, string-keyed maps
Nested Table       →  Best for SQL interop, set operations, arbitrary DML
VARRAY             →  Best for fixed-size ordered lists stored in DB columns
```

---

## Associative Arrays (INDEX BY)

An **associative array** is a key-value map. The key is either a `PLS_INTEGER` or a `VARCHAR2`. It does **not** need initialization and cannot be stored in database tables.

### Declaration

```sql
-- Integer-indexed
TYPE t_emp_sal IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
l_sal t_emp_sal;

-- String-indexed (lookup map pattern)
TYPE t_country_code IS TABLE OF VARCHAR2(3) INDEX BY VARCHAR2(100);
l_codes t_country_code;

-- %ROWTYPE — collection of full table rows
TYPE t_emp_tab IS TABLE OF employees%ROWTYPE INDEX BY PLS_INTEGER;
l_emps t_emp_tab;

-- %TYPE — collection of a single column's type
TYPE t_sal_tab IS TABLE OF employees.salary%TYPE INDEX BY PLS_INTEGER;
l_sals t_sal_tab;
```

### %ROWTYPE Associative Array — Keyed Cache

A common pattern is loading rows into a string-keyed associative array for O(log n) lookups, avoiding repeated SQL round-trips.

```sql
DECLARE
    TYPE t_emp_cache IS TABLE OF employees%ROWTYPE INDEX BY VARCHAR2(30);
    l_cache t_emp_cache;
    l_rec   employees%ROWTYPE;
BEGIN
    -- Build a lookup cache keyed by last_name
    FOR r IN (SELECT * FROM employees WHERE department_id = 60) LOOP
        l_cache(r.last_name) := r;   -- store the entire row
    END LOOP;

    -- Access any field on the cached row by key
    IF l_cache.EXISTS('Hunold') THEN
        l_rec := l_cache('Hunold');
        DBMS_OUTPUT.PUT_LINE(
            l_rec.first_name  || ' ' ||
            l_rec.last_name   || ' — salary: ' || l_rec.salary
        );
    END IF;
END;
/
```

### Usage

```sql
DECLARE
    TYPE t_lookup IS TABLE OF VARCHAR2(50) INDEX BY VARCHAR2(30);
    l_dept t_lookup;
BEGIN
    -- Assign values directly — no initialization needed
    l_dept('SALES')   := 'New York';
    l_dept('FINANCE') := 'Chicago';
    l_dept('HR')      := 'Dallas';

    -- Access by key
    DBMS_OUTPUT.PUT_LINE(l_dept('SALES'));   -- New York

    -- Check existence before access (avoid NO_DATA_FOUND)
    IF l_dept.EXISTS('FINANCE') THEN
        DBMS_OUTPUT.PUT_LINE(l_dept('FINANCE'));
    END IF;
END;
/
```

### String-Keyed Iteration

```sql
DECLARE
    TYPE t_lookup IS TABLE OF VARCHAR2(50) INDEX BY VARCHAR2(30);
    l_dept t_lookup;
    l_key  VARCHAR2(30);
BEGIN
    l_dept('SALES')   := 'New York';
    l_dept('FINANCE') := 'Chicago';

    -- FIRST / NEXT pattern for string-indexed arrays
    l_key := l_dept.FIRST;
    WHILE l_key IS NOT NULL LOOP
        DBMS_OUTPUT.PUT_LINE(l_key || ' => ' || l_dept(l_key));
        l_key := l_dept.NEXT(l_key);
    END LOOP;
END;
/
```

---

## Nested Tables

A **nested table** is an unbounded, integer-indexed collection that must be initialized before use. It can be stored as a column type in a database table and used with the `TABLE()` operator in SQL.

### Declaration & Initialization

```sql
-- Type declared at schema level (can be used as column type)
CREATE OR REPLACE TYPE t_name_list IS TABLE OF VARCHAR2(100);
/

-- Or declared in a PL/SQL block
DECLARE
    TYPE t_numbers IS TABLE OF NUMBER;

    -- Must call the constructor to initialize — otherwise NULL
    l_nums t_numbers := t_numbers();        -- empty, not null
    l_names t_name_list := t_name_list(    -- initialized with values
        'Alice', 'Bob', 'Carol'
    );
BEGIN
    -- Extend before assigning new elements
    l_nums.EXTEND;
    l_nums(1) := 42;

    l_nums.EXTEND(3);   -- add 3 null slots
    l_nums(2) := 10;
    l_nums(3) := 20;
    l_nums(4) := 30;

    DBMS_OUTPUT.PUT_LINE('Count: ' || l_nums.COUNT);  -- 4
END;
/
```

### Sparse Behavior After DELETE

```sql
DECLARE
    TYPE t_nums IS TABLE OF NUMBER;
    l_n t_nums := t_nums(10, 20, 30, 40, 50);
BEGIN
    l_n.DELETE(3);   -- removes index 3; collection is now sparse

    -- COUNT = 4, but index 3 is gone
    -- Always use EXISTS() or FIRST/NEXT when iterating sparse tables
    FOR i IN 1 .. l_n.LAST LOOP
        IF l_n.EXISTS(i) THEN
            DBMS_OUTPUT.PUT_LINE(i || ': ' || l_n(i));
        END IF;
    END LOOP;
END;
/
```

### %ROWTYPE Nested Table — Bulk Load and Field Access

```sql
DECLARE
    TYPE t_emp_tab IS TABLE OF employees%ROWTYPE;
    l_emps t_emp_tab;
BEGIN
    -- BULK COLLECT into a %ROWTYPE collection
    SELECT *
    BULK COLLECT INTO l_emps
    FROM   employees
    WHERE  department_id = 80
    ORDER  BY last_name;

    -- Access individual fields by collection index
    FOR i IN 1 .. l_emps.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE(
            RPAD(l_emps(i).last_name, 20) ||
            RPAD(l_emps(i).job_id, 12)   ||
            l_emps(i).salary
        );
    END LOOP;
END;
/
```

### %ROWTYPE Nested Table — Modify Fields In-Place

Because the collection holds a copy of each row, you can mutate fields before writing back with FORALL.

```sql
DECLARE
    TYPE t_emp_tab IS TABLE OF employees%ROWTYPE;
    l_emps t_emp_tab;
BEGIN
    SELECT *
    BULK COLLECT INTO l_emps
    FROM   employees
    WHERE  job_id = 'SA_REP';

    -- Mutate fields directly on the collected rows
    FOR i IN 1 .. l_emps.COUNT LOOP
        l_emps(i).salary         := l_emps(i).salary * 1.08;
        l_emps(i).commission_pct := NVL(l_emps(i).commission_pct, 0) + 0.01;
    END LOOP;

    -- Write back with FORALL
    FORALL i IN 1 .. l_emps.COUNT
        UPDATE employees
        SET    salary         = l_emps(i).salary,
               commission_pct = l_emps(i).commission_pct
        WHERE  employee_id    = l_emps(i).employee_id;

    DBMS_OUTPUT.PUT_LINE('Updated: ' || SQL%ROWCOUNT);
    COMMIT;
END;
/
```

### Using Nested Tables in SQL with TABLE()

```sql
-- Schema-level type required for TABLE() operator
CREATE OR REPLACE TYPE t_id_list IS TABLE OF NUMBER;
/

-- Pass a collection into a SQL query
DECLARE
    l_ids t_id_list := t_id_list(101, 105, 110, 202);
BEGIN
    FOR r IN (
        SELECT e.employee_id, e.last_name
        FROM   employees e
        JOIN   TABLE(l_ids) t ON e.employee_id = t.COLUMN_VALUE
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(r.employee_id || ' ' || r.last_name);
    END LOOP;
END;
/
```

---

## VARRAYs

A **VARRAY** (Variable-Size Array) has a fixed maximum size declared at definition time. Indices are always dense (no gaps). It cannot use `DELETE(n)` — only `TRIM` to remove from the end.

### Declaration & Initialization

```sql
-- Must specify maximum size
TYPE t_week_days IS VARRAY(7) OF VARCHAR2(10);

DECLARE
    l_days t_week_days := t_week_days('Mon','Tue','Wed','Thu','Fri');
BEGIN
    -- Extend up to declared max
    l_days.EXTEND;
    l_days(6) := 'Sat';

    DBMS_OUTPUT.PUT_LINE('Days: ' || l_days.COUNT);  -- 6
    DBMS_OUTPUT.PUT_LINE('Limit: ' || l_days.LIMIT); -- 7

    -- Simple FOR loop — always dense
    FOR i IN 1 .. l_days.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE(l_days(i));
    END LOOP;
END;
/
```

---

## Initialization

|Collection|NULL (uninitialized)|Empty (initialized, no elements)|With Values|
|---|---|---|---|
|Associative Array|N/A — can use immediately|N/A — use directly|`l_arr(1) := val;`|
|Nested Table|`l_nt t_nt;` — raises `COLLECTION_IS_NULL`|`l_nt := t_nt();`|`l_nt := t_nt(1,2,3);`|
|VARRAY|`l_va t_va;` — raises `COLLECTION_IS_NULL`|`l_va := t_va();`|`l_va := t_va('a','b');`|

> **Rule of thumb:** Always initialize Nested Tables and VARRAYs at declaration. Always call `.EXTEND` before assigning by index.

### Initialization Pattern

```sql
DECLARE
    TYPE t_ids IS TABLE OF NUMBER;
    l_ids t_ids;
BEGIN
    -- Bad: l_ids(1) := 99;  -- raises COLLECTION_IS_NULL

    l_ids := t_ids();     -- initialize
    l_ids.EXTEND;         -- make room for one element
    l_ids(1) := 99;       -- now safe

    -- Or in one shot:
    l_ids := t_ids(1, 2, 3, 4, 5);
END;
/
```

---

## Common Operations & Iteration

### Collection Methods

|Method|Applies To|Description|
|---|---|---|
|`.COUNT`|All|Number of elements currently in the collection|
|`.FIRST`|All|Lowest existing index (or `NULL` if empty)|
|`.LAST`|All|Highest existing index (or `NULL` if empty)|
|`.NEXT(n)`|All|Index after `n`, or `NULL`|
|`.PRIOR(n)`|All|Index before `n`, or `NULL`|
|`.EXISTS(n)`|All|`TRUE` if index `n` is populated|
|`.EXTEND`|NT, VA|Append one `NULL` element|
|`.EXTEND(n)`|NT, VA|Append `n` `NULL` elements|
|`.EXTEND(n, i)`|NT, VA|Append `n` copies of element `i`|
|`.TRIM`|NT, VA|Remove last element|
|`.TRIM(n)`|NT, VA|Remove last `n` elements|
|`.DELETE`|AA, NT|Remove all elements|
|`.DELETE(n)`|AA, NT|Remove element at index `n`|
|`.DELETE(m, n)`|AA, NT|Remove elements from `m` to `n`|
|`.LIMIT`|VA only|Maximum size declared|

### Iteration Patterns

```sql
DECLARE
    TYPE t_nums IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    l_n t_nums;
    i   PLS_INTEGER;
BEGIN
    l_n(1) := 10; l_n(2) := 20; l_n(5) := 50;  -- sparse

    -- Pattern 1: FOR loop with EXISTS (safe for sparse)
    FOR idx IN 1 .. l_n.LAST LOOP
        IF l_n.EXISTS(idx) THEN
            DBMS_OUTPUT.PUT_LINE(idx || ': ' || l_n(idx));
        END IF;
    END LOOP;

    -- Pattern 2: FIRST/NEXT (best for sparse or string-indexed)
    i := l_n.FIRST;
    WHILE i IS NOT NULL LOOP
        DBMS_OUTPUT.PUT_LINE(i || ': ' || l_n(i));
        i := l_n.NEXT(i);
    END LOOP;

    -- Pattern 3: Simple FOR (dense collections only — VARRAY or fresh Nested Table)
    -- For i IN 1 .. l_n.COUNT LOOP ... END LOOP;
    -- Avoid this on sparse collections — index gaps cause NO_DATA_FOUND
END;
/
```

---

## BULK COLLECT

`BULK COLLECT` populates a collection from a SQL query in a single context switch, dramatically reducing round-trips between the SQL and PL/SQL engines.

### Basic BULK COLLECT

```sql
DECLARE
    TYPE t_emp_ids  IS TABLE OF employees.employee_id%TYPE;
    TYPE t_emp_names IS TABLE OF employees.last_name%TYPE;

    l_ids   t_emp_ids;
    l_names t_emp_names;
BEGIN
    SELECT employee_id, last_name
    BULK COLLECT INTO l_ids, l_names
    FROM employees
    WHERE department_id = 60;

    FOR i IN 1 .. l_ids.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE(l_ids(i) || ' ' || l_names(i));
    END LOOP;
END;
/
```

### BULK COLLECT into Record Collection

Using `%ROWTYPE` as the collection element type means every row from the query maps directly to a strongly-typed record — no parallel scalar arrays needed. Access fields with dot notation: `l_emps(i).field_name`.

```sql
DECLARE
    TYPE t_emp_tab IS TABLE OF employees%ROWTYPE;
    l_emps t_emp_tab;
BEGIN
    SELECT *
    BULK COLLECT INTO l_emps
    FROM   employees
    WHERE  salary > 10000
    ORDER  BY department_id, last_name;

    DBMS_OUTPUT.PUT_LINE('Fetched: ' || l_emps.COUNT);

    -- Dot-notation field access
    FOR i IN 1 .. l_emps.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE(
            l_emps(i).employee_id || '  ' ||
            l_emps(i).last_name   || '  ' ||
            l_emps(i).department_id
        );
    END LOOP;
END;
/
```

### BULK COLLECT into Partial-Row Collection (%TYPE)

When you only need a subset of columns, declare the type with individual `%TYPE` anchors rather than `%ROWTYPE` to avoid pulling unused data into PGA memory.

```sql
DECLARE
    -- Only the columns we actually need
    TYPE r_emp IS RECORD (
        employee_id  employees.employee_id%TYPE,
        last_name    employees.last_name%TYPE,
        salary       employees.salary%TYPE,
        dept_id      employees.department_id%TYPE
    );
    TYPE t_emp_tab IS TABLE OF r_emp;
    l_emps t_emp_tab;
BEGIN
    SELECT employee_id, last_name, salary, department_id
    BULK COLLECT INTO l_emps
    FROM   employees
    WHERE  salary > 10000;

    FOR i IN 1 .. l_emps.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE(
            l_emps(i).last_name || ' dept=' || l_emps(i).dept_id
        );
    END LOOP;
END;
/
```

### BULK COLLECT with LIMIT (Cursor + Batching)

> **Critical pattern for large tables.** Without `LIMIT`, all rows load into memory at once — a risk on million-row tables.

```sql
DECLARE
    TYPE t_emp_tab IS TABLE OF employees%ROWTYPE;
    l_emps  t_emp_tab;
    l_batch CONSTANT PLS_INTEGER := 1000;

    CURSOR c_emps IS
        SELECT * FROM employees ORDER BY employee_id;
BEGIN
    OPEN c_emps;

    LOOP
        FETCH c_emps BULK COLLECT INTO l_emps LIMIT l_batch;

        -- Process this batch
        FOR i IN 1 .. l_emps.COUNT LOOP
            -- your row-level logic here
            NULL;
        END LOOP;

        EXIT WHEN l_emps.COUNT < l_batch;  -- last batch
    END LOOP;

    CLOSE c_emps;
END;
/
```

### BULK COLLECT from DML with RETURNING

`RETURNING ... INTO` lets a DML statement hand data back to PL/SQL in the same round-trip — no follow-up `SELECT` needed. Combined with `BULK COLLECT`, it populates a collection with the affected rows' values the moment the DML executes.

**Why it matters:**

- Eliminates a second query to find out what was changed
- Runs in one SQL-to-PL/SQL context switch instead of two
- Works with `INSERT`, `UPDATE`, and `DELETE`
- Can return multiple columns into parallel collections or a record collection

**Syntax:**

```sql
DML ...
RETURNING col1, col2, ...
BULK COLLECT INTO collection1, collection2, ...;
```

The collections are always **replaced**, not appended — each DML execution re-populates them from scratch.

#### Single Column — Capture Updated IDs

```sql
DECLARE
    TYPE t_ids IS TABLE OF employees.employee_id%TYPE;
    l_updated_ids t_ids;
BEGIN
    UPDATE employees
    SET    salary = salary * 1.10
    WHERE  department_id = 80
    RETURNING employee_id BULK COLLECT INTO l_updated_ids;

    DBMS_OUTPUT.PUT_LINE('Updated: ' || l_updated_ids.COUNT || ' rows');

    -- l_updated_ids now holds every employee_id that was touched
    FOR i IN 1 .. l_updated_ids.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE('  -> emp_id: ' || l_updated_ids(i));
    END LOOP;
END;
/
```

#### Multiple Columns — Parallel Collections

```sql
DECLARE
    TYPE t_ids   IS TABLE OF employees.employee_id%TYPE;
    TYPE t_names IS TABLE OF employees.last_name%TYPE;
    TYPE t_sals  IS TABLE OF employees.salary%TYPE;

    l_ids   t_ids;
    l_names t_names;
    l_sals  t_sals;
BEGIN
    UPDATE employees
    SET    salary = salary * 1.10
    WHERE  department_id = 80
    RETURNING employee_id, last_name, salary
    BULK COLLECT INTO l_ids, l_names, l_sals;

    -- l_sals(i) is the NEW salary (value after the update)
    FOR i IN 1 .. l_ids.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE(
            l_names(i) || ' new salary: ' || l_sals(i)
        );
    END LOOP;
END;
/
```

> **Note:** `RETURNING` gives you the **post-DML** values for `INSERT` and `UPDATE`, and the **pre-DML** values for `DELETE`.

#### DELETE — Capture Removed Rows

```sql
DECLARE
    TYPE t_ids   IS TABLE OF employees.employee_id%TYPE;
    TYPE t_names IS TABLE OF employees.last_name%TYPE;

    l_ids   t_ids;
    l_names t_names;
BEGIN
    DELETE FROM employees
    WHERE  hire_date < DATE '2000-01-01'
    RETURNING employee_id, last_name
    BULK COLLECT INTO l_ids, l_names;

    DBMS_OUTPUT.PUT_LINE('Deleted ' || l_ids.COUNT || ' employees:');
    FOR i IN 1 .. l_ids.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE('  ' || l_ids(i) || ' ' || l_names(i));
    END LOOP;
END;
/
```

#### INSERT with RETURNING

```sql
DECLARE
    TYPE t_ids IS TABLE OF employees.employee_id%TYPE;
    l_new_ids t_ids;
BEGIN
    INSERT INTO employees (employee_id, first_name, last_name,
                           email, hire_date, job_id, salary)
    SELECT employee_seq.NEXTVAL, 'Test', 'User' || ROWNUM,
           'TUSER' || ROWNUM, SYSDATE, 'IT_PROG', 5000
    FROM   dual
    CONNECT BY ROWNUM <= 5
    RETURNING employee_id BULK COLLECT INTO l_new_ids;

    DBMS_OUTPUT.PUT_LINE('Inserted IDs:');
    FOR i IN 1 .. l_new_ids.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE('  ' || l_new_ids(i));
    END LOOP;
END;
/
```

#### RETURNING Inside FORALL

`FORALL` also supports `RETURNING ... BULK COLLECT INTO`. The results accumulate across all iterations into a single collection.

```sql
DECLARE
    TYPE t_ids     IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    TYPE t_new_sal IS TABLE OF employees.salary%TYPE;

    l_emp_ids  t_ids;
    l_new_sals t_new_sal;
BEGIN
    l_emp_ids(1) := 101;
    l_emp_ids(2) := 102;
    l_emp_ids(3) := 103;

    FORALL i IN 1 .. l_emp_ids.COUNT
        UPDATE employees
        SET    salary = salary * 1.15
        WHERE  employee_id = l_emp_ids(i)
        RETURNING salary BULK COLLECT INTO l_new_sals;
        -- l_new_sals accumulates one row per FORALL iteration

    FOR i IN 1 .. l_new_sals.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE('New salary: ' || l_new_sals(i));
    END LOOP;
END;
/
```

---

## FORALL

`FORALL` sends DML statements in bulk from a collection to the SQL engine, eliminating per-row context switches.

### Basic FORALL

```sql
DECLARE
    TYPE t_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    l_ids t_ids;
BEGIN
    l_ids(1) := 101;
    l_ids(2) := 102;
    l_ids(3) := 107;

    -- All deletes sent to SQL engine in one batch
    FORALL i IN 1 .. l_ids.COUNT
        DELETE FROM employees WHERE employee_id = l_ids(i);

    DBMS_OUTPUT.PUT_LINE('Deleted: ' || SQL%ROWCOUNT);
END;
/
```

### FORALL with INDICES OF (Sparse Collections)

```sql
DECLARE
    TYPE t_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    l_ids t_ids;
BEGIN
    l_ids(1)  := 101;
    l_ids(5)  := 102;   -- gap at 2,3,4
    l_ids(10) := 107;

    -- INDICES OF skips gaps safely
    FORALL i IN INDICES OF l_ids
        DELETE FROM employees WHERE employee_id = l_ids(i);
END;
/
```

### FORALL with VALUES OF

```sql
DECLARE
    TYPE t_idx_list IS TABLE OF PLS_INTEGER INDEX BY PLS_INTEGER;
    TYPE t_ids      IS TABLE OF NUMBER      INDEX BY PLS_INTEGER;

    l_which t_idx_list;   -- which indices to process
    l_ids   t_ids;
BEGIN
    l_ids(1) := 101; l_ids(2) := 102; l_ids(3) := 103; l_ids(4) := 104;
    -- Only process indices 1 and 3
    l_which(1) := 1; l_which(2) := 3;

    FORALL i IN VALUES OF l_which
        DELETE FROM employees WHERE employee_id = l_ids(i);
END;
/
```

### FORALL with SAVE EXCEPTIONS

> Without `SAVE EXCEPTIONS`, the first DML error rolls back the entire `FORALL`. With it, Oracle continues and collects all errors in `SQL%BULK_EXCEPTIONS`.

```sql
DECLARE
    TYPE t_ids  IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    l_ids       t_ids;
    l_err_count PLS_INTEGER;

    bulk_errors EXCEPTION;
    PRAGMA EXCEPTION_INIT(bulk_errors, -24381);
BEGIN
    l_ids(1) := 101;
    l_ids(2) := -999;   -- will violate a constraint
    l_ids(3) := 103;

    BEGIN
        FORALL i IN 1 .. l_ids.COUNT SAVE EXCEPTIONS
            DELETE FROM employees WHERE employee_id = l_ids(i);
    EXCEPTION
        WHEN bulk_errors THEN
            l_err_count := SQL%BULK_EXCEPTIONS.COUNT;
            FOR i IN 1 .. l_err_count LOOP
                DBMS_OUTPUT.PUT_LINE(
                    'Error at index ' || SQL%BULK_EXCEPTIONS(i).ERROR_INDEX ||
                    ': ' || SQLERRM(-SQL%BULK_EXCEPTIONS(i).ERROR_CODE)
                );
            END LOOP;
    END;
END;
/
```

---

## Use Cases

|Pattern|Best Collection|Notes|
|---|---|---|
|Lookup / cache by string key|Associative Array (VARCHAR2 index)|O(log n) access, no init needed|
|Staging rows from a query|Nested Table (via BULK COLLECT)|Use LIMIT to control memory|
|Bulk DML back to database|Any (via FORALL)|INDICES OF for sparse|
|Fixed-size config list|VARRAY|Stored in a single DB column|
|Passing ID lists to SQL|Nested Table (schema-level type)|TABLE() operator|
|Row-by-row avoidance|Nested Table + BULK COLLECT + FORALL|The core "bulk processing" pattern|
|Deduplication or set ops|Nested Table|Supports MULTISET operators|
|Per-session memo / cache|Associative Array|Keyed by natural key (e.g. emp_id)|

### The Core Bulk Pattern (Full Example)

```sql
-- Read rows in batches, transform, write back — zero row-by-row context switches
DECLARE
    TYPE t_emp_tab IS TABLE OF employees%ROWTYPE;
    TYPE t_sal_tab IS TABLE OF employees.salary%TYPE INDEX BY PLS_INTEGER;

    l_emps   t_emp_tab;
    l_sals   t_sal_tab;
    l_batch  CONSTANT PLS_INTEGER := 500;

    CURSOR c IS
        SELECT * FROM employees WHERE department_id = 80;
BEGIN
    OPEN c;
    LOOP
        FETCH c BULK COLLECT INTO l_emps LIMIT l_batch;
        EXIT WHEN l_emps.COUNT = 0;

        -- Transform
        FOR i IN 1 .. l_emps.COUNT LOOP
            l_sals(i) := l_emps(i).salary * 1.05;
        END LOOP;

        -- Bulk write
        FORALL i IN 1 .. l_emps.COUNT
            UPDATE employees
            SET    salary = l_sals(i)
            WHERE  employee_id = l_emps(i).employee_id;

        COMMIT;
    END LOOP;
    CLOSE c;
END;
/
```

---

## Limitations & Gotchas

### General

|Limitation|Detail|
|---|---|
|Single dimension only|PL/SQL collections are 1D. Simulate 2D with a collection of records or a collection of collections.|
|No native sorting|You must implement bubble/quick sort or use SQL (`SELECT * FROM TABLE(...)`)|
|No set operations on AA|MULTISET operators (UNION, INTERSECT, EXCEPT) work on Nested Tables only|
|Integer overflow on COUNT|`.COUNT` returns `INTEGER`. With billions of rows, prefer cursor-based pagination|
|Associative arrays not in SQL|You cannot use `TABLE(l_assoc_array)` in a SQL statement|
|Schema-level type required for SQL|`TABLE()` only works with types created with `CREATE TYPE`, not block-level `TYPE ... IS TABLE OF`|

### Initialization Errors

```sql
-- COLLECTION_IS_NULL — accessing a never-initialized NT or VARRAY
DECLARE
    TYPE t_n IS TABLE OF NUMBER;
    l_n t_n;   -- NULL, not empty
BEGIN
    l_n.EXTEND;      -- ORA-06531: Reference to uninitialized collection
END;

-- Fix: initialize before use
l_n := t_n();
```

### Subscript Errors

```sql
-- ORA-06533: Subscript beyond count
DECLARE
    TYPE t_n IS TABLE OF NUMBER;
    l_n t_n := t_n(1,2,3);
BEGIN
    l_n(5) := 99;   -- ERROR: index 5 does not exist, only 1..3
    -- Fix: l_n.EXTEND(2); then l_n(5) := 99;
END;

-- ORA-01403 / NO_DATA_FOUND on sparse table without EXISTS()
DECLARE
    TYPE t_n IS TABLE OF NUMBER;
    l_n t_n := t_n(10,20,30);
BEGIN
    l_n.DELETE(2);   -- now sparse
    FOR i IN 1..l_n.LAST LOOP
        DBMS_OUTPUT.PUT_LINE(l_n(i));  -- crashes at i=2
        -- Fix: wrap in IF l_n.EXISTS(i) THEN
    END LOOP;
END;
```

### Memory

- `BULK COLLECT` without `LIMIT` loads **all rows** into PGA memory. On large tables this can cause ORA-04030 (out-of-process memory). Always use `LIMIT` with a cursor.
- Collections live in the **PGA** (session memory), not the SGA. Extremely large collections affect the session, not the shared pool.
- Collections are freed when they go out of scope. For package-level collections, call `.DELETE` explicitly to release memory.

### VARRAY-Specific

- Cannot use `.DELETE(n)` on a VARRAY — only `.TRIM` from the end.
- `.LIMIT` is fixed at type definition; cannot be changed at runtime.
- Always dense — no sparse behavior possible.

### FORALL-Specific

- `FORALL` supports only a **single DML statement** per clause.
- The collection index in `FORALL i IN 1..n` must be contiguous unless `INDICES OF` or `VALUES OF` is used.
- Without `SAVE EXCEPTIONS`, the first failure halts the entire batch and rolls it back.
- `SQL%ROWCOUNT` after `FORALL` returns the **total** rows affected across all iterations, not per-iteration counts. Use `SQL%BULK_ROWCOUNTS(i)` for per-row counts.

```sql
-- Per-row DML counts after FORALL
FORALL i IN 1..l_ids.COUNT
    DELETE FROM employees WHERE employee_id = l_ids(i);

FOR i IN 1..l_ids.COUNT LOOP
    DBMS_OUTPUT.PUT_LINE('Row ' || i || ' deleted: ' || SQL%BULK_ROWCOUNTS(i));
END LOOP;
```

---

_Document covers Oracle Database 12c and later. Some features (e.g., `INDICES OF`, `VALUES OF`) require 10g+._