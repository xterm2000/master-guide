Node IPs are stored in `linux/ssh/nodes.env`. Edit that file to update IPs before running.

```bash
source ~/nodes.env   # or: source linux/ssh/nodes.env

echo "=== Mass reboot ==="
for role in "${!NODES[@]}"; do
  NODE="${NODES[$role]}"
  echo -n "SSH to $role ($NODE) as kbadm ... "
  sudo -u kbadm ssh \
    -i /home/kbadm/.ssh/id_kbadm \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=5 \
    kbadm@$NODE \
    "sudo reboot now" 2>&1
done
```
