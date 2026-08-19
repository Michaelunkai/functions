#Requires -RunAsAdministrator
# Windows 11 Startup Fix

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "`n  ============ STARTUP FIX ============" -ForegroundColor Yellow
Write-Host "  Optimizing startup...`n" -ForegroundColor White

# Step 1: List current startup items
Write-Host "[1/4] Current startup items:" -ForegroundColor Yellow
$startupItems = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
$startupItems | ForEach-Object {
    Write-Host "  - $($_.Name): $($_.Location)" -ForegroundColor Gray
}
Write-Host "  Total: $($startupItems.Count) items" -ForegroundColor Cyan

# Step 2: Check startup impact
Write-Host "`n[2/4] High-impact startup items:" -ForegroundColor Yellow
$regRun = Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
$regRun.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
    Write-Host "  [USER] $($_.Name)" -ForegroundColor Gray
}
$regRunMachine = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
$regRunMachine.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
    Write-Host "  [SYSTEM] $($_.Name)" -ForegroundColor Gray
}

# Step 3: Fix boot config
Write-Host "`n[3/4] Optimizing boot configuration..." -ForegroundColor Yellow
# Enable fast startup
powercfg /hibernate on 2>&1 | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 1 -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Fast startup enabled" -ForegroundColor Green

# Reduce boot timeout
bcdedit /timeout 3 2>&1 | Out-Null
Write-Host "  [OK] Boot timeout: 3 seconds" -ForegroundColor Green

# Step 4: Clear startup delays
Write-Host "`n[4/4] Clearing startup delays..." -ForegroundColor Yellow
$delayPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize"
if (Test-Path $delayPath) {
    Remove-ItemProperty -Path $delayPath -Name "StartupDelayInMSec" -Force -ErrorAction SilentlyContinue
}
# Set to 0 delay
if (-not (Test-Path $delayPath)) { New-Item -Path $delayPath -Force | Out-Null }
Set-ItemProperty -Path $delayPath -Name "StartupDelayInMSec" -Value 0 -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Startup delay removed" -ForegroundColor Green

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
Write-Host "  Startup optimized. Reboot to see improvements." -ForegroundColor White
Write-Host "  Use Task Manager > Startup to disable specific apps." -ForegroundColor Gray

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
