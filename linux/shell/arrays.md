# Bash Arrays

## Indexed Arrays

```bash
declare -a fruits=("apple" "banana" "cherry")
echo "${fruits[0]}"     # apple
echo "${fruits[1]}"     # banana

fruits+=("date")        # append an element
echo "${fruits[@]}"     # apple banana cherry date  — all values
echo "${!fruits[@]}"    # 0 1 2 3                    — all indices
echo "${#fruits[@]}"    # 4                          — element count
```

Always quote `"${fruits[@]}"` when expanding — unquoted `${fruits[@]}` re-triggers word-splitting and globbing on each element, the same class of bug covered for loops in `bash-loops-cookbook.md`.

---

## Associative Arrays

```bash
declare -A NODES=(
  [control-plane]="10.0.4.229"
  [worker-1]="10.0.15.20"
  [worker-2]="10.0.5.214"
  [worker-3]="10.0.4.240"
)

echo "${NODES[@]}"      # values only
echo "${!NODES[@]}"     # keys only
echo "${#NODES[@]}"     # count

for node in "${!NODES[@]}"; do
    echo "$node is ${NODES[$node]}"
done
```

`declare -A` is mandatory *before* the first assignment — unlike an indexed array, bash has no way to infer "this should be associative" from the literal `(...)` syntax alone; without `-A` first, string keys like `[control-plane]` are silently misinterpreted.

---

## Joining an array with a custom separator (`IFS`)

```bash
arr=(a b c)
( IFS=,; echo "${arr[*]}" )   # a,b,c
```

`${arr[*]}` joins all elements into a single string using the first character of `$IFS` as the separator (`${arr[@]}` never does this — `[@]` always keeps elements distinct). Scoping the `IFS=,` assignment inside a subshell `( ... )` means it never leaks into the rest of the script — no manual reset needed afterward. This is the same scoping principle as `linux/shell/bash-loops-cookbook.md`'s `IFS` section: prefer scoping the change (subshell, or a per-command prefix like `IFS=',' read ...`) over a global `IFS=...` followed by a manual reset.

---

## Populating an Array from stdin

### Whole file or stream at once — `mapfile`/`readarray`

```bash
mapfile -t hosts < hosts.txt
echo "${#hosts[@]} hosts loaded"
echo "${hosts[0]}"
```

`-t` strips the trailing newline from each line as it's loaded — without it, every element keeps a literal `\n` at the end. This is the fastest way to get a file into an array when you don't need to transform or filter lines on the way in.

### From a command's output, not a file

```bash
mapfile -t nodes < <(kubectl get nodes -o name)
```

`< <(...)` (process substitution) feeds `mapfile` the command's output as if it were a file, without a temp file and without the pipe-subshell problem — see `linux/shell/process-substitution.md` for why `command | mapfile -t nodes` would silently fail to populate `nodes` in the calling shell (the pipeline's last stage runs in a subshell, so the array would only exist inside it).

### Line-by-line, when each line needs processing before it's added

```bash
hosts=()
while IFS= read -r line; do
    [[ "$line" =~ ^# ]] && continue   # skip comment lines, for example
    hosts+=("$line")
done < hosts.txt
```

Reach for this over `mapfile` whenever a line needs a decision (skip/transform) before it goes into the array — `mapfile` only loads verbatim, one element per line, with no hook to filter as it goes.

### Splitting one line into an array by a delimiter

```bash
IFS=',' read -ra fields <<< "line,with,commas"
echo "${fields[1]}"   # with
```

`IFS=','` prefixed directly on the `read` call scopes the custom separator to this one invocation only — nothing to reset afterward (same principle as the join example above).

---

## Use Cases

### 1. Run a command against every host in a list

```bash
mapfile -t hosts < hosts.txt
for host in "${hosts[@]}"; do
    ssh "$host" uptime </dev/null
done
```

The `</dev/null` on the `ssh` call matters the moment this loop reads from stdin itself (e.g., `while read` instead of `mapfile`) — otherwise `ssh` can swallow the rest of the input. See the `bash-loops-cookbook.md` recipe on giving a loop body its own stdin for the full explanation.

### 2. Count resources per namespace, driven by an array of names

```bash
mapfile -t namespaces < <(kubectl get ns -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n')

for ns in "${namespaces[@]}"; do
    echo "$ns: $(kubectl get pods -n "$ns" --no-headers | wc -l) pods"
done
```

The `jsonpath` output is space-separated on one line; `tr ' ' '\n'` reshapes it to one-per-line before `mapfile` loads it — the same "flatten structured output to plain text, then treat it like any other text stream" bridge covered in `text-process-cookbook.md`.

### 3. Tally values into an associative array while scanning a log

```bash
declare -A status_count
while IFS= read -r code; do
    ((status_count[$code]++))
done < <(awk '{print $9}' access.log)

for code in "${!status_count[@]}"; do
    echo "$code: ${status_count[$code]}"
done
```

This is the array-based version of the `sort | uniq -c` counting idiom used throughout `text-process-cookbook.md` — useful specifically when you need the counts available as *live variables* in the current shell (to branch on a threshold, for example) rather than just printed as a report.

---

## See Also

- `bash-loops-cookbook.md` — `IFS` scoping rules, safe stdin handling, and the `while IFS= read -r` idiom used throughout this file
- `process-substitution.md` — `< <(...)` and why it's required for `mapfile`/`while read` to see a command's output without losing the loop's variables
- `text-process-cookbook.md` — the counting/aggregation pipelines these array recipes mirror in plain-text form
