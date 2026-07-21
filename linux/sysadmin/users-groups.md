# User & Group Administration (RHEL-based)

## The three files behind every user

```bash
head -2 /etc/passwd
# root:x:0:0:Super User:/root:/bin/bash
# bin:x:1:1:bin:/bin:/usr/sbin/nologin
```

`/etc/passwd` fields, colon-separated: `username:x:UID:GID:comment:home:shell`. The `x` in the password field means the real hash lives in `/etc/shadow`, not here — `/etc/passwd` is world-readable, `/etc/shadow` is not.

```bash
head -2 /etc/group
# root:x:0:
# bin:x:1:
```

`/etc/group` fields: `groupname:x:GID:member,member,...`. The trailing member list is only for a user's *supplementary* groups — a user's *primary* group membership is recorded in `/etc/passwd`'s GID field instead, not here.

## UID ranges

```bash
grep -E "^(UID_MIN|UID_MAX)" /etc/login.defs
# UID_MIN                  1000
# UID_MAX                 60000
```

System/service accounts (created by packages, e.g. `bin`, `daemon`) get UIDs below `UID_MIN`. Regular human accounts created with plain `useradd` get the next free UID starting at `UID_MIN` (1000 on this system).

## Creating users

```bash
sudo useradd alice
sudo useradd -m -s /bin/bash -c "Alice Smith" alice   # -m: create home dir, -s: shell, -c: comment/GECOS
sudo useradd -G wheel,docker alice                     # -G: supplementary groups at creation time
```

Defaults for a bare `useradd` come from `/etc/default/useradd`:

```bash
cat /etc/default/useradd
# GROUP=100
# HOME=/home
# INACTIVE=-1
# EXPIRE=
# SHELL=/bin/bash
# SKEL=/etc/skel
# CREATE_MAIL_SPOOL=yes
```

`SKEL=/etc/skel` is where the template dotfiles (`.bashrc`, `.bash_profile`, etc.) get copied from into a new home directory when `-m` is used.

`CREATE_MAIL_SPOOL=yes` pre-creates an empty local mailbox file at `/var/spool/mail/<username>` for the new user — the legacy Unix mechanism cron and system daemons use to deliver mail locally (e.g. a cron job's stderr). Usually sits empty and unused on modern boxes, but `userdel -r` cleans it up along with the home directory.

## Modifying users

```bash
sudo usermod -aG wheel alice     # -aG: APPEND to supplementary groups (never use -G alone here — it REPLACES the group list)
sudo usermod -s /bin/zsh alice   # change shell
sudo usermod -L alice            # lock the account (prepends ! to the password hash in /etc/shadow)
sudo usermod -U alice            # unlock
sudo usermod -l newname alice    # rename login (does not rename home dir)
```

The `-aG` vs `-G` distinction is the single most common `usermod` mistake: `usermod -G wheel alice` with no `-a` drops every other supplementary group alice was in and leaves her only in `wheel`.

## Deleting users

```bash
sudo userdel alice        # leaves home dir and mail spool behind
sudo userdel -r alice     # also removes home dir and mail spool
```

## Groups

```bash
sudo groupadd developers
sudo groupadd -g 2000 developers   # force a specific GID
sudo groupdel developers
sudo gpasswd -a alice developers   # add alice to developers (alternative to usermod -aG)
sudo gpasswd -d alice developers   # remove alice from developers
```

## Inspecting identity and membership

```bash
id alice                  # uid, gid, and all groups for alice
groups alice               # just the group names
getent passwd alice        # /etc/passwd lookup (works against NSS sources too, not just the flat file)
getent group developers    # /etc/group lookup
```

`getent` is the safer way to query user/group info than grepping `/etc/passwd` directly — on systems using LDAP/SSSD for identity, `/etc/passwd` won't have the full picture but `getent` will.

## Passwords and account aging

```bash
sudo passwd alice           # set/change password interactively
sudo passwd -l alice        # lock (same effect as usermod -L)
sudo passwd -e alice        # expire immediately — force change at next login
sudo chage -l alice         # list current aging info
sudo chage -M 90 alice      # max password age: 90 days
sudo chage -m 7 alice       # min password age: 7 days (blocks rapid re-changes to dodge history)
sudo chage -W 14 alice      # warn 14 days before expiry
```

Distribution defaults for these, before any per-user `chage` override, come from `/etc/login.defs`:

```bash
grep -E "^(PASS_MAX_DAYS|PASS_MIN_DAYS|PASS_WARN_AGE)" /etc/login.defs
# PASS_MAX_DAYS	99999   (effectively "never expires" — this is the out-of-the-box default)
# PASS_MIN_DAYS	0
# PASS_WARN_AGE	7
```

## sudo access

Adding a user to the `wheel` group is what grants `sudo` on RHEL-family systems — `/etc/sudoers` (or a drop-in under `/etc/sudoers.d/`) has a `%wheel ALL=(ALL) ALL` line that authorizes the whole group, so `usermod -aG wheel alice` is the standard way to grant sudo, not editing `/etc/sudoers` per-user.

```bash
sudo usermod -aG wheel alice
sudo visudo   # always use visudo, never edit /etc/sudoers directly — it validates syntax before saving
```

## Practical Recipes

### Onboard a new admin (home dir, shell, sudo, supplementary groups, forced password change)

```bash
sudo useradd -m -s /bin/bash -c "Alice Smith" -G wheel,docker alice
sudo passwd alice          # set an initial password
sudo passwd -e alice       # force a change at first login rather than handing over a permanent one
```

### Offboard a departing user — lock first, decide on deletion later

Don't jump straight to `userdel` — locking preserves the account (and its file ownership/audit trail) while you confirm nothing still depends on it:

```bash
sudo usermod -L alice           # lock the password (login blocked)
sudo chage -E 0 alice           # also expire the account immediately (belt-and-suspenders over just -L)
# ...once confirmed safe to remove entirely:
sudo userdel -r alice           # removes home dir + mail spool too
```

### Service account with no interactive login

For a process that needs a Unix identity (to own files, run a daemon as) but should never be logged into directly:

```bash
sudo useradd -r -s /sbin/nologin -M svc_backup   # -r: system account (UID below UID_MIN), -M: no home dir, -s: shell that refuses login
```

`/sbin/nologin` prints a message and exits instead of starting a shell — confirmed present on this system at both `/sbin/nologin` and `/usr/sbin/nologin` (the same binary, RHEL symlinks `/sbin` into `/usr/sbin`).
