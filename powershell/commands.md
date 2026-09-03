# PowerShell Commands ↔ Aliases ↔ Bash Equivalents

| PS Command | PS Alias | Bash Equiv | Description |
|---|---|---|---|
| ForEach-Object | %, foreach | (loop, e.g. `for x in ...`) | Run a script block for each pipeline object |
| Where-Object | ?, where | `grep` / `[ ]` test / `awk` | Filter pipeline objects by condition |
| Add-Content | ac | `>>` | Append text to a file |
| Add-PSSnapin | asnp | — | Load a legacy PowerShell snap-in |
| Get-Content | cat, gc, type | `cat` | Read file contents |
| Set-Location | cd, chdir, sl | `cd` | Change current directory |
| ConvertFrom-String | cfs | `awk` / `sed` (structured parse) | Parse text into structured objects |
| Clear-Content | clc | `> file` (truncate) | Empty a file's contents, keep the file |
| Clear-Host | clear, cls | `clear` | Clear the terminal screen |
| Clear-History | clhy | `history -c` | Clear session command history |
| Clear-Item | cli | `rm` (item-provider generic) | Clear contents of an item (e.g. registry value) |
| Clear-ItemProperty | clp | — | Clear a specific property's value |
| Clear-Variable | clv | `unset` (value only) | Clear a variable's value, keep the variable |
| Connect-PSSession | cnsn | `ssh` (reattach) | Reconnect to a disconnected remote session |
| Compare-Object | compare, diff | `diff` | Compare two sets of objects/files |
| Copy-Item | copy, cp, cpi | `cp` | Copy files/folders |
| Copy-ItemProperty | cpp | — | Copy a property from one item to another |
| Invoke-WebRequest | curl, iwr, wget | `curl` / `wget` | Make an HTTP request |
| Convert-Path | cvpa | `realpath` | Convert a path to a provider-native full path |
| Disable-PSBreakpoint | dbp | — | Disable a debugger breakpoint |
| Remove-Item | del, erase, rd, ri, rm, rmdir | `rm`, `rmdir` | Delete files/folders |
| Get-ChildItem | dir, gci, ls | `ls` | List directory contents |
| Disconnect-PSSession | dnsn | `disown` (rough) | Disconnect from a remote session, leave it running |
| Enable-PSBreakpoint | ebp | — | Enable a debugger breakpoint |
| Write-Output | echo, write | `echo` | Send objects to the output stream |
| Export-Alias | epal | `alias > file` | Save current aliases to a file |
| Export-Csv | epcsv | — | Write objects to a CSV file |
| Export-PSSession | epsn | — | Save a remote session's commands as a local module |
| Enter-PSSession | etsn | `ssh` | Start an interactive remote session |
| Exit-PSSession | exsn | `exit` (from ssh) | Leave an interactive remote session |
| Format-Custom | fc | — | Format output using a custom view |
| Format-Hex | fhx | `xxd` / `hexdump` | Display file/data as a hex dump |
| Format-List | fl | — | Format output as a property list |
| Format-Table | ft | `column` (loose) | Format output as a table |
| Format-Wide | fw | `ls` (wide mode) | Format output as a wide, multi-column list |
| Get-Alias | gal | `alias` | List defined aliases |
| Get-PSBreakpoint | gbp | — | List debugger breakpoints |
| Get-Clipboard | gcb | `xclip -o` / `pbpaste` | Read clipboard contents |
| Get-Command | gcm | `which` / `type` | Look up a command/cmdlet |
| Get-PSCallStack | gcs | — | Show current debugger/script call stack |
| Get-PSDrive | gdr | `df` / `mount` (loose) | List PowerShell drives (incl. non-filesystem) |
| Get-History | ghy, h, history | `history` | Show session command history |
| Get-Item | gi | `stat` (loose) | Get an item (file, reg key, etc.) |
| Get-ComputerInfo | gin | `uname -a` / `hostnamectl` | Show OS/hardware system info |
| Get-Job | gjb | `jobs` | List background jobs |
| Get-Location | gl, pwd | `pwd` | Show current directory |
| Get-Member | gm | — | Show an object's properties/methods (type introspection) |
| Get-Module | gmo | — | List loaded/available modules |
| Get-ItemProperty | gp | `cat` (for reg-like data) | Get a property value of an item |
| Get-Process | gps, ps | `ps` | List running processes |
| Get-ItemPropertyValue | gpv | — | Get just the value of an item property |
| Group-Object | group | `sort \| uniq -c` | Group objects by a property value |
| Get-PSSession | gsn | — | List active remote sessions |
| Get-PSSnapin | gsnp | — | List loaded snap-ins |
| Get-Service | gsv | `systemctl status` / `service --status-all` | List/query Windows services |
| Get-TimeZone | gtz | `timedatectl` | Show current time zone |
| Get-Unique | gu | `uniq` | Return unique items from a sorted list |
| Get-Variable | gv | — | List session variables |
| Get-WmiObject | gwmi | — | Query WMI (legacy, superseded by CIM) |
| Invoke-Command | icm | `ssh host cmd` | Run a command locally or on remote machines |
| Invoke-Expression | iex | `eval` | Execute a string as code |
| Invoke-History | ihy, r | `!!` / `!n` | Re-run a command from history |
| Invoke-Item | ii | `xdg-open` / `open` | Open an item with its default handler |
| Import-Alias | ipal | `source alias_file` | Load aliases from a file |
| Import-Csv | ipcsv | — | Read a CSV file into objects |
| Import-Module | ipmo | `source` / `import` | Load a PowerShell module |
| Import-PSSession | ipsn | — | Import commands from a remote session |
| Invoke-RestMethod | irm | `curl` (JSON/REST aware) | Call a REST API, auto-parses response |
| powershell_ise.exe | ise | — | Launch the PowerShell ISE editor |
| Invoke-WmiMethod | iwmi | — | Call a method on a WMI object |
| Stop-Process | kill, spps | `kill` | Terminate a process |
| Out-Printer | lp | `lpr` | Send output to a printer |
| mkdir | md | `mkdir` | Create a directory |
| Measure-Object | measure | `wc` | Count/measure/sum pipeline objects |
| Move-Item | mi, move, mv | `mv` | Move/rename files or folders |
| New-PSDrive | mount, ndr | `mount` | Map a new PS drive (filesystem or provider) |
| Move-ItemProperty | mp | — | Move a property between items |
| New-Alias | nal | `alias` | Create a new alias (errors if it exists) |
| New-Item | ni | `touch` / `mkdir` | Create a new file, folder, or item |
| New-Module | nmo | — | Create an in-memory dynamic module |
| New-PSSessionConfigurationFile | npssc | — | Create a session configuration file |
| New-PSSession | nsn | `ssh` (persistent) | Create a persistent remote session |
| New-Variable | nv | `declare` | Create a new variable |
| Out-GridView | ogv | — | Show output in an interactive grid GUI (Windows only) |
| Out-Host | oh | (default stdout) | Send output to the console explicitly |
| Pop-Location | popd | `popd` | Return to a previously pushed directory |
| Push-Location | pushd | `pushd` | Push current directory onto a stack, then move |
| help | man | `man` | Show help for a command |
| Remove-PSBreakpoint | rbp | — | Delete a debugger breakpoint |
| Receive-Job | rcjb | `wait` (loose) | Get results/output from a background job |
| Receive-PSSession | rcsn | — | Get output from a disconnected session |
| Remove-PSDrive | rdr | `umount` | Remove a mapped PS drive |
| Rename-Item | ren, rni | `mv` | Rename a file, folder, or item |
| Remove-Job | rjb | — | Delete a background job |
| Remove-Module | rmo | — | Unload a module from the session |
| Rename-ItemProperty | rnp | — | Rename a property on an item |
| Remove-ItemProperty | rp | — | Delete a property from an item |
| Remove-PSSession | rsn | `exit` (ssh) | Close and delete a remote session |
| Remove-PSSnapin | rsnp | — | Unload a snap-in |
| Resume-Job | rujb | `fg` (loose) | Resume a suspended background job |
| Remove-Variable | rv | `unset` | Delete a variable |
| Resolve-Path | rvpa | `realpath` / `readlink -f` | Resolve a path, including wildcards |
| Remove-WmiObject | rwmi | — | Delete a WMI object instance |
| Start-Job | sajb | `cmd &` | Start a background job |
| Set-Alias | sal | `alias` | Create or overwrite an alias |
| Start-Process | saps, start | (`cmd &` / `nohup`) | Launch a new process |
| Start-Service | sasv | `systemctl start` | Start a Windows service |
| Set-PSBreakpoint | sbp | — | Set a debugger breakpoint |
| Set-Content | sc | `>` (overwrite) | Write/replace a file's content |
| Set-Clipboard | scb | `xclip` / `pbcopy` | Write text to the clipboard |
| Select-Object | select | `cut` / `head` / `tail` (partial) | Select specific properties or a subset of objects |
| Set-Variable | set, sv | `export` / assignment | Set a variable's value |
| Show-Command | shcm | — | Show a GUI form for building a command (Windows only) |
| Set-Item | si | — | Set the value of an item |
| Set-Location | sl | `cd` | (see `cd` above — duplicate alias) |
| Start-Sleep | sleep | `sleep` | Pause execution |
| Select-String | sls | `grep` | Search text using patterns (rg's PS ancestor) |
| Sort-Object | sort | `sort` | Sort pipeline objects |
| Set-ItemProperty | sp | — | Set the value of an item's property |
| Stop-Job | spjb | — | Stop a running background job |
| Stop-Service | spsv | `systemctl stop` | Stop a Windows service |
| Set-TimeZone | stz | `timedatectl set-timezone` | Set the system time zone |
| Suspend-Job | sujb | `Ctrl+Z` (loose) | Suspend a running job (workflow jobs only) |
| Set-WmiInstance | swmi | — | Create/update a WMI class instance |
| Tee-Object | tee | `tee` | Split output to both console/file and pipeline |
| Trace-Command | trcm | `strace` (loose) | Trace internal execution of a command |
| Wait-Job | wjb | `wait` | Block until a background job finishes |

**Note on "—" rows:** several of these (WMI, PSSnapin, breakpoints, PSSessionConfigurationFile) are Windows-management-stack concepts with no real Linux analog — forcing a bash equivalent there would just be misleading, so it's left blank rather than inventing a fake mapping. Same logic applies to `Out-GridView`/`Show-Command`, which are GUI-only and Windows-specific regardless of shell.