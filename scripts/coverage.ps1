param(
    [switch]$SkipFlutter,
    [switch]$SkipBackend,
    [double]$BackendMin = 89,
    [double]$BackendBranchMin = 73,
    [double]$FlutterMin = 86
)

# Line-coverage gate. Runs the test suites with coverage and fails when a total drops under its threshold.
# Backend: coverlet (cobertura), generated EF migrations excluded. Flutter: lcov from `flutter test --coverage`.
# Raise the minimums when coverage grows; keep them a couple of points under the measured value.
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$failed = @()

function Check([string]$Name, [double]$Covered, [double]$Total, [double]$Min) {
    $pct = if ($Total -gt 0) { 100.0 * $Covered / $Total } else { 0 }
    $line = '{0}: {1:N1}% ({2}/{3}), minimum {4}%' -f $Name, $pct, $Covered, $Total, $Min
    if ($pct -lt $Min) { $script:failed += $Name; Write-Host "FAILED $line" -ForegroundColor Red }
    else { Write-Host "ok $line" -ForegroundColor Green }
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
    if (-not $env:EBT_TEST_PG) {
        Write-Host 'EBT_TEST_PG is not set and no .env was found in the repo root. Set EBT_TEST_PG (superuser connection string) and retry.' -ForegroundColor Red
        exit 1
    }
    $out = Join-Path ([IO.Path]::GetTempPath()) "metagest-cov-$([guid]::NewGuid().ToString('N'))"
    Write-Host '==> backend coverage' -ForegroundColor Cyan
    Push-Location $Root
    dotnet test Ebt.sln --nologo --collect:'XPlat Code Coverage' --results-directory $out
    if ($LASTEXITCODE -ne 0) { $failed += 'dotnet test' }
    Pop-Location
    $file = Get-ChildItem $out -Recurse -Filter coverage.cobertura.xml -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($file) {
        [xml]$xml = Get-Content $file.FullName
        $cov = 0; $all = 0; $bcov = 0; $ball = 0
        foreach ($cls in $xml.coverage.packages.package.classes.class) {
            if ($cls.filename -match 'Migrations') { continue }
            foreach ($l in $cls.lines.line) {
                $all++; if ([int]$l.hits -gt 0) { $cov++ }
                if ($l.'condition-coverage' -match '\((\d+)/(\d+)\)') { $bcov += [int]$Matches[1]; $ball += [int]$Matches[2] }
            }
        }
        Check 'backend' $cov $all $BackendMin
        Check 'backend branches' $bcov $ball $BackendBranchMin
    } else { $failed += 'backend coverage report'; Write-Host 'No cobertura report found.' -ForegroundColor Red }
    Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not $SkipFlutter) {
    Write-Host '==> flutter coverage' -ForegroundColor Cyan
    Push-Location (Join-Path $Root 'clients/flutter')
    flutter test --coverage
    if ($LASTEXITCODE -ne 0) { $failed += 'flutter test' }
    $lcov = 'coverage/lcov.info'
    if (Test-Path $lcov) {
        $lf = 0; $lh = 0
        foreach ($l in Get-Content $lcov) {
            if ($l.StartsWith('LF:')) { $lf += [int]$l.Substring(3) }
            elseif ($l.StartsWith('LH:')) { $lh += [int]$l.Substring(3) }
        }
        Check 'flutter' $lh $lf $FlutterMin
    } else { $failed += 'flutter coverage report'; Write-Host 'No lcov.info found.' -ForegroundColor Red }
    Pop-Location
    # flutter test rewrites these three tracked plugin files on Windows; restore only them.
    git -C $Root checkout -- clients/flutter/windows/flutter/generated_plugin_registrant.cc clients/flutter/windows/flutter/generated_plugin_registrant.h clients/flutter/windows/flutter/generated_plugins.cmake 2>$null
}

Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host "COVERAGE CHECK FAILED: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host 'Coverage thresholds met.' -ForegroundColor Green
