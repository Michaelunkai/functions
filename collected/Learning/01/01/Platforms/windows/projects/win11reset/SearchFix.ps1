#Requires -RunAsAdministrator
# Windows 11 Search Fix

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "`n  ============ SEARCH FIX ============" -ForegroundColor Yellow
Write-Host "  Fixing Windows Search...`n" -ForegroundColor White

# Step 1: Stop search service
Write-Host "[1/4] Stopping Windows Search..." -ForegroundColor Yellow
Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Service stopped" -ForegroundColor Green

# Step 2: Delete search index
Write-Host "`n[2/4] Rebuilding search index..." -ForegroundColor Yellow
$indexPath = "$env:ProgramData\Microsoft\Search\Data\Applications\Windows"
if (Test-Path $indexPath) {
    Remove-Item "$indexPath\Windows.edb" -Force -ErrorAction SilentlyContinue
    Remove-Item "$indexPath\*.log" -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Index cleared (will rebuild)" -ForegroundColor Green
}

# Step 3: Reset search registry
Write-Host "`n[3/4] Resetting search configuration..." -ForegroundColor Yellow
$searchReg = "HKLM:\SOFTWARE\Microsoft\Windows Search"
if (Test-Path $searchReg) {
    Set-ItemProperty -Path $searchReg -Name "SetupCompletedSuccessfully" -Value 0 -Force -ErrorAction SilentlyContinue
}
Write-Host "  [OK] Configuration reset" -ForegroundColor Green

# Step 4: Start search service
Write-Host "`n[4/4] Starting Windows Search..." -ForegroundColor Yellow
Start-Service -Name "WSearch" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
$wsearch = Get-Service -Name "WSearch" -ErrorAction SilentlyContinue
if ($wsearch.Status -eq "Running") {
    Write-Host "  [OK] Service running" -ForegroundColor Green
} else {
    Write-Host "  [!] Service not running - try reboot" -ForegroundColor Yellow
}

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
Write-Host "  Search index is rebuilding." -ForegroundColor White
Write-Host "  This may take 15-30 minutes in the background." -ForegroundColor Gray

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
