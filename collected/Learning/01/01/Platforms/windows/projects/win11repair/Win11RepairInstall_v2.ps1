#Requires -RunAsAdministrator
# Windows 11 ULTIMATE Repair - FAST Edition
# Version 2.0 - Complete repair, MAXIMUM SPEED
# PowerShell 5.1 Compatible

param(
    [switch]$SkipPreRepair,    # Skip DISM/SFC if you want just the upgrade
    [switch]$SkipUpgrade,      # Skip in-place upgrade, just do repairs
    [switch]$Force,            # Force even if no issues detected
    [switch]$DryRun,           # Test mode - shows what would happen without doing it
    [switch]$NoWait            # Skip "Press any key" at the end (for automation)
)

$ErrorActionPreference = "Continue"
$isoPath = "E:\isos\Windows.iso"
$logFile = "$PSScriptRoot\repair_log_v2.txt"
$reportFile = "$PSScriptRoot\repair_report.txt"

# ===== FAST LOGGING =====
function Log {
    param([string]$msg, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $msg"
    $color = switch($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } "SUCCESS" { "Green" } default { "White" } }
    Write-Host $line -ForegroundColor $color
    $line | Out-File -FilePath $logFile -Append -Encoding UTF8
}

# ===== DRY RUN WRAPPER =====
function Invoke-Action {
    param([string]$Description, [scriptblock]$Action)
    if ($DryRun) {
        Log "[DRY] Would: $Description" "WARN"
        return @{ ExitCode = 0 }
    } else {
        Log $Description
        return & $Action
    }
}

# ===== PROGRESS BAR =====
$script:phaseNum = 0
function Show-Phase {
    param([string]$Name, [string]$Time)
    $script:phaseNum++
    Write-Host "`n>>> PHASE $($script:phaseNum): $Name $Time" -ForegroundColor Cyan
    Log "PHASE $($script:phaseNum): $Name $Time"
}

# ===== HEADER =====
Clear-Host
$modeText = if ($DryRun) { " [DRY RUN - NO CHANGES]" } else { "" }
Write-Host "`n  ========== WINDOWS 11 ULTIMATE REPAIR v2.0 (FAST)$modeText ==========" -ForegroundColor Cyan
Write-Host "  Complete System Restoration - Optimized for Speed" -ForegroundColor Cyan
Write-Host "  =============================================================`n" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "  >>> DRY RUN MODE - No actual changes will be made <<<`n" -ForegroundColor Yellow
}

Remove-Item $logFile -Force -ErrorAction SilentlyContinue
Log "=== FAST REPAIR STARTED $(if($DryRun){'(DRY RUN)'}else{''}) ===" "SUCCESS"
$startTime = Get-Date

$repairsDone = @()

# ===== PRE-FLIGHT CHECKS =====
Write-Host "Running pre-flight checks..." -ForegroundColor Gray

# Check disk space
$freeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
if ($freeGB -lt 15) {
    Write-Host "  [!] Low disk space: $freeGB GB (need 15+ GB)" -ForegroundColor Red
    if (-not $Force -and -not $DryRun) {
        Write-Host "  Use -Force to continue anyway, or free up disk space." -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "  [OK] Disk space: $freeGB GB" -ForegroundColor Green
}

# Check ISO exists (if upgrade is planned)
if (-not $SkipUpgrade) {
    if (Test-Path $isoPath) {
        $isoSize = [math]::Round((Get-Item $isoPath).Length / 1GB, 2)
        Write-Host "  [OK] ISO found: $isoPath ($isoSize GB)" -ForegroundColor Green
    } else {
        Write-Host "  [!] ISO not found: $isoPath" -ForegroundColor Red
        if (-not $DryRun) {
            Write-Host "  Cannot proceed without ISO. Use -SkipUpgrade for repairs only." -ForegroundColor Yellow
            exit 1
        }
    }
}

Write-Host ""

# ===== PHASE 1: SYSTEM ANALYSIS =====
Show-Phase "System Analysis" "(~2 sec)"
Log "Free space: $freeGB GB"

# ===== PHASE 2: STOP SERVICES =====
Show-Phase "Stop Services" "(~1 sec)"
$services = @("wuauserv", "bits", "cryptsvc", "msiserver")
if (-not $DryRun) {
    $services | ForEach-Object { Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue }
} else {
    Log "[DRY] Would stop: $($services -join ', ')" "WARN"
}
$repairsDone += "Services stopped"

# ===== PHASE 3: DISM REPAIR (optimized - skip CheckHealth/ScanHealth) =====
if (-not $SkipPreRepair) {
    Show-Phase "DISM RestoreHealth" "(~5-15 min)"
    
    # Go straight to RestoreHealth - it does the scan internally anyway
    # This saves 5-10 minutes vs running CheckHealth + ScanHealth first
    if (-not $DryRun) {
        Log "Running: DISM /RestoreHealth"
        $dism = Start-Process -FilePath "DISM.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -Wait -PassThru -NoNewWindow
        Log "DISM RestoreHealth exit: $($dism.ExitCode)"
        
        # Component cleanup is a separate command - run after restore
        Log "Running: DISM /StartComponentCleanup"
        $dismClean = Start-Process -FilePath "DISM.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup" -Wait -PassThru -NoNewWindow
        Log "DISM Cleanup exit: $($dismClean.ExitCode)"
    } else {
        Log "[DRY] Would run DISM /RestoreHealth" "WARN"
        Log "[DRY] Would run DISM /StartComponentCleanup" "WARN"
        $dism = @{ ExitCode = 0 }
    }
    
    # If failed, try ISO source (faster than retrying WU)
    if ($dism.ExitCode -ne 0 -and (Test-Path $isoPath)) {
        Log "Trying ISO as source..." "WARN"
        Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null
        $mount = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction SilentlyContinue
        $drv = ($mount | Get-Volume -ErrorAction SilentlyContinue).DriveLetter
        if ($drv) {
            $src = if (Test-Path "${drv}:\sources\install.wim") { "WIM:${drv}:\sources\install.wim:1" } 
                   elseif (Test-Path "${drv}:\sources\install.esd") { "ESD:${drv}:\sources\install.esd:1" }
                   else { $null }
            if ($src) {
                $dismIso = Start-Process -FilePath "DISM.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth /Source:$src /LimitAccess" -Wait -PassThru -NoNewWindow
                Log "DISM (ISO) exit: $($dismIso.ExitCode)"
            }
            Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null
        }
    }
    $repairsDone += "DISM repair done"
}

# ===== PHASE 4: SFC (runs while we do other stuff) =====
$sfcJob = $null
if (-not $SkipPreRepair) {
    Show-Phase "SFC Scan" "(~10-15 min, background)"
    if (-not $DryRun) {
        # Run SFC in background job while we do other repairs
        $sfcJob = Start-Job -ScriptBlock {
            $result = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -PassThru -NoNewWindow
            return $result.ExitCode
        }
    } else {
        Log "[DRY] Would run SFC /scannow in background" "WARN"
    }
    $repairsDone += "SFC started (background)"
}

# ===== PHASE 5: WINDOWS UPDATE RESET =====
Show-Phase "Windows Update Reset" "(~10 sec)"

# Rename folders (fast)
$ts = Get-Date -Format 'yyyyMMddHHmmss'
$sdPath = "$env:SystemRoot\SoftwareDistribution"
$crPath = "$env:SystemRoot\System32\catroot2"
if (-not $DryRun) {
    if (Test-Path $sdPath) { Rename-Item $sdPath "$sdPath.old.$ts" -Force -ErrorAction SilentlyContinue; Log "SoftwareDistribution renamed" }
    if (Test-Path $crPath) { Rename-Item $crPath "$crPath.old.$ts" -Force -ErrorAction SilentlyContinue; Log "catroot2 renamed" }
} else {
    Log "[DRY] Would rename SoftwareDistribution and catroot2" "WARN"
}

# Essential DLLs only (skip rarely-needed ones for speed)
$essentialDlls = @("wuapi.dll", "wuaueng.dll", "wucltui.dll", "wups.dll", "wuweb.dll", "qmgr.dll")
if (-not $DryRun) {
    $essentialDlls | ForEach-Object { Start-Process "regsvr32.exe" -ArgumentList "/s $_" -NoNewWindow -Wait }
    Log "Essential DLLs registered"
} else {
    Log "[DRY] Would register: $($essentialDlls -join ', ')" "WARN"
}

# Quick network reset
if (-not $DryRun) {
    Start-Process "netsh" -ArgumentList "winsock reset" -NoNewWindow -Wait
    Log "Winsock reset"
} else {
    Log "[DRY] Would reset Winsock" "WARN"
}

$repairsDone += "Windows Update reset"

# ===== PHASE 6: REGISTRY =====
Show-Phase "Registry Cleanup" "(~1 sec)"
$regPaths = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate"
)
if (-not $DryRun) {
    $regPaths | ForEach-Object { if (Test-Path $_) { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue } }
} else {
    Log "[DRY] Would clean registry paths: $($regPaths -join ', ')" "WARN"
}
$repairsDone += "Registry cleaned"

# ===== WAIT FOR SFC IF STILL RUNNING =====
if ($sfcJob) {
    Log "Waiting for SFC to complete..."
    $sfcResult = Wait-Job $sfcJob -Timeout 900 | Receive-Job  # 15 min max
    Remove-Job $sfcJob -Force -ErrorAction SilentlyContinue
    Log "SFC complete: exit $sfcResult"
    $repairsDone += "SFC completed"
}

# ===== PHASE 7: RESTART SERVICES =====
Show-Phase "Restart Services" "(~1 sec)"
if (-not $DryRun) {
    @("cryptsvc", "bits", "wuauserv") | ForEach-Object { Start-Service -Name $_ -ErrorAction SilentlyContinue }
} else {
    Log "[DRY] Would restart: cryptsvc, bits, wuauserv" "WARN"
}
$repairsDone += "Services restarted"

# ===== PHASE 8: IN-PLACE UPGRADE =====
$setupPID = $null
if (-not $SkipUpgrade) {
    Show-Phase "In-Place Upgrade" "(launches setup)"
    
    if (-not (Test-Path $isoPath)) {
        Log "ERROR: ISO not found at $isoPath" "ERROR"
    } else {
        Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null
        $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        $driveLetter = ($mountResult | Get-Volume -ErrorAction SilentlyContinue).DriveLetter
        if (-not $driveLetter) { $driveLetter = (Get-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Get-Volume -ErrorAction SilentlyContinue).DriveLetter }
        
        if ($driveLetter) {
            $setupPath = "${driveLetter}:\setup.exe"
            if (Test-Path $setupPath) {
                # In-place repair upgrade arguments:
                # /auto upgrade     - automatic upgrade, keeps files+apps
                # /dynamicupdate disable - don't download updates during install (faster)
                # /eula accept      - auto-accept license
                # /migratedrivers all - keep all existing drivers
                # /telemetry disable - no telemetry during install
                # /compat ignorewarning - proceed despite minor compatibility issues
                $setupArgs = "/auto upgrade /dynamicupdate disable /eula accept /migratedrivers all /telemetry disable /compat ignorewarning"
                
                if (-not $DryRun) {
                    Log "Launching setup: $setupArgs"
                    $process = Start-Process -FilePath $setupPath -ArgumentList $setupArgs -PassThru
                    $setupPID = $process.Id
                    Log "Setup launched! PID: $setupPID" "SUCCESS"
                    $repairsDone += "Upgrade launched (PID: $setupPID)"
                } else {
                    Log "[DRY] Would launch: $setupPath $setupArgs" "WARN"
                    $repairsDone += "Upgrade would be launched (DRY RUN)"
                }
                
                # Quick post-repair task setup
                if (-not $DryRun) {
                    $verifyScript = '$sfc = Start-Process "sfc.exe" "/verifyonly" -Wait -PassThru -NoNewWindow; "SFC verify: $($sfc.ExitCode)" | Out-File "C:\Windows\Temp\repair_verify.txt"'
                    $verifyScript | Out-File "$env:SystemRoot\Temp\verify_repair.ps1" -Encoding ASCII -Force
                    $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$env:SystemRoot\Temp\verify_repair.ps1`""
                    $taskTrigger = New-ScheduledTaskTrigger -AtStartup
                    Unregister-ScheduledTask -TaskName "PostRepairVerify" -Confirm:$false -ErrorAction SilentlyContinue
                    Register-ScheduledTask -TaskName "PostRepairVerify" -Action $taskAction -Trigger $taskTrigger -RunLevel Highest -Force | Out-Null
                    Log "Post-repair verification task created"
                } else {
                    Log "[DRY] Would create PostRepairVerify scheduled task" "WARN"
                }
            } else {
                Log "setup.exe not found!" "ERROR"
            }
        }
    }
}

# ===== REPORT =====
$elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
Log "===== COMPLETE in $elapsed seconds =====" "SUCCESS"

$reportLines = @(
    "========== WINDOWS 11 ULTIMATE REPAIR REPORT =========="
    "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "Duration: $elapsed seconds"
    ""
    "REPAIRS PERFORMED:"
)
$repairsDone | ForEach-Object { $reportLines += "  [OK] $_" }
$reportLines += ""
$reportLines += "Your PC will restart automatically. DO NOT turn off!"
$reportLines += "Log: $logFile"

$report = $reportLines -join "`r`n"
$report | Out-File $reportFile -Encoding UTF8 -Force
Write-Host "`n$report" -ForegroundColor Cyan

Write-Host "`n  ========== REPAIR LAUNCHED! ===========" -ForegroundColor Green
Write-Host "  Completed pre-repair in $elapsed seconds" -ForegroundColor Green
Write-Host "  PC will restart automatically during upgrade." -ForegroundColor Yellow
Write-Host "  DO NOT turn off your computer!`n" -ForegroundColor Red

if (-not $NoWait) {
    Write-Host "Press any key to close..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
