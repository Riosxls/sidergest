param(
    [int]$Keep = 14,
    [string]$CopyTo,
    [string]$Reason = 'manual',
    [switch]$Quiet
)

# Dumps the Docker database to backups\ebt-<reason>-<timestamp>.dump (pg_dump custom format), keeps the newest $Keep dumps and
# optionally copies the new one to another disk or share (-CopyTo). Exit code 0 only when the dump exists and is not empty.
# While it runs it writes backup-status\progress.json (percent and stage); the API container mounts that folder read-only and the app shows a
# progress bar from it. pg_dump reports no percentage, so the dump stage compares the growing file with the size of the previous dump.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Dir = Join-Path $Root 'backups'
$StatusDir = Join-Path $Root 'backup-status'
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
New-Item -ItemType Directory -Force -Path $StatusDir | Out-Null

function Say([string]$Message) { if (-not $Quiet) { Write-Host $Message } }

$script:StartedAt = [DateTimeOffset]::UtcNow
$script:Percent = 0
function Set-Progress([int]$Percent, [string]$Stage, [bool]$Running = $true) {
    $script:Percent = $Percent
    try {
        $now = [DateTimeOffset]::UtcNow
        $json = [ordered]@{ running = $Running; percent = $Percent; stage = $Stage; startedAt = $script:StartedAt.ToString('o'); updatedAt = $now.ToString('o') } | ConvertTo-Json
        $tmp = Join-Path $StatusDir 'progress.json.tmp'
        Set-Content -Path $tmp -Value $json -Encoding utf8
        Move-Item -Path $tmp -Destination (Join-Path $StatusDir 'progress.json') -Force
    } catch { }   # progress is a nicety: never fail the backup because of it
}

Push-Location $Root
try {
    Set-Progress 1 'Preparando...'
    $container = (& docker compose ps --status running -q db 2>$null | Select-Object -First 1)
    if (-not $container) { throw 'The db container is not running; nothing to back up.' }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $file = Join-Path $Dir "ebt-$Reason-$stamp.dump"
    $tmp = "/tmp/ebt-$stamp.dump"

    # Expected dump size: the previous dump, else a fraction of the database size.
    $expected = 0
    $statusFile = Join-Path $StatusDir 'status.json'
    if (Test-Path $statusFile) {
        try { $expected = [long](Get-Content $statusFile -Raw | ConvertFrom-Json).lastBackupSizeBytes } catch { $expected = 0 }
    }
    if ($expected -le 0) {
        try { $expected = [long]((& docker exec $container psql -U ebt -d ebt -At -c "select pg_database_size('ebt')") | Select-Object -First 1) / 4 } catch { $expected = 0 }
    }

    # Dump inside the container and copy the file out: PowerShell pipes would re-encode a binary dump.
    Set-Progress 3 'Gravando o banco de dados...'
    $dump = Start-Process -FilePath 'docker' -ArgumentList @('exec', $container, 'pg_dump', '-U', 'ebt', '-d', 'ebt', '-Fc', '-f', $tmp) -NoNewWindow -PassThru
    $null = $dump.Handle   # keeps the process handle so ExitCode is available after it exits
    while (-not $dump.HasExited) {
        Start-Sleep -Milliseconds 700
        if ($expected -gt 0) {
            $size = 0
            try { $size = [long]((& docker exec $container stat -c %s $tmp 2>$null) | Select-Object -First 1) } catch { $size = 0 }
            $ratio = [math]::Min(1.0, $size / $expected)
            Set-Progress ([int](3 + 82 * $ratio)) 'Gravando o banco de dados...'
        }
    }
    $dump.WaitForExit()
    if ($dump.ExitCode -ne 0) { throw 'pg_dump failed.' }

    Set-Progress 86 'Copiando o arquivo...'
    & docker cp "${container}:$tmp" $file
    if ($LASTEXITCODE -ne 0) { throw 'docker cp failed.' }
    & docker exec $container rm -f $tmp | Out-Null

    Set-Progress 90 'Conferindo o arquivo...'
    if (-not (Test-Path $file) -or (Get-Item $file).Length -lt 1024) { throw "Backup file is missing or too small: $file" }
    Say "Backup written: $file ($([math]::Round((Get-Item $file).Length / 1MB, 1)) MB)"

    if ($CopyTo) {
        Set-Progress 92 'Copiando para o destino...'
        New-Item -ItemType Directory -Force -Path $CopyTo | Out-Null
        Copy-Item $file $CopyTo -Force
        Say "Copied to $CopyTo"
    }

    Set-Progress 97 'Limpando cópias antigas...'
    Get-ChildItem $Dir -Filter 'ebt-*.dump' | Sort-Object LastWriteTime -Descending | Select-Object -Skip $Keep | ForEach-Object {
        Remove-Item $_.FullName -Force
        Say "Removed old backup $($_.Name)"
    }
    # The API container mounts only backup-status (never the dumps), so it can report the last backup without being able to read the data.
    $all = @(Get-ChildItem $Dir -Filter 'ebt-*.dump' | Sort-Object LastWriteTime -Descending)
    $status = [ordered]@{ count = $all.Count; lastBackupAt = $null; lastBackupFile = $null; lastBackupSizeBytes = $null }
    if ($all.Count -gt 0) {
        $status.lastBackupAt = $all[0].LastWriteTimeUtc.ToString('o')
        $status.lastBackupFile = $all[0].Name
        $status.lastBackupSizeBytes = $all[0].Length
    }
    $status | ConvertTo-Json | Set-Content -Path $statusFile -Encoding utf8
    Set-Progress 100 'Concluído' $false
    exit 0
} catch {
    Set-Progress $script:Percent 'Falhou' $false
    Write-Host "BACKUP FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
