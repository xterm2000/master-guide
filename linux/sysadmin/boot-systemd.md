# Boot Process, systemd, and Services (RHEL-based)

## The boot sequence, stage by stage

```
firmware (UEFI/BIOS) → bootloader (GRUB2) → kernel + initramfs → systemd (PID 1) → target
```

1. **Firmware** (UEFI on modern hardware) runs POST (Power-On Self-Test — the firmware-level hardware check before any OS code runs at all), then hands off to the bootloader found on the **EFI system partition** (a small FAT32 partition, separate from your Linux filesystems, that UEFI firmware knows how to read directly — it holds the bootloader binary itself, since the firmware has no idea how to read ext4/XFS/LVM).
2. **GRUB2** loads — its runtime config lives at `/boot/grub2/grub.cfg`, generated from `/etc/default/grub` plus drop-ins, not edited directly (see below).
3. **Kernel + initramfs** load. The initramfs is a small temporary root filesystem containing just enough drivers/tools to find and mount the *real* root filesystem (critical when root is on LVM or an encrypted volume, as it is on this system per `GRUB_CMDLINE_LINUX`'s `rd.lvm.lv=rl/root`).
4. **Kernel hands off to PID 1**, which on this system is `systemd`:

```bash
ps -p 1 -o pid,comm,cmd
#     PID COMMAND         CMD
#       1 systemd         /usr/lib/systemd/systemd --system --deserialize=107
```

PID 1 isn't just "whichever process starts first" — the kernel treats it as structurally special: every orphaned process (whose parent died) gets re-parented to PID 1, and if PID 1 itself ever dies, the kernel panics rather than continuing, because there's nothing left to own the process tree. This is why `systemd` (or on non-systemd distros, `init`) has to be extremely robust — it's the one process the whole system's stability assumes will never crash.

**The `-d` / `-ctl` naming pattern**: throughout this doc, commands come in two flavors — `systemd`/`crond`/`sshd` (the `-d` suffix marks a **daemon**: a background process started once, never run interactively) versus `systemctl`/`journalctl` (the `-ctl` suffix marks a **control client**: the CLI you actually type, which talks to the daemon — usually over D-Bus for the systemd family — to query or change its state). It's a reliable convention across `systemd-*d` / `*ctl` pairs (`systemd-journald`/`journalctl`, `systemd-networkd`/`networkctl`, `systemd-logind`/`loginctl`); older pre-systemd daemons like `crond` and `sshd` still use the `-d` half but don't have a matching `-ctl` tool — control for those goes through `systemctl` itself instead.

5. **systemd** takes over process supervision for the rest of boot and the entire running system, working toward reaching a **target** — see below.

```bash
systemd-analyze
# Startup finished in 2.594s (kernel) + 2.367s (initrd) + 5.847s (userspace) = 10.809s
# multi-user.target reached after 5.829s in userspace.
```

`systemd-analyze` reports each of these three phases separately — useful for knowing whether a slow boot is a hardware/firmware problem (kernel+initrd time) or a services problem (userspace time).

```bash
systemd-analyze blame | head -5
# 12.350s kdump.service
#  5.092s rsyslog.service
#  5.043s cockpit-issue.service
```

`blame` ranks units by how long each took to start — the first place to look when boot feels slow.

## GRUB2 config — never edit grub.cfg directly

```bash
cat /etc/default/grub
# GRUB_TIMEOUT=5
# GRUB_DEFAULT=saved
# GRUB_CMDLINE_LINUX="crashkernel=2G-64G:256M,64G-:512M resume=UUID=... rd.lvm.lv=rl/root rd.lvm.lv=rl/swap"
```

Edit `/etc/default/grub`, then regenerate the actual boot config:

```bash
sudo grub2-mkconfig -o /boot/grub2/grub.cfg          # BIOS systems
sudo grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg   # UEFI systems (path varies by distro)
```

`grub.cfg` is a generated artifact — hand edits get silently overwritten the next time anything regenerates it (kernel update, `grub2-mkconfig` run by another tool), so `/etc/default/grub` is the actual source of truth.

## systemd targets — the modern replacement for SysV runlevels

A **target** is a synchronization point: a named unit that groups together the other units that must be active to consider that state of the system "reached." Where SysV init had numbered runlevels (0-6), systemd has named targets — some map roughly 1:1 for compatibility:

| Old runlevel | systemd target | Meaning |
|---|---|---|
| 0 | `poweroff.target` | shut down |
| 1 | `rescue.target` | single-user/maintenance mode |
| 3 | `multi-user.target` | full multi-user, no GUI |
| 5 | `graphical.target` | multi-user + display manager |
| 6 | `reboot.target` | reboot |

```bash
systemctl get-default
# multi-user.target
```

This system boots to `multi-user.target` — a server without a desktop environment. `graphical.target` is `multi-user.target` plus a display manager on top (it `Wants=` and pulls in graphical-session units), not a separate parallel state.

```bash
sudo systemctl set-default multi-user.target   # change what a normal boot targets
sudo systemctl isolate rescue.target           # switch to a target right now, without rebooting
```

`isolate` stops everything not required by the target you're switching to — this is how you drop into rescue mode live, not just at boot.

## Unit types

A **unit** is systemd's generic abstraction for "a thing with a name that can be started, stopped, and have dependencies on other things" — the same dependency/ordering machinery (`Wants=`, `Requires=`, `After=`, `Before=`) applies whether that thing is a running process, a mount point, or a scheduled timer. This is a deliberate departure from SysV init, which only really knew about "services" as numbered shell scripts with no shared dependency model. Everything systemd supervises is a unit, typed by suffix:

| Suffix | Manages |
|---|---|
| `.service` | a long-running or one-shot process |
| `.target` | a synchronization group of other units (see above) |
| `.timer` | a scheduled trigger for a `.service` (see `cron-at.md`) |
| `.mount` / `.automount` | a filesystem mount point |
| `.socket` | a socket that can lazily start a `.service` on first connection |
| `.device` | a kernel-exposed device node |
| `.path` | triggers a `.service` when a watched path changes |

## Where unit files live

```bash
systemctl show -p FragmentPath crond
# FragmentPath=/usr/lib/systemd/system/crond.service
```

Three locations, in increasing precedence:

- `/usr/lib/systemd/system/` — shipped by packages; treat as read-only, gets overwritten on package updates.
- `/etc/systemd/system/` — local overrides and custom units; this is where you put your own `.service`/`.timer` files (as done in `cron-at.md`'s backup timer example).
- `/run/systemd/system/` — runtime-only, gone on reboot.

Never edit a file under `/usr/lib/`; either drop a full replacement in `/etc/systemd/system/` (same filename, takes precedence) or use `systemctl edit unitname` to create a drop-in override snippet under `/etc/systemd/system/unitname.d/` that layers on top of the shipped file instead of replacing it.

## Managing services

```bash
sudo systemctl start crond          # start now
sudo systemctl stop crond           # stop now
sudo systemctl restart crond        # stop then start
sudo systemctl reload crond         # re-read config without restarting the process (if the unit supports it)
sudo systemctl enable crond         # start automatically at boot (creates a symlink into the target's .wants/ dir — e.g. /etc/systemd/system/multi-user.target.wants/crond.service — which is literally how systemd knows what to pull in when it reaches that target; `disable` just removes that symlink)
sudo systemctl disable crond        # don't start at boot
sudo systemctl enable --now crond   # both at once — the common combo
```

```bash
systemctl status crond      # is it running, recent log lines, main PID
systemctl is-active crond   # just "active"/"inactive", script-friendly exit code
systemctl is-enabled crond  # just "enabled"/"disabled"
```

After any change to a unit *file* (not a `start`/`stop`/`enable` call), reload systemd's view of it:

```bash
sudo systemctl daemon-reload
```

`enable`/`disable` only change whether a unit *starts at boot* — they don't start or stop it right now, which is why `--now` exists as a shortcut for the extremely common "make it running and keep it that way" case.

## Reading logs — journald

`journald` is systemd's own logging daemon — it captures stdout/stderr from every unit it starts (plus kernel messages and its own structured metadata like unit name, PID, boot ID) into a binary, indexed store, instead of relying on units to write text log files or speak to `syslog` themselves. `journalctl` is the query tool for that store. This is why `journalctl -u myapp.service` above just works with no extra logging configuration — any service run via systemd gets this for free.

```bash
journalctl -u crond              # all logs for one unit
journalctl -u crond -f           # follow, like tail -f
journalctl -b                    # logs from the current boot only
journalctl -b -1                 # logs from the previous boot
journalctl --list-boots          # enumerate available boots to pick from
journalctl -p err                # filter by priority (emerg/alert/crit/err/warning/notice/info/debug)
journalctl --since "1 hour ago"  # relative time filter
```

```bash
journalctl --list-boots
# IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY
#   0 fea8742368ac46a48a2d4f44079db15d Sat 2026-07-18 12:49:36 EDT Tue 2026-07-21 13:16:10 EDT
```

Only one boot is listed here because journald's persistent storage retains logs since this box's last actual reboot — `-1`, `-2`, etc. become available once there's boot history to look back through.

## Practical Recipes

### Diagnose a slow boot

```bash
systemd-analyze                 # split into kernel / initrd / userspace time
systemd-analyze blame           # which unit took longest
systemd-analyze critical-chain  # the actual dependency chain that determined total boot time (blame alone can be misleading — a slow unit off the critical path doesn't delay boot)
```

### A service that keeps crash-looping

```bash
systemctl status myapp.service          # check "Active:" line for restart count / last exit code
journalctl -u myapp.service -n 50       # last 50 log lines for context
systemctl show myapp.service -p ExecStart,Restart,RestartSec   # confirm what the unit is actually configured to do on failure
```

### Override one setting in a shipped unit without forking the whole file

```bash
sudo systemctl edit crond
# opens an editor for /etc/systemd/system/crond.service.d/override.conf — add just the lines you want to change:
# [Service]
# Restart=always
sudo systemctl daemon-reload
sudo systemctl restart crond
```

This keeps the override isolated and package-update-safe, instead of copying and hand-editing the entire shipped `.service` file.
