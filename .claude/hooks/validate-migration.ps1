[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
# Preserve explicit exit-code handling for Atlas and Docker even when they write
# diagnostics to stderr.
$PSNativeCommandUseErrorActionPreference = $false

# PostToolUse cannot undo a completed Write. Exit 2 returns validation feedback
# to Claude Code so the next action can address the failure.

if (-not (Get-Command atlas -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine('Atlas CLI is not installed. Migration validation hook cannot run.')
    exit 2
}

& atlas migrate hash --env local
if ($LASTEXITCODE -ne 0) {
    exit 2
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine('Docker CLI is not installed. Atlas migration lint cannot run.')
    exit 2
}

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& docker info *> $null
$dockerInfoExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference

if ($dockerInfoExitCode -ne 0) {
    [Console]::Error.WriteLine('Docker is not available. Atlas migration lint cannot run.')
    exit 2
}

& atlas migrate lint --env local --latest 1
if ($LASTEXITCODE -ne 0) {
    exit 2
}

exit 0
