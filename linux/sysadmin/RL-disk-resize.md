# Resizing a Rocky Linux VM Disk (VMware, LVM + XFS)

Steps to expand a guest filesystem after increasing the virtual disk size in VMware, for a Rocky Linux VM using LVM on top of a GPT partition, with an XFS root filesystem.

## 1. Resize the disk in VMware first
Increase the virtual disk size from the VMware host/hypervisor UI before touching anything in the guest.

## 2. Check that the guest sees the new size

```bash
lsblk
```

Look at the total size of the disk device (e.g. `nvme0n1`). If it doesn't reflect the new size, try a rescan (SCSI-style, may not apply to NVMe):

```bash
echo 1 | sudo tee /sys/class/block/nvme0n1/device/rescan
```

or for NVMe specifically:

```bash
sudo dnf install nvme-cli
sudo nvme ns-rescan /dev/nvme0n1
```

If neither works, a simple `sudo reboot` will always pick up the new size.

> In this case, the guest already saw the full new size (40G) without any rescan.

## 3. Grow the partition holding the LVM PV

Identify the correct partition number from `lsblk` (in this case `nvme0n1p3`, not `p2` — check carefully, don't assume).

```bash
sudo dnf install cloud-utils-growpart   # if growpart isn't already installed
sudo growpart /dev/nvme0n1 3
```

## 4. Fix the LVM "devices file" if `pvresize` fails

Modern LVM restricts visible devices via `/etc/lvm/devices/system.devices`. After a resize, VMware's virtual NVMe controller can report a **new hardware ID (`sys_wwid`)** for the same disk, leaving a stale entry behind. Symptom:

```
Cannot use /dev/nvme0n1p3: device is not in devices file
```

Check current entries:

```bash
sudo lvmdevices
```

If you see two entries for the same `PVID` but different `IDNAME` (one stale, `Device none`, one active), remove the stale one. Note: `--delnotfound` and `--delid` flags are **not available on all LVM versions** — if they fail, edit the file directly:

```bash
sudo cp /etc/lvm/devices/system.devices /etc/lvm/devices/system.devices.bak
sudo sed -i '/eui.<STALE_ID_HERE>/d' /etc/lvm/devices/system.devices
sudo lvmdevices   # confirm only the correct entry remains
```

(Alternative if adding fresh: `sudo lvmdevices --adddev /dev/nvme0n1p3` — may prompt to confirm a duplicate PVID; answer yes only after confirming via `lvmdevices` that the old entry is genuinely stale.)

## 5. Resize the LVM physical volume

```bash
sudo pvresize /dev/nvme0n1p3
sudo vgs   # confirm VFree shows the new free space
```

## 6. Extend the logical volume

```bash
sudo lvextend -l +100%FREE /dev/mapper/rl-root
```

## 7. Grow the XFS filesystem (can be done live, while mounted)

```bash
sudo xfs_growfs /
```

## 8. Verify

```bash
df -h /
```

## Result

Root filesystem grew from **17G → 37G**, usage dropped from **87% → 41%**, ~22G free.

## Full command summary

```bash
sudo growpart /dev/nvme0n1 3
sudo lvmdevices                      # inspect for stale entries
sudo sed -i '/eui.<STALE_ID>/d' /etc/lvm/devices/system.devices   # only if needed
sudo pvresize /dev/nvme0n1p3
sudo lvextend -l +100%FREE /dev/mapper/rl-root
sudo xfs_growfs /
df -h /
```

## Appendix: Understanding `df` output on this system

```
[root@shiva ~]# df | grep -v overlay
Filesystem          1K-blocks     Used Available Use% Mounted on
/dev/mapper/rl-root  38727680 15789584  22938096  41% /
devtmpfs              3888220        0   3888220   0% /dev
tmpfs                 3915668        0   3915668   0% /dev/shm
tmpfs                 1566268    10064   1556204   1% /run
tmpfs                    1024        0      1024   0% /run/credentials/systemd-journald.service
/dev/nvme0n1p2         983040   277872    705168  29% /boot
tmpfs                    1024        0      1024   0% /run/credentials/getty@tty1.service
tmpfs                  783132        4    783128   1% /run/user/1000
```

- **`/dev/mapper/rl-root` → `/`** — the real LVM logical volume, disk-backed root filesystem (the one resized above, XFS).
- **`devtmpfs` → `/dev`** — kernel-populated virtual filesystem holding device nodes (`/dev/sda`, `/dev/null`, etc.). RAM-backed.
- **`tmpfs` → `/dev/shm`** — shared memory for inter-process communication. RAM-backed, defaults to ~half of physical RAM.
- **`tmpfs` → `/run`** — runtime state (PID files, sockets, locks) for the current boot session only; wiped on reboot.
- **`tmpfs` → `/run/credentials/*.service`** — small per-service tmpfs mounts systemd uses to pass credentials securely into individual services. Normal and tiny (1M each).
- **`/dev/nvme0n1p2` → `/boot`** — separate physical partition holding kernel, initramfs, bootloader files. Kept apart from `/` so boot files survive even if the root LV has problems.
- **`tmpfs` → `/run/user/1000`** — per-user runtime directory, created on login, used by session services (e.g. D-Bus).

**Key takeaway:** anything mounted as `tmpfs`/`devtmpfs` lives in RAM only, disappears on reboot, and doesn't consume disk space — safe to ignore when checking real disk usage. Only `rl-root` (`/`) and `nvme0n1p2` (`/boot`) represent actual disk capacity.

## See Also

- [`lvm-storage.md`](lvm-storage.md) — the PV/VG/LV concept model behind every command
  in this walkthrough, plus building an LVM stack from scratch, filesystems, and
  shrinking/removing