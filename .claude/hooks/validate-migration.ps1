[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

if (-not (Get-Command atlas -ErrorAction SilentlyContinue)) {
    Write-Warning 'Atlas CLI is not installed. Skipping migration validation hook.'
    exit 0
}

& atlas migrate hash --env local
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Warning 'Docker CLI is not installed. Skipping Atlas migration lint.'
    exit 0
}

& docker info 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Warning 'Docker is not available. Skipping Atlas migration lint.'
    exit 0
}

& atlas migrate lint --env local --latest 1
exit $LASTEXITCODE
