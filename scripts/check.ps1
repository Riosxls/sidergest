param(
    [switch]$SkipFlutter,
    [switch]$SkipBackend,
    [switch]$Coverage
)

# Local gate while GitHub CI is off: build, backend tests, Flutter analyze and tests. Run it before every push.
# Backend tests create and drop their own throwaway database on the Docker Postgres (EBT_TEST_PG); the real "ebt" database is never touched.
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$failed = @()

function Run([string]$Name, [scriptblock]$Block) {
    Write-Host "==> $Name" -ForegroundColor Cyan
    & $Block
    if ($LASTEXITCODE -ne 0) { $script:failed += $Name; Write-Host "FAILED: $Name" -ForegroundColor Red }
}

if (-not $SkipBackend) {
    if (-not $env:EBT_TEST_PG) {
        $envFile = Join-Path $Root '.env'
        $port = if ($env:EBT_DB_PORT) { $env:EBT_DB_PORT } else { '25432' }
        if (Test-Path $envFile) {
            $pw = ((Get-Content $envFile | Where-Object { $_ -like 'EBT_DB_PASSWORD=*' }) -replace '^EBT_DB_PASSWORD=', '').Trim()
            $env:EBT_TEST_PG = "Host=localhost;Port=$port;Username=ebt;Password=$pw"
        }
    }
    Push-Location $Root
    Run 'dotnet build' { dotnet build Ebt.sln --nologo -v q }
    if (-not $Coverage) { Run 'dotnet test' { dotnet test Ebt.sln --nologo --no-build } }
    # Known-vulnerable NuGet packages (direct and transitive): a warning, never a failure, because it needs the network and a new advisory should not block a push.
    Write-Host '==> vulnerable packages (warning only)' -ForegroundColor Cyan
    $vuln = @(dotnet list Ebt.sln package --vulnerable --include-transitive 2>&1 | ForEach-Object { "$_" })
    $rows = @($vuln | Where-Object { $_ -match '^\s*>\s' })
    if ($rows.Count -gt 0) {
        Write-Host 'WARNING: vulnerable NuGet packages found:' -ForegroundColor Yellow
        $rows | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    } else { Write-Host 'No vulnerable packages reported.' }
    Pop-Location
}

if (-not $SkipFlutter) {
    Push-Location (Join-Path $Root 'clients/flutter')
    Run 'flutter analyze' { flutter analyze }
    if (-not $Coverage) { Run 'flutter test' { flutter test } }
    Pop-Location
}

if ($Coverage) {
    # Replaces the plain test runs above: same tests, plus the line-coverage thresholds.
    Run 'coverage thresholds' { & (Join-Path $PSScriptRoot 'coverage.ps1') -SkipBackend:$SkipBackend -SkipFlutter:$SkipFlutter }
}

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "CHECK FAILED: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host 'All checks passed.' -ForegroundColor Green
