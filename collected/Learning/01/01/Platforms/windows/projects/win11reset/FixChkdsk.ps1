#Requires -RunAsAdministrator
# Fix Chkdsk Not Running at Startup
# One-click fix for the most common chkdsk issue

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "`n  ============ FIX CHKDSK ============" -ForegroundColor Cyan
Write-Host "  Fixing chkdsk startup issues`n" -ForegroundColor White

# Step 1: Fix BootExecute registry
Write-Host "[1/4] Fixing BootExecute registry..." -ForegroundColor Yellow
try {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    $current = (Get-ItemProperty $regPath -Name BootExecute -ErrorAction SilentlyContinue).BootExecute
    Write-Host "  Current: $current" -ForegroundColor Gray
    
    # Set correct value
    Set-ItemProperty -Path $regPath -Name BootExecute -Value "autocheck autochk *" -Type MultiString
    Write-Host "  [OK] Registry fixed" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
}

# Step 2: Verify autochk.exe exists
Write-Host "`n[2/4] Verifying autochk.exe..." -ForegroundColor Yellow
$autochkPath = "$env:SystemRoot\System32\autochk.exe"
if (Test-Path $autochkPath) {
    $size = [math]::Round((Get-Item $autochkPath).Length / 1KB, 2)
    Write-Host "  [OK] autochk.exe exists ($size KB)" -ForegroundColor Green
} else {
    Write-Host "  [MISSING] autochk.exe not found!" -ForegroundColor Red
    Write-Host "  Attempting to restore via DISM..." -ForegroundColor Yellow
    Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -Wait -NoNewWindow
}

# Step 3: Check volume dirty bit
Write-Host "`n[3/4] Checking volume status..." -ForegroundColor Yellow
$fsutil = & fsutil dirty query C: 2>&1
Write-Host "  $fsutil" -ForegroundColor Gray

# Step 4: Schedule chkdsk
Write-Host "`n[4/4] Scheduling chkdsk for next boot..." -ForegroundColor Yellow
$schedule = & cmd /c "echo Y | chkdsk C: /F" 2>&1 | Out-String
if ($schedule -match "scheduled") {
    Write-Host "  [OK] Chkdsk scheduled for next reboot" -ForegroundColor Green
} else {
    Write-Host "  Result: $schedule" -ForegroundColor Gray
}

# Summary
Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Cyan
Write-Host "  Chkdsk should now run at next boot." -ForegroundColor White
Write-Host "`n  To verify, reboot and watch for the" -ForegroundColor Gray
Write-Host "  chkdsk screen before Windows loads." -ForegroundColor Gray

Write-Host "`n  Reboot now? (Y/N): " -NoNewline -ForegroundColor Yellow
$reboot = Read-Host
if ($reboot -eq "Y") {
    Write-Host "  Rebooting in 5 seconds..." -ForegroundColor Cyan
    Start-Sleep -Seconds 5
    Restart-Computer -Force
} else {
    Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
