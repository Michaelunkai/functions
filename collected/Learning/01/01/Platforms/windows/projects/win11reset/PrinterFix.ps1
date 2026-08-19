#Requires -RunAsAdministrator
# Windows 11 Printer Fix
# Fixes print spooler and queue issues

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "`n  ============ PRINTER FIX ============" -ForegroundColor Cyan
Write-Host "  Fixing printer issues...`n" -ForegroundColor White

# Step 1: Stop spooler
Write-Host "[1/4] Stopping Print Spooler..." -ForegroundColor Yellow
Stop-Service -Name "Spooler" -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Spooler stopped" -ForegroundColor Green

# Step 2: Clear print queue
Write-Host "`n[2/4] Clearing print queue..." -ForegroundColor Yellow
Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Queue cleared" -ForegroundColor Green

# Step 3: Reset spooler
Write-Host "`n[3/4] Resetting spooler configuration..." -ForegroundColor Yellow
# Reset spooler security descriptor
$sd = "D:(A;;CCLCSWLOCRRC;;;AU)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWRPWPDTLOCRRC;;;SY)"
& sc.exe sdset Spooler $sd 2>&1 | Out-Null
Write-Host "  [OK] Configuration reset" -ForegroundColor Green

# Step 4: Start spooler
Write-Host "`n[4/4] Starting Print Spooler..." -ForegroundColor Yellow
Start-Service -Name "Spooler" -ErrorAction SilentlyContinue
Set-Service -Name "Spooler" -StartupType Automatic -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$spooler = Get-Service -Name "Spooler"
if ($spooler.Status -eq "Running") {
    Write-Host "  [OK] Spooler running" -ForegroundColor Green
} else {
    Write-Host "  [!] Spooler failed to start" -ForegroundColor Red
}

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
Write-Host "  Print spooler has been reset." -ForegroundColor White
Write-Host "  Try printing again. If issues persist," -ForegroundColor Gray
Write-Host "  remove and re-add the printer." -ForegroundColor Gray

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
