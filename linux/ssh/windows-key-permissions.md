# Windows SSH Key Permissions

On Linux, OpenSSH refuses to use a private key if its file permissions allow
group or other access (`chmod 600` is the fix — see the permissions section of
[`linux-commands.md`](../linux-commands.md)). Windows has no `chmod`; permissions
are ACL entries, and by default a file inherits a broad ACL from its parent
folder — typically including entries like `NT AUTHORITY\Authenticated Users` or
`BUILTIN\Users`, i.e. every account that can log into the machine. Win32-OpenSSH
runs the same check as Linux OpenSSH: if the private key's ACL grants access to
anyone beyond the file's owner (and, implicitly, `SYSTEM`/`Administrators`), it
refuses to load the key, usually with an "Bad permissions" / "UNPROTECTED PRIVATE
KEY FILE" error — the same protection `chmod 600` provides, expressed through
ACLs instead of the Unix permission bits.

`icacls` is the command-line tool for editing a file's ACL directly (the GUI
equivalent is the Security tab in file Properties). The commands below strip the
inherited broad-access entries and grant access to one account only:

> Not verified live on a Windows host in this repo (no Windows machine in the
> current environment) — this reflects documented Win32-OpenSSH behavior, not a
> tested transcript. If you hit a mismatch, `icacls $keyFile` (no other args)
> prints the current ACL for comparison.

```powershell
$keyFile = "C:\Users\<username>\.ssh\id_kbadm"

icacls $keyFile /inheritance:r                          # stop inheriting the parent folder's ACL
icacls $keyFile /remove "NT AUTHORITY\Authenticated Users"
icacls $keyFile /remove "BUILTIN\Users"
icacls $keyFile /remove "Everyone"
icacls $keyFile /grant "<username>:F"                    # re-grant full control to just this account
```

- **`/inheritance:r`** — removes (`r`) inherited permission entries from the
  parent folder, so only explicitly-granted entries remain. Without this, the
  broad inherited entries stay even after you `/remove` them by name, because
  they get re-applied from the parent on the next inheritance refresh.
- **`/remove <account>`** — deletes any ACL entry for that account.
- **`/grant <account>:F`** — grants Full control (`F`) to the named account. Use
  the *narrowest* permission that works if `F` feels too broad (`R` for
  read-only, since an SSH client only needs to read the key).

## See Also

- [`ssh-key-distribution.md`](ssh-key-distribution.md) — generating the key this file locks down
- [`acls.md`](../sysadmin/acls.md) — the Linux equivalent (POSIX ACLs), including the mask gotcha that has no Windows analogue
