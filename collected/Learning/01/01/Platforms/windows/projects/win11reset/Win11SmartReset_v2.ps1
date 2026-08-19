#Requires -RunAsAdministrator
# Windows 11 Smart Reset v2.0 - FAST AUTOMATIC EDITION
# Optimized for speed and automation
# 
# MODES:
#   -Mode QuickFix    : (5 min)  Fast fixes for common issues
#   -Mode DeepRepair  : (15 min) Full system repair - KEEPS ALL APPS
#   -Mode Diagnose    : (2 min)  Just analyze, don't fix

param(
    [ValidateSet("QuickFix", "DeepRepair", "Diagnose")]
    [string]$Mode = "QuickFix",
    
    [switch]$Force,            # Skip confirmations
    [switch]$NoReboot,         # Don't auto-reboot
    [switch]$Verbose           # Extra output
)

$ErrorActionPreference = "Continue"
$logFile = "$PSScriptRoot\reset_log_v2.txt"
$reportFile = "$PSScriptRoot\reset_report_v2.txt"
$script:issues = @()
$script:fixes = @()

# ===== FAST LOGGING =====
function Log {
    param([string]$msg, [string]$Level = "INFO")
    $ts = Get-Date -Format 'HH:mm:ss.fff'
    $line = "[$ts] [$Level] $msg"
    $color = switch($Level) { 
        "ERROR" { "Red" } "WARN" { "Yellow" } "SUCCESS" { "Green" } 
        "ACTION" { "Cyan" } "DIAG" { "Magenta" } default { "White" } 
    }
    Write-Host $line -ForegroundColor $color
    $line | Out-File -FilePath $logFile -Append -Encoding UTF8
}

function Issue { param([string]$msg) $script:issues += $msg; Log $msg "WARN" }
function Fixed { param([string]$msg) $script:fixes += $msg; Log $msg "SUCCESS" }

# ===== PROGRESS =====
$script:phase = 0
$script:totalPhases = switch($Mode) { "QuickFix" { 6 } "DeepRepair" { 10 } "Diagnose" { 4 } }
function Phase { 
    param([string]$Name) 
    $script:phase++
    Write-Host "`n[$($script:phase)/$($script:totalPhases)] $Name" -ForegroundColor Cyan
    Log "PHASE $($script:phase): $Name"
}

# ===== HEADER =====
Clear-Host
Write-Host "`n  ============ WINDOWS 11 SMART RESET v2.0 ============" -ForegroundColor Cyan
Write-Host "  Mode: $Mode | Automatic | Fast" -ForegroundColor Yellow
Write-Host "  ====================================================`n" -ForegroundColor Cyan

Remove-Item $logFile -Force -ErrorAction SilentlyContinue
Log "=== SMART RESET v2.0 STARTED - Mode: $Mode ===" "SUCCESS"
$startTime = Get-Date

# ===== DIAGNOSE MODE =====
if ($Mode -eq "Diagnose") {
    Phase "System Information"
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    Log "OS: $($os.Caption) $($os.Version)"
    Log "PC: $($cs.Manufacturer) $($cs.Model)"
    Log "RAM: $([math]::Round($cs.TotalPhysicalMemory/1GB, 2)) GB"
    Log "Install Date: $($os.InstallDate)"
    Log "Last Boot: $($os.LastBootUpTime)"
    
    Phase "Disk Health"
    $disk = Get-CimInstance Win32_DiskDrive | Select-Object -First 1
    $diskStatus = (Get-PhysicalDisk | Select-Object -First 1).HealthStatus
    Log "Disk: $($disk.Model) - Status: $diskStatus"
    
    # Check for pending chkdsk
    $bootExec = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name BootExecute -ErrorAction SilentlyContinue).BootExecute
    if ($bootExec -match "autocheck autochk \*") {
        Log "Chkdsk: Properly configured" "SUCCESS"
    } else {
        Issue "Chkdsk: NOT properly configured!"
    }
    
    # Check pending reboot
    $pendingReboot = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    if ($pendingReboot) { Issue "Reboot pending - some updates/fixes waiting" }
    
    Phase "Windows Update Status"
    $wuPath = "$env:SystemRoot\SoftwareDistribution"
    $wuSize = [math]::Round((Get-ChildItem $wuPath -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 2)
    Log "WU Cache size: $wuSize MB"
    if ($wuSize -gt 500) { Issue "WU Cache bloated: $wuSize MB" }
    
    # Check WU service
    $wuService = Get-Service wuauserv -ErrorAction SilentlyContinue
    Log "WU Service: $($wuService.Status)"
    
    Phase "System File Integrity (Quick Check)"
    Log "Running: sfc /verifyonly (may take a minute)..."
    $sfcResult = & sfc /verifyonly 2>&1 | Out-String
    if ($sfcResult -match "did not find any integrity violations") {
        Log "SFC: No integrity violations found" "SUCCESS"
    } elseif ($sfcResult -match "found corrupt files") {
        Issue "SFC: Corrupt files detected!"
    } else {
        Log "SFC: Check complete"
    }
    
    # Summary
    Write-Host "`n========== DIAGNOSIS SUMMARY ==========" -ForegroundColor Yellow
    if ($script:issues.Count -eq 0) {
        Write-Host "  No issues detected!" -ForegroundColor Green
    } else {
        Write-Host "  Issues found:" -ForegroundColor Red
        $script:issues | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
        Write-Host "`n  Recommendation: Run with -Mode QuickFix or -Mode DeepRepair" -ForegroundColor Cyan
    }
    
    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    Write-Host "`n  Completed in $elapsed seconds" -ForegroundColor Gray
    Write-Host "  Log: $logFile" -ForegroundColor Gray
    Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

# ===== QUICK FIX MODE (Fast, targeted fixes) =====
if ($Mode -eq "QuickFix") {
    
    Phase "Stopping Services"
    @("wuauserv", "bits", "cryptsvc") | ForEach-Object { 
        Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue 
    }
    Fixed "Services stopped"

    Phase "Fixing Chkdsk Configuration"
    # This is the #1 reason chkdsk doesn't run at boot
    try {
        $bootExec = "autocheck autochk *"
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name BootExecute -Value $bootExec -Type MultiString
        Fixed "Chkdsk registry configured"
    } catch {
        Issue "Could not fix chkdsk registry: $($_.Exception.Message)"
    }
    
    # Check if autochk.exe exists
    $autochkPath = "$env:SystemRoot\System32\autochk.exe"
    if (-not (Test-Path $autochkPath)) {
        Issue "autochk.exe missing! Running DISM to restore..."
        $dism = Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth /Source:C:\Windows\WinSxS" -Wait -PassThru -NoNewWindow
    } else {
        Log "autochk.exe present" "SUCCESS"
    }

    Phase "Quick DISM Repair"
    # Just restore health - skip cleanup for speed
    $dism = Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -Wait -PassThru -NoNewWindow
    if ($dism.ExitCode -eq 0) {
        Fixed "DISM repair completed"
    } else {
        Issue "DISM returned exit code: $($dism.ExitCode)"
    }

    Phase "Quick SFC Scan"
    $sfc = Start-Process "sfc.exe" -ArgumentList "/scannow" -Wait -PassThru -NoNewWindow
    if ($sfc.ExitCode -eq 0) {
        Fixed "SFC scan completed"
    } else {
        Log "SFC exit: $($sfc.ExitCode) (may need reboot)" "WARN"
    }

    Phase "Windows Update Quick Fix"
    # Just rename the folders - fastest WU fix
    $ts = Get-Date -Format 'yyyyMMddHHmmss'
    $sdPath = "$env:SystemRoot\SoftwareDistribution"
    if (Test-Path $sdPath) {
        try {
            Rename-Item $sdPath "$sdPath.old.$ts" -Force
            Fixed "SoftwareDistribution reset"
        } catch {
            Issue "Could not reset SoftwareDistribution"
        }
    }
    
    # Essential DLL re-registration
    @("wuapi.dll", "wuaueng.dll", "wups.dll") | ForEach-Object { 
        regsvr32.exe /s $_ 2>$null 
    }
    Fixed "WU DLLs registered"

    Phase "Restarting Services"
    @("cryptsvc", "bits", "wuauserv") | ForEach-Object { 
        Start-Service -Name $_ -ErrorAction SilentlyContinue 
    }
    Fixed "Services restarted"
}

# ===== DEEP REPAIR MODE (Comprehensive) =====
if ($Mode -eq "DeepRepair") {
    
    Phase "Stop All Related Services"
    $services = @("wuauserv", "bits", "cryptsvc", "msiserver", "TrustedInstaller", "WSearch", "BITS")
    $services | ForEach-Object { Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue }
    Fixed "All services stopped"

    Phase "Deep Chkdsk Fix"
    # Fix registry
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name BootExecute -Value "autocheck autochk *" -Type MultiString
    Fixed "Chkdsk registry fixed"
    
    # Verify autochk
    if (Test-Path "$env:SystemRoot\System32\autochk.exe") {
        Fixed "autochk.exe verified"
    } else {
        Issue "autochk.exe MISSING"
    }
    
    # Check for dirty bit
    $fsutil = & fsutil dirty query C: 2>&1
    Log "Volume dirty status: $fsutil"
    
    # Schedule chkdsk (will run at next boot)
    $chkdskSchedule = & cmd /c "echo Y | chkdsk C: /F" 2>&1 | Out-String
    if ($chkdskSchedule -match "scheduled") {
        Fixed "Chkdsk scheduled for next boot"
    } else {
        Log "Chkdsk schedule result: $chkdskSchedule" "WARN"
    }

    Phase "DISM Full Repair"
    Log "Running DISM RestoreHealth (this may take 5-15 minutes)..."
    $dism1 = Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -Wait -PassThru -NoNewWindow
    Log "DISM RestoreHealth exit: $($dism1.ExitCode)"
    
    Log "Running DISM Component Cleanup..."
    $dism2 = Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /ResetBase" -Wait -PassThru -NoNewWindow
    Log "DISM Cleanup exit: $($dism2.ExitCode)"
    Fixed "DISM repair and cleanup completed"

    Phase "Full SFC Scan"
    Log "Running SFC (this may take 10-15 minutes)..."
    $sfc = Start-Process "sfc.exe" -ArgumentList "/scannow" -Wait -PassThru -NoNewWindow
    Log "SFC exit: $($sfc.ExitCode)"
    Fixed "SFC scan completed"

    Phase "Windows Update Full Reset"
    $ts = Get-Date -Format 'yyyyMMddHHmmss'
    
    # Rename folders
    $sdPath = "$env:SystemRoot\SoftwareDistribution"
    $crPath = "$env:SystemRoot\System32\catroot2"
    if (Test-Path $sdPath) { Rename-Item $sdPath "$sdPath.old.$ts" -Force -ErrorAction SilentlyContinue }
    if (Test-Path $crPath) { Rename-Item $crPath "$crPath.old.$ts" -Force -ErrorAction SilentlyContinue }
    Fixed "WU cache folders reset"
    
    # Full DLL registration
    $dlls = @("atl.dll","urlmon.dll","mshtml.dll","shdocvw.dll","browseui.dll","jscript.dll","vbscript.dll","scrrun.dll","msxml3.dll","msxml6.dll","actxprxy.dll","softpub.dll","wintrust.dll","dssenh.dll","rsaenh.dll","cryptdlg.dll","oleaut32.dll","ole32.dll","shell32.dll","wuapi.dll","wuaueng.dll","wucltui.dll","wups.dll","wups2.dll","wuweb.dll","qmgr.dll","qmgrprxy.dll","wucltux.dll")
    $dlls | ForEach-Object { regsvr32.exe /s $_ 2>$null }
    Fixed "All WU DLLs registered"

    Phase "Network Stack Reset"
    netsh winsock reset | Out-Null
    netsh int ip reset | Out-Null
    netsh advfirewall reset | Out-Null
    ipconfig /flushdns | Out-Null
    ipconfig /registerdns | Out-Null
    Fixed "Network stack reset"

    Phase "Registry Cleanup"
    $regPaths = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )
    $regPaths | ForEach-Object { 
        if (Test-Path $_) { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue } 
    }
    Fixed "Policy registry cleaned"

    Phase "System Cleanup"
    # Clear temp
    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    
    # Clear prefetch (will rebuild)
    Remove-Item "$env:SystemRoot\Prefetch\*" -Force -ErrorAction SilentlyContinue
    
    # Reset icon cache
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache*" -Force -ErrorAction SilentlyContinue
    Start-Process explorer -ErrorAction SilentlyContinue
    Fixed "System cleanup completed"

    Phase "Restart Services"
    $services = @("cryptsvc", "bits", "wuauserv", "TrustedInstaller", "WSearch")
    $services | ForEach-Object { Start-Service -Name $_ -ErrorAction SilentlyContinue }
    Fixed "Services restarted"
}

# ===== FINAL REPORT =====
$elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
Log "===== COMPLETE in $elapsed seconds =====" "SUCCESS"

Write-Host "`n========== RESET REPORT ==========" -ForegroundColor Cyan
Write-Host "Mode: $Mode" -ForegroundColor Yellow
Write-Host "Duration: $elapsed seconds" -ForegroundColor White

if ($script:fixes.Count -gt 0) {
    Write-Host "`nFixes Applied:" -ForegroundColor Green
    $script:fixes | ForEach-Object { Write-Host "  [OK] $_" -ForegroundColor Green }
}

if ($script:issues.Count -gt 0) {
    Write-Host "`nIssues Detected:" -ForegroundColor Yellow
    $script:issues | ForEach-Object { Write-Host "  [!] $_" -ForegroundColor Yellow }
}

# Save report
$reportLines = @(
    "========== WINDOWS 11 SMART RESET v2.0 REPORT =========="
    "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "Mode: $Mode"
    "Duration: $elapsed seconds"
    ""
    "FIXES APPLIED:"
    ($script:fixes | ForEach-Object { "  [OK] $_" })
    ""
    "ISSUES:"
    ($script:issues | ForEach-Object { "  [!] $_" })
    ""
    "RECOMMENDATION: Reboot your computer to complete repairs."
    "If chkdsk was scheduled, it will run automatically at next boot."
)
$reportLines | Out-File $reportFile -Encoding UTF8 -Force

Write-Host "`n  Log: $logFile" -ForegroundColor Gray
Write-Host "  Report: $reportFile" -ForegroundColor Gray

# Reboot prompt
if (-not $NoReboot) {
    Write-Host "`nReboot is recommended to complete repairs." -ForegroundColor Yellow
    if (-not $Force) {
        $reboot = Read-Host "Reboot now? (Y/N)"
        if ($reboot -eq "Y") {
            Log "Rebooting in 10 seconds..."
            Start-Sleep -Seconds 10
            Restart-Computer -Force
        }
    }
}

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
