# Kubernetes Cluster Setup Guide

## Bastion → Kubespray Deployment on Rocky Linux

Provisions a bare-metal-style Kubernetes cluster from a bastion host using Kubespray running inside Podman.  
Topology: 1 bastion · 1 control plane · 3 workers.

> **AWS note:** This guide targets bare-metal simulation. Where AWS-specific steps are needed (e.g. disabling source/dest check), they are called out inline with an `[AWS]` marker and also collected in
>  [Appendix B] [Appendix B - AWS-Specific Steps](#Appendix%20B%20-%20AWS-Specific%20Steps). All core steps work unchanged on real hardware or any VMs.

---

## Topology

| Role          | Hostname   | Private IP    | 
| ------------- | ---------- | ------------- |
| Bastion       | `bastion`  | `10.0.12.33`  |
| Control Plane | `control`  | `10.0.10.147` |
| Worker 1      | `worker-1` | `10.0.8.232`  |
| Worker 2      | `worker-2` | `10.0.13.59`  |
| Worker 3      | `worker-3` | `10.0.13.244` |

> IPs are examples - your actual IPs go into `nodes.env` (Step 0).

---

## Phase 1 - Cluster Preparation

### Step 0 - Define Node Map

Store all node IPs in a reusable env file. Every script in this guide sources it.

```bash
cat > ~/nodes.env << 'EOF'
declare -A NODES
NODES=(
  [control]="10.0.10.147"
  [worker-1]="10.0.8.232"
  [worker-2]="10.0.13.59"
  [worker-3]="10.0.13.244"
)
EOF
```

Source it now and persist it in `~/.bashrc`:

```bash
source ~/nodes.env
echo 'source ~/nodes.env' >> ~/.bashrc
```

> **Note:** Bash associative arrays cannot be exported to subprocesses. Any script that uses `$NODES` must `source ~/nodes.env` at the top.

Quick sanity check:

```bash
echo "${NODES[control]}"
for role in "${!NODES[@]}"; do echo "$role -> ${NODES[$role]}"; done
```

---

### Step 1 - Verify Node Connectivity

Confirm SSH access from the bastion to all nodes using the bootstrap key before doing anything else.

```bash
source ~/nodes.env

for role in "${!NODES[@]}"; do
  HOST="${NODES[$role]}"
  echo -n "Testing $role ($HOST) .. "
  ssh -i ~/top-key.pem \
      -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=no \
      rocky@$HOST "echo OK" 2>/dev/null || echo "FAILED"
done
```

---

### Step 2 - Create the `kbadm` Admin User on the Bastion

```bash
sudo useradd -m -s /bin/bash kbadm

sudo bash -c 'echo "kbadm ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/kbadm'
sudo chmod 440 /etc/sudoers.d/kbadm

# Validate sudoers syntax
sudo visudo -c -f /etc/sudoers.d/kbadm && echo "Syntax OK"

# Copy nodes env to kbadm's home
sudo cp ~/nodes.env /home/kbadm/
```

---

### Step 3 - Generate SSH Key for `kbadm`

```bash
sudo mkdir -p /home/kbadm/.ssh
sudo ssh-keygen -t ed25519 -C "kbadm@bastion" -f /home/kbadm/.ssh/id_kbadm -N ""
sudo chown -R kbadm:kbadm /home/kbadm/.ssh

# Add the public key to kbadm's own authorized_keys
sudo -u kbadm bash -c '
  cat /home/kbadm/.ssh/id_kbadm.pub >> /home/kbadm/.ssh/authorized_keys
  chmod 600 /home/kbadm/.ssh/authorized_keys
'
```

---

### Step 4 - Provision `kbadm` on All Nodes

Creates the `kbadm` user, configures passwordless sudo, and installs the SSH public key on each node - all tunnelled through the existing `rocky` bootstrap account.

```bash
source /home/kbadm/nodes.env
PUBKEY=$(sudo cat /home/kbadm/.ssh/id_kbadm.pub)
ADMIN_USER="rocky"

for role in "${!NODES[@]}"; do
  NODE="${NODES[$role]}"
  echo "============================================"
  echo "Setting up kbadm on $role ($NODE) ..."
  echo "============================================"

  ssh -i ~/top-key.pem \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=10 \
      "$ADMIN_USER@$NODE" \
      "PUBKEY='$PUBKEY' bash -s" << 'REMOTE_SCRIPT'

    set -e

    # Create user
    if id kbadm &>/dev/null; then
      echo "[INFO] User kbadm already exists - skipping creation."
    else
      sudo useradd -m -s /bin/bash kbadm
      echo "[OK] User kbadm created."
    fi

    # Passwordless sudo
    echo "kbadm ALL=(ALL) NOPASSWD:ALL" | \
      sudo tee /etc/sudoers.d/kbadm > /dev/null
    sudo chmod 440 /etc/sudoers.d/kbadm
    sudo visudo -c -f /etc/sudoers.d/kbadm > /dev/null
    echo "[OK] Passwordless sudo configured."

    # SSH directory
    sudo mkdir -p /home/kbadm/.ssh
    sudo chmod 700 /home/kbadm/.ssh

    # Install public key
    echo "$PUBKEY" | sudo tee /home/kbadm/.ssh/authorized_keys > /dev/null
    sudo chmod 600 /home/kbadm/.ssh/authorized_keys
    sudo chown -R kbadm:kbadm /home/kbadm/.ssh
    echo "[OK] SSH public key installed."

    id kbadm
    echo "[DONE] kbadm setup complete on $(hostname)."

REMOTE_SCRIPT

  echo ""
done
```

### Key Layout Quick Reference

```
BASTION (10.0.0.100)
├-- top-key.pem              ← original admin key
└-- /home/kbadm/
    └-- .ssh/
        ├-- id_kbadm         ← KubeAdmin private key (never leave bastion)
        ├-- id_kbadm.pub     ← distributed to all nodes
        ├-- authorized_keys  ← allows kbadm → kbadm on bastion
        └-- config           ← named host aliases

ALL NODES (including bastion)
├-- User: kbadm
│   ├-- Home: /home/kbadm
│   ├-- Shell: /bin/bash
│   └-- .ssh/authorized_keys ← contains id_kbadm.pub
└-- /etc/sudoers.d/kbadm
    └-- kbadm ALL=(ALL) NOPASSWD:ALL
```

---

### Step 5 - Verify `kbadm` SSH and Sudo Access

```bash
source /home/kbadm/nodes.env

echo "=== SSH login check ==="
for role in "${!NODES[@]}"; do
  NODE="${NODES[$role]}"
  echo -n "SSH to $role ($NODE) as kbadm ... "
  sudo -u kbadm ssh \
    -i /home/kbadm/.ssh/id_kbadm \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=5 \
    kbadm@$NODE \
    "echo OK - hostname: \$(hostname)" 2>&1
done

echo ""
echo "=== Sudo check ==="
for role in "${!NODES[@]}"; do
  NODE="${NODES[$role]}"
  echo -n "Sudo on $role ($NODE) ... "
  sudo -u kbadm ssh \
    -i /home/kbadm/.ssh/id_kbadm \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=5 \
    kbadm@$NODE \
    "sudo whoami" 2>&1
done
```

---

### Step 6 - Configure SSH Client for `kbadm`

Write a persistent SSH config so `kbadm` can reach nodes by short hostname alias.

```bash
source /home/kbadm/nodes.env

sudo -u kbadm bash -c "cat > /home/kbadm/.ssh/config << 'EOF'
Host *
    IdentityFile /home/kbadm/.ssh/id_kbadm
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    User kbadm

Host control
    HostName ${NODES[control]}

Host worker-1
    HostName ${NODES[worker-1]}

Host worker-2
    HostName ${NODES[worker-2]}

Host worker-3
    HostName ${NODES[worker-3]}
EOF
chmod 600 /home/kbadm/.ssh/config"
```

---

### Step 7 - Set Hostnames

```bash
source /home/kbadm/nodes.env
ADMIN_USER="rocky"

# Bastion itself
sudo hostnamectl set-hostname bastion

# Remote nodes - role name becomes the hostname
for role in "${!NODES[@]}"; do
  NODE="${NODES[$role]}"
  echo "Setting hostname on $NODE -> $role"
  ssh -i ~/top-key.pem \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=10 \
      "$ADMIN_USER@$NODE" \
      "sudo hostnamectl set-hostname $role && echo '[DONE] Hostname: \$(hostname)'"
done

# Verify
echo "--- Verification ---"
for role in "${!NODES[@]}"; do
  echo "[$role]"
  ssh -i ~/top-key.pem -o StrictHostKeyChecking=no \
    "$ADMIN_USER@${NODES[$role]}" "hostname"
done
```

---

### Step 8 - Populate `/etc/hosts` Cluster-Wide

Adds all node IPs and hostnames to `/etc/hosts` on every machine so that short hostnames (`ping control`, `ssh worker-2`) resolve natively without relying solely on SSH config aliases. This is the bare-metal way - no DNS dependency required.

```bash
source /home/kbadm/nodes.env
ADMIN_USER="kbadm"

# Reset block
RESET_BLOCK="127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4"

# Build the hosts block
HOSTS_BLOCK="# k8s cluster nodes
$(hostname -I | awk '{print $1}') bastion"
for role in "${!NODES[@]}"; do
  HOSTS_BLOCK+="
${NODES[$role]} $role"
done
sleep 3
echo "--- Hosts block to be added ---"
echo "$HOSTS_BLOCK"
echo "--------------------------------"

# Reset and apply to bastion
echo "$RESET_BLOCK" | sudo tee /etc/hosts > /dev/null
echo "$HOSTS_BLOCK" | sudo tee -a /etc/hosts > /dev/null
echo "[OK] bastion /etc/hosts updated"

# Reset and apply to all nodes
for role in "${!NODES[@]}"; do
  NODE="${NODES[$role]}"
  ssh -i /home/kbadm/.ssh/id_kbadm \
      -o StrictHostKeyChecking=no \
      "$ADMIN_USER@$NODE" \
      "echo '$RESET_BLOCK' | sudo tee /etc/hosts > /dev/null && \
       echo '$HOSTS_BLOCK' | sudo tee -a /etc/hosts > /dev/null && \
       echo '[OK] $role updated'"
done
```

Verify from the bastion:

```bash
for role in "${!NODES[@]}"; do
  echo -n "ping $role ... "
  ping -c 1 -W 2 $role &>/dev/null && echo "OK" || echo "FAIL"
done
```

---

## Phase 2 - Install Kubespray

### Step 9 - Install Prerequisites on Bastion

```bash
sudo dnf install -y podman git vim jq nc bind-utils
```

---

### Step 10 - Clone and Configure Kubespray

```bash
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray

cp -rfp inventory/sample inventory/mycluster
```

Generate the inventory from `nodes.env`:

```bash
source /home/kbadm/nodes.env
ADMIN_USER="kbadm"
cat > inventory/mycluster/hosts.yaml << EOF
all:
  hosts:
    control:
      ansible_host: ${NODES[control]}
      ansible_user: $ADMIN_USER

    worker-1:
      ansible_host: ${NODES[worker-1]}
      ansible_user: $ADMIN_USER

    worker-2:
      ansible_host: ${NODES[worker-2]}
      ansible_user: $ADMIN_USER

    worker-3:
      ansible_host: ${NODES[worker-3]}
      ansible_user: $ADMIN_USER

  children:
    kube_control_plane:
      hosts:
        control:
    kube_node:
      hosts:
        worker-1:
        worker-2:
        worker-3:
    etcd:
      hosts:
        control:
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {}
EOF
```

---

## Phase 3 - Network Configuration

Workers have no direct internet route - they reach the outside world through the bastion acting as a NAT gateway.

The bastion performs three network roles:

|Role|Mechanism|
|---|---|
|SSH jump host|Only node with a public IP; all cluster SSH goes through it|
|NAT gateway|Workers route internet-bound traffic via bastion MASQUERADE|
|Ingress proxy|iptables DNAT forwards ports 80/443 to worker NodePorts via HAProxy|

```
[Internet]
     │
     ▼
[Bastion - public IP]
  ├-- SSH jump → all nodes (kbadm key)
  ├-- MASQUERADE → outbound NAT for workers
  └-- HAProxy :80/:443 → worker NodePorts → Ingress controller
     │
     ▼
[control / worker-1 / worker-2 / worker-3]
  └-- default route via bastion (10.0.12.33)
```
 > [!caution]
 >  **[AWS]** Before configuring routing, you must disable the source/destination check on the bastion EC2 instance, or AWS will silently drop forwarded packets. 
 >   See  [Step B1 - Disable Source/Destination Check (AWS only)](#Step%20B1%20-%20Disable%20Source/Destination%20Check%20(AWS%20only))]

---

### Step 11 - Configure Bastion as NAT Gateway (nftables)

Rocky Linux 9 ships with nftables as the native firewall backend. This replaces the legacy `iptables-services` approach from older guides.
#### ipforwarding
```bash
# Enable IP forwarding - persistent via sysctl
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-ip-forward.conf
sudo sysctl --system
```
#### K8s nftables Setup 

##### 1. Create the ruleset file

```bash
sudo tee /etc/nftables/k8s-nat.nft > /dev/null << 'EOF'
# k8s NAT and forwarding rules
# Meant to be included by /etc/sysconfig/nftables.conf

table ip nftables_svc {

    # Networks to masquerade (k8s pod/service CIDRs)
    set masq_ips {
        type ipv4_addr
        flags interval
        elements = { 10.0.0.0/8 }
    }

    # Port-shadow attack mitigation + masquerade
    chain do_masquerade {
        meta iif > 0 th sport < 16384 th dport >= 32768 masquerade random
        masquerade
    }

    chain POSTROUTING {
        type nat hook postrouting priority srcnat + 20
        policy accept
        ip saddr @masq_ips jump do_masquerade
    }

    chain FORWARD {
        type filter hook forward priority 0; policy drop;
        ip saddr 10.0.0.0/8 accept
        ip daddr 10.0.0.0/8 ct state related,established accept
    }
}
EOF
```


##### 2. Add to system config
```bash

# Confirm the file was written
cat /etc/nftables/k8s-nat.nft

# Append the include to sysconfig (idempotent - skips if already present)
grep -q 'k8s-nat.nft' /etc/sysconfig/nftables.conf || \
  echo 'include "/etc/nftables/k8s-nat.nft"' >> /etc/sysconfig/nftables.conf

# Confirm the include line is present
# Validate syntax - no output means clean, errors will show the exact line
grep k8s-nat /etc/sysconfig/nftables.conf
nft -c -f /etc/sysconfig/nftables.conf

# Enable the service so it starts on boot
# Restart to load the new ruleset
systemctl enable --now nftables
systemctl restart nftables

# Confirm the service is running
# Confirm the ruleset is loaded - expect to see nftables_svc table
systemctl status nftables
nft list ruleset

# Reboot to verify persistence
reboot
# After coming back up, confirm rules survived
nft list ruleset
```

The `nftables_svc` table should still be present without any manual intervention.
Expected output should show both the `nat` and `filter` tables with the rules above.

**What each rule does:**

|Rule|Purpose|
|---|---|
|`oifname "eth0" masquerade`|Rewrites source IP on outbound packets to the bastion's public IP. Unlike SNAT, MASQUERADE handles dynamic IPs automatically.|
|`ip saddr 10.0.0.0/8 accept`|Allows the kernel to forward packets originating from private nodes.|
|`ip daddr 10.0.0.0/8 ct state related,established accept`|Allows reply packets back to private nodes for established connections.|

**Packet flow:**

```
[10.x.x.x worker]
      │  src: 10.0.x.x
      ▼
[Bastion - forward chain]
   saddr 10.0.0.0/8 → ACCEPT
      │
      ▼
[Bastion - postrouting chain]
   oifname eth0 → MASQUERADE  (src rewritten to bastion public IP)
      │
      ▼
[Internet]
      │  reply comes back
      ▼
[Bastion - forward chain]
   daddr 10.0.0.0/8, ct state established → ACCEPT
      │
      ▼
[Worker receives reply]
```


##### 3. Script k8s-nftables-setup.sh 
`k8s-nftables-setup.sh`

```bash
#!/usr/bin/env bash
# k8s-nftables-setup.sh - create, append, load, and verify k8s NAT + forwarding rules
# Run as root: sudo -i

set -euo pipefail

# Abort if not running as root
if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script as root (sudo -i)" >&2
    exit 1
fi

RULES_FILE="/etc/nftables/k8s-nat.nft"
SYSCONFIG="/etc/sysconfig/nftables.conf"

echo "==> [1/4] Writing ruleset to ${RULES_FILE}"
tee "${RULES_FILE}" > /dev/null << 'EOF'
# k8s NAT and forwarding rules
# Meant to be included by /etc/sysconfig/nftables.conf

table ip nftables_svc {

    # Networks to masquerade (k8s pod/service CIDRs)
    set masq_ips {
        type ipv4_addr
        flags interval
        elements = { 10.0.0.0/8 }
    }

    # Port-shadow attack mitigation + masquerade
    chain do_masquerade {
        meta iif > 0 th sport < 16384 th dport >= 32768 masquerade random
        masquerade
    }

    chain POSTROUTING {
        type nat hook postrouting priority srcnat + 20
        policy accept
        ip saddr @masq_ips jump do_masquerade
    }

    chain FORWARD {
        type filter hook forward priority 0; policy drop;
        ip saddr 10.0.0.0/8 accept
        ip daddr 10.0.0.0/8 ct state related,established accept
    }
}
EOF

echo "==> [2/4] Appending include to ${SYSCONFIG} (if not already present)"
grep -q "${RULES_FILE}" "${SYSCONFIG}" || \
    echo "include \"${RULES_FILE}\"" >> "${SYSCONFIG}"

echo "==> [3/4] Validating syntax"
nft -c -f "${SYSCONFIG}" && echo "    Syntax OK"

echo "==> [4/4] Loading ruleset"
systemctl enable --now nftables
systemctl restart nftables

echo ""
echo "==> Verification"
echo "--- nftables service status ---"
systemctl is-active nftables

echo "--- loaded ruleset ---"
nft list ruleset

echo "--- include line in sysconfig ---"
grep k8s-nat "${SYSCONFIG}"

echo ""
echo "Done. Reboot and re-run 'nft list ruleset' to confirm persistence."
```
##### 4. Rollback


```bash
#!/usr/bin/env bash
# k8s-nftables-rollback.sh - remove k8s NAT + forwarding rules
# Run as root: sudo ./k8s-nftables-rollback.sh

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script as root (sudo -i)" >&2
    exit 1
fi

RULES_FILE="/etc/nftables/k8s-nat.nft"
SYSCONFIG="/etc/sysconfig/nftables.conf"

echo "==> [1/4] Removing include line from ${SYSCONFIG}"
sed -i "\|${RULES_FILE}|d" "${SYSCONFIG}"

echo "==> [2/4] Removing ruleset file"
rm -f "${RULES_FILE}"

echo "==> [3/4] Reloading nftables to flush k8s rules"
systemctl restart nftables

echo "==> [4/4] Disabling IP forwarding"
rm -f /etc/sysctl.d/99-ip-forward.conf
sysctl -w net.ipv4.ip_forward=0
sysctl --system

echo ""
echo "==> Verification"
echo "--- active ruleset (nftables_svc table should be gone) ---"
nft list ruleset

echo "--- include line should return no output ---"
grep k8s-nat "${SYSCONFIG}" || echo "    Clean - no k8s-nat reference found"

echo "--- ip_forward should be 0 ---"
sysctl net.ipv4.ip_forward

echo ""
echo "Done. Reboot and re-run 'nft list ruleset' to confirm rollback persists."
```

---

### Step 12 - Set Workers' Default Route via Bastion (Persistent)

On bare metal the default route must survive reboots. This uses NetworkManager to make it permanent, unlike a one-shot `ip route` command.

First, get the bastion's private IP:

```bash
BASTION_IP=$(hostname -I | awk '{print $1}')
echo "Bastion IP: $BASTION_IP"
```

Apply to all nodes:

```bash
#!/bin/bash
BASTION_IP=$(hostname -I | awk '{print $1}')
echo "Bastion IP: $BASTION_IP"
source /home/kbadm/nodes.env
ADMIN_USER="kbadm"

for role in control worker; do
  NODE="${NODES[$role]}"
  echo "--- Setting persistent default route on $role ($NODE) ---"

  ssh -o StrictHostKeyChecking=no "$ADMIN_USER@$NODE" "
    set -e

    CONN=\$(nmcli -t -f NAME con show --active | head -1)
    echo \"  Active connection: \$CONN\"

    METHOD=\$(nmcli -g ipv4.method con show \"\$CONN\")
    echo \"  IPv4 method: \$METHOD\"

    if [ \"\$METHOD\" = \"auto\" ]; then
      # DHCP - use ipv4.routes instead of ipv4.gateway
      echo \"  DHCP connection: adding static route instead of gateway\"
      sudo nmcli connection modify \"\$CONN\" \
        ipv4.routes \"0.0.0.0/0 $BASTION_IP\" \
        ipv4.never-default no
    else
      # Static - safe to set gateway directly
      echo \"  Static connection: setting ipv4.gateway\"
      sudo nmcli connection modify \"\$CONN\" \
        ipv4.gateway $BASTION_IP \
        ipv4.never-default no
    fi

    sudo nmcli connection up \"\$CONN\"

    ip route show default
    echo '[DONE]' \$(hostname) default route set to $BASTION_IP
  "
  echo ""
done
```

> **Why not `ip route replace`?** The `ip route` command is ephemeral - it vanishes on reboot. The NetworkManager approach writes to the connection profile on disk, so the route is re-applied automatically at boot.

---

### Step 13 - Verify NAT Routing

Run these checks manually, or use the helper script [`nat-verify.sh`] [`nat-verify.sh` - Verify NAT Routing for All Workers](#`nat-verify.sh`%20-%20Verify%20NAT%20Routing%20for%20All%20Workers) below.

```bash
#!/usr/bin/env bash
source /home/kbadm/nodes.env
ADMIN_USER="kbadm"
BASTION_IP=$(hostname -I | awk '{print $1}')

# Your public IP as seen from the internet
echo "--- Bastion public IP ---"
curl -s ifconfig.me
echo ""

# Step 1 - can worker ping bastion?
echo "--- Step 1: worker-1 → ping bastion ---"
ssh $ADMIN_USER@${NODES[worker-1]} "ping -c 3 $BASTION_IP"

# Step 2 - is default route set on worker?
echo "--- Step 2: worker-1 default route ---"
ssh $ADMIN_USER@${NODES[worker-1]} "ip route show default"

# Step 3 - can worker ping a public IP?
echo "--- Step 3: worker-1 → ping 8.8.8.8 ---"
ssh $ADMIN_USER@${NODES[worker-1]} "ping -c 3 8.8.8.8"

# Step 4 - is DNS working?
echo "--- Step 4: worker-1 DNS ---"
ssh $ADMIN_USER@${NODES[worker-1]} "nslookup registry.k8s.io"

# -- Replaced: nft list table ip nat / filter → NM + kernel checks ------------

# Step 5 - bastion NAT: IP forwarding + NM connection method
echo "--- Step 5: Bastion NAT (NetworkManager) ---"
echo "  IP forwarding: $(cat /proc/sys/net/ipv4/ip_forward) (1=enabled)"

BASTION_CONN=$(nmcli -t -f NAME con show --active | head -1)
NM_METHOD=$(nmcli -g ipv4.method con show "$BASTION_CONN")
echo "  Active connection:  $BASTION_CONN"
echo "  ipv4.method:        $NM_METHOD"
echo "  Bastion default GW: $(ip route show default | awk '/default/ {print $3; exit}')"

# Step 6 - worker-1 NM route profile + bastion forwarding policy
echo "--- Step 6: worker-1 NM route + bastion forwarding ---"
ssh $ADMIN_USER@${NODES[worker-1]} "
  CONN=\$(nmcli -t -f NAME con show --active | head -1)
  echo \"  Active connection: \$CONN\"
  echo \"  ipv4.routes:       \$(nmcli -g ipv4.routes con show \"\$CONN\")\"
  echo \"  ipv4.method:       \$(nmcli -g ipv4.method con show \"\$CONN\")\"
  echo \"  ipv4.never-default:\$(nmcli -g ipv4.never-default con show \"\$CONN\")\"
"
# Forward chain equivalent - check kernel forwarding policy
echo "  Bastion FORWARD policy: $(sudo iptables -L FORWARD -n | head -2 | tail -1)"

# -----------------------------------------------------------------------------

# Step 7 - end-to-end HTTPS from worker
echo "--- Step 7: worker-1 → HTTPS registry.k8s.io ---"
ssh $ADMIN_USER@${NODES[worker-1]} \
  "curl -L -s -o /dev/null -w '%{http_code}' https://registry.k8s.io"
echo ""
echo "# Should return 200"
```

---

## Phase 4 - Deploy the Cluster

### Step 14 - Run Kubespray via Podman

From the bastion, inside the `kubespray` directory:

```bash
cd ~/kubespray

podman run --rm -it \
  --mount type=bind,source="$(pwd)"/inventory/mycluster,dst=/inventory,relabel=shared \
  --mount type=bind,source="/home/kbadm/.ssh/id_kbadm",dst=/root/.ssh/id_rsa,relabel=shared \
  quay.io/kubespray/kubespray:v2.31.0 bash
```

Inside the container:

```bash
ansible-playbook -i /inventory/hosts.yaml cluster.yml -b -v \
  --private-key=~/.ssh/id_rsa \
  -e kube_version=1.35.0 \
  2>&1 | tee kubespray-$(date +%F).log
```

---

### Step 15 - Install `kubectl` on Bastion

```bash
cd~

curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

echo 'export PATH=$PATH:/usr/local/bin' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
source ~/.bashrc

rm ~/kubectl
kubectl version --client
```

---

### Step 16 - Retrieve Kubeconfig from Control Plane

```bash
source /home/kbadm/nodes.env
CONTROL_PLANE="${NODES[control]}"

mkdir -p ~/.kube
ssh -i /home/kbadm/.ssh/id_kbadm kbadm@$CONTROL_PLANE \
  "sudo cat /etc/kubernetes/admin.conf" > ~/.kube/config

chmod 600 ~/.kube/config
```

Or directly on the control plane node itself:

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

---

### Step 17 - Verify the Cluster

```bash
kubectl get nodes
```

Expected output (all nodes `Ready`):

```
NAME       STATUS   ROLES           AGE   VERSION
control    Ready    control-plane   Xm    v1.35.0
worker-1   Ready    <none>          Xm    v1.35.0
worker-2   Ready    <none>          Xm    v1.35.0
worker-3   Ready    <none>          Xm    v1.35.0
```

---

## Quick Reference

| Phase             | Steps | What it does                                             | 
| ----------------- | ----- | -------------------------------------------------------- |
| Preparation       | 0–1   | Node map + SSH connectivity check                        |
| Admin user        | 2–6   | `kbadm` user, SSH key, sudo, SSH config                  |
| Hostnames + hosts | 7–8   | Set hostnames and populate `/etc/hosts` cluster-wide     |
| Kubespray         | 9–10  | Install tools, clone + configure Kubespray               |
| Network           | 11–13 | nftables NAT gateway, persistent default routes, verify  |
| Deploy            | 14–17 | Run Kubespray, install kubectl, fetch kubeconfig, verify |

> **[AWS]** Also run Step B1 (disable src/dst check) before Step 11.

---

## Helper Scripts

### `nat-verify.sh` - Verify NAT Routing for All Workers


check 2 - nftables
```bash
#!/usr/bin/env bash
# verify_nat_setup.sh - Confirm all NAT/routing settings are correctly applied
# Usage: sudo ./verify_nat_setup.sh
# Run from the bastion host.

source /home/kbadm/nodes.env
ADMIN_USER="kbadm"
BASTION_IP=$(hostname -I | awk '{print $1}')

PASS=0
FAIL=0
WARN=0

# --- Color helpers ------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

pass() { echo -e "  ${GREEN}✓ PASS${RESET}  $1"; ((PASS++)); }
fail() { echo -e "  ${RED}✗ FAIL${RESET}  $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}⚠ WARN${RESET}  $1"; ((WARN++)); }
section() { echo -e "\n${BOLD}${CYAN}══ $1 ══${RESET}"; }

# --- Helper: run a command on a remote worker ---------------------------------
remote() { ssh -o ConnectTimeout=5 "$ADMIN_USER@${NODES[$1]}" "$2" 2>/dev/null; }

# -----------------------------------------------------------------------------
section "1. Bastion - IP Forwarding"
# -----------------------------------------------------------------------------

FWD=$(cat /proc/sys/net/ipv4/ip_forward)
if [[ "$FWD" == "1" ]]; then
    pass "ip_forward = 1 (kernel forwarding active)"
else
    fail "ip_forward = $FWD - run: echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward"
fi

# Verify it's persistent (sysctl.d or sysctl.conf)
if grep -rqs 'net.ipv4.ip_forward\s*=\s*1' /etc/sysctl.conf /etc/sysctl.d/ 2>/dev/null; then
    pass "ip_forward persisted in sysctl config"
else
    warn "ip_forward not found in /etc/sysctl.conf or /etc/sysctl.d/ - will reset on reboot"
fi

# -----------------------------------------------------------------------------
section "2. Bastion - NAT Masquerade (nftables)"
# -----------------------------------------------------------------------------

# Ensure nft is available
if ! command -v nft &>/dev/null; then
    fail "nft not found - install nftables: sudo apt install nftables"
else
    pass "nft binary found ($(nft --version 2>/dev/null | head -1))"

    # Check for a masquerade rule anywhere in nat postrouting chains
    MASQ=$(sudo nft list ruleset 2>/dev/null \
        | grep -c 'masquerade')
    if [[ "$MASQ" -ge 1 ]]; then
        pass "nftables masquerade rule present ($MASQ occurrence(s))"
        sudo nft list ruleset 2>/dev/null \
            | grep -n 'masquerade' | while read -r line; do
            echo "         $line"
        done
    else
        fail "No masquerade rule found in nftables ruleset"
        echo "         Fix example (add to your nftables config):"
        echo "           table ip nat {"
        echo "             chain POSTROUTING {"
        echo "               type nat hook postrouting priority srcnat; policy accept;"
        echo "               oifname <WAN_IFACE> masquerade"
        echo "             }"
        echo "           }"
    fi

    # Check for a forward chain with an accept policy or accept rules
    FORWARD_ACCEPT=$(sudo nft list ruleset 2>/dev/null \
        | grep -c 'hook forward')
    FORWARD_POLICY_ACCEPT=$(sudo nft list ruleset 2>/dev/null \
        | grep -A2 'hook forward' | grep -c 'policy accept')

    if [[ "$FORWARD_POLICY_ACCEPT" -ge 1 ]]; then
        pass "nftables forward hook chain has policy accept"
    elif [[ "$FORWARD_ACCEPT" -ge 1 ]]; then
        # Chain exists but policy may be drop - check for explicit accept rules
        FORWARD_RULES=$(sudo nft list ruleset 2>/dev/null \
            | grep -A10 'hook forward' | grep -c 'accept')
        if [[ "$FORWARD_RULES" -ge 1 ]]; then
            pass "nftables forward chain has explicit accept rule(s)"
        else
            warn "nftables forward chain found but no accept policy or accept rules - traffic may be dropped"
        fi
    else
        warn "No nftables forward hook chain detected - ensure forwarded traffic is not blocked"
    fi

    # Check nftables service is enabled (persistent across reboots)
    if systemctl is-enabled nftables &>/dev/null; then
        pass "nftables service is enabled (persistent on reboot)"
    else
        warn "nftables service is not enabled - rules will not persist on reboot"
        echo "         Fix: sudo systemctl enable nftables"
    fi
fi

# -----------------------------------------------------------------------------
section "3. Bastion - NetworkManager Connection"
# -----------------------------------------------------------------------------

BASTION_CONN=$(nmcli -t -f NAME con show --active | head -1)
NM_METHOD=$(nmcli -g ipv4.method con show "$BASTION_CONN" 2>/dev/null)
BASTION_GW=$(ip route show default | awk '/default/ {print $3; exit}')

[[ -n "$BASTION_CONN" ]] && pass "Active NM connection: $BASTION_CONN" \
                          || fail "No active NetworkManager connection found"

if [[ "$NM_METHOD" == "auto" || "$NM_METHOD" == "manual" ]]; then
    pass "NM ipv4.method = $NM_METHOD"
else
    warn "NM ipv4.method = $NM_METHOD (expected 'auto' or 'manual')"
fi

[[ -n "$BASTION_GW" ]] && pass "Bastion default gateway = $BASTION_GW" \
                        || fail "Bastion has no default gateway"

# -----------------------------------------------------------------------------
section "4. worker-1 - Routing"
# -----------------------------------------------------------------------------

W1_DEFROUTE=$(remote worker-1 "ip route show default")
if echo "$W1_DEFROUTE" | grep -q 'default'; then
    GW=$(echo "$W1_DEFROUTE" | awk '/default/ {print $3; exit}')
    pass "worker-1 has default route via $GW"
else
    fail "worker-1 has no default route"
fi

# Verify gateway matches bastion IP (expected for NAT-through-bastion setups)
if echo "$W1_DEFROUTE" | grep -q "$BASTION_IP"; then
    pass "worker-1 default route points to bastion ($BASTION_IP)"
else
    warn "worker-1 default gateway is NOT the bastion ($BASTION_IP) - verify this is intentional"
    echo "         Current: $W1_DEFROUTE"
fi

W1_NEVER_DEFAULT=$(remote worker-1 "
  CONN=\$(nmcli -t -f NAME con show --active | head -1)
  nmcli -g ipv4.never-default con show \"\$CONN\" 2>/dev/null
")
if [[ "$W1_NEVER_DEFAULT" == "no" || "$W1_NEVER_DEFAULT" == "" ]]; then
    pass "worker-1 ipv4.never-default = ${W1_NEVER_DEFAULT:-no} (default route allowed)"
else
    fail "worker-1 ipv4.never-default = $W1_NEVER_DEFAULT - NM will suppress the default route"
fi

# -----------------------------------------------------------------------------
section "5. worker-1 → Bastion Connectivity"
# -----------------------------------------------------------------------------

if remote worker-1 "ping -c 2 -W 2 $BASTION_IP" | grep -q '2 received'; then
    pass "worker-1 can ping bastion ($BASTION_IP)"
else
    fail "worker-1 cannot ping bastion ($BASTION_IP)"
fi

# -----------------------------------------------------------------------------
section "6. worker-1 → Public Internet (ICMP)"
# -----------------------------------------------------------------------------

if remote worker-1 "ping -c 2 -W 3 8.8.8.8" | grep -q '2 received'; then
    pass "worker-1 can reach 8.8.8.8 (NAT masquerade working)"
else
    fail "worker-1 cannot ping 8.8.8.8 - NAT forwarding may be broken"
fi

# -----------------------------------------------------------------------------
section "7. worker-1 - DNS Resolution"
# -----------------------------------------------------------------------------

DNS_OUT=$(remote worker-1 "nslookup registry.k8s.io 2>&1")
if echo "$DNS_OUT" | grep -q 'Address:.*[0-9]'; then
    RESOLVED=$(echo "$DNS_OUT" | grep -A1 'Name:' | grep 'Address:' | head -1 | awk '{print $2}')
    pass "worker-1 DNS resolves registry.k8s.io → $RESOLVED"
else
    fail "worker-1 DNS cannot resolve registry.k8s.io"
    echo "         Output: $(echo "$DNS_OUT" | head -3)"
fi

# -----------------------------------------------------------------------------
section "8. worker-1 → HTTPS End-to-End (registry.k8s.io)"
# -----------------------------------------------------------------------------

HTTP_CODE=$(remote worker-1 \
  "curl -L -s -o /dev/null -w '%{http_code}' --max-time 10 https://registry.k8s.io")

if [[ "$HTTP_CODE" == "200" ]]; then
    pass "worker-1 HTTPS to registry.k8s.io returned HTTP $HTTP_CODE"
elif [[ "$HTTP_CODE" =~ ^[23] ]]; then
    pass "worker-1 HTTPS to registry.k8s.io returned HTTP $HTTP_CODE (success-class)"
elif [[ -z "$HTTP_CODE" ]]; then
    fail "worker-1 HTTPS check timed out or connection refused"
else
    fail "worker-1 HTTPS to registry.k8s.io returned HTTP $HTTP_CODE"
fi

# -----------------------------------------------------------------------------
section "Summary"
# -----------------------------------------------------------------------------

TOTAL=$((PASS + FAIL + WARN))
echo ""
echo -e "  Total checks : $TOTAL"
echo -e "  ${GREEN}Passed${RESET}       : $PASS"
echo -e "  ${RED}Failed${RESET}       : $FAIL"
echo -e "  ${YELLOW}Warnings${RESET}     : $WARN"
echo ""

if [[ "$FAIL" -eq 0 && "$WARN" -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}All checks passed - NAT routing is correctly configured.${RESET}"
elif [[ "$FAIL" -eq 0 ]]; then
    echo -e "  ${YELLOW}${BOLD}No failures, but review warnings above.${RESET}"
else
    echo -e "  ${RED}${BOLD}$FAIL check(s) failed - review output above and fix before proceeding.${RESET}"
fi
echo ""
```

Save as `~/nat-verify.sh` on the bastion.

```bash
#!/usr/bin/env bash
# Verify internet reachability for every worker node through the bastion NAT.
set -euo pipefail

source /home/kbadm/nodes.env
ADMIN_USER="kbadm"
BASTION_IP=$(hostname -I | awk '{print $1}')
PASS=0; FAIL=0


install_nslookup() {
  local role="$1" node="$2"
  printf "  %-12s %-20s " "$role" "$node"

  local output
  if output=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
      "$ADMIN_USER@$node" \
      "command -v nslookup &>/dev/null && echo ALREADY_PRESENT || \
       (sudo dnf install -y bind-utils 2>&1 | tail -1 && echo INSTALLED)" \
      2>&1); then
    if echo "$output" | grep -q "ALREADY_PRESENT"; then
      printf "%-10s %s\n" "SKIPPED" "(already installed)"
    else
      printf "%-10s\n" "OK"
    fi
    ((PASS += 1))
  else
    printf "%-10s %s\n" "FAIL" "$output"
    ((FAIL += 1))
  fi
}

echo "=== Install nslookup on all nodes $(date) ==="
echo ""
printf "  %-12s %-20s %-10s\n" "ROLE" "NODE" "RESULT"
printf "  %-12s %-20s %-10s\n" "----" "----" "------"

for role in "${!NODES[@]}"; do
  install_nslookup "$role" "${NODES[$role]}"
done

echo "=== Results: $PASS succeeded, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && true || exit 1

PASS=0; FAIL=0

echo "=== NAT verification $(date) ==="

check() {
  local role="$1" node="$2" label="$3" cmd="$4"
  local result
  result=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    "$ADMIN_USER@$node" "$cmd" 2>&1) && status="OK" || status="FAIL"
  printf "  %-10s %-30s %s\n" "$role" "$label" "$status"
  [[ "$status" == "OK" ]] && ((PASS += 1)) || ((FAIL += 1))
}

echo ""

# -- Replaced: iptables MASQUERADE check → NetworkManager/kernel NAT checks ---
echo "--- Bastion NAT (NetworkManager) ---"

# 1. IP forwarding must be enabled for NAT to work
FWD=$(cat /proc/sys/net/ipv4/ip_forward)
[[ "$FWD" == "1" ]] \
  && echo "  IP forwarding:        ENABLED" \
  || echo "  IP forwarding:        DISABLED  ← NAT will not work"

# 2. Active NM connection on bastion
BASTION_CONN=$(nmcli -t -f NAME con show --active | head -1)
echo "  Active connection:    $BASTION_CONN"

# 3. Check the connection is set to share (NM's built-in NAT mode)
#    or at minimum that ipv4.never-default is not blocking forwarding
NM_METHOD=$(nmcli -g ipv4.method con show "$BASTION_CONN")
echo "  ipv4.method:          $NM_METHOD"
[[ "$NM_METHOD" == "shared" ]] \
  && echo "  NM shared/NAT mode:   ACTIVE" \
  || echo "  NM shared/NAT mode:   NOT set (manual NAT assumed via external rules)"

# 4. Confirm bastion itself has a default route to the internet
BASTION_GW=$(ip route show default | awk '/default/ {print $3; exit}')
[[ -n "$BASTION_GW" ]] \
  && echo "  Bastion default GW:   $BASTION_GW  ← upstream route present" \
  || echo "  Bastion default GW:   MISSING  ← no upstream route"

echo ""
# -----------------------------------------------------------------------------

echo "--- Per-node checks ---"
printf "  %-10s %-30s %s\n" "NODE" "CHECK" "RESULT"
printf "  %-10s %-30s %s\n" "----" "-----" "------"

for role in "${!NODES[@]}"; do
  node="${NODES[$role]}"
  check "$role" "$node" "ping bastion"         "ping -c 2 -W 2 $BASTION_IP > /dev/null"
  check "$role" "$node" "default route via NAT" "ip route show default | grep -q $BASTION_IP"

  # Only workers have a statically configured NM route via bastion
  if [[ "$role" != "control" ]]; then
    check "$role" "$node" "NM route configured" \
      "CONN=\$(nmcli -t -f NAME con show --active | head -1); nmcli -g ipv4.routes con show \"\$CONN\" | grep -q '0.0.0.0'"
  fi

  check "$role" "$node" "ping 8.8.8.8"          "ping -c 2 -W 3 8.8.8.8 > /dev/null"
  check "$role" "$node" "DNS registry.k8s.io"   "nslookup registry.k8s.io > /dev/null"
  check "$role" "$node" "HTTPS registry.k8s.io" \
    "curl -L -s -o /dev/null -w '%{http_code}' https://registry.k8s.io | grep -q 200"
  echo ""
done

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1

```

```bash
chmod +x ~/nat-verify.sh
~/nat-verify.sh
```

---

### `cluster-health.sh` - Post-Deploy Cluster Health Check

Save as `~/cluster-health.sh` on the bastion (after kubectl is configured).

```bash
#!/usr/bin/env bash
# Quick cluster health summary: nodes, system pods, failed pods.
set -euo pipefail

check_heading() { echo ""; echo "=== $1 ==="; }

check_heading "Nodes"
kubectl get nodes -o wide

check_heading "System pods (kube-system)"
kubectl get pods -n kube-system

check_heading "Failed / pending pods (all namespaces)"
FAILED=$(kubectl get pods -A --field-selector=status.phase=Failed 2>/dev/null)
PENDING=$(kubectl get pods -A --field-selector=status.phase=Pending 2>/dev/null)
[[ -z "$FAILED" ]]  && echo "  No failed pods"  || echo "$FAILED"
[[ -z "$PENDING" ]] && echo "  No pending pods" || echo "$PENDING"

check_heading "Node conditions (non-Ready)"
kubectl get nodes -o json \
  | jq -r '.items[] | .metadata.name as $n
    | .status.conditions[]
    | select(.type != "Ready" and .status == "True")
    | "  \($n): \(.type) - \(.message)"' \
  || echo "  (jq not available - skipping condition check)"

check_heading "API server reachability"
kubectl cluster-info

echo ""
echo "=== Done ==="
```

```bash
chmod +x ~/cluster-health.sh
~/cluster-health.sh
```

---

### `gen-inventory.sh` - Regenerate Kubespray Inventory from `nodes.env`

Useful if IPs change and you need to rebuild `hosts.yaml` without editing it by hand.

```bash
#!/usr/bin/env bash
# Regenerate inventory/mycluster/hosts.yaml from ~/nodes.env
set -euo pipefail

NODES_ENV="${NODES_ENV:-/home/kbadm/nodes.env}"
INVENTORY_DIR="${KUBESPRAY_DIR:-$HOME/kubespray}/inventory/mycluster"

source "$NODES_ENV"

mkdir -p "$INVENTORY_DIR"

cat > "$INVENTORY_DIR/hosts.yaml" << EOF
all:
  hosts:
    control:
      ansible_host: ${NODES[control]}
      ansible_user: kbadm

    worker-1:
      ansible_host: ${NODES[worker-1]}
      ansible_user: kbadm

    worker-2:
      ansible_host: ${NODES[worker-2]}
      ansible_user: kbadm

    worker-3:
      ansible_host: ${NODES[worker-3]}
      ansible_user: kbadm

  children:
    kube_control_plane:
      hosts:
        control:
    kube_node:
      hosts:
        worker-1:
        worker-2:
        worker-3:
    etcd:
      hosts:
        control:
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {}
EOF

echo "[OK] Written to $INVENTORY_DIR/hosts.yaml"
cat "$INVENTORY_DIR/hosts.yaml"
```

```bash
chmod +x ~/gen-inventory.sh
~/gen-inventory.sh
```

---

# Appendix

> Sections below are supplementary - post-install topics, optional components, and debugging snippets not required for initial cluster deployment.

---

## A1 - DNS Forwarding on Bastion (optional)

If workers need name resolution via the bastion:

```bash
sudo dnf install -y dnsmasq
echo -e "listen-address=0.0.0.0\nbind-interfaces" | sudo tee -a /etc/dnsmasq.conf
sudo systemctl enable --now dnsmasq
```

---

## A2 - Nginx Reverse Proxy on Bastion (optional)

> Not relevant to initial cluster install. Useful if you want the bastion to proxy HTTP traffic to worker NodePorts without a Kubernetes Ingress controller.

```bash
sudo dnf install -y nginx
```

### config
-----

```bash
# Default (port 30080, myapp.example.com) 
bash generate_nginx.sh 
# Custom port and domain g
enerate_nginx_config 30443 api.example.com 
# Write directly to nginx config
generate_nginx_config > /etc/nginx/conf.d/k8s.conf && nginx -s reload
```


```bash
#!/bin/bash
source ~/nodes.env

generate_nginx_config() {
    local port=${1:-30080}
    local server_name=${2:-myapp.example.com}

    # Build upstream block
    upstream_block="upstream k8s_workers {\n"
    for node in "${!NODES[@]}"; do
        [[ "$node" == "control" ]] && continue
        upstream_block+="    server ${NODES[$node]}:${port};   # ${node} NodePort\n"
    done
    upstream_block+="}"

    # Full config
    cat << EOF
${upstream_block}

server {
    listen 80;
    server_name ${server_name};

    location / {
        proxy_pass http://k8s_workers;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
}

generate_nginx_config
```


-------

`/etc/nginx/conf.d/myapp.conf`:

```nginx
upstream k8s_workers {
    server 10.0.1.11:30080;   # worker-1 NodePort
    server 10.0.1.12:30080;   # worker-2 NodePort
    server 10.0.1.13:30080;   # worker-3 NodePort
}

server {
    listen 80;
    server_name myapp.example.com;

    location / {
        proxy_pass http://k8s_workers;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

```bash
sudo systemctl enable --now nginx
sudo nginx -t && sudo systemctl reload nginx
```

---

## A3 - HAProxy Load Balancer on Bastion (recommended bare-metal pattern)

> Not required for initial cluster install. Replaces the iptables round-robin and single-worker DNAT approaches with a proper health-checked load balancer - no cloud provider needed.

HAProxy sits on the bastion and load-balances ports 80 and 443 across all three workers' Ingress NodePorts. It health-checks the backends and removes failed workers automatically.

```
Internet → Bastion:80/443
               │
               ▼
           HAProxy
      (health-checked LB)
     /         |         \
worker-1   worker-2   worker-3
   │            │          │
Ingress     Ingress    Ingress
controller  controller controller
               │
         (routes by host/path)
         app-a svc / app-b svc
```

**Install HAProxy:**

```bash
sudo dnf install -y haproxy
```

**Configure `/etc/haproxy/haproxy.cfg`:**

```haproxy
global
    log /dev/log local0
    maxconn 4096
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5s
    timeout client  30s
    timeout server  30s

frontend k8s_http
    bind *:80
    default_backend workers_http

frontend k8s_https
    bind *:443
    mode tcp
    default_backend workers_https

backend workers_http
    balance roundrobin
    option httpchk GET /healthz
    server worker-1 10.0.8.232:HTTP_NODE_PORT  check
    server worker-2 10.0.13.59:HTTP_NODE_PORT  check
    server worker-3 10.0.13.244:HTTP_NODE_PORT check

backend workers_https
    mode tcp
    balance roundrobin
    server worker-1 10.0.8.232:HTTPS_NODE_PORT  check
    server worker-2 10.0.13.59:HTTPS_NODE_PORT  check
    server worker-3 10.0.13.244:HTTPS_NODE_PORT check
```

Replace `HTTP_NODE_PORT` and `HTTPS_NODE_PORT` with the actual NodePorts assigned to the Ingress controller (check with `kubectl get svc -n ingress-nginx`).

**Dynamic way** 

```bash
#!/usr/bin/env bash
set -euo pipefail

trap 'echo "ERROR at line $LINENO: $(sed -n "${LINENO}p" "$0")" >&2' ERR

# Load node IPs
source ./nodes.env

# Get both NodePorts in one command
HTTP_NODE_PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
HTTPS_NODE_PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')

# Validate ports were retrieved
if [[ -z "$HTTP_NODE_PORT" || -z "$HTTPS_NODE_PORT" ]]; then
  echo "ERROR: Could not retrieve NodePorts from ingress-nginx" >&2
  exit 1
fi

echo "Ports → HTTP: $HTTP_NODE_PORT  HTTPS: $HTTPS_NODE_PORT"

TMPFILE="$HOME/haproxy.cfg"

cat > "$TMPFILE" <<EOF
global
    log /dev/log local0
    maxconn 4096
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5s
    timeout client  30s
    timeout server  30s

frontend k8s_http
    bind *:80
    default_backend workers_http

frontend k8s_https
    bind *:443
    mode tcp
    option tcplog
    default_backend workers_https

backend workers_http
    balance roundrobin
    server worker-1 ${NODES[worker-1]}:${HTTP_NODE_PORT}  check
    server worker-2 ${NODES[worker-2]}:${HTTP_NODE_PORT}  check
    server worker-3 ${NODES[worker-3]}:${HTTP_NODE_PORT}  check

backend workers_https
    mode tcp
    balance roundrobin
    server worker-1 ${NODES[worker-1]}:${HTTPS_NODE_PORT} check
    server worker-2 ${NODES[worker-2]}:${HTTPS_NODE_PORT} check
    server worker-3 ${NODES[worker-3]}:${HTTPS_NODE_PORT} check
EOF

echo "Config written to $TMPFILE"
echo "---"
cat "$TMPFILE"
echo "---"

haproxy -c -f "$TMPFILE" || { echo "ERROR: config validation failed" >&2; exit 1; }

sudo cp "$TMPFILE" /etc/haproxy/haproxy.cfg
echo "OK - reloading haproxy..."
sudo systemctl start  haproxy
sudo systemctl reload haproxy
sudo systemctl status haproxy --no-pager

```

- **Sources `nodes.env` directly** - add/remove workers there and the config follows automatically
- **Skips `control`** - only worker nodes go into the backends
- **Validates before reloading** - `haproxy -c` catches config errors before `systemctl reload`
- **No sed/manual replacements** - fully generated every run

```bash
chmod +x gen-haproxy.sh 
sudo ./gen-haproxy.sh
```
**Enable and start:**

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg && echo "Config OK"
sudo systemctl enable --now haproxy
```

**Allow ports 80/443 through the bastion's local firewall:**

```bash
# On bare metal - open ports in nftables
sudo nft add rule ip filter input tcp dport { 80, 443 } accept
# Persist by reloading the ruleset after adding to your nft config file
```

> **[AWS]** On EC2, open ports 80 and 443 in the bastion's security group instead. See [Appendix B - Step B2] 
> [Step B2 - Open Ports 80/443 in Security Group (AWS only)](#Step%20B2%20-%20Open%20Ports%2080/443%20in%20Security%20Group%20(AWS%20only))

---

## A4 - Kubernetes Ingress Controller (required for A3 to work)

> Not required for initial cluster install. Deploy an Nginx Ingress controller on the cluster; the bastion HAProxy forwards ports 80/443 to it.

**Deploy the controller (bare-metal provider manifest):**

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/baremetal/deploy.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

**Check the assigned NodePorts:**

```bash
kubectl get svc -n ingress-nginx
# NAME                       TYPE       PORT(S)
# ingress-nginx-controller   NodePort   80:3XXXX/TCP,443:3XXXX/TCP
```

Use these NodePort values in the HAProxy backend config above.

**Per-app Ingress resource:**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: production
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp-svc
            port:
              number: 8080
  - host: otherapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: otherapp-svc
            port:
              number: 9090
```

Add a new app:

```bash
kubectl apply -f my-new-app-ingress.yaml
```

Remove an app (no bastion changes needed):

```bash
kubectl delete ingress my-old-app
```

**Pin Ingress controller to a specific worker (optional):**

```bash
kubectl patch deployment ingress-nginx-controller \
  -n ingress-nginx \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/nodeSelector","value":{"kubernetes.io/hostname":"worker-1"}}]'
```

---

## A5 - Debugging Snippets

> One-off commands captured during cluster debugging.

**Delete all failed pods across namespaces:**

```bash
kubectl delete pods --field-selector=status.phase=Failed -A
```

**Remove a taint from a node:**

```bash
kubectl taint nodes worker-1 node.kubernetes.io/memory-pressure:NoSchedule-
```

**Label a worker node with the worker role:**

```bash
kubectl label node worker-1 node-role.kubernetes.io/worker=worker
```

**Create persistent storage directory on a worker:**

```bash
source /home/kbadm/nodes.env
ADMIN_USER="kbadm"
ssh $ADMIN_USER@${NODES[worker-1]} \
  "sudo mkdir -p /srv/cluster-data/jenkins-data && sudo chmod -R 777 /srv/cluster-data"
```

**Change kube-proxy mode from ipvs to iptables:**

```bash
kubectl edit configmap kube-proxy -n kube-system
# Change:  mode: ipvs
# To:      mode: iptables
```

**Delete a specific default route on a node:**

```bash
ssh 10.0.7.167 "sudo ip route del default via 10.0.8.197 dev eth0"
ssh 10.0.7.167 "ip route show | grep default"
```

**Add a policy-based routing table on a worker** (for EIP-attached workers that need direct egress):

```bash
ssh 10.0.7.167 << 'EOF'
# Add a second routing table
echo "200 eip-table" | sudo tee -a /etc/iproute2/rt_tables

# Default route via IGW in that table
sudo ip route add default via 10.0.0.1 dev eth0 table eip-table

# Rule: traffic FROM this worker's own IP uses eip-table
sudo ip rule add from 10.0.7.167 table eip-table priority 100

# Verify
ip rule show
ip route show table eip-table
EOF
```

**Reset all nftables rules (full wipe):**

```bash
sudo nft flush ruleset
sudo systemctl reload nftables
```

Verify after reset:

```bash
sudo nft list ruleset
```

---

## A6 - Inter-Cluster Connectivity Check

> Comprehensive in-cluster network validation using a `curl` pod. Tests pod-to-pod, pod-to-service, DNS resolution, and cross-node reachability. Run after the cluster is up and `kubectl` is configured.

### What it tests

|Layer|Check|
|---|---|
|DNS|CoreDNS resolves cluster-internal names|
|Pod networking|Pods on different nodes can reach each other by IP|
|Service networking|ClusterIP services are reachable from any pod|
|Cross-node|Every worker can be reached from every other worker|
|External egress|Pods can reach the internet through the NAT|
|Kubernetes API|Pod can reach the API server|

---

### Step 1 - Deploy a curl pod on each node

DaemonSet places one curl pod per node with `hostNetwork: false` (normal pod networking):

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: curl-probe
  namespace: default
  labels:
    app: curl-probe
spec:
  selector:
    matchLabels:
      app: curl-probe
  template:
    metadata:
      labels:
        app: curl-probe
    spec:
      tolerations:
      - operator: Exists
      containers:
      - name: curl
        image: alpine/curl
        command: ["sleep", "3600"]
        resources:
          requests:
            cpu: "10m"
            memory: "16Mi"
EOF
```

Wait for all pods to be running:

```bash
kubectl rollout status daemonset/curl-probe --timeout=120s
kubectl get pods -l app=curl-probe -o wide
```

---

### Step 2 - Deploy a test ClusterIP service

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-server
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: echo-server
  template:
    metadata:
      labels:
        app: echo-server
    spec:
      containers:
      - name: echo
        image: hashicorp/http-echo:latest
        args: ["-text=hello-from-echo"]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: echo-svc
  namespace: default
spec:
  selector:
    app: echo-server
  ports:
  - port: 80
    targetPort: 5678
EOF
```

```bash
kubectl wait deployment/echo-server --for=condition=Available --timeout=90s
```

---

### Step 3 - Collect pod IPs and names

```bash
kubectl get pods -l app=curl-probe -o wide

PODS=($(kubectl get pods -l app=curl-probe -o jsonpath='{.items[*].metadata.name}'))
POD_IPS=($(kubectl get pods -l app=curl-probe -o jsonpath='{.items[*].status.podIP}'))
NODES_LIST=($(kubectl get pods -l app=curl-probe -o jsonpath='{.items[*].spec.nodeName}'))

for i in "${!PODS[@]}"; do
  echo "  ${PODS[$i]}  ip=${POD_IPS[$i]}  node=${NODES_LIST[$i]}"
done
```

---

### Step 4 - DNS resolution checks

```bash
POD="${PODS[0]}"

echo "=== DNS: Kubernetes API server ==="
kubectl exec "$POD" -- curl -sk https://kubernetes.default.svc.cluster.local/healthz && echo " [OK]" || echo " [FAIL]"

echo "=== DNS: echo-svc ClusterIP ==="
kubectl exec "$POD" -- curl -sf http://echo-svc.default.svc.cluster.local && echo " [OK]" || echo " [FAIL]"

echo "=== DNS: short name ==="
kubectl exec "$POD" -- curl -sf http://echo-svc && echo " [OK]" || echo " [FAIL]"

echo "=== DNS: external (github.com) ==="
kubectl exec "$POD" -- curl -sf -o /dev/null -w "%{http_code}" https://github.com && echo "" || echo " [FAIL]"
```

---

### Step 5 - Pod-to-pod connectivity (cross-node)

```bash
PODS=($(kubectl get pods -l app=curl-probe -o jsonpath='{.items[*].metadata.name}'))
POD_IPS=($(kubectl get pods -l app=curl-probe -o jsonpath='{.items[*].status.podIP}'))
NODES_LIST=($(kubectl get pods -l app=curl-probe -o jsonpath='{.items[*].spec.nodeName}'))

PASS=0; FAIL=0

echo ""
echo "=== Pod-to-pod reachability ==="
printf "  %-40s %-16s %-16s %s\n" "FROM-POD (node)" "TO-IP" "TO-NODE" "RESULT"
printf "  %-40s %-16s %-16s %s\n" "--------" "-----" "-------" "------"

for i in "${!PODS[@]}"; do
  for j in "${!POD_IPS[@]}"; do
    [[ $i -eq $j ]] && continue
    SRC="${PODS[$i]} (${NODES_LIST[$i]})"
    DST_IP="${POD_IPS[$j]}"
    DST_NODE="${NODES_LIST[$j]}"

    if kubectl exec "${PODS[$i]}" -- \
        curl -sf --max-time 5 "http://${DST_IP}:5678" -o /dev/null 2>/dev/null; then
      STATUS="OK"
      ((PASS+=1))
    else
      STATUS="FAIL"
      ((FAIL+=1))
    fi
    printf "  %-40s %-16s %-16s %s\n" "$SRC" "$DST_IP" "$DST_NODE" "$STATUS"
  done
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
```

---

### Step 6 - Service reachability from every node

```bash
PODS=($(kubectl get pods -l app=curl-probe -o jsonpath='{.items[*].metadata.name}'))
NODES_LIST=($(kubectl get pods -l app=curl-probe -o jsonpath='{.items[*].spec.nodeName}'))

SVC_URL="http://echo-svc.default.svc.cluster.local"
PASS=0; FAIL=0

echo ""
echo "=== ClusterIP service reachability ==="
printf "  %-30s %-16s %s\n" "POD" "NODE" "RESULT"
printf "  %-30s %-16s %s\n" "---" "----" "------"

for i in "${!PODS[@]}"; do
  POD="${PODS[$i]}"
  NODE="${NODES_LIST[$i]}"
  RESPONSE=$(kubectl exec "$POD" -- curl -sf --max-time 5 "$SVC_URL" 2>/dev/null)
  if echo "$RESPONSE" | grep -q "hello-from-echo"; then
    STATUS="OK"
    ((PASS+=1))
  else
    STATUS="FAIL"
    ((FAIL+=1))
  fi
  printf "  %-30s %-16s %s\n" "$POD" "$NODE" "$STATUS"
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
```

---

### Step 7 - External egress from pods

```bash
PODS=($(kubectl get pods -l app=curl-probe -o jsonpath='{.items[*].metadata.name}'))
NODES_LIST=($(kubectl get pods -l app=curl-probe -o jsonpath='{.items[*].spec.nodeName}'))

PASS=0; FAIL=0

echo ""
echo "=== External egress from pods ==="
printf "  %-30s %-16s %-6s %s\n" "POD" "NODE" "CODE" "RESULT"

for i in "${!PODS[@]}"; do
  POD="${PODS[$i]}"
  NODE="${NODES_LIST[$i]}"
  CODE=$(kubectl exec "$POD" -- \
    curl -sf -o /dev/null -w "%{http_code}" --max-time 10 https://ifconfig.me 2>/dev/null)
  if [[ "$CODE" == "200" ]]; then
    STATUS="OK"
    ((PASS+=1))
  else
    STATUS="FAIL (HTTP $CODE)"
    ((FAIL+=1))
  fi
  printf "  %-30s %-16s %-6s %s\n" "$POD" "$NODE" "$CODE" "$STATUS"
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
```

---

### Step 8 - Kubernetes API reachability from pods

```bash
PODS=($(kubectl get pods -l app=curl-probe -o jsonpath='{.items[*].metadata.name}'))
NODES_LIST=($(kubectl get pods -l app=curl-probe -o jsonpath='{.items[*].spec.nodeName}'))

PASS=0; FAIL=0

echo ""
echo "=== API server reachability ==="
printf "  %-30s %-16s %s\n" "POD" "NODE" "RESULT"

for i in "${!PODS[@]}"; do
  POD="${PODS[$i]}"
  NODE="${NODES_LIST[$i]}"
  RESPONSE=$(kubectl exec "$POD" -- \
    curl -sf --max-time 5 -k https://kubernetes.default.svc/healthz 2>/dev/null)
  if [[ "$RESPONSE" == "ok" ]]; then
    STATUS="OK"
    ((PASS+=1))
  else
    STATUS="FAIL"
    ((FAIL+=1))
  fi
  printf "  %-30s %-16s %s\n" "$POD" "$NODE" "$STATUS"
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
```

---

### `cluster-connectivity.sh` - Full automated run

Save as `~/cluster-connectivity.sh` on the bastion. Runs all checks in one pass and exits non-zero if anything fails.

```bash
#!/usr/bin/env bash
# Full inter-cluster connectivity check using curl probe pods.
set -euo pipefail

PASS=0; FAIL=0
ERRORS=()

hdr() { echo ""; echo "=== $1 ==="; }
ok()  { echo "  [OK]  $*"; ((PASS+=1)); }
fail(){ echo "  [FAIL] $*"; ((FAIL+=1)); ERRORS+=("$*"); }

# -- Gather pod inventory -----------------------------------------------------
hdr "Deploying curl-probe DaemonSet"
kubectl apply -f - <<'YAML' >/dev/null
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: curl-probe
  namespace: default
  labels:
    app: curl-probe
spec:
  selector:
    matchLabels:
      app: curl-probe
  template:
    metadata:
      labels:
        app: curl-probe
    spec:
      tolerations:
      - operator: Exists
      containers:
      - name: curl
        image: curlimages/curl:latest
        command: ["sleep", "3600"]
        resources:
          requests:
            cpu: "10m"
            memory: "16Mi"
YAML

kubectl rollout status daemonset/curl-probe --timeout=120s >/dev/null
echo "  DaemonSet ready."

hdr "Deploying echo-server"
kubectl apply -f - <<'YAML' >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-server
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: echo-server
  template:
    metadata:
      labels:
        app: echo-server
    spec:
      containers:
      - name: echo
        image: hashicorp/http-echo:latest
        args: ["-text=hello-from-echo"]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: echo-svc
  namespace: default
spec:
  selector:
    app: echo-server
  ports:
  - port: 80
    targetPort: 5678
YAML

kubectl wait deployment/echo-server --for=condition=Available --timeout=90s >/dev/null
echo "  echo-server ready."

mapfile -t PODS      < <(kubectl get pods -l app=curl-probe -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
mapfile -t POD_IPS   < <(kubectl get pods -l app=curl-probe -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}')
mapfile -t NODE_LIST < <(kubectl get pods -l app=curl-probe -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}')

echo ""
echo "  Probes:"
for i in "${!PODS[@]}"; do
  printf "    %-40s ip=%-16s node=%s\n" "${PODS[$i]}" "${POD_IPS[$i]}" "${NODE_LIST[$i]}"
done

# -- DNS ----------------------------------------------------------------------
hdr "DNS resolution"
POD="${PODS[0]}"
if kubectl exec "$POD" -- curl -sf --max-time 5 -k https://kubernetes.default.svc.cluster.local/healthz 2>/dev/null | grep -q ok; then
  ok "API server DNS (kubernetes.default.svc.cluster.local)"
else
  fail "API server DNS"
fi

if kubectl exec "$POD" -- curl -sf --max-time 5 http://echo-svc.default.svc.cluster.local 2>/dev/null | grep -q hello-from-echo; then
  ok "Service DNS (echo-svc.default.svc.cluster.local)"
else
  fail "Service DNS"
fi

if kubectl exec "$POD" -- curl -sf --max-time 5 http://echo-svc 2>/dev/null | grep -q hello-from-echo; then
  ok "Short-name DNS (echo-svc)"
else
  fail "Short-name DNS"
fi

# -- ClusterIP service reachability from every node --------------------------
hdr "ClusterIP service reachability"
for i in "${!PODS[@]}"; do
  if kubectl exec "${PODS[$i]}" -- curl -sf --max-time 5 http://echo-svc.default.svc.cluster.local 2>/dev/null | grep -q hello-from-echo; then
    ok "${PODS[$i]} (${NODE_LIST[$i]}) → echo-svc"
  else
    fail "${PODS[$i]} (${NODE_LIST[$i]}) → echo-svc"
  fi
done

# -- Kubernetes API reachability from every pod -------------------------------
hdr "Kubernetes API reachability"
for i in "${!PODS[@]}"; do
  if kubectl exec "${PODS[$i]}" -- curl -sf --max-time 5 -k https://kubernetes.default.svc/healthz 2>/dev/null | grep -q ok; then
    ok "${PODS[$i]} (${NODE_LIST[$i]}) → API server"
  else
    fail "${PODS[$i]} (${NODE_LIST[$i]}) → API server"
  fi
done

# -- External egress ----------------------------------------------------------
hdr "External egress (HTTPS)"
for i in "${!PODS[@]}"; do
  CODE=$(kubectl exec "${PODS[$i]}" -- curl -sf -o /dev/null -w "%{http_code}" --max-time 10 https://ifconfig.me 2>/dev/null || true)
  if [[ "$CODE" == "200" ]]; then
    ok "${PODS[$i]} (${NODE_LIST[$i]}) → internet (HTTP $CODE)"
  else
    fail "${PODS[$i]} (${NODE_LIST[$i]}) → internet (HTTP $CODE)"
  fi
done

# -- Summary -------------------------------------------------------------------
echo ""
echo "============================================"
echo "  TOTAL: $PASS passed, $FAIL failed"
echo "============================================"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "  Failed checks:"
  for e in "${ERRORS[@]}"; do echo "    - $e"; done
  echo ""
fi

# -- Cleanup -------------------------------------------------------------------
hdr "Cleanup"
kubectl delete daemonset curl-probe --ignore-not-found >/dev/null
kubectl delete deployment echo-server --ignore-not-found >/dev/null
kubectl delete service echo-svc --ignore-not-found >/dev/null
echo "  Removed curl-probe, echo-server, echo-svc."

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
```

```bash
chmod +x ~/cluster-connectivity.sh
~/cluster-connectivity.sh
```

Expected output (all passing):

```
=== DNS resolution ===
  [OK]  API server DNS (kubernetes.default.svc.cluster.local)
  [OK]  Service DNS (echo-svc.default.svc.cluster.local)
  [OK]  Short-name DNS (echo-svc)

=== ClusterIP service reachability ===
  [OK]  curl-probe-xxxxx (control) → echo-svc
  [OK]  curl-probe-yyyyy (worker-1) → echo-svc
  [OK]  curl-probe-zzzzz (worker-2) → echo-svc
  [OK]  curl-probe-aaaaa (worker-3) → echo-svc

=== Kubernetes API reachability ===
  [OK]  curl-probe-xxxxx (control) → API server
  ...

=== External egress (HTTPS) ===
  [OK]  curl-probe-xxxxx (control) → internet (HTTP 200)
  ...

============================================
  TOTAL: 11 passed, 0 failed
============================================
```

**If a check fails:**

|Symptom|Likely cause|
|---|---|
|DNS fails|CoreDNS pod not running - check `kubectl get pods -n kube-system`|
|Service unreachable from specific node|kube-proxy not synced on that node; check `kubectl get pods -n kube-system -l k8s-app=kube-proxy`|
|Pod-to-pod cross-node fails|Calico BGP peering down; check `calicoctl node status` on the affected node|
|External egress fails|NAT rule missing or IP forwarding off; re-run `nat-verify.sh`|
|API server unreachable|Network policy blocking pod CIDR → control plane; check Calico policies|

---

# Appendix B - AWS-Specific Steps

> These steps are **only required when running on AWS EC2**. They have no equivalent on bare metal and can be ignored entirely in a real hardware environment.

---

## Step B1 - Disable Source/Destination Check (AWS only)

AWS EC2 drops forwarded packets by default unless the instance's source/destination check is disabled. On bare metal, the kernel forwards packets without restriction - this check simply does not exist.

Run **once from your local machine** before configuring NAT on the bastion:

```bash
BASTION_ID="i-0f7ed48227f447df5"   # replace with your bastion instance ID

aws ec2 modify-instance-attribute \
  --region us-east-1 \
  --instance-id "$BASTION_ID" \
  --no-source-dest-check
```

Verify:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=k8s-lab-bastion" \
  --query "Reservations[].Instances[].[InstanceId, SourceDestCheck]" \
  --output table
```

Expected: `SourceDestCheck = False`.

> After this step, proceed to [Step 11 - Configure Bastion as NAT Gateway]
> [Step 11 - Configure Bastion as NAT Gateway (nftables)](#Step%2011%20-%20Configure%20Bastion%20as%20NAT%20Gateway%20(nftables))

---

## Step B2 - Open Ports 80/443 in Security Group (AWS only)

On bare metal, open ports in nftables directly (see [A3])
[A3 - HAProxy Load Balancer on Bastion (recommended bare-metal pattern)](#A3%20-%20HAProxy%20Load%20Balancer%20on%20Bastion%20(recommended%20bare-metal%20pattern)). 
On EC2, you instead add rules to the bastion's security group:

```bash
INSTANCE_ID="i-0168e4e5b0a5d9adc"

SG_ID=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0

echo "Done - ports 80 and 443 open on $SG_ID"
```

**Verify security group rules:**

```bash
INSTANCE_ID="i-0168e4e5b0a5d9adc"

SG_ID=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
  --output text)
  
echo "Security Group: $SG_ID"

echo ""
echo "=== INBOUND ==="
aws ec2 describe-security-group-rules \
  --filters Name=group-id,Values=$SG_ID \
  --query 'SecurityGroupRules[?!IsEgress].[CidrIpv4,FromPort,ToPort,IpProtocol,Description]' \
  --output table

echo ""
echo "=== OUTBOUND ==="
aws ec2 describe-security-group-rules \
  --filters Name=group-id,Values=$SG_ID \
  --query 'SecurityGroupRules[?IsEgress].[CidrIpv4,FromPort,ToPort,IpProtocol,Description]' \
  --output table
```

**Open a specific NodePort (optional):**

```bash
aws ec2 authorize-security-group-ingress \
  --group-id sg-02d253bfb3e717b33 \
  --protocol tcp \
  --port 30082 \
  --cidr 0.0.0.0/0
```

---

## Step B3 - Useful AWS CLI Snippets

> General EC2 inspection commands useful when running the cluster on AWS.

List all instances with state, IPs, key, and source-dest check:

```bash
aws ec2 describe-instances \
  --query "Reservations[*].Instances[*].{
    ID:InstanceId,
    Type:InstanceType,
    State:State.Name,
    PubIP:PublicIpAddress,
    PrivIP:PrivateIpAddress,
    Key:KeyName,
    SdCheck:SourceDestCheck,
    SH:SecurityGroups[0].GroupName }" \
  --region "us-east-1" \
  --filters "Name=instance-state-name,Values=running" \
  --output table
```

List instances with Name tag:

```bash
aws ec2 describe-instances \
  --query "Reservations[].Instances[].[Tags[?Key=='Name']|[0].Value,InstanceId,InstanceType,State.Name,PublicIpAddress,PrivateIpAddress]" \
  --output table
```

Check SourceDestCheck on a specific instance:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=k8s-lab-worker-1" \
  --query "Reservations[].Instances[].[InstanceId, SourceDestCheck]" \
  --output table
```

Allocate and associate an Elastic IP:

```bash
aws ec2 allocate-address --domain vpc
aws ec2 associate-address --instance-id i-xxxxxxxx --allocation-id eipalloc-xxxxxxxx
```

---

## Step B4 - iptables Round-Robin Load Balancer (legacy AWS alternative)

> This is an older pattern kept for reference. Prefer [HAProxy (A3)]
> [A3 - HAProxy Load Balancer on Bastion (recommended bare-metal pattern)](#A3%20-%20HAProxy%20Load%20Balancer%20on%20Bastion%20(recommended%20bare-metal%20pattern))
> for new setups - it health-checks backends and handles node failure cleanly. The iptables `statistic nth` approach is stateless and does not detect downed workers.

```bash
source /home/kbadm/nodes.env
HTTP_PORT=30929    # replace with your actual NodePort for 80
HTTPS_PORT=30662   # replace with your actual NodePort for 443

WORKER1="${NODES[worker-1]}"
WORKER2="${NODES[worker-2]}"
WORKER3="${NODES[worker-3]}"

# HTTP round-robin
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 \
  -m statistic --mode nth --every 3 --packet 0 \
  -j DNAT --to-destination ${WORKER1}:${HTTP_PORT}

sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 \
  -m statistic --mode nth --every 2 --packet 0 \
  -j DNAT --to-destination ${WORKER2}:${HTTP_PORT}

sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 \
  -j DNAT --to-destination ${WORKER3}:${HTTP_PORT}

# HTTPS round-robin
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 443 \
  -m statistic --mode nth --every 3 --packet 0 \
  -j DNAT --to-destination ${WORKER1}:${HTTPS_PORT}

sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 443 \
  -m statistic --mode nth --every 2 --packet 0 \
  -j DNAT --to-destination ${WORKER2}:${HTTPS_PORT}

sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 443 \
  -j DNAT --to-destination ${WORKER3}:${HTTPS_PORT}

sudo service iptables save
```

**Reset all iptables rules (full wipe):**

```bash
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -t raw -F
sudo iptables -X
sudo iptables -t nat -X
sudo iptables -t mangle -X
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT
sudo service iptables save
```

Verify after reset:

```bash
sudo iptables -L -n -v
sudo iptables -t nat -L -n -v
```