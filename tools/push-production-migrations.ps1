param(
    [string]$ProjectRef = "tgeezbwbrovfyjbeykrj"
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

function Invoke-Checked {
    param([string]$Label, [scriptblock]$Command)
    Write-Host "== $Label =="
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is required"
}
if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
    throw "Python launcher py is required"
}
$npx = (Get-Command npx.cmd -ErrorAction SilentlyContinue)
if (-not $npx) {
    throw "npx.cmd is required"
}
$branch = (git branch --show-current).Trim()
if ($branch -ne "main") {
    throw "Production migrations must be deployed from main; current=$branch"
}
if ((git status --porcelain).Length -ne 0) {
    throw "Working tree is not clean. Commit migration and baseline first."
}

Invoke-Checked "Fetch origin/main" { git fetch origin main }
$head = (git rev-parse HEAD).Trim()
$originMain = (git rev-parse origin/main).Trim()
if ($head -ne $originMain) {
    throw "HEAD is not identical to origin/main. Production deploy blocked."
}

Invoke-Checked "Migration integrity" {
    py tools/check_migration_integrity.py
}
Invoke-Checked "Production history pre-check" {
    py tools/production_migration_sync.py --project-ref $ProjectRef
}
Invoke-Checked "Supabase dry-run" {
    & $npx.Source --yes supabase@latest db push --linked --project-ref $ProjectRef --dry-run
}

Invoke-Checked "Supabase Production push" {
    & $npx.Source --yes supabase@latest db push --linked --project-ref $ProjectRef --yes
}

Invoke-Checked "Production history post-check" {
    py tools/production_migration_sync.py --project-ref $ProjectRef
}

Write-Host "PRODUCTION MIGRATION DEPLOY: OK"
