# Runs PSScriptAnalyzer over every tracked (and new, untracked) .ps1 / .psm1 file, using the settings file beside it.
# Warnings and errors fail the run. Needs the PSScriptAnalyzer module:
#   Install-Module PSScriptAnalyzer -Scope CurrentUser        (or run this script with -Install)
# Run directly: pwsh -NoProfile -File tools/lint-powershell.ps1
param([switch]$Install)

$ErrorActionPreference = 'Stop'
$root = (& git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$settings = Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1'

if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
    if ($Install) {
        Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -Repository PSGallery -AcceptLicense
    } else {
        Write-Error 'PSScriptAnalyzer is not installed. Run: Install-Module PSScriptAnalyzer -Scope CurrentUser (or pass -Install).'
        exit 1
    }
}

$files = & git -C $root ls-files --cached --others --exclude-standard '*.ps1' '*.psm1' |
    Where-Object { $_ -notmatch '^archive/' } | Sort-Object -Unique
$failed = 0
foreach ($f in $files) {
    $path = Join-Path $root $f
    if (-not (Test-Path $path)) { continue }
    $found = Invoke-ScriptAnalyzer -Path $path -Settings $settings -Severity Warning, Error
    if ($found) {
        $failed += @($found).Count
        foreach ($r in $found) { Write-Output ("FAIL {0}:{1} {2}: {3}" -f $f, $r.Line, $r.RuleName, $r.Message) }
    } else {
        Write-Output "ok   $f"
    }
}
if ($failed) { Write-Output "$failed PSScriptAnalyzer finding(s)"; exit 1 }
exit 0
