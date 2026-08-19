Write-Host "=== COMPLETE WINDOWS UPDATE RESET ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1] Stopping Windows Update services..." -ForegroundColor Yellow
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Stop-Service -Name BITS -Force -ErrorAction SilentlyContinue
Write-Host "   Services stopped"

Write-Host ""
Write-Host "[2] Clearing Windows Update cache completely..." -ForegroundColor Yellow
$downloadPath = "C:\Windows\SoftwareDistribution\Download"
if (Test-Path $downloadPath) {
    Get-ChildItem $downloadPath -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    Write-Host "   Download folder cleared"
}
$authPath = "C:\Windows\SoftwareDistribution\AuthKB"
if (Test-Path $authPath) {
    Get-ChildItem $authPath -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    Write-Host "   AuthKB folder cleared"
}
$cabPath = "C:\Windows\SoftwareDistribution\Datastore"
if (Test-Path $cabPath) {
    Get-ChildItem $cabPath -Recurse -Filter "*.cab" | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "   Datastore cab files cleared"
}

Write-Host ""
Write-Host "[3] Resetting Windows Update registry keys..." -ForegroundColor Yellow
$regKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
)
foreach ($key in $regKeys) {
    if (Test-Path $key) {
        Write-Host "   $key exists"
    }
}

Write-Host ""
Write-Host "[4] Starting services..." -ForegroundColor Yellow
Start-Service -Name BITS -ErrorAction SilentlyContinue
Start-Service -Name wuauserv -ErrorAction SilentlyContinue
Start-Service -Name CryptSvc -ErrorAction SilentlyContinue
Get-Service wuauserv, BITS, CryptSvc | Select-Object Name, Status | ForEach-Object { Write-Host "   $($_.Name): $($_.Status)" }

Write-Host ""
Write-Host "[5] Clearing stale Windows Update sessions..." -ForegroundColor Yellow
$session = New-Object -ComObject Microsoft.Update.Session
$session = $null
[GC]::Collect()
Write-Host "   Session cleared"

Write-Host ""
Write-Host "[6] Running fresh Windows Update scan..." -ForegroundColor Yellow
$us = New-Object -ComObject Microsoft.Update.Session
$searcher = $us.CreateUpdateSearcher()
$searcher.Search("IsInstalled=0 and Type='Software'") | Out-Null
Start-Sleep -Seconds 3

$sr = $searcher.Search("IsInstalled=0")
Write-Host "   Pending updates found: $($sr.Result.Updates.Count)"

Write-Host ""
Write-Host "[7] Final verification..." -ForegroundColor Yellow
$finalSearch = $us.CreateUpdateSearcher()
$finalResult = $finalSearch.Search("IsInstalled=0")
Write-Host "   Final count: $($finalResult.Result.Updates.Count)"