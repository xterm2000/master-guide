# icdiff
```bash

pip3 install icdiff --user
~/.local/bin/icdiff 6759-values-traefik.yaml 6759-values-traefik_2.yaml

alias icdiff="~/.local/bin/icdiff --"
```


# jq guide

> **jq** - a lightweight command-line JSON processor  
> Syntax: `jq [flags] [expression] [file...]`

## substitute for sponge 
```bash
jq '.foo = 1' file.json > tmp.json && mv tmp.json file.json
```

Or wrap it in a shell function so it feels like sponge:

```bash
# Add to ~/.bashrc or ~/.zshrc
sponge() { tmp=$(mktemp); cat > "$tmp" && mv "$tmp" "$1"; }
```

Then you can use it exactly like the real thing:

```bash
jq '.foo = 1' file.json | sponge file.json
```
---

## Reading Values

```bash
# Read a top-level key
jq '.name' file.json

# Read a nested key
jq '.spec.replicas' deployment.json

# Read an array element (0-indexed)
jq '.items[0]' file.json

# Read last element
jq '.items[-1]' file.json

# Read multiple keys at once
jq '.name, .version' file.json

# Read all array elements
jq '.items[]' file.json
```

---

## Exploring an Unfamiliar Structure

> When you don't know the shape of the JSON yet - list keys before writing a
> real query. `-r` only strips quotes from string *scalars*; an array like
> `keys` still prints as bracketed JSON unless you stream it with `keys[]`.

```bash
# List top-level keys (bracketed JSON array - quotes/commas intact)
jq 'keys' file.json

# List top-level keys, one bare key per line (the fix: keys[] streams them)
jq -r 'keys[]' file.json

# List keys of a nested object
jq -r '.tipsHistory | keys[]' file.json

# List keys of a nested object whose name has special characters (slashes, dots, spaces)
# - bracket form is required here, dot form (.projects.name) would break on "/"
jq -r '.projects["/home/user/project"] | keys[]' file.json

# See the type of every top-level value (object/array/string/number/etc.) alongside its key
jq -r 'to_entries[] | "\(.key): \(.value | type)"' file.json

# See the type of a value at a specific path, without dumping its contents
jq '.spec.template | type' deployment.json

# Show one level of structure without printing every leaf value
jq 'map_values(type)' file.json

# Count how many keys an object has (quick "how big is this thing" check)
jq '. | length' file.json

# Get a compact overview: for each top-level key, print its type and, for
# arrays/objects, how many elements/keys it holds ("-" for scalars, since
# `length` errors on booleans and is meaningless on numbers/strings-as-count)
jq -r 'to_entries[] | "\(.key): \(.value|type)(\(.value | if (type=="object" or type=="array") then length else "-" end))"' file.json
```

**Same idea, simpler - skip string interpolation, let jq's own object/array output do the formatting:**

```bash
# Every top-level key paired with its type, as plain JSON objects (no \(...) escaping)
jq 'to_entries | map({(.key): (.value|type)})' file.json

# Every "path" to every scalar leaf in the whole document - the fastest way
# to see the real shape of a file you've never opened before
jq '[paths(scalars)]' file.json

# Same, but flat and one-per-line (easier to grep through)
jq -c 'paths(scalars)' file.json

# All the distinct key-sets used by objects anywhere in the tree
# (useful when nested objects don't all share the same shape)
jq '[.. | objects | keys] | unique' file.json
```

---

## Writing / Updating Values

> jq is read-only by default - it does not edit files in-place.  
> Use shell redirection or `sponge` (from moreutils) to update files.

```bash
# Update a key and write back
jq '.spec.replicas = 3' file.json | sponge file.json

# Or with a temp file
jq '.spec.replicas = 3' file.json > tmp.json && mv tmp.json file.json

# Set a new key
jq '.metadata.label = "prod"' file.json | sponge file.json

# Update a nested key
jq '.config.timeout = 30' file.json | sponge file.json

# Append to an array
jq '.items += ["newitem"]' file.json | sponge file.json

# Delete a key
jq 'del(.metadata.annotations)' file.json | sponge file.json
```

---

## Nested Structures

Given this example JSON:

```json
{
  "app": {
    "name": "myservice",
    "version": "2.1.0",
    "config": {
      "database": {
        "host": "db.internal",
        "port": 5432,
        "credentials": {
          "user": "admin",
          "password": "secret"
        }
      },
      "cache": {
        "host": "redis.internal",
        "ttl": 300
      }
    },
    "replicas": [
      {
        "region": "us-east",
        "count": 3,
        "settings": { "autoscale": true, "maxCount": 10 }
      },
      {
        "region": "eu-west",
        "count": 2,
        "settings": { "autoscale": false, "maxCount": 5 }
      }
    ]
  }
}
```

```bash
# Read a deeply nested scalar
jq '.app.config.database.host' app.json
# → "db.internal"

# Read a value 3+ levels deep
jq '.app.config.database.credentials.user' app.json
# → "admin"

# Update a deeply nested value
jq '.app.config.database.port = 5433' app.json | sponge app.json

# Add a new key deep in the tree
jq '.app.config.database.pool = {"maxSize": 20}' app.json | sponge app.json

# Delete a nested key
jq 'del(.app.config.cache.ttl)' app.json | sponge app.json

# Read a nested key from a specific array element
jq '.app.replicas[0].settings.autoscale' app.json
# → true

# Read a nested field from every array element
jq '.app.replicas[].region' app.json
# → "us-east"
# → "eu-west"

# Filter array elements by a nested field value
jq '.app.replicas[] | select(.settings.autoscale == true)' app.json

# Update a nested field across ALL array elements
jq '.app.replicas[].settings.maxCount = 15' app.json | sponge app.json

# Update a nested field only in matching array elements
jq '(.app.replicas[] | select(.region == "eu-west") | .count) = 4' app.json | sponge app.json

# Extract just nested sub-objects from each array element
jq '.app.replicas[] | .settings' app.json

# Collect a nested field from all array elements into a new array
jq '[.app.replicas[].region]' app.json
# → ["us-east", "eu-west"]

# Read multiple nested paths at once
jq '.app.config.database.host, .app.config.cache.host' app.json

# Check if a deeply nested key exists
jq '.app.config.database | has("credentials")' app.json
# → true

# Rebuild a new object from nested fields (projection)
jq '.app.replicas[] | {region: .region, max: .settings.maxCount}' app.json

# Swap a nested value using another nested value
jq '.app.config.cache.ttl = .app.config.database.port' app.json | sponge app.json

# Recursively search all values for keys named "host"
jq '.. | objects | .host? // empty' app.json
# → "db.internal"
# → "redis.internal"

# Extract a nested sub-tree as compact JSON
jq -c '.app.config' app.json
```

---

## Filtering & Selecting

```bash
# Filter array by value
jq '.items[] | select(.status == "active")' file.json

# Filter by key existence
jq '.items[] | select(has("email"))' file.json

# Filter with regex
jq '.items[] | select(.name | test("^prod-"))' file.json

# Select specific fields from filtered results
jq '.items[] | select(.type == "A") | .name' file.json

# Filter with multiple conditions
jq '.items[] | select(.status == "active" and .count > 2)' file.json

# Filter nulls out of an array
jq '.items[] | select(. != null)' file.json
```

---

## Slurp Mode (-s)

```bash
# Read all inputs into a single array before processing
jq -s '.' file1.json file2.json
# → [{ ... }, { ... }]

# Slurp stdin (e.g. from a pipeline)
cat *.json | jq -s '.'

# Merge all slurped inputs into one object
cat *.json | jq -s 'add'

# Slurp and sort combined array by a field
jq -s 'sort_by(.name)' file1.json file2.json

# Slurp and deduplicate
jq -s 'unique_by(.id)' file1.json file2.json

# Slurp and group by a field
jq -s 'group_by(.type)' file1.json file2.json

# Slurp lines of raw strings into a JSON array
echo -e "apple\nbanana\ncherry" | jq -Rs 'split("\n") | map(select(. != ""))'
# → ["apple", "banana", "cherry"]

# Process multiple files as a single stream without slurp
jq -n '[inputs]' file1.json file2.json   # equivalent to -s for arrays
```

---

## Working with Multiple Files

```bash
# Process all JSON files in a directory
jq '.name' *.json

# Merge two objects (right overrides left)
jq -s '.[0] * .[1]' base.json overrides.json

# Combine outputs from multiple files into one array
jq -s '.' file1.json file2.json

# Read a second file inside an expression
jq --slurpfile patch patch.json '. * $patch[0]' base.json

# Pass a file as a variable
jq --argjson cfg "$(cat config.json)" '$cfg.timeout' /dev/null
```

---

## Transformations

```bash
# Rename a key
jq '.newKey = .oldKey | del(.oldKey)' file.json

# Map over array - transform each element
jq '.items[] |= . + {enabled: true}' file.json

# Sort an array of strings
jq '.tags | sort' file.json

# Sort array of objects by a field
jq '.items | sort_by(.name)' file.json

# Sort descending
jq '.items | sort_by(.count) | reverse' file.json

# Unique values
jq '.tags | unique' file.json

# Count array length
jq '.items | length' file.json

# Collect into array with map
jq '[.items[] | .name]' file.json

# Flatten nested arrays
jq '.items | flatten' file.json

# Flatten one level deep
jq '.items | flatten(1)' file.json

# Reduce array to a single value
jq '.items | map(.count) | add' file.json

# Index an array into an object (key by field)
jq '.items | INDEX(.id)' file.json             # jq 1.7+
jq '[.items[] | {(.id): .}] | add' file.json  # older versions

# String interpolation
jq '.items[] | "\(.name) is \(.status)"' file.json
```

---

## String & Type Operations

```bash
# Convert number to string
jq '.count | tostring' file.json

# Convert string to number
jq '.version | tonumber' file.json

# Split a string
jq '"a,b,c" | split(",")' file.json

# Join an array of strings
jq '.tags | join(", ")' file.json

# Test a regex
jq '.name | test("^prod-")' file.json

# Extract regex capture groups
jq '.name | capture("(?<env>[a-z]+)-(?<id>[0-9]+)")' file.json

# ASCII lowercase / uppercase
jq '.name | ascii_downcase' file.json

# String length
jq '.name | length' file.json

# Check type
jq '.value | type' file.json
# → "number" | "string" | "boolean" | "array" | "object" | "null"
```

---

## Format Output

```bash
# Pretty-print (default)
jq '.' file.json

# Compact output (single line)
jq -c '.' file.json

# Raw string output (no quotes)
jq -r '.name' file.json

# Raw input (read plain text lines)
jq -R '.' file.txt

# Tab-indented output
jq --tab '.' file.json

# Null-delimited output (for xargs -0)
jq -rj '.name + "\u0000"' file.json

# Output as shell assignment
jq -r '"export NAME=\(.name)"' file.json
```

---

## Useful Flags

|Flag|Description|
|---|---|
|`-r`|Raw output - strings without quotes|
|`-c`|Compact output - single line|
|`-s`|Slurp - read all inputs into one array|
|`-R`|Raw input - read lines as strings|
|`-n`|Null input - don't read any input, use `input`/`inputs`|
|`-e`|Exit non-zero if output is `false` or `null`|
|`-f file`|Read filter expression from a file|
|`--arg k v`|Pass a shell string as `$k`|
|`--argjson k v`|Pass a JSON value as `$k`|
|`--slurpfile k f`|Slurp file into `$k` as array|
|`--rawfile k f`|Read file into `$k` as a string|
|`--jsonargs`|Treat remaining args as JSON positional args|
|`--args`|Treat remaining args as string positional args|
|`--tab`|Use tabs for indentation|
|`--indent N`|Set indentation (1–7 spaces)|
|`--stream`|Stream input as `[path, value]` pairs|
|`--join-output` / `-j`|No newline after each output|

---

## Operators Quick Reference

|Operator|Description|
|---|---|
|`.key`|Field access|
|`.key?`|Field access (suppress errors)|
|`.[0]`, `.[-1]`|Array index|
|`.[]`|Iterate array/object|
|`\|`|Pipe output|
|`,`|Produce multiple outputs|
|`+`|Add / concatenate / merge|
|`-`|Subtract / array difference|
|`//`|Alternative operator (default if null/false)|
|`select(cond)`|Filter by condition|
|`has("key")`|Check key existence|
|`in(obj)`|Check if value is a key in obj|
|`test("regex")`|Regex match (boolean)|
|`capture("regex")`|Named regex capture groups|
|`del(.key)`|Delete key|
|`length`|Length of string/array/object|
|`keys`|Sorted list of keys|
|`keys_unsorted`|Keys in original order|
|`values`|List of values|
|`to_entries`|`[{key, value}]` pairs|
|`from_entries`|Object from `[{key, value}]`|
|`with_entries(f)`|Map over key-value pairs|
|`map(f)`|Apply filter to each element|
|`map_values(f)`|Apply filter to each value|
|`any(f)`|True if any element matches|
|`all(f)`|True if all elements match|
|`recurse` / `..`|Recursive descent|
|`paths`|All paths in the document|
|`getpath(p)`|Get value at path array|
|`setpath(p; v)`|Set value at path array|
|`delpaths([p])`|Delete multiple paths|
|`env`|Object of all env variables|
|`$ENV`|Same as `env`|
|`now`|Current Unix timestamp|
|`input`|Read next input (with `-n`)|
|`inputs`|Read all remaining inputs (with `-n`)|
|`limit(n; f)`|First n outputs of f|
|`first(f)`|First output of f|
|`last(f)`|Last output of f|
|`until(cond; f)`|Loop until condition is true|
|`reduce`|Fold/accumulate|
|`label-break`|Early exit from a loop|
|`@base64`|Base64 encode|
|`@base64d`|Base64 decode|
|`@uri`|URL encode|
|`@csv`|Format as CSV row|
|`@tsv`|Format as TSV row|
|`@html`|HTML-escape|
|`@json`|Serialize to JSON string|
|`@sh`|Shell-quote a string|
|`@text`|Identity (same as `tostring`)|

---

## Environment Variables

```bash
# Read an env variable in expression
jq -n 'env.HOME'

# Or via $ENV
jq -n '$ENV.HOME'

# Pass shell variable into jq safely
jq --arg name "$NAME" '.items[] | select(.name == $name)' file.json

# Pass JSON value from shell
jq --argjson limit "$LIMIT" '.items | limit($limit; .[])' file.json
```

---

## Tips

```bash
# Validate JSON syntax
jq '.' file.json > /dev/null && echo "valid"

# Pretty-print and page
jq -C '.' file.json | less -R

# Generate JSON without input
jq -n '{name: "app", version: "1.0"}'

# Check exit code (false/null → exit 1)
jq -e '.enabled' config.json || echo "not enabled"

# Count matching elements
jq '[.items[] | select(.status == "active")] | length' file.json

# Process NDJSON (newline-delimited JSON) line by line
cat stream.ndjson | jq -c 'select(.level == "error")'

# Merge JSON from stdin with a local file
echo '{"extra": 1}' | jq -s '.[0] * .[1]' - base.json

# Use reduce to sum a field
jq '.items | reduce .[].count as $c (0; . + $c)' file.json

# Get all unique values for a key
jq '[.items[].status] | unique' file.json

# Debug mid-pipeline
jq '.items[] | debug | .name' file.json
```



## kubernetes

`kubectl get node -o json` wraps everything in a list object with an `items` array.

```bash
k get nodes -o json | jq -r '.items[] | .metadata.name + " " + (.status.addresses[] | select(.type=="InternalIP") | .address)'
k get nodes -o json | jq -r '.items[] | (.status.addresses[] | select(.type=="InternalIP") | .address) + " " + (.status.addresses[] | select(.type=="Hostname") | .address)'

k get nodes -o json | jq -r '.items[] | [
  (.status.addresses[] | select(.type=="InternalIP") | .address),
  (.status.addresses[] | select(.type=="Hostname") | .address)
] | @tsv' | column -t


{ echo "IP HOSTNAME"; k get nodes -o json | jq -r '.items[] | [
  (.status.addresses[] | select(.type=="InternalIP") | .address),
  (.status.addresses[] | select(.type=="Hostname") | .address)
] | @tsv'; } | column -t
```

# yq guide


```bash
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq
```

> **yq** (mikefarah/yq) - a portable command-line YAML processor  
> Syntax: `yq [expression] [file...]`
> sponge is needed for writing `sudo dnf install moreutils`

---

## Reading Values

```bash
# Read a top-level key
yq '.name' file.yaml

# Read a nested key
yq '.spec.replicas' deployment.yaml

# Read an array element (0-indexed)
yq '.items[0]' file.yaml

# Read last element
yq '.items[-1]' file.yaml

# Read multiple keys at once
yq '.name, .version' file.yaml

# Read all array elements
yq '.items[]' file.yaml
```

---

## Writing / Updating Values

```bash
# Update a key in-place
yq -i '.spec.replicas = 3' deployment.yaml

# Set a new key
yq -i '.metadata.label = "prod"' file.yaml

# Update a nested key
yq -i '.config.timeout = 30' file.yaml

# Append to an array
yq -i '.items += ["newitem"]' file.yaml

# Delete a key
yq -i 'del(.metadata.annotations)' file.yaml
```

---

## Nested Structures

Given this example YAML:

```yaml
# app.yaml
app:
  name: myservice
  version: "2.1.0"
  config:
    database:
      host: db.internal
      port: 5432
      credentials:
        user: admin
        password: secret
    cache:
      host: redis.internal
      ttl: 300
  replicas:
    - region: us-east
      count: 3
      settings:
        autoscale: true
        maxCount: 10
    - region: eu-west
      count: 2
      settings:
        autoscale: false
        maxCount: 5
```

```bash
# Read a deeply nested scalar
yq '.app.config.database.host' app.yaml
# → db.internal

# Read a value 3+ levels deep
yq '.app.config.database.credentials.user' app.yaml
# → admin

# Update a deeply nested value in-place
yq -i '.app.config.database.port = 5433' app.yaml

# Add a new key deep in the tree (creates intermediate nodes)
yq -i '.app.config.database.pool.maxSize = 20' app.yaml

# Delete a nested key
yq -i 'del(.app.config.cache.ttl)' app.yaml

# Read a nested key from a specific array element
yq '.app.replicas[0].settings.autoscale' app.yaml
# → true

# Read a nested field from every array element
yq '.app.replicas[].region' app.yaml
# → us-east
# → eu-west

# Filter array elements by a nested field value
yq '.app.replicas[] | select(.settings.autoscale == true)' app.yaml

# Update a nested field across ALL array elements
yq -i '.app.replicas[].settings.maxCount = 15' app.yaml

# Update a nested field only in matching array elements
yq -i '(.app.replicas[] | select(.region == "eu-west") | .count) = 4' app.yaml

# Extract just nested sub-objects from each array element
yq '.app.replicas[] | .settings' app.yaml

# Collect a nested field from all array elements into a new array
yq '[.app.replicas[].region]' app.yaml
# → ["us-east", "eu-west"]

# Read multiple nested paths at once
yq '.app.config.database.host, .app.config.cache.host' app.yaml

# Check if a deeply nested key exists
yq '.app.config.database | has("credentials")' app.yaml
# → true

# Rebuild a new object from nested fields (projection)
yq '.app.replicas[] | {"region": .region, "max": .settings.maxCount}' app.yaml

# Swap a nested value using another nested value
yq -i '.app.config.cache.ttl = .app.config.database.port' app.yaml

# Recursively search all keys named "host" anywhere in the tree
yq '.. | select(key == "host")' app.yaml
# → db.internal
# → redis.internal

# Flatten nested map to JSON for inspection
yq -o=json '.app.config' app.yaml
```

---

## Filtering & Selecting

```bash
# Filter array by value
yq '.items[] | select(.status == "active")' file.yaml

# Filter by key existence
yq '.items[] | select(has("email"))' file.yaml

# Filter with regex
yq '.items[] | select(.name | test("^prod-"))' file.yaml

# Select specific fields from filtered results
yq '.items[] | select(.type == "A") | .name' file.yaml
```

---

## Working with Multiple Files

```bash
# Merge two YAML files (second overrides first)
yq '. * load("overrides.yaml")' base.yaml

# Concatenate documents
yq '.' file1.yaml file2.yaml

# Process all yamls in a directory
yq '.name' *.yaml
```

---

## Transformations

```bash
# Rename a key
yq '.newKey = .oldKey | del(.oldKey)' file.yaml

# Map over array - transform each element
yq '.items[].enabled = true' file.yaml

# Sort an array of strings
yq '.tags | sort' file.yaml

# Sort array of objects by a field
yq '.items | sort_by(.name)' file.yaml

# Unique values
yq '.tags | unique' file.yaml

# Count array length
yq '.items | length' file.yaml

# Collect into array with map
yq '[.items[] | .name]' file.yaml
```

---

## Format Conversion

```bash
# YAML → JSON
yq -o=json '.' file.yaml

# JSON → YAML
yq -p=json '.' file.json

# YAML → TOML (v4.30+)
yq -o=toml '.' file.yaml

# Pretty-print with indentation
yq --indent 4 '.' file.yaml

# Output as CSV (flat arrays)
yq -o=csv '.rows[]' file.yaml
```

---

## Multi-Document YAML

```bash
# Read all documents in a multi-doc file
yq '.' multi.yaml

# Select a specific document (0-indexed)
yq 'select(di == 1)' multi.yaml

# Update only the second document
yq '(select(di == 1) | .spec.replicas) = 5' multi.yaml
```

---

## Merging & Anchors

```bash
# Deep merge (right overrides left)
yq '. *d load("patch.yaml")' base.yaml

# Merge keeping existing values (append only)
yq '. *n load("patch.yaml")' base.yaml

# Explode anchors/aliases into plain YAML
yq 'explode(.)' file.yaml
```

---

## Useful Flags

|Flag|Description|
|---|---|
|`-i`|Edit file in-place|
|`-o=json`|Output as JSON|
|`-o=toml`|Output as TOML|
|`-p=json`|Parse input as JSON|
|`-p=toml`|Parse input as TOML|
|`--indent N`|Set indentation (default: 2)|
|`-e`|Exit with non-zero if expression returns null/false|
|`-r` / `--unwrapScalar`|Output raw string (no quotes)|
|`-C`|Force colored output|
|`--no-doc`|Don't print document separators (`---`)|
|`-n`|Evaluate expression without any input file|

---

## Operators Quick Reference

|Operator|Description|
|---|---|
|`.key`|Field access|
|`.key?`|Field access (suppress errors)|
|`.[0]`, `.[-1]`|Array index|
|`.[]`|Iterate array/object|
|`\|`|Pipe output|
|`select(cond)`|Filter by condition|
|`has("key")`|Check key existence|
|`test("regex")`|Regex match|
|`. * b`|Merge (shallow)|
|`. *d b`|Deep merge|
|`del(.key)`|Delete key|
|`length`|Length of string/array/object|
|`keys`|List keys of object|
|`values`|List values of object|
|`sort_by(.field)`|Sort array by field|
|`unique_by(.field)`|Deduplicate by field|
|`group_by(.field)`|Group array elements|
|`env(VAR)`|Read environment variable|
|`strenv(VAR)`|Read env var as string|
|`..`|Recursive descent (all nodes)|

---

## Environment Variables in Expressions

```bash
# Use env var in expression
NAME=myapp yq '.name == env(NAME)' file.yaml

# Inject env var as a value
IMAGE=nginx:latest yq -i '.spec.image = strenv(IMAGE)' file.yaml
```

---

## Tips

```bash
# Validate YAML syntax
yq '.' file.yaml > /dev/null && echo "valid"

# Evaluate without a file (generate YAML)
yq -n '.name = "app" | .version = "1.0"'

# Colorized output (useful in scripts)
yq -C '.' file.yaml | less -R

# Check if a key exists and exit non-zero if not
yq -e '.spec.replicas' deployment.yaml
```

`yq` doesn't have a direct `-s` / `--slurp` flag like `jq`, but it achieves the same thing differently.

**In jq**, `-s` reads all inputs into a single array before processing.

**In yq**, you use `load()` or just pass multiple files - and if you want to collect everything into an array, you wrap with `[...]`:

```bash
# Slurp all docs from a file into an array
yq '[.]' file.yaml

# Slurp multiple files into an array
yq -n '[load("a.yaml"), load("b.yaml")]'

# Slurp all elements from a multi-doc YAML into one array
yq -n '[load_all("multi.yaml")]'
```

For the stdin slurp case (`cat *.yaml | jq -s .`), the yq equivalent is:

```bash
cat *.yaml | yq '[.]'
```

Though honestly for multiple files piped together, passing them as arguments is cleaner:

```bash
yq '.' file1.yaml file2.yaml   # streams them
yq '[.]' file1.yaml file2.yaml  # wraps each in array - not quite the same as jq -s
```

The subtle difference: `yq` is natively multi-document aware, so it often doesn't _need_ slurp mode - you can iterate across all docs with `select(di == N)` or just `.[]` without collecting first.


# 🦇 bat guide 

> `bat` - a `cat` clone with syntax highlighting, line numbers, and Git integration.

---

## Installation

Not part of base RHEL/Rocky — install from EPEL (see `installations.md` for the EPEL setup itself):

```bash
sudo dnf install epel-release -y
sudo dnf install bat
```

---

## Basic Usage

```bash
bat file.yaml                  # display a file with syntax highlighting
bat file1.yaml file2.yaml      # display multiple files
bat *.yaml                     # display all yaml files
bat -n file.yaml               # show line numbers only (no other decorations)
bat -A file.yaml               # show non-printable characters (tabs, spaces, etc.)
```

---

## Paging

```bash
bat file.yaml                  # auto-paging when content exceeds terminal height
bat -p file.yaml               # disable pager (plain output, like cat)
bat --pager "less -R" file.yaml  # use a custom pager
BAT_PAGER="less -RF" bat file.yaml  # set pager via env var
```

---

## Syntax & Language

```bash
bat -l yaml file               # force YAML highlighting (no .yaml extension)
bat -l json output.log         # treat a .log file as JSON
bat --list-languages           # list all supported languages
```

---

## Themes

```bash
bat --list-themes              # list all available themes
bat --theme=TwoDark file.yaml  # use a specific theme
bat --theme=ansi file.yaml     # minimal ANSI-safe theme (good for CI)
bat --theme=GitHub file.yaml   # light GitHub theme
```

---

## Style Control

```bash
bat --style=full file.yaml      # everything: line numbers, git, header (default)
bat --style=plain file.yaml     # color only, no decorations
bat --style=numbers file.yaml   # line numbers only
bat --style=header file.yaml    # filename header only
bat --style=grid file.yaml      # add grid lines
bat --style=numbers,grid file.yaml  # combine styles
```

---

## Git Integration

```bash
bat file.yaml                  # shows +/~/- markers in gutter for git changes
bat --diff file.yaml           # only show changed lines (like diff)
```

---

## Piping & Integration

```bash
# Colorize grep output
grep -n "node" config.yaml | bat -l yaml

# Use as a man pager
export MANPAGER="sh -c 'col -bx | bat -l man -p'"

# Preview files in fzf
fzf --preview 'bat --color=always {}'

# Pipe any command output with a language hint
kubectl get pod -o yaml | bat -l yaml
docker inspect mycontainer | bat -l json
cat /etc/hosts | bat -l ini
```

---

## Aliases & Shell Functions

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# Ubuntu: batcat → bat
alias bat='batcat'

# Shorthand plain cat (no decorations, no pager)
alias batp='bat --style=plain --paging=never'

# Quick YAML viewer
alias yamlcat='bat -l yaml --style=numbers'

# Quick JSON viewer
alias jsoncat='bat -l json --style=numbers'

# Man pages with bat
alias man='batman'  # if batman wrapper is installed, else use the MANPAGER export below

# Pretty-print any piped input with auto language detection
alias prettify='bat --style=plain --paging=never'
```

```bash
# Shell function: preview a file with a forced language
batl() {
  bat --language="${1}" "${2}"
}
# Usage: batl json output.log

# Shell function: search inside a file and show context with highlighting
batgrep() {
  grep -n "${1}" "${2}" | bat --language="${3:-text}" --style=numbers
}
# Usage: batgrep "error" app.log yaml
```

---

## Environment Variables

```bash
export BAT_THEME="TwoDark"          # set default theme
export BAT_STYLE="numbers,grid"     # set default style
export BAT_PAGER="less -RF"         # set default pager
export MANPAGER="sh -c 'col -bx | bat -l man -p'"  # bat as man pager
```

---

## Quick Reference Card

|Task|Command|
|---|---|
|View file|`bat file.yaml`|
|No decorations|`bat -p file.yaml`|
|Force language|`bat -l json file.log`|
|List themes|`bat --list-themes`|
|Set theme|`bat --theme=TwoDark file`|
|Show git diff|`bat --diff file`|
|Show non-printable|`bat -A file`|
|Pipe to fzf|`fzf --preview 'bat --color=always {}'`|
|kubectl yaml|`kubectl get pod -o yaml \| bat -l yaml`|

---

> 💡 **Tip:** Set `BAT_THEME` and `BAT_STYLE` in your shell profile so every `bat` call uses your preferred defaults without extra flags.