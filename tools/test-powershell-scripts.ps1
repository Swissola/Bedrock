<#
.SYNOPSIS
    Tests for the PowerShell scripts in tools/: setup-mcp.ps1, prepare-wiki-docs.ps1
    and install-claude-config.ps1.

.DESCRIPTION
    Run:  pwsh tools/test-powershell-scripts.ps1      (or Windows PowerShell 5.1: powershell -File ...)

    No Pester: the bash suites are self-contained scripts that print PASS/FAIL lines,
    and these follow the same shape so the repo has one testing style and no module to
    install. Every scenario runs the script under test in a CHILD process of the same
    PowerShell that is running this file, so `exit` codes are real and nothing leaks.

    Nothing real is touched. `claude` is a stub on PATH that records its arguments, the
    vault endpoint is a throwaway HttpListener on a free local port, and every fixture is
    a temp folder removed on exit. The suite is also meant to be run under Windows
    PowerShell 5.1, because that is what most Windows users start the scripts with.

    A check that is expected to fail because of a CONFIRMED defect in a script under test
    uses Expect-Defect: it is reported as KNOWN DEFECT without failing the run, and turns
    into a failure the moment the script is fixed (so the marker gets removed).
#>

$ErrorActionPreference = 'Stop'
# Belt and braces: the installer honours CLAUDE_HOME, so even if a check ever ran it without
# --prefix it would write to this throwaway folder and not to the real ~/.claude.
$env:CLAUDE_HOME = Join-Path ([System.IO.Path]::GetTempPath()) ("bedrock-ps-claude-home-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$script:Pass = 0
$script:Fail = 0
$script:KnownDefects = 0
$script:Cleanup = New-Object System.Collections.ArrayList
$ToolsDir = $PSScriptRoot
$Self = (Get-Process -Id $PID).Path          # the pwsh / powershell running this file
$IsWin = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows

function Assert-Eq($Desc, $Expected, $Actual) {
    if ("$Expected" -ceq "$Actual") { Write-Output "PASS: $Desc"; $script:Pass++ }
    else { Write-Output "FAIL: $Desc (expected [$Expected], got [$Actual])"; $script:Fail++ }
}
function Assert-Has($Desc, $Text, $Needle) {
    Assert-Eq $Desc 'yes' $(if (("$Text").Contains($Needle)) { 'yes' } else { 'no' })
}
function Assert-Lacks($Desc, $Text, $Needle) {
    Assert-Eq $Desc 'no' $(if (("$Text").Contains($Needle)) { 'yes' } else { 'no' })
}
function Expect-Defect($Desc, $Desired, $Actual) {
    if ("$Desired" -ceq "$Actual") {
        Write-Output "FAIL: $Desc is now fixed: change Expect-Defect to Assert-Eq"; $script:Fail++
    } else {
        Write-Output "KNOWN DEFECT: $Desc (wanted [$Desired], got [$Actual])"; $script:KnownDefects++
    }
}
function New-Dir {
    $d = Join-Path ([System.IO.Path]::GetTempPath()) ("bedrock-ps-" + [guid]::NewGuid().ToString('N').Substring(0, 10))
    New-Item -ItemType Directory -Path $d | Out-Null
    [void]$script:Cleanup.Add($d)
    return $d
}
function Remove-Fixtures { foreach ($d in $script:Cleanup) { Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue } }

# Writes text as UTF-8 WITHOUT a BOM, whichever PowerShell is running.
function Write-Utf8([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

# Runs a script in a child PowerShell. -Env sets/overrides environment variables for the
# child only (the current ones are restored afterwards); -PathPrefix is prepended to PATH.
# Returns @{ Code; Out } where Out is stdout and stderr together.
function Invoke-Child([string]$Script, [string[]]$Arguments = @(), [string]$WorkDir = '', [hashtable]$Env = @{}, [string]$PathPrefix = '', [string[]]$PathDrop = @()) {
    $saved = @{}
    foreach ($k in @($Env.Keys) + 'PATH') { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }
    try {
        foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
        $sep = [System.IO.Path]::PathSeparator
        $entries = @($saved['PATH'] -split [regex]::Escape($sep) | Where-Object { $_ })
        foreach ($drop in $PathDrop) {
            $entries = @($entries | Where-Object { -not (Test-Path (Join-Path $_ $drop)) -and -not (Test-Path (Join-Path $_ "$drop.exe")) -and -not (Test-Path (Join-Path $_ "$drop.cmd")) })
        }
        if ($PathPrefix) { $entries = @($PathPrefix) + $entries }
        [Environment]::SetEnvironmentVariable('PATH', ($entries -join $sep))
        $prev = Get-Location
        if ($WorkDir) { Set-Location $WorkDir }
        # Windows PowerShell 5.1 turns a native command's stderr into terminating errors
        # under 'Stop', so relax it for the call: the child's own errors are the data here.
        $eap = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $out = & $Self -NoProfile -NonInteractive -File $Script @Arguments 2>&1 | ForEach-Object { "$_" }
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $eap; Set-Location $prev }
        $joined = ($out -join "`n"); return @{ Code = $code; Out = $joined; Flat = ($joined -replace '\s+', ' ') }
    } finally {
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
}

# --- setup-mcp.ps1 --------------------------------------------------------------

$SetupMcp = Join-Path $ToolsDir 'setup-mcp.ps1'
$ApiKey = 'k3y-FAKE-0123456789abcdef'

# A stub `claude` in a bin dir: logs its arguments, answers --version. Returns the dir.
function New-StubClaude([string]$LogFile) {
    $bin = New-Dir
    if ($IsWin) {
        Write-Utf8 (Join-Path $bin 'claude.cmd') "@echo off`r`necho %*>>`"$LogFile`"`r`nif `"%1`"==`"--version`" echo 9.9.9 (stub)`r`nexit /b 0`r`n"
    } else {
        $p = Join-Path $bin 'claude'
        Write-Utf8 $p "#!/bin/sh`necho `"`$*`" >> `"$LogFile`"`nif [ `"`$1`" = `"--version`" ]; then echo `"9.9.9 (stub)`"; fi`nexit 0`n"
        & chmod +x $p
    }
    return $bin
}

# A vault folder holding the plugin's data.json. -Flag true/false/$null (omit the setting).
function New-PluginVault([string]$Flag, [string]$Port = '', [string]$Key = $ApiKey, [switch]$NoPlugin) {
    $vault = New-Dir
    if ($NoPlugin) { return $vault }
    $dir = Join-Path $vault '.obsidian/plugins/obsidian-local-rest-api'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $lines = @('{', '  "port": 27124,')
    if ($Port) { $lines += "  `"insecurePort`": $Port," }
    if ($Flag) { $lines += "  `"enableInsecureServer`": $Flag," }
    if ($Key) { $lines += "  `"apiKey`": `"$Key`"," }
    $lines += '  "bindingHost": "127.0.0.1"', '}'
    Write-Utf8 (Join-Path $dir 'data.json') (($lines -join "`n") + "`n")
    return $vault
}
function Get-DataFile($Vault) { Join-Path $Vault '.obsidian/plugins/obsidian-local-rest-api/data.json' }

# A local HTTP endpoint answering every request with $Status, recording the
# Authorization header it saw in $AuthFile. Returns the job; -Port is a free port.
function Get-FreePort {
    $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
    return $port
}
function Start-StubEndpoint([int]$Port, [int]$Status, [string]$AuthFile) {
    $job = Start-Job -ScriptBlock {
        param($p, $s, $f)
        $l = New-Object System.Net.HttpListener
        $l.Prefixes.Add("http://localhost:$p/")
        $l.Start()
        while ($true) {
            $c = $l.GetContext()
            [System.IO.File]::AppendAllText($f, "$($c.Request.Headers['Authorization']) $($c.Request.Url.AbsolutePath)`n")
            $c.Response.StatusCode = $s
            $c.Response.Close()
        }
    } -ArgumentList $Port, $Status, $AuthFile
    for ($i = 0; $i -lt 60; $i++) {
        try { $t = New-Object System.Net.Sockets.TcpClient; $t.Connect('127.0.0.1', $Port); $t.Close(); break } catch { Start-Sleep -Milliseconds 100 }
    }
    return $job
}

function Test-SetupMcp {
    # step 1: no claude
    $vault = New-PluginVault 'true'
    $r = Invoke-Child $SetupMcp @('-VaultPath', $vault) -PathPrefix (New-Dir) -PathDrop @('claude')
    Assert-Eq 'setup-mcp.ps1, no claude: exit 1' 1 $r.Code
    Assert-Has 'setup-mcp.ps1, no claude: says how to install it' $r.Flat 'npm install -g @anthropic-ai/claude-code'

    # step 2: no plugin
    $log = Join-Path (New-Dir) 'claude.log'; $bin = New-StubClaude $log
    $vault = New-PluginVault '' -NoPlugin
    $r = Invoke-Child $SetupMcp @('-VaultPath', $vault) -PathPrefix $bin
    Assert-Eq 'setup-mcp.ps1, no plugin: exit 1' 1 $r.Code
    Assert-Has 'setup-mcp.ps1, no plugin: names the missing data.json' $r.Flat 'Local REST API plugin not found'
    Assert-Has 'setup-mcp.ps1, claude present: step 1 shows its version' $r.Flat '[Step 1] OK - Claude Code 9.9.9 (stub)'

    # step 3: server off -> switched on, stop for a restart
    $log = Join-Path (New-Dir) 'claude.log'; $bin = New-StubClaude $log
    $vault = New-PluginVault 'false'
    $r = Invoke-Child $SetupMcp @('-VaultPath', $vault) -PathPrefix $bin
    $data = Get-Content (Get-DataFile $vault) -Raw
    Assert-Eq 'setup-mcp.ps1, server off: exit 0 (a clean stop)' 0 $r.Code
    Assert-Has 'setup-mcp.ps1, server off: tells the user to restart Obsidian' $r.Flat 'Restart Obsidian now'
    Assert-Has 'setup-mcp.ps1, server off: data.json flipped to true' $data '"enableInsecureServer": true'
    Assert-Lacks 'setup-mcp.ps1, server off: no false left behind' $data '"enableInsecureServer": false'
    Assert-Has 'setup-mcp.ps1, server off: other settings preserved' $data '"bindingHost": "127.0.0.1"'
    Assert-Eq 'setup-mcp.ps1, server off: it stops before registering anything' 'no' $(if ((Test-Path $log) -and ((Get-Content $log -Raw) -match 'mcp ')) { 'yes' } else { 'no' })
    $bytes = [System.IO.File]::ReadAllBytes((Get-DataFile $vault))
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    # Regression: under Windows PowerShell 5.1 the script once rewrote data.json with a BOM
    # (Set-Content -Encoding utf8), which a strict JSON.parse rejects. Run this suite under
    # both PowerShell 7 and powershell.exe to cover both.
    Assert-Eq "setup-mcp.ps1 (PowerShell $($PSVersionTable.PSVersion.Major)), server off: data.json is rewritten without a UTF-8 BOM" 'no' $(if ($hasBom) { 'yes' } else { 'no' })

    # Regression: non-ASCII text in data.json must survive the read and the rewrite as UTF-8
    # (Windows PowerShell 5.1's Get-Content reads BOM-less UTF-8 as ANSI and mangles it).
    $vault = New-PluginVault 'false'
    $dataPath = Get-DataFile $vault
    $text = (Get-Content $dataPath -Raw -Encoding UTF8) -replace '"bindingHost": "127.0.0.1"', ('"note": "caf' + [char]0x00E9 + ' ' + [char]0x20AC + '", "bindingHost": "127.0.0.1"')
    Write-Utf8 $dataPath $text
    $r = Invoke-Child $SetupMcp @('-VaultPath', $vault) -PathPrefix $bin
    $after = [System.IO.File]::ReadAllText($dataPath, (New-Object System.Text.UTF8Encoding($false)))
    Assert-Has 'setup-mcp.ps1, server off: non-ASCII text in data.json survives the rewrite' $after ('caf' + [char]0x00E9 + ' ' + [char]0x20AC)
    Assert-Has 'setup-mcp.ps1, server off: ...and the setting was still flipped' $after '"enableInsecureServer": true'

    # step 3: no such setting / step: no key
    $vault = New-PluginVault ''
    $r = Invoke-Child $SetupMcp @('-VaultPath', $vault) -PathPrefix $bin
    Assert-Eq 'setup-mcp.ps1, no enableInsecureServer setting: exit 1' 1 $r.Code
    Assert-Has 'setup-mcp.ps1, no enableInsecureServer setting: says the format may have changed' $r.Flat "Could not find 'enableInsecureServer'"
    $vault = New-PluginVault 'true' -Key ''
    $r = Invoke-Child $SetupMcp @('-VaultPath', $vault) -PathPrefix $bin
    Assert-Eq 'setup-mcp.ps1, no apiKey: exit 1' 1 $r.Code
    Assert-Has 'setup-mcp.ps1, no apiKey: says to open Obsidian once' $r.Flat "Could not find 'apiKey'"

    # steps 4 and 5: register, then probe, with a real local endpoint
    $log = Join-Path (New-Dir) 'claude.log'; $bin = New-StubClaude $log
    $port = Get-FreePort; $auth = Join-Path (New-Dir) 'auth.log'
    $job = Start-StubEndpoint $port 200 $auth
    try {
        $vault = New-PluginVault 'true' "$port"
        $r = Invoke-Child $SetupMcp @('-VaultPath', $vault) -PathPrefix $bin
        $calls = if (Test-Path $log) { @(Get-Content $log) } else { @() }
        Assert-Eq 'setup-mcp.ps1, happy path: exit 0' 0 $r.Code
        Assert-Eq 'setup-mcp.ps1, registration: remove runs first' 'mcp remove obsidian --scope user' $calls[1]
        Assert-Has 'setup-mcp.ps1, registration: add uses http transport, the custom port, user scope' ($calls[2]) "mcp add --transport http obsidian http://localhost:$port/mcp/"
        Assert-Has 'setup-mcp.ps1, registration: add passes the bearer key' ($calls[2]) "Bearer $ApiKey"
        Assert-Has 'setup-mcp.ps1, registration: user scope' ($calls[2]) '--scope user'
        Assert-Has 'setup-mcp.ps1, probe: step 5 reports HTTP 200' $r.Flat '[Step 5] OK - vault endpoint responded HTTP 200'
        Assert-Has 'setup-mcp.ps1, probe: bearer key sent to /vault/' (Get-Content $auth -Raw) "Bearer $ApiKey /vault/"
        Assert-Lacks 'setup-mcp.ps1: the API key is never printed' $r.Flat $ApiKey
    } finally { Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue }

    # step 5: endpoint answers non-200
    $log = Join-Path (New-Dir) 'claude.log'; $bin = New-StubClaude $log
    $port = Get-FreePort; $auth = Join-Path (New-Dir) 'auth.log'
    $job = Start-StubEndpoint $port 401 $auth
    try {
        $vault = New-PluginVault 'true' "$port"
        $r = Invoke-Child $SetupMcp @('-VaultPath', $vault) -PathPrefix $bin
        Assert-Eq 'setup-mcp.ps1, endpoint answers 401: exit 1' 1 $r.Code
        Assert-Has 'setup-mcp.ps1, endpoint answers 401: reports the probe failed' $r.Flat 'Step 5'
        Assert-Lacks 'setup-mcp.ps1, endpoint answers 401: no success line' $r.Flat 'Done.'
    } finally { Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue }

    # default port when the config names none (nothing listens there, so only the registration is checked)
    $log = Join-Path (New-Dir) 'claude.log'; $bin = New-StubClaude $log
    $vault = New-PluginVault 'true'
    $r = Invoke-Child $SetupMcp @('-VaultPath', $vault) -PathPrefix $bin
    $calls = if (Test-Path $log) { @(Get-Content $log) } else { @() }
    Assert-Has 'setup-mcp.ps1, no insecurePort: registers on 27123' ($calls -join "`n") 'http://localhost:27123/mcp/'
}

# --- prepare-wiki-docs.ps1 --------------------------------------------------------

$PrepareWiki = Join-Path $ToolsDir 'prepare-wiki-docs.ps1'

# A working folder with docs and a wiki-publish.json built from $Docs (array of hashtables).
function New-WikiWork($Docs, $Files, [string]$Space = 'TEAMSPACE') {
    $w = New-Dir
    foreach ($name in $Files.Keys) {
        $p = Join-Path $w $name
        New-Item -ItemType Directory -Path (Split-Path $p) -Force | Out-Null
        Write-Utf8 $p $Files[$name]
    }
    $cfg = @{ space = $Space; documents = $Docs } | ConvertTo-Json -Depth 5
    Write-Utf8 (Join-Path $w 'wiki-publish.json') $cfg
    return $w
}
function Get-Staged($Work, $Name) { Get-Content (Join-Path $Work ".wiki-stage/$Name") -Raw }

function Test-PrepareWiki {
    $files = [ordered]@{
        'docs/guide.md'  = "# Real Guide`n`nFirst paragraph.`n`nSecond paragraph.`n"
        'docs/notitle.md' = "Just text, no heading at all.`n"
        'docs/code.md'   = "# Install Guide`n`nRun this:`n`n``````bash`n# install the dependencies`nnpm install`n``````n`nDone.`n"
    }
    $docs = @(
        @{ source = 'docs/guide.md'; title = 'Configured Title'; parent = 'Parent Page' },
        @{ source = 'docs/notitle.md' }
    )
    $w = New-WikiWork $docs $files
    $r = Invoke-Child $PrepareWiki -WorkDir $w
    Assert-Eq 'prepare-wiki-docs.ps1, normal run: exit 0' 0 $r.Code
    Assert-Has 'prepare-wiki-docs.ps1: reports each file prepared' $r.Flat 'Prepared: docs/guide.md'
    Assert-Has 'prepare-wiki-docs.ps1: reports the count' $r.Flat 'Done. 2 file(s) written to .wiki-stage'
    $g = Get-Staged $w 'guide.md'
    Assert-Eq 'prepare-wiki-docs.ps1: output is named after the source file, in .wiki-stage' 'yes' $(if (Test-Path (Join-Path $w '.wiki-stage/guide.md')) { 'yes' } else { 'no' })
    Assert-Has 'prepare-wiki-docs.ps1: starts with a front-matter block' $g "---`nspace: TEAMSPACE`n"
    Assert-Has 'prepare-wiki-docs.ps1: a configured title wins over the heading' $g "title: Configured Title`n"
    Assert-Has 'prepare-wiki-docs.ps1: a configured parent is recorded' $g "parent: Parent Page`n"
    Assert-Lacks 'prepare-wiki-docs.ps1: the H1 is stripped (the wiki title carries it)' $g '# Real Guide'
    Assert-Has 'prepare-wiki-docs.ps1: the body is kept' $g "First paragraph.`n`nSecond paragraph."
    Assert-Has 'prepare-wiki-docs.ps1: body follows the front matter after one blank line' $g "---`n`nFirst paragraph."

    $n = Get-Staged $w 'notitle.md'
    Assert-Has 'prepare-wiki-docs.ps1: no heading and no title: falls back to the file name' $n 'title: notitle'
    Assert-Lacks 'prepare-wiki-docs.ps1: no parent configured: no parent line' $n 'parent:'
    Assert-Has 'prepare-wiki-docs.ps1: a doc without a heading keeps its text' $n 'Just text, no heading at all.'

    # title from the heading when the config gives none
    $w2 = New-WikiWork @(@{ source = 'docs/guide.md' }) $files
    $r = Invoke-Child $PrepareWiki -WorkDir $w2
    Assert-Has 'prepare-wiki-docs.ps1: no configured title: taken from the first H1' (Get-Staged $w2 'guide.md') 'title: Real Guide'

    # a stale output folder is emptied first
    Write-Utf8 (Join-Path $w2 '.wiki-stage/stale.md') 'old'
    $r = Invoke-Child $PrepareWiki -WorkDir $w2
    Assert-Eq 'prepare-wiki-docs.ps1: files left from an earlier run are removed' 'no' $(if (Test-Path (Join-Path $w2 '.wiki-stage/stale.md')) { 'yes' } else { 'no' })

    # a custom config file and output folder
    $custom = New-WikiWork @(@{ source = 'docs/guide.md' }) $files
    Move-Item (Join-Path $custom 'wiki-publish.json') (Join-Path $custom 'other.json')
    $r = Invoke-Child $PrepareWiki @('-ConfigFile', 'other.json', '-OutputDir', 'out') -WorkDir $custom
    Assert-Eq 'prepare-wiki-docs.ps1: -ConfigFile and -OutputDir are honoured' 'yes' $(if (Test-Path (Join-Path $custom 'out/guide.md')) { 'yes' } else { 'no' })

    # errors
    $empty = New-Dir
    $r = Invoke-Child $PrepareWiki -WorkDir $empty
    Assert-Eq 'prepare-wiki-docs.ps1, no config: exit 1' 1 $r.Code
    Assert-Has 'prepare-wiki-docs.ps1, no config: says to copy the example' $r.Flat 'wiki-publish.example.json'
    $w3 = New-WikiWork @(@{ source = 'docs/missing.md' }) $files
    $r = Invoke-Child $PrepareWiki -WorkDir $w3
    Assert-Eq 'prepare-wiki-docs.ps1, missing source: exit 1' 1 $r.Code
    Assert-Has 'prepare-wiki-docs.ps1, missing source: names the file' $r.Flat 'Source file not found: docs/missing.md'

    # Regression: the heading-stripping regex once had no "first only" limit, so it also deleted
    # every line starting "# " in the body, including shell comments inside a fenced code
    # block. Only the leading title is stripped.
    $w4 = New-WikiWork @(@{ source = 'docs/code.md' }) $files
    $r = Invoke-Child $PrepareWiki -WorkDir $w4
    $code = Get-Staged $w4 'code.md'
    Assert-Has 'prepare-wiki-docs.ps1: code fence content survives (command line)' $code 'npm install'
    Assert-Has 'prepare-wiki-docs.ps1: a "# comment" line inside a code fence is kept' $code '# install the dependencies'
    Assert-Lacks 'prepare-wiki-docs.ps1: the title heading is still stripped' $code '# Install Guide'
}

# --- install-claude-config.ps1 -----------------------------------------------------

$InstallPs1 = Join-Path $ToolsDir 'install-claude-config.ps1'

function Test-InstallWrapper {
    if (-not $IsWin) { Write-Host 'SKIP: install-claude-config.ps1 (it looks for Git for Windows bash, so only meaningful on Windows)'; return }
    $r = Invoke-Child $InstallPs1 @('--help')
    Assert-Eq 'install-claude-config.ps1 --help: exit 0 passed through' 0 $r.Code
    Assert-Has 'install-claude-config.ps1 --help: the real installer ran' $r.Flat '--no-skills'
    $r = Invoke-Child $InstallPs1 @('--bogus')
    Assert-Eq 'install-claude-config.ps1, bad option: the installer''s exit 2 is passed through' 2 $r.Code
    $prefix = Join-Path (New-Dir) 'claude'
    $r = Invoke-Child $InstallPs1 @('--check', '--prefix', $prefix)
    Assert-Eq 'install-claude-config.ps1 --check on an empty prefix: exit 1 passed through' 1 $r.Code
    Assert-Eq 'install-claude-config.ps1 --check: nothing created' 'no' $(if (Test-Path $prefix) { 'yes' } else { 'no' })
    $r = Invoke-Child $InstallPs1 @('--dry-run', '--prefix', $prefix)
    Assert-Eq 'install-claude-config.ps1 --dry-run: exit 0' 0 $r.Code
    Assert-Has 'install-claude-config.ps1 --dry-run: arguments reach the installer unchanged' $r.Flat "Install: $prefix"

    # No Git for Windows bash anywhere. ProgramFiles cannot be overridden for a child process
    # (Windows resets it), so run a copy of the wrapper whose candidate paths point nowhere:
    # same code, same error branch, same exit code.
    $copy = Join-Path (New-Dir) 'install-no-bash.ps1'
    Write-Utf8 $copy ((Get-Content $InstallPs1 -Raw) -replace '\\Git\\bin\\bash\.exe', '\NoSuchGit\bash.exe')
    $r = Invoke-Child $copy @('--help')
    # Regression: the wrapper sets $ErrorActionPreference = 'Stop', so its Write-Error used to
    # end the script with exit 1 before the `exit 2` on the next line. Every other usage
    # error from the installer is exit 2, which this branch is meant to match.
    Assert-Eq 'install-claude-config.ps1, no Git bash found: exits 2' 2 $r.Code
    Assert-Has 'install-claude-config.ps1, no Git bash found: says what to install' $r.Flat "Git for Windows' bash.exe was not found"
}

try {
    Test-SetupMcp
    Test-PrepareWiki
    Test-InstallWrapper
} finally {
    Remove-Fixtures
}

Write-Host "--- $script:Pass passed, $script:Fail failed, $script:KnownDefects known defect(s) ---"
if ($script:Fail -gt 0) { exit 1 } else { exit 0 }
