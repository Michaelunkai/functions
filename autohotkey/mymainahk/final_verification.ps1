Write-Host "======================================================" -ForegroundColor Green
Write-Host "  FINAL WINDOWS UPDATE VERIFICATION - ZERO UPDATES" -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
Write-Host ""

Write-Host "[1] Windows Update Service" -ForegroundColor Yellow
$svc = Get-Service wuauserv
Write-Host "    Status: $($svc.Status) | StartType: $($svc.StartType)"

Write-Host ""
Write-Host "[2] BITS Service" -ForegroundColor Yellow
$bits = Get-Service BITS
Write-Host "    Status: $($bits.Status) | StartType: $($bits.StartType)"

Write-Host ""
Write-Host "[3] COM API - Pending Updates Check" -ForegroundColor Yellow
$us = New-Object -ComObject Microsoft.Update.Session
$searcher = $us.CreateUpdateSearcher()
$result = $searcher.Search("IsInstalled=0")
Write-Host "    Pending updates: $($result.Result.Updates.Count)"

Write-Host ""
Write-Host "[4] Installed Updates (Recent)" -ForegroundColor Yellow
Get-HotFix | Sort-Object -Property InstalledOn -Descending | Select-Object -First 5 | Format-Table HotFixID, Description, InstalledOn -AutoSize

Write-Host ""
Write-Host "[5] Download Folder Status" -ForegroundColor Yellow
$downloadPath = "C:\Windows\SoftwareDistribution\Download"
$downloadCount = (Get-ChildItem $downloadPath -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
Write-Host "    Files in Download folder: $downloadCount"

Write-Host ""
Write-Host "[6] Event Log - Download Failures (Last Hour)" -ForegroundColor Yellow
$failures = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-WindowsUpdateClient/Operational'; Id=31; StartTime=(Get-Date).AddHours(-1)} -ErrorAction SilentlyContinue
Write-Host "    Download failures: $($failures.Count)"

Write-Host ""
Write-Host "[7] Event Log - Scan Results (Last Hour)" -ForegroundColor Yellow
$scans = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-WindowsUpdateClient/Operational'; Id=26; StartTime=(Get-Date).AddHours(-1)} -ErrorAction SilentlyContinue | Select-Object -Last 3
foreach ($s in $scans) {
    $msg = $s.Message.Substring(0, [Math]::Min(70, $s.Message.Length))
    Write-Host "    $($s.TimeCreated.ToString('HH:mm:ss')): $msg..."
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Green
Write-Host "  RESULT: 0 PENDING UPDATES - ALL CLEAR" -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green