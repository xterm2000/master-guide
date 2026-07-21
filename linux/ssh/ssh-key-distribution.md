# SSH Key Generation & Distribution

Public-key auth replaces the password prompt with a key pair: a private key that
never leaves your machine, and a public key copied onto every remote node's
`~/.ssh/authorized_keys`. The remote sshd challenges the client to prove it holds
the private key matching one of the authorized public keys — if it can, you're in,
no password asked. `ssh-copy-id` automates the "copy the public key onto each
node" step below; it still needs one password (or existing key) per node for that
initial copy.

```bash
USER_ID="user-id"

# 0. Get node IPs from a live Kubernetes cluster, if that's your source of truth
k get nodes -o json | jq -r '.items[] | .metadata.name + " " + (.status.addresses[] | select(.type=="InternalIP") | .address)'

# 1. Generate an SSH key (skip if you already have one)
ssh-keygen -t ed25519 -C "$USER_ID" -f ~/.ssh/id_ed25519 -N ""

# 2. Load the node list (see nodes.env — this uses the NODES1 indexed-array shape)
source nodes.env
NODES=("${NODES1[@]}")

# 3. Distribute the key to all nodes
for node in "${NODES[@]}"; do
  echo "=== $node ==="
  ssh-copy-id -i ~/.ssh/id_ed25519.pub \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=no \
    $USER_ID@$node
done

# 4. Verify passwordless login works
for node in "${NODES[@]}"; do
  echo -n "$node: "
  ssh -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=no \
      -o BatchMode=yes \
      $USER_ID@$node "echo OK" 2>&1
done
```

## See Also

- [`passwordless-sudo.md`](passwordless-sudo.md) — once login is passwordless, removing the *sudo* password prompt too
- [`nodes.env`](nodes.env) — the node-list formats referenced above
- [`ssh-config.md`](ssh-config.md) — persisting `StrictHostKeyChecking`/`ConnectTimeout` etc. in `~/.ssh/config` instead of repeating them on every command
- [`windows-key-permissions.md`](windows-key-permissions.md) — locking down the private key file on a Windows client
