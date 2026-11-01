param(
    [switch]$DryRun
)

# Runs on the server computer (Task Scheduler, every 5 minutes; see install-backup-agent.ps1). Reads the backup plan the admin
# set in the app (table backup_settings), runs scripts\backup.ps1 when a backup is due and reports the result back to the table.
# The API container cannot do this itself: it has no Docker access and no pg_dump. Schedule rules mirror
# Ebt.Core/Maintenance/BackupSchedule.cs; keep the two in sync.
$ErrorActionPreference = 'Stop'
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

function Invoke-Agent {
    Push-Location $Root
    try {
        $container = (& docker compose ps --status running -q db 2>$null | Select-Object -First 1)
        if (-not $container) { return }   # Docker or the database is down: nothing to do, try again in 5 minutes.

        $row = try { Invoke-Sql $container @"
select enabled, frequency, to_char(time_of_day, 'HH24:MI'), weekday, coalesce(destination, ''), keep,
       coalesce(extract(epoch from run_requested_at)::bigint, 0), coalesce(extract(epoch from last_run_at)::bigint, 0)
from backup_settings where id = 1
"@ } catch { $null }
        if (-not $row) { return }   # The API has not migrated the table yet.
        $f = ($row | Select-Object -First 1) -split '\|'
        $plan = [pscustomobject]@{
            Enabled = $f[0] -eq 't'; Frequency = [int]$f[1]; Time = $f[2]; Weekday = [int]$f[3]
            Destination = $f[4]; Keep = [int]$f[5]; RunRequested = Get-Instant $f[6]; LastRun = Get-Instant $f[7]
        }

        Invoke-Sql $container 'update backup_settings set agent_seen_at = now() where id = 1' | Out-Null

        $now = [DateTimeOffset]::UtcNow
        $due = Get-NextDue $plan $now
        if (-not $due -or $due -gt $now) { return }
        $manual = $plan.RunRequested -and (-not $plan.LastRun -or $plan.RunRequested -gt $plan.LastRun)
        if ($DryRun) { Write-Host "Backup due ($(if ($manual) { 'manual' } else { 'scheduled' }))."; return }

        $ok = $false
        if (-not (Test-Destination $plan.Destination)) {
            $message = 'Destino inválido: use um caminho completo como D:\backups ou \\servidor\pasta.'
        } else {
            $args = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'backup.ps1'), '-Quiet', '-Keep', $plan.Keep, '-Reason', $(if ($manual) { 'manual' } else { 'scheduled' }))
            if ($plan.Destination) { $args += @('-CopyTo', $plan.Destination) }
            $output = (& powershell @args 2>&1 | Out-String).Trim()
            $ok = $LASTEXITCODE -eq 0
            $message = if ($ok) { if ($plan.Destination) { 'Backup feito e copiado.' } else { 'Backup feito (sem cópia externa).' } } else { $output }
        }
        # Keep the message plain so it can sit inside a SQL literal.
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
    try { Invoke-Agent } catch { Write-Host "BACKUP AGENT FAILED: $($_.Exception.Message)" -ForegroundColor Red; exit 1 } finally { $mutex.ReleaseMutex() }
}
