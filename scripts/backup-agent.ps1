param(
    [switch]$DryRun,
    [switch]$Once,
    [int]$PollSeconds = 4
)

# Runs on the server computer (Task Scheduler starts it at logon and every 5 minutes as a watchdog; it then loops every few seconds so "Fazer backup agora" starts at once; see install-backup-agent.ps1). Reads the backup plan the admin
# set in the app (table backup_settings), runs scripts\backup.ps1 when a backup is due and reports the result back to the table.
# The API container cannot do this itself: it has no Docker access and no pg_dump. Schedule rules mirror
# Ebt.Core/Maintenance/BackupSchedule.cs; keep the two in sync.
$ErrorActionPreference = 'Stop'
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)   # text piped to docker exec psql must be UTF-8, or accents become "?"
$Root = Split-Path -Parent $PSScriptRoot

function Get-NextDue {
    param($Plan, [DateTimeOffset]$Now)
    # Plan: Enabled, Frequency (0 hourly, 1 every 6 hours, 2 daily, 3 weekly), Time (HH:mm), Weekday (0 = Sunday), LastRun, RunRequested (both DateTimeOffset or $null)
    if ($Plan.RunRequested -and (-not $Plan.LastRun -or $Plan.RunRequested -gt $Plan.LastRun)) { return $Now }
    if (-not $Plan.Enabled) { return $null }
    if (-not $Plan.LastRun) { return $Now }
    $last = $Plan.LastRun
    $due = switch ($Plan.Frequency) {
        0 { $last.AddHours(1) }
        1 { $last.AddHours(6) }
        default {
            $h, $m = $Plan.Time -split ':'
            $day = $last.LocalDateTime.Date
            $slot = $null
            for ($i = 0; $i -le 8 -and -not $slot; $i++) {
                $d = $day.AddDays($i)
                if ($Plan.Frequency -eq 3 -and [int]$d.DayOfWeek -ne $Plan.Weekday) { continue }
                $local = $d.AddHours([int]$h).AddMinutes([int]$m)
                $candidate = [DateTimeOffset]::new($local, [TimeZoneInfo]::Local.GetUtcOffset($local))
                if ($candidate -gt $last) { $slot = $candidate }
            }
            $slot
        }
    }
    if ($due -lt $Now) { return $Now }
    return $due
}

function Test-Destination([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }
    return ($Path -match '^[A-Za-z]:[\\/]' -or $Path -match '^\\\\[^\\.?]') -and $Path -notmatch '(^|[\\/])\.\.([\\/]|$)' -and $Path -notmatch '["*?<>|]'
}

function Invoke-Sql([string]$Container, [string]$Sql) {
    $out = $Sql | & docker exec -i $Container psql -U ebt -d ebt -At -F '|' -v ON_ERROR_STOP=1 2>&1
    if ($LASTEXITCODE -ne 0) { throw "psql failed: $out" }
    return $out
}

function Get-Instant($Value) {
    if ([long]$Value -le 0) { return $null }
    return [DateTimeOffset]::FromUnixTimeSeconds([long]$Value)
}

# Appends to backup-status/agent.log (kept under 200 KB) so a dead agent leaves a reason behind. Never throws.
function Write-AgentLog([string]$Text) {
    try {
        $dir = Join-Path $Root 'backup-status'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $path = Join-Path $dir 'agent.log'
        if ((Test-Path $path) -and (Get-Item $path).Length -gt 200KB) { Move-Item $path ($path + '.old') -Force }
        Add-Content -Path $path -Value ("{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PID, $Text) -Encoding utf8
    } catch { }
}

# Writes progress.json the way backup.ps1 does, for the stages only the agent knows about (stopping, stopped).
function Write-AgentProgress([string]$Stage, [bool]$Running) {
    try {
        $dir = Join-Path $Root 'backup-status'
        $path = Join-Path $dir 'progress.json'
        $percent = 0; $started = [DateTimeOffset]::UtcNow.ToString('o')
        if (Test-Path $path) {
            $old = Get-Content $path -Raw | ConvertFrom-Json
            $percent = [int]$old.percent
            if ($old.startedAt) { $started = [string]$old.startedAt }
        }
        $json = [ordered]@{ running = $Running; percent = $percent; stage = $Stage; startedAt = $started; updatedAt = [DateTimeOffset]::UtcNow.ToString('o') } | ConvertTo-Json
        $tmp = Join-Path $dir 'progress.json.tmp'
        Set-Content -Path $tmp -Value $json -Encoding utf8
        Move-Item -Path $tmp -Destination $path -Force
    } catch { }
}

# True when the app asked to stop this run: "Interromper" set cancel_requested_at after the run began, or (for a manual run) the request was withdrawn.
function Test-CancelRequested([string]$Container, [double]$StartedEpoch, [bool]$Manual) {
    try {
        $epoch = $StartedEpoch.ToString([Globalization.CultureInfo]::InvariantCulture)
        $row = Invoke-Sql $Container "select (cancel_requested_at is not null and cancel_requested_at > to_timestamp($epoch)), (run_requested_at is null) from backup_settings where id = 1"
        $f = ($row | Select-Object -First 1) -split '\|'
        return ($f[0] -eq 't') -or ($Manual -and $f[1] -eq 't')
    } catch { return $false }
}

# Stops a running backup: kills backup.ps1 and its children, ends pg_dump inside the container, removes the partial files of this run.
function Stop-Backup($Proc, [string]$Container, [datetime]$StartedAt, [string]$Destination) {
    Write-AgentProgress 'Cancelando...' $true
    & taskkill /PID $Proc.Id /T /F 2>&1 | Out-Null
    try { Invoke-Sql $Container "select pg_terminate_backend(pid) from pg_stat_activity where application_name = 'pg_dump'" | Out-Null } catch { }
    & docker exec $Container sh -c 'rm -f /tmp/ebt-*.dump' 2>&1 | Out-Null
    $dir = Join-Path $Root 'backups'
    Get-ChildItem $dir -Filter 'ebt-*' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $StartedAt.AddSeconds(-2) } | ForEach-Object {
        if ($Destination) { Remove-Item (Join-Path $Destination $_.Name) -Force -ErrorAction SilentlyContinue }
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
    Write-AgentProgress 'Cancelado' $false
}

# Lists the dumps (this computer and the destination) in backup-status/backups.json so the app can offer them for restoring.
function Publish-BackupList([string]$Destination) {
    try {
        $script:LastListed = Get-Date
        $found = @{}
        $scan = @(@{ Folder = (Join-Path $Root 'backups'); Where = 'local' })
        if ($Destination) { $scan += @{ Folder = $Destination; Where = 'destination' } }
        foreach ($s in $scan) {
            if (-not (Test-Path -LiteralPath $s.Folder)) { continue }
            foreach ($f in (Get-ChildItem -LiteralPath $s.Folder -Filter 'ebt-*.dump' -ErrorAction SilentlyContinue)) {
                if (-not (Test-Path -LiteralPath ($f.FullName + '.sha256'))) { continue }   # no checksum file = unfinished run, not offered
                $created = $f.LastWriteTime
                if ($f.Name -match '-(\d{8})-(\d{6})[.]dump$') {
                    try { $created = [datetime]::ParseExact($Matches[1] + $Matches[2], 'yyyyMMddHHmmss', $null) } catch { }
                }
                $entry = if ($found.ContainsKey($f.Name)) { $found[$f.Name] } else { @{ name = $f.Name; sizeBytes = $f.Length; createdAt = ([DateTimeOffset]$created).ToString('o'); locations = @(); hasChecksum = $false } }
                $entry.locations += $s.Where
                if (Test-Path -LiteralPath ($f.FullName + '.sha256')) { $entry.hasChecksum = $true }
                $found[$f.Name] = $entry
            }
        }
        $items = @($found.Values | Sort-Object { $_.createdAt } -Descending | ForEach-Object {
            [ordered]@{ name = $_.name; sizeBytes = $_.sizeBytes; createdAt = $_.createdAt; location = $(if ($_.locations.Count -gt 1) { 'both' } else { $_.locations[0] }); hasChecksum = $_.hasChecksum }
        })
        $json = [ordered]@{ listedAt = [DateTimeOffset]::UtcNow.ToString('o'); items = $items } | ConvertTo-Json -Depth 4
        $dir = Join-Path $Root 'backup-status'
        $tmp = Join-Path $dir 'backups.json.tmp'
        Set-Content -Path $tmp -Value $json -Encoding utf8
        Move-Item -Path $tmp -Destination (Join-Path $dir 'backups.json') -Force
    } catch { Write-AgentLog "list error: $($_.Exception.Message)" }
}

# A restore asked for in the app. The request row is read separately from the plan: the columns may not exist yet (old schema), which must not stop the backups.
function Invoke-RestoreRequest([string]$Container, $Plan) {
    $file = $null
    try { $file = (Invoke-Sql $Container 'select restore_file from backup_settings where id = 1 and restore_requested_at is not null and restore_file is not null' | Select-Object -First 1) } catch { return $false }
    if (-not $file) { return $false }
    $file = "$file".Trim()
    # Taken: the request stays (restore_requested_at) until restore-result.json is newer; the file name is cleared so it cannot run twice.
    try { Invoke-Sql $Container 'update backup_settings set restore_file = null where id = 1' | Out-Null } catch { }
    Write-AgentLog "restore requested: $file"
    $result = Join-Path (Join-Path $Root 'backup-status') 'restore-result.json'
    $path = $null
    if ($file -match '^ebt-[A-Za-z0-9-]+-[0-9]{8}-[0-9]{6}[.]dump$') {
        $local = Join-Path (Join-Path $Root 'backups') $file
        if (Test-Path -LiteralPath $local) { $path = $local }
        elseif ($Plan.Destination -and (Test-Path -LiteralPath (Join-Path $Plan.Destination $file))) { $path = Join-Path $Plan.Destination $file }
    }
    if (-not $path) {
        $json = [ordered]@{ ok = $false; message = 'Arquivo de backup não encontrado. Os dados atuais foram mantidos.'; file = $file; safetyDump = $null; finishedAt = [DateTimeOffset]::UtcNow.ToString('o') } | ConvertTo-Json
        Set-Content -Path $result -Value $json -Encoding utf8
        Write-AgentLog 'restore: file not found'
        return $true
    }
    $env:METAGEST_BACKUP_COPYTO = $Plan.Destination
    $q = [string][char]34
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ($q + (Join-Path $PSScriptRoot 'restore.ps1') + $q), '-DumpPath', ($q + $path + $q)) -PassThru -Wait -WindowStyle Hidden
    Write-AgentLog "restore finished, exit code $($proc.ExitCode)"
    $script:Container = $null
    Publish-BackupList $Plan.Destination
    return $true
}

# A deletion asked for in the app: removes the dump (and its .sha256) from this computer and from the destination, refreshes status.json and the list.
function Invoke-DeleteRequest([string]$Container, $Plan) {
    $file = $null
    try { $file = (Invoke-Sql $Container 'select delete_file from backup_settings where id = 1 and delete_requested_at is not null and delete_file is not null' | Select-Object -First 1) } catch { return $false }
    if (-not $file) { return $false }
    $file = "$file".Trim()
    try { Invoke-Sql $Container 'update backup_settings set delete_file = null where id = 1' | Out-Null } catch { }
    Write-AgentLog "delete requested: $file"
    $ok = $false; $message = ''
    if ($file -notmatch '^ebt-[A-Za-z0-9-]+-[0-9]{8}-[0-9]{6}[.]dump$') {
        $message = 'Nome de arquivo inválido.'
    } else {
        $folders = @((Join-Path $Root 'backups'))
        if ($Plan.Destination) { $folders += $Plan.Destination }
        $removed = 0
        foreach ($f in $folders) {
            $path = Join-Path $f $file
            try {
                if (Test-Path -LiteralPath $path) {
                    Remove-Item -LiteralPath $path -Force
                    Remove-Item -LiteralPath ($path + '.sha256') -Force -ErrorAction SilentlyContinue
                    $removed++
                }
            } catch { $message = "Não foi possível apagar em ${f}: $($_.Exception.Message)" }
        }
        if (-not $message) {
            if ($removed -gt 0) { $ok = $true; $message = 'Backup excluído.' } else { $message = 'O arquivo já não existia.'; $ok = $true }
        }
    }
    # status.json describes the newest dump and the count: recompute it so the app never points at a deleted file.
    try {
        $dir = Join-Path $Root 'backup-status'
        $all = @(Get-ChildItem (Join-Path $Root 'backups') -Filter 'ebt-*.dump' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        $status = [ordered]@{ count = $all.Count; lastBackupAt = $null; lastBackupFile = $null; lastBackupSizeBytes = $null; lastBackupSha256 = $null }
        if ($all.Count -gt 0) {
            $status.lastBackupAt = $all[0].LastWriteTimeUtc.ToString('o'); $status.lastBackupFile = $all[0].Name; $status.lastBackupSizeBytes = $all[0].Length
            $side = $all[0].FullName + '.sha256'
            if (Test-Path -LiteralPath $side) { $status.lastBackupSha256 = ((Get-Content -LiteralPath $side -TotalCount 1) -split '\s+')[0] }
        }
        $status | ConvertTo-Json | Set-Content -Path (Join-Path $dir 'status.json') -Encoding utf8
        $res = [ordered]@{ ok = $ok; message = $message; file = $file; finishedAt = [DateTimeOffset]::UtcNow.ToString('o') } | ConvertTo-Json
        Set-Content -Path (Join-Path $dir 'delete-result.json') -Value $res -Encoding utf8
    } catch { Write-AgentLog "delete bookkeeping error: $($_.Exception.Message)" }
    Write-AgentLog "delete finished ok=${ok}: $message"
    Publish-BackupList $Plan.Destination
    return $true
}

# Restore drill rules (not part of BackupSchedule.cs): due when there is no drill.json, when the last one is 7 days old, or one day after a failed one.
function Test-DrillDue($Last, [DateTimeOffset]$Now) {
    if (-not $Last -or -not $Last.finishedAt) { return $true }
    $age = $Now - [DateTimeOffset]::Parse([string]$Last.finishedAt)
    if ($Last.ok) { return $age.TotalDays -ge 7 }
    return $age.TotalDays -ge 1
}

# Starts scripts\restore-drill.ps1 in the background when the drill is due and the automatic plan is on (so there are dumps to test); one at a time.
function Invoke-DrillIfDue($Plan) {
    if ($script:DrillProc) {
        if (-not $script:DrillProc.HasExited) { return }
        Write-AgentLog "restore drill finished, exit code $($script:DrillProc.ExitCode)"
        $script:DrillProc = $null
    }
    if (-not $Plan.Enabled -or ((Get-Date) - $script:LastDrillCheck).TotalMinutes -lt 10) { return }
    $script:LastDrillCheck = Get-Date
    $last = $null
    $path = Join-Path (Join-Path $Root 'backup-status') 'drill.json'
    if (Test-Path -LiteralPath $path) { try { $last = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { $last = $null } }
    if (-not (Test-DrillDue $last ([DateTimeOffset]::UtcNow))) { return }
    if ($DryRun) { Write-Host 'Restore drill due.'; return }
    Write-AgentLog 'restore drill start'
    $q = [string][char]34
    $script:DrillProc = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ($q + (Join-Path $PSScriptRoot 'restore-drill.ps1') + $q), '-Quiet') -PassThru -WindowStyle Hidden
    $null = $script:DrillProc.Handle   # keeps the handle so ExitCode is available after it exits
}

function Invoke-Agent {
    Push-Location $Root
    try {
        if (-not $script:Container) { $script:Container = (& docker compose ps --status running -q db 2>$null | Select-Object -First 1) }
        $container = $script:Container
        if (-not $container) { return }   # Docker or the database is down: nothing to do, try again in 5 minutes.

        $row = try { Invoke-Sql $container @"
select enabled, frequency, to_char(time_of_day, 'HH24:MI'), weekday, coalesce(destination, ''), keep,
       coalesce(extract(epoch from run_requested_at)::bigint, 0), coalesce(extract(epoch from last_run_at)::bigint, 0)
from backup_settings where id = 1
"@ } catch { $null }
        if (-not $row) { $script:Container = $null; return }   # The API has not migrated the table yet, or the db container was recreated.
        $f = ($row | Select-Object -First 1) -split '\|'
        $plan = [pscustomobject]@{
            Enabled = $f[0] -eq 't'; Frequency = [int]$f[1]; Time = $f[2]; Weekday = [int]$f[3]
            Destination = $f[4]; Keep = [int]$f[5]; RunRequested = Get-Instant $f[6]; LastRun = Get-Instant $f[7]
        }

        if (((Get-Date) - $script:LastBeat).TotalSeconds -ge 60) {
            Invoke-Sql $container 'update backup_settings set agent_seen_at = now() where id = 1' | Out-Null
            $script:LastBeat = Get-Date
        }

        if (Invoke-RestoreRequest $container $plan) { return }
        if (Invoke-DeleteRequest $container $plan) { return }
        if (((Get-Date) - $script:LastListed).TotalMinutes -ge 10) { Publish-BackupList $plan.Destination }
        Invoke-DrillIfDue $plan

        $now = [DateTimeOffset]::UtcNow
        $due = Get-NextDue $plan $now
        if (-not $due -or $due -gt $now) { return }
        $manual = $plan.RunRequested -and (-not $plan.LastRun -or $plan.RunRequested -gt $plan.LastRun)
        if ($DryRun) { Write-Host "Backup due ($(if ($manual) { 'manual' } else { 'scheduled' }))."; return }

        $ok = $false
        if (-not $plan.Destination) {
            $message = 'Defina a pasta de destino do backup.'
        } elseif (-not (Test-Destination $plan.Destination)) {
            $message = 'Destino inválido: use um caminho completo como D:\backups ou \\servidor\pasta.'
        } else {
            $reason = if ($manual) { 'manual' } else { 'scheduled' }
            $quote = [string][char]34
            $args = @('-NoProfile', '-File', ($quote + (Join-Path $PSScriptRoot 'backup.ps1') + $quote), '-Quiet', '-Keep', $plan.Keep, '-Reason', $reason)
            # The destination goes through the environment, not the command line: a path ending in a backslash (D:\) would be mangled by quoting.
            $env:METAGEST_BACKUP_COPYTO = $plan.Destination
            $outFile = Join-Path ([IO.Path]::GetTempPath()) 'metagest-backup-agent.out'
            $errFile = Join-Path ([IO.Path]::GetTempPath()) 'metagest-backup-agent.err'
            Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
            $startedAt = Get-Date
            Write-AgentLog "backup start ($reason)"
            $startedEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0
            $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -PassThru -WindowStyle Hidden -RedirectStandardOutput $outFile -RedirectStandardError $errFile
            $null = $proc.Handle   # keeps the handle so ExitCode is available after it exits
            $cancelled = $false
            while (-not $proc.HasExited) {
                Start-Sleep -Seconds 1
                if (Test-CancelRequested $container $startedEpoch ([bool]$manual)) { $cancelled = $true; break }
            }
            if ($cancelled) {
                Stop-Backup $proc $container $startedAt $plan.Destination
                $message = 'Backup cancelado.'
            } else {
                $proc.WaitForExit()
                $ok = $proc.ExitCode -eq 0
                $output = ((Get-Content $outFile, $errFile -Raw -ErrorAction SilentlyContinue) -join ' ').Trim()
                $message = if ($ok) { if ($plan.Destination) { 'Backup feito e copiado.' } else { 'Backup feito (sem cópia externa).' } } else { $output }
            }
        }
        # Keep the message plain so it can sit inside a SQL literal.
        Write-AgentLog "backup end ok=${ok}: $message"
        Publish-BackupList $plan.Destination
        $safe = ($message -replace '[^\p{L}\p{N} .,:;_()/\\-]', '?')
        if ($safe.Length -gt 480) { $safe = $safe.Substring(0, 480) }
        Invoke-Sql $container "update backup_settings set last_run_at = now(), last_run_ok = $(if ($ok) { 'true' } else { 'false' }), last_run_message = '$($safe -replace "'", "''")' where id = 1" | Out-Null
    } finally {
        Pop-Location
    }
}

# Dot-sourcing (. .\backup-agent.ps1) only loads the functions, which is how they are tested.
if ($MyInvocation.InvocationName -ne '.') {
    $mutex = New-Object Threading.Mutex($false, 'Global\MetaGestBackupAgent')
    if (-not $mutex.WaitOne(0)) { exit 0 }   # a previous run is still dumping
    $script:Container = $null
    Write-AgentLog "agent started"
    $script:LastBeat = [datetime]::MinValue
    $script:LastListed = [datetime]::MinValue
    $script:LastDrillCheck = [datetime]::MinValue
    $script:DrillProc = $null
    try {
        do {
            try { Invoke-Agent } catch { $script:Container = $null; Write-AgentLog "error: $($_.Exception.Message)" }
            if (-not $Once -and -not $DryRun) { Start-Sleep -Seconds $PollSeconds }
        } while (-not $Once -and -not $DryRun)
    } catch { Write-AgentLog "FATAL: $($_.Exception.Message)"; exit 1 } finally { Write-AgentLog "agent exiting"; $mutex.ReleaseMutex() }
}
