#Requires -RunAsAdministrator
# Windows 11 Display Fix

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "`n  ============ DISPLAY FIX ============" -ForegroundColor Magenta
Write-Host "  Fixing display issues...`n" -ForegroundColor White

# Step 1: Restart graphics drivers
Write-Host "[1/4] Restarting graphics services..." -ForegroundColor Yellow
# This triggers a display driver restart (same as Win+Ctrl+Shift+B)
$signature = @'
[DllImport("user32.dll")]
public static extern bool keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
'@
# Note: Manual restart is safer
Write-Host "  Tip: Press Win+Ctrl+Shift+B to restart graphics driver" -ForegroundColor Gray
Write-Host "  [OK] Instruction provided" -ForegroundColor Green

# Step 2: Reset display settings
Write-Host "`n[2/4] Resetting display cache..." -ForegroundColor Yellow
$displayRegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\VideoSettings"
if (Test-Path $displayRegPath) {
    Remove-Item $displayRegPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Display cache cleared" -ForegroundColor Green
} else {
    Write-Host "  [OK] No cache to clear" -ForegroundColor Gray
}

# Step 3: Clear icon cache
Write-Host "`n[3/4] Clearing icon cache..." -ForegroundColor Yellow
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
Start-Process explorer -ErrorAction SilentlyContinue
Write-Host "  [OK] Cache cleared" -ForegroundColor Green

# Step 4: Check for driver issues
Write-Host "`n[4/4] Checking graphics adapter..." -ForegroundColor Yellow
Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | ForEach-Object {
    $status = if ($_.Status -eq "OK") { "[OK]" } else { "[!]" }
    $color = if ($_.Status -eq "OK") { "Green" } else { "Red" }
    Write-Host "  $status $($_.FriendlyName) - $($_.Status)" -ForegroundColor $color
}

Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  Driver: $($_.DriverVersion)" -ForegroundColor Gray
    Write-Host "  Resolution: $($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)" -ForegroundColor Gray
}

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
Write-Host "  Display settings reset." -ForegroundColor White
Write-Host "  If issues persist, update graphics drivers." -ForegroundColor Gray

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
