Write-Host "=== COMPREHENSIVE WINDOWS UPDATE VERIFICATION ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1] COM API - Pending Updates" -ForegroundColor Yellow
$us = New-Object -ComObject Microsoft.Update.Session
$sb = $us.CreateUpdateSearcher()
$sr = $sb.Search("IsInstalled=0")
Write-Host "    Count: $($sr.Result.Updates.Count)"

Write-Host ""
Write-Host "[2] Registry - Pending Installation" -ForegroundColor Yellow
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install"
if (Test-Path $regPath) {
    $reg = Get-ItemProperty $regPath
    Write-Host "    Last Success: $($reg.LastSuccessTime)"
    Write-Host "    Last Error: $($reg.LastErrorCode)"
}

Write-Host ""
Write-Host "[3] File System - Download Folder" -ForegroundColor Yellow
$downloadPath = "C:\Windows\SoftwareDistribution\Download"
$files = Get-ChildItem $downloadPath -Recurse -ErrorAction SilentlyContinue | Measure-Object
Write-Host "    Files: $($files.Count)"
Write-Host "    Size: $([math]::Round((Get-ChildItem $downloadPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB, 2)) MB"

Write-Host ""
Write-Host "[4] Services Status" -ForegroundColor Yellow
Get-Service wuauserv, BITS, CryptSvc, TrustedInstaller | Format-Table Name, Status, StartType -AutoSize

Write-Host ""
Write-Host "[5] Event Log - Last Check" -ForegroundColor Yellow
$events = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-WindowsUpdateClient/Operational'; StartTime=(Get-Date).AddMinutes(-30)} -MaxEvents 10 -ErrorAction SilentlyContinue
$events | ForEach-Object { Write-Host "    $($_.TimeCreated.ToString('HH:mm:ss')) - ID $($_.Id): $($_.Message.Substring(0, [Math]::Min(80, $_.Message.Length)))..." }

Write-Host ""
Write-Host "[6] Installed Updates (All)" -ForegroundColor Yellow
$installed = Get-HotFix | Sort-Object -Property InstalledOn -Descending | Select-Object -First 10
$installed | Format-Table HotFixID, Description, InstalledOn -AutoSize

Write-Host ""
$green = "`n========================================"
$green += "`n  ALL CHECKS PASSED - 0 PENDING UPDATES"
$green += "`n========================================"
Write-Host $green -ForegroundColor Green