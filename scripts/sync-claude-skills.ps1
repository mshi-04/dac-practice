[CmdletBinding()]
param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repositoryRoot '.agents/skills'
$destinationRoot = Join-Path $repositoryRoot '.claude/skills'
$excludedClaudeSkillNames = @('atlas')

if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "Source skill directory does not exist: $sourceRoot"
}

$sourceSkills = Get-ChildItem -LiteralPath $sourceRoot -Directory | Sort-Object Name
if ($sourceSkills.Count -eq 0) {
    throw "No source skills found in: $sourceRoot"
}

$differences = [System.Collections.Generic.List[string]]::new()
$sourceSkillNames = @($sourceSkills.Name)

if (-not (Test-Path -LiteralPath $destinationRoot -PathType Container)) {
    if ($Check) {
        $differences.Add('Missing Claude Code skill directory: .claude/skills')
    } else {
        New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    }
}

if (Test-Path -LiteralPath $destinationRoot -PathType Container) {
    $generatedSkills = Get-ChildItem -LiteralPath $destinationRoot -Directory | Where-Object {
        $_.Name -notin $excludedClaudeSkillNames
    }

    foreach ($generatedSkill in $generatedSkills) {
        if ($generatedSkill.Name -notin $sourceSkillNames) {
            $message = "Stale generated Claude Code skill: .claude/skills/$($generatedSkill.Name)"
            if ($Check) {
                $differences.Add($message)
            } else {
                Remove-Item -LiteralPath $generatedSkill.FullName -Recurse -Force
            }
        }
    }
}

foreach ($sourceSkill in $sourceSkills) {
    $destinationSkill = Join-Path $destinationRoot $sourceSkill.Name

    if (-not (Test-Path -LiteralPath $destinationSkill -PathType Container)) {
        $differences.Add("Missing Claude Code skill: .claude/skills/$($sourceSkill.Name)")
        if ($Check) {
            continue
        }
    }

    if (-not $Check) {
        if (Test-Path -LiteralPath $destinationSkill) {
            Remove-Item -LiteralPath $destinationSkill -Recurse -Force
        }
        Copy-Item -LiteralPath $sourceSkill.FullName -Destination $destinationRoot -Recurse -Force
        continue
    }

    $sourceFiles = Get-ChildItem -LiteralPath $sourceSkill.FullName -File -Recurse
    $destinationFiles = Get-ChildItem -LiteralPath $destinationSkill -File -Recurse
    $sourceRelativePaths = @($sourceFiles | ForEach-Object { $_.FullName.Substring($sourceSkill.FullName.Length + 1) })
    $destinationRelativePaths = @($destinationFiles | ForEach-Object { $_.FullName.Substring($destinationSkill.Length + 1) })

    foreach ($relativePath in Compare-Object -ReferenceObject $sourceRelativePaths -DifferenceObject $destinationRelativePaths) {
        $differences.Add("File list differs for $($sourceSkill.Name): $($relativePath.InputObject)")
    }

    foreach ($relativePath in $sourceRelativePaths) {
        $sourceFile = Join-Path $sourceSkill.FullName $relativePath
        $destinationFile = Join-Path $destinationSkill $relativePath
        if ((Test-Path -LiteralPath $destinationFile -PathType Leaf) -and
            (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $destinationFile -Algorithm SHA256).Hash) {
            $differences.Add("Content differs for $($sourceSkill.Name): $relativePath")
        }
    }
}

if ($Check) {
    if ($differences.Count -gt 0) {
        $differences | ForEach-Object { Write-Error $_ }
        exit 1
    }

    Write-Output 'Claude Code skills are synchronized with .agents/skills.'
    exit 0
}

Write-Output 'Synchronized .agents/skills to .claude/skills.'
