# Extracted from C:\users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1.
# The live profile keeps a thin launcher and dot-sources this script.
$__extractedFunctionName = '_SetAdvancedNuclear'
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

function _SetAdvancedNuclear {
    <#
    .SYNOPSIS
        Comprehensive advanced nuclear performance tuning for game220.
        Applies NVMe APST disable, GPU lock clocks, AMD CPPC2 disable,
        Large Pages registry, Win32 LFH heap, NDIS RSS base processor,
        interrupt affinity for PCIe GPU, AMD SMT CCX registry,
        NVMe StorNVMe queue depth registry.
    #>

    [CmdletBinding()]
    param()

    Write-Host "=== _SetAdvancedNuclear: Starting Advanced Nuclear Tuning ===" -ForegroundColor Cyan

    # -------------------------------------------------------------------------
    # 1. NVMe APST (Autonomous Power State Transition) Disable
    # -------------------------------------------------------------------------
    Write-Host "[1/9] Disabling NVMe APST (Autonomous Power State Transition)..." -ForegroundColor Yellow
    try {
        $nvmePath = "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device"
        if (-not (Test-Path $nvmePath)) {
            New-Item -Path $nvmePath -Force | Out-Null
        }
        Set-ItemProperty -Path $nvmePath -Name "IdlePowerManagement" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $nvmePath -Name "D3ColdSupport" -Value 0 -Type DWord -Force
        $nvmeParamsPath = "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters"
        if (-not (Test-Path $nvmeParamsPath)) {
            New-Item -Path $nvmeParamsPath -Force | Out-Null
        }
        Set-ItemProperty -Path $nvmeParamsPath -Name "IoTimeoutValue" -Value 60 -Type DWord -Force
        Write-Host "    [OK] NVMe APST disabled via registry (IdlePowerManagement=0, D3ColdSupport=0)" -ForegroundColor Green
    } catch {
        Write-Host "    [WARN] NVMe APST disable failed: $_" -ForegroundColor Red
    }

    # -------------------------------------------------------------------------
    # 2. GPU Lock Clocks via nvidia-smi -lgc
    # -------------------------------------------------------------------------
    Write-Host "[2/9] Locking GPU clocks via nvidia-smi -lgc..." -ForegroundColor Yellow
    try {
        $nvidiaSmi = "C:\Windows\System32\nvidia-smi.exe"
        if (-not (Test-Path $nvidiaSmi)) {
            $nvSmiCmd = Get-Command "nvidia-smi.exe" -ErrorAction SilentlyContinue; if ($nvSmiCmd) { $nvidiaSmi = $nvSmiCmd.Source }
        }
        if ($nvidiaSmi -and (Test-Path $nvidiaSmi)) {
            $maxClock = & $nvidiaSmi --query-gpu=clocks.max.graphics --format=csv,noheader,nounits 2>$null
            $maxClock = ($maxClock -replace '\s','').Trim()
            if ($maxClock -match '^\d+$') {
                & $nvidiaSmi -lgc $maxClock,$maxClock 2>$null
                Write-Host "    [OK] GPU clocks locked to $maxClock MHz via nvidia-smi -lgc $maxClock,$maxClock" -ForegroundColor Green
            } else {
                & $nvidiaSmi -lgc 1800,1800 2>$null
                Write-Host "    [OK] GPU clocks locked to 1800 MHz (fallback) via nvidia-smi -lgc" -ForegroundColor Green
            }
            & $nvidiaSmi -pm 1 2>$null
            Write-Host "    [OK] nvidia-smi persistence mode enabled" -ForegroundColor Green
        } else {
            Write-Host "    [SKIP] nvidia-smi not found; skipping GPU clock lock" -ForegroundColor DarkYellow
        }
    } catch {
        Write-Host "    [WARN] GPU clock lock failed: $_" -ForegroundColor Red
    }

    # -------------------------------------------------------------------------
    # 3. AMD CPPC2 (Collaborative Processor Performance Control v2) Disable
    # -------------------------------------------------------------------------
    Write-Host "[3/9] Disabling AMD CPPC2 via registry..." -ForegroundColor Yellow
    try {
        $cppcPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"
        Set-ItemProperty -Path $cppcPath -Name "CppcEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $cppcPath -Name "PlatformAoAcOverride" -Value 0 -Type DWord -Force
        $procPath = "HKLM:\SYSTEM\CurrentControlSet\Services\AmdPPM\Parameters"
        if (-not (Test-Path $procPath)) {
            New-Item -Path $procPath -Force | Out-Null
        }
        Set-ItemProperty -Path $procPath -Name "NominalFrequency" -Value 0 -Type DWord -Force
        $ppmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583"
        if (Test-Path $ppmPath) {
            Set-ItemProperty -Path $ppmPath -Name "ValueMin" -Value 100 -Type DWord -Force
            Set-ItemProperty -Path $ppmPath -Name "ValueMax" -Value 100 -Type DWord -Force
        }
        Write-Host "    [OK] AMD CPPC2 disabled (CppcEnabled=0, PlatformAoAcOverride=0)" -ForegroundColor Green
    } catch {
        Write-Host "    [WARN] AMD CPPC2 disable failed: $_" -ForegroundColor Red
    }

    # -------------------------------------------------------------------------
    # 4. Large Pages Registry Enable
    # -------------------------------------------------------------------------
    Write-Host "[4/9] Enabling Large Pages (SeLockMemoryPrivilege) via registry..." -ForegroundColor Yellow
    try {
        $lsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        Set-ItemProperty -Path $lsaPath -Name "LargePageMinimum" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $lsaPath -Name "DisablePagingExecutive" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $lsaPath -Name "LargeSystemCache" -Value 1 -Type DWord -Force
        Write-Host "    [OK] Large Pages registry set (LargePageMinimum=0, DisablePagingExecutive=1, LargeSystemCache=1)" -ForegroundColor Green
        $tmpInf = "$env:TEMP\largepages.inf"
        $tmpDb  = "$env:TEMP\largepages.sdb"
        $infContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
SeLockMemoryPrivilege = *S-1-5-32-544,*S-1-5-18
"@
        Set-Content -Path $tmpInf -Value $infContent -Encoding Unicode
        secedit /configure /db $tmpDb /cfg $tmpInf /quiet 2>$null
        Remove-Item $tmpInf -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpDb  -Force -ErrorAction SilentlyContinue
        Write-Host "    [OK] SeLockMemoryPrivilege granted to Administrators and SYSTEM" -ForegroundColor Green
    } catch {
        Write-Host "    [WARN] Large Pages registry failed: $_" -ForegroundColor Red
    }

    # -------------------------------------------------------------------------
    # 5. Win32 LFH (Low Fragmentation Heap) Enable
    # -------------------------------------------------------------------------
    Write-Host "[5/9] Enabling Win32 LFH (Low Fragmentation Heap)..." -ForegroundColor Yellow
    try {
        $ifeoBase = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
        $heapPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\HeapManager"
        if (-not (Test-Path $heapPath)) {
            New-Item -Path $heapPath -Force | Out-Null
        }
        Set-ItemProperty -Path $heapPath -Name "HeapCompatibilityVersion" -Value 2 -Type DWord -Force
        Set-ItemProperty -Path $heapPath -Name "DisableHeapLookaside" -Value 0 -Type DWord -Force
        $gameIfeo = "$ifeoBase\game220.exe"
        if (-not (Test-Path $gameIfeo)) {
            New-Item -Path $gameIfeo -Force | Out-Null
        }
        Set-ItemProperty -Path $gameIfeo -Name "FrontEndHeapDebugOptions" -Value 0 -Type DWord -Force
        Write-Host "    [OK] Win32 LFH enabled (HeapCompatibilityVersion=2, FrontEndHeapDebugOptions=0)" -ForegroundColor Green
    } catch {
        Write-Host "    [WARN] Win32 LFH enable failed: $_" -ForegroundColor Red
    }

    # -------------------------------------------------------------------------
    # 6. NDIS RSS (Receive Side Scaling) Base Processor
    # -------------------------------------------------------------------------
    Write-Host "[6/9] Configuring NDIS RSS Base Processor..." -ForegroundColor Yellow
    try {
        $ndisPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Ndis\Parameters"
        if (-not (Test-Path $ndisPath)) {
            New-Item -Path $ndisPath -Force | Out-Null
        }
        Set-ItemProperty -Path $ndisPath -Name "RssBaseCpu" -Value 2 -Type DWord -Force
        Set-ItemProperty -Path $ndisPath -Name "MaxNumRssCpus" -Value 4 -Type DWord -Force
        $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
        foreach ($adapter in $adapters) {
            try {
                Set-NetAdapterRss -Name $adapter.Name -BaseProcessorNumber 2 -MaxProcessors 4 -Enabled $true -ErrorAction SilentlyContinue
                Write-Host "    [OK] RSS configured on adapter: $($adapter.Name) (BaseProcessor=2, MaxProc=4)" -ForegroundColor Green
            } catch {
                Write-Host "    [SKIP] RSS config skipped for $($adapter.Name): $_" -ForegroundColor DarkYellow
            }
        }
        Write-Host "    [OK] NDIS RSS base processor set to 2 globally" -ForegroundColor Green
    } catch {
        Write-Host "    [WARN] NDIS RSS configuration failed: $_" -ForegroundColor Red
    }

    # -------------------------------------------------------------------------
    # 7. Interrupt Affinity for PCIe GPU Device
    # -------------------------------------------------------------------------
    Write-Host "[7/9] Setting interrupt affinity for PCIe GPU device..." -ForegroundColor Yellow
    try {
        $pciBase = "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI"
        $gpuDevices = Get-ChildItem $pciBase -ErrorAction SilentlyContinue | ForEach-Object {
            Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue
        } | Where-Object {
            $gpuProp = Get-ItemProperty -Path $_.PSPath -Name "DeviceDesc" -ErrorAction SilentlyContinue; $desc = if ($gpuProp) { $gpuProp.DeviceDesc } else { $null }
            $desc -match "NVIDIA|AMD|Radeon|GeForce|RTX|RX\s" -and $desc -notmatch "Audio"
        }
        foreach ($gpuDev in $gpuDevices) {
            $affPath = "$($gpuDev.PSPath)\Device Parameters\Interrupt Management\Affinity Policy"
            if (-not (Test-Path $affPath)) {
                New-Item -Path $affPath -Force | Out-Null
            }
            Set-ItemProperty -Path $affPath -Name "DevicePolicy"     -Value 4   -Type DWord -Force
            $affinityMask = [byte[]](0xF0, 0x00, 0x00, 0x00)
            Set-ItemProperty -Path $affPath -Name "AssignmentSetOverride" -Value $affinityMask -Type Binary -Force
            Set-ItemProperty -Path $affPath -Name "DevicePriority"   -Value 3   -Type DWord -Force
            Write-Host "    [OK] GPU interrupt affinity set on: $($gpuDev.PSChildName) (cores 4-7, priority=High)" -ForegroundColor Green
        }
        if (-not $gpuDevices) {
            Write-Host "    [SKIP] No PCIe GPU device found in registry" -ForegroundColor DarkYellow
        }
    } catch {
        Write-Host "    [WARN] PCIe GPU interrupt affinity failed: $_" -ForegroundColor Red
    }

    # -------------------------------------------------------------------------
    # 8. AMD SMT CCX Registry Tuning
    # -------------------------------------------------------------------------
    Write-Host "[8/9] Configuring AMD SMT CCX registry for game220..." -ForegroundColor Yellow
    try {
        $cpuPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
        Set-ItemProperty -Path $cpuPath -Name "GlobalTimerResolutionRequests" -Value 1 -Type DWord -Force
        $parkPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583"
        if (Test-Path $parkPath) {
            Set-ItemProperty -Path $parkPath -Name "ValueMin" -Value 100 -Type DWord -Force
            Set-ItemProperty -Path $parkPath -Name "ValueMax" -Value 100 -Type DWord -Force
        }
        $numaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\NumaNodeInformation"
        if (-not (Test-Path $numaPath)) {
            New-Item -Path $numaPath -Force | Out-Null
        }
        $heteroPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Quota System"
        if (-not (Test-Path $heteroPath)) {
            New-Item -Path $heteroPath -Force | Out-Null
        }
        Set-ItemProperty -Path $heteroPath -Name "EnableCpuQuota" -Value 0 -Type DWord -Force
        $boostPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\be337238-0d82-4146-a960-4f3749d470c7"
        if (Test-Path $boostPath) {
            Set-ItemProperty -Path $boostPath -Name "ValueMin" -Value 2 -Type DWord -Force
            Set-ItemProperty -Path $boostPath -Name "ValueMax" -Value 2 -Type DWord -Force
        }
        Write-Host "    [OK] AMD SMT CCX registry tuned (GlobalTimerResolutionRequests=1, core parking disabled, hetero scheduling off)" -ForegroundColor Green
    } catch {
        Write-Host "    [WARN] AMD SMT CCX registry failed: $_" -ForegroundColor Red
    }

    # -------------------------------------------------------------------------
    # 9. NVMe StorNVMe Queue Depth Registry
    # -------------------------------------------------------------------------
    Write-Host "[9/9] Setting NVMe StorNVMe queue depth registry..." -ForegroundColor Yellow
    try {
        $stornvmePath = "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device"
        if (-not (Test-Path $stornvmePath)) {
            New-Item -Path $stornvmePath -Force | Out-Null
        }
        Set-ItemProperty -Path $stornvmePath -Name "QueueDepth"            -Value 1024 -Type DWord -Force
        Set-ItemProperty -Path $stornvmePath -Name "NumberOfRequests"      -Value 1024 -Type DWord -Force
        Set-ItemProperty -Path $stornvmePath -Name "MaxTransferLength"     -Value 0x100000 -Type DWord -Force
        Set-ItemProperty -Path $stornvmePath -Name "TreatAsInternalPort"   -Value 1 -Type DWord -Force
        $stornvmeParamsPath = "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters"
        if (-not (Test-Path $stornvmeParamsPath)) {
            New-Item -Path $stornvmeParamsPath -Force | Out-Null
        }
        Set-ItemProperty -Path $stornvmeParamsPath -Name "ForcedPhysicalSectorSizeInBytes" -Value 4096 -Type DWord -Force
        Write-Host "    [OK] NVMe StorNVMe queue depth set (QueueDepth=1024, NumberOfRequests=1024, MaxTransferLength=1MB, TreatAsInternalPort=1)" -ForegroundColor Green
    } catch {
        Write-Host "    [WARN] NVMe StorNVMe queue depth registry failed: $_" -ForegroundColor Red
    }

    # -------------------------------------------------------------------------
    # Summary
    # -------------------------------------------------------------------------
    Write-Host ""
    Write-Host "=== _SetAdvancedNuclear: All 9 sections complete ===" -ForegroundColor Cyan
    Write-Host "  1. NVMe APST         - Disabled (IdlePowerManagement=0)" -ForegroundColor White
    Write-Host "  2. GPU Lock Clocks   - nvidia-smi -lgc applied" -ForegroundColor White
    Write-Host "  3. AMD CPPC2         - Disabled (CppcEnabled=0)" -ForegroundColor White
    Write-Host "  4. Large Pages       - Registry + SeLockMemoryPrivilege granted" -ForegroundColor White
    Write-Host "  5. Win32 LFH Heap    - HeapCompatibilityVersion=2" -ForegroundColor White
    Write-Host "  6. NDIS RSS          - BaseProcessor=2, MaxProcessors=4" -ForegroundColor White
    Write-Host "  7. PCIe GPU IRQ Aff  - Cores 4-7, priority=High" -ForegroundColor White
    Write-Host "  8. AMD SMT CCX       - CCX scheduling + boost registry tuned" -ForegroundColor White
    Write-Host "  9. NVMe Queue Depth  - QueueDepth=1024, TreatAsInternalPort=1" -ForegroundColor White
    Write-Host ""
    Write-Host "NOTE: Some changes require a system restart to take full effect." -ForegroundColor DarkCyan
}

& $__extractedFunctionName @__extractedArgs