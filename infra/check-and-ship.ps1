<#
.SYNOPSIS
    Verifies the workspace, then commits and pushes it.

.DESCRIPTION
    Everything that has to pass before this goes on a remote, in the order that
    fails fastest: backend suite, analyzer, mobile suite. The first failure stops
    the run, because a commit built on a red suite is worse than no commit.

    Each step echoes its command first, so a failure in the output is traceable
    to the line that caused it.

.EXAMPLE
    .\infra\check-and-ship.ps1
    .\infra\check-and-ship.ps1 -WhatIf      # run the checks, change nothing
#>
[CmdletBinding()]
param(
    [Alias('WhatIf')]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Invoke-Step {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string[]]$Command
    )

    Write-Host ''
    Write-Host "==> $Name" -ForegroundColor Cyan
    Write-Host "   $($Command -join ' ')" -ForegroundColor DarkGray

    Push-Location (Join-Path $root $WorkDir)
    try {
        & $Command[0] $Command[1..($Command.Count - 1)]
        if ($LASTEXITCODE -ne 0) {
            throw "$Name failed with exit code $LASTEXITCODE. Nothing was committed."
        }
    }
    finally {
        Pop-Location
    }
    Write-Host "   ok" -ForegroundColor Green
}

$python = Join-Path $root 'backend\.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    throw "Backend virtualenv not found at $python."
}

Invoke-Step -Name 'Backend tests' -WorkDir 'backend' `
    -Command @($python, '-m', 'pytest', 'tests', '-q')

Invoke-Step -Name 'Flutter analyze' -WorkDir 'apps\mobile' `
    -Command @('flutter', 'analyze')

Invoke-Step -Name 'Flutter tests' -WorkDir 'apps\mobile' `
    -Command @('flutter', 'test')

if ($DryRun) {
    Write-Host ''
    Write-Host 'Dry run: checks passed, stopping before git.' -ForegroundColor Yellow
    return
}

# ---------------------------------------------------------------------- git

Write-Host ''
Write-Host '==> Staging' -ForegroundColor Cyan
Push-Location $root
try {
    & git add -A
    if ($LASTEXITCODE -ne 0) { throw "git add failed with exit code $LASTEXITCODE." }

    # Shown before committing, not after: a secret that got staged is still
    # recoverable, and .gitignore is not proof on its own.
    $staged = & git diff --cached --name-only
    if ($LASTEXITCODE -ne 0) { throw 'git diff --cached failed.' }
    if (-not $staged) {
        Write-Host '   nothing staged, working tree already clean.' -ForegroundColor Yellow
        return
    }

    Write-Host '   staged files:' -ForegroundColor DarkGray
    foreach ($file in $staged) { Write-Host "     $file" -ForegroundColor DarkGray }

    & git commit -m 'Add Arabic address search, coverage zones, and a LAN demo build'
    if ($LASTEXITCODE -ne 0) { throw "git commit failed with exit code $LASTEXITCODE." }

    & git push
    if ($LASTEXITCODE -ne 0) {
        throw "git push failed with exit code $LASTEXITCODE. The commit is local; re-run after fixing connectivity."
    }

    Write-Host ''
    Write-Host '   pushed.' -ForegroundColor Green
    Write-Host ''
    Write-Host '   Next: .\infra\demo.ps1   (builds the APK and serves the API)' -ForegroundColor Yellow
}
finally {
    Pop-Location
}