$events = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-WindowsUpdateClient/Operational'; Id=31; StartTime=(Get-Date).AddHours(-1)} -MaxEvents 5 -ErrorAction SilentlyContinue
foreach ($e in $events) {
    Write-Host "Time: $($e.TimeCreated)"
    Write-Host "Message: $($e.Message)"
    Write-Host "---"
}