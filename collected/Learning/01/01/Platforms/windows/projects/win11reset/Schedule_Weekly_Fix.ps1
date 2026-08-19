#Requires -RunAsAdministrator
# Create a weekly scheduled task to run Silent_QuickFix
# Runs every Sunday at 3 AM

$scriptPath = "$PSScriptRoot\Silent_QuickFix.ps1"

Write-Host "Creating weekly maintenance task..." -ForegroundColor Cyan

$taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

# Every Sunday at 3 AM
$taskTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "3:00AM"

$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false

$taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Remove existing task if present
Unregister-ScheduledTask -TaskName "Weekly_Win11_QuickFix" -Confirm:$false -ErrorAction SilentlyContinue

# Create new task
Register-ScheduledTask -TaskName "Weekly_Win11_QuickFix" -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Principal $taskPrincipal -Description "Weekly Windows 11 maintenance - Quick Fix" | Out-Null

Write-Host "Task created: Weekly_Win11_QuickFix" -ForegroundColor Green
Write-Host "Schedule: Every Sunday at 3:00 AM" -ForegroundColor Gray
Write-Host ""
Write-Host "To manage this task:" -ForegroundColor Yellow
Write-Host "  View: Get-ScheduledTask -TaskName 'Weekly_Win11_QuickFix'"
Write-Host "  Remove: Unregister-ScheduledTask -TaskName 'Weekly_Win11_QuickFix'"
Write-Host ""
pause
