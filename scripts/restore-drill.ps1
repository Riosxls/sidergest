param(
    [string]$DumpPath,                  # default: the newest verified dump in the backup destination (else in backups\)
    [string]$Container,                 # tests only: the Postgres container (default: the compose db service)
    [string]$StatusDir,                 # tests only: where drill.json goes (default: backup-status)
    [switch]$Quiet
)

# Restore drill: proves a backup can really be restored, without touching the live database.
#   1. picks the newest dump (backup destination first, then backups\), checks its SHA-256 sidecar and pg_restore -l;
#   2. restores it into a throwaway database metagest_drill_<timestamp> inside the db container (same pg_restore approach as restore.ps1);
#   3. compares row counts of the key tables and the migration history with the live database;
#   4. ALWAYS drops the throwaway database (try/finally) and writes backup-status\drill.json
#      { ok, startedAt, finishedAt, dump, counts: { table: { live, drill } }, migrations: { live, drill }, errors: [...] }.
# The live database is only read (counts). Row counts normally differ a little because the dump is older than the live data; that is not an error.
# Errors: restore failed, a key table missing or no users in the restored copy, a migration in the dump that the live database does not know.
# backup-agent.ps1 runs this weekly (daily again after a failed drill); the API shows it in /health/ready and mails when it failed.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if (-not $StatusDir) { $StatusDir = Join-Path $Root 'backup-status' }
New-Item -ItemType Directory -Force -Path $StatusDir | Out-Null

$StartedAt = [DateTimeOffset]::UtcNow
$Errors = New-Object System.Collections.Generic.List[string]
$Counts = [ordered]@{}
$Migrations = [ordered]@{ live = $null; drill = $null }
$DumpName = $null
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$DrillDb = "metagest_drill_$Stamp"
$Remote = "/tmp/metagest-drill-$Stamp.dump"
$DbCreated = $false
$KeyTables = @('users', 'customers', 'products', 'quotes', 'sales_orders', 'production_orders', 'stock_documents', 'fiscal_documents')

function Say([string]$Message) { if (-not $Quiet) { Write-Host $Message } }

function Invoke-Psql([string]$Db, [string]$Sql) {
    # psql prints NOTICEs on stderr; only the exit code decides.
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

function Write-Drill([bool]$Ok) {
    $json = [ordered]@{
        ok = $Ok
        startedAt = $StartedAt.ToString('o')
        finishedAt = [DateTimeOffset]::UtcNow.ToString('o')
        dump = $DumpName
        counts = $Counts
        migrations = $Migrations
        errors = @($Errors)
    } | ConvertTo-Json -Depth 5
    $tmp = Join-Path $StatusDir 'drill.json.tmp'
    Set-Content -Path $tmp -Value $json -Encoding utf8
    Move-Item -Path $tmp -Destination (Join-Path $StatusDir 'drill.json') -Force
}

# Newest dump that has its .sha256 file (a run that did not finish never has one).
function Get-NewestDump([string]$Folder) {
    if (-not $Folder -or -not (Test-Path -LiteralPath $Folder)) { return $null }
    return Get-ChildItem -LiteralPath $Folder -Filter 'ebt-*.dump' -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath ($_.FullName + '.sha256') } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

Push-Location $Root
try {
    $script:C = $Container
    if (-not $script:C) { $script:C = (& docker compose ps --status running -q db 2>$null | Select-Object -First 1) }
    if (-not $script:C) { throw 'The db container is not running.' }

    # 1. Pick and check the dump.
    if (-not $DumpPath) {
        $dest = ''
        try { $dest = Invoke-Psql 'ebt' "select coalesce(destination, '') from backup_settings where id = 1" } catch { }
        $pick = Get-NewestDump $dest
        if (-not $pick) { $pick = Get-NewestDump (Join-Path $Root 'backups') }
        if (-not $pick) { throw 'No verified backup found (destination or backups\).' }
        $DumpPath = $pick.FullName
    }
    if (-not (Test-Path -LiteralPath $DumpPath)) { throw "Dump not found: $DumpPath" }
    $DumpName = Split-Path $DumpPath -Leaf
    Say "Drill with $DumpName"
    $sidecar = $DumpPath + '.sha256'
    if (Test-Path -LiteralPath $sidecar) {
        $expected = ((Get-Content -LiteralPath $sidecar -TotalCount 1) -split '\s+')[0].ToUpperInvariant()
        if ((Get-FileHash -LiteralPath $DumpPath -Algorithm SHA256).Hash.ToUpperInvariant() -ne $expected) { throw 'The dump is corrupt (SHA-256 does not match).' }
    } else { $Errors.Add('The dump has no .sha256 file.') }

    # 2. Restore into the throwaway database.
    & docker cp $DumpPath "$($script:C):$Remote"
    if ($LASTEXITCODE -ne 0) { throw 'Could not copy the dump into the db container.' }
    & docker exec $script:C sh -c "pg_restore -l $Remote > /dev/null"
    if ($LASTEXITCODE -ne 0) { throw 'The file is not a valid PostgreSQL archive (pg_restore -l failed).' }
    Invoke-Psql 'postgres' "create database $DrillDb" | Out-Null
    $DbCreated = $true
    & docker exec $script:C pg_restore -U ebt -d $DrillDb --no-owner $Remote
    if ($LASTEXITCODE -ne 0) { throw 'pg_restore failed to build the throwaway database.' }

    # 3. Compare with the live database.
    foreach ($t in $KeyTables) {
        $liveHas = (Invoke-Psql 'ebt' "select to_regclass('public.$t') is not null") -eq 't'
        $drillHas = (Invoke-Psql $DrillDb "select to_regclass('public.$t') is not null") -eq 't'
        if (-not $drillHas -and -not $liveHas) { continue }   # a table neither side has (older schema): not a finding
        $live = if ($liveHas) { [long](Invoke-Psql 'ebt' "select count(*) from $t") } else { $null }
        $drill = if ($drillHas) { [long](Invoke-Psql $DrillDb "select count(*) from $t") } else { $null }
        $Counts[$t] = [ordered]@{ live = $live; drill = $drill }
        if ($liveHas -and -not $drillHas) { $Errors.Add("Table $t is missing in the restored copy.") }
    }
    if ($Counts.Contains('users') -and -not ($Counts['users'].drill -ge 1)) { $Errors.Add('The restored copy has no users.') }

    $liveMig = @((Invoke-Psql 'ebt' 'select "MigrationId" from "__EFMigrationsHistory" order by 1') -split "`n" | Where-Object { $_ })
    $drillMig = @((Invoke-Psql $DrillDb 'select "MigrationId" from "__EFMigrationsHistory" order by 1') -split "`n" | Where-Object { $_ })
    $Migrations.live = if ($liveMig.Count) { $liveMig[-1] } else { $null }
    $Migrations.drill = if ($drillMig.Count) { $drillMig[-1] } else { $null }
    if ($drillMig.Count -eq 0) { $Errors.Add('The restored copy has no migration history.') }
    $unknown = @($drillMig | Where-Object { $liveMig -notcontains $_ })
    if ($unknown.Count -gt 0) { $Errors.Add("The dump has migrations the live database does not know: $($unknown -join ', ').") }
} catch {
    $Errors.Add($_.Exception.Message)
} finally {
    if ($DbCreated) {
        try {
            Invoke-Psql 'postgres' "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$DrillDb' and pid <> pg_backend_pid()" | Out-Null
            Invoke-Psql 'postgres' "drop database if exists $DrillDb" | Out-Null
        } catch { $Errors.Add("The throwaway database $DrillDb could not be dropped: $($_.Exception.Message)") }
    }
    try { if ($script:C) { & docker exec $script:C rm -f $Remote 2>$null | Out-Null } } catch { }
    Pop-Location
}

$ok = $Errors.Count -eq 0
try { Write-Drill $ok } catch { Write-Host "Could not write drill.json: $($_.Exception.Message)" -ForegroundColor Red }
if ($ok) {
    Say 'Restore drill OK.'
    exit 0
}
Write-Host ("RESTORE DRILL FAILED: " + ($Errors -join ' | ')) -ForegroundColor Red
exit 1
