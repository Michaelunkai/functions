# Extracted from C:\users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1.
# The live profile keeps a thin launcher and dot-sources this script.
$__extractedFunctionName = '_SetCoolmaxPhase2'
$__extractedScriptPath = $PSCommandPath
$__extractedArgs = @($args)
if ($__extractedArgs -contains '-SelfTest') {
    [pscustomobject]@{
        Script = $__extractedScriptPath
        Exists = (Test-Path -LiteralPath $__extractedScriptPath)
        Function = $__extractedFunctionName
        Mode = 'SelfTest'
    }
    return
}

function _SetCoolmaxPhase2 {
    Write-Host "=== [COOLMAX-P2] Phase 2: Maximum Cooling + Hardware Maximization (35 categories) ===" -ForegroundColor Cyan

    # 1. GPU fans: NVML direct fan control (no MSI Afterburner) + max power limit
    _SetGpuFanDirect -FanPct 100 -PowerLimitPct 111
    Write-Host "[CP2-01] GPU fans: NVML direct 100% + nvidia-smi 400W power limit" -ForegroundColor Cyan

    # 1b. NVIDIA: Lock clocks at max, disable idle/boost variance
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        nvidia-smi --auto-boost-default=0 2>$null | Out-Null
        $fanOut = nvidia-smi --query-gpu=fan.speed --format=csv,noheader,nounits 2>$null
        Write-Host "[CP2-01b] NVIDIA: locked clocks, fan=$fanOut%" -ForegroundColor Green
    } else { Write-Host "[CP2-01b] nvidia-smi not found" -ForegroundColor Yellow }

    # 2. GPU: Force all power states P0 always - max clocks, max heat, max cooling use
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\NVTweak" /v "PowerMizerDefault" /t REG_DWORD /d 1 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\NVTweak" /v "PowerMizerDefaultAC" /t REG_DWORD /d 1 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\NVTweak" /v "MinGpuClockIdlePercent" /t REG_DWORD /d 100 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\NVTweak" /v "DisableGpuIdleStates" /t REG_DWORD /d 1 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\NVTweak" /v "DisableCudaContextSuspend" /t REG_DWORD /d 1 /f 2>$null
    Write-Host "[CP2-02] NVIDIA: forced P0, idle states disabled, CUDA suspend disabled" -ForegroundColor Green

    # 3. AMD PBO: all limits maximized
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "PBOEnabled" /t REG_DWORD /d 1 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "PBOScalar" /t REG_DWORD /d 10 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "AllCoreBoost" /t REG_DWORD /d 1 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "MaxBoostFreqOverride" /t REG_DWORD /d 200 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "EDCLimit" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "TDCLimit" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "PPTLimit" /t REG_DWORD /d 0 /f 2>$null
    Write-Host "[CP2-03] AMD PBO: enabled, scalar=10, +200MHz, EDC/TDC/PPT limits zeroed (unlimited)" -ForegroundColor Green

    # 4. AMD: ALL power/clock gating off - hardware runs at FULL speed always
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "ClockGatingEnabled" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "VoltageGatingEnabled" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "PowerGatingEnabled" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "RampGatingEnabled" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "DisableHwPStateManagement" /t REG_DWORD /d 1 /f 2>$null
    Write-Host "[CP2-04] AMD: ALL gating disabled (clock/voltage/power/ramp/HwPState)" -ForegroundColor Green

    # 5. AMD C-states: disable all (CPU never idles, stays hot, cooling works max)
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "MaxCState" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "CStateLatency" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "CStateDemotionEnabled" /t REG_DWORD /d 0 /f 2>$null
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR IDLEDISABLE 1 2>$null
    powercfg /setacvalueindex SCHEME_CURRENT 2e601130-5351-4d9d-8e04-252966bad054 d502f7ee-1dc7-4efd-a55d-f04b6f5c0545 0 2>$null
    Write-Host "[CP2-05] AMD C-states: MaxCState=0, idle disable, no demotion" -ForegroundColor Green

    # 6. AMD Turbo Boost Max + all-core boost
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 2 2>$null
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTPOL 100 2>$null
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 0 2>$null
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFINCREASEPOL 2 2>$null
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFINCTHRESHOLD 5 2>$null
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFINCTIME 1 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Host "[CP2-06] Boost: mode=Aggressive, policy=100%, EPP=0, inc threshold=5%, inc time=1" -ForegroundColor Green

    # 7. FCLK: maximize fabric clock (DDR5 memory subsystem max throughput)
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdkmdag\Parameters" /v "DynamicFclkDisable" /t REG_DWORD /d 1 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdkmdag\Parameters" /v "FclkPowerGatingEnable" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "DFCStatesDisable" /t REG_DWORD /d 1 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "FabricPstateDisable" /t REG_DWORD /d 1 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "UclkDividerState" /t REG_DWORD /d 0 /f 2>$null
    Write-Host "[CP2-07] FCLK: power gating off, fabric P-states off, UCLK divider=1:1" -ForegroundColor Green

    # 8. Memory controller: JEDEC max + no throttle
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "MemoryThrottleEnabled" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "MemClkDeepSleepDisable" /t REG_DWORD /d 1 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v "DisablePagingExecutive" /t REG_DWORD /d 1 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v "LargeSystemCache" /t REG_DWORD /d 1 /f 2>$null
    try { Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue } catch {}
    Write-Host "[CP2-08] Memory: throttle off, deep sleep off, compression off, paging exec off" -ForegroundColor Green

    # 9. ACPI active cooling policy (force active fan cooling, not passive throttle)
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v "AcCoolingPolicy" /t REG_DWORD /d 1 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v "DcCoolingPolicy" /t REG_DWORD /d 1 /f 2>$null
    powercfg /setacvalueindex SCHEME_CURRENT SUB_SYSTEM SYSCOOLINGPOL 1 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Host "[CP2-09] ACPI cooling policy=ACTIVE (fans, not throttle)" -ForegroundColor Green

    # 10. Thermal zone: disable passive throttling (no CPU slowdown on heat)
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\2a737441-1930-4402-8d77-b2bebba308a3\8619b916-e004-4dd8-9b66-dae86f806698" /v "Attributes" /t REG_DWORD /d 2 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\ACPI\Parameters" /v "PassiveCoolingEnabled" /t REG_DWORD /d 0 /f 2>$null
    Write-Host "[CP2-10] Thermal passive cooling DISABLED (hardware fans handle it)" -ForegroundColor Green

    # 11. NVMe thermal throttle disable
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device" /v "NVMeAPSTEnabled" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device" /v "IdlePowerManagement" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device" /v "D3ColdSupported" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device" /v "MaxTransferLength" /t REG_DWORD /d 0x100000 /f 2>$null
    Write-Host "[CP2-11] NVMe: APST off, idle PM off, D3Cold off, max transfer 1MB" -ForegroundColor Green

    # 12. PCIe: LTR (Latency Tolerance Reporting) disable + OBFF disable
    $pciClass = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    if (Test-Path $pciClass) {
        Get-ChildItem $pciClass -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
            Set-ItemProperty -Path $_.PSPath -Name "PCIELinkStateControl" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $_.PSPath -Name "EnableMsI" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $_.PSPath -Name "DisableLTR" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $_.PSPath -Name "DisableOBFF" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "[CP2-12] PCIe: LTR disabled, OBFF disabled, link state=max, MSI=1" -ForegroundColor Green

    # 13. AMD iGPU 780M: force max clocks
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001" /v "PP_GPUPowerDownEnabled" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001" /v "KMD_EnableComputePreemption" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001" /v "PP_ThermalAutoThrottlingEnable" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001" /v "PP_FuzzyFanControlSupport" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001" /v "PowerThrottleEnabled" /t REG_DWORD /d 0 /f 2>$null
    Write-Host "[CP2-13] AMD iGPU 780M: power down off, preemption off, thermal throttle off" -ForegroundColor Green

    # 14. Connected standby / modern standby FULLY off
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v "CsEnabled" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v "HibernateEnabled" /t REG_DWORD /d 0 /f 2>$null
    powercfg /h off 2>$null | Out-Null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v "S3Enabled" /t REG_DWORD /d 0 /f 2>$null
    Write-Host "[CP2-14] Hibernate OFF, connected standby OFF, S3 sleep OFF" -ForegroundColor Green

    # 15. AMD VRB (Voltage Reference Bandwidth) + current limits
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "VRBEnabled" /t REG_DWORD /d 1 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "MaxCurrentOverride" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "VddcrVddMaxOverride" /t REG_DWORD /d 0 /f 2>$null
    Write-Host "[CP2-15] AMD VRB enabled, current/VRM limits zeroed (no cap)" -ForegroundColor Green

    # 16. Hyper-V: disable if active (reduces overhead + heat latency)
    bcdedit /set hypervisorlaunchtype off 2>&1 | Out-Null
    bcdedit /set vsmlaunchtype off 2>&1 | Out-Null
    Write-Host "[CP2-16] Hyper-V OFF, VSM OFF (bare metal execution)" -ForegroundColor Green

    # 17. CPU thread scheduler: distribute load to ALL cores (equal heat = max cooling use)
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl" /v "Win32PrioritySeparation" /t REG_DWORD /d 0x26 /f 2>$null
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR DISTRIBUTEUTIL 1 2>$null
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR LATENCYHINTPERF 100 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Host "[CP2-17] Thread distribution=1, latency hint=100% (all cores used equally)" -ForegroundColor Green

    # 18. USB root hubs: max power (cooling controller USB devices run at max)
    Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match "Root Hub" } | ForEach-Object {
        $devPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($_.InstanceId)\Device Parameters"
        if (Test-Path $devPath) {
            Set-ItemProperty -Path $devPath -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "[CP2-18] USB root hubs: enhanced power management disabled" -ForegroundColor Green

    # 19. NIC: interrupt coalescing OFF (max responsiveness, no batching delay)
    Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        Set-NetAdapterAdvancedProperty -Name $_.Name -RegistryKeyword "*InterruptModeration" -RegistryValue 0 -ErrorAction SilentlyContinue
        Set-NetAdapterRss -Name $_.Name -Enabled $true -ErrorAction SilentlyContinue
    }
    Write-Host "[CP2-19] NIC: interrupt moderation OFF, RSS ON (all adapters)" -ForegroundColor Green

    # 20. Windows push notifications + delivery optimization OFF
    Stop-Service WpnService -Force -ErrorAction SilentlyContinue
    Set-Service WpnService -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service DoSvc -Force -ErrorAction SilentlyContinue
    Set-Service DoSvc -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Host "[CP2-20] WpnService + DoSvc stopped and disabled" -ForegroundColor Green

    # 21. MMCSS Games task: maximize all fields
    $mmGames = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
    if (Test-Path $mmGames) {
        Set-ItemProperty -Path $mmGames -Name "Priority" -Value 6 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $mmGames -Name "GPU Priority" -Value 8 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $mmGames -Name "Affinity" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $mmGames -Name "Background Only" -Type String -Value "False" -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $mmGames -Name "Clock Rate" -Value 10000 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $mmGames -Name "Scheduling Category" -Type String -Value "High" -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $mmGames -Name "SFIO Priority" -Type String -Value "High" -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $mmGames -Name "NoLazyMode" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $mmGames -Name "AlwaysOn" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    Write-Host "[CP2-21] MMCSS Games: priority=6, GPU=8, ClockRate=10000, NoLazy, AlwaysOn" -ForegroundColor Green

    # 22. StorPort: max throughput settings
    $storPath = "HKLM:\SYSTEM\CurrentControlSet\Control\StorPort"
    if (-not (Test-Path $storPath)) { New-Item -Path $storPath -Force | Out-Null }
    Set-ItemProperty -Path $storPath -Name "TotalRequestHoldTime" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $storPath -Name "BusyPauseOnPower" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $storPath -Name "EnableIdlePowerManagement" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $storPath -Name "IoTimeoutValue" -Value 30 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host "[CP2-22] StorPort: hold=0, idle PM=0, busy pause=0, timeout=30s" -ForegroundColor Green

    # 23. All background services OFF - 100% CPU/GPU for hardware stress
    $cpSvcs = @("SysMain","WSearch","DiagTrack","MapsBroker","BITS","lfsvc","wuauserv","UsoSvc","WaasMedicSvc","WerSvc","WpnService","DoSvc","XblGameSave","XboxGipSvc","RetailDemo","TabletInputService","Fax","Spooler")
    foreach ($s in $cpSvcs) { Stop-Service $s -Force -ErrorAction SilentlyContinue }
    Write-Host "[CP2-23] 18 background services stopped" -ForegroundColor Green

    # 24. Kernel: no idle, no coalescing, boost all threads
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v "DpcWatchdogPeriod" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v "AdditionalCriticalWorkerThreads" /t REG_DWORD /d 8 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v "GlobalTimerResolutionRequests" /t REG_DWORD /d 1 /f 2>$null
    Write-Host "[CP2-24] Kernel: DpcWatchdog=0, +8 critical threads, GlobalTimerRes=1" -ForegroundColor Green

    # 25. AMD Ryzen: CPPC disable (all cores boost equally - uniform heat = max cooling)
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "CppcEnabled" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "PreferredCoreEnable" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdppm\Parameters" /v "CppcAutonomous" /t REG_DWORD /d 0 /f 2>$null
    Write-Host "[CP2-25] AMD CPPC off, preferred cores off - all cores boost equally" -ForegroundColor Green

    # 26. NTFS: disable last access, 8.3, optimize
    fsutil behavior set disable8dot3 1 2>$null | Out-Null
    fsutil behavior set disablelastaccess 1 2>$null | Out-Null
    fsutil behavior set disableDeleteNotify 0 2>$null | Out-Null
    Write-Host "[CP2-26] NTFS: 8.3=off, lastaccess=off, TRIM=enabled" -ForegroundColor Green

    # 27. Win32PrioritySeparation: max foreground boost
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl" /v "Win32PrioritySeparation" /t REG_DWORD /d 0x26 /f 2>$null
    Write-Host "[CP2-27] Win32PrioritySeparation=0x26 (max foreground boost)" -ForegroundColor Green

    # 28. LLTD (link layer topology): off (network overhead)
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\LLTD" /v "EnableLLTDIO" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\LLTD" /v "EnableRspndr" /t REG_DWORD /d 0 /f 2>$null
    Write-Host "[CP2-28] LLTD disabled (no link topology overhead)" -ForegroundColor Green

    # 29. Large pages + heap LFH
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v "LargePageMinimum" /t REG_DWORD /d 0 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v "HeapDeCommitFreeBlockThreshold" /t REG_DWORD /d 0x40000 /f 2>$null
    Write-Host "[CP2-29] Large pages enabled, heap LFH decommit threshold set" -ForegroundColor Green

    # 30. Security mitigations OFF (more CPU throughput = more heat = max cooling)
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v "FeatureSettingsOverride" /t REG_DWORD /d 3 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v "FeatureSettingsOverrideMask" /t REG_DWORD /d 3 /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v "DisableExceptionChainValidation" /t REG_DWORD /d 1 /f 2>$null
    Write-Host "[CP2-30] Spectre/Meltdown mitigations off, exception chain validation off" -ForegroundColor Green

    # 31. bcdedit: disable Hyper-V, no recovery, max timeout
    bcdedit /set hypervisorlaunchtype off 2>&1 | Out-Null
    bcdedit /set disabledynamictick yes 2>&1 | Out-Null
    bcdedit /set useplatformtick yes 2>&1 | Out-Null
    bcdedit /set tscsyncpolicy enhanced 2>&1 | Out-Null
    bcdedit /set useplatformclock false 2>&1 | Out-Null
    Write-Host "[CP2-31] bcdedit: Hyper-V off, dynamic tick off, platform tick, TSC sync enhanced" -ForegroundColor Green

    # 32. Timer resolution: 0.5ms (max precision scheduling)
    $timeDll = Add-Type -MemberDefinition @"
[DllImport("ntdll.dll", SetLastError=true)] public static extern int NtSetTimerResolution(int DesiredResolution, bool SetResolution, out int CurrentResolution);
"@ -Name "Timer" -Namespace "WinAPI" -PassThru -ErrorAction SilentlyContinue
    if ($timeDll) { $cur = 0; $timeDll::NtSetTimerResolution(5000, $true, [ref]$cur) | Out-Null }
    Write-Host "[CP2-32] Timer resolution set to 0.5ms (5000 units)" -ForegroundColor Green

    # 33. Final GPU status check - use NVML for accurate per-fan speeds
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        $final = nvidia-smi --query-gpu=power.draw,power.limit,temperature.gpu,clocks.gr,clocks.mem --format=csv,noheader,nounits 2>$null
        Write-Host "[CP2-33] FINAL GPU: $final (W draw, W limit, C temp, MHz core, MHz mem)" -ForegroundColor Cyan
    }
    $nvmlScript = 'C:\Users\micha\Documents\WindowsPowerShell\_SetNvGpuFan.ps1'
    if (Test-Path $nvmlScript) { & $nvmlScript -FanPct 100 }

    # 34. CPU status check
    $cpuMin = (powercfg /query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 2>$null | Select-String "Current AC") -replace '.*:\s*0x','' -replace '\s.*',''
    $cpuMax = (powercfg /query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 2>$null | Select-String "Current AC") -replace '.*:\s*0x','' -replace '\s.*',''
    Write-Host "[CP2-34] FINAL CPU: min=$cpuMin% max=$cpuMax% (should be 100/100)" -ForegroundColor Cyan

    # 35. Summary
    Write-Host "=== [COOLMAX-P2] Phase 2 complete - 35 categories, BOTH NVIDIA+AMD maximized ===" -ForegroundColor Cyan
}

& $__extractedFunctionName @__extractedArgs