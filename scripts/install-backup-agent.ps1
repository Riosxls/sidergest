param([switch]$Remove)

# Registers (or removes) the Windows scheduled task that runs scripts\backup-agent.ps1 every 5 minutes for the current user.
# Run it once on the server computer. What to back up, where to copy it and how often is set in the app (Configurações > Administração).
$ErrorActionPreference = 'Stop'
$Task = 'MetaGest backup agent'
if ($Remove) {
    & schtasks /Delete /TN $Task /F
    exit $LASTEXITCODE
}
$script = Join-Path $PSScriptRoot 'backup-agent.ps1'
$run = "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
& schtasks /Create /SC MINUTE /MO 5 /TN $Task /TR $run /F
if ($LASTEXITCODE -ne 0) { throw 'schtasks failed.' }
Write-Host "Task '$Task' registered. The app shows 'agente ativo' within 5 minutes."
