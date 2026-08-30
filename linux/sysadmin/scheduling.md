# cron, at & systemd timers (RHEL-based)

Three scheduling tools for three overlapping jobs:

- **cron** — run a command repeatedly on a recurring wall-clock schedule.
- **at** — run a command exactly once at a future point in time.
- **systemd timers** — the modern alternative to both: a `.timer` unit triggers a `.service` unit, recurring *or* one-off, with journald logging, catch-up after downtime, dependency ordering, and per-user scheduling.

On a systemd distro (this box is one) timers are generally preferred for new work; cron stays useful for a one-line job and for portability to non-systemd systems, and is what most existing scripts and runbooks still assume.

## cron

```bash
rpm -qf $(which crontab)
# cronie-1.7.0-14.el10.x86_64
systemctl is-active crond
# active
```

The package is called `cronie` (a maintained fork of the original vixie-cron); the daemon it runs is `crond`. Installed and enabled by default on this system.

### Per-user crontabs

```bash
crontab -l          # list current user's crontab
crontab -e          # edit current user's crontab (opens $EDITOR)
crontab -r          # remove current user's crontab entirely
sudo crontab -u alice -l   # list/edit another user's crontab (root only)
```

Per-user crontabs are stored under `/var/spool/cron/` — you never edit that file directly, always go through `crontab -e` so the daemon picks up the change and syntax gets validated.

### Field format

```
*  *  *  *  *  command
|  |  |  |  |
|  |  |  |  +--- day of week (0-6, Sunday=0 or 7; or sun,mon,tue,...)
|  |  |  +------ month (1-12; or jan,feb,...)
|  |  +--------- day of month (1-31)
|  +------------ hour (0-23)
+--------------- minute (0-59)
```

```bash
# every day at 2:30am
30 2 * * * /usr/local/bin/backup.sh

# every 15 minutes
*/15 * * * * /usr/local/bin/healthcheck.sh

# every weekday (mon-fri) at 9am
0 9 * * 1-5 /usr/local/bin/report.sh
```

`,` for lists (`1,15`), `-` for ranges (`1-5`), `/` for step values (`*/15`) — combinable, e.g. `0 8-18/2 * * *` = every 2 hours between 8am and 6pm.

### The system crontab and drop-in style

```bash
cat /etc/crontab
# SHELL=/bin/bash
# PATH=/sbin:/bin:/usr/sbin:/usr/bin
# MAILTO=root
```

`/etc/crontab` has one extra field a per-user crontab doesn't: a **username** column right after the five time fields, since this file isn't owned by a single implicit user the way `crontab -e` output is:

```
*  *  *  *  *  user-name  command to be executed
```

`MAILTO=root` here means any output/errors from these jobs get mailed to root's mail spool (see `users-groups.md`'s note on mail spools) rather than silently discarded.

Rather than editing `/etc/crontab` directly, drop a file into `/etc/cron.d/` instead — same five-fields-plus-username format, but keeps your job isolated from the system file and easy to package/version separately:

```bash
sudo tee /etc/cron.d/my-job <<'EOF'
0 3 * * * root /usr/local/bin/nightly-cleanup.sh
EOF
```

### The hourly/daily/weekly/monthly shortcuts

```bash
ls -d /etc/cron.*
# /etc/cron.d/  /etc/cron.hourly/  /etc/cron.daily/  /etc/cron.weekly/  /etc/cron.monthly/
```

Drop an executable script (no crontab syntax, just a normal script with a shebang) into one of these directories and it runs on that cadence automatically — driven by `/etc/cron.d/0hourly` + `run-parts`, not a hardcoded schedule per file. Simpler than writing a cron time-spec when "roughly daily" is precise enough.

### Restricting who can use cron

```bash
ls /etc/cron.allow /etc/cron.deny
# /etc/cron.deny exists (empty), /etc/cron.allow does not exist on this system
```

If `/etc/cron.allow` exists, only users listed in it may use `crontab`. If it doesn't exist (this system's case), everyone *not* listed in `/etc/cron.deny` may use it. An empty `/etc/cron.deny` (as here) means no one is denied — effectively unrestricted.

## at — run something once, later

```bash
sudo dnf install -y at    # not installed by default on this system
sudo systemctl enable --now atd
```

```bash
at 2:00pm
at> /usr/local/bin/one-shot.sh
at> <Ctrl-D>
# job 3 at Tue Jul 21 14:00:00 2026

echo "/usr/local/bin/one-shot.sh" | at now + 1 hour   # non-interactive, pipe the command in
at now + 5 minutes -f /path/to/script.sh                # -f: read commands from a file instead of stdin
```

Time specs accept both clock times (`at 2:00pm`, `at 14:00`, `at teatime`) and relative offsets (`now + 1 hour`, `now + 3 days`, `tomorrow`).

```bash
atq            # list pending at jobs for current user (same as `at -l`)
atrm 3         # cancel job number 3 (same as `at -d 3`)
```

Same allow/deny restriction mechanism as cron, via `/etc/at.allow` / `/etc/at.deny`.

## systemd timers

A timer is **two units working as a pair**:

- a `.service` unit — *what* to run (usually `Type=oneshot`, since it starts, does its job, and exits);
- a `.timer` unit — *when* to run it. The timer's name should match the service it activates (`backup.timer` → `backup.service`); if it doesn't, point at it explicitly with `Unit=` in the `[Timer]` section.

The split looks like overhead versus a one-line crontab entry, but it buys you: job output goes to the journal automatically (`journalctl -u backup.service`), the service can declare `After=network-online.target` / `Requires=` like any other unit, and you can run the job on demand for testing with `systemctl start backup.service` without touching the schedule.

### A recurring timer

```bash
sudo tee /etc/systemd/system/backup.service <<'EOF'
[Unit]
Description=Nightly backup
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup.sh
EOF

sudo tee /etc/systemd/system/backup.timer <<'EOF'
[Unit]
Description=Run backup.service nightly at 2am

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
RandomizedDelaySec=15m

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now backup.timer
```

`enable` wires the timer into `timers.target` so it survives reboot; `--now` also starts it for the current boot. Note you enable the **timer**, never the service.

### `OnCalendar=` — wall-clock schedules

Format is `DOW YYYY-MM-DD HH:MM:SS`; any field can be `*`, a list (`1,15`), a range (`Mon..Fri`), or a step (`*/15`, `0/15`). Shorthands: `minutely`, `hourly`, `daily`, `weekly`, `monthly`, `quarterly`, `yearly`.

```
OnCalendar=hourly                  # top of every hour
OnCalendar=*-*-* *:0/15:00         # every 15 minutes
OnCalendar=Mon..Fri *-*-* 09:00    # weekdays at 9am
OnCalendar=Mon *-*-* 09:00:00      # Mondays at 9am
OnCalendar=*-*-01 04:00:00         # 1st of every month at 4am
OnCalendar=*-*-* 00,12:00:00       # midnight and noon
```

Always validate an expression before deploying — it also prints the next few fire times:

```bash
systemd-analyze calendar "Mon *-*-* 09:00:00"
#   Normalized form: Mon *-*-* 09:00:00
#       Next elapse: Mon 2026-08-31 09:00:00 EDT
systemd-analyze calendar --iterations=5 "*-*-* *:0/15:00"
```

### Monotonic timers — relative to an event, not the clock

Instead of `OnCalendar=`, a timer can fire a fixed span after some reference point:

```
OnBootSec=15min          # 15 min after the machine boots
OnStartupSec=5min        # 5 min after systemd itself started
OnUnitActiveSec=2h       # 2h after the service last activated (→ "every 2h")
OnActiveSec=30s          # 30s after the timer unit itself was started
```

`OnUnitActiveSec=` is the one to reach for when you want **"every N minutes measured from when the last run finished"** rather than a fixed grid. Plain `*/5` cron will happily start a second copy of a job while the first is still running; an `OnUnitActiveSec=5min` timer only schedules the next run after the current one exits.

```bash
sudo tee /etc/systemd/system/poll.timer <<'EOF'
[Unit]
Description=Poll upstream every 5 min after boot

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF
```

### `Persistent=` and `RandomizedDelaySec=` — the things cron can't do

- **`Persistent=true`** (realtime timers only): if the machine was powered off at the scheduled time, the timer fires the missed run once as soon as the system is back up, instead of silently skipping it. Last-run state is stored under `/var/lib/systemd/timers/`.
- **`RandomizedDelaySec=15m`**: delay each activation by a random amount up to this value. Across a fleet of machines with the same timer, this smears the load (e.g. all nodes phoning home) instead of a thundering herd on the exact minute.
- **`AccuracySec=1s`**: by default systemd batches timer wakeups within a 1-minute window to save power; tighten this if a job genuinely needs to fire on the second.

### User timers — no root, no crontab

Run a timer as your own user, with units under `~/.config/systemd/user/`:

```bash
mkdir -p ~/.config/systemd/user
tee ~/.config/systemd/user/sync.service <<'EOF'
[Unit]
Description=Sync my notes

[Service]
Type=oneshot
ExecStart=%h/bin/sync-notes.sh
EOF

tee ~/.config/systemd/user/sync.timer <<'EOF'
[Unit]
Description=Sync notes every 30 min

[Timer]
OnCalendar=*:0/30

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now sync.timer
```

By default a user's services stop when their last login session ends. To let user timers run around the clock (e.g. on a headless box you only SSH into occasionally):

```bash
sudo loginctl enable-linger $USER
```

### Transient timers — the `at` equivalent, no unit files

`systemd-run` creates throwaway timer+service units on the fly:

```bash
# one-off, 10 minutes from now, cancellable
systemd-run --on-active=10m --unit=reboot-node systemctl reboot
systemctl stop reboot-node.timer          # cancel before it fires

# one-off at a wall-clock time
sudo systemd-run --on-calendar="2026-08-30 03:00" /usr/local/bin/migrate.sh

# quick recurring job without writing files
systemd-run --on-active=1m --on-unit-active=5m --unit=ping-check ping -c1 10.0.0.1
```

Output still lands in the journal (`journalctl -u reboot-node`), unlike `at` whose output goes to mail.

### Managing timers

```bash
systemctl list-timers                 # active timers, next + last fire time, what they activate
systemctl list-timers --all           # include inactive ones
systemctl status backup.timer
systemctl start backup.service        # run the job now, ignoring the schedule (good for testing)
journalctl -u backup.service          # this run's + past runs' output; failures show up here
journalctl -u backup.service --since today
systemctl cat backup.timer            # show the effective unit file(s)
```

## Choosing a tool

| Situation | Use |
|---|---|
| One-line recurring job, or a system without systemd, or matching an existing runbook | **cron** (`crontab -e` or `/etc/cron.d/`) |
| "Roughly daily/hourly" script, don't care about the exact minute | drop it in **`/etc/cron.{daily,hourly,weekly,monthly}/`** |
| One-off future action, cancellable (maintenance window, delayed reboot) | **`at`** or **`systemd-run --on-active=`** |
| Recurring job that must log to journald, catch up after downtime (`Persistent=true`), order after another unit, or jitter across a fleet (`RandomizedDelaySec=`) | **systemd timer** |
| "Every N minutes *after the previous run finishes*" (no overlap) | **systemd timer** with `OnUnitActiveSec=` |
| Per-user schedule with no root and no crontab access | **user systemd timer** + `loginctl enable-linger` |

## Practical Recipes

### A cron backup job that actually surfaces failures instead of failing silently

The classic cron mistake is a job that fails every night with nobody noticing, because output only goes to a mail spool nobody reads. Redirect explicitly instead of relying on `MAILTO`:

```bash
sudo tee /etc/cron.d/nightly-backup <<'EOF'
MAILTO=""
0 2 * * * root /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1 || echo "backup failed $(date)" >> /var/log/backup-failures.log
EOF
```

Empty `MAILTO=""` disables the mail-spool delivery entirely (rather than silently accumulating in a spool no one checks) since output is redirected to a real log file instead. The equivalent systemd timer needs none of this plumbing — `journalctl -u backup.service` already has the output and the exit status.

### One-off: reboot a node in 10 minutes, cancellable

Useful for a maintenance window where you want a safety margin to abort if something looks wrong before the box goes down. Either tool works:

```bash
# with at
sudo dnf install -y at && sudo systemctl enable --now atd
echo "systemctl reboot" | sudo at now + 10 minutes
atq                          # confirm it's queued, note the job number
sudo atrm <job-number>       # cancel if plans change before it fires

# with systemd-run (no package to install)
sudo systemd-run --on-active=10m --unit=maint-reboot systemctl reboot
systemctl list-timers maint-reboot.timer
sudo systemctl stop maint-reboot.timer     # cancel
```
