# Macrium Reflect Backup Cleanup Script v2.0
# Disables Image Guardian, deletes backup* files, re-enables protection
# Run as Administrator

$ErrorActionPreference = "Stop"
$LogFile = "F:\reflect_cleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$TargetPath = "F:\win11recovery"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry
    Add-Content -Path $LogFile -Value $logEntry
}

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host "ERROR: Run as Administrator!"; exit 1 }

Write-Log "========== CLEANUP STARTED =========="

# Get files before
$filesBefore = Get-ChildItem -Path $TargetPath -Filter "backup*" -Recurse -ErrorAction SilentlyContinue
$totalSizeBefore = ($filesBefore | Measure-Object -Property Length -Sum).Sum
Write-Log "Found $($filesBefore.Count) backup files ($([math]::Round($totalSizeBefore/1GB,2)) GB)"

if ($filesBefore.Count -eq 0) {
    Write-Log "No backup files found. Exiting."
    exit 0
}

foreach ($f in $filesBefore) {
    Write-Log "  - $($f.FullName) ($([math]::Round($f.Length/1GB,2)) GB)"
}

# Disable Image Guardian
Write-Log "Disabling Image Guardian..."
Stop-Process -Name "ReflectUI","ReflectMonitor" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "MacriumService" -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Macrium\reflect\MIG" -Name "Enabled" -Value 0
Set-ItemProperty -Path "HKLM:\SOFTWARE\Macrium\reflect\ImageGuardian" -Name "AutoProtect" -Value 0
Start-Service -Name "MacriumService" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Write-Log "Image Guardian disabled"

# Delete files
$deleted = 0
$failed = 0
foreach ($f in $filesBefore) {
    try {
        Write-Log "Deleting: $($f.FullName)"
        Remove-Item -Path $f.FullName -Force
        $deleted++
    } catch {
        Write-Log "FAILED: $($f.FullName) - $($_.Exception.Message)" "ERROR"
        $failed++
    }
}

# Verify
$remaining = Get-ChildItem -Path $TargetPath -Filter "backup*" -Recurse -ErrorAction SilentlyContinue
Write-Log "Verification: $($remaining.Count) files remaining"

# Re-enable Image Guardian
Write-Log "Re-enabling Image Guardian..."
Set-ItemProperty -Path "HKLM:\SOFTWARE\Macrium\reflect\MIG" -Name "Enabled" -Value 1
Set-ItemProperty -Path "HKLM:\SOFTWARE\Macrium\reflect\ImageGuardian" -Name "AutoProtect" -Value 1
Write-Log "Image Guardian re-enabled"

# Summary
Write-Log "========== SUMMARY =========="
Write-Log "Files deleted: $deleted"
Write-Log "Files failed: $failed"
Write-Log "Space freed: $([math]::Round($totalSizeBefore/1GB,2)) GB"
Write-Log "Remaining: $($remaining.Count)"
Write-Log "Log: $LogFile"
Write-Log "========== COMPLETED =========="
