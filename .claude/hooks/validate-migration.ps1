[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

if (-not (Get-Command atlas -ErrorAction SilentlyContinue)) {
    Write-Error 'Atlas CLI is not installed. Migration validation hook cannot run.'
    exit 1
}

& atlas migrate hash --env local
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error 'Docker CLI is not installed. Atlas migration lint cannot run.'
    exit 1
}

& docker info 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error 'Docker is not available. Atlas migration lint cannot run.'
    exit 1
}

& atlas migrate lint --env local --latest 1
exit $LASTEXITCODE
