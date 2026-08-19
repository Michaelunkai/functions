#Requires -RunAsAdministrator
# Create System Restore Point

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "`n  ============ CREATE RESTORE POINT ============" -ForegroundColor Green
Write-Host "  Creating a system backup point...`n" -ForegroundColor White

# Check if System Restore is enabled
$restoreEnabled = (Get-ComputerRestorePoint -ErrorAction SilentlyContinue) -ne $null
$srConfig = Get-CimInstance -ClassName Win32_SystemRestoreConfig -ErrorAction SilentlyContinue

# Enable System Restore if disabled
Write-Host "[1/3] Checking System Restore status..." -ForegroundColor Yellow
try {
    Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    Write-Host "  [OK] System Restore enabled on C:" -ForegroundColor Green
} catch {
    Write-Host "  [!] Could not enable (may already be enabled)" -ForegroundColor Gray
}

# Create restore point
Write-Host "`n[2/3] Creating restore point..." -ForegroundColor Yellow
$description = "Win11Reset Backup - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
try {
    Checkpoint-Computer -Description $description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
    Write-Host "  [OK] Restore point created: $description" -ForegroundColor Green
} catch {
    if ($_.Exception.Message -match "1058") {
        Write-Host "  [!] Too soon since last restore point (Windows limit)" -ForegroundColor Yellow
        Write-Host "      Windows only allows one restore point per 24 hours." -ForegroundColor Gray
    } else {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
}

# List recent restore points
Write-Host "`n[3/3] Recent restore points:" -ForegroundColor Yellow
$points = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Select-Object -Last 5
if ($points) {
    $points | ForEach-Object {
        Write-Host "  [$($_.SequenceNumber)] $($_.Description) - $($_.CreationTime)" -ForegroundColor Gray
    }
} else {
    Write-Host "  No restore points found" -ForegroundColor Gray
}

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
Write-Host "  To restore: Settings > System > Recovery > Open System Restore" -ForegroundColor Gray

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
