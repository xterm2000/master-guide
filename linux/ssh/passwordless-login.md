
```bash

USER_ID="user-id"

# 0. get the nodes ips

k get nodes -o json | jq -r '.items[] | .metadata.name + " " + (.status.addresses[] | select(.type=="InternalIP") | .address)'


# 1. Generate SSH key (skip if you already have one)
ssh-keygen -t ed25519 -C "$USER_ID" -f ~/.ssh/id_ed25519 -N ""

# 2. Define the nodes array
NODES=(
  100.99.199.231
  100.99.199.232
  100.99.199.233
  100.99.199.225
  100.99.199.226
  100.99.199.227
  100.99.199.228
  100.99.199.229
  100.99.199.230
  100.99.228.12
  100.99.228.13
  100.99.228.14
)

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

# Run on each node after SSH access is set up
for node in "${NODES[@]}"; do
  echo "=== $node ==="
  ssh -t \
      -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=no \
      $USER_ID@$node \
      "echo '$USER_ID ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/$USER_ID && sudo chmod 440 /etc/sudoers.d/$USER_ID && sudo cat /etc/sudoers.d/$USER_ID"
done


for node in "${NODES[@]}"; do
  echo -n "$node: "
  ssh $node "sudo whoami" 2>&1
done
```

## when passwordless doesn't work
```bash
# ============================================================
# CHECK 1 - file exists and permissions (must be 440)
# ============================================================
sudo ls -la /etc/sudoers.d/$USER_ID
sudo stat -c "%a %n" /etc/sudoers.d/$USER_ID

# ============================================================
# CHECK 2 - sudoers.d is included in main sudoers
# ============================================================
grep -i includedir /etc/sudoers

# ============================================================
# CHECK 3 - file syntax is valid
# ============================================================
sudo visudo -c -f /etc/sudoers.d/$USER_ID

# ============================================================
# CHECK 4 - no hidden characters in file
# ============================================================
sudo cat -A /etc/sudoers.d/$USER_ID
# Good:  $USER_ID ALL=(ALL) NOPASSWD: ALL$
# Bad:   $USER_ID ALL=(ALL) NOPASSWD: ALL^M$  (Windows line endings)

# ============================================================
# CHECK 5 - what rules are actually applied to your user
# ============================================================
sudo -l
# Look for conflicting PASSWD: ALL rules overriding NOPASSWD

# ============================================================
# CHECK 6 - check all sudoers files for conflicts
# ============================================================
sudo grep -r "$USER_ID\|PASSWD" /etc/sudoers /etc/sudoers.d/

# Example output shape (redacted/generic — replace with your own):
# /etc/sudoers:# %wheel   ALL=(ALL)       NOPASSWD: ALL
# /etc/sudoers.d/some-team:%some-admin-group ALL=(ALL) PASSWD:ALL
# /etc/sudoers.d/$USER_ID:$USER_ID ALL=(ALL) NOPASSWD: ALL
#
# What to look for: any OTHER rule (group or user) that also matches you and
# says "PASSWD:ALL" instead of "NOPASSWD:ALL" — sudo evaluates rules in order
# and a later, more specific PASSWD rule can override an earlier NOPASSWD one.


# ============================================================
# CHECK 7 - check group membership (groups may inherit PASSWD rules)
# ============================================================
id $USER_ID

# ============================================================
# CHECK 8 - verify passwordless sudo works across all nodes
# ============================================================
for node in "${NODES[@]}"; do
  echo -n "$node: "
  ssh $node "sudo whoami" 2>&1
done
```





