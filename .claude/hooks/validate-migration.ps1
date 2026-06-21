[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# PostToolUse cannot undo a completed Write. Exit 2 returns validation feedback
# to Claude Code so the next action can address the failure.

if (-not (Get-Command atlas -ErrorAction SilentlyContinue)) {
    Write-Error 'Atlas CLI is not installed. Migration validation hook cannot run.'
    exit 2
}

& atlas migrate hash --env local
if ($LASTEXITCODE -ne 0) {
    exit 2
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error 'Docker CLI is not installed. Atlas migration lint cannot run.'
    exit 2
}

& docker info 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error 'Docker is not available. Atlas migration lint cannot run.'
    exit 2
}

& atlas migrate lint --env local --latest 1
if ($LASTEXITCODE -ne 0) {
    exit 2
}

exit 0
