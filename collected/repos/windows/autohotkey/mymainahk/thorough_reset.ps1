Write-Host "=== THOROUGH WINDOWS UPDATE RESET ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "[Step 1] Stop ALL Windows Update services..." -ForegroundColor Yellow
$services = @("wuauserv", "BITS", "CryptSvc", "TrustedInstaller", "msiserver")
foreach ($svc in $services) {
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    Write-Host "   Stopped: $svc"
}

Write-Host ""
Write-Host "[Step 2] Full cleanup of SoftwareDistribution..." -ForegroundColor Yellow
$folders = @("Download", "DataStore", "AuthKB", "Proxy")
foreach ($folder in $folders) {
    $path = "C:\Windows\SoftwareDistribution\$folder"
    if (Test-Path $path) {
        Get-ChildItem $path -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "   Cleared: $folder"
    }
}

Write-Host ""
Write-Host "[Step 3] Restart Windows Update service..." -ForegroundColor Yellow
Start-Service wuauserv -ErrorAction SilentlyContinue
Start-Service BITS -ErrorAction SilentlyContinue
Start-Service CryptSvc -ErrorAction SilentlyContinue

Write-Host "   Services restarted"
Get-Service wuauserv, BITS, CryptSvc | Select-Object Name, Status | ForEach-Object { Write-Host "   $($_.Name): $($_.Status)" }

Write-Host ""
Write-Host "[Step 4] Force Windows Update to re-scan..." -ForegroundColor Yellow
$us = [Activator]::CreateInstance([Type]::GetTypeFromCLSID("243e5236-2d9d-4f24-9746-1e79c6225e7b"))
$searcher = $us.CreateUpdateSearcher()
$searcher.Search("Type='Software'") | Out-Null

Write-Host "   Scan triggered"

Start-Sleep -Seconds 5

Write-Host ""
Write-Host "[Step 5] Check results..." -ForegroundColor Yellow
$check = $searcher.Search("IsInstalled=0")
Write-Host "   Pending updates: $($check.Result.Updates.Count)"

if ($check.Result.Updates.Count -gt 0) {
    $check.Result.Updates | ForEach-Object {
        Write-Host "   - $($_.Title)"
    }
} else {
    Write-Host "   No pending updates" -ForegroundColor Green
}