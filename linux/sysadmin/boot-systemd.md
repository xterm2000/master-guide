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
| `.timer` | a scheduled trigger for a `.service` (see `scheduling.md`) |
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
- `/etc/systemd/system/` — local overrides and custom units; this is where you put your own `.service`/`.timer` files (as done in `scheduling.md`'s backup timer example).
- `/run/systemd/system/` — runtime-only, gone on reboot.

Never edit a file under `/usr/lib/`; either drop a full replacement in `/etc/systemd/system/` (same filename, takes precedence) or use `systemctl edit unitname` to create a drop-in override snippet under `/etc/systemd/system/unitname.d/` that layers on top of the shipped file instead of replacing it.

## Writing a service unit

When a homelab app or daemon should start at boot, be supervised, restart on crash, and log to journald, write it a `.service` unit instead of hand-rolling `nohup`/`screen` or an `@reboot` cron line. A unit file has three sections: `[Unit]` (metadata and ordering), `[Service]` (the process itself), and `[Install]` (what `systemctl enable` hooks it into).

### A minimal long-running service

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My app
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/myapp --port 8080
Restart=on-failure
RestartSec=5s
User=myapp
Group=myapp

[Install]
WantedBy=multi-user.target
```

- `After=` / `Wants=network-online.target` — order this after the network is actually up *and* pull that target in. `After=` alone only orders; it doesn't request the dependency.
- `ExecStart=` — the command, an **absolute path**, run in the foreground (see `Type=` below). Not a shell — no pipes, globs, or `&&` unless you wrap it in `/bin/sh -c '...'`.
- `WantedBy=multi-user.target` — when you later run `systemctl enable myapp`, this is the line that tells systemd to create the `multi-user.target.wants/myapp.service` symlink (the same mechanism described under "Managing services" below).

### `Type=` — the setting most people get wrong

Tells systemd how to know the service is "up" so it can start whatever ordered `After=` it.

| `Type=` | ExecStart is considered started... | Use for |
|---|---|---|
| `simple` (default) | immediately, as soon as it forks | a foreground app that doesn't signal readiness |
| `exec` | once the binary has `execve()`'d | same, but catches an ExecStart that fails to even start |
| `notify` | when the app calls `sd_notify(READY=1)` | apps with real readiness signalling — e.g. this box's `sshd.service` is `Type=notify` |
| `forking` | when the original process exits and leaves a child | legacy daemons that background themselves; pair with `PIDFile=` |
| `oneshot` | it runs to completion and exits | scripts / setup steps; see `scheduling.md` for timer-driven ones |

A modern app you run in the foreground → `simple` or `exec`. A daemon that insists on backgrounding itself → `forking` + `PIDFile=/run/myapp.pid`.

### Restart policy and the crash-loop guard

```ini
[Service]
Restart=on-failure      # no | on-failure | always | on-abnormal | on-abort | on-watchdog | on-success
RestartSec=5s

[Unit]
StartLimitIntervalSec=60s
StartLimitBurst=5
```

`Restart=on-failure` covers a non-zero exit or a kill by signal, but not a clean `systemctl stop` or exit 0. `Restart=always` also restarts after a clean exit — use it for something that's *supposed* to run forever.

Without a limit, a service that dies instantly on startup will restart forever. `StartLimitBurst=5` within `StartLimitIntervalSec=60s` means: after 5 failed starts in a minute, stop trying and drop the unit into `failed` state. `systemctl status` then shows `start request repeated too quickly`; `systemctl reset-failed myapp` clears it once you've fixed the cause.

### Running as a non-root user

```ini
[Service]
User=myapp
Group=myapp
# or, let systemd invent a throwaway UID for the lifetime of the process:
DynamicUser=yes
StateDirectory=myapp        # creates + owns /var/lib/myapp
CacheDirectory=myapp        # /var/cache/myapp
LogsDirectory=myapp         # /var/log/myapp
RuntimeDirectory=myapp      # /run/myapp, wiped on stop
```

The `*Directory=` options create the directory with the right ownership and mode automatically — no `mkdir`/`chown` in an `ExecStartPre=`. With `DynamicUser=yes` this is the *only* safe way to give the service writable storage, since the UID isn't stable across restarts. The app sees the paths via `$STATE_DIRECTORY`, `$CACHE_DIRECTORY`, etc.

### Environment and working directory

```ini
[Service]
WorkingDirectory=/opt/myapp
Environment=LOG_LEVEL=info
Environment="DB_DSN=postgres://localhost/app"
EnvironmentFile=-/etc/sysconfig/myapp
```

`EnvironmentFile=` reads `KEY=value` lines from a file — the leading `-` means "don't fail if it's missing" (this box's `sshd.service` uses `EnvironmentFile=-/etc/sysconfig/sshd`). Keeps secrets and host-specific tuning out of the version-controlled unit.

### Pre/post hooks and reload

```ini
[Service]
ExecStartPre=/usr/local/bin/myapp --check-config
ExecStartPost=-/usr/local/bin/notify-deploy    # leading - : ignore failure
ExecReload=/bin/kill -HUP $MAINPID
ExecStopPost=/usr/local/bin/cleanup
```

`$MAINPID` expands to the PID of the `ExecStart` process (this box's `sshd.service` uses exactly `ExecReload=/bin/kill -HUP $MAINPID`). Multiple `ExecStartPre=` lines run in order; if any fails (without a `-`), the service doesn't start.

### Cheap hardening

```ini
[Service]
NoNewPrivileges=true
ProtectSystem=strict       # entire filesystem read-only...
ReadWritePaths=/var/lib/myapp   # ...except these
ProtectHome=true
PrivateTmp=true             # private /tmp namespace, auto-cleaned
```

```bash
systemd-analyze security myapp.service   # scores the unit's exposure, lists what each directive would tighten
```

Even just `NoNewPrivileges`, `ProtectSystem=strict` + `ReadWritePaths=`, and `PrivateTmp` remove most of the easy escalation paths for a compromised service, at zero code change.

### Deploy checklist

```bash
sudo systemd-analyze verify /etc/systemd/system/myapp.service   # lint: undefined directives, bad ordering
sudo systemctl daemon-reload                                    # make systemd re-read the file
sudo systemctl start myapp
systemctl status myapp
journalctl -u myapp -f                                          # watch it come up
sudo systemctl enable myapp                                     # once happy: start at boot too
```

User-level services (`~/.config/systemd/user/`, `loginctl enable-linger`) and throwaway transient units (`systemd-run`) are covered in `scheduling.md`.

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
