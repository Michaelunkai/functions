Write-Host "=== Final Windows Update Status ==="
Write-Host "`n1. Checking pending updates (COM API)..."
$us = New-Object -ComObject Microsoft.Update.Session
$sb = $us.CreateUpdateSearcher()
$sr = $sb.Search("IsInstalled=0")
Write-Host "   Pending updates: $($sr.Result.Updates.Count)"
if ($sr.Result.Updates.Count -gt 0) {
    $sr.Result.Updates | ForEach-Object { Write-Host "   - $($_.Title)" }
}

Write-Host "`n2. Checking installed updates (last 5)..."
Get-HotFix | Sort-Object -Property InstalledOn -Descending | Select-Object -First 5 | ForEach-Object { Write-Host "   - $($_.HotFixID) - $($_.InstalledOn)" }

Write-Host "`n3. Checking Windows Update services..."
Get-Service wuauserv, BITS, CryptSvc | Select-Object Name, Status | ForEach-Object { Write-Host "   - $($_.Name): $($_.Status)" }

Write-Host "`n4. Checking SoftwareDistribution folder..."
$downloadPath = "C:\Windows\SoftwareDistribution\Download"
if (Test-Path $downloadPath) {
    $files = Get-ChildItem $downloadPath -Recurse -ErrorAction SilentlyContinue
    Write-Host "   Files in Download folder: $($files.Count)"
} else {
    Write-Host "   Download folder is empty or doesn't exist"
}

Write-Host "`n5. Checking event log summary (last 24 hours)..."
$events = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-WindowsUpdateClient/Operational'; StartTime=(Get-Date).AddHours(-24)} -MaxEvents 50 -ErrorAction SilentlyContinue
$foundCount = ($events | Where-Object { $_.Id -eq 26 }).Count
Write-Host "   'Found updates' events: $foundCount"
$errors = $events | Where-Object { $_.Level -eq 2 }
Write-Host "   Error events: $($errors.Count)"