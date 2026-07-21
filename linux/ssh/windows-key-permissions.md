```powershell
$keyFile = "C:\Users\<username>\.ssh\id_kbadm"

icacls $keyFile /inheritance:r
icacls $keyFile /remove "NT AUTHORITY\Authenticated Users"
icacls $keyFile /remove "BUILTIN\Users"
icacls $keyFile /remove "Everyone"
icacls $keyFile /grant "<username>:F"
```