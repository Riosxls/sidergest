param(
    [int]$Keep = 14,
    [string]$CopyTo,
    [string]$Reason = 'manual',
    [switch]$Quiet
)

# Dumps the Docker database to backups\ebt-<reason>-<timestamp>.dump (pg_dump custom format), keeps the newest $Keep dumps and
# optionally copies the new one to another disk or share (-CopyTo). Exit code 0 only when the dump exists and is not empty.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Dir = Join-Path $Root 'backups'
New-Item -ItemType Directory -Force -Path $Dir | Out-Null

function Say([string]$Message) { if (-not $Quiet) { Write-Host $Message } }

Push-Location $Root
try {
    $container = (& docker compose ps --status running -q db 2>$null | Select-Object -First 1)
    if (-not $container) { throw 'The db container is not running; nothing to back up.' }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $file = Join-Path $Dir "ebt-$Reason-$stamp.dump"
    $tmp = "/tmp/ebt-$stamp.dump"

    # Dump inside the container and copy the file out: PowerShell pipes would re-encode a binary dump.
    & docker exec $container pg_dump -U ebt -d ebt -Fc -f $tmp
    if ($LASTEXITCODE -ne 0) { throw 'pg_dump failed.' }
    & docker cp "${container}:$tmp" $file
    if ($LASTEXITCODE -ne 0) { throw 'docker cp failed.' }
    & docker exec $container rm -f $tmp | Out-Null

    if (-not (Test-Path $file) -or (Get-Item $file).Length -lt 1024) { throw "Backup file is missing or too small: $file" }
    Say "Backup written: $file ($([math]::Round((Get-Item $file).Length / 1MB, 1)) MB)"

    if ($CopyTo) {
        New-Item -ItemType Directory -Force -Path $CopyTo | Out-Null
        Copy-Item $file $CopyTo -Force
        Say "Copied to $CopyTo"
    }

    Get-ChildItem $Dir -Filter 'ebt-*.dump' | Sort-Object LastWriteTime -Descending | Select-Object -Skip $Keep | ForEach-Object {
        Remove-Item $_.FullName -Force
        Say "Removed old backup $($_.Name)"
    }
    # The API container mounts only backup-status (never the dumps), so it can report the last backup without being able to read the data.
    $StatusDir = Join-Path $Root 'backup-status'
    New-Item -ItemType Directory -Force -Path $StatusDir | Out-Null
    $all = @(Get-ChildItem $Dir -Filter 'ebt-*.dump' | Sort-Object LastWriteTime -Descending)
    $status = [ordered]@{ count = $all.Count; lastBackupAt = $null; lastBackupFile = $null; lastBackupSizeBytes = $null }
    if ($all.Count -gt 0) {
        $status.lastBackupAt = $all[0].LastWriteTimeUtc.ToString('o')
        $status.lastBackupFile = $all[0].Name
        $status.lastBackupSizeBytes = $all[0].Length
    }
    $status | ConvertTo-Json | Set-Content -Path (Join-Path $StatusDir 'status.json') -Encoding utf8
    exit 0
} catch {
    Write-Host "BACKUP FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
