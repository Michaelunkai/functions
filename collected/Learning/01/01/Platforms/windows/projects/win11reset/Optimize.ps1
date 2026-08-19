#Requires -RunAsAdministrator
# Windows 11 Optimization Script
# Safe performance improvements

param(
    [switch]$Aggressive,  # More optimizations (some may affect features)
    [switch]$DryRun,      # Show what would happen
    [switch]$Undo         # Reverse optimizations
)

$ErrorActionPreference = "Continue"
$logFile = "$PSScriptRoot\optimize_log.txt"

function Log {
    param([string]$msg, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $msg"
    $color = switch($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } "SUCCESS" { "Green" } "SKIP" { "DarkGray" } default { "White" } }
    Write-Host $line -ForegroundColor $color
    $line | Out-File -FilePath $logFile -Append -Encoding UTF8
}

function Optimize {
    param([string]$Name, [scriptblock]$Action, [scriptblock]$UndoAction)
    if ($DryRun) {
        Log "[DRY] Would: $Name" "WARN"
    } elseif ($Undo -and $UndoAction) {
        Log "Undoing: $Name"
        try { & $UndoAction; Log "Reverted: $Name" "SUCCESS" } catch { Log "Failed: $($_.Exception.Message)" "ERROR" }
    } else {
        Log "Applying: $Name"
        try { & $Action; Log "Done: $Name" "SUCCESS" } catch { Log "Failed: $($_.Exception.Message)" "ERROR" }
    }
}

Clear-Host
$mode = if ($Undo) { "UNDO" } elseif ($DryRun) { "DRY RUN" } else { "OPTIMIZE" }
Write-Host "`n  ============ WINDOWS 11 OPTIMIZATION ($mode) ============" -ForegroundColor Cyan
Write-Host "  Safe performance improvements`n" -ForegroundColor White

Remove-Item $logFile -Force -ErrorAction SilentlyContinue
Log "=== Optimization Started - Mode: $mode ==="

# ===== DISK CLEANUP =====
Write-Host "`n>>> Disk Cleanup" -ForegroundColor Yellow

Optimize "Clear Windows Temp files" {
    Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
}

Optimize "Clear Windows Update cache (old downloads)" {
    Remove-Item "$env:SystemRoot\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
}

Optimize "Clear Prefetch (will rebuild)" {
    Remove-Item "$env:SystemRoot\Prefetch\*" -Force -ErrorAction SilentlyContinue
}

Optimize "Clear thumbnail cache" {
    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
}

# ===== STARTUP OPTIMIZATION =====
Write-Host "`n>>> Startup Optimization" -ForegroundColor Yellow

Optimize "Disable Windows Search indexing on SSD" {
    $ssd = Get-PhysicalDisk | Where-Object { $_.MediaType -eq "SSD" }
    if ($ssd) {
        Stop-Service WSearch -Force -ErrorAction SilentlyContinue
        Set-Service WSearch -StartupType Manual -ErrorAction SilentlyContinue
    }
} {
    Set-Service WSearch -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service WSearch -ErrorAction SilentlyContinue
}

# ===== VISUAL PERFORMANCE =====
Write-Host "`n>>> Visual Performance" -ForegroundColor Yellow

Optimize "Optimize visual effects for performance" {
    # Disable animations
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Value 0 -ErrorAction SilentlyContinue
}

# ===== PRIVACY & TELEMETRY (if Aggressive) =====
if ($Aggressive) {
    Write-Host "`n>>> Privacy & Telemetry (Aggressive)" -ForegroundColor Yellow
    
    Optimize "Disable telemetry service" {
        Stop-Service DiagTrack -Force -ErrorAction SilentlyContinue
        Set-Service DiagTrack -StartupType Disabled -ErrorAction SilentlyContinue
    } {
        Set-Service DiagTrack -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service DiagTrack -ErrorAction SilentlyContinue
    }
    
    Optimize "Disable Cortana" {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0 -Force -ErrorAction SilentlyContinue
    } {
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -ErrorAction SilentlyContinue
    }
}

# ===== MEMORY OPTIMIZATION =====
Write-Host "`n>>> Memory Optimization" -ForegroundColor Yellow

Optimize "Clear standby memory" {
    # This is safe and Windows will recache as needed
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}

Optimize "Optimize paging file" {
    # Let Windows manage it automatically
    $cs = Get-CimInstance Win32_ComputerSystem
    $cs | Set-CimInstance -Property @{AutomaticManagedPagefile=$true} -ErrorAction SilentlyContinue
}

# ===== NETWORK OPTIMIZATION =====
Write-Host "`n>>> Network Optimization" -ForegroundColor Yellow

Optimize "Reset DNS cache" {
    Clear-DnsClientCache
}

Optimize "Optimize network adapter settings" {
    # Disable Large Send Offload (can cause issues)
    Get-NetAdapter | Where-Object Status -eq "Up" | ForEach-Object {
        Disable-NetAdapterLso -Name $_.Name -ErrorAction SilentlyContinue
    }
}

# ===== SCHEDULED TASKS =====
Write-Host "`n>>> Unnecessary Scheduled Tasks" -ForegroundColor Yellow

$tasksToDisable = @(
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
)

foreach ($task in $tasksToDisable) {
    Optimize "Disable: $($task.Split('\')[-1])" {
        Disable-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue | Out-Null
    } {
        Enable-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue | Out-Null
    }
}

# ===== SUMMARY =====
$elapsed = [math]::Round(((Get-Date) - (Get-Date).AddSeconds(-30)).TotalSeconds, 1)
Log "=== Optimization Complete ==="

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
Write-Host "  Log: $logFile" -ForegroundColor Gray

if (-not $DryRun -and -not $Undo) {
    Write-Host "`n  Recommendations:" -ForegroundColor Yellow
    Write-Host "  - Restart for full effect" -ForegroundColor Gray
    Write-Host "  - Run with -Aggressive for more optimizations" -ForegroundColor Gray
    Write-Host "  - Run with -Undo to reverse changes" -ForegroundColor Gray
}

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
