# 🛠️ Linux Swiss Army Knife

> A no-nonsense command reference for sysadmins, developers, and power users.

---

## 1. Disk Usage - Find Space Hogs

### Check overall disk space

```bash
df -h
```

### Top-level directory sizes (current dir)

```bash
du -h --max-depth=1 . | sort -hr
```

### Top 10 largest directories from root

```bash
du -h --max-depth=1 / 2>/dev/null | sort -hr | head -10
```

### Top 10 largest directories anywhere (recursive)

```bash
du -ah / 2>/dev/null | sort -hr | head -10
```

### Find large files over 500 MB

```bash
find / -type f -size +500M -exec du -h {} + 2>/dev/null | sort -hr
```

### Largest directories in /var (common log/cache bloat)

```bash
du -h --max-depth=2 /var | sort -hr | head -20
```

### Check inode usage, not just byte usage

```bash
df -i
```

`df -h` answers "how many bytes are free"; it says nothing about **inodes** — the
fixed-size table of metadata records a filesystem allocates up front, one per file or
directory, separate from the data blocks that hold file *contents*. A filesystem can
run out of inodes while `df -h` still shows plenty of free space, if something creates
a huge number of tiny files (a mail spool, a session-cache directory, a runaway log
rotation writing one file per second) — each new file consumes one inode regardless of
how small it is. The symptom is `No space left on device` on a disk `df -h` swears is
half empty; `df -i`'s `IUse%` column is the number that actually explains it.

---

## 2. Memory - See What's Eating RAM

### Human-readable memory summary

```bash
free -h
#                total        used        free      shared  buff/cache   available
# Mem:           7.5Gi       2.1Gi       1.0Gi        99Mi       4.7Gi       5.3Gi
```

**Read `available`, not `free`.** The kernel uses spare RAM to cache disk data
(`buff/cache`) because unused memory doing nothing is wasted memory — but that cache is
*reclaimed instantly* the moment a process actually needs it, so it's not really
"used" in any way that matters. `free` (the column) only counts memory doing
*nothing at all*, which on a box that's been up a while is almost always misleadingly
small. `available` is the kernel's own estimate of "how much a new process could
actually get if it asked right now" — that's the number that tells you whether memory
pressure is real.

### Detailed memory info

```bash
cat /proc/meminfo
```

### Top memory-consuming processes

```bash
ps aux --sort=-%mem | head -15
```

### Live memory view (updates every 2s)

```bash
watch -n 2 free -h
```

### Memory usage per process with `smem`

```bash
smem -r -k | head -20
```

> 💡 Install with: `sudo apt install smem` or `sudo dnf install smem`

---

## 3. Port Scanning

### Scan open ports on localhost

```bash
ss -tulnp
```

### Alternative with netstat

```bash
netstat -tulnp
```

### Scan a remote host (common ports)

```bash
nmap 192.168.1.1
```

### Scan a specific port range

```bash
nmap -p 1-1024 192.168.1.1
```

### Scan for open ports on an entire subnet

```bash
nmap -p 22,80,443 192.168.1.0/24
```

### Fast scan with service/version detection

```bash
nmap -sV --open 192.168.1.1
```

### Scan without nmap (pure bash, single port check)

```bash
timeout 1 bash -c "echo >/dev/tcp/192.168.1.1/22" && echo "Port open" || echo "Port closed"
```

---

## 4. IP Scanning - Discover Hosts on the Network

### Ping sweep a subnet (quick & dirty)

```bash
for i in $(seq 1 254); do
  ping -c1 -W1 192.168.1.$i &>/dev/null && echo "192.168.1.$i is up" &
done
wait
```

### Faster ping sweep with fping

```bash
fping -a -g 192.168.1.0/24 2>/dev/null
```

> 💡 Install: `sudo apt install fping`

### Host discovery with nmap (no port scan)

```bash
nmap -sn 192.168.1.0/24
```

### ARP scan (only works on local network)

```bash
sudo arp-scan --localnet
```

> 💡 Install: `sudo apt install arp-scan`

### Show your own IP addresses

```bash
ip addr show
# or shorter:
ip -brief addr
```

### Show routing table

```bash
ip route
```

---

## 5. File Search

`find` walks a directory tree testing every file/directory it encounters against a
list of conditions you give it, left to right — conditions are implicitly **AND**ed
together (a file must pass all of them), and the default action if you don't specify
one is `-print`. That mental model — "conditions, ANDed, applied per-file, then an
action" — is why `find`'s syntax always reads the same shape: `find <where> <tests...>
<action>`, no matter how many tests are chained.

**Why not just `ls -R | grep`?** It looks like the same job, but `ls` was built for
*display*, not for feeding a pipeline — its recursive output interleaves directory
headers and blank lines with the actual filenames, and (in the default multi-column
layout) can pack several unrelated entries onto one line:

```
$ ls -R lstest
lstest:
keep.log  sub/

lstest/sub:
weird name.log

$ ls -R lstest | grep ".log"
keep.log  sub/
weird name.log
```
Both matches came through, but neither line tells you *what directory it's in* — that
context lived in the header line `grep` just filtered out. `find`, on the same tree,
gives one full path per line, every time, with no header/column parsing involved:
```
$ find lstest -name "*.log"
lstest/sub/weird name.log
lstest/keep.log
```
The deeper issue is that `find` has real, typed predicates (`-mtime`, `-size`, `-user`,
`-type`) evaluated against actual filesystem metadata — `ls -R | grep` can only ever
match against *text `ls` chose to print*, which means anything beyond "does the name
contain this substring" (find files >100M, modified in the last 7 days, owned by a
specific user) means parsing `ls -l`'s column output by hand — fragile, and dependent
on `ls`'s date format, locale, and column layout not changing under you. `find`'s
tests don't parse text at all; they ask the filesystem directly.

### Find file by name

```bash
find /path -name "filename.txt"
```

### Case-insensitive name search

```bash
find /path -iname "*.log"
```

### Find files modified in the last 24 hours

```bash
find /path -mtime -1
```

### Find files modified in the last 30 minutes

```bash
find /path -mmin -30
```

### Find files larger than 100 MB

```bash
find /path -size +100M
```

### Find files by owner

```bash
find /path -user alice
```

### Only files, or only directories

```bash
find /path -type f     # regular files only
find /path -type d     # directories only
```
Without `-type`, `find` matches anything — files, directories, symlinks, sockets. Most
recipes above (`-name`, `-mtime`, `-size`) implicitly assume "files," but nothing stops
a directory from also matching `-name "*.log"` if one happens to be named that way —
`-type f` is cheap insurance against that.

### Limit how deep the search recurses

```bash
find /path -maxdepth 1 -name "*.conf"    # this directory only, no subdirectories
find /path -maxdepth 2 -type d           # two levels down, no further
```
`find` recurses fully by default (unbounded depth) — `-maxdepth` caps it. Must come
*before* the test flags in the command (`find /path -maxdepth 1 -name ...`, not the
reverse) — `find` processes options positionally, and global options like `-maxdepth`
apply from where they appear onward.

### Find and execute a command on results

```bash
find /path -name "*.tmp" -exec rm -f {} \;
```

### Fast file lookup by name (uses index)

```bash
# Update index first:
sudo updatedb
# Then search:
locate filename.txt
```

### Find recently changed config files

```bash
find /etc -name "*.conf" -mtime -7
```

### Delete matches directly, without a separate `rm`

```bash
find /path -name "*.tmp" -delete
```
`-delete` is its own action (like `-print`/`-exec`), not a shortcut for `-exec rm {} \;`
— it's built into `find` itself, so it's faster (no subprocess spawned per match) and
safer in one specific way: **`-delete` refuses to remove a non-empty directory**,
whereas `-exec rm -rf {} \;` will happily do exactly that if `-type d` matches
something you didn't expect. Always dry-run first by swapping `-delete` for `-print`
and reading the output before trusting it against anything you can't easily recreate.

### Find empty files or directories

```bash
find /path -type d -empty    # empty directories
find /path -type f -empty    # zero-byte files
```
Useful for spotting leftover scaffolding (a directory created but never populated) or
a botched write (a log/output file that should have content but doesn't).

### Exclude a directory from the results (e.g. skip `.git`)

Two different tools for what sounds like one job, and the difference matters on a
large tree:

```bash
find . -name "*.md" -not -path "*/.git/*"    # or: ! -path "*/.git/*"
```
`-not`/`!` is just another **test** — it still walks into `.git`, checks every file
inside it against `-path`, and filters the ones that match. Cheap on a small repo,
wasteful on something like a `.git` directory with thousands of internal objects.

```bash
find . -path "*/.git" -prune -o -name "*.md" -print
```
`-prune` tells `find` to stop descending into that directory **at all** — it's not a
filter applied after the fact, it's an instruction to skip the whole subtree during the
walk. The `-o` (OR) is required here: read it as "if this is the `.git` path, prune it;
*otherwise*, apply the name test and print." Faster on large excluded trees (build
artifacts, `.git`, `node_modules`), and the one to reach for once `-not -path` visibly
slows down.

Verified:
```bash
$ find testdir -name "*.md" -not -path "*/.git/*"
testdir/top.md
testdir/keep/real.md
$ find testdir -path "*/.git" -prune -o -name "*.md" -print
testdir/top.md
testdir/keep/real.md
```
Same result on a small tree — the two only diverge in *how much work* `find` does to
get there, not in what comes out.

---

## 6. Text Search - grep & Friends

### Basic grep

```bash
grep "pattern" file.txt
```

### Case-insensitive search

```bash
grep -i "error" /var/log/syslog
```

### Recursive search in all files under a directory

```bash
grep -r "pattern" /path/to/dir/
```

### Show line numbers

```bash
grep -n "pattern" file.txt
```

### Show N lines of context around a match

```bash
grep -C 3 "error" /var/log/syslog
```

### Count matching lines

```bash
grep -c "pattern" file.txt
```

### Invert match (lines that do NOT match)

```bash
grep -v "debug" app.log
```

### Search multiple patterns

```bash
grep -E "error|warn|critical" /var/log/syslog
```

### Faster recursive search with ripgrep

```bash
rg "pattern" /path/to/dir/
```

> 💡 Install: `sudo apt install ripgrep`

### Search only specific file types

```bash
grep -r --include="*.py" "import os" /project/
# or with rg:
rg -t py "import os" /project/
```

---

## 7. SSH - Passwordless Authentication

### Step 1 - Generate an SSH key pair (if you don't have one)

```bash
ssh-keygen -t ed25519 -C "your_comment_or_email"
# Keys saved to: ~/.ssh/id_ed25519 and ~/.ssh/id_ed25519.pub
```

### Step 2 - Copy your public key to the remote server

```bash
ssh-copy-id user@remote-host
```

> If `ssh-copy-id` isn't available:
> 
> ```bash
> cat ~/.ssh/id_ed25519.pub | ssh user@remote-host "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
> ```

### Step 3 - Verify permissions on the remote server

```bash
# Run these on the remote server:
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

### Step config for easy aliases (`~/.ssh/config`)

```
Host myserver
    HostName 192.168.1.50
    User alice
    IdentityFile ~/.ssh/id_ed25519
    Port 22
```

Now connect simply with:

```bash
ssh myserver
```

### Disable password auth on server (after confirming key works!)

Edit `/etc/ssh/sshd_config`:

```
PasswordAuthentication no
PubkeyAuthentication yes
```

Then restart SSH:

```bash
sudo systemctl restart sshd
```

---

## 8. User Permissions

### List all users

```bash
cat /etc/passwd | cut -d: -f1
```

### Add a new user

```bash
sudo useradd -m -s /bin/bash alice
sudo passwd alice
```

### Add user to a group

```bash
sudo usermod -aG sudo alice
```

### Show groups a user belongs to

```bash
groups alice
id alice
```

### Remove user from a group

```bash
sudo gpasswd -d alice groupname
```

### Lock / unlock a user account

```bash
sudo usermod -L alice    # lock
sudo usermod -U alice    # unlock
```

### Delete a user (and their home dir)

```bash
sudo userdel -r alice
```

### Switch to another user

```bash
su - alice
```

### Run a command as another user

```bash
sudo -u alice command
```

### List sudoers

```bash
sudo cat /etc/sudoers
# or check drop-in files:
ls /etc/sudoers.d/
```

---

## 9. File & Directory Permissions (Numeric)

### Permission bits reference

|Octal|Binary|Meaning|
|---|---|---|
|`7`|111|read + write + execute|
|`6`|110|read + write|
|`5`|101|read + execute|
|`4`|100|read only|
|`0`|000|no permissions|

> **Format:** `chmod [owner][group][others] file` Example: `755` = owner rwx, group rx, others rx

### Common permission combos

```bash
chmod 755 script.sh       # executable script (owner full, others read+exec)
chmod 644 config.txt      # config file (owner rw, others read only)
chmod 600 secret.key      # private key (owner rw only, nobody else)
chmod 700 private_dir/    # private dir (owner only)
chmod 777 shared/         # full open (use sparingly!)
```

### Change owner

```bash
chown alice file.txt
chown alice:devteam file.txt    # owner:group
chown -R alice:devteam /path/  # recursive
```

### Change group only

```bash
chgrp devteam file.txt
```

### View permissions

```bash
ls -la /path/
stat file.txt
```

### Find files with dangerous permissions

```bash
# World-writable files:
find / -perm -o+w -type f 2>/dev/null

# SUID binaries:
find / -perm -4000 -type f 2>/dev/null

# Files with no owner:
find / -nouser 2>/dev/null
```

**When owner/group/other isn't granular enough** (e.g. "this one extra user needs
read-write, without joining the group or loosening `other`") — that's what ACLs are
for, a separate mechanism layered on top of these numeric bits. See
[`linux/sysadmin/acls.md`](sysadmin/acls.md) for `getfacl`/`setfacl` and the mask
gotcha that trips people up.

---

## 10. journalctl - Reading System Logs

### View all logs (newest last)

```bash
journalctl
```

### Follow live logs (like tail -f)

```bash
journalctl -f
```

### Logs since last boot

```bash
journalctl -b
```

### Logs from a previous boot

```bash
journalctl -b -1    # one boot ago
journalctl -b -2    # two boots ago
```

### Logs for a specific service

```bash
journalctl -u nginx
journalctl -u nginx -f    # follow live
```

### Filter by priority (err, warn, info, debug)

```bash
journalctl -p err
journalctl -p warning..err
```

### Logs from a time range

```bash
journalctl --since "2024-01-15 09:00:00" --until "2024-01-15 10:00:00"
journalctl --since "1 hour ago"
journalctl --since today
```

### Show logs in JSON format

```bash
journalctl -o json-pretty -u sshd | head -50
```

### Disk space used by journal

```bash
journalctl --disk-usage
```

### Vacuum old logs

```bash
sudo journalctl --vacuum-time=7d    # keep last 7 days
sudo journalctl --vacuum-size=500M  # keep max 500 MB
```

---

## 11. System Services - systemctl

### List all running services

```bash
systemctl list-units --type=service --state=running
```

### List all services (including inactive)

```bash
systemctl list-units --type=service --all
```

### Check status of a service

```bash
systemctl status nginx
```

### Start / stop / restart a service

```bash
sudo systemctl start nginx
sudo systemctl stop nginx
sudo systemctl restart nginx
```

### Reload config without full restart

```bash
sudo systemctl reload nginx
```

### Enable / disable at boot

```bash
sudo systemctl enable nginx
sudo systemctl disable nginx
```

### Enable and start in one command

```bash
sudo systemctl enable --now nginx
```

### Check if a service is enabled

```bash
systemctl is-enabled nginx
systemctl is-active nginx
```

### Show failed services

```bash
systemctl --failed
```

### Show service dependencies

```bash
systemctl list-dependencies nginx
```

### Mask a service (prevent it from ever starting)

```bash
sudo systemctl mask nginx
sudo systemctl unmask nginx
```

---

## 12. Processes - List, Kill, fg, bg

### List all running processes

```bash
ps aux
```

### Filter by name

```bash
ps aux | grep nginx
# or:
pgrep -a nginx
```

### Interactive process viewer

```bash
top
# Better alternative:
htop
```

### Find PID of a process

```bash
pidof nginx
pgrep nginx
```

### Kill a process by PID

```bash
kill 1234              # graceful (SIGTERM)
kill -9 1234           # force kill (SIGKILL)
```

### Kill by name

```bash
pkill nginx            # graceful
pkill -9 nginx         # force
killall nginx
```

### Kill all processes by a user

```bash
sudo pkill -u alice
```

### Send a process to the background

```bash
command &              # start directly in background
# or if already running: Ctrl+Z then:
bg                     # resume in background
```

### Bring a background process to foreground

```bash
fg                     # most recent background job
fg %2                  # job number 2
```

### List background jobs

```bash
jobs
jobs -l                # with PIDs
```

### Run process immune to hangups (survives terminal close)

```bash
nohup command &
# or with disown:
command &
disown
```

### Monitor a specific process live

```bash
watch -n 1 "ps aux | grep nginx"
```

### Top processes by CPU

```bash
ps aux --sort=-%cpu | head -10
```

### Top processes by memory

```bash
ps aux --sort=-%mem | head -10
```

---

---

## 13. Package Installation - RHEL / dnf Reference

> Applies to: **RHEL 8/9, CentOS Stream, AlmaLinux, Rocky Linux, Fedora**

### dnf basics

```bash
sudo dnf install package-name       # install
sudo dnf remove package-name        # uninstall
sudo dnf update                     # update all packages
sudo dnf update package-name        # update specific package
sudo dnf upgrade                    # same as update (preferred on RHEL 9+)
sudo dnf autoremove                 # remove unused dependencies
sudo dnf clean all                  # clear cache
```

### Search & inspect

```bash
dnf search keyword                  # search by name/summary
dnf info package-name               # show package details
dnf list installed                  # all installed packages
dnf list available | grep keyword   # search available packages
dnf provides /usr/bin/nmap          # find which package owns a file
dnf repoquery --list package-name   # list files installed by a package
```

### Packages needed for this doc's commands

The table below maps each section's tools to the RHEL package that provides them.

|Section|Tool(s)|Package to install|
|---|---|---|
|Disk Usage|`du`, `df`|_(coreutils - pre-installed)_|
|Disk Usage|`find`|_(findutils - pre-installed)_|
|Memory|`free`|_(procps-ng - pre-installed)_|
|Memory|`smem`|`smem` _(EPEL required)_|
|Port Scanning|`ss`|_(iproute - pre-installed)_|
|Port Scanning|`netstat`|`net-tools`|
|Port Scanning|`nmap`|`nmap`|
|IP Scanning|`fping`|`fping` _(EPEL required)_|
|IP Scanning|`arp-scan`|`arp-scan` _(EPEL required)_|
|IP Scanning|`ip`|_(iproute - pre-installed)_|
|File Search|`locate` / `updatedb`|`mlocate` or `plocate`|
|Text Search|`grep`|_(grep - pre-installed)_|
|Text Search|`rg` (ripgrep)|`ripgrep` _(EPEL required)_|
|SSH|`ssh`, `ssh-copy-id`|`openssh-clients`|
|SSH|`sshd` (server)|`openssh-server`|
|Processes|`htop`|`htop` _(EPEL required)_|
|Processes|`ps`, `kill`, `top`|_(procps-ng - pre-installed)_|
|Processes|`pgrep`, `pkill`|_(procps-ng - pre-installed)_|
|Logs|`journalctl`|`systemd` _(pre-installed)_|
|Services|`systemctl`|`systemd` _(pre-installed)_|

### Enable EPEL (required for several tools above)

EPEL (Extra Packages for Enterprise Linux) provides `fping`, `htop`, `ripgrep`, `smem`, `arp-scan`, and many other tools not in the base RHEL repos.

```bash
# RHEL 8
sudo dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm

# RHEL 9
sudo dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm

# AlmaLinux / Rocky Linux (easier)
sudo dnf install epel-release

# Verify EPEL is active
dnf repolist | grep epel
```

### Install everything from this doc in one shot

```bash
# Base tools (no EPEL needed)
sudo dnf install -y \
  net-tools \
  nmap \
  openssh-clients \
  openssh-server \
  mlocate

# EPEL tools (enable EPEL first - see above)
sudo dnf install -y \
  fping \
  arp-scan \
  htop \
  ripgrep \
  smem

# Update locate database after installing mlocate
sudo updatedb
```

### Enable CodeReady Builder (CRB) - sometimes needed

Some EPEL packages depend on CRB (formerly PowerTools on CentOS):

```bash
# RHEL 8
sudo subscription-manager repos --enable codeready-builder-for-rhel-8-x86_64-rpms

# RHEL 9
sudo subscription-manager repos --enable codeready-builder-for-rhel-9-x86_64-rpms

# AlmaLinux / Rocky (no subscription needed)
sudo dnf config-manager --set-enabled crb
```

See [`linux/sysadmin/installations.md`](sysadmin/installations.md) for what CRB
actually contains (verified live via `dnf repoquery --repo=crb`) — mostly `-devel`/
`-static` packages for libraries not in AppStream.

### dnf history & rollback

```bash
dnf history                         # list past transactions
dnf history info 5                  # details of transaction #5
sudo dnf history undo 5             # roll back transaction #5
```

### Install from a local RPM file

```bash
sudo dnf install ./package.rpm
# or:
sudo rpm -ivh package.rpm
```

### Group installs (bundles of related packages)

```bash
dnf group list                      # show available groups
sudo dnf group install "Development Tools"
sudo dnf group install "System Tools"
```

---

## 14. Port listening - tcpdump
```bash
# Basic - watch all traffic on an interface
sudo tcpdump -i eth0
```
```bash
# Specific port
sudo tcpdump -i eth0 port 80
```
```bash
# Specific host
sudo tcpdump -i eth0 host 10.96.x.x
```
```bash
# Combine - traffic to/from a host on a port
sudo tcpdump -i eth0 host 10.96.x.x and port 80
```
```bash
# More verbose, show payload as ASCII
sudo tcpdump -i eth0 port 80 -A
```
```bash
# Save to file for later analysis in Wireshark
sudo tcpdump -i eth0 -w /tmp/capture.pcap
```
```bash
# Watch all interfaces
sudo tcpdump -i any port 80
```

---

## See Also

- [`linux/text-processing/grep.md`](text-processing/grep.md) — regex modes (BRE/ERE/
  PCRE), decoding combined flags (`-Evo`), the full `*grep` family — §6 here is just
  the basics
- [`linux/ssh/passwordless-login.md`](ssh/passwordless-login.md) — the full
  passwordless-SSH walkthrough §7 here summarizes
- [`linux/sysadmin/users-groups.md`](sysadmin/users-groups.md) — the three files
  (`/etc/passwd`, `/etc/shadow`, `/etc/group`) behind everything in §8
- [`linux/sysadmin/boot-systemd.md`](sysadmin/boot-systemd.md) — boot sequence and
  systemd targets/units behind §11's `systemctl` commands
- [`linux/sysadmin/acls.md`](sysadmin/acls.md) — Access Control Lists, for permission
  needs §9's numeric model can't express
- [`linux/sysadmin/installations.md`](sysadmin/installations.md) — install reference
  for every tool named in this doc, RHEL/Rocky-specific
- [`linux/sysadmin/lvm-storage.md`](sysadmin/lvm-storage.md) — the storage layer
  underneath §1's `du`/`df` commands, if the numbers need more than just "who's using
  space"

---

_Last updated: 2026 · Works on Debian/Ubuntu, RHEL/Fedora, and most systemd-based distros._