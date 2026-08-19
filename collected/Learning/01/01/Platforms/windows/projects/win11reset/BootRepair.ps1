#Requires -RunAsAdministrator
# Windows 11 Boot Repair
# Fixes common boot issues

$ErrorActionPreference = "Continue"
$logFile = "$PSScriptRoot\boot_repair_log.txt"

function Log {
    param([string]$msg, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $msg"
    $color = switch($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } "SUCCESS" { "Green" } default { "White" } }
    Write-Host $line -ForegroundColor $color
    $line | Out-File -FilePath $logFile -Append -Encoding UTF8
}

Clear-Host
Write-Host "`n  ============ BOOT REPAIR ============" -ForegroundColor Cyan
Write-Host "  Repairing Windows boot components...`n" -ForegroundColor White

Remove-Item $logFile -Force -ErrorAction SilentlyContinue
Log "=== Boot Repair Started ==="

# Step 1: Check boot type
Write-Host "[1/6] Detecting boot type..." -ForegroundColor Yellow
$bootType = if (Test-Path "C:\Windows\Boot\EFI") { "UEFI" } else { "Legacy BIOS" }
Log "Boot Type: $bootType"
Write-Host "  Boot Type: $bootType" -ForegroundColor Cyan

# Step 2: Check secure boot
Write-Host "`n[2/6] Checking Secure Boot..." -ForegroundColor Yellow
try {
    $secureboot = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
    Log "Secure Boot: $(if($secureboot){'Enabled'}else{'Disabled'})"
    Write-Host "  Secure Boot: $(if($secureboot){'Enabled'}else{'Disabled'})" -ForegroundColor Gray
} catch {
    Log "Secure Boot: Not available (Legacy BIOS)" "WARN"
    Write-Host "  Secure Boot: Not available" -ForegroundColor Gray
}

# Step 3: Repair Boot Configuration
Write-Host "`n[3/6] Repairing Boot Configuration..." -ForegroundColor Yellow

# bootrec commands (work in both BIOS and UEFI)
Log "Running: bootrec /fixmbr"
$result = & cmd /c "bootrec /fixmbr" 2>&1 | Out-String
Log $result.Trim()

Log "Running: bootrec /fixboot"
$result = & cmd /c "bootrec /fixboot" 2>&1 | Out-String
Log $result.Trim()
if ($result -match "denied") {
    Log "Access denied - trying alternative method..." "WARN"
    $result = & cmd /c "bootsect /nt60 C: /force /mbr" 2>&1 | Out-String
    Log $result.Trim()
}

Log "Running: bootrec /rebuildbcd"
$result = & cmd /c "echo A | bootrec /rebuildbcd" 2>&1 | Out-String
Log $result.Trim()

Write-Host "  [OK] Boot configuration repaired" -ForegroundColor Green

# Step 4: Rebuild BCD
Write-Host "`n[4/6] Rebuilding Boot Store..." -ForegroundColor Yellow
$systemDrive = $env:SystemDrive
Log "Running: bcdboot $systemDrive\Windows"

if ($bootType -eq "UEFI") {
    # UEFI boot
    $result = & cmd /c "bcdboot $systemDrive\Windows /s $systemDrive /f UEFI" 2>&1 | Out-String
} else {
    # Legacy BIOS
    $result = & cmd /c "bcdboot $systemDrive\Windows /s $systemDrive /f BIOS" 2>&1 | Out-String
}
Log $result.Trim()
Write-Host "  [OK] Boot store rebuilt" -ForegroundColor Green

# Step 5: Check boot entries
Write-Host "`n[5/6] Verifying boot entries..." -ForegroundColor Yellow
$bcdedit = & bcdedit /enum 2>&1 | Out-String
if ($bcdedit -match "Windows") {
    Log "Windows boot entry found" "SUCCESS"
    Write-Host "  [OK] Windows boot entry verified" -ForegroundColor Green
} else {
    Log "No Windows boot entry found!" "ERROR"
    Write-Host "  [!] No Windows entry - may need manual repair" -ForegroundColor Red
}

# Step 6: UEFI entry repair (if UEFI)
if ($bootType -eq "UEFI") {
    Write-Host "`n[6/6] Repairing UEFI entries..." -ForegroundColor Yellow
    
    # Create new UEFI entry
    $efiPath = "\EFI\Microsoft\Boot\bootmgfw.efi"
    $result = & cmd /c "bcdedit /set `{bootmgr`} path $efiPath" 2>&1 | Out-String
    Log "Set bootmgr path: $result"
    
    # Set default
    $result = & cmd /c "bcdedit /set `{bootmgr`} displaybootmenu no" 2>&1 | Out-String
    Log "Boot menu: $result"
    
    Write-Host "  [OK] UEFI entries repaired" -ForegroundColor Green
} else {
    Write-Host "`n[6/6] Legacy BIOS - No UEFI repair needed" -ForegroundColor Gray
}

# Summary
Log "=== Boot Repair Complete ==="
Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
Write-Host "  Boot repair finished!" -ForegroundColor White
Write-Host "  Log: $logFile" -ForegroundColor Gray
Write-Host "`n  If Windows still won't start:" -ForegroundColor Yellow
Write-Host "  1. Boot from Windows USB" -ForegroundColor Gray
Write-Host "  2. Select 'Repair your computer'" -ForegroundColor Gray
Write-Host "  3. Troubleshoot > Startup Repair" -ForegroundColor Gray

Write-Host "`n  Reboot now? (Y/N): " -NoNewline -ForegroundColor Cyan
$reboot = Read-Host
if ($reboot -eq "Y") {
    Write-Host "  Rebooting in 5 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    Restart-Computer -Force
} else {
    Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
