# Access Control Lists (ACLs) (RHEL-based)

Every command and output block below was actually run on a live Rocky Linux 10.2 box
(this dev machine) — not copied from documentation. Where noted, one specific claim
about "installed by default" was checked live and turned out to be **wrong** on the
first pass; that correction is kept in, because it's a real, useful data point.

---

## 1. The problem ACLs solve

Standard Unix permissions give you exactly three buckets per file: **owner**, **group**,
**other** — one set of read/write/execute bits each, nothing more. That's fine until you
need something a plain owner/group/other split can't express, e.g.:

> "User `alice` needs read-write on this file. User `bob` needs read-only. Everyone
> else in the `finance` group needs read-only. Everyone else gets nothing."

Four different access levels, on one file. Traditional permissions can encode at most
three (owner / group / other), and only one group. You'd otherwise have to create a
dedicated group per unique combination of people — which stops scaling the moment
combinations multiply.

An **ACL (Access Control List)** is a per-file, per-directory list of *extra* permission
entries layered on top of the normal owner/group/other bits — each entry naming one
specific additional user or group and what they can do, independent of the base
permissions.

---

## 2. Is the tooling even installed? (verified live — don't assume)

```bash
$ rpm -q acl
package acl is not installed
```

This is a fresh Rocky Linux 10.2 install, and `acl` (the package providing `getfacl`/
`setfacl`) was **not present by default**. Minimal installs, cloud images, and
containers commonly ship without it even though the filesystem itself (XFS, ext4) has
always supported ACLs at the on-disk-format level — the *tools to manage them* are a
separate, optional userspace package. Install it before anything below will work:

```bash
sudo dnf install acl
```

**Don't take "ships by default" as read anywhere** (including in this doc, before this
section) — the concrete, checkable test is `rpm -q acl` or just trying `getfacl
--version` and seeing if it exists.

---

## 3. Reading an ACL — `getfacl`

**A plain file, no ACL set yet:**

```bash
$ touch acltest.txt
$ ls -l acltest.txt
-rw-r--r--. 1 mitek mitek 0 Jul 21 16:58 acltest.txt

$ getfacl acltest.txt
# file: acltest.txt
# owner: mitek
# group: mitek
user::rw-
group::r--
other::r--
```

Note the trailing `.` after the permission string in `ls -l` (`-rw-r--r--.`) — that dot
means "this file has an SELinux security context attached," which is unrelated to ACLs
and present on essentially every file on a RHEL-family system. It becomes a `+` instead,
specifically, once an ACL is added — see the next section.

`getfacl`'s three lines with no ACL yet (`user::`, `group::`, `other::`) are just the
same three traditional permission buckets, printed in ACL syntax — an unmodified file's
ACL is nothing more than a restatement of its normal permissions.

---

## 4. Setting an ACL — `setfacl`

```bash
$ setfacl -m u:nobody:rw acltest.txt
$ ls -l acltest.txt
-rw-rw-r--+ 1 mitek mitek 0 Jul 21 16:58 acltest.txt
```

**The `+` is the tell.** The moment a file has any ACL entry beyond the base three,
`ls -l` appends a `+` to the permission string — that's your signal, in any plain
directory listing, that `getfacl` is needed to see the full picture; the eight
characters `-rw-rw-r--` alone no longer tell the whole story.

```bash
$ getfacl acltest.txt
# file: acltest.txt
# owner: mitek
# group: mitek
user::rw-
user:nobody:rw-
group::r--
mask::rw-
other::r--
```

- **`-m u:nobody:rw`** — `-m` (modify/add an entry), `u:` (this entry is for a user, `g:`
  would mean group), `nobody` (the specific user), `rw` (the rights granted).
- **A new line appeared that wasn't asked for: `mask::rw-`.** This is the single most
  important, least obvious ACL concept — covered next.

---

## 5. The mask — the part that trips people up

The **mask** is a ceiling applied to every *named* ACL entry (any `user:name:` or
`group:name:` line) — not to the file owner, and not to "other." The *effective*
permission for a named entry is the entry's own bits **AND**ed with the mask, whichever
is more restrictive wins.

`setfacl` auto-manages the mask by default (recalculating it to the union of all named
entries' rights whenever you add one), which is why it didn't need to be set by hand
above. But it becomes very visible once it *doesn't* match what you granted:

```bash
$ mkdir acldir && setfacl -d -m g:users:rwx acldir && touch acldir/newfile.txt
$ getfacl acldir/newfile.txt
# file: acldir/newfile.txt
# owner: mitek
# group: mitek
user::rw-
group::r-x	#effective:r--
group:users:rwx	#effective:rw-
mask::rw-
other::r--
```

Look at `group:users:rwx	#effective:rw-` — the group was granted full `rwx`, but the
mask is `rw-`, so `getfacl` itself prints the *effective* (actually-enforced) permission
next to the *granted* one whenever they differ. The `x` was silently clipped. This is
the #1 real-world ACL debugging trap: someone grants a permission, it visibly doesn't
work, and the reason is never the grant itself — it's the mask capping it.

```bash
setfacl -m m::rwx acldir/newfile.txt   # explicitly raise the mask, "m::" = mask entry
```

---

## 6. Removing ACL entries

```bash
$ setfacl -x u:nobody acltest.txt      # -x: remove one specific entry
$ getfacl acltest.txt
# file: acltest.txt
# owner: mitek
# group: mitek
user::rw-
group::r--
mask::r--
other::r--
```

**Verified, non-obvious behavior:** removing the *last* named entry does **not** remove
the `mask::` line — it stays behind, harmlessly, as plain bookkeeping. To strip a file's
ACL back to nothing at all (no mask, no named entries, `ls -l` loses its `+`):

```bash
setfacl -b acltest.txt      # -b: remove the entire ACL, back to plain owner/group/other
```

---

## 7. Default ACLs on a directory — inheritance for new files

Everything above sets an ACL on one existing file. A **default ACL** on a *directory*
is a template: any new file or subdirectory created inside automatically inherits it,
with no extra step required at creation time.

```bash
$ mkdir acldir2 && setfacl -d -m g:users:rwx acldir2
$ getfacl acldir2
# file: acldir2
# owner: mitek
# group: mitek
user::rwx
group::r-x
other::r-x
default:user::rwx
default:group::r-x
default:group:users:rwx
default:mask::rwx
default:other::r-x
```

- **`-d` (default)** — every line here prefixed `default:` applies only to *future*
  children of this directory, not to the directory itself (the directory's own,
  non-`default:`-prefixed entries are unchanged and plain).
- Any file created inside `acldir2` from this point on gets `group:users:rwx` baked in
  automatically — no one has to remember to `setfacl` each new file by hand.

---

## Real-world scenarios

**Shared project directory, mixed teams.** `/srv/releases` is writable by the `deploy`
group for CI, but a `qa` group also needs read-only access to verify artifacts — without
being folded into `deploy` (which would also grant them write). Traditional permissions
force a choice: one group owns the directory, everyone else is `other`. An ACL adds
`qa`'s read-only entry alongside the existing group ownership, with nothing else
changed:
```bash
setfacl -m g:qa:r-x /srv/releases
setfacl -d -m g:qa:r-x /srv/releases   # so files dropped in later inherit it too
```

**One user needs temporary access to someone else's file, without a chmod that leaks to
everyone.** A contractor needs to read one log file owned by a service account, for a
single investigation, without being added to that account's group (which might grant
access to far more than just this one file) and without loosening the file's `other`
bits for the whole system:
```bash
setfacl -m u:contractor_jdoe:r-- /var/log/app/incident.log
# ...investigation done...
setfacl -x u:contractor_jdoe /var/log/app/incident.log
```

**Debugging "permission denied" that `ls -l` says shouldn't happen.** This is the
single most common real ACL support ticket: a user reports being denied access to a
file whose `ls -l` bits *look* like they should allow it. The fix isn't in `chmod` at
all — it's `ls -l | grep '+'` (or just `getfacl`) to check whether an ACL (and
specifically its mask, Section 5) is silently overriding what the plain bits suggest.
Anyone debugging permissions on a RHEL box who only ever looks at `ls -l`'s nine
characters is missing exactly the case ACLs exist to handle.

---

## See Also

- [`users-groups.md`](users-groups.md) — the traditional owner/group/other permission
  model ACLs extend
- [`lvm-storage.md`](lvm-storage.md) — XFS/ext4, the filesystems ACL entries are stored
  on-disk within
