## Looping Over hosts.txt in Bash


```
100.99.229.66   eclapls00111lb
100.99.229.67   eclapls00111lc
100.99.229.68   eclapls00111ld
100.99.229.69   eclapls00111le
100.99.229.70   eclapls00111lf
100.99.229.71   eclapls00111lg
100.99.229.72   eclapls00111lh
100.99.229.73   eclapls00111li
100.99.229.74   eclapls00111lj
100.99.229.75   eclapls00112la
100.99.229.76   eclapls00112lb
100.99.229.77   eclapls00113la
```

### generate nodes.env - array
```bash
#!/bin/bash
{
    echo "declare -A NODES=("
    while read -r ip hostname; do
        echo "    [$hostname]=$ip"
    done < hosts.txt
    echo ")"
} > nodes.env

```

```bash
#!/bin/bash
OUTPUT=nodes_3.env    # define once, use everywhere

echo "declare -A NODES=(" > "$OUTPUT"
while read -r ip hostname; do
    echo "    [$hostname]=$ip"
done < hosts.txt >> "$OUTPUT"
echo ")" >> "$OUTPUT"

```

### Basic loop - read both fields

```bash
while read -r ip hostname; do
    echo "$hostname -> $ip"
done < hosts.txt
```

---

### Common patterns for your use case

**SSH into each host:**

```bash
while read -r ip hostname; do
    ssh -n AOSKubeAdmin@$ip "hostname && uptime"
done < hosts.txt
```

**Copy a file to all hosts:**

```bash
while read -r ip hostname; do
    scp /path/to/file AOSKubeAdmin@$ip:/destination/
done < hosts.txt
```

**Run a command and prefix output with hostname:**

```bash
while read -r ip hostname; do
    echo "=== $hostname ==="
    ssh -n AOSKubeAdmin@$ip "df -h"
done < hosts.txt
```

---

### Parallel execution - for speed

Sequential loops are slow across 12 hosts. Backgrounding with `&` + `wait`:

```bash
while read -r ip hostname; do    
    ssh -n AOSKubeAdmin@$ip "hostname && uptime" &
done < hosts.txt
wait    # blocks until all background jobs finish
```

Or with `xargs` for controlled parallelism (4 at a time):

```bash
awk '{print $1}' hosts.txt | xargs -P4 -I{} ssh AOSKubeAdmin@{} "uptime"
```

---

### Extract just IPs or just hostnames

```bash
# IPs only
awk '{print $1}' hosts.txt

# Hostnames only
awk '{print $2}' hosts.txt

# Use in a loop
for host in $(awk '{print $2}' hosts.txt); do
    echo "doing something with $host"
done
```

---

### Skip blank lines / comments safely

If your file might have comments or blank lines:

```bash
while read -r ip hostname; do
    [[ -z "$ip" || "$ip" == \#* ]] && continue
    ssh -n AOSKubeAdmin@$ip "uptime"
done < hosts.txt
```

---

### Quick one-liners

```bash
# Check SSH connectivity to all hosts
while read -r ip _; do ssh -n -o ConnectTimeout=3 AOSKubeAdmin@$ip exit && echo "$ip OK" || echo "$ip FAIL"; done < hosts.txt

# Collect /etc/os-release from all
while read -r ip hostname; do echo "$hostname: $(ssh -n AOSKubeAdmin@$ip 'grep PRETTY /etc/os-release')"; done < hosts.txt
```

The `_` in `read -r ip _` is a common convention when you want the first field and want to explicitly discard the rest.