$events = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-WindowsUpdateClient/Operational'; StartTime=(Get-Date).AddDays(-1)} -MaxEvents 100 -ErrorAction SilentlyContinue
$errors = $events | Where-Object { $_.Level -eq 2 -or $_.LevelDisplayName -eq 'Error' }
Write-Host "Errors found: $($errors.Count)"
if ($errors.Count -gt 0) {
    $errors | Select-Object TimeCreated, Id, Message | Format-List
} else {
    Write-Host "No errors in Windows Update log"
}