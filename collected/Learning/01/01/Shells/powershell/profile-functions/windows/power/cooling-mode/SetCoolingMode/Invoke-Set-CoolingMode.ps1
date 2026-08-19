# Extracted from C:\users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1.
# The live profile keeps a thin launcher and dot-sources this script.
$__extractedFunctionName = 'Set-CoolingMode'
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

function Set-CoolingMode {
    param(
        [ValidateSet("Silent","Performance","Turbo")]
        [string]$ThrottleMode = "Performance",
        [ValidateSet("Balanced","UltimatePerfA","Nuclear")]
        [string]$PowerPlan = "Balanced",
        [int]$CPUMin = 50,
        [int]$CPUMax = 100,
        [bool]$KillHeavyProcesses = $false,
        [string]$Label,
        [string]$Color = "Cyan",
        [int]$TierNum = -1
    )

    Write-Host ""
    Write-Host "[$Label]" -ForegroundColor $Color
    Write-Host "============================================" -ForegroundColor DarkGray

    # 1. Set ASUS Throttle Mode via InitialSetting.ini
    $iniPath = "C:\ProgramData\ASUS\ARMOURY CRATE Config\Data\InitialSetting.ini"
    $throttleValue = $script:AsusThrottleModes[$ThrottleMode]
    if (Test-Path $iniPath) {
        try {
            $content = Get-Content $iniPath -Raw
            $newContent = $content -replace 'ThrottleModeOnAC=\d', "ThrottleModeOnAC=$throttleValue"
            $newContent = $newContent -replace 'ThrottleModeOnDC=\d', "ThrottleModeOnDC=$throttleValue"
            Set-Content $iniPath $newContent -Force
            Write-Host "[THROTTLE] $ThrottleMode (Mode $throttleValue)" -ForegroundColor $(if($ThrottleMode -eq "Silent"){"Green"}elseif($ThrottleMode -eq "Turbo"){"Magenta"}else{"Yellow"})
        } catch {
            Write-Host "[THROTTLE] Failed to update: Run as Admin" -ForegroundColor Red
        }
    } else {
        Write-Host "[THROTTLE] Config not found" -ForegroundColor Red
    }

    # 2. Set Power Plan
    $planGUIDs = @{
        "Balanced" = "381b4222-f694-41f0-9685-ff5bb260df2e"
        "UltimatePerfA" = "7d5aaf84-c743-4470-9f38-fde1729a8a29"
        "Nuclear" = "e7b3c3f6-7f35-4f4c-8b48-8f1ece9cd139"
    }
    $guid = $planGUIDs[$PowerPlan]
    if ($guid) {
        powercfg /setactive $guid 2>$null
        Write-Host "[POWER] $PowerPlan" -ForegroundColor $(if($PowerPlan -eq "Nuclear"){"Magenta"}elseif($PowerPlan -eq "UltimatePerfA"){"Yellow"}else{"Green"})
    }

    # 3. Set CPU Min/Max processor states (apply to actual plan GUID, not SCHEME_CURRENT alias)
    try {
        # Get actual GUID of current scheme
        $schemeOutput = powercfg /getactivescheme 2>$null
        if ($schemeOutput -match '([0-9a-fA-F-]{36})') {
            $schemeGuid = $matches[1]
            # Set min processor state (AC and DC)
            powercfg /setacvalueindex $schemeGuid SUB_PROCESSOR PROCTHROTTLEMIN $CPUMin 2>$null
            powercfg /setdcvalueindex $schemeGuid SUB_PROCESSOR PROCTHROTTLEMIN $CPUMin 2>$null
            # Set max processor state (AC and DC)
            powercfg /setacvalueindex $schemeGuid SUB_PROCESSOR PROCTHROTTLEMAX $CPUMax 2>$null
            powercfg /setdcvalueindex $schemeGuid SUB_PROCESSOR PROCTHROTTLEMAX $CPUMax 2>$null
            # Reapply the scheme to activate changes
            powercfg /setactive $schemeGuid 2>$null
        }
        Write-Host "[CPU] $CPUMin% - $CPUMax%" -ForegroundColor $(if($CPUMax -le 50){"Green"}elseif($CPUMax -le 80){"Yellow"}else{"Cyan"})
    } catch {
        Write-Host "[CPU] Failed to set: $_" -ForegroundColor Red
    }

    # 4. GPU info (nvidia-smi -pl not supported on laptop GPUs - controlled by ASUS throttle mode)
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        $gpuInfo = nvidia-smi --query-gpu=power.draw,temperature.gpu --format=csv,noheader,nounits 2>$null
        if ($gpuInfo) {
            $parts = $gpuInfo -split ','
            $draw = [math]::Round([float]$parts[0].Trim())
            $temp = $parts[1].Trim()
            Write-Host "[GPU] ${draw}W draw | ${temp}C (controlled by Throttle Mode)" -ForegroundColor $(if([int]$temp -lt 50){"Green"}elseif([int]$temp -lt 70){"Yellow"}else{"Red"})
        }
    }

    # 5. Kill heavy background processes if requested
    if ($KillHeavyProcesses) {
        $heavyProcesses = @(
            "OneDrive", "Dropbox", "GoogleDrive", "iCloudServices",
            "Teams", "Slack", "Spotify", "iTunes",
            "SearchIndexer", "WSearch", "SysMain"
        )
        $killed = 0
        foreach ($proc in $heavyProcesses) {
            $procs = Get-Process -Name $proc -ErrorAction SilentlyContinue
            if ($procs) {
                $procs | Stop-Process -Force -ErrorAction SilentlyContinue
                $killed++
            }
        }
        $services = @("SysMain", "WSearch")
        foreach ($svc in $services) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        }
        if ($killed -gt 0) {
            Write-Host "[CLEANUP] Killed $killed heavy processes" -ForegroundColor Yellow
        }
    }

    # 6. Clear memory if coolmax
    if ($ThrottleMode -eq "Turbo" -and $CPUMax -eq 100) {
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        Write-Host "[MEMORY] GC collected" -ForegroundColor DarkCyan
    }

    # 7. MSI Afterburner: fan curve + power limit + mem offset - ALL scale linearly by tier
    # cool1: Fan=30%, PowerLimit=50%, MemOffset=0  ???  cool220: Fan=100%, PowerLimit=111%, MemOffset=200
    $tierNum = $TierNum  # use explicit param if provided
    if ($tierNum -le 0) {
        # fallback: scan all call stack frames for cool(\d+)
        $tierNum = 110
        foreach ($frame in (Get-PSCallStack)) {
            if ($frame.Command -match 'cool(\d+)') { $tierNum = [int]$Matches[1]; break }
            if ($frame.Location -match 'cool(\d+)\.ps1') { $tierNum = [int]$Matches[1]; break }
        }
    }
    if ($tierNum -ge 220) {
        $fanSpeed   = 100
        $pwrLimit   = 111
        $memOffset  = 200
    } else {
        $fanSpeed  = [int](30 + ($tierNum - 1) * (70.0 / 219))
        $pwrLimit  = [int](50 + ($tierNum - 1) * (61.0 / 219))
        $memOffset = [int](($tierNum - 1) * (200.0 / 219))
        if ($fanSpeed  -lt 30)  { $fanSpeed  = 30 }
        if ($fanSpeed  -gt 99)  { $fanSpeed  = 99 }
        if ($pwrLimit  -lt 50)  { $pwrLimit  = 50 }
        if ($pwrLimit  -gt 110) { $pwrLimit  = 110 }
        if ($memOffset -lt 0)   { $memOffset = 0 }
    }
    _SetGpuFanDirect -FanPct $fanSpeed -PowerLimitPct $pwrLimit

    Write-Host "============================================" -ForegroundColor DarkGray
    Write-Host ""
}

& $__extractedFunctionName @__extractedArgs