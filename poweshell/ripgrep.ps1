$SearchPath = "C:\Versions\nbc3_trunk\Source"
$SearchExt = "cpp", "h", "dfm"

function head {
    param([string]$Path, [int]$N = 10)
    Get-Content $Path -TotalCount $N
}

function tail {
    param([string]$Path, [int]$N = 10, [switch]$Follow)
    Get-Content $Path -Tail $N -Wait:$Follow
}
$SearchPath = "C:\Versions\nbc3_trunk\Source"
$SearchExt = "cpp", "h", "dfm"

function head {
    param([string]$Path, [int]$N = 10)
    Get-Content $Path -TotalCount $N
}

function tail {
    param([string]$Path, [int]$N = 10, [switch]$Follow)
    Get-Content $Path -Tail $N -Wait:$Follow
}

function rgs {
    <#
    .SYNOPSIS
    Wrapper around ripgrep with baked-in defaults for smart-case search and configurable extensions.

    .DESCRIPTION
    Searches file contents using rg, applying smart-case matching (-S) and line numbers (-n) by default.
    Extensions to search are controlled via -Ext (defaults to $SearchExt), and the search root defaults
    to $SearchPath unless overridden with -Path. Optional -Word and -Literal switches map to rg's -w
    and -F flags respectively.

    .PARAMETER Pattern
    The search pattern (regex by default, unless -Literal is specified).

    .PARAMETER Path
    Directory to search. Defaults to $SearchPath.

    .PARAMETER Ext
    One or more file extensions to search, without dots (e.g. cpp, h). Defaults to $SearchExt.

    .PARAMETER Word
    Match whole words only. Maps to rg's -w flag.

    .PARAMETER Literal
    Treat Pattern as a literal string instead of regex. Maps to rg's -F flag.

    .EXAMPLE
    rgs GetCodesc
    Searches $SearchPath for "GetCodesc" across the default extensions in $SearchExt.

    .EXAMPLE
    rgs "vector<int>" -Literal
    Searches for the literal string "vector<int>" without regex interpretation of < and >.

    .EXAMPLE
    rgs Log -Ext cpp,h -Word
    Searches only .cpp and .h files for the whole word "Log" (excludes Logger, Logging, etc.).

    .INPUTS
    None. Pattern, Path, and Ext are passed as parameters, not via the pipeline.

    .OUTPUTS
    System.String. Raw rg output lines (filename, line number, matched line).

    .NOTES
    Requires ripgrep (rg) on PATH. $SearchPath and $SearchExt should be set in the profile before this
    function is dot-sourced.
    #>

    param(
        [Parameter(Mandatory, Position=0)][string]$Pattern,
        [string]$Path = $SearchPath,
        [string[]]$Ext = $SearchExt,
        [switch]$Word,
        [switch]$Literal
    )
    $globs = $Ext | ForEach-Object { "-g", "*.$_" }
    $flags = @("-n", "-S")
    if ($Word)    { $flags += "-w" }
    if ($Literal) { $flags += "-F" }
    rg @flags @globs $Pattern $Path
}