# Storage & LVM (RHEL-based)

This is a from-the-ground-up explanation of how Linux storage is layered, and how LVM
fits into it. Every example below is checked against a real running system (a Rocky
Linux VM) rather than invented — commands you can't safely run against your own disk
(creating a fresh PV/VG from scratch) are still syntax-verified via `man`, called out
where that's the case.

---

## 1. The layering concept — why there's more than just "a disk"

A traditional (non-LVM) disk looks like this:

```
physical disk  →  partition  →  filesystem  →  mount point
```

One partition is a fixed-size slice of one physical disk. If you outgrow it, your only
options are destructive: repartition, or move everything to a bigger disk. LVM inserts
two extra layers of *indirection* between "partition" and "filesystem" specifically to
remove that limitation:

```
physical disk → partition → Physical Volume (PV) → Volume Group (VG) → Logical Volume (LV) → filesystem → mount point
```

| Layer | What it is | Why it exists |
|---|---|---|
| **Partition** | A slice of a physical disk, same as always | Still the thing LVM sits on top of — LVM doesn't replace partitioning, it consumes a partition (or a whole raw disk) as its input |
| **Physical Volume (PV)** | A partition (or whole disk) labeled so LVM recognizes it as usable storage | This is the "raw material" layer — a PV contributes its space to a pool, nothing more |
| **Volume Group (VG)** | A pool combining one or more PVs' space into a single free-space pool | This is the actual point of LVM: a VG can span *multiple physical disks*, so "how much space do I have" stops being tied to any one disk |
| **Logical Volume (LV)** | A carved-out chunk of a VG's pooled space, presented to the OS as if it were a normal block device | This is what actually gets a filesystem and a mount point — and because it's carved from a flexible pool (not a fixed disk region), it can be resized without repartitioning |

**Concretely, on this system** (verified via `lsblk` + `pvs` + `vgs` + `lvs`):

```
$ lsblk
NAME        MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
nvme0n1     259:0    0   40G  0 disk
├─nvme0n1p1 259:1    0    1M  0 part
├─nvme0n1p2 259:2    0    1G  0 part /boot
└─nvme0n1p3 259:3    0   39G  0 part
  ├─rl-root 253:0    0   37G  0 lvm  /
  └─rl-swap 253:1    0    2G  0 lvm  [SWAP]

$ pvs
  PV             VG Fmt  Attr PSize   PFree
  /dev/nvme0n1p3 rl lvm2 a--  <39.00g    0

$ vgs
  VG #PV #LV #SN Attr   VSize   VFree
  rl   1   2   0 wz--n- <39.00g    0

$ lvs
  LV   VG Attr       LSize
  root rl -wi-ao---- <37.00g
  swap rl -wi-ao----   2.00g
```

Reading this bottom-up through the table above: `nvme0n1p3` (the third partition) is
the one **PV**. It's the sole member of VG **`rl`** (`#PV 1`), which pools its whole
~39G. That pool is carved into two **LVs**: `root` (37G, mounted at `/`) and `swap`
(2G, used as swap space). Note `/boot` (`nvme0n1p2`) is **not** under LVM at all — it's
a plain partition with a filesystem directly on it. This is standard practice: `/boot`
has to be readable by the bootloader *before* LVM is available, so it's kept simple.

**Real-world scenario — why this matters in practice:** a database server ships with a
single 100G disk, and `/var/lib/mysql` is an LV inside a VG on that disk. Six months in,
the database is at 95% and the business needs it to keep running with zero downtime.
Without LVM, this is a weekend outage: shut down, image the disk, attach a bigger one,
restore, hope nothing breaks. With LVM: attach a second disk to the VM, `pvcreate` +
`vgextend` it into the *same* VG the database's LV already lives in, `lvextend` the LV,
`xfs_growfs` — all four steps run live, with the database still accepting writes the
entire time. This exact shape (attach disk → extend VG → extend LV → grow filesystem)
is the single most common reason production Linux boxes use LVM at all, even when they
only ever have one disk at install time.

**The naming convention** — an LV shows up as a device two different ways, both valid,
both pointing at the same thing:
```
/dev/mapper/rl-root      # device-mapper name: <vgname>-<lvname>
/dev/rl/root             # VG-directory name: /dev/<vgname>/<lvname>
```
`df`/`mount` output on this system shows `/dev/mapper/rl-root` — that's `device-mapper`
(the kernel subsystem LVM is built on) naming it `rl-root` because it's VG `rl`, LV `root`.

---

## 2. Partitioning a new disk

Before a disk can become a PV, it typically needs at least one partition on it (LVM
*can* consume a whole raw disk with no partition table, but partitioning first is the
normal/expected practice — it makes the disk self-documenting to `lsblk`/`fdisk` later).

**Partition table types** — every disk needs exactly one of these:
- **MBR** (`msdos`) — legacy, disks up to 2TB, max 4 primary partitions
- **GPT** — modern default, disks beyond 2TB, effectively unlimited partitions

On this system, `nvme0n1` uses GPT (confirmed by having a 1MiB `nvme0n1p1` — that's the
BIOS-boot/GPT-metadata partition GPT layouts commonly reserve).

**Interactive tool — `fdisk`** (works for both MBR and GPT since recent versions):
```bash
sudo fdisk /dev/sdb
# then, at the fdisk prompt:
#   n     new partition
#   p     primary (MBR only)
#   w     write changes and exit
```

**Scriptable tool — `parted`** (verified via `man parted`):
```bash
sudo parted /dev/sdb -- mklabel gpt              # create a GPT partition table
sudo parted /dev/sdb -- mkpart primary 0% 100%   # one partition using the whole disk
sudo parted -l                                    # list partition layout on all disks (-l/--list)
```

**Real-world scenario:** you're provisioning 20 identical worker nodes with Ansible/
Kubespray (this repo's own cluster uses Kubespray — see `k8s/kubespray-bastion-aws-ec2.md`).
Doing `fdisk`'s interactive `n`/`p`/`w` prompts by hand 20 times isn't viable. `parted
... --script` (non-interactive, no prompts) is what an automation playbook actually
calls — it's the same partitioning job, just scriptable instead of typed at a keyboard
one keystroke at a time. `fdisk` is what you reach for once, by hand, on a single box
you're SSH'd into.

---

## 3. Building the LVM stack: PV → VG → LV

Three commands, one per layer, run in order. (Syntax below verified via `man pvcreate`,
`man vgcreate`, `lvcreate --help` — not run live, since this system's PV/VG/LV already
exist and creating a throwaway one isn't a safe thing to demo against a real disk.)

```bash
# 1. Mark a partition (or whole disk) as LVM-usable — writes an LVM label + metadata area
sudo pvcreate /dev/sdb1

# 2. Create a Volume Group, naming it and giving it its first PV(s)
sudo vgcreate data_vg /dev/sdb1

# 3. Carve out a Logical Volume from the VG's pool
sudo lvcreate -L 20G -n data_lv data_vg   # -L: explicit size; -n: LV name
# or, to use all remaining free space in the VG instead of a fixed size:
sudo lvcreate -l 100%FREE -n data_lv data_vg   # -l: extents/percentage, not bytes
```

A VG can be extended later with more PVs (more physical disks added to the same pool):
```bash
sudo pvcreate /dev/sdc1
sudo vgextend data_vg /dev/sdc1
```
This is the concrete payoff of the layering from Section 1 — the VG's total size grew
without touching the LV or filesystem sitting on top of it at all.

**What each command means, in plain terms, with a scenario per step:**

| Command | What it actually does | Real-world trigger |
|---|---|---|
| `pvcreate /dev/sdb1` | Stamps a small LVM label + metadata header onto the partition, nothing else — no data layout yet, just "LVM, please recognize this as usable" | You just attached a fresh cloud volume (AWS EBS, VMware vmdk) to a running VM and it shows up as `/dev/sdb` — this is step one before it can join any pool |
| `vgcreate data_vg /dev/sdb1` | Creates the named pool and immediately absorbs `sdb1`'s full space into it | Setting up a new app server that needs a dedicated, separately-managed data area — e.g. isolating `/var/lib/postgresql` from the OS disk so a runaway query filling up data doesn't also fill up `/` and crash the whole box |
| `lvcreate -L 20G -n data_lv data_vg` | Carves a fixed-size, named chunk out of the VG's pool and exposes it as a block device at `/dev/data_vg/data_lv` | You know exactly how big the volume should be up front (a 20G volume for a service with a known, bounded dataset) |
| `lvcreate -l 100%FREE -n data_lv data_vg` | Same, but claims *all* remaining pool space instead of a fixed number | Single-purpose disk added specifically for one LV — no reason to leave anything unallocated |
| `pvcreate /dev/sdc1` + `vgextend data_vg /dev/sdc1` | Pool absorbs a *second* physical disk's space alongside the first | The database scenario above: ran out of room, attached a second disk instead of replacing the first — now the VG spans two physical disks transparently to anything using the LV |

---

## 4. Putting a filesystem on the LV and mounting it

An LV is just a block device at this point — empty, no filesystem yet, same as a raw
partition would be.

```bash
sudo mkfs.xfs /dev/data_vg/data_lv       # XFS — RHEL/Rocky's default
# or:
sudo mkfs.ext4 /dev/data_vg/data_lv      # ext4 — the other common choice
```

Each of these writes an actual filesystem's on-disk structures (superblock, inode
tables, journal) onto the previously-empty LV — this is the equivalent of formatting a
USB drive before Windows/macOS will let you drop files onto it, just at the command
line and for a server disk instead. **Real-world scenario for choosing between them:**
XFS resizes up freely but never down (Section 6) and handles very large files well —
the default for most RHEL workloads including this system's own root LV. ext4 is chosen
when a tool in the stack specifically requires it, or when the ability to shrink later
is worth more than XFS's other advantages — e.g. a volume you know will be resized
frequently in both directions during early-stage capacity planning.

**Mount it, and find the UUID to make that mount survive a reboot:**
```bash
sudo mkdir -p /data
sudo mount /dev/data_vg/data_lv /data

sudo blkid /dev/data_vg/data_lv
# /dev/mapper/data_vg-data_lv: UUID="..." TYPE="xfs"
```

**Why `/etc/fstab` uses UUID, not `/dev/sdX`** — device names like `/dev/sdb` are
assigned by enumeration order at boot, which can shift if a disk is added, removed, or
the controller enumerates differently on a given boot. A UUID is generated once, baked
into the filesystem itself, and never changes — so `/etc/fstab` references survive disk
reordering that a `/dev/sdX` reference wouldn't. This system's real `/etc/fstab`
(verified via `cat /etc/fstab`) does exactly this for every entry:

```
UUID=52ab6a60-649f-4758-bd7c-0cadab2c795a /                       xfs     defaults        0 0
UUID=7284c43f-e9e5-4149-b957-9293c758fd2d /boot                   xfs     defaults        0 0
UUID=d140e21e-e27c-4b82-a9b4-f2719376c600 none                    swap    defaults        0 0
```

Adding a new entry follows the same shape: `UUID=<from blkid>  <mountpoint>  <fstype>  defaults  0 0`.
After editing, `sudo mount -a` mounts everything in `/etc/fstab` that isn't already
mounted — the standard way to test a new fstab line *before* rebooting and finding out
it was wrong.

**Real-world scenario:** a colleague once hand-edited `/etc/fstab` with `/dev/sdb1`
instead of a UUID, on a box with two identical data disks. A firmware update changed
boot-time enumeration order — `sdb` and `sdc` swapped identities — and on next reboot
the *wrong* disk mounted at that path. Nothing crashed, no error was thrown; the box
just silently came up serving stale/wrong data until someone noticed the mismatch hours
later. That's the specific, concrete failure UUID-based `fstab` entries exist to
prevent — the label is baked into the filesystem itself, so it can't get reassigned by
something as mundane as a reboot.

**Why `mount -a` before rebooting matters, concretely:** if a hand-typed `fstab` line
has a typo in the UUID or filesystem type, `mount -a` fails loudly right there in your
current SSH session — annoying, but recoverable by just fixing the line and retrying.
The same mistake discovered only *after* a reboot, on a remote/headless/cloud box, can
mean the machine fails to boot to a usable state at all (some systems drop to an
emergency shell waiting on a console that isn't there) — turning a one-line typo into a
support ticket for out-of-band/console access.

---

## 5. Growing storage

This repo already has a fully worked, real-world walkthrough of this exact process —
see [`RL-disk-resize.md`](RL-disk-resize.md) for the complete live example (VMware disk
resize → `growpart` → a real "devices file" gotcha → `pvresize` → `lvextend` →
`xfs_growfs`), including actual before/after `df` output from this same system.

The short version, once the underlying partition already has more room available to it:
```bash
sudo pvresize /dev/nvme0n1p3          # tell LVM the PV grew
sudo lvextend -l +100%FREE /dev/mapper/rl-root   # give all new free space to this LV
sudo xfs_growfs /                     # grow the XFS filesystem to fill the LV (XFS: online, while mounted)
# ext4 equivalent of the last step:
sudo resize2fs /dev/mapper/rl-root
```
Note the order: PV first (LVM has to know the pool got bigger), then LV (claim some of
that new space for one specific volume), then filesystem (make that space actually
usable) — each layer only knows about the one below it, so growth has to propagate
upward one layer at a time.

**Real-world scenario — the exact one this system hit:** a Rocky Linux VM in VMware was
provisioned at 20G and hit 87% disk usage. Rather than migrating to a bigger VM (hours
of downtime, DNS/IP changes, re-provisioning), the fix was: bump the virtual disk to
40G from the VMware host UI (seconds, no VM restart needed), then run exactly this
five-command chain from inside the guest, live, while the box stayed up and serving
traffic the whole time. Usage dropped from 87% to 41% with zero downtime. This is the
single most common LVM operation an on-call sysadmin actually performs — "disk is
filling up, extend it" — versus the rarer LV-creation-from-scratch commands in Section 3.

---

## 6. Shrinking, removing, and swap as an LV

**Shrinking is the dangerous direction** — unlike growing, the filesystem must be
shrunk *before* the LV, and only ext4 supports this live-ish (offline, actually — XFS
cannot be shrunk at all, ever, by design):
```bash
sudo umount /data
sudo e2fsck -f /dev/data_vg/data_lv          # required before resize2fs shrinks anything
sudo resize2fs /dev/data_vg/data_lv 15G       # shrink filesystem FIRST
sudo lvreduce -L 15G /dev/data_vg/data_lv     # then shrink the LV to match
```
Shrinking an XFS filesystem is not possible with any tool — the only way to "shrink" an
XFS-backed LV is to back up the data, recreate a smaller filesystem, and restore.

**Real-world scenario — why this asymmetry catches people off guard:** RHEL/Rocky
default to XFS for root and data volumes (this system included, per Section 1). Someone
provisions a 500G LV for what turns out to be a 20G workload, wants the space back for
another LV in the same VG — and discovers there is no `xfs_shrinkfs`, no flag, no way,
period, short of backup/recreate/restore. This is *the* reason experienced RHEL admins
tend to under-provision LVs slightly and grow later (Section 5, always safe, always
online) rather than over-provisioning "just in case" — growing is cheap and reversible-
in-spirit, shrinking XFS is not reversible at all without a full data migration.

**Command-by-command, for the ext4 shrink path above:**

| Command | What it actually does | Why this order, this step |
|---|---|---|
| `umount /data` | Detaches the filesystem from the directory tree — no process can be actively using it during a shrink | Shrinking live, mounted data risks corrupting whatever the filesystem's structures currently point at |
| `e2fsck -f /dev/data_vg/data_lv` | Forces a full consistency check even if the filesystem *looks* clean | `resize2fs` refuses to shrink a filesystem it hasn't just verified — this is a hard prerequisite, not a suggestion |
| `resize2fs ... 15G` | Physically relocates data/metadata to fit within the new, smaller boundary, *then* shrinks the filesystem's idea of its own size | Must happen before the LV shrinks underneath it — if the LV shrank first, the filesystem would be truncated mid-data, destroying whatever no longer fits |
| `lvreduce -L 15G ...` | Shrinks the LV (and therefore the block device) down to match what the filesystem was just resized to fit inside | Only safe to run *after* the filesystem confirmed it no longer needs the space being removed |

**Removing the LVM stack** (reverse order of creation):
```bash
sudo umount /data
sudo lvremove /dev/data_vg/data_lv
sudo vgremove data_vg
sudo pvremove /dev/sdb1
```

**Swap as an LV** — this system's `rl-swap` LV (verified via `lsblk`/`swapon --show`
above) is created and activated the same way as any LV, just formatted and enabled
differently:
```bash
sudo mkswap /dev/rl/swap
sudo swapon /dev/rl/swap
```
and referenced in `/etc/fstab` with filesystem type `swap` and mount point `none` — see
this system's real third `fstab` line above. Being an LV (rather than a fixed
partition) means swap can be grown later with the same `lvextend` pattern as any other
LV, without needing a dedicated swap partition sized correctly up front.

**Real-world scenario:** a memory-hungry batch job (a big `awk`/`sort` pass over a
multi-GB file, or a database `VACUUM`) starts triggering the OOM killer under real
production load, but the box can't be resized/rebooted with a bigger swap partition
during a maintenance window that hasn't been scheduled yet. Because swap here is an LV,
not a fixed partition, the fix is `lvextend` on `rl-swap` (same command shape as growing
`rl-root` in Section 5) followed by `mkswap`+`swapon` on the newly-grown device — live,
no reboot, buying breathing room until the actual root cause (the job's memory usage) is
addressed.

---

## See Also

- [`RL-disk-resize.md`](RL-disk-resize.md) — full worked example of growing this
  exact system's root LV, including a real LVM "devices file" gotcha specific to
  VMware's virtual NVMe controller
- `df`/`mount`-output breakdown (`tmpfs` vs real disk-backed mounts) — also in
  `RL-disk-resize.md`'s appendix
