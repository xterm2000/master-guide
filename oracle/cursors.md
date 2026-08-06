---
domain: oracle
year: 2026
---

# Oracle PL/SQL Cursors

## Contents

- [[#Implicit vs Explicit Cursors]]
- [[#When to Use OPEN / FETCH / CLOSE]]
- [[#Common Cursor Use Cases]]
- [[#Cursor Attributes]]
- [[#Collection Types]]
- [[#BULK COLLECT Behavior]]

---

## Implicit vs Explicit Cursors

### Implicit (inline FOR loop)

```sql
FOR rec IN (SELECT * FROM orders WHERE status = 'PENDING') LOOP
  -- Oracle handles OPEN and CLOSE automatically
END LOOP;
```

### Explicit (declared cursor)

```sql
CURSOR c_orders IS SELECT * FROM orders WHERE status = 'PENDING';

FOR rec IN c_orders LOOP
  -- Oracle still handles OPEN and CLOSE
END LOOP;
```

### Benefits of declaring explicitly

|Benefit|Notes|
|---|---|
|Reusability|Reference the same cursor multiple times|
|Parameterization|Accept input values — impossible with inline cursors|
|Readability|SQL lives in one named place at the top|
|Fine-grained control|Manual OPEN / FETCH / CLOSE, BULK COLLECT with LIMIT|
|Clearer attributes|`c_cursor%ROWCOUNT` vs ambiguous `SQL%ROWCOUNT`|

**Rule of thumb:** use inline for simple one-shot loops; switch to explicit when you need parameters, reuse, bulk fetching, or complex flow control.

---

## When to Use OPEN / FETCH / CLOSE

The FOR loop (implicit or explicit) handles open/close automatically. Manual control is needed when:

**Early exit / conditional logic**

```sql
OPEN c_orders;
LOOP
  FETCH c_orders INTO v_row;
  EXIT WHEN c_orders%NOTFOUND;

  IF v_row.status = 'X' THEN
    EXIT; -- bail out mid-cursor
  END IF;
END LOOP;
CLOSE c_orders;
```

**BULK COLLECT with LIMIT (large datasets)**

```sql
OPEN c_orders;
LOOP
  FETCH c_orders BULK COLLECT INTO l_rows LIMIT 1000;
  EXIT WHEN l_rows.COUNT = 0;

  FORALL i IN 1..l_rows.COUNT
    INSERT INTO target VALUES l_rows(i);
END LOOP;
CLOSE c_orders;
```

**REF CURSOR — passing cursors between procedures**

```sql
PROCEDURE get_data(p_cur OUT SYS_REFCURSOR) IS
BEGIN
  OPEN p_cur FOR SELECT * FROM employees;
  -- caller is responsible for closing
END;
```

|Situation|Manual OPEN/CLOSE?|
|---|---|
|FOR loop (implicit or explicit)|No|
|BULK COLLECT with LIMIT|Yes|
|Early exit / complex flow|Yes|
|REF CURSOR|Yes|

> Always close in an `EXCEPTION` block if opening manually — otherwise the cursor stays open on error.

---

## Common Cursor Use Cases

**Row-by-row business logic too complex for SQL**

```sql
FOR rec IN (SELECT * FROM orders WHERE status = 'PENDING') LOOP
  IF rec.amount > 10000 THEN
    apply_discount(rec.order_id);
  ELSIF rec.customer_tier = 'GOLD' THEN
    escalate_to_manager(rec.order_id);
  ELSE
    auto_approve(rec.order_id);
  END IF;
END LOOP;
```

**Calling a procedure or external API per row**

```sql
FOR rec IN (SELECT * FROM customers WHERE opted_in = 'Y') LOOP
  send_email_notification(rec.customer_id, rec.email);
  log_communication(rec.customer_id, 'EMAIL');
END LOOP;
```

**Dynamic DDL / admin scripting**

```sql
FOR rec IN (SELECT table_name FROM user_tables WHERE table_name LIKE 'TMP_%') LOOP
  EXECUTE IMMEDIATE 'DROP TABLE ' || rec.table_name;
END LOOP;
```

**Parent-child processing (nested cursors)**

```sql
FOR parent IN (SELECT * FROM invoices WHERE month = 6) LOOP
  calculate_invoice_header(parent.invoice_id);

  FOR child IN (SELECT * FROM invoice_lines WHERE invoice_id = parent.invoice_id) LOOP
    apply_tax_rule(child.line_id, parent.tax_code);
  END LOOP;
END LOOP;
```

**Data migration / transformation**

```sql
FOR rec IN (SELECT * FROM legacy_customers) LOOP
  v_formatted_phone := format_phone(rec.phone_raw);
  v_country_code    := resolve_country(rec.region_code);

  INSERT INTO new_customers VALUES (rec.id, v_formatted_phone, v_country_code, ...);
END LOOP;
```

> Cursors are a code smell for pure data manipulation — a single `UPDATE`, `MERGE`, or `INSERT ... SELECT` will outperform a cursor significantly. Use cursors when logic genuinely can't be expressed in SQL.

---

## Cursor Attributes

Four attributes, work on both implicit and explicit cursors.

|Attribute|Returns|Meaning|
|---|---|---|
|`%FOUND`|BOOLEAN|TRUE if last fetch returned a row|
|`%NOTFOUND`|BOOLEAN|TRUE if last fetch returned nothing|
|`%ROWCOUNT`|NUMBER|How many rows fetched so far|
|`%ISOPEN`|BOOLEAN|TRUE if cursor is currently open|

**Explicit cursor** — prefix with cursor name

```sql
OPEN c_orders;
LOOP
  FETCH c_orders INTO v_row;
  EXIT WHEN c_orders%NOTFOUND;

  dbms_output.put_line('Processed: ' || c_orders%ROWCOUNT);
END LOOP;
CLOSE c_orders;
```

**Implicit cursor** — use `SQL%attribute` after DML

```sql
UPDATE orders SET status = 'CLOSED' WHERE due_date < SYSDATE;

IF SQL%NOTFOUND THEN
  dbms_output.put_line('Nothing to update');
ELSE
  dbms_output.put_line('Updated ' || SQL%ROWCOUNT || ' rows');
END IF;
```

**`%ISOPEN` — guard before closing**

```sql
EXCEPTION
  WHEN OTHERS THEN
    IF c_orders%ISOPEN THEN  -- avoid ORA-01001
      CLOSE c_orders;
    END IF;
    RAISE;
```

**`%ROWCOUNT` — commit batching**

```sql
FOR rec IN (SELECT * FROM large_table) LOOP
  process(rec);

  IF MOD(c_cursor%ROWCOUNT, 500) = 0 THEN
    COMMIT;
  END IF;
END LOOP;
```

### Gotchas

- `%FOUND` / `%NOTFOUND` return NULL (not TRUE/FALSE) before the first fetch
- `SQL%ROWCOUNT` is overwritten by every DML — capture it immediately if needed
- `SQL%ISOPEN` is always FALSE for implicit cursors
- Cursor attributes are unavailable after a FOR loop ends

---

## Collection Types

Three collection types used with cursors:

||Nested Table|Index By PLS_INTEGER|Index By VARCHAR2|
|---|---|---|---|
|Needs initialization|Yes|No|No|
|BULK COLLECT target|Yes|Yes|No|
|FORALL source|Yes|Yes|No|
|Key type|Integer 1..N|Any integer|String|
|Random access by name|No|No|Yes|
|Can store in DB column|Yes|No|No|

**Nested table — requires manual init and EXTEND**

```sql
TYPE t_pp IS TABLE OF c_pp%ROWTYPE;
v_pp t_pp;

-- initialize first, extend before each element
v_pp := t_pp();
v_pp.EXTEND;
v_pp(1) := some_row;
```

**INDEX BY PLS_INTEGER — assign directly, no init needed**

```sql
TYPE t_pp IS TABLE OF c_pp%ROWTYPE INDEX BY PLS_INTEGER;
v_pp t_pp;

v_pp(1)   := some_row;   -- just assign
v_pp(100) := some_row;   -- sparse is fine
v_pp(-1)  := some_row;   -- negative keys work too
```

**INDEX BY VARCHAR2 — key-value map / lookup**

```sql
TYPE t_plan_map IS TABLE OF ph_plan%ROWTYPE INDEX BY VARCHAR2(50);
v_map t_plan_map;

FOR rec IN (SELECT * FROM ph_plan WHERE ...) LOOP
  v_map(rec.plan_id) := rec;  -- keyed by meaningful identifier
END LOOP;

-- lookup directly, no loop needed
IF v_map.EXISTS('1234567') THEN
  v_row := v_map('1234567');
END IF;
```

---

## BULK COLLECT Behavior

`BULK COLLECT INTO` automatically initializes and overwrites the collection on every fetch — no manual init needed.

```sql
TYPE t_pp IS TABLE OF c_pp%ROWTYPE INDEX BY PLS_INTEGER;
v_pp t_pp;

-- uninitialized here — doesn't matter
FETCH c_pp BULK COLLECT INTO v_pp;
-- v_pp is now populated
```

**Inside a loop — collection is replaced each iteration**

For a parameterized cursor, parameters are passed at `OPEN`, not at `FETCH`. You must OPEN and CLOSE manually inside the loop:

```sql
FOR plan_rec IN c_plans LOOP

  OPEN c_pp(plan_rec.plan_id);   -- parameter passed here
  FETCH c_pp BULK COLLECT INTO v_pp;
  CLOSE c_pp;

  OPEN c_pah(plan_rec.plan_id);
  FETCH c_pah BULK COLLECT INTO v_pah;
  CLOSE c_pah;

  -- process v_pp and v_pah

END LOOP;
```

> You cannot pass parameters at the FETCH step — FETCH only pulls rows from an already-opened cursor.

**Empty result — COUNT = 0, not NULL**

```sql
FETCH c_pp BULK COLLECT INTO v_pp;

FOR i IN 1..v_pp.COUNT LOOP  -- safely skips if empty
  ...
END LOOP;
```

> To accumulate across iterations instead of overwriting, append rows manually rather than relying on BULK COLLECT.