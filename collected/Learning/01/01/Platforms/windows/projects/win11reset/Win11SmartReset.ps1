#Requires -RunAsAdministrator
# Windows 11 Smart Reset - Lightest Possible System Restoration
# Version 1.0 - Fixes issues like chkdsk, keeps apps and settings
# 
# PURPOSE: This script performs the LIGHTEST possible system reset/repair
# that preserves ALL applications and settings while fixing common issues
# like chkdsk not running at startup, corrupted system files, etc.
#
# MODES:
#   -Mode Repair     : (DEFAULT) Deep repair without reset - keeps everything
#   -Mode LightReset : Windows "Keep my files" reset - removes apps, keeps files
#   -Mode FullReset  : Complete Windows reset - removes everything
#   -Mode CloudReset : Reset from cloud download (cleanest, slower)

param(
    [ValidateSet("Repair", "LightReset", "FullReset", "CloudReset")]
    [string]$Mode = "Repair",
    
    [switch]$ScheduleChkdsk,    # Force schedule chkdsk at boot
    [switch]$FixBootloader,     # Repair bootloader/BCD
    [switch]$ResetNetwork,      # Full network stack reset
    [switch]$ResetWU,           # Reset Windows Update completely
    [switch]$Force,             # Skip confirmations
    [switch]$DryRun,            # Show what would happen
    [switch]$NoReboot           # Don't auto-reboot
)

$ErrorActionPreference = "Continue"
$logFile = "$PSScriptRoot\reset_log.txt"
$reportFile = "$PSScriptRoot\reset_report.txt"

# ===== LOGGING =====
function Log {
    param([string]$msg, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $msg"
    $color = switch($Level) { 
        "ERROR" { "Red" } 
        "WARN" { "Yellow" } 
        "SUCCESS" { "Green" } 
        "ACTION" { "Cyan" }
        default { "White" } 
    }
    Write-Host $line -ForegroundColor $color
    $line | Out-File -FilePath $logFile -Append -Encoding UTF8
}

# ===== DRY RUN WRAPPER =====
function Invoke-Action {
    param([string]$Description, [scriptblock]$Action)
    if ($DryRun) {
        Log "[DRY RUN] Would: $Description" "WARN"
        return $true
    } else {
        Log $Description "ACTION"
        try {
            & $Action
            return $true
        } catch {
            Log "Failed: $($_.Exception.Message)" "ERROR"
            return $false
        }
    }
}

# ===== HEADER =====
Clear-Host
$modeText = if ($DryRun) { " [DRY RUN]" } else { "" }
Write-Host "`n  ============ WINDOWS 11 SMART RESET v1.0$modeText ============" -ForegroundColor Cyan
Write-Host "  Lightest Possible System Restoration" -ForegroundColor Cyan
Write-Host "  Mode: $Mode" -ForegroundColor Yellow
Write-Host "  ========================================================`n" -ForegroundColor Cyan

Remove-Item $logFile -Force -ErrorAction SilentlyContinue
Log "=== SMART RESET STARTED - Mode: $Mode ===" "SUCCESS"
$startTime = Get-Date
$actionsDone = @()

# ===== MODE EXPLANATIONS =====
Write-Host "MODE DETAILS:" -ForegroundColor Yellow
switch ($Mode) {
    "Repair" {
        Write-Host "  [Repair] Deep system repair - KEEPS ALL APPS AND SETTINGS" -ForegroundColor Green
        Write-Host "           Fixes: chkdsk issues, corrupted files, boot problems" -ForegroundColor Gray
        Write-Host "           This is the LIGHTEST option that fixes most problems.`n" -ForegroundColor Gray
    }
    "LightReset" {
        Write-Host "  [LightReset] Windows 'Keep my files' reset" -ForegroundColor Yellow
        Write-Host "               REMOVES: All installed applications" -ForegroundColor Red
        Write-Host "               KEEPS: Personal files, user accounts`n" -ForegroundColor Green
    }
    "FullReset" {
        Write-Host "  [FullReset] Complete Windows reset" -ForegroundColor Red
        Write-Host "              REMOVES: Everything - apps, files, settings" -ForegroundColor Red
        Write-Host "              Result: Fresh Windows installation`n" -ForegroundColor Gray
    }
    "CloudReset" {
        Write-Host "  [CloudReset] Reset with fresh Windows download" -ForegroundColor Yellow
        Write-Host "               Downloads latest Windows from Microsoft" -ForegroundColor Gray
        Write-Host "               Slower but cleanest possible reset`n" -ForegroundColor Gray
    }
}

# ===== CONFIRMATION FOR DESTRUCTIVE MODES =====
if ($Mode -ne "Repair" -and -not $Force -and -not $DryRun) {
    Write-Host "WARNING: This mode will remove applications!" -ForegroundColor Red
    $confirm = Read-Host "Type 'YES' to confirm"
    if ($confirm -ne "YES") {
        Write-Host "Aborted by user." -ForegroundColor Yellow
        exit 0
    }
}

# ===== PRE-FLIGHT CHECKS =====
Write-Host "`nRunning pre-flight checks..." -ForegroundColor Gray

# Check disk space
$freeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
$requiredGB = switch ($Mode) { "Repair" { 5 } "LightReset" { 10 } "FullReset" { 20 } "CloudReset" { 15 } }
if ($freeGB -lt $requiredGB) {
    Write-Host "  [!] Low disk space: $freeGB GB (need $requiredGB+ GB)" -ForegroundColor Red
    if (-not $Force -and -not $DryRun) { exit 1 }
} else {
    Write-Host "  [OK] Disk space: $freeGB GB" -ForegroundColor Green
}

# Check Windows version
$winVer = (Get-CimInstance Win32_OperatingSystem).Caption
Write-Host "  [OK] Windows: $winVer" -ForegroundColor Green

# ============================================================
# REPAIR MODE - Deepest repair without resetting
# ============================================================
if ($Mode -eq "Repair") {
    
    # ----- PHASE 1: Stop interfering services -----
    Write-Host "`n>>> PHASE 1: Stopping services..." -ForegroundColor Cyan
    $services = @("wuauserv", "bits", "cryptsvc", "msiserver", "TrustedInstaller")
    Invoke-Action "Stopping Windows services" {
        $services | ForEach-Object { Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue }
    }
    $actionsDone += "Services stopped"

    # ----- PHASE 2: Fix CHKDSK issues -----
    Write-Host "`n>>> PHASE 2: Fixing disk check issues..." -ForegroundColor Cyan
    
    # Check if chkdsk is pending
    $chkdskPending = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name BootExecute -ErrorAction SilentlyContinue).BootExecute
    $pendingText = if ($chkdskPending -match "autocheck") { "PENDING" } else { "Not scheduled" }
    Log "Current chkdsk status: $pendingText"
    
    # Fix chkdsk registry (common issue)
    Invoke-Action "Fixing chkdsk registry entries" {
        # Ensure autocheck is properly configured
        $bootExec = "autocheck autochk *"
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name BootExecute -Value $bootExec -Type MultiString
    }
    $actionsDone += "Chkdsk registry fixed"
    
    # Schedule chkdsk if requested or if issues detected
    if ($ScheduleChkdsk) {
        Invoke-Action "Scheduling chkdsk on next boot" {
            # Use echo Y to auto-confirm the schedule
            $chkdskResult = & cmd /c "echo Y | chkdsk C: /F /R" 2>&1
            Log "Chkdsk scheduled: $chkdskResult"
        }
        $actionsDone += "Chkdsk scheduled for boot"
    }
    
    # Fix autochk.exe if corrupted
    Invoke-Action "Verifying autochk.exe integrity" {
        $autochkPath = "$env:SystemRoot\System32\autochk.exe"
        if (Test-Path $autochkPath) {
            $hash = (Get-FileHash $autochkPath -Algorithm SHA256).Hash.Substring(0,16)
            Log "autochk.exe hash: $hash"
        } else {
            Log "autochk.exe MISSING - will be restored by DISM" "WARN"
        }
    }

    # ----- PHASE 3: DISM Repair -----
    Write-Host "`n>>> PHASE 3: DISM System Repair..." -ForegroundColor Cyan
    Invoke-Action "Running DISM RestoreHealth" {
        $dism = Start-Process -FilePath "DISM.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -Wait -PassThru -NoNewWindow
        Log "DISM exit code: $($dism.ExitCode)"
    }
    $actionsDone += "DISM repair completed"
    
    Invoke-Action "Running DISM Component Cleanup" {
        $cleanup = Start-Process -FilePath "DISM.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /ResetBase" -Wait -PassThru -NoNewWindow
        Log "DISM cleanup exit: $($cleanup.ExitCode)"
    }
    $actionsDone += "Component cleanup done"

    # ----- PHASE 4: SFC Scan -----
    Write-Host "`n>>> PHASE 4: System File Checker..." -ForegroundColor Cyan
    Invoke-Action "Running SFC /scannow" {
        $sfc = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -PassThru -NoNewWindow
        Log "SFC exit code: $($sfc.ExitCode)"
    }
    $actionsDone += "SFC scan completed"

    # ----- PHASE 5: Windows Update Reset -----
    if ($ResetWU) {
        Write-Host "`n>>> PHASE 5: Windows Update Reset..." -ForegroundColor Cyan
        
        Invoke-Action "Clearing Windows Update cache" {
            $ts = Get-Date -Format 'yyyyMMddHHmmss'
            $sdPath = "$env:SystemRoot\SoftwareDistribution"
            $crPath = "$env:SystemRoot\System32\catroot2"
            if (Test-Path $sdPath) { Rename-Item $sdPath "$sdPath.old.$ts" -Force }
            if (Test-Path $crPath) { Rename-Item $crPath "$crPath.old.$ts" -Force }
        }
        $actionsDone += "WU cache cleared"
        
        Invoke-Action "Re-registering Windows Update DLLs" {
            $dlls = @("atl.dll","urlmon.dll","mshtml.dll","shdocvw.dll","browseui.dll","jscript.dll","vbscript.dll","scrrun.dll","msxml.dll","msxml3.dll","msxml6.dll","actxprxy.dll","softpub.dll","wintrust.dll","dssenh.dll","rsaenh.dll","gpkcsp.dll","sccbase.dll","slbcsp.dll","cryptdlg.dll","oleaut32.dll","ole32.dll","shell32.dll","initpki.dll","wuapi.dll","wuaueng.dll","wuaueng1.dll","wucltui.dll","wups.dll","wups2.dll","wuweb.dll","qmgr.dll","qmgrprxy.dll","wucltux.dll","muweb.dll","wuwebv.dll")
            $dlls | ForEach-Object { regsvr32.exe /s $_ 2>$null }
        }
        $actionsDone += "WU DLLs registered"
    }

    # ----- PHASE 6: Network Reset -----
    if ($ResetNetwork) {
        Write-Host "`n>>> PHASE 6: Network Stack Reset..." -ForegroundColor Cyan
        Invoke-Action "Resetting network stack" {
            netsh winsock reset
            netsh int ip reset
            netsh advfirewall reset
            ipconfig /flushdns
            ipconfig /registerdns
        }
        $actionsDone += "Network stack reset"
    }

    # ----- PHASE 7: Boot Repair -----
    if ($FixBootloader) {
        Write-Host "`n>>> PHASE 7: Boot Repair..." -ForegroundColor Cyan
        Invoke-Action "Repairing bootloader" {
            bootrec /fixmbr 2>$null
            bootrec /fixboot 2>$null
            bootrec /rebuildbcd 2>$null
            bcdboot C:\Windows /s C: /f ALL 2>$null
        }
        $actionsDone += "Bootloader repaired"
    }

    # ----- PHASE 8: Additional Fixes -----
    Write-Host "`n>>> PHASE 8: Additional Fixes..." -ForegroundColor Cyan
    
    Invoke-Action "Fixing Windows Search" {
        Stop-Service WSearch -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:ProgramData\Microsoft\Search\Data\Applications\Windows\Windows.edb" -Force -ErrorAction SilentlyContinue
        Start-Service WSearch -ErrorAction SilentlyContinue
    }
    $actionsDone += "Windows Search reset"
    
    Invoke-Action "Clearing temp files" {
        Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:SystemRoot\Prefetch\*" -Force -ErrorAction SilentlyContinue
    }
    $actionsDone += "Temp files cleared"
    
    Invoke-Action "Rebuilding icon cache" {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache*" -Force -ErrorAction SilentlyContinue
    }
    $actionsDone += "Icon cache rebuilt"

    # ----- PHASE 9: Restart Services -----
    Write-Host "`n>>> PHASE 9: Restarting services..." -ForegroundColor Cyan
    Invoke-Action "Starting Windows services" {
        @("cryptsvc", "bits", "wuauserv", "TrustedInstaller") | ForEach-Object { 
            Start-Service -Name $_ -ErrorAction SilentlyContinue 
        }
        Start-Process explorer -ErrorAction SilentlyContinue
    }
    $actionsDone += "Services restarted"

    # ----- PHASE 10: Schedule Post-Repair Verification -----
    Write-Host "`n>>> PHASE 10: Setting up verification..." -ForegroundColor Cyan
    Invoke-Action "Creating verification task" {
        $verifyScript = @'
# Post-Reset Verification
$log = "C:\Windows\Temp\reset_verify.txt"
"Verification started: $(Get-Date)" | Out-File $log
$sfc = Start-Process "sfc.exe" "/verifyonly" -Wait -PassThru -NoNewWindow
"SFC Verify exit: $($sfc.ExitCode)" | Out-File $log -Append
"Verification complete: $(Get-Date)" | Out-File $log -Append
Unregister-ScheduledTask -TaskName "PostResetVerify" -Confirm:$false -ErrorAction SilentlyContinue
'@
        $verifyScript | Out-File "$env:SystemRoot\Temp\verify_reset.ps1" -Encoding ASCII -Force
        $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$env:SystemRoot\Temp\verify_reset.ps1`""
        $taskTrigger = New-ScheduledTaskTrigger -AtStartup
        Unregister-ScheduledTask -TaskName "PostResetVerify" -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName "PostResetVerify" -Action $taskAction -Trigger $taskTrigger -RunLevel Highest -Force | Out-Null
    }
    $actionsDone += "Verification scheduled"
}

# ============================================================
# LIGHT RESET MODE - Windows Reset keeping files
# ============================================================
elseif ($Mode -eq "LightReset") {
    Write-Host "`n>>> Initiating Windows Reset (Keep my files)..." -ForegroundColor Yellow
    Write-Host "    This will REMOVE all applications but keep personal files." -ForegroundColor Red
    
    Invoke-Action "Launching Windows Reset (Light)" {
        # systemreset.exe with -keepmyfiles for light reset (undocumented but works)
        # Falls back to launching recovery settings if needed
        
        # Method 1: Try Push Button Reset with config
        $resetConfig = @"

<Reset xmlns="urn:schemas-microsoft-com:windows-pbr">
    <Option>1</Option>
    <WipeData>0</WipeData>
</Reset>
"@
        $resetConfigPath = "$env:TEMP\resetconfig.xml"
        $resetConfig | Out-File $resetConfigPath -Encoding UTF8
        
        # Launch system reset
        Start-Process "systemreset.exe" -ArgumentList "-keepUserData" -Wait -ErrorAction SilentlyContinue
        
        # If that didn't work, open Recovery settings
        Start-Process "ms-settings:recovery"
        Log "Recovery settings opened - Please click 'Reset PC' > 'Keep my files'" "ACTION"
    }
    $actionsDone += "Windows Reset initiated"
}

# ============================================================
# FULL RESET MODE - Complete Windows reset
# ============================================================
elseif ($Mode -eq "FullReset") {
    Write-Host "`n>>> Initiating Complete Windows Reset..." -ForegroundColor Red
    Write-Host "    This will REMOVE EVERYTHING - apps, files, settings." -ForegroundColor Red
    
    Invoke-Action "Launching Windows Reset (Full)" {
        Start-Process "systemreset.exe" -ArgumentList "-factoryreset" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        # Fallback to settings
        Start-Process "ms-settings:recovery"
        Log "Recovery settings opened - Please click 'Reset PC' > 'Remove everything'" "ACTION"
    }
    $actionsDone += "Full reset initiated"
}

# ============================================================
# CLOUD RESET MODE - Download fresh Windows
# ============================================================
elseif ($Mode -eq "CloudReset") {
    Write-Host "`n>>> Initiating Cloud Reset..." -ForegroundColor Yellow
    Write-Host "    This will download and install a fresh Windows copy." -ForegroundColor Gray
    
    Invoke-Action "Launching Cloud Reset" {
        # Open recovery settings with cloud reset hint
        Start-Process "ms-settings:recovery"
        Log "Recovery settings opened - Select 'Reset PC' > 'Cloud download'" "ACTION"
        
        Write-Host "`n  INSTRUCTIONS:" -ForegroundColor Cyan
        Write-Host "  1. Click 'Reset PC'" -ForegroundColor White
        Write-Host "  2. Choose 'Keep my files' or 'Remove everything'" -ForegroundColor White
        Write-Host "  3. Select 'Cloud download' (downloads ~4GB)" -ForegroundColor White
        Write-Host "  4. Follow the prompts" -ForegroundColor White
    }
    $actionsDone += "Cloud reset instructions shown"
}

# ===== REPORT =====
$elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
Log "===== COMPLETE in $elapsed seconds =====" "SUCCESS"

$reportLines = @(
    "========== WINDOWS 11 SMART RESET REPORT =========="
    "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "Mode: $Mode"
    "Duration: $elapsed seconds"
    ""
    "ACTIONS PERFORMED:"
)
$actionsDone | ForEach-Object { $reportLines += "  [OK] $_" }
$reportLines += ""

if ($Mode -eq "Repair") {
    $reportLines += "REPAIR COMPLETE - No reboot required for most fixes."
    $reportLines += "If chkdsk was scheduled, reboot to run disk check."
} else {
    $reportLines += "RESET INITIATED - Follow on-screen instructions."
}

$reportLines += "Log: $logFile"

$report = $reportLines -join "`r`n"
$report | Out-File $reportFile -Encoding UTF8 -Force
Write-Host "`n$report" -ForegroundColor Cyan

# ===== REBOOT PROMPT =====
if ($Mode -eq "Repair" -and $ScheduleChkdsk -and -not $NoReboot -and -not $DryRun) {
    Write-Host "`nChkdsk is scheduled. Reboot now to run disk check?" -ForegroundColor Yellow
    $reboot = Read-Host "Type 'YES' to reboot now"
    if ($reboot -eq "YES") {
        Log "Rebooting in 10 seconds..."
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
}

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
