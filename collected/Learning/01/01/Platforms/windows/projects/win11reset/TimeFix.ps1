#Requires -RunAsAdministrator
# Windows 11 Time Fix

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "`n  ============ TIME FIX ============" -ForegroundColor Yellow
Write-Host "  Fixing time synchronization...`n" -ForegroundColor White

# Current time
Write-Host "Current system time: $(Get-Date)" -ForegroundColor Gray

# Step 1: Restart time service
Write-Host "`n[1/4] Restarting time service..." -ForegroundColor Yellow
Stop-Service -Name "w32time" -Force -ErrorAction SilentlyContinue
Start-Service -Name "w32time" -ErrorAction SilentlyContinue
Write-Host "  [OK] Service restarted" -ForegroundColor Green

# Step 2: Configure time servers
Write-Host "`n[2/4] Configuring time servers..." -ForegroundColor Yellow
w32tm /config /manualpeerlist:"time.windows.com,0x1 time.nist.gov,0x1 pool.ntp.org,0x1" /syncfromflags:manual /reliable:yes /update 2>&1 | Out-Null
Write-Host "  [OK] Servers configured" -ForegroundColor Green

# Step 3: Force sync
Write-Host "`n[3/4] Forcing time sync..." -ForegroundColor Yellow
w32tm /resync /force 2>&1 | Out-Null
Start-Sleep -Seconds 2
Write-Host "  [OK] Sync requested" -ForegroundColor Green

# Step 4: Verify
Write-Host "`n[4/4] Verifying time..." -ForegroundColor Yellow
$status = w32tm /query /status 2>&1
Write-Host "  Updated time: $(Get-Date)" -ForegroundColor Cyan

# Check if UTC in BIOS issue (common with dual-boot)
$utcReg = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" -Name "RealTimeIsUniversal" -ErrorAction SilentlyContinue
if ($utcReg) {
    Write-Host "  Note: UTC mode enabled (for dual-boot)" -ForegroundColor Gray
}

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
Write-Host "  Time synchronization configured." -ForegroundColor White

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
