#Requires -RunAsAdministrator
# Windows Store Fix
# Fixes Microsoft Store and AppX issues

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "`n  ============ WINDOWS STORE FIX ============" -ForegroundColor Magenta
Write-Host "  Fixing Microsoft Store issues...`n" -ForegroundColor White

# Step 1: Clear Store cache
Write-Host "[1/5] Clearing Store cache..." -ForegroundColor Yellow
Start-Process "wsreset.exe" -Wait -ErrorAction SilentlyContinue
Write-Host "  [OK] Cache cleared" -ForegroundColor Green

# Step 2: Reset Store via PowerShell
Write-Host "`n[2/5] Resetting Store app..." -ForegroundColor Yellow
Get-AppxPackage *WindowsStore* | ForEach-Object {
    Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppxManifest.xml" -ErrorAction SilentlyContinue
}
Write-Host "  [OK] Store reset" -ForegroundColor Green

# Step 3: Re-register all Store apps
Write-Host "`n[3/5] Re-registering Store apps..." -ForegroundColor Yellow
Get-AppxPackage -AllUsers | ForEach-Object {
    Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppxManifest.xml" -ErrorAction SilentlyContinue
} 2>&1 | Out-Null
Write-Host "  [OK] Apps re-registered" -ForegroundColor Green

# Step 4: Clear app licenses
Write-Host "`n[4/5] Refreshing app licenses..." -ForegroundColor Yellow
$clipSvc = Get-Service clipsvc -ErrorAction SilentlyContinue
if ($clipSvc) {
    Stop-Service clipsvc -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:ProgramData\Microsoft\Windows\ClipSVC\*" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service clipsvc -ErrorAction SilentlyContinue
}
Write-Host "  [OK] Licenses refreshed" -ForegroundColor Green

# Step 5: Restart Store services
Write-Host "`n[5/5] Restarting services..." -ForegroundColor Yellow
@("wuauserv", "bits", "AppXSvc") | ForEach-Object {
    Restart-Service -Name $_ -Force -ErrorAction SilentlyContinue
}
Write-Host "  [OK] Services restarted" -ForegroundColor Green

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
Write-Host "  Microsoft Store should now work properly." -ForegroundColor White
Write-Host "  If issues persist, try rebooting." -ForegroundColor Gray

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
