#Requires -RunAsAdministrator
# Windows 11 Bluetooth Fix

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "`n  ============ BLUETOOTH FIX ============" -ForegroundColor Cyan
Write-Host "  Fixing Bluetooth issues...`n" -ForegroundColor White

# Step 1: Restart Bluetooth services
Write-Host "[1/4] Restarting Bluetooth services..." -ForegroundColor Yellow
$btServices = @("bthserv", "BluetoothUserService_*")
foreach ($pattern in $btServices) {
    Get-Service -Name $pattern -ErrorAction SilentlyContinue | ForEach-Object {
        Restart-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
        Write-Host "  Restarted: $($_.DisplayName)" -ForegroundColor Gray
    }
}
Write-Host "  [OK] Services restarted" -ForegroundColor Green

# Step 2: Reset Bluetooth adapter
Write-Host "`n[2/4] Resetting Bluetooth adapter..." -ForegroundColor Yellow
Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | ForEach-Object {
    Disable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  Reset: $($_.FriendlyName)" -ForegroundColor Gray
}
Write-Host "  [OK] Adapter reset" -ForegroundColor Green

# Step 3: Clear Bluetooth cache
Write-Host "`n[3/4] Clearing Bluetooth cache..." -ForegroundColor Yellow
Stop-Service -Name "bthserv" -Force -ErrorAction SilentlyContinue
$btCache = "$env:ProgramData\Microsoft\Bluetooth"
if (Test-Path $btCache) {
    Remove-Item "$btCache\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Cache cleared" -ForegroundColor Green
} else {
    Write-Host "  [OK] No cache to clear" -ForegroundColor Gray
}
Start-Service -Name "bthserv" -ErrorAction SilentlyContinue

# Step 4: Run troubleshooter
Write-Host "`n[4/4] Running Bluetooth troubleshooter..." -ForegroundColor Yellow
Start-Process "msdt.exe" -ArgumentList "/id BluetoothDiagnostic" -Wait -ErrorAction SilentlyContinue
Write-Host "  [OK] Troubleshooter launched" -ForegroundColor Green

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
Write-Host "  Bluetooth should now be working." -ForegroundColor White
Write-Host "  Check Settings > Bluetooth & devices" -ForegroundColor Gray

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
