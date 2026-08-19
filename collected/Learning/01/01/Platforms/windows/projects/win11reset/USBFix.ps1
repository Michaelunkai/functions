#Requires -RunAsAdministrator
# Windows 11 USB Fix

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "`n  ============ USB FIX ============" -ForegroundColor Cyan
Write-Host "  Fixing USB device issues...`n" -ForegroundColor White

# Step 1: Reset USB host controllers
Write-Host "[1/4] Resetting USB controllers..." -ForegroundColor Yellow
Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match "ROOT_HUB" -or $_.InstanceId -match "HOST" } | ForEach-Object {
    Disable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  Reset: $($_.FriendlyName)" -ForegroundColor Gray
}
Write-Host "  [OK] Controllers reset" -ForegroundColor Green

# Step 2: Disable USB selective suspend
Write-Host "`n[2/4] Disabling USB power saving..." -ForegroundColor Yellow
$powerScheme = powercfg /getactivescheme | Select-String -Pattern "GUID: ([a-z0-9-]+)" | ForEach-Object { $_.Matches.Groups[1].Value }
if ($powerScheme) {
    # USB selective suspend: 2a737441-1930-4402-8d77-b2bebba308a3 / 48e6b7a6-50f5-4782-a5d4-53bb8f07e226
    powercfg /setacvalueindex $powerScheme 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
    powercfg /setdcvalueindex $powerScheme 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
    Write-Host "  [OK] Power saving disabled" -ForegroundColor Green
}

# Step 3: Remove hidden/ghost devices
Write-Host "`n[3/4] Removing ghost USB devices..." -ForegroundColor Yellow
$env:DEVMGR_SHOW_NONPRESENT_DEVICES = 1
Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Unknown" -or $_.Status -eq "Error" } | ForEach-Object {
    pnputil /remove-device $_.InstanceId 2>&1 | Out-Null
    Write-Host "  Removed: $($_.FriendlyName)" -ForegroundColor Gray
}
Write-Host "  [OK] Ghost devices cleared" -ForegroundColor Green

# Step 4: Check current USB devices
Write-Host "`n[4/4] Current USB devices:" -ForegroundColor Yellow
Get-PnpDevice -Class USB -Status OK -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  [OK] $($_.FriendlyName)" -ForegroundColor Green
}

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
Write-Host "  USB devices reset." -ForegroundColor White
Write-Host "  Reconnect any problematic devices." -ForegroundColor Gray

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
