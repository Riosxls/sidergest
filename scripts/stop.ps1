param([switch]$Purge, [switch]$Yes)   # -Yes skips the typed confirmation of -Purge (the backup before it always runs)

$ErrorActionPreference = 'Continue'
foreach ($v in "EBT_DB_PASSWORD", "EBT_JWT_KEY", "EBT_ADMIN_PASSWORD") { if (-not (Get-Item "env:$v" -ErrorAction SilentlyContinue)) { Set-Item "env:$v" "unused-for-teardown" } }
$Root = Split-Path -Parent $PSScriptRoot
$RunDir = Join-Path $Root '.run'
$PidFile = Join-Path $RunDir 'api.pid'
$OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows

if (Test-Path $PidFile) {
    $apiPid = [int](Get-Content $PidFile)
    if (Get-Process -Id $apiPid -ErrorAction SilentlyContinue) {
        Write-Host "Stopping local API (pid $apiPid)"
        if ($OnWindows) { & taskkill /PID $apiPid /T /F *> $null } else { & pkill -P $apiPid; Stop-Process -Id $apiPid -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item $PidFile
}

if (Get-Command docker -ErrorAction SilentlyContinue) {
    & docker info *> $null
    if ($LASTEXITCODE -eq 0) {
        Push-Location $Root
        if ($Purge) {
            # -Purge deletes the database for good: dump it first and stop if that fails, then ask for the word.
            if (& docker compose ps --status running -q db 2>$null) {
                Write-Host "Backing up the database before it is deleted"
                & powershell -NoProfile -File (Join-Path $PSScriptRoot 'backup.ps1') -Reason before-purge -Quiet
                if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Host "Backup failed, so nothing was deleted." -ForegroundColor Red; exit 1 }
            } elseif (& docker volume ls -q 2>$null | Select-String -Pattern 'pgdata' -Quiet) {
                Write-Host "The database container is not running, so it cannot be backed up. Start it (start.bat -ApiOnly) and try again." -ForegroundColor Red
                Pop-Location; exit 1
            }
            if (-not $Yes) {
                $answer = Read-Host "This DELETES the database volume. The backup above is in backups. Type DELETE to continue"
                if ($answer -cne 'DELETE') { Pop-Location; Write-Host "Cancelled, nothing was deleted."; exit 1 }
            }
            Write-Host "Removing containers and database volume"
            & docker compose --profile tools down -v
        } else {
            Write-Host "Stopping containers (data kept)"
            & docker compose --profile tools down
        }
        Pop-Location
    }
}

Remove-Item (Join-Path $RunDir 'mode') -ErrorAction SilentlyContinue
Write-Host "Stopped."
