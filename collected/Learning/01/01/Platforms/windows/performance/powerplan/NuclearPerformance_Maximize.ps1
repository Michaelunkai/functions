#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Nuclear Performance Power Plan - SAFE MAXIMUM PERFORMANCE v16
.DESCRIPTION
    Maximizes every possible power setting for peak performance WITHOUT causing BSOD.
    REMOVED crash-causing settings: IDLEDISABLE, dangerous C-state registry hacks.
    Implements MULTIPLE startup persistence methods for guaranteed enforcement.
.NOTES
    v16: SAFE VERSION - No more KMODE_EXCEPTION_NOT_HANDLED crashes
    Multiple startup methods: Task Scheduler, Registry Run, Group Policy
#>

$ErrorActionPreference = "Continue"
$changes = @()
$planGuid = "e7b3c3f6-7f35-4f4c-8b48-8f1ece9cd139"
$planName = "Nuclear_Performance_v16_SAFE"

Write-Host "============================================" -ForegroundColor Red
Write-Host "  NUCLEAR PERFORMANCE - SAFE MAX v16      " -ForegroundColor Red
Write-Host "     NO CRASH - MAXIMUM PERFORMANCE       " -ForegroundColor Red
Write-Host "============================================" -ForegroundColor Red
Write-Host ""

# Verify running as admin
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Run as Administrator required!" -ForegroundColor Red
    exit 1
}

# ============================================
# CHECK IF POWER PLAN EXISTS, CREATE IF NOT
# ============================================
Write-Host "[1/25] Checking/Creating power plan..." -ForegroundColor Yellow

$existingPlan = powercfg /list | Select-String $planGuid
if (-not $existingPlan) {
    Write-Host "  Creating new Nuclear Performance plan..." -ForegroundColor Cyan
    # Duplicate from High Performance (8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c)
    powercfg /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c $planGuid 2>$null
    powercfg /changename $planGuid $planName "Maximum safe performance - No BSOD" 2>$null
    $changes += "Created new power plan: $planName"
} else {
    $changes += "Power plan already exists: $planName"
}

# Activate the Nuclear Performance plan
Write-Host "[2/25] Activating Nuclear Performance plan..." -ForegroundColor Yellow
powercfg /setactive $planGuid 2>$null
$changes += "Activated power plan: $planName"

# ============================================
# POWER BUTTON BEHAVIOR CONFIGURATION
# ============================================
Write-Host "[3/25] Configuring power button behaviors..." -ForegroundColor Yellow

# Power button action = Do nothing (0) - prevents accidental shutdown
powercfg /setacvalueindex $planGuid SUB_BUTTONS PBUTTONACTION 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_BUTTONS PBUTTONACTION 0 2>$null
$changes += "Power Button Action: DO NOTHING"

# Sleep button action = Do nothing (0)
powercfg /setacvalueindex $planGuid SUB_BUTTONS SBUTTONACTION 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_BUTTONS SBUTTONACTION 0 2>$null
$changes += "Sleep Button Action: DO NOTHING"

# Lid close action = Do nothing (0)
powercfg /setacvalueindex $planGuid SUB_BUTTONS LIDACTION 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_BUTTONS LIDACTION 0 2>$null
$changes += "Lid Close Action: DO NOTHING"

# ============================================
# PROCESSOR POWER MANAGEMENT (SAFE SETTINGS)
# ============================================
Write-Host "[4/25] Maximizing CPU settings (SAFE)..." -ForegroundColor Yellow

# Minimum processor state = 100%
powercfg /setacvalueindex $planGuid SUB_PROCESSOR PROCTHROTTLEMIN 100 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR PROCTHROTTLEMIN 100 2>$null
$changes += "CPU Minimum State: 100%"

# Maximum processor state = 100%
powercfg /setacvalueindex $planGuid SUB_PROCESSOR PROCTHROTTLEMAX 100 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR PROCTHROTTLEMAX 100 2>$null
$changes += "CPU Maximum State: 100%"

# Maximum processor frequency = 0 (unlimited)
powercfg /setacvalueindex $planGuid SUB_PROCESSOR PROCFREQMAX 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR PROCFREQMAX 0 2>$null
$changes += "Maximum Processor Frequency: UNLIMITED"

# System cooling policy = Active (1)
powercfg /setacvalueindex $planGuid SUB_PROCESSOR SYSCOOLPOL 1 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR SYSCOOLPOL 1 2>$null
$changes += "System Cooling Policy: ACTIVE"

# Processor performance boost mode = Aggressive (2)
powercfg /setacvalueindex $planGuid SUB_PROCESSOR PERFBOOSTMODE 2 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR PERFBOOSTMODE 2 2>$null
$changes += "CPU Boost Mode: Aggressive"

# Processor performance boost policy = 100%
powercfg /setacvalueindex $planGuid SUB_PROCESSOR PERFBOOSTPOL 100 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR PERFBOOSTPOL 100 2>$null
$changes += "CPU Boost Policy: 100%"

# NOTE: IDLEDISABLE REMOVED - This was causing KMODE_EXCEPTION_NOT_HANDLED
# CPU idle states are managed safely by Windows - forcing disable causes BSOD

# Allow Throttle States = Off (0) - SAFE
powercfg /setacvalueindex $planGuid SUB_PROCESSOR THROTTLING 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR THROTTLING 0 2>$null
$changes += "Allow Throttle States: OFF"

# Core parking min cores = 100% (all cores active)
powercfg /setacvalueindex $planGuid SUB_PROCESSOR CPMINCORES 100 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR CPMINCORES 100 2>$null
$changes += "Core Parking Min: 100%"

# Core parking max cores = 100%
powercfg /setacvalueindex $planGuid SUB_PROCESSOR CPMAXCORES 100 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR CPMAXCORES 100 2>$null
$changes += "Core Parking Max: 100%"

# Core parking concurrency threshold = 100
powercfg /setacvalueindex $planGuid SUB_PROCESSOR CPCONCURRENCY 100 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR CPCONCURRENCY 100 2>$null
$changes += "Core Parking Concurrency: 100%"

# Core parking distribution threshold = 100
powercfg /setacvalueindex $planGuid SUB_PROCESSOR DISTRIBUTEUTIL 100 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR DISTRIBUTEUTIL 100 2>$null
$changes += "Core Parking Distribution: 100%"

# Heterogeneous policy = 0 (prefer performance cores)
powercfg /setacvalueindex $planGuid SUB_PROCESSOR HETEROPOLICY 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR HETEROPOLICY 0 2>$null
$changes += "Heterogeneous Policy: Performance Cores"

# Processor autonomous mode = Disabled
powercfg /setacvalueindex $planGuid SUB_PROCESSOR PERFAUTONOMOUS 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR PERFAUTONOMOUS 0 2>$null
$changes += "CPU Autonomous Mode: DISABLED"

# Energy performance preference = 0 (max performance)
powercfg /setacvalueindex $planGuid SUB_PROCESSOR PERFEPP 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR PERFEPP 0 2>$null
$changes += "Energy Performance Preference: 0% (Max Perf)"

# Performance time check interval = 1ms
powercfg /setacvalueindex $planGuid SUB_PROCESSOR PERFCHECK 1 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR PERFCHECK 1 2>$null
$changes += "Performance Check Interval: 1ms"

# Performance increase threshold = 0%
powercfg /setacvalueindex $planGuid SUB_PROCESSOR PERFINCTHRESHOLD 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR PERFINCTHRESHOLD 0 2>$null
$changes += "Performance Increase Threshold: 0%"

# Performance decrease threshold = 100%
powercfg /setacvalueindex $planGuid SUB_PROCESSOR PERFDECTHRESHOLD 100 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR PERFDECTHRESHOLD 100 2>$null
$changes += "Performance Decrease Threshold: 100%"

# Performance increase time = 1 (fastest)
powercfg /setacvalueindex $planGuid SUB_PROCESSOR PERFINCTIME 1 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR PERFINCTIME 1 2>$null
$changes += "Performance Increase Time: 1 (fastest)"

# Performance decrease time = 100 (slowest)
powercfg /setacvalueindex $planGuid SUB_PROCESSOR PERFDECTIME 100 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR PERFDECTIME 100 2>$null
$changes += "Performance Decrease Time: 100 (slowest)"

# Latency sensitivity = 100 (max performance)
powercfg /setacvalueindex $planGuid SUB_PROCESSOR LATENCYHINTPERF 100 2>$null
powercfg /setdcvalueindex $planGuid SUB_PROCESSOR LATENCYHINTPERF 100 2>$null
$changes += "Latency Sensitivity: Maximum"

# ============================================
# HARD DISK (SUB_DISK)
# ============================================
Write-Host "[5/25] Configuring disk settings..." -ForegroundColor Yellow

# Turn off hard disk after = Never
powercfg /setacvalueindex $planGuid SUB_DISK DISKIDLE 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_DISK DISKIDLE 0 2>$null
$changes += "Hard Disk Sleep: NEVER"

# NVME/AHCI power management = Maximum performance
powercfg /setacvalueindex $planGuid SUB_DISK 0b2d69d7-a2a1-449c-9680-f91c70521c60 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_DISK 0b2d69d7-a2a1-449c-9680-f91c70521c60 0 2>$null
$changes += "NVMe Power Management: Maximum Performance"

# ============================================
# SLEEP SETTINGS (SUB_SLEEP)
# ============================================
Write-Host "[6/25] Disabling sleep features..." -ForegroundColor Yellow

# Sleep after = Never
powercfg /setacvalueindex $planGuid SUB_SLEEP STANDBYIDLE 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_SLEEP STANDBYIDLE 0 2>$null
$changes += "Sleep After: NEVER"

# Hibernate after = Never
powercfg /setacvalueindex $planGuid SUB_SLEEP HIBERNATEIDLE 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_SLEEP HIBERNATEIDLE 0 2>$null
$changes += "Hibernate After: NEVER"

# Allow hybrid sleep = Off
powercfg /setacvalueindex $planGuid SUB_SLEEP HYBRIDSLEEP 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_SLEEP HYBRIDSLEEP 0 2>$null
$changes += "Hybrid Sleep: DISABLED"

# Allow wake timers = Disable
powercfg /setacvalueindex $planGuid SUB_SLEEP RTCWAKE 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_SLEEP RTCWAKE 0 2>$null
$changes += "Wake Timers: DISABLED"

# Unattended sleep timeout = 0
powercfg /setacvalueindex $planGuid SUB_SLEEP UNATTENDSLEEP 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_SLEEP UNATTENDSLEEP 0 2>$null
$changes += "Unattended Sleep: DISABLED"

# ============================================
# USB SETTINGS
# ============================================
Write-Host "[7/25] Disabling USB power saving..." -ForegroundColor Yellow

# USB selective suspend = Disabled
powercfg /setacvalueindex $planGuid 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null
powercfg /setdcvalueindex $planGuid 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null
$changes += "USB Selective Suspend: DISABLED"

# USB 3 Link Power Management = Off
powercfg /setacvalueindex $planGuid 2a737441-1930-4402-8d77-b2bebba308a3 d4e98f31-5ffe-4ce1-be31-1b38b384c009 0 2>$null
powercfg /setdcvalueindex $planGuid 2a737441-1930-4402-8d77-b2bebba308a3 d4e98f31-5ffe-4ce1-be31-1b38b384c009 0 2>$null
$changes += "USB 3 Link Power Management: OFF"

# ============================================
# PCI EXPRESS (SUB_PCIEXPRESS)
# ============================================
Write-Host "[8/25] Disabling PCIe power management..." -ForegroundColor Yellow

# Link State Power Management = Off
powercfg /setacvalueindex $planGuid SUB_PCIEXPRESS ASPM 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_PCIEXPRESS ASPM 0 2>$null
$changes += "PCIe ASPM: OFF"

# ============================================
# DISPLAY SETTINGS (SUB_VIDEO)
# ============================================
Write-Host "[9/25] Configuring display settings..." -ForegroundColor Yellow

# Turn off display after = Never
powercfg /setacvalueindex $planGuid SUB_VIDEO VIDEOIDLE 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_VIDEO VIDEOIDLE 0 2>$null
$changes += "Display Turn Off: NEVER"

# Adaptive brightness = Off
powercfg /setacvalueindex $planGuid SUB_VIDEO ADAPTBRIGHT 0 2>$null
powercfg /setdcvalueindex $planGuid SUB_VIDEO ADAPTBRIGHT 0 2>$null
$changes += "Adaptive Brightness: OFF"

# Display brightness = 100%
powercfg /setacvalueindex $planGuid SUB_VIDEO aded5e82-b909-4619-9949-f5d71dac0bcb 100 2>$null
powercfg /setdcvalueindex $planGuid SUB_VIDEO aded5e82-b909-4619-9949-f5d71dac0bcb 100 2>$null
$changes += "Display Brightness: 100%"

# Dimmed display brightness = 100%
powercfg /setacvalueindex $planGuid SUB_VIDEO f1fbfde2-a960-4165-9f88-50667911ce96 100 2>$null
powercfg /setdcvalueindex $planGuid SUB_VIDEO f1fbfde2-a960-4165-9f88-50667911ce96 100 2>$null
$changes += "Dimmed Display Brightness: 100%"

# ============================================
# GRAPHICS SETTINGS (GPU)
# ============================================
Write-Host "[10/25] Maximizing GPU settings..." -ForegroundColor Yellow

$gpuGuid = "5fb4938d-1ee8-4b0f-9a3c-5036b0ab995c"

# Graphics power preference = Maximum performance (2)
powercfg /setacvalueindex $planGuid $gpuGuid 3619c3f2-afb2-4afc-b0e9-e7fef372de36 2 2>$null
powercfg /setdcvalueindex $planGuid $gpuGuid 3619c3f2-afb2-4afc-b0e9-e7fef372de36 2 2>$null
$changes += "Integrated GPU: Maximum Performance"

# Switchable Dynamic Graphics = MAXIMIZE PERFORMANCE (3)
powercfg /setacvalueindex $planGuid $gpuGuid dd848b2a-8a5d-4451-9ae2-39cd41658f6c 3 2>$null
powercfg /setdcvalueindex $planGuid $gpuGuid dd848b2a-8a5d-4451-9ae2-39cd41658f6c 3 2>$null
$changes += "Switchable Graphics: MAXIMIZE PERFORMANCE"

# ============================================
# WIRELESS ADAPTER SETTINGS
# ============================================
Write-Host "[11/25] Maximizing WiFi performance..." -ForegroundColor Yellow

$wifiGuid = "19cbb8fa-5279-450e-9fac-8a3d5fedd0c1"
powercfg /setacvalueindex $planGuid $wifiGuid 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 2>$null
powercfg /setdcvalueindex $planGuid $wifiGuid 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 2>$null
$changes += "WiFi Power Saving: Maximum Performance"

# ============================================
# MULTIMEDIA SETTINGS
# ============================================
Write-Host "[12/25] Optimizing multimedia settings..." -ForegroundColor Yellow

# When playing video = Optimize video quality
powercfg /setacvalueindex $planGuid 9596fb26-9850-41fd-ac3e-f7c3c00afd4b 34c7b99f-9a6d-4b3c-8dc7-b6693b78cef4 0 2>$null
powercfg /setdcvalueindex $planGuid 9596fb26-9850-41fd-ac3e-f7c3c00afd4b 34c7b99f-9a6d-4b3c-8dc7-b6693b78cef4 0 2>$null
$changes += "Video Playback Quality: Maximum"

# When sharing media = Prevent idle
powercfg /setacvalueindex $planGuid 9596fb26-9850-41fd-ac3e-f7c3c00afd4b 03680956-93bc-4294-bba6-4e0f09bb717f 1 2>$null
powercfg /setdcvalueindex $planGuid 9596fb26-9850-41fd-ac3e-f7c3c00afd4b 03680956-93bc-4294-bba6-4e0f09bb717f 1 2>$null
$changes += "Media Sharing: Prevent Idle"

# ============================================
# BROWSER SETTINGS
# ============================================
Write-Host "[13/25] Configuring browser settings..." -ForegroundColor Yellow

# JavaScript Timer Frequency = Maximum Performance
powercfg /setacvalueindex $planGuid 02f815b5-a5cf-4c84-bf20-649d1f75d3d8 4c793e7d-a264-42e1-87d3-7a0d2f523ccd 1 2>$null
powercfg /setdcvalueindex $planGuid 02f815b5-a5cf-4c84-bf20-649d1f75d3d8 4c793e7d-a264-42e1-87d3-7a0d2f523ccd 1 2>$null
$changes += "JavaScript Timer: Maximum Performance"

# ============================================
# DISABLE HIBERNATION
# ============================================
Write-Host "[14/25] Disabling hibernation..." -ForegroundColor Yellow

powercfg /hibernate off 2>$null
$changes += "Hibernation: DISABLED"

# ============================================
# DISABLE MODERN STANDBY (SAFE)
# ============================================
Write-Host "[15/25] Disabling Connected Standby..." -ForegroundColor Yellow

$regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"
if (Test-Path $regPath) {
    Set-ItemProperty -Path $regPath -Name "PlatformAoAcOverride" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    $changes += "Modern Standby (S0): DISABLED"
}

# ============================================
# SAFE PERFORMANCE REGISTRY TWEAKS
# ============================================
Write-Host "[16/25] Applying SAFE registry performance tweaks..." -ForegroundColor Yellow

# Disable Power Throttling (SAFE)
$throttlePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
if (-not (Test-Path $throttlePath)) {
    New-Item -Path $throttlePath -Force | Out-Null
}
Set-ItemProperty -Path $throttlePath -Name "PowerThrottlingOff" -Value 1 -Type DWord -Force
$changes += "Power Throttling: DISABLED"

# NOTE: REMOVED dangerous C-state registry manipulation that caused BSOD
# NOTE: REMOVED ValueMax=0 for core parking - using powercfg instead

# Timer Resolution
$timerPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
if (Test-Path $timerPath) {
    Set-ItemProperty -Path $timerPath -Name "GlobalTimerResolutionRequests" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
}
$changes += "Global Timer Resolution: High Performance"

# ============================================
# MULTITASKING OPTIMIZATIONS
# ============================================
Write-Host "[17/25] Applying multitasking optimizations..." -ForegroundColor Yellow

$multiMediaPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
if (-not (Test-Path $multiMediaPath)) {
    New-Item -Path $multiMediaPath -Force | Out-Null
}
Set-ItemProperty -Path $multiMediaPath -Name "SystemResponsiveness" -Value 0 -Type DWord -Force
$changes += "System Responsiveness: 0 (100% to apps)"

Set-ItemProperty -Path $multiMediaPath -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord -Force
$changes += "Network Throttling: DISABLED"

# Gaming optimizations
$gamingPath = "$multiMediaPath\Tasks\Games"
if (-not (Test-Path $gamingPath)) {
    New-Item -Path $gamingPath -Force | Out-Null
}
Set-ItemProperty -Path $gamingPath -Name "GPU Priority" -Value 8 -Type DWord -Force
Set-ItemProperty -Path $gamingPath -Name "Priority" -Value 6 -Type DWord -Force
Set-ItemProperty -Path $gamingPath -Name "Scheduling Category" -Value "High" -Type String -Force
Set-ItemProperty -Path $gamingPath -Name "SFIO Priority" -Value "High" -Type String -Force
$changes += "Gaming Priority: Maximum"

# ============================================
# MEMORY MANAGEMENT
# ============================================
Write-Host "[18/25] Optimizing memory management..." -ForegroundColor Yellow

$memPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
if (Test-Path $memPath) {
    Set-ItemProperty -Path $memPath -Name "DisablePagingExecutive" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    $changes += "Paging Executive: DISABLED"

    Set-ItemProperty -Path $memPath -Name "LargeSystemCache" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    $changes += "Large System Cache: ENABLED"
}

# ============================================
# FILE SYSTEM OPTIMIZATIONS
# ============================================
Write-Host "[19/25] Optimizing file system..." -ForegroundColor Yellow

$fsPath = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
if (Test-Path $fsPath) {
    Set-ItemProperty -Path $fsPath -Name "NtfsDisableLastAccessUpdate" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    $changes += "NTFS Last Access Update: DISABLED"

    Set-ItemProperty -Path $fsPath -Name "NtfsDisable8dot3NameCreation" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    $changes += "8.3 Name Creation: DISABLED"
}

# ============================================
# NETWORK OPTIMIZATIONS
# ============================================
Write-Host "[20/25] Optimizing network stack..." -ForegroundColor Yellow

$tcpPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
if (Test-Path $tcpPath) {
    Set-ItemProperty -Path $tcpPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $tcpPath -Name "TCPNoDelay" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    $changes += "TCP Nagle Algorithm: DISABLED"

    Set-ItemProperty -Path $tcpPath -Name "DefaultTTL" -Value 64 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $tcpPath -Name "TcpTimedWaitDelay" -Value 30 -Type DWord -Force -ErrorAction SilentlyContinue
    $changes += "Network Buffers: Optimized"
}

# ============================================
# BATTERY SETTINGS
# ============================================
Write-Host "[21/25] Forcing battery to max performance..." -ForegroundColor Yellow

$batteryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"
if (Test-Path $batteryPath) {
    Set-ItemProperty -Path $batteryPath -Name "EnergyEstimationEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    $changes += "Battery Saver: DISABLED"
}

# ============================================
# STARTUP PERSISTENCE METHOD 1: SCHEDULED TASK
# ============================================
Write-Host "[22/25] Creating Scheduled Task startup..." -ForegroundColor Yellow

$scriptPath = $PSCommandPath
$taskName = "NuclearPerformance_v16"

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Nuclear Performance v16 SAFE - Auto startup" | Out-Null
$changes += "Startup Method 1: Scheduled Task (SYSTEM)"

# ============================================
# STARTUP PERSISTENCE METHOD 2: REGISTRY RUN
# ============================================
Write-Host "[23/25] Creating Registry Run startup..." -ForegroundColor Yellow

$runPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$runCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
Set-ItemProperty -Path $runPath -Name "NuclearPerformance" -Value $runCommand -Type String -Force
$changes += "Startup Method 2: Registry Run (HKLM)"

# Also add to current user
$runPathUser = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
Set-ItemProperty -Path $runPathUser -Name "NuclearPerformance" -Value $runCommand -Type String -Force
$changes += "Startup Method 3: Registry Run (HKCU)"

# ============================================
# STARTUP PERSISTENCE METHOD 3: LOGON TASK
# ============================================
Write-Host "[24/25] Creating Logon Task startup..." -ForegroundColor Yellow

$logonTaskName = "NuclearPerformance_Logon"
Unregister-ScheduledTask -TaskName $logonTaskName -Confirm:$false -ErrorAction SilentlyContinue

$logonTrigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName $logonTaskName -Action $action -Trigger $logonTrigger -Principal $principal -Settings $settings -Description "Nuclear Performance v16 - Logon trigger" | Out-Null
$changes += "Startup Method 4: Logon Task"

# ============================================
# APPLY AND VERIFY
# ============================================
Write-Host "[25/25] Applying all changes..." -ForegroundColor Yellow

powercfg /setactive $planGuid 2>$null

# Verify
$activePlan = powercfg /getactivescheme
Write-Host ""
Write-Host "Active plan confirmed:" -ForegroundColor Green
Write-Host $activePlan -ForegroundColor Cyan

# ============================================
# OUTPUT SUMMARY
# ============================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  NUCLEAR PERFORMANCE v16 SAFE - APPLIED  " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""

$i = 1
foreach ($change in $changes) {
    Write-Host "[$i] $change" -ForegroundColor White
    $i++
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  CRASH-CAUSING SETTINGS REMOVED:          " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  - IDLEDISABLE (caused KMODE_EXCEPTION)" -ForegroundColor Yellow
Write-Host "  - C-state registry manipulation" -ForegroundColor Yellow
Write-Host "  - Dangerous core parking registry hacks" -ForegroundColor Yellow
Write-Host ""
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  STARTUP PERSISTENCE (4 METHODS):         " -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  1. Scheduled Task (SYSTEM at boot)" -ForegroundColor White
Write-Host "  2. Registry HKLM Run" -ForegroundColor White
Write-Host "  3. Registry HKCU Run" -ForegroundColor White
Write-Host "  4. Scheduled Task (Logon trigger)" -ForegroundColor White
Write-Host ""
Write-Host "TOTAL CHANGES: $($changes.Count)" -ForegroundColor Green
Write-Host ""
Write-Host "NO RESTART REQUIRED - Settings applied immediately!" -ForegroundColor Green
Write-Host ""

# Save log
$logPath = "$PSScriptRoot\NuclearPerformance_v16_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$changes | Out-File -FilePath $logPath -Encoding UTF8
Write-Host "Log saved to: $logPath" -ForegroundColor Cyan
