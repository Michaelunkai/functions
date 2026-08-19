Set-StrictMode -Version 2.0

function Get-LocalAIHardwareProfile {
    $computer = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|GeForce|RTX|Quadro|Tesla|CUDA' }
    $nvidiaSmi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    $smiRows = @()
    if ($nvidiaSmi) {
        try {
            $raw = & $nvidiaSmi.Source --query-gpu=name,memory.total,memory.free,driver_version,pci.bus_id,compute_cap --format=csv,noheader,nounits 2>$null
            foreach ($line in $raw) {
                $parts = $line -split '\s*,\s*'
                if ($parts.Count -ge 6) {
                    $smiRows += [pscustomobject]@{
                        Name = $parts[0]
                        TotalVramMiB = [int]$parts[1]
                        FreeVramMiB = [int]$parts[2]
                        DriverVersion = $parts[3]
                        PciBusId = $parts[4]
                        ComputeCapability = $parts[5]
                    }
                }
            }
        } catch {}
    }
    $primary = $null
    if ($smiRows.Count -gt 0) {
        $primary = $smiRows | Sort-Object TotalVramMiB -Descending | Select-Object -First 1
    } elseif ($gpus) {
        $gpu = $gpus | Sort-Object AdapterRAM -Descending | Select-Object -First 1
        $primary = [pscustomobject]@{
            Name = $gpu.Name
            TotalVramMiB = [math]::Floor([double]$gpu.AdapterRAM / 1MB)
            FreeVramMiB = $null
            DriverVersion = $gpu.DriverVersion
            PciBusId = $null
            ComputeCapability = $null
        }
    }
    $ramMiB = [math]::Floor([double]$computer.TotalPhysicalMemory / 1MB)
    $logical = [int]$cpu.NumberOfLogicalProcessors
    $profile = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        ComputerName = $env:COMPUTERNAME
        CpuName = $cpu.Name
        PhysicalCores = [int]$cpu.NumberOfCores
        LogicalProcessors = $logical
        SystemRamMiB = $ramMiB
        NvidiaGpu = $primary
        AllNvidiaGpus = $smiRows
        HasNvidiaSmi = [bool]$nvidiaSmi
        RecommendedThreads = [math]::Max(1, [math]::Min($logical - 1, $logical))
        VramBudgetMiB = if ($primary -and $primary.TotalVramMiB) { [math]::Floor([double]$primary.TotalVramMiB * 0.88) } else { 0 }
        PowerPlanBefore = (& powercfg /getactivescheme 2>$null)
    }
    return $profile
}

function Enable-LocalAIPerformanceMode {
    param([switch]$SkipMutation)
    if ($SkipMutation) { return [pscustomobject]@{ Mutated = $false; Reason = 'SkipMutation' } }
    $before = & powercfg /getactivescheme 2>$null
    $root = Get-ProjectRoot
    Save-Json -InputObject ([pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        ActiveSchemeBefore = $before
        MutatedSettings = @(
            @{ Sub = 'SUB_PROCESSOR'; Setting = 'PROCTHROTTLEMIN'; Value = 100 },
            @{ Sub = 'SUB_PROCESSOR'; Setting = 'PROCTHROTTLEMAX'; Value = 100 },
            @{ Sub = 'SUB_PROCESSOR'; Setting = 'SYSCOOLPOL'; Value = 1 },
            @{ Sub = 'SUB_PCIEXPRESS'; Setting = 'ASPM'; Value = 0 }
        )
    }) -Path (Join-Path $root 'state\power-rollback.json')
    & powercfg /setactive SCHEME_MIN | Out-Null
    $settings = @(
        @{ Sub = 'SUB_PROCESSOR'; Setting = 'PROCTHROTTLEMIN'; Value = 100 },
        @{ Sub = 'SUB_PROCESSOR'; Setting = 'PROCTHROTTLEMAX'; Value = 100 },
        @{ Sub = 'SUB_PROCESSOR'; Setting = 'SYSCOOLPOL'; Value = 1 },
        @{ Sub = 'SUB_PCIEXPRESS'; Setting = 'ASPM'; Value = 0 }
    )
    foreach ($s in $settings) {
        & powercfg /setacvalueindex SCHEME_CURRENT $s.Sub $s.Setting $s.Value 2>$null | Out-Null
    }
    & powercfg /setactive SCHEME_CURRENT | Out-Null
    return [pscustomobject]@{ Mutated = $true; PowerPlanBefore = $before; PowerPlanAfter = (& powercfg /getactivescheme 2>$null) }
}

Export-ModuleMember -Function *
