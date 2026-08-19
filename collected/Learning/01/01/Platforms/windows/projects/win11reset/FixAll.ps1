#Requires -RunAsAdministrator
# Windows 11 FIX ALL - Complete System Repair
# The nuclear option - runs everything

param(
    [switch]$Force,
    [switch]$NoReboot,
    [switch]$Silent  # For scheduled tasks
)

$ErrorActionPreference = "Continue"
$logFile = "$PSScriptRoot\fixall_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

function Log {
    param([string]$msg, [string]$Level = "INFO")
    $ts = Get-Date -Format 'HH:mm:ss'
    $line = "[$ts] [$Level] $msg"
    if (-not $Silent) {
        $color = switch($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } "SUCCESS" { "Green" } "PHASE" { "Cyan" } default { "White" } }
        Write-Host $line -ForegroundColor $color
    }
    $line | Out-File -FilePath $logFile -Append -Encoding UTF8
}

$script:phase = 0
function Phase { 
    param([string]$Name, [string]$Time) 
    $script:phase++
    Log "=== PHASE $($script:phase): $Name ($Time) ===" "PHASE"
}

# Header
if (-not $Silent) {
    Clear-Host
    Write-Host "`n  ============ FIX ALL - NUCLEAR OPTION ============" -ForegroundColor Red
    Write-Host "  Complete system repair - this will take 20-30 minutes" -ForegroundColor Yellow
    Write-Host "  ===================================================`n" -ForegroundColor Red
}

Log "=== FIX ALL STARTED ===" "SUCCESS"
$startTime = Get-Date

# PHASE 1: Stop all services
Phase "Stop Services" "30s"
$services = @("wuauserv", "bits", "cryptsvc", "msiserver", "TrustedInstaller", "WSearch", "BITS", "dosvc")
$services | ForEach-Object { 
    Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue 
    Log "Stopped: $_"
}

# PHASE 2: Chkdsk Fix
Phase "Chkdsk Configuration" "1m"
Log "Fixing BootExecute registry..."
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name BootExecute -Value "autocheck autochk *" -Type MultiString -ErrorAction SilentlyContinue

# Verify autochk.exe
$autochkPath = "$env:SystemRoot\System32\autochk.exe"
if (Test-Path $autochkPath) {
    Log "autochk.exe present" "SUCCESS"
} else {
    Log "autochk.exe MISSING - will restore via DISM" "WARN"
}

# Schedule chkdsk
Log "Scheduling chkdsk for next boot..."
& cmd /c "echo Y | chkdsk C: /F" 2>&1 | Out-Null
Log "Chkdsk scheduled"

# PHASE 3: DISM Repairs
Phase "DISM Repair" "10-15m"
Log "Running DISM RestoreHealth..."
$dism1 = Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -Wait -PassThru -NoNewWindow
Log "DISM RestoreHealth exit: $($dism1.ExitCode)"

Log "Running DISM StartComponentCleanup..."
$dism2 = Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup" -Wait -PassThru -NoNewWindow
Log "DISM Cleanup exit: $($dism2.ExitCode)"

Log "Running DISM AnalyzeComponentStore..."
$dism3 = Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /AnalyzeComponentStore" -Wait -PassThru -NoNewWindow
Log "DISM Analyze exit: $($dism3.ExitCode)"

# PHASE 4: SFC
Phase "SFC Scan" "10-15m"
Log "Running SFC /scannow..."
$sfc = Start-Process "sfc.exe" -ArgumentList "/scannow" -Wait -PassThru -NoNewWindow
Log "SFC exit: $($sfc.ExitCode)"

# PHASE 5: Windows Update Reset
Phase "Windows Update Reset" "2m"
$ts = Get-Date -Format 'yyyyMMddHHmmss'

# Rename cache folders
$sdPath = "$env:SystemRoot\SoftwareDistribution"
$crPath = "$env:SystemRoot\System32\catroot2"
if (Test-Path $sdPath) { Rename-Item $sdPath "$sdPath.old.$ts" -Force -ErrorAction SilentlyContinue; Log "SoftwareDistribution renamed" }
if (Test-Path $crPath) { Rename-Item $crPath "$crPath.old.$ts" -Force -ErrorAction SilentlyContinue; Log "catroot2 renamed" }

# Re-register all DLLs
$dlls = @(
    "atl.dll","urlmon.dll","mshtml.dll","shdocvw.dll","browseui.dll","jscript.dll","vbscript.dll",
    "scrrun.dll","msxml.dll","msxml3.dll","msxml6.dll","actxprxy.dll","softpub.dll","wintrust.dll",
    "dssenh.dll","rsaenh.dll","gpkcsp.dll","sccbase.dll","slbcsp.dll","cryptdlg.dll","oleaut32.dll",
    "ole32.dll","shell32.dll","initpki.dll","wuapi.dll","wuaueng.dll","wuaueng1.dll","wucltui.dll",
    "wups.dll","wups2.dll","wuweb.dll","qmgr.dll","qmgrprxy.dll","wucltux.dll","muweb.dll","wuwebv.dll"
)
Log "Registering $($dlls.Count) DLLs..."
$dlls | ForEach-Object { regsvr32.exe /s $_ 2>$null }
Log "DLLs registered"

# Reset BITS
Log "Resetting BITS..."
bitsadmin /reset /allusers 2>&1 | Out-Null

# PHASE 6: Network Reset
Phase "Network Stack Reset" "1m"
Log "Resetting Winsock..."
netsh winsock reset 2>&1 | Out-Null
Log "Resetting IP stack..."
netsh int ip reset 2>&1 | Out-Null
Log "Resetting firewall..."
netsh advfirewall reset 2>&1 | Out-Null
Log "Flushing DNS..."
ipconfig /flushdns 2>&1 | Out-Null
ipconfig /registerdns 2>&1 | Out-Null
Log "Network reset complete"

# PHASE 7: Registry Cleanup
Phase "Registry Cleanup" "30s"
$regPaths = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
)
foreach ($path in $regPaths) {
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        Log "Removed: $path"
    }
}

# PHASE 8: System Cleanup
Phase "System Cleanup" "2m"
Log "Clearing temp files..."
Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
Log "Clearing prefetch..."
Remove-Item "$env:SystemRoot\Prefetch\*" -Force -ErrorAction SilentlyContinue
Log "Clearing Windows Update cache..."
Remove-Item "$env:SystemRoot\SoftwareDistribution.old.*" -Recurse -Force -ErrorAction SilentlyContinue
Log "Rebuilding icon cache..."
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache*" -Force -ErrorAction SilentlyContinue

# PHASE 9: Windows Repair
Phase "Windows Component Repair" "1m"
Log "Running Windows Component cleanup..."
Dism.exe /Online /Cleanup-Image /SPSuperseded 2>&1 | Out-Null

# PHASE 10: Restart Services
Phase "Restart Services" "30s"
$startServices = @("cryptsvc", "bits", "wuauserv", "TrustedInstaller", "WSearch", "dosvc")
$startServices | ForEach-Object { 
    Start-Service -Name $_ -ErrorAction SilentlyContinue 
    Log "Started: $_"
}
Start-Process explorer -ErrorAction SilentlyContinue

# PHASE 11: Verification Task
Phase "Setup Verification" "10s"
$verifyScript = @'
# Post-Fix Verification
$log = "C:\Windows\Temp\fixall_verify.txt"
"Verification started: $(Get-Date)" | Out-File $log
$sfc = Start-Process "sfc.exe" "/verifyonly" -Wait -PassThru -NoNewWindow
"SFC Verify exit: $($sfc.ExitCode)" | Out-File $log -Append
"Verification complete: $(Get-Date)" | Out-File $log -Append
Unregister-ScheduledTask -TaskName "PostFixAllVerify" -Confirm:$false -ErrorAction SilentlyContinue
'@
$verifyScript | Out-File "$env:SystemRoot\Temp\verify_fixall.ps1" -Encoding ASCII -Force
$taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$env:SystemRoot\Temp\verify_fixall.ps1`""
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
Unregister-ScheduledTask -TaskName "PostFixAllVerify" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "PostFixAllVerify" -Action $taskAction -Trigger $taskTrigger -RunLevel Highest -Force | Out-Null
Log "Verification task created"

# Complete
$elapsed = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
Log "=== FIX ALL COMPLETE in $elapsed minutes ===" "SUCCESS"

# Report
if (-not $Silent) {
    Write-Host "`n  ============ FIX ALL COMPLETE ============" -ForegroundColor Green
    Write-Host "  Duration: $elapsed minutes" -ForegroundColor Cyan
    Write-Host "  Log: $logFile" -ForegroundColor Gray
    Write-Host "`n  IMPORTANT:" -ForegroundColor Yellow
    Write-Host "  - Chkdsk will run at next boot (don't interrupt!)" -ForegroundColor Yellow
    Write-Host "  - Some fixes require a reboot to complete" -ForegroundColor Yellow
    Write-Host "  - Verification will run automatically after reboot" -ForegroundColor Yellow
    
    if (-not $NoReboot) {
        Write-Host "`n  Reboot now to complete repairs? (Y/N): " -NoNewline -ForegroundColor Cyan
        $reboot = Read-Host
        if ($reboot -eq "Y") {
            Log "Rebooting in 10 seconds..."
            Start-Sleep -Seconds 10
            Restart-Computer -Force
        }
    }
    
    Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
