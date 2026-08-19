#Requires -RunAsAdministrator
# Windows 11 Explorer Fix

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "`n  ============ EXPLORER FIX ============" -ForegroundColor Green
Write-Host "  Fixing File Explorer...`n" -ForegroundColor White

# Step 1: Kill explorer
Write-Host "[1/5] Stopping Explorer..." -ForegroundColor Yellow
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Write-Host "  [OK] Explorer stopped" -ForegroundColor Green

# Step 2: Clear recent files
Write-Host "`n[2/5] Clearing recent files..." -ForegroundColor Yellow
Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\*" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations\*" -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Recent files cleared" -ForegroundColor Green

# Step 3: Clear thumbnail cache
Write-Host "`n[3/5] Clearing thumbnail cache..." -ForegroundColor Yellow
Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Thumbnails cleared" -ForegroundColor Green

# Step 4: Reset folder view
Write-Host "`n[4/5] Resetting folder options..." -ForegroundColor Yellow
$shellPath = "HKCU:\SOFTWARE\Microsoft\Windows\Shell"
if (Test-Path "$shellPath\Bags") {
    Remove-Item "$shellPath\Bags" -Recurse -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$shellPath\BagMRU") {
    Remove-Item "$shellPath\BagMRU" -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "  [OK] Folder views reset" -ForegroundColor Green

# Step 5: Start explorer
Write-Host "`n[5/5] Starting Explorer..." -ForegroundColor Yellow
Start-Process explorer
Start-Sleep -Seconds 3
Write-Host "  [OK] Explorer started" -ForegroundColor Green

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
Write-Host "  File Explorer should now be working." -ForegroundColor White

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
