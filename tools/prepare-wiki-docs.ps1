<#
.SYNOPSIS
    Stages selected vault docs for publishing to an external wiki, per docs/publishing-to-a-wiki.md.

.DESCRIPTION
    Reads wiki-publish.json (copy wiki-publish.example.json to get started), and for each
    listed document: strips the leading "# Title" heading (the wiki page title already
    carries that), and writes the result into an output folder ready for whatever
    platform-specific publish step your CI job runs next.

    This script only prepares content — it does not talk to any wiki API itself. See
    docs/publishing-to-a-wiki.md for why, and for example CI snippets that call this
    script and then hand its output to your actual publish step.

.EXAMPLE
    .\prepare-wiki-docs.ps1
#>

param(
    [string]$ConfigFile = "wiki-publish.json",
    [string]$OutputDir = ".wiki-stage"
)

if (-not (Test-Path $ConfigFile)) {
    Write-Error "$ConfigFile not found. Copy tools/wiki-publish.example.json to $ConfigFile and edit it first."
    exit 1
}

$config = Get-Content $ConfigFile -Raw | ConvertFrom-Json

if (Test-Path $OutputDir) {
    Remove-Item -Recurse -Force $OutputDir
}
New-Item -ItemType Directory -Force $OutputDir | Out-Null

foreach ($doc in $config.documents) {
    if (-not (Test-Path $doc.source)) {
        Write-Error "Source file not found: $($doc.source)"
        exit 1
    }

    $content = Get-Content $doc.source -Raw -Encoding UTF8

    # Extract title from first h1 heading, or fall back to filename
    $titleMatch = [regex]::Match($content, '(?m)^# (.+)$')
    $title = if ($doc.title) {
        $doc.title
    } elseif ($titleMatch.Success) {
        $titleMatch.Groups[1].Value.Trim()
    } else {
        [System.IO.Path]::GetFileNameWithoutExtension($doc.source)
    }

    # Remove the h1 heading and any immediately following blank line —
    # the wiki page title already carries this.
    $content = $content -replace '(?m)^# .+\r?\n(\r?\n)?', ''

    # Record space/title/parent as simple frontmatter-style metadata for
    # whatever platform-specific publish step runs next to read. Adapt
    # this block's format to whatever your actual publish step expects.
    $metaParts = @("space: $($config.space)", "title: $title")
    if ($doc.parent) {
        $metaParts += "parent: $($doc.parent)"
    }
    $header = "---`n$($metaParts -join "`n")`n---`n`n"
    $content = $header + $content.TrimStart()

    $outputFile = Join-Path $OutputDir ([System.IO.Path]::GetFileName($doc.source))
    Set-Content -Path $outputFile -Value $content -Encoding UTF8 -NoNewline
    Write-Host "Prepared: $($doc.source) -> $outputFile"
}

Write-Host "Done. $($config.documents.Count) file(s) written to $OutputDir"
