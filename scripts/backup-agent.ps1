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
    Get-ChildItem $dir -Filter 'ebt-*.dump' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $StartedAt.AddSeconds(-2) } | ForEach-Object {
        if ($Destination) { Remove-Item (Join-Path $Destination $_.Name) -Force -ErrorAction SilentlyContinue }
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
    Write-AgentProgress 'Cancelado' $false
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
            if ($plan.Destination) { $args += @('-CopyTo', ($quote + $plan.Destination + $quote)) }
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
    try {
        do {
            try { Invoke-Agent } catch { $script:Container = $null; Write-AgentLog "error: $($_.Exception.Message)" }
            if (-not $Once -and -not $DryRun) { Start-Sleep -Seconds $PollSeconds }
        } while (-not $Once -and -not $DryRun)
    } catch { Write-AgentLog "FATAL: $($_.Exception.Message)"; exit 1 } finally { Write-AgentLog "agent exiting"; $mutex.ReleaseMutex() }
}
