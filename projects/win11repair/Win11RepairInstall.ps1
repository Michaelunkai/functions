#Requires -RunAsAdministrator
# Windows 11 In-Place Repair - DIRECT ISO VERSION
# Uses: E:\isos\Windows.iso

$ErrorActionPreference = "Stop"
$isoPath = "E:\isos\Windows.iso"
$logFile = "$PSScriptRoot\repair_log.txt"

function Log($msg) {
    $line = "$(Get-Date -Format 'HH:mm:ss') - $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

# Clear old log
Remove-Item $logFile -Force -ErrorAction SilentlyContinue

Log "=== Windows 11 Repair Install ==="
Log "Using ISO: $isoPath"

# Verify ISO
if (-not (Test-Path $isoPath)) {
    Log "ERROR: ISO not found!"
    exit 1
}
Log "ISO verified: $([math]::Round((Get-Item $isoPath).Length/1GB, 2)) GB"

# Mount ISO
Log "Mounting ISO..."
try {
    # Dismount if already mounted
    Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    
    $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
    Start-Sleep -Milliseconds 500
    $driveLetter = ($mountResult | Get-Volume).DriveLetter
    
    if (-not $driveLetter) {
        $driveLetter = (Get-DiskImage -ImagePath $isoPath | Get-Volume).DriveLetter
    }
    Log "Mounted to: ${driveLetter}:"
} catch {
    Log "ERROR mounting: $($_.Exception.Message)"
    exit 1
}

# Verify setup.exe
$setupPath = "${driveLetter}:\setup.exe"
if (-not (Test-Path $setupPath)) {
    Log "ERROR: setup.exe not found!"
    Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
    exit 1
}
Log "Found: $setupPath"

# Launch repair
Log "Launching Windows Setup..."
$setupArgs = "/auto upgrade /dynamicupdate disable /eula accept /migratedrivers all /telemetry disable /compat ignorewarning"
Log "Args: $setupArgs"

try {
    $process = Start-Process -FilePath $setupPath -ArgumentList $setupArgs -PassThru
    Log "Setup launched! PID: $($process.Id)"
    Log "Windows will restart automatically during repair."
    Log "DO NOT turn off your computer!"
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  REPAIR STARTED!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "PID: $($process.Id)" -ForegroundColor Cyan
    Write-Host "Your PC will restart automatically." -ForegroundColor Yellow
    Write-Host "DO NOT turn off your computer!" -ForegroundColor Red
    
} catch {
    Log "ERROR: $($_.Exception.Message)"
    Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
    exit 1
}
