Node IPs are stored in `linux/ssh/nodes.env`. Edit that file to update IPs before running.
This uses `NODES2`, the associative (role-keyed) shape, since a reboot script
wants to print which role it's rebooting, not just an IP.

```bash
source ~/nodes.env   # or: source linux/ssh/nodes.env

echo "=== Mass reboot ==="
for role in "${!NODES2[@]}"; do
  NODE="${NODES2[$role]}"
  echo -n "SSH to $role ($NODE) as kbadm ... "
  sudo -u kbadm ssh \
    -i /home/kbadm/.ssh/id_kbadm \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=5 \
    kbadm@$NODE \
    "sudo reboot now" 2>&1
done
```

## See Also

- [`nodes.env`](nodes.env) — the `NODES2` array used above
- [`passwordless-sudo.md`](passwordless-sudo.md) — required for the unattended `sudo reboot` here to not prompt
