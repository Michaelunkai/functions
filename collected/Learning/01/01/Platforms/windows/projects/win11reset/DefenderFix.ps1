#Requires -RunAsAdministrator
# Windows Defender Fix

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "`n  ============ DEFENDER FIX ============" -ForegroundColor Red
Write-Host "  Fixing Windows Defender...`n" -ForegroundColor White

# Step 1: Restart services
Write-Host "[1/4] Restarting Defender services..." -ForegroundColor Yellow
$defenderServices = @("WinDefend", "WdNisSvc", "SecurityHealthService")
foreach ($svc in $defenderServices) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        Restart-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Write-Host "  Restarted: $($service.DisplayName)" -ForegroundColor Gray
    }
}
Write-Host "  [OK] Services restarted" -ForegroundColor Green

# Step 2: Update definitions
Write-Host "`n[2/4] Updating virus definitions..." -ForegroundColor Yellow
Update-MpSignature -ErrorAction SilentlyContinue
$defStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($defStatus) {
    Write-Host "  Signature version: $($defStatus.AntivirusSignatureVersion)" -ForegroundColor Gray
    Write-Host "  Last updated: $($defStatus.AntivirusSignatureLastUpdated)" -ForegroundColor Gray
}
Write-Host "  [OK] Definitions updated" -ForegroundColor Green

# Step 3: Reset Defender settings
Write-Host "`n[3/4] Resetting Defender configuration..." -ForegroundColor Yellow
# Ensure real-time protection is on
Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction SilentlyContinue
Set-MpPreference -DisableScriptScanning $false -ErrorAction SilentlyContinue
Write-Host "  [OK] Configuration reset" -ForegroundColor Green

# Step 4: Check status
Write-Host "`n[4/4] Current Defender status:" -ForegroundColor Yellow
$status = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($status) {
    $rtColor = if ($status.RealTimeProtectionEnabled) { "Green" } else { "Red" }
    Write-Host "  Real-time protection: $(if($status.RealTimeProtectionEnabled){'ON'}else{'OFF'})" -ForegroundColor $rtColor
    Write-Host "  Antivirus enabled: $(if($status.AntivirusEnabled){'YES'}else{'NO'})" -ForegroundColor Green
    Write-Host "  Last scan: $($status.LastFullScanEndTime)" -ForegroundColor Gray
} else {
    Write-Host "  [!] Could not get status" -ForegroundColor Yellow
}

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
Write-Host "  Windows Defender should now be working." -ForegroundColor White

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
