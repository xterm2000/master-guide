# cron & at (RHEL-based)

Two different scheduling tools for two different jobs: **cron** runs a command repeatedly on a recurring schedule, **at** runs a command exactly once at a future point in time.

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

## cron vs at vs systemd timers

| Need | Tool |
|---|---|
| Recurring schedule (daily, every 15 min, etc.) | cron |
| One-off future execution | at |
| Recurring schedule with dependency ordering, logging via journald, or that needs to run even if the box was off at the scheduled time | systemd timer (`.timer` unit + `.service` unit) |

systemd timers are the modern alternative to cron on any systemd-based distro (which includes this one), and are generally preferred for new work because job output goes to `journalctl` instead of a mail spool, and timers integrate with the rest of the systemd dependency graph — but cron remains ubiquitous, simpler for a one-line recurring job, and is what most existing scripts/runbooks still assume.

## Practical Recipes

### A backup job that actually surfaces failures instead of failing silently

The classic cron mistake is a job that fails every night with nobody noticing, because output only goes to a mail spool nobody reads. Redirect explicitly instead of relying on `MAILTO`:

```bash
sudo tee /etc/cron.d/nightly-backup <<'EOF'
MAILTO=""
0 2 * * * root /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1 || echo "backup failed $(date)" >> /var/log/backup-failures.log
EOF
```

Empty `MAILTO=""` disables the mail-spool delivery entirely (rather than silently accumulating in a spool no one checks) since output is redirected to a real log file instead.

### The same job as a systemd timer, for comparison

```bash
sudo tee /etc/systemd/system/backup.service <<'EOF'
[Unit]
Description=Nightly backup

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

[Install]
WantedBy=timers.target
EOF

sudo systemctl enable --now backup.timer
sudo systemctl list-timers backup.timer   # confirm next scheduled run
journalctl -u backup.service              # failures show up here automatically, no redirect needed
```

`Persistent=true` is the one thing cron can't do: if the machine was powered off at 2am, the timer fires the missed run as soon as the system is back up, instead of silently skipping that day.

### One-off: reboot a node in 10 minutes, cancellable

Useful for a maintenance window where you want a safety margin to abort if something looks wrong before the box goes down:

```bash
sudo dnf install -y at && sudo systemctl enable --now atd
echo "systemctl reboot" | sudo at now + 10 minutes
atq                          # confirm it's queued, note the job number
sudo atrm <job-number>       # cancel if plans change before it fires
```
