# Windows wrapper for install-claude-config.sh: finds Git for Windows' bash and
# runs the real installer with the same arguments.
#
#   .\tools\install-claude-config.ps1 --vault C:\path\to\vault
#   .\tools\install-claude-config.ps1 --check
#
# Not the WSL bash that Windows puts in System32 (it sees a different filesystem
# and a different home directory), so this looks for Git for Windows explicitly.

$ErrorActionPreference = 'Stop'

# @(...) matters: with a single match PowerShell returns a bare string, and
# $candidates[0] would then be that string's first character.
$candidates = @(@(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
) | Where-Object { $_ -and (Test-Path $_) })

if (-not $candidates) {
    Write-Error "Git for Windows' bash.exe was not found. Install Git for Windows (https://git-scm.com/download/win), or run tools/install-claude-config.sh from another bash."
    exit 2
}

$script = (Join-Path $PSScriptRoot 'install-claude-config.sh') -replace '\\', '/'
& $candidates[0] $script @args
exit $LASTEXITCODE
