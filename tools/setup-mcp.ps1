<#
.SYNOPSIS
    Automates the scriptable parts of docs/mcp-setup.md for this vault, on Windows.

.DESCRIPTION
    Safe to re-run at any point — it checks current state before changing anything, and
    never needs a placeholder value typed in by hand (vault path is auto-detected from this
    script's own location; the API key is read directly out of the plugin's data.json).

    What it can't do for you: installing the "Local REST API" Obsidian plugin itself
    (Settings -> Community plugins -> Browse -> "Local REST API" -> Install + Enable) —
    that's a one-time GUI/trust-prompt step. Run this script after that's done.

    Registers the MCP server against http://localhost:27123/. If your organization's
    Claude Code policy requires a specific allowlisted hostname instead of localhost,
    see "Enterprise MCP allowlists" in docs/mcp-setup.md and register manually with
    that hostname instead of running this script's Step 4.

.EXAMPLE
    .\setup-mcp.ps1
#>

param(
    [string]$VaultPath = (Resolve-Path "$PSScriptRoot\..").Path
)

Write-Host "Vault path: $VaultPath"

# --- Step 1: Claude Code present ---
$claudeVersion = & claude --version 2>$null
if (-not $claudeVersion) {
    Write-Error "Claude Code not found on PATH. Install it first: npm install -g @anthropic-ai/claude-code"
    exit 1
}
Write-Host "[Step 1] OK - Claude Code $claudeVersion"

# --- Step 2: plugin installed? (can't be automated past this check - see .DESCRIPTION) ---
$pluginDir = Join-Path $VaultPath ".obsidian\plugins\obsidian-local-rest-api"
$dataFile  = Join-Path $pluginDir "data.json"

if (-not (Test-Path $dataFile)) {
    Write-Error "Local REST API plugin not found at $dataFile. Install it via Obsidian first: Settings -> Community plugins -> Browse -> 'Local REST API' -> Install + Enable. Then re-run this script."
    exit 1
}
Write-Host "[Step 2] OK - plugin installed"

# --- Step 3: enable the plain-HTTP server ---
$dataRaw = Get-Content $dataFile -Raw

if ($dataRaw -match '"enableInsecureServer":\s*false') {
    $dataRaw = $dataRaw -replace '"enableInsecureServer":\s*false', '"enableInsecureServer": true'
    Set-Content -Path $dataFile -Value $dataRaw -Encoding utf8 -NoNewline
    Write-Host "[Step 3] Enabled HTTP server. Restart Obsidian now, then re-run this script to continue."
    exit 0
} elseif ($dataRaw -match '"enableInsecureServer":\s*true') {
    Write-Host "[Step 3] OK - HTTP server already enabled"
} else {
    Write-Error "Could not find 'enableInsecureServer' in $dataFile - plugin config format may have changed. Check it by hand."
    exit 1
}

if ($dataRaw -match '"apiKey":\s*"([^"]+)"') {
    $apiKey = $Matches[1]
} else {
    Write-Error "Could not find 'apiKey' in $dataFile. Open Obsidian with the plugin enabled at least once first."
    exit 1
}

$port = 27123
if ($dataRaw -match '"insecurePort":\s*(\d+)') {
    $port = $Matches[1]
}

# --- Step 4: register the MCP server (remove-then-add, so re-running fixes a bad prior registration) ---
try { claude mcp remove obsidian --scope user 2>$null | Out-Null } catch {}
claude mcp add --transport http obsidian "http://localhost:$port/mcp/" --header "Authorization: Bearer $apiKey" --scope user
Write-Host "[Step 4] OK - registered. Restart your Claude Code session to pick this up."

# --- Step 5: verify the HTTP endpoint answers ---
try {
    $verify = Invoke-WebRequest -Uri "http://localhost:$port/vault/" -Headers @{ Authorization = "Bearer $apiKey" } -UseBasicParsing
    Write-Host "[Step 5] OK - vault endpoint responded HTTP $($verify.StatusCode)"
} catch {
    Write-Error "[Step 5] Vault endpoint did not respond as expected: $_"
    exit 1
}

Write-Host ""
Write-Host "Done. Restart your Claude Code session, then ask it to read 'index.md' to confirm end-to-end."
