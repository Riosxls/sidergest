param([switch]$Remove)

# Registers (or removes) the Windows scheduled task for scripts/backup-agent.ps1, for the current user.
# The agent is a loop that checks the backup plan every few seconds, so "Fazer backup agora" in the app starts at once. The task starts it at
# logon and every minute as a watchdog (a second copy exits at once because of a mutex). It also runs on battery power and has no time limit.
# What to back up, where to copy it and how often is set in the app (Configurações > Administração).
$ErrorActionPreference = 'Stop'
$Task = 'MetaGest backup agent'
if ($Remove) {
    Unregister-ScheduledTask -TaskName $Task -Confirm:$false
    Write-Host "Task '$Task' removed."
    exit 0
}
$script = Join-Path $PSScriptRoot 'backup-agent.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
$triggers = @(
    (New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME),
    (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 1))
)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Seconds 0)
Register-ScheduledTask -TaskName $Task -Action $action -Trigger $triggers -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $Task
Write-Host "Task '$Task' registered and started. The app shows 'agente ativo' within a minute."
