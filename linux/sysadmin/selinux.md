# SELinux (RHEL-based)

## What SELinux actually is

Standard Unix permissions (`rwx` owner/group/other) are **discretionary access control (DAC)** — whoever owns a file decides who can touch it, and a process running as that owner can do anything that owner is allowed to do, full stop. SELinux adds **mandatory access control (MAC)** on top: a system-wide policy, which no individual user or process can override, that says exactly what a given process is allowed to do — regardless of file ownership. A compromised `httpd` process running as root is still DAC-omnipotent; under SELinux's `targeted` policy it's confined to only what the `httpd_t` domain is permitted to do, which is normally nowhere near "read `/etc/shadow`" even though root technically could.

This is why SELinux denials are a distinct failure mode from permission errors: a command can pass every `rwx`/ownership check and still get blocked, because DAC and MAC are two independent gates that both have to allow it.

## Modes

```bash
getenforce
# Permissive
sestatus
# SELinux status:                 enabled
# SELinuxfs mount:                /sys/fs/selinux
# SELinux root directory:         /etc/selinux
# Loaded policy name:             targeted
# Current mode:                   permissive
# Mode from config file:          permissive
```

Three modes:

| Mode | Behavior |
|---|---|
| `enforcing` | policy violations are blocked and logged |
| `permissive` | policy violations are only **logged**, never blocked — the system behaves as if SELinux weren't there, but you can see what *would* have been denied |
| `disabled` | no policy loaded at all |

This system is currently in `permissive` mode (confirmed via `getenforce` above) — useful for working out what a new service needs without it actually breaking, but not a real security boundary in that state.

```bash
sudo setenforce 1   # enforcing, until reboot
sudo setenforce 0   # permissive, until reboot
```

Persisting a mode change across reboots requires editing the config file, not just `setenforce`:

```bash
cat /etc/selinux/config
# SELINUX=permissive
# SELINUXTYPE=targeted
```

`SELINUXTYPE=targeted` is the standard policy set — it confines specific "targeted" daemons (web servers, DNS, etc.) while leaving most user processes unconfined. The alternative `mls` (Multi-Level Security) policy confines everything under a much stricter military-style classification model and is rarely used outside specific compliance contexts.

## Contexts — the labels everything gets

Every file, process, and port carries an SELinux **context**, a 4-part label: `user:role:type:level`. In practice, almost all everyday SELinux work is about the third field, the **type**, because `targeted` policy rules are written as "type X may access type Y" — this is why it's often called **type enforcement**.

```bash
ls -dZ /home/mitek
# unconfined_u:object_r:user_home_dir_t:s0 /home/mitek/

ls -lZ /etc/passwd
# system_u:object_r:passwd_file_t:s0 /etc/passwd

ps -eZ | head -2
# system_u:system_r:init_t:s0  1  ?  systemd
```

Reading these: `/etc/passwd` has type `passwd_file_t`; the `systemd` process (PID 1) runs in domain `init_t` (a process's "type" is also called its **domain** — same concept, different word by convention when talking about running processes instead of files). The policy defines which domains may access which file types — e.g. `httpd_t` can read `httpd_sys_content_t` but not `passwd_file_t`, which is exactly the confinement that limits a compromised web server.

## Fixing wrong file contexts: restorecon vs chcon

This is the single most common real-world SELinux fix: a file was created or moved somewhere and picked up the wrong context (commonly after copying with `cp` into a service's directory, or extracting a tarball) — the fix is almost never to just grant broader access, it's to relabel the file to what policy already expects it to be.

```bash
sudo restorecon -v /var/www/html/index.html   # reset to the context policy defines for this path
sudo restorecon -Rv /var/www/html/            # recursive
```

`restorecon` looks up the **expected** context for a path from policy's file-context database (`semanage fcontext -l`) and applies it — it doesn't invent a new label, it restores the canonical one.

```bash
sudo chcon -t httpd_sys_content_t /var/www/html/index.html   # set an explicit context by hand
```

`chcon` sets a context directly and **does not persist across a relabel** — the next `restorecon` run (or full filesystem relabel) reverts it, because `chcon` doesn't update the policy's file-context database, it only touches that one file's extended attribute. For a permanent custom mapping (e.g. serving web content from a non-standard directory), register the rule with `semanage fcontext` instead, then apply it with `restorecon`:

```bash
sudo semanage fcontext -a -t httpd_sys_content_t "/srv/mysite(/.*)?"   # register the rule
sudo restorecon -Rv /srv/mysite                                        # apply it
```

Confirmed real policy rules for `/var/www` on this system, for comparison:

```bash
sudo semanage fcontext -l | grep /var/www
# /var/www(/.*)?                     all files   system_u:object_r:httpd_sys_content_t:s0
# /var/www(/.*)?/logs(/.*)?          all files   system_u:object_r:httpd_log_t:s0
# /var/www/[^/]*/cgi-bin(/.*)?       all files   system_u:object_r:httpd_sys_script_exec_t:s0
```

## Ports

Services can only bind to ports whose SELinux port-type they're allowed to use — this is why moving a service to a nonstandard port (e.g. running `httpd` on 8081 instead of 80/443/8080/etc.) can fail under SELinux even with the firewall and DAC permissions correct:

```bash
sudo semanage port -l | grep ssh
# ssh_port_t    tcp    22
sudo semanage port -l | grep http_port
# http_port_t   tcp    80, 81, 443, 488, 8008, 8009, 8443, 9000
```

To allow a daemon to use a port outside its normal set, add it to the relevant port type instead of disabling SELinux:

```bash
sudo semanage port -a -t http_port_t -p tcp 8081
```

## Booleans — policy on/off switches without writing custom policy

Booleans are pre-defined toggles for common policy variations, so you don't need to write custom policy for well-known cases:

```bash
getsebool -a | wc -l
# 327

getsebool -a | grep httpd | head -3
# httpd_anon_write --> off
# httpd_builtin_scripting --> on
# httpd_can_check_spam --> off
```

```bash
sudo setsebool httpd_can_network_connect on          # runtime only
sudo setsebool -P httpd_can_network_connect on        # -P: persist across reboot
```

`httpd_can_network_connect` is the canonical example — by default `targeted` policy blocks a web server from making outbound network connections (e.g. to a backend database on another host); this boolean is the sanctioned way to allow it, instead of loosening `httpd_t`'s policy generally.

## Diagnosing denials

```bash
sudo ausearch -m avc -ts recent    # recent Access Vector Cache denials from the audit log
sudo audit2why < /var/log/audit/audit.log   # explain a denial in plain English
sudo audit2allow -a                          # generate a custom policy module that WOULD allow the denials seen so far
```

`audit2allow`'s suggested policy is a starting point for investigation, not something to blindly apply — it will happily generate a rule permitting exactly the denied action, which can mean "correctly grants what a legitimate service needs" or "papers over a misconfigured path/context that should have been fixed with `restorecon` instead." Always read what it's proposing before loading it.

```bash
sudo audit2allow -a -M mypolicy   # write a loadable module instead of just printing the rule
sudo semodule -i mypolicy.pp      # load it
```

`sealert` (from `setroubleshoot-server`, if installed) gives a friendlier denial explanation with a suggested fix, pulled from the same audit data:

```bash
sudo sealert -a /var/log/audit/audit.log
```

## Quick reference

| Task | Command |
|---|---|
| Current mode | `getenforce` |
| Full status | `sestatus` |
| Toggle mode (temporary) | `setenforce 0\|1` |
| Persist mode | edit `/etc/selinux/config`, `SELINUX=` |
| Show file/dir context | `ls -Z`, `ls -dZ` |
| Show process context | `ps -eZ` |
| Reset to policy-defined context | `restorecon -Rv PATH` |
| Set a one-off context (non-persistent) | `chcon -t TYPE PATH` |
| Register a permanent context rule | `semanage fcontext -a -t TYPE "PATTERN"` |
| List/allow ports | `semanage port -l`, `semanage port -a -t TYPE -p tcp PORT` |
| List/toggle booleans | `getsebool -a`, `setsebool [-P] NAME on\|off` |
| Investigate a denial | `ausearch -m avc -ts recent`, `audit2why`, `sealert` |

## Practical Recipes

### "It works with SELinux disabled" — the wrong fix, and the right one

Disabling SELinux entirely to make something work is a common shortcut that removes the whole confinement layer system-wide, not just for the one path that was actually broken. Work through it properly instead:

```bash
# 1. Confirm SELinux is actually the blocker (flip to permissive temporarily, don't disable)
sudo setenforce 0
# ...retry the failing action...
# if it now works, SELinux was the cause — flip back before continuing
sudo setenforce 1

# 2. Find the specific denial
sudo ausearch -m avc -ts recent

# 3. Decide: wrong file context (fix with restorecon/semanage fcontext),
#    or a legitimate boolean-gated need (fix with setsebool -P),
#    or genuinely custom (generate + review a module with audit2allow)
```

### Serving web content from a non-default directory

```bash
sudo mkdir -p /srv/mysite
sudo semanage fcontext -a -t httpd_sys_content_t "/srv/mysite(/.*)?"
sudo restorecon -Rv /srv/mysite
# now httpd can read it under targeted policy, same as /var/www/html
```

### A containerized/custom daemon needs to listen on a nonstandard port

```bash
sudo semanage port -l | grep -w 9090   # check if the port already has a type
sudo semanage port -a -t http_port_t -p tcp 9090   # if not, and it's HTTP-like traffic, add it to an appropriate existing type
```
