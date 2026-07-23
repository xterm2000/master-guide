Let's go piece by piece through the full command, then the glob itself, then how it actually matches a real path.

**The command:**
```
rg -lc "ChangeSpotProperties" --iglob "modules/{client,server,idl}/**/*.{cpp,h,idl}"
```

| Piece | Meaning |
|---|---|
| `rg` | invoke ripgrep |
| `-l` | list filenames only (not matching lines) |
| `-c` | show count of matches per file — combined with `-l` this gives `path:count`, which is what you saw in your output |
| `"ChangeSpotProperties"` | the content search term — case-sensitive as typed (no `-i` here) |
| `--iglob` | apply the following glob as a file **path filter**, matched case-insensitively |
| `"modules/{client,server,idl}/**/*.{cpp,h,idl}"` | the glob pattern itself — broken down below |

**The glob, char by char:**

```
modules/{client,server,idl}/**/*.{cpp,h,idl}
```

| Segment | Meaning |
|---|---|
| `modules/` | literal text — path must start with a folder named `modules` (case-insensitive because of `--iglob`, so `Modules` also matches), immediately followed by `/` |
| `{client,server,idl}` | brace expansion — one literal alternative from this list, no wildcards inside it. Expands to three parallel patterns: `client`, `server`, `idl` |
| `/` | literal slash — separates that folder name from what comes next |
| `**` | double-star — matches **zero or more full path segments**, including going through nested subdirectories. This is what lets `Modules/Server/Repository/Sales/...` match even though there are two extra folders (`Repository/Sales`) between `Server` and the file |
| `/` | literal slash before the filename |
| `*` | single-star — matches any characters **within one path segment** (the filename itself, minus extension) — does not cross `/` |
| `.` | literal dot before the extension |
| `{cpp,h,idl}` | brace expansion again — file extension must be one of these three |

**Visually, the glob is really the brace-expansion of 3×3 = 9 concrete patterns, and a file matches if it satisfies any one of the 9:**

```
modules/client/**/*.cpp     modules/server/**/*.cpp     modules/idl/**/*.cpp
modules/client/**/*.h       modules/server/**/*.h       modules/idl/**/*.h
modules/client/**/*.idl     modules/server/**/*.idl     modules/idl/**/*.idl
```

**Mapped onto one of your real matches:**This is a structural/reference question — you want to see how the glob's literal parts map onto a real matched path. A structural diagram fits.The bottom section is the important part for you to internalize going forward: two separate `-g`/`--iglob` flags are OR'd — a file passes if it satisfies *either one alone*. One combined glob string is AND — a file must satisfy the *whole* pattern in one shot. That single fact is what broke your command last time and what the fixed version fixes.