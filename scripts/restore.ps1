param(
    [Parameter(Mandatory = $true)][string]$DumpPath,
    [string]$Container,                 # tests only: the Postgres container to restore into (default: the compose db service)
    [string]$Database = 'ebt',
    [string]$StatusDir,                 # tests only: where progress.json and restore-result.json go (default: backup-status)
    [switch]$SkipApi,                   # tests only: do not stop and start the api container
    [switch]$SkipSafetyDump             # tests only: no pre-restore backup
)

# Restores a pg_dump (custom format) over the live database WITHOUT touching it until the new one is proven good:
#   1. check the dump (file, SHA-256 sidecar, pg_restore -l) and take a safety backup of the current data ("before-restore");
#   2. restore into a brand new database (<name>_restore) and sanity-check it;
#   3. stop the api container, rename the live database to <name>_before_restore_<stamp> and the new one to <name>, start the api again.
# Any failure before step 3 leaves the live database exactly as it was. The previous database is kept (only the newest one) so a bad restore can be rolled back.
# Progress goes to progress.json (the app shows it while the api is up) and the outcome to restore-result.json (the api returns it once it is back).
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if (-not $StatusDir) { $StatusDir = Join-Path $Root 'backup-status' }
New-Item -ItemType Directory -Force -Path $StatusDir | Out-Null

$script:StartedAt = [DateTimeOffset]::UtcNow
$script:Percent = 0
$script:ApiStopped = $false
$script:Swapped = $false
$script:SafetyDump = $null

function Set-Progress([int]$Percent, [string]$Stage, [bool]$Running = $true) {
    $script:Percent = $Percent
    try {
        $now = [DateTimeOffset]::UtcNow
        $json = [ordered]@{ running = $Running; percent = $Percent; stage = $Stage; startedAt = $script:StartedAt.ToString('o'); updatedAt = $now.ToString('o') } | ConvertTo-Json
        $tmp = Join-Path $StatusDir 'progress.json.tmp'
        Set-Content -Path $tmp -Value $json -Encoding utf8
        Move-Item -Path $tmp -Destination (Join-Path $StatusDir 'progress.json') -Force
    } catch { }
}

function Write-Result([bool]$Ok, [string]$Message) {
    $json = [ordered]@{ ok = $Ok; message = $Message; file = (Split-Path $DumpPath -Leaf); safetyDump = $script:SafetyDump; finishedAt = [DateTimeOffset]::UtcNow.ToString('o') } | ConvertTo-Json
    $tmp = Join-Path $StatusDir 'restore-result.json.tmp'
    Set-Content -Path $tmp -Value $json -Encoding utf8
    Move-Item -Path $tmp -Destination (Join-Path $StatusDir 'restore-result.json') -Force
}

function Invoke-Psql([string]$Db, [string]$Sql) {
    # psql prints NOTICEs on stderr; with ErrorActionPreference Stop PowerShell would turn them into errors, so only the exit code decides.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & docker exec $script:C psql -U ebt -d $Db -At -v ON_ERROR_STOP=1 -c $Sql 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prev }
    $text = (($out | ForEach-Object { "$_" }) -join "`n").Trim()
    if ($code -ne 0) { throw "psql failed: $text" }
    return (($out | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" }) -join "`n").Trim()
}
Push-Location $Root
try {
    $script:C = $Container
    if (-not $script:C) { $script:C = (& docker compose ps --status running -q db 2>$null | Select-Object -First 1) }
    if (-not $script:C) { throw 'The db container is not running.' }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $newDb = "${Database}_restore"
    $oldDb = "${Database}_before_restore_$stamp"
    $remote = '/tmp/ebt-restore.dump'

    Set-Progress 1 'Conferindo o backup...'
    if (-not (Test-Path -LiteralPath $DumpPath) -or (Get-Item -LiteralPath $DumpPath).Length -lt 1024) { throw 'O arquivo de backup não existe ou está vazio.' }
    $sidecar = $DumpPath + '.sha256'
    if (Test-Path -LiteralPath $sidecar) {
        $expected = ((Get-Content -LiteralPath $sidecar -TotalCount 1) -split '\s+')[0].ToUpperInvariant()
        $actual = (Get-FileHash -LiteralPath $DumpPath -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($expected -ne $actual) { throw 'O arquivo de backup está corrompido (o SHA-256 não confere).' }
    }
    & docker cp $DumpPath "$($script:C):$remote"
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível copiar o backup para o servidor de banco.' }
    & docker exec $script:C sh -c "pg_restore -l $remote > /dev/null"
    if ($LASTEXITCODE -ne 0) { throw 'O arquivo não é um backup válido do PostgreSQL.' }

    if (-not $SkipSafetyDump) {
        Set-Progress 8 'Fazendo backup de segurança dos dados atuais...'
        $before = Get-Date
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'backup.ps1') -Reason before-restore -Quiet | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'O backup de segurança dos dados atuais falhou; nada foi alterado.' }
        $safety = Get-ChildItem (Join-Path $Root 'backups') -Filter 'ebt-before-restore-*.dump' | Where-Object { $_.LastWriteTime -ge $before.AddSeconds(-5) } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($safety) { $script:SafetyDump = $safety.Name }
    }

    Set-Progress 30 'Preparando o banco novo...'
    Invoke-Psql 'postgres' "drop database if exists $newDb" | Out-Null
    Invoke-Psql 'postgres' "create database $newDb" | Out-Null

    Set-Progress 35 'Restaurando os dados...'
    $liveSize = [long](Invoke-Psql 'postgres' "select pg_database_size('$Database')")
    $proc = Start-Process -FilePath 'docker' -ArgumentList @('exec', $script:C, 'pg_restore', '-U', 'ebt', '-d', $newDb, '--no-owner', $remote) -NoNewWindow -PassThru
    $null = $proc.Handle
    while (-not $proc.HasExited) {
        Start-Sleep -Milliseconds 800
        try {
            $size = [long](Invoke-Psql 'postgres' "select pg_database_size('$newDb')")
            $ratio = if ($liveSize -gt 0) { [math]::Min(1.0, $size / $liveSize) } else { 0 }
            Set-Progress ([int](35 + 40 * $ratio)) 'Restaurando os dados...'
        } catch { }
    }
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) { throw 'pg_restore falhou ao montar o banco novo.' }

    Set-Progress 76 'Conferindo o banco restaurado...'
    $tables = [int](Invoke-Psql $newDb "select count(*) from information_schema.tables where table_schema = 'public'")
    if ($tables -lt 5) { throw 'O banco restaurado parece vazio.' }
    $users = [int](Invoke-Psql $newDb 'select count(*) from users')
    if ($users -lt 1) { throw 'O banco restaurado não tem usuários.' }

    if (-not $SkipApi) {
        Set-Progress 80 'Parando o sistema...'
        & docker compose stop api | Out-Null
        $script:ApiStopped = $true
    }

    Set-Progress 85 'Trocando o banco de dados...'
    $kill = "select pg_terminate_backend(pid) from pg_stat_activity where datname in ('$Database', '$newDb') and pid <> pg_backend_pid()"
    Invoke-Psql 'postgres' $kill | Out-Null
    Invoke-Psql 'postgres' "alter database $Database rename to $oldDb" | Out-Null
    try {
        Invoke-Psql 'postgres' "alter database $newDb rename to $Database" | Out-Null
    } catch {
        Invoke-Psql 'postgres' "alter database $oldDb rename to $Database" | Out-Null   # put the live database back
        throw
    }
    $script:Swapped = $true

    # A dump taken while a restore was pending carries the request flag; clear it so the restore never repeats.
    try { Invoke-Psql $Database 'update backup_settings set restore_file = null, restore_requested_at = null where id = 1' | Out-Null } catch { }
    # Keep only the newest previous database.
    $olds = (Invoke-Psql 'postgres' "select datname from pg_database where datname like '${Database}_before_restore_%' order by datname desc offset 1") -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    foreach ($d in $olds) { try { Invoke-Psql 'postgres' "drop database if exists ""$d""" | Out-Null } catch { } }

    if (-not $SkipApi) {
        Set-Progress 92 'Reiniciando o sistema...'
        & docker compose start api | Out-Null
        $script:ApiStopped = $false
        $apiContainer = (& docker compose ps -q api | Select-Object -First 1)
        $healthy = $false
        for ($i = 0; $i -lt 60 -and -not $healthy; $i++) {
            Start-Sleep -Seconds 2
            $state = (& docker inspect -f '{{.State.Health.Status}}' $apiContainer 2>$null)
            if ($state -eq 'healthy') { $healthy = $true }
        }
        if (-not $healthy) { throw 'O banco foi restaurado, mas o sistema não voltou a responder. O banco anterior foi guardado como ' + $oldDb + '.' }
    }

    & docker exec $script:C rm -f $remote | Out-Null
    Set-Progress 100 'Concluído' $false
    Write-Result $true ('Backup restaurado. O banco anterior foi guardado como ' + $oldDb + '.')
    exit 0
} catch {
    $msg = $_.Exception.Message
    try {
        if (-not $script:Swapped) {
            Invoke-Psql 'postgres' "drop database if exists ${Database}_restore" | Out-Null
            $msg = $msg + ' Os dados atuais foram mantidos.'
        }
        & docker exec $script:C rm -f '/tmp/ebt-restore.dump' 2>&1 | Out-Null
    } catch { }
    try { if ($script:ApiStopped -and -not $SkipApi) { & docker compose start api | Out-Null } } catch { }
    Set-Progress $script:Percent 'Falhou' $false
    try { Write-Result $false $msg } catch { }
    Write-Host "RESTORE FAILED: $msg" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}