param([switch]$Remove)

# Registers (or removes) the Windows scheduled task that runs scripts\backup-agent.ps1 every 5 minutes for the current user.
# Run it once on the server computer. What to back up, where to copy it and how often is set in the app (Configurações > Administração).
# The task also runs on battery power and catches up after sleep, because the server computer may be a laptop.
$ErrorActionPreference = 'Stop'
$Task = 'MetaGest backup agent'
if ($Remove) {
    Unregister-ScheduledTask -TaskName $Task -Confirm:$false
    Write-Host "Task '$Task' removed."
    exit 0
}
$script = Join-Path $PSScriptRoot 'backup-agent.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1)
Register-ScheduledTask -TaskName $Task -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
Write-Host "Task '$Task' registered. The app shows 'agente ativo' within 5 minutes."
