param([switch]$Purge)

$ErrorActionPreference = 'Continue'
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
