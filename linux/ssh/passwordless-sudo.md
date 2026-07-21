# Passwordless Sudo

Once SSH login itself is passwordless (see [`ssh-key-distribution.md`](ssh-key-distribution.md)),
a script that runs `sudo` on each node will still stop and ask for a password —
login and sudo are two separate authentication checks. `sudo` reads its rules from
`/etc/sudoers`, plus every file dropped in `/etc/sudoers.d/` (via an `includedir`
directive). Files there are evaluated in the same combined rule set, in the order
they're read — later matching rules can override earlier ones. `NOPASSWD` on a
rule tells sudo not to prompt at all for the commands that rule covers.

```bash
USER_ID="user-id"
source nodes.env
NODES=("${NODES1[@]}")

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

## When passwordless sudo doesn't work

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

# Example output shape (generic — replace with your own):
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

## See Also

- [`ssh-key-distribution.md`](ssh-key-distribution.md) — passwordless *login*, the prerequisite for this
- [`nodes.env`](nodes.env) — the node-list formats referenced above
