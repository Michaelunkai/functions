#Requires -RunAsAdministrator
# Windows 11 Taskbar Fix

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "`n  ============ TASKBAR FIX ============" -ForegroundColor Cyan
Write-Host "  Fixing taskbar and Start menu...`n" -ForegroundColor White

# Step 1: Kill explorer
Write-Host "[1/4] Restarting Explorer..." -ForegroundColor Yellow
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Step 2: Clear icon cache
Write-Host "`n[2/4] Clearing icon cache..." -ForegroundColor Yellow
Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Cache cleared" -ForegroundColor Green

# Step 3: Re-register taskbar
Write-Host "`n[3/4] Re-registering taskbar components..." -ForegroundColor Yellow
Get-AppxPackage -AllUsers | Where-Object { $_.Name -match "ShellExperienceHost|StartMenuExperienceHost" } | ForEach-Object {
    Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppxManifest.xml" -ErrorAction SilentlyContinue
    Write-Host "  Re-registered: $($_.Name)" -ForegroundColor Gray
}
Write-Host "  [OK] Components re-registered" -ForegroundColor Green

# Step 4: Start explorer
Write-Host "`n[4/4] Starting Explorer..." -ForegroundColor Yellow
Start-Process explorer
Start-Sleep -Seconds 3
Write-Host "  [OK] Explorer started" -ForegroundColor Green

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
Write-Host "  Taskbar should now be working." -ForegroundColor White
Write-Host "  If issues persist, reboot the PC." -ForegroundColor Gray

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
