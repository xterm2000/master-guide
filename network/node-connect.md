```bash
cat > ./nodes.env << 'EOF'
declare -A NODES
NODES=(
  [control-1]="100.99.229.66"
  [control-2]="100.99.229.67"
  [control-3]="100.99.229.68"
  [worker-1]="100.99.229.69"
  [worker-2]="100.99.229.70"
  [worker-3]="100.99.229.71"
  [worker-4]="100.99.229.72"
  [worker-5]="100.99.229.73"
  [worker-6]="100.99.229.74"
  [worker-7]="100.99.229.75"
  [worker-8]="100.99.229.76"
  [monitor]="100.99.229.77"
)
EOF

```
---
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODES_ENV="${SCRIPT_DIR}/nodes.env"

usage() {
  echo "Usage: $(basename "$0") <c|w|m> [number]"
  echo ""
  echo "  c <n>   SSH into control-<n>"
  echo "  w <n>   SSH into worker-<n>"
  echo "  m       SSH into monitor"
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") c 1    # SSH to control-1"
  echo "  $(basename "$0") w 3    # SSH to worker-3"
  echo "  $(basename "$0") m      # SSH to monitor"
  exit 1
}

[[ $# -lt 1 ]] && usage

TYPE="$1"
NUMBER="${2:-}"

# Source the nodes file to load the NODES associative array
if [[ ! -f "$NODES_ENV" ]]; then
  echo "Error: nodes.env not found at $NODES_ENV" >&2
  exit 1
fi
source "$NODES_ENV"

case "$TYPE" in
  c|control)
    [[ -z "$NUMBER" ]] && { echo "Error: control requires a node number"; usage; }
    NODE_KEY="control-${NUMBER}"
    ;;
  w|worker)
    [[ -z "$NUMBER" ]] && { echo "Error: worker requires a node number"; usage; }
    NODE_KEY="worker-${NUMBER}"
    ;;
  m|monitor)
    NODE_KEY="monitor"
    ;;
  *)
    echo "Error: unknown type '$TYPE'" >&2
    usage
    ;;
esac

IP="${NODES[$NODE_KEY]:-}"
if [[ -z "$IP" ]]; then
  echo "Error: node '$NODE_KEY' not found in nodes.env" >&2
  echo ""
  echo "Available nodes:"
  for key in $(echo "${!NODES[@]}" | tr ' ' '\n' | sort); do
    printf "  %-12s %s\n" "$key" "${NODES[$key]}"
  done
  exit 1
fi

echo "Connecting to $NODE_KEY ($IP)..."
exec ssh "$IP"
```