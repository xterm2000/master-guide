---
title: jq guide
type: reference
audience: llm-agent, human
---

# jq guide

Sample data for every example below (`jq_guide_sample.json`): 3 objects,
4 fields each, one with 2 children, two with 0.

```json
[
  { "id": 1, "name": "Alpha", "table": "tbl_alpha", "children": [] },
  { "id": 2, "name": "Beta",  "table": "tbl_beta",  "children": [] },
  { "id": 3, "name": "Gamma", "table": "tbl_gamma", "children": [
      { "name": "child_a", "table": "tbl_child_a" },
      { "name": "child_b", "table": "tbl_child_b" }
    ]
  }
]
```

---

# Part 1: the mechanics (read this first, not last)

A jq **filter** takes one JSON input and produces a **stream** of zero,
one, or many JSON outputs. `|` feeds the left filter's output stream into
the right filter, one item at a time, independently. That's the whole
model -- every command in this guide is just a different way of doing one
of three things to that stream:

- **STAYS** -- 1 in, 1 out. `.`, `.foo`, `length`, `type`.
- **EXPLODES** -- 1 in, MANY out. `.[]`, `paths`, `,`.
- **DROPS** -- 1 in, 0 out. `select(false)`, `empty`.

(Those 3 are exhaustive -- any output count is 0, 1, or more than 1,
nothing else is possible.)

One more mechanism, on a different axis -- it doesn't act on "one input,"
it closes a whole STREAM back down to a single value:

- **`[ ... ]`** (the array collector), plus `-s`/slurp and `reduce`.

Trace one real pipeline through explode / drop / explode / stays,
watching the item count at every stage:

```bash
jq '.[] | select(.children|length>0) | .children[] | .name' jq_guide_sample.json
```
```
"child_a"
"child_b"
```
```
[ {Alpha}, {Beta}, {Gamma} ]      <- 1 array
        │  .[]                        EXPLODES
        ▼
 {Alpha} {Beta} {Gamma}            <- 3 items
        │  select(.children|length>0)  DROPS (2 dropped: empty children)
        ▼
       {Gamma}                     <- 1 item survives
        │  .children[]                EXPLODES
        ▼
  {child_a} {child_b}              <- 2 items
        │  .name                      STAYS (transforms each, count unchanged)
        ▼
  "child_a"  "child_b"             <- 2 items, final output
```

Wrap it in `[ ... ]` and the 2-item stream collapses to one array:
```bash
jq -c '[.[] | select(.children|length>0) | .children[] | .name]' jq_guide_sample.json
# -> ["child_a","child_b"]
```

**`[ ... ]` never implies iteration on its own.** It runs whatever's
inside against the current `.` and wraps however many outputs that
produces into one array -- if there's no `.[]` inside, nothing explodes:

```bash
jq '.[] | length' jq_guide_sample.json      # explode first (3 objects), length of EACH (4 keys)
# -> 4   4   4                               3 separate outputs

jq -c '[length]' jq_guide_sample.json        # NO explosion -- length of the WHOLE array (3), wrapped
# -> [3]                                     1 output

jq -c '[.[] | length]' jq_guide_sample.json  # explode, length each, THEN collect
# -> [4,4,4]                                 1 output, holding 3 collected values
```

One nuance worth flagging now: `map(f)` and `add` explode-and-recollect
*internally*, but from the outside one array goes in and one array/value
comes out -- so as a black box they're STAYS, not the collector mechanism:
```bash
jq -c '. as $b | (map(.name)|length), ($b|length)' jq_guide_sample.json
# -> 3   3     -- one 3-element array in, one 3-element array out
```

---

# Part 2: looking at data you don't know yet

Before filtering anything, inspect it. This is the toolkit for "what am I
even looking at":

## `.` -- identity

Works on: anything. Input, unchanged -- the starting point for everything else.
```bash
jq '.' jq_guide_sample.json
```

## `type` -- which of the 6 JSON kinds

Works on: anything. `"null"`, `"boolean"`, `"number"`, `"string"`, `"array"`, `"object"`.
```bash
jq '.[0] | type' jq_guide_sample.json   # -> "object"
jq 'type' jq_guide_sample.json          # -> "array"
```

## `keys` -- list the keys/indices

Works on: **array or object** (array -> `[0,1,...]`, object -> sorted key names).
```bash
jq '.[0] | keys' jq_guide_sample.json
# -> ["children","id","name","table"]
```

## `[.[]]` -- get the values (the counterpart to `keys`)

Works on: **array or object**. Collects an object's values into an array,
the same way `keys` collects its key names -- but **not sorted**, unlike
`keys`:
```bash
echo '{"b":1,"a":2}' | jq 'keys'    # -> ["a","b"]   SORTED
echo '{"b":1,"a":2}' | jq '[.[]]'   # -> [1,2]       ORIGINAL order (b, then a)
```
So `keys[i]` and `[.[]][i]` don't line up when order differs. Need them
paired? Use `to_entries` (`[{key,value}, ...]`, original order).

Naming trap: jq also has a builtin literally called `values` (`values/0`),
but it means something unrelated -- "drop nulls from a stream," not "get
an object's values":
```bash
echo '{"a":1,"b":null}' | jq '.[] | values'   # -> 1   (only b's null is dropped)
```

## `length` -- count

Works on: **anything** -- array -> element count, object -> key count,
string -> char count, number -> its absolute value, null -> 0.
```bash
jq 'length' jq_guide_sample.json        # -> 3   (array)
jq '.[0] | length' jq_guide_sample.json # -> 4   (object, 4 keys)
```

---

# Part 3: navigating structure you DO know

## `.foo` -- field access

Works on: **object only**.
```bash
jq '.[0].name' jq_guide_sample.json   # -> "Alpha"
```

## `.[N]` -- index one element

Works on: **array only**.
```bash
jq '.[0]' jq_guide_sample.json
# -> {"id":1,"name":"Alpha","table":"tbl_alpha","children":[]}
```

## `.[a:b]` -- slice a range

Works on: **array only**. `a` inclusive, `b` exclusive.
```bash
jq -c '.[0:2]' jq_guide_sample.json      # -> array of Alpha, Beta
jq '.[0:2] | type' jq_guide_sample.json  # -> "array" -- still an array, not its contents
```
Immediate next question this raises: a slice is still `type=="array"`, so
you can't `.foo` it directly:
```bash
jq '.[0:2].name' jq_guide_sample.json
# -> jq: error: Cannot index array with string "name"
```
Fix -- explode first: `.[0:2][].name` or `.[0:2] | map(.name)`.

## `.[]` -- explode into many outputs

Works on: **array or object** (array -> elements, object -> values).
```bash
jq '.[] | .name' jq_guide_sample.json
```
```
"Alpha"
"Beta"
"Gamma"
```
```
[ {...}, {...}, {...} ]      <- ONE array, 3 elements
        │  .[]
        ▼
  {...}   {...}   {...}      <- THREE separate outputs
    │       │       │  .name
    ▼       ▼       ▼
 "Alpha"  "Beta"  "Gamma"
```

---

# Part 4: filtering

## `select(cond)` -- keep only if true

Works on: anything (a gate, not type-specific).
```bash
jq '.[] | select(.children | length > 0)' jq_guide_sample.json
# -> {"id":3,"name":"Gamma", ...}
```

**Next question this raises:** what if the condition lives one level
down, inside a nested array (like `children`)? Plain
`select(.children[].name=="child_a")` looks reasonable but has two real
bugs:
```bash
echo '{"children":[]}' | jq 'select(.children[].n=="x")'
# -> nothing at all -- empty children produced NO boolean, so it's silently DROPPED, not "false"

echo '{"children":[{"n":"x"},{"n":"x"}]}' | jq -c 'select(.children[].n=="x")'
# -> prints the object TWICE -- once per matching child, a duplicate bug
```
Fix: `any(generator; condition)` collapses the child stream to one
true/false first, so the parent is emitted at most once, and zero
children correctly means false:
```bash
jq -c '.[] | select(any(.children[]?; .name=="child_a"))' jq_guide_sample.json
# -> {"id":3,"name":"Gamma", ...}
```

## Filtering by pattern, not just exact equality: regex

`select(.foo == "x")` only matches exact strings. For a pattern, jq has
real regex support (Oniguruma) via `test`/`match`/`capture`/`sub`/`gsub`.
`test(regex)` is the one that goes inside `select`:

```bash
jq -c '.[] | select(.table | test("^tbl_[ab]"))' jq_guide_sample.json
# -> {"id":1,"name":"Alpha",...}  {"id":2,"name":"Beta",...}

jq '.[] | select(.name | test("alpha"; "i")) | .name' jq_guide_sample.json
# -> "Alpha"     ("i" flag = case-insensitive)
```

| function | does |
|---|---|
| `test(regex)` / `test(regex; "i")` | true/false -- goes inside `select` |
| `match(regex)` | full match details: offset, length, capture groups |
| `capture(regex)` | named groups as an object: `capture("tbl_(?<suffix>.*)")` -> `{"suffix":"alpha"}` |
| `sub(regex; repl)` | replace first match |
| `gsub(regex; repl)` | replace all matches |

---

# Part 5: transforming and collecting

## `map(f)` -- transform every element

Works on: **array**.
```bash
jq -c 'map(.name)' jq_guide_sample.json
# -> ["Alpha","Beta","Gamma"]
```
**Next question this raises:** what if the input is an object, not an
array? `map(f)` still runs -- but silently drops the keys:
```bash
echo '{"a":1,"b":2}' | jq -c 'map(.+1)'         # -> [2,3]        keys GONE, now an array
echo '{"a":1,"b":2}' | jq -c 'map_values(.+1)'  # -> {"a":2,"b":3} keys kept
```
Use `map_values` when the input is an object and you want it to stay one.

## `[ f ]` -- array collector

Gathers a stream of outputs back into one array (see Part 1 for the
full mechanics):
```bash
jq -c '[.[] | select(.children|length>0) | .name]' jq_guide_sample.json
# -> ["Gamma"]
```

## `unique` -- dedupe a collected array

Works on: **array** (needs a collected array, not a live stream -- collect
first with `[ ]`, then dedupe):
```bash
jq -c '[.[] | type] | unique' jq_guide_sample.json
# -> ["object"]
```
Outside jq, `sort -u` does the same job on plain text (needs `-r` since
it doesn't understand JSON string quoting):
```bash
jq -r '.[] | type' jq_guide_sample.json | sort -u
# -> object
```
Use `unique` when staying inside a jq pipeline; use `sort -u` only once
you're handing the result to a non-jq shell tool anyway.

## String interpolation `"...\(.foo)..."`

Works on: anything. Splices a filter's result into a string:
```bash
jq '.[] | "\(.name):\(.table)"' jq_guide_sample.json
```
```
"Alpha:tbl_alpha"
"Beta:tbl_beta"
"Gamma:tbl_gamma"
```

## `if/then/else/end` -- inline conditional

Works on: anything -- a value expression, usable anywhere.
```bash
jq '.[] | if (.children|length) > 0 then "has children" else "no children" end' jq_guide_sample.json
```
```
"no children"
"no children"
"has children"
```

---

## Quick reference: everything above

| command | works on | does |
|---|---|---|
| `.` | anything | passthrough |
| `type` | anything | which of the 6 JSON types |
| `keys` | array or object | list indices/key-names (sorted) |
| `[.[]]` | array or object | list values (NOT sorted) |
| `length` | anything | count (per-type rules above) |
| `.foo` | object | get a field by name |
| `.[N]` | array | get an element by index |
| `.[a:b]` | array | slice a range (still an array) |
| `.[]` | array or object | explode into many outputs |
| `select(cond)` | anything | keep only if `cond` is true |
| `any(gen; cond)` | anything | true if ANY item from `gen` satisfies `cond` |
| `map(f)` | array | transform every element |
| `map_values(f)` | object | transform every value, keep the keys |
| `[ f ]` | any stream | collect outputs into one array |
| `unique` | array | dedupe (needs a collected array) |
| `if/then/else/end` | anything | inline conditional |

---

# Part 6: searching data of unknown depth

## `paths(scalars)` -- address of every leaf value

Works on: array or object. Recurses the whole tree and returns the
address to every leaf, regardless of depth:
```bash
jq -c '.[2] | [paths(scalars)]' jq_guide_sample.json
```
```json
[["id"],["name"],["table"],["children",0,"name"],["children",0,"table"],["children",1,"name"],["children",1,"table"]]
```

Real-world use: find a VALUE anywhere without knowing which field holds
it or how deep it sits:
```bash
jq -c '[paths(scalars) as $p | select(getpath($p)=="tbl_child_a") | $p]' jq_guide_sample.json
# -> [[2,"children",0,"table"]]
```
On the full pipeline dataset, this finds a value regardless of shape --
some matches are a record's own field, others nested one level down,
in a single query that a shape-specific filter would miss half of:
```bash
jq '[paths(scalars) as $p | select(getpath($p)=="plan") | $p] | length' outputs/dbr_child_tables.json
# -> 13
```

## `path(f)` -- the address of ONE thing you name

Different from `paths(scalars)`: that gives you *every* leaf
automatically; `path(f)` gives you the address of the *one* expression
`f` you specify -- useful when you need to patch a value whose position
you don't know ahead of time (pairs with `setpath`):
```bash
jq -c '.[2] | path(.children[] | select(.name=="child_b"))' jq_guide_sample.json
# -> ["children",1]   -- found the index for you, didn't have to hardcode it
```

---

# Part 7: how to approach a query

Same data, different starting question -- pick the angle that matches
what you actually know:

- **Schema-first** (don't know the shape): `jq '.[0] | type, keys' file.json`
- **Search-first** (know a value, not its location): the `paths(scalars)` pattern above
- **Aggregate-first** (want a distribution, not one record):
  ```bash
  jq -c '[.[] | .children|length] | group_by(.) | map({n: .[0], count: length})' jq_guide_sample.json
  # -> [{"n":0,"count":2},{"n":2,"count":1}]
  ```
- **Incremental**: build one `|` stage at a time, test after each, before adding the next.
- **Defensive** (heterogeneous data): reach for `select`/`any`/`try` *before* writing the risky part, not after it crashes.

---

# Part 8: CLI flags

`jq [flags] 'filter' file.json` -- flags go before the filter.

| flag | does | use case |
|---|---|---|
| `-r` | print strings unquoted | piping into a shell command expecting plain text |
| `-c` | compact, one line per value | piping into `grep`/`wc -l`/another `jq` |
| `-n` | skip reading input; `.` is `null` | quick calculations, building JSON from scratch |
| `-s` | slurp: wrap ALL input docs into ONE array | turn a stream of separate JSON objects into one array |
| `-e` | exit code reflects output truthiness | using jq as a condition in a shell script |
| `--arg name value` | inject a shell value as `$name` | parameterize a filter safely |

```bash
jq -r '.[0].name' jq_guide_sample.json    # -> Alpha (unquoted)
jq -c '.[0]' jq_guide_sample.json          # -> {"id":1,...} (one line)
jq -n '1+1'                                # -> 2
printf '{"a":1}\n{"a":2}\n' | jq -s -c '.' # -> [{"a":1},{"a":2}]
jq -e '.[2].children|length>0' jq_guide_sample.json; echo "exit:$?"  # -> true  exit:0
name="Alpha"; jq --arg name "$name" -c '.[]|select(.name==$name)' jq_guide_sample.json
```

---

# Part 9: keywords

Actually reserved -- verified: cannot be redefined.

`if` `then` `elif` `else` `end`  `def`  `as`  `reduce`  `foreach`  `try` `catch`  `import` `include`  `label`  `and` `or`

Everything else (`length`, `select`, `map`, `keys`, `paths`, `scalars`,
`type`...) is an ordinary builtin *function*, not a keyword:
```bash
jq -n 'def scalars: "x"; 5 | scalars'   # -> "x"   compiles fine, silently overrides the real one
jq -n 'def if: 1; 1'                    # -> syntax error: unexpected if, expecting IDENT
```
Surprising non-keywords, just ordinary names: `true`, `false`, `null`, `not`, `empty`, `error`.

---

# Part 10: sharp edges (rare, but will bite you eventually)

## `,` binds looser than `|` -- mixed-type streams can abort mid-run

```bash
jq '.[0],.[2]|type' jq_guide_sample.json
# -> "object"   "object"
```
Each comma branch runs on the *original* input, outputs merge, then
`|type` runs once per merged output. Danger: if a later filter only
works on one type, a mismatched item **aborts everything after it**:
```bash
jq '.[0],.[2].children,.[1] | .name' jq_guide_sample.json
```
```
jq: error: Cannot index array with string "name"
"Alpha"
```
`.[1]` (fine, listed last) never printed. Fixes: `select(type=="object")`, `if/then/else`, `try/catch`.

## `length` of a number is its absolute value -- not "1"

```bash
jq '.[2] | length' jq_guide_sample.json       # -> 4  (4 keys)
jq -n '4 | length'                             # -> 4  (abs(4) -- unrelated rule, same digit)
jq '.[2]|length|length' jq_guide_sample.json   # -> 4  (looks like a no-op, isn't)
```
```
{Gamma, 4 keys}
     │ length        <- "how many keys" (object rule)
     ▼
     4                <- now a plain NUMBER
     │ length         <- "abs value" (number rule -- unrelated meaning)
     ▼
     4                <- same digit, DIFFERENT operation
```

## `try/catch` -- `.` inside `catch` is the ERROR, not the original item

```bash
jq '.[0],.[2] | . as $it | try ($it.children|length|keys) catch "on \($it.name): \(.)"' jq_guide_sample.json
```
```
"on Alpha: number (0) has no keys"
"on Gamma: number (2) has no keys"
```
Capture the item with `as $it` *before* the risky call -- bare `.` inside
`catch` gives the error's own value, not the original item's.

## Terminology: "map" is not a third container type

JSON has exactly two containers: array and object. What other languages
call a map/dict/hash *is* what JSON calls an object. jq's `map(f)`
function is unrelated naming (functional-programming vocabulary), not
evidence of a third type.

---

# Part 11: jqp -- interactive jq playground (TUI)

Install:
```bash
curl -sL https://github.com/noahgorstein/jqp/releases/download/v0.8.0/jqp_Linux_x86_64.tar.gz -o /tmp/jqp.tar.gz
tar -xzf /tmp/jqp.tar.gz -C /tmp jqp
mkdir -p ~/.local/bin
mv /tmp/jqp ~/.local/bin/
chmod +x ~/.local/bin/jqp
rm /tmp/jqp.tar.gz
jqp --version
```

