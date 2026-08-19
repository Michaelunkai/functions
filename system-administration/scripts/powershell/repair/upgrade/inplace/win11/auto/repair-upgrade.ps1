#Requires -RunAsAdministrator
# repair-upgrade.ps1 - Fully automatic Windows 11 in-place repair upgrade
# Extracts ISO to durable project-owned storage so migcore.dll and all migration DLLs are local
# Zero manual steps. Zero errors. Run elevated and walk away.

param(
    [string]$IsoSource = "F:\isos\Windows.iso",
    [string]$ExtractDir = "F:\study\Platforms\windows\system-administration\scripts\powershell\repair\upgrade\inplace\win11\auto\runtime\WinSetup",
    [string]$LocalIso = "F:\study\Platforms\windows\system-administration\scripts\powershell\repair\upgrade\inplace\win11\auto\cache\Windows.iso",
    [string]$LatestUpdateDownloadDir = "F:\study\Platforms\windows\system-administration\scripts\powershell\repair\upgrade\inplace\win11\auto\downloads\updates",
    [switch]$DisableDynamicUpdate,
    [switch]$SkipLatestUpdateDownload,
    [switch]$ForceClearRebootPending,
    [switch]$VerifyAutomationOnly,
    [switch]$VerifyIsoPreparationOnly,
    [switch]$VerifyCleanupOnly,
    [int]$MonitorExistingSetupProcessId = 0,
    [switch]$RegisterPostBootOnly,
    [string]$PostBootCommand = 'c; rrm windows.old',
    [Parameter(ValueFromRemainingArguments = $true)][object[]]$RemainingArgs
)

$ErrorActionPreference = 'Stop'
$host.UI.RawUI.WindowTitle = "Repair Upgrade - Automated"
$script:RepairUpgradeScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:RepairUpgradePostBootRoot = Join-Path $script:RepairUpgradeScriptRoot 'postboot'
$script:RepairUpgradeTracePath = $env:REPAIR_UPGRADE_TRACE_PATH
$script:RepairUpgradeTracingEnabled = -not [string]::IsNullOrWhiteSpace($script:RepairUpgradeTracePath)
$script:RepairUpgradeProgressId = 19421
$script:RepairUpgradeProgressPercent = -1
$script:RepairUpgradeProgressStatus = ''
$script:RepairUpgradeStartedAt = Get-Date
$script:RepairUpgradeLaunchDeadline = $script:RepairUpgradeStartedAt.AddMinutes(30)
$script:RepairUpgradeLaunchProofPath = Join-Path $script:RepairUpgradePostBootRoot 'setup-launch-proof.json'

if (-not $PSBoundParameters.ContainsKey('ForceClearRebootPending')) {
    $ForceClearRebootPending = $true
}

function Write-TraceLine($msg) {
    if (-not $script:RepairUpgradeTracingEnabled) { return }
    Add-Content -LiteralPath $script:RepairUpgradeTracePath -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $msg) -Encoding ASCII
}
function Get-RepairUpgradePercentForStep($StepId) {
    switch -Regex ([string]$StepId) {
        '^VERIFY$' { return 5 }
        '^0$'      { return 2 }
        '^0B$'     { return 8 }
        '^0A$'     { return 12 }
        '^1$'      { return 18 }
        '^2$'      { return 26 }
        '^3$'      { return 36 }
        '^4$'      { return 44 }
        '^5$'      { return 50 }
        '^6$'      { return 56 }
        '^7$'      { return 62 }
        '^8$'      { return 68 }
        '^9$'      { return 74 }
        '^10$'     { return 80 }
        '^11$'     { return 86 }
        '^12$'     { return 92 }
        default    { return $script:RepairUpgradeProgressPercent }
    }
}
function Update-RepairUpgradeProgress {
    param(
        [string]$Activity = 'Windows Repair Upgrade Automation',
        [string]$Status,
        [int]$PercentComplete = -1
    )

    if ($PercentComplete -lt 0) { $PercentComplete = $script:RepairUpgradeProgressPercent }
    $script:RepairUpgradeProgressPercent = $PercentComplete
    if ($PSBoundParameters.ContainsKey('Status')) {
        $script:RepairUpgradeProgressStatus = $Status
    } else {
        $Status = $script:RepairUpgradeProgressStatus
    }
    try {
        New-Item -ItemType Directory -Path $script:RepairUpgradeRuntimeRoot -Force | Out-Null
        [pscustomobject]@{
            StartedAt = $script:RepairUpgradeStartedAt.ToString('o')
            UpdatedAt = (Get-Date).ToString('o')
            LaunchDeadline = $script:RepairUpgradeLaunchDeadline.ToString('o')
            Activity = $Activity
            Status = $Status
            PercentComplete = $PercentComplete
            LaunchProofPath = $script:RepairUpgradeLaunchProofPath
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:RepairUpgradeProgressPath -Encoding ASCII
    } catch {
        Write-TraceLine "progress-json-write failed: $($_.Exception.Message)"
    }
    Write-Progress -Id $script:RepairUpgradeProgressId -Activity $Activity -Status $Status -PercentComplete $PercentComplete
}
function Complete-RepairUpgradeProgress {
    Update-RepairUpgradeProgress -Status 'Complete' -PercentComplete 100
    Write-Progress -Id $script:RepairUpgradeProgressId -Activity 'Windows Repair Upgrade Automation' -Completed
}
function Assert-RepairUpgradeLaunchDeadline {
    param([string]$StepId)

    if ([string]$StepId -in @('12', 'MONITOR', 'VERIFY')) { return }
    if ((Get-Date) -le $script:RepairUpgradeLaunchDeadline) { return }

    $deadlineText = $script:RepairUpgradeLaunchDeadline.ToString('yyyy-MM-dd HH:mm:ss')
    Write-Fail "Repair-upgrade launch deadline passed before setup.exe started. Deadline was $deadlineText; refusing to drift past the 30-minute start contract."
}

function Write-Step($n, $msg) {
    Assert-RepairUpgradeLaunchDeadline -StepId $n
    $percent = Get-RepairUpgradePercentForStep -StepId $n
    Update-RepairUpgradeProgress -Status ("Step {0}: {1}" -f $n, $msg) -PercentComplete $percent
    Write-TraceLine "STEP[$n] $msg"
    Write-Host "`n[$n] $msg" -ForegroundColor Cyan
}
function Write-Ok($msg)      { Update-RepairUpgradeProgress -Status $msg; Write-TraceLine "OK $msg"; Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Fail($msg)    { Update-RepairUpgradeProgress -Status $msg; Write-TraceLine "FAIL $msg"; Write-Host "    [FAIL] $msg" -ForegroundColor Red; throw $msg }
function Write-Warn($msg)    { Update-RepairUpgradeProgress -Status $msg; Write-TraceLine "WARN $msg"; Write-Host "    [WARN] $msg" -ForegroundColor Yellow }
function Write-BlockedRebootPending($msg) {
    Update-RepairUpgradeProgress -Status $msg
    Write-TraceLine "WARN_LEGACY $msg"
    Write-Host "    [WARN] $msg" -ForegroundColor Yellow
    $script:WINUPG_BLOCKED_REASON = $msg
}
function Normalize-RepairUpgradeLooseArguments {
    foreach ($extraArg in @($RemainingArgs)) {
        if ($extraArg -isnot [string]) { continue }
        if ($extraArg -match '^-ForceClearRebootPending[-_A-Za-z0-9]+$') {
            $script:RepairUpgradeNormalizedForceClearAlias = $extraArg
            $script:ForceClearRebootPending = $true
        }
    }
}
function Find-SevenZipExecutable {
    $candidates = @(
        'F:\tools\7-Zip\7z.exe',
        'F:\scoop\shims\7z.exe',
        'F:\scoop\apps\7zip\current\7z.exe',
        'F:\study\Tools\7-Zip\7z.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return (Get-Item -LiteralPath $candidate -Force).FullName }
    }
    $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source) -and ($cmd.Source -notlike 'C:\*')) { return $cmd.Source }
    return $null
}
function Enable-VolumeAutomount {
    $mountvol = Join-Path $env:SystemRoot 'System32\mountvol.exe'
    if (-not (Test-Path -LiteralPath $mountvol)) {
        Write-Warn "mountvol.exe was not found; continuing without changing automount state."
        return
    }

    & $mountvol /E | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Windows volume automount is enabled."
    } else {
        Write-Warn "mountvol /E exited with code $LASTEXITCODE; continuing with ISO mount fallback checks."
    }
}
function Invoke-ExplorerIsoMount {
    param(
        [Parameter(Mandatory=$true)][string]$IsoPath
    )

    $shell = New-Object -ComObject Shell.Application
    $parentPath = Split-Path -Path $IsoPath -Parent
    $leafName = Split-Path -Path $IsoPath -Leaf
    $namespace = $shell.Namespace($parentPath)
    if (-not $namespace) {
        throw "Explorer Shell namespace lookup failed for $parentPath"
    }

    $item = $namespace.ParseName($leafName)
    if (-not $item) {
        throw "Explorer Shell could not resolve $leafName under $parentPath"
    }

    $mountVerb = $item.Verbs() |
        Where-Object { $_.Name -replace '&','' -match '^\s*Mount\s*$' } |
        Select-Object -First 1
    if (-not $mountVerb) {
        throw "Explorer Shell did not expose a Mount verb for $IsoPath"
    }

    $mountVerb.DoIt()
}
function Mount-WindowsIso {
    param(
        [Parameter(Mandatory=$true)][string]$IsoPath
    )

    $mountDiskImage = Get-Command -Name Mount-DiskImage -ErrorAction SilentlyContinue
    if ($mountDiskImage) {
        try {
            $null = Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop
            return 'StorageCmdlet'
        } catch {
            Write-Warn "Mount-DiskImage reported '$($_.Exception.Message)'; trying Explorer mount fallback."
        }
    } else {
        Write-Warn "Mount-DiskImage is unavailable on this machine; trying Explorer mount fallback."
    }

    Invoke-ExplorerIsoMount -IsoPath $IsoPath
    return 'ExplorerVerb'
}
function Invoke-RobocopyTree {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$true)][string]$DestinationPath
    )

    & robocopy $SourcePath $DestinationPath /E /MT:8 /NFL /NDL /NJH /NJS /R:2 /W:1 | Out-Null
    if ($LASTEXITCODE -gt 7) {
        throw "Robocopy from $SourcePath to $DestinationPath failed with exit code $LASTEXITCODE"
    }
}
# ALLOW_DESTRUCTIVE: Step 4 removes only stale Windows setup folders C:\$WINDOWS.~BT and C:\$Windows.~WS with bounded timeouts and visible progress.
function Invoke-RepairUpgradeBoundedNativeCommand {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$ArgumentList,
        [Parameter(Mandatory=$true)][string]$Label,
        [int]$TimeoutSeconds = 120
    )

    Write-Host ("    {0} ..." -f $Label) -ForegroundColor DarkCyan
    Write-TraceLine ("NATIVE begin {0}" -f $Label)
    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -WindowStyle Hidden
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $nextPulse = 5
    while (-not $process.HasExited) {
        Start-Sleep -Seconds 1
        if ($stopwatch.Elapsed.TotalSeconds -ge $nextPulse) {
            $status = "{0} running for {1}s" -f $Label, [int]$stopwatch.Elapsed.TotalSeconds
            Update-RepairUpgradeProgress -Status $status
            Write-Host ("    [WORKING] {0}" -f $status) -ForegroundColor DarkGray
            Write-TraceLine ("NATIVE pulse {0}" -f $status)
            $nextPulse += 5
        }
        if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "{0} timed out after {1} seconds" -f $Label, $TimeoutSeconds
        }
    }
    $process.WaitForExit()
    Write-TraceLine ("NATIVE end {0} exit={1}" -f $Label, $process.ExitCode)
    return $process.ExitCode
}
function Remove-RepairUpgradeFolderSafely {
    param(
        [Parameter(Mandatory=$true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Ok "$Path already clean"
        return
    }

    $cmdPath = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $tryFastRemove = {
        param(
            [Parameter(Mandatory=$true)][string]$TargetPath,
            [Parameter(Mandatory=$true)][string]$Label
        )

        try {
            $exitCode = Invoke-RepairUpgradeBoundedNativeCommand -FilePath $cmdPath -ArgumentList @('/d', '/c', "rd /s /q `"$TargetPath`" >nul 2>nul") -Label $Label -TimeoutSeconds 10
            if ($exitCode -ne 0) {
                Write-Warn "$Label exited with code $exitCode"
            }
        } catch {
            Write-Warn $_.Exception.Message
        }
    }

    Write-Host ("    Attempting fast child-first removal of {0} ..." -f $Path) -ForegroundColor DarkCyan
    Write-TraceLine ("REMOVE child-first begin {0}" -f $Path)
    $childItems = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    foreach ($childItem in $childItems) {
        & $tryFastRemove $childItem.FullName ("fast remove {0}" -f $childItem.FullName)
    }
    & $tryFastRemove $Path ("fast remove {0}" -f $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-TraceLine ("REMOVE child-first success {0}" -f $Path)
        Write-Ok "Removed $Path"
        return
    }

    try {
        $takeownExit = Invoke-RepairUpgradeBoundedNativeCommand -FilePath (Join-Path $env:SystemRoot 'System32\takeown.exe') -ArgumentList @('/f', $Path, '/r', '/d', 'y') -Label ("takeown {0}" -f $Path) -TimeoutSeconds 45
        if ($takeownExit -ne 0) {
            Write-Warn "takeown exited with code $takeownExit for $Path"
        }
    } catch {
        Write-Warn $_.Exception.Message
    }
    try {
        $icaclsExit = Invoke-RepairUpgradeBoundedNativeCommand -FilePath (Join-Path $env:SystemRoot 'System32\icacls.exe') -ArgumentList @($Path, '/grant', 'administrators:F', '/t') -Label ("icacls {0}" -f $Path) -TimeoutSeconds 45
        if ($icaclsExit -ne 0) {
            Write-Warn "icacls exited with code $icaclsExit for $Path"
        }
    } catch {
        Write-Warn $_.Exception.Message
    }

    Write-Host ("    Final removal of {0} ..." -f $Path) -ForegroundColor DarkCyan
    try {
        $finalExit = Invoke-RepairUpgradeBoundedNativeCommand -FilePath $cmdPath -ArgumentList @('/d', '/c', "attrib -r `"$Path\*`" /s /d >nul 2>nul & rd /s /q `"$Path`" >nul 2>nul") -Label ("final remove {0}" -f $Path) -TimeoutSeconds 10
        if ($finalExit -ne 0) {
            Write-Warn "final remove exited with code $finalExit for $Path"
        }
    } catch {
        Write-Warn $_.Exception.Message
    }
    if (Test-Path -LiteralPath $Path) {
        if ($Path -ieq 'C:\$WINDOWS.~BT') {
            Write-Fail "Could not fully remove $Path; Windows Setup will fail with 0xC1900107 while this stale setup folder is locked. Close any Setup/Explorer windows using it or reboot once, then rerun WINUPG."
        }
        Write-Warn "Could not fully remove $Path"
    } else {
        Write-Ok "Removed $Path"
    }
}
function Get-RepairUpgradeSetupLogSnapshot {
    $candidateLogs = @(
        'C:\$WINDOWS.~BT\Sources\Panther\setupact.log',
        'C:\$WINDOWS.~BT\Sources\Rollback\setupact.log'
    )
    $logPath = $candidateLogs | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $logPath) {
        return [pscustomobject]@{
            Path = $null
            LastWriteTime = $null
            ProgressPercent = $null
            ActivityLine = $null
        }
    }

    $item = Get-Item -LiteralPath $logPath -Force
    $tail = @(Get-Content -LiteralPath $logPath -Tail 80 -ErrorAction SilentlyContinue)
    $progressPercent = $null
    $activityLine = $null
    $reversedTail = @($tail)
    [array]::Reverse($reversedTail)
    foreach ($line in $reversedTail) {
        if (-not $activityLine -and $line -match 'Overall progress: \[(\d+)%\]') {
            $progressPercent = [int]$Matches[1]
            $activityLine = $line.Trim()
            continue
        }
        if (-not $activityLine -and $line -match 'Action progress: \[(\d+)%\]') {
            $progressPercent = [int]$Matches[1]
            $activityLine = $line.Trim()
            continue
        }
        if (-not $activityLine -and $line -match 'SPWIMCallback: .*?Progress:\s*(\d+)') {
            $progressPercent = [int]$Matches[1]
            $activityLine = $line.Trim()
            continue
        }
        if (-not $activityLine -and $line -match 'Progress percentage \[(\d+)\]') {
            $progressPercent = [int]$Matches[1]
            $activityLine = $line.Trim()
            continue
        }
        if (-not $activityLine -and $line -match 'Transfer: .*?\[(\d+)%\]') {
            $progressPercent = [int]$Matches[1]
            $activityLine = $line.Trim()
            continue
        }
        if (-not $activityLine -and $line -match 'Executing download|Successfully acquired payload|Download progress|Installing|Finalize|Migration|Appraiser|Expanding|Extracting|Processing|Apply Deltas|Data migration complete|VALIDATION|Capabilities|provisioning|OPERATIONTRACK|QueueAddCbsPackage|Add \[\d+\] package|Machine-specific apply|Machine-independent apply|Complete servicing operations|Refresh localized strings|boot settings|DiskSpaceReq') {
            $activityLine = $line.Trim()
        }
        if ($progressPercent -ne $null -and $activityLine) { break }
    }

    return [pscustomobject]@{
        Path = $logPath
        LastWriteTime = $item.LastWriteTime
        ProgressPercent = $progressPercent
        ActivityLine = $activityLine
    }
}
function Get-RepairUpgradeSetupPhaseDefinition {
    param(
        [string]$ActivityLine
    )

    $line = [string]$ActivityLine
    $phaseName = 'Setup activity'
    $phaseStart = 92.00
    $phaseEnd = 99.40
    $expectedSeconds = 900

    if ($line -match 'Executing download|Successfully acquired payload|Download progress|Progress percentage \[') {
        $phaseName = 'Dynamic Update download'
        $phaseStart = 92.00
        $phaseEnd = 94.00
        $expectedSeconds = 600
    } elseif ($line -match 'Extracting \[|Expanding express|Found \d+ blobs|Extracted all files from container|Saving action list') {
        $phaseName = 'Dynamic Update extraction'
        $phaseStart = 94.00
        $phaseEnd = 95.60
        $expectedSeconds = 900
    } elseif ($line -match 'Started DPX phase|Ended DPX phase|Apply Deltas|Resume and Download Job|Transfer: ') {
        $phaseName = 'Delta package apply'
        $phaseStart = 95.60
        $phaseEnd = 97.20
        $expectedSeconds = 1800
    } elseif ($line -match 'QueueAddCbsPackage|Add \[\d+\] package|Expanding package:|Copying metadata contents|DiskSpaceReq|DUImageSandbox') {
        $phaseName = 'Servicing package staging'
        $phaseStart = 97.20
        $phaseEnd = 98.10
        $expectedSeconds = 1200
    } elseif ($line -match 'VALIDATION|Appraiser|Compat|Capabilities|OC Validator|LP Validator') {
        $phaseName = 'Validation'
        $phaseStart = 98.10
        $phaseEnd = 98.70
        $expectedSeconds = 900
    } elseif ($line -match 'Migration|MIG|Machine-specific apply|Machine-independent apply|Offline portion|Complete file operations|Execute provisioning migration|provisioning|SPWIMCallback|Overall progress:|Action progress:|Mapped Global progress') {
        $phaseName = 'Migration and apply'
        $phaseStart = 98.70
        $phaseEnd = 99.25
        $expectedSeconds = 1800
    } elseif ($line -match 'Finalize|Gather end install|Complete servicing operations|Start suspended services|Refresh localized strings|boot settings') {
        $phaseName = 'Finalize'
        $phaseStart = 99.25
        $phaseEnd = 99.70
        $expectedSeconds = 900
    }

    [pscustomobject]@{
        Name = $phaseName
        StartPercent = [double]$phaseStart
        EndPercent = [double]$phaseEnd
        ExpectedSeconds = [int]$expectedSeconds
    }
}
function Get-RepairUpgradeDisplayPercent {
    param(
        [double]$PhaseStartPercent,
        [double]$PhaseEndPercent,
        [datetime]$PhaseStartTime,
        [datetime]$LastSignalTime,
        [int]$ExpectedSeconds,
        [Nullable[int]]$LogProgressPercent,
        [bool]$HasFreshSignal
    )

    $displayPercent = [double]$PhaseStartPercent
    $phaseWidth = [Math]::Max(0.01, $PhaseEndPercent - $PhaseStartPercent)
    if ($LogProgressPercent -ne $null) {
        $normalizedLogProgress = [Math]::Min(1.0, [Math]::Max(0.0, ([double]$LogProgressPercent / 100.0)))
        $displayPercent = $PhaseStartPercent + ($phaseWidth * $normalizedLogProgress)
    } else {
        $phaseAgeSeconds = [Math]::Max(0.0, ((Get-Date) - $PhaseStartTime).TotalSeconds)
        $expectedSeconds = [Math]::Max(60, $ExpectedSeconds)
        $ratio = [Math]::Min(0.985, $phaseAgeSeconds / [double]$expectedSeconds)
        $displayPercent = $PhaseStartPercent + ($phaseWidth * $ratio)
    }

    if (-not $HasFreshSignal) {
        $signalAgeSeconds = [Math]::Max(0.0, ((Get-Date) - $LastSignalTime).TotalSeconds)
        if ($signalAgeSeconds -ge 30) {
            $displayPercent = [Math]::Max($PhaseStartPercent, $displayPercent - [Math]::Min(0.40, ($signalAgeSeconds - 30) / 300.0))
        }
    }

    return [Math]::Round([Math]::Min(99.90, [Math]::Max(92.00, $displayPercent)), 2)
}
function Get-ActiveRepairUpgradeSetupProcess {
    param(
        [string]$ExpectedExtractDir
    )

    $escapedExtractDir = if ($ExpectedExtractDir) { [regex]::Escape($ExpectedExtractDir) } else { $null }
    $candidates = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -in @('setup.exe', 'setupprep.exe', 'SetupHost.exe') -and (
            ($escapedExtractDir -and $_.CommandLine -match $escapedExtractDir) -or
            $_.CommandLine -match '\\\$WINDOWS\.\~BT\\Sources\\SetupHost\.exe' -or
            $_.CommandLine -match '\/Auto Upgrade'
        )
    })
    if (-not $candidates) { return $null }

    return $candidates |
        Sort-Object @{Expression = { if ($_.Name -ieq 'setup.exe') { 0 } elseif ($_.Name -ieq 'SetupHost.exe') { 1 } else { 2 } }}, CreationDate |
        Select-Object -First 1
}
function Wait-RepairUpgradeSetup {
    param(
        [Parameter(Mandatory=$true)]$Process,
        [int]$HeartbeatSeconds = 5,
        [int]$NoActivityTimeoutSeconds = 900
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastSignalTime = Get-Date
    $lastLogWriteTime = $null
    $lastReportedStatus = $null
    $lastProcessCpu = $null
    $phaseDefinition = Get-RepairUpgradeSetupPhaseDefinition -ActivityLine $null
    $phaseSignature = $phaseDefinition.Name
    $phaseStartTime = Get-Date

    while (-not $Process.HasExited) {
        Start-Sleep -Seconds 1
        try { $Process.Refresh() } catch { }

        $logSnapshot = Get-RepairUpgradeSetupLogSnapshot
        $logChanged = $logSnapshot.LastWriteTime -and ($lastLogWriteTime -ne $logSnapshot.LastWriteTime)
        if ($logChanged) {
            $lastLogWriteTime = $logSnapshot.LastWriteTime
            $lastSignalTime = Get-Date
        }
        $cpuAdvanced = $false
        if ($null -ne $Process.CPU) {
            if ($null -eq $lastProcessCpu) {
                $lastProcessCpu = $Process.CPU
            } elseif ($Process.CPU -gt $lastProcessCpu) {
                $cpuAdvanced = $true
                $lastProcessCpu = $Process.CPU
                $lastSignalTime = Get-Date
            }
        }

        $currentPhaseDefinition = Get-RepairUpgradeSetupPhaseDefinition -ActivityLine $logSnapshot.ActivityLine
        $currentPhaseSignature = '{0}|{1:0.00}|{2:0.00}' -f $currentPhaseDefinition.Name, $currentPhaseDefinition.StartPercent, $currentPhaseDefinition.EndPercent
        if ($currentPhaseSignature -ne $phaseSignature) {
            $phaseDefinition = $currentPhaseDefinition
            $phaseSignature = $currentPhaseSignature
            $phaseStartTime = Get-Date
            Write-TraceLine ("SETUP phase {0}" -f $phaseDefinition.Name)
        }

        if (($stopwatch.Elapsed.TotalSeconds % $HeartbeatSeconds) -lt 1) {
            $statusParts = @()
            $hasFreshSignal = $logChanged -or $cpuAdvanced
            $displayPercent = Get-RepairUpgradeDisplayPercent -PhaseStartPercent $phaseDefinition.StartPercent -PhaseEndPercent $phaseDefinition.EndPercent -PhaseStartTime $phaseStartTime -LastSignalTime $lastSignalTime -ExpectedSeconds $phaseDefinition.ExpectedSeconds -LogProgressPercent $logSnapshot.ProgressPercent -HasFreshSignal:$hasFreshSignal
            $percent = [Math]::Floor($displayPercent)
            $statusParts += ("setup {0:n2}% est" -f $displayPercent)
            $statusParts += ("phase {0}" -f $phaseDefinition.Name)
            if ($logSnapshot.ProgressPercent -ne $null) {
                $statusParts += ("DU signal {0}%" -f $logSnapshot.ProgressPercent)
            }
            $phaseAgeSeconds = [int]((Get-Date) - $phaseStartTime).TotalSeconds
            $statusParts += ("phase age {0}s" -f $phaseAgeSeconds)
            if ($logSnapshot.LastWriteTime) {
                $ageSeconds = [int]((Get-Date) - $logSnapshot.LastWriteTime).TotalSeconds
                $statusParts += ("log age {0}s" -f $ageSeconds)
            }
            if ($null -ne $Process.CPU) {
                $statusParts += ("cpu {0:n1}s" -f [double]$Process.CPU)
            }
            if ($cpuAdvanced -and -not $logChanged) {
                $statusParts += 'SetupHost CPU advancing'
            }
            if (-not $hasFreshSignal) {
                $signalAgeSeconds = [int]((Get-Date) - $lastSignalTime).TotalSeconds
                $statusParts += ("waiting for fresh setup signal {0}s" -f $signalAgeSeconds)
            }
            if ($logSnapshot.ActivityLine) {
                $statusParts += $logSnapshot.ActivityLine
            }
            if ($statusParts.Count -eq 0) {
                $statusParts += ("setup.exe running for {0}s" -f [int]$stopwatch.Elapsed.TotalSeconds)
            }
            $status = ($statusParts -join ' | ')
            Update-RepairUpgradeProgress -Status $status -PercentComplete $percent
            if ($status -ne $lastReportedStatus) {
                Write-Host ("    [WORKING] {0}" -f $status) -ForegroundColor DarkGray
                Write-TraceLine ("SETUP heartbeat {0}" -f $status)
                $lastReportedStatus = $status
            }
        }

        if (((Get-Date) - $lastSignalTime).TotalSeconds -ge $NoActivityTimeoutSeconds) {
            $diagnostic = if ($logSnapshot.ActivityLine) { $logSnapshot.ActivityLine } else { 'no recent setup log activity detected' }
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
            throw "Windows setup monitoring timed out after $NoActivityTimeoutSeconds seconds without activity: $diagnostic"
        }
    }

    $Process.WaitForExit()
}
function Convert-RepairUpgradeExitCodeToHex {
    param(
        [int]$ExitCode
    )

    if ($ExitCode -lt 0) {
        return ('0x{0:X8}' -f ([uint32]($ExitCode + 0x100000000L)))
    }
    return ('0x{0:X8}' -f ([uint32]$ExitCode))
}
function Get-RepairUpgradeBlueBoxSnapshot {
    $logPath = 'C:\Windows\Logs\MoSetup\BlueBox.log'
    if (-not (Test-Path -LiteralPath $logPath)) {
        return [pscustomobject]@{
            Path = $logPath
            Exists = $false
            MainHrHex = $null
            ProcessExitHex = $null
            DynamicUpdateDetected = $false
            DiagnosticFailureHex = $null
            TailLine = $null
        }
    }

    $tail = @(Get-Content -LiteralPath $logPath -Tail 200 -ErrorAction SilentlyContinue)
    $mainHrHex = $null
    $processExitHex = $null
    $diagnosticFailureHex = $null
    $tailLine = $null
    $dynamicUpdateDetected = $false
    $reversedTail = @($tail)
    [array]::Reverse($reversedTail)
    foreach ($line in $reversedTail) {
        if (-not $tailLine -and -not [string]::IsNullOrWhiteSpace($line)) {
            $tailLine = $line.Trim()
        }
        if (-not $mainHrHex -and $line -match 'MainHr: Error = (0x[0-9A-Fa-f]+)') {
            $mainHrHex = $Matches[1].ToUpperInvariant()
        }
        if (-not $processExitHex -and $line -match 'Process exit code: \[(0x[0-9A-Fa-f]+)\]') {
            $processExitHex = $Matches[1].ToUpperInvariant()
        }
        if (-not $diagnosticFailureHex -and $line -match 'Diagnostic Analysis failed \[(0x[0-9A-Fa-f]+)\]') {
            $diagnosticFailureHex = $Matches[1].ToUpperInvariant()
        }
        if (-not $dynamicUpdateDetected -and $line -match 'Dynamic update detected!') {
            $dynamicUpdateDetected = $true
        }
        if ($mainHrHex -and $processExitHex -and $tailLine -and ($dynamicUpdateDetected -or $diagnosticFailureHex)) {
            break
        }
    }

    return [pscustomobject]@{
        Path = $logPath
        Exists = $true
        MainHrHex = $mainHrHex
        ProcessExitHex = $processExitHex
        DynamicUpdateDetected = $dynamicUpdateDetected
        DiagnosticFailureHex = $diagnosticFailureHex
        TailLine = $tailLine
    }
}
function Dismount-WindowsIso {
    param(
        [Parameter(Mandatory=$true)][string]$IsoPath,
        [string]$DriveLetter
    )

    $dismountDiskImage = Get-Command -Name Dismount-DiskImage -ErrorAction SilentlyContinue
    if ($dismountDiskImage) {
        try {
            Dismount-DiskImage -ImagePath $IsoPath -ErrorAction Stop
            return 'StorageCmdlet'
        } catch {
            Write-Warn "Dismount-DiskImage reported '$($_.Exception.Message)'; leaving ISO mounted."
        }
    }
    return $null
}
function Get-RepairUpgradeCriticalRelativePaths {
    return @(
        'setup.exe',
        'sources\autorun.dll',
        'sources\migcore.dll',
        'sources\AppExtAgent.dll',
        'sources\dismapi.dll',
        'sources\mighost.exe',
        'sources\migstore.dll',
        'sources\setupcore.dll',
        'sources\setuphost.exe',
        'sources\setupplatform.dll',
        'sources\spwizeng.dll',
        'sources\unbcl.dll',
        'sources\unattend.dll',
        'sources\uxlib.dll',
        'sources\wdscore.dll',
        'sources\SetupPlatform.cfg'
    )
}
function Get-RepairUpgradeImageRelativePaths {
    return @('sources\install.esd','sources\install.wim')
}
function Test-RepairUpgradeExtractComplete {
    param(
        [Parameter(Mandatory=$true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    foreach ($relativePath in (Get-RepairUpgradeCriticalRelativePaths)) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path $relativePath))) {
            return $false
        }
    }
    foreach ($relativePath in (Get-RepairUpgradeImageRelativePaths)) {
        if (Test-Path -LiteralPath (Join-Path $Path $relativePath)) {
            return $true
        }
    }
    return $false
}
function Get-CdRomDriveLetters {
    try {
        return @(
            Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 5' -EA Stop |
                Where-Object { $_.DeviceID } |
                ForEach-Object { $_.DeviceID.TrimEnd(':') }
        )
    } catch {
        return @(
            [System.IO.DriveInfo]::GetDrives() |
                Where-Object { $_.DriveType -eq [System.IO.DriveType]::CDRom -and $_.IsReady } |
                ForEach-Object { $_.Name.Substring(0,1) }
        )
    }
}
function Test-WindowsSetupVolume($DriveLetter) {
    if (-not $DriveLetter) { return $false }
    $letter = ([string]$DriveLetter).TrimEnd(':','\')
    if ($letter.Length -ne 1) { return $false }
    $root = "${letter}:\"
    return (
        (Test-Path -LiteralPath (Join-Path $root 'setup.exe')) -and
        (Test-Path -LiteralPath (Join-Path $root 'sources\setuphost.exe'))
    )
}
function Resolve-WindowsIsoDriveLetter {
    param(
        [Parameter(Mandatory=$true)][string]$IsoPath,
        [string[]]$BeforeDriveLetters = @()
    )

    $deadline = (Get-Date).AddSeconds(30)
    do {
        $valid = @(
            Get-CdRomDriveLetters |
                Where-Object { Test-WindowsSetupVolume $_ } |
                Select-Object -Unique
        )
        $newValid = @($valid | Where-Object { $BeforeDriveLetters -notcontains $_ })
        if ($newValid.Count -eq 1) { return $newValid[0] }
        if ($valid.Count -eq 1) { return $valid[0] }
        if ($newValid.Count -gt 1) {
            Write-Fail "Multiple new Windows setup ISO volumes were found after mounting ${IsoPath}: $($newValid -join ', ')"
        }
        if ($valid.Count -gt 1) {
            Write-Fail "Multiple Windows setup ISO volumes are mounted; cannot safely choose one: $($valid -join ', ')"
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    throw "ISO mounted but no Windows setup drive letter was found"
}
function Get-PendingFileRenameOperationsValue {
    $sessionManager = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -EA SilentlyContinue
    if (-not $sessionManager) { return $null }
    $property = $sessionManager.PSObject.Properties['PendingFileRenameOperations']
    if (-not $property) { return $null }
    return $property.Value
}
function Invoke-RebootPendingGate {
    param(
        [string]$PendingFileRenameMessage = 'PendingFileRenameOperations contains {0} entries.',
        [switch]$CheckRegistryFlags
    )

    $pfro = Get-PendingFileRenameOperationsValue
    if ($pfro) {
        Remove-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -Force -EA SilentlyContinue
        $pfroAfterClear = Get-PendingFileRenameOperationsValue
        if (-not $pfroAfterClear) {
            Write-Warn "Force-cleared $($pfro.Count) entries"
        } else {
            Write-Warn (("{0} Auto-clear attempted but {1} entries still remain; continuing anyway." -f ($PendingFileRenameMessage -f $pfro.Count), $pfroAfterClear.Count))
        }
    } else {
        Write-Ok "None pending"
    }

    if ($CheckRegistryFlags) {
        $paths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        )
        foreach ($rp in $paths) {
            if (Test-Path $rp) {
                Remove-Item $rp -Force -EA SilentlyContinue
                if (-not (Test-Path $rp)) {
                    Write-Warn "Force-cleared $(Split-Path $rp -Leaf)"
                } else {
                    Write-Warn "A reboot-pending flag remains at $rp after auto-clear attempt; continuing anyway."
                }
            }
        }
    }

    return $true
}
function Test-PortableExecutableFile($Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force -EA SilentlyContinue
    if (-not $item -or $item.Length -lt 128) { return $false }
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object System.IO.BinaryReader($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) { return $false }
        $stream.Seek(60, [System.IO.SeekOrigin]::Begin) | Out-Null
        $peOffset = $reader.ReadInt32()
        if ($peOffset -le 0 -or $peOffset -gt ($stream.Length - 6)) { return $false }
        $stream.Seek($peOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
        if ($reader.ReadUInt32() -ne 0x00004550) { return $false }
        return $reader.ReadUInt16() -ne 0
    } finally {
        $stream.Dispose()
    }
}
function Repair-InvalidExtractedPortableExecutables($SourceRoot, $DestinationRoot) {
    $invalid = @(
        Get-ChildItem -LiteralPath $DestinationRoot -Recurse -File -EA SilentlyContinue |
            Where-Object { $_.Extension -in '.dll', '.exe' -and -not (Test-PortableExecutableFile $_.FullName) }
    )
    if ($invalid.Count -eq 0) { Write-Ok "Portable executable validation passed."; return }
    Write-Host "    [WARN] Found $($invalid.Count) invalid extracted executable image(s); recopying them safely..." -ForegroundColor Yellow
    foreach ($file in $invalid) {
        $relativePath = $file.FullName.Substring($DestinationRoot.TrimEnd('\').Length).TrimStart('\')
        $sourcePath = Join-Path $SourceRoot $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath)) { Write-Fail "Source file missing during repair: $relativePath" }
        Copy-Item -LiteralPath $sourcePath -Destination $file.FullName -Force
        if (-not (Test-PortableExecutableFile $file.FullName)) { Write-Fail "Repaired file is still invalid: $relativePath" }
        Write-Ok "Repaired $relativePath"
    }
    Write-Ok "Portable executable validation passed after repair copy."
}
function Get-CurrentWindowsBuildInfo {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int]$cv.CurrentBuild
    $ubr = 0
    if ($null -ne $cv.UBR) { $ubr = [int]$cv.UBR }
    [pscustomobject]@{
        ProductName    = $cv.ProductName
        DisplayVersion = $cv.DisplayVersion
        EditionID      = $cv.EditionID
        Build          = $build
        UBR            = $ubr
        FullBuild      = "$build.$ubr"
        Architecture   = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
    }
}
function Get-LatestWindows11ReleaseInfo {
    param([string]$DisplayVersion)

    if (-not $DisplayVersion) { Write-Warn "DisplayVersion is empty; skipping latest-build lookup."; return $null }
    $url = 'https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information'
    Write-Host "    Checking Microsoft release info: $url"
    $page = Invoke-WebRequest -Uri $url -UseBasicParsing
    $text = [System.Net.WebUtility]::HtmlDecode(($page.Content -replace '<[^>]+>', ' '))
    $text = $text -replace '\s+', ' '

    $versionPattern = [regex]::Escape($DisplayVersion)
    $pattern = "$versionPattern\s+General Availability Channel\s+\d{4}-\d{2}-\d{2}\s+\d{4}-\d{2}-\d{2}\s+\d{4}-\d{2}-\d{2}\s+.*?\s+(\d{4}-\d{2}-\d{2})\s+(\d+\.\d+)"
    $match = [regex]::Match($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        $historyPattern = "Version\s+$versionPattern\s+\(OS build\s+\d+\).*?General Availability Channel\s+.*?\s+(\d{4}-\d{2}-\d{2})\s+(\d+\.\d+)\s+KB(\d+)"
        $match = [regex]::Match($text, $historyPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    if (-not $match.Success) { Write-Warn "Could not parse latest build for Windows 11 $DisplayVersion from Microsoft release info."; return $null }

    $latestBuild = $match.Groups[2].Value
    $kbMatch = [regex]::Match($text, "General Availability Channel\s+.*?\s+$([regex]::Escape($latestBuild))\s+KB(\d+)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $kb = $null
    if ($kbMatch.Success) { $kb = $kbMatch.Groups[1].Value }

    [pscustomobject]@{
        DisplayVersion = $DisplayVersion
        LatestBuild    = $latestBuild
        ReleaseDate    = $match.Groups[1].Value
        KB             = $kb
        Source         = $url
    }
}
function Get-MicrosoftCatalogDownloadUrls {
    param(
        [Parameter(Mandatory=$true)][string]$KB,
        [Parameter(Mandatory=$true)][string]$DisplayVersion,
        [Parameter(Mandatory=$true)][string]$LatestBuild
    )

    $searchUrl = "https://www.catalog.update.microsoft.com/Search.aspx?q=KB$KB"
    Write-Host "    Checking Microsoft Update Catalog: $searchUrl"
    $search = Invoke-WebRequest -Uri $searchUrl -UseBasicParsing
    $ids = @(
        [regex]::Matches($search.Content, 'ScopedViewInline\.aspx\?updateid=([0-9a-f-]{36})', 'IgnoreCase') |
            ForEach-Object { $_.Groups[1].Value } |
            Select-Object -Unique
    )
    foreach ($id in $ids) {
        $detailUrl = "https://www.catalog.update.microsoft.com/ScopedViewInline.aspx?updateid=$id"
        $detail = Invoke-WebRequest -Uri $detailUrl -UseBasicParsing
        $plain = [System.Net.WebUtility]::HtmlDecode(($detail.Content -replace '<[^>]+>', ' '))
        if ($plain -match 'x64-based Systems' -and $plain -match [regex]::Escape($DisplayVersion) -and $plain -match [regex]::Escape($LatestBuild)) {
            $payload = '[{"size":0,"languages":"","uidInfo":"' + $id + '","updateID":"' + $id + '"}]'
            $downloadUrl = 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx?updateIDs=' + [uri]::EscapeDataString($payload)
            $download = Invoke-WebRequest -Uri $downloadUrl -UseBasicParsing
            $urls = @(
                [regex]::Matches($download.Content, 'https://[^"''<>]+\.msu', 'IgnoreCase') |
                    ForEach-Object { [System.Net.WebUtility]::HtmlDecode($_.Value) } |
                    Select-Object -Unique
            )
            if ($urls.Count -gt 0) { return $urls }
        }
    }
    return @()
}
function Save-UrlFile {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$Destination
    )

    if (Test-Path -LiteralPath $Destination) {
        $existing = Get-Item -LiteralPath $Destination -Force
        if ($existing.Length -gt 0) { Write-Ok "Already downloaded $($existing.Name) ($([math]::Round($existing.Length/1MB,1)) MB)"; return }
    }

    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $bits = Get-Command Start-BitsTransfer -EA SilentlyContinue
    if ($bits) {
        Start-BitsTransfer -Source $Url -Destination $Destination -DisplayName (Split-Path -Leaf $Destination)
    } elseif (Get-Command curl.exe -EA SilentlyContinue) {
        & curl.exe -L --fail --retry 5 --retry-delay 5 --continue-at - --output $Destination $Url
        if ($LASTEXITCODE -ne 0) { Write-Fail "curl.exe failed with exit code $LASTEXITCODE while downloading $Url" }
    } else {
        (New-Object System.Net.WebClient).DownloadFile($Url, $Destination)
    }

    $item = Get-Item -LiteralPath $Destination -Force
    if ($item.Length -lt 1MB) { Write-Fail "Downloaded file is unexpectedly small: $Destination" }
    Write-Ok "Downloaded $($item.Name) ($([math]::Round($item.Length/1MB,1)) MB)"
}
function Save-LatestWindowsUpdatePackages {
    param(
        [Parameter(Mandatory=$true)]$CurrentInfo,
        [string]$DownloadDir
    )

    $latest = Get-LatestWindows11ReleaseInfo -DisplayVersion $CurrentInfo.DisplayVersion
    if (-not $latest) { return $null }
    Write-Ok "Microsoft latest for Windows 11 $($latest.DisplayVersion): build $($latest.LatestBuild)$(if($latest.KB){" KB$($latest.KB)"})"
    if ([version]$CurrentInfo.FullBuild -ge [version]$latest.LatestBuild) {
        Write-Ok "This PC is already on the latest listed build ($($CurrentInfo.FullBuild))."
        return $latest
    }

    Write-Warn "This PC is behind latest listed build: installed $($CurrentInfo.FullBuild), latest $($latest.LatestBuild)."
    if (-not $latest.KB) { Write-Warn "No KB was parsed, so automatic Catalog download is skipped."; return $latest }
    $urls = Get-MicrosoftCatalogDownloadUrls -KB $latest.KB -DisplayVersion $latest.DisplayVersion -LatestBuild $latest.LatestBuild
    if ($urls.Count -eq 0) { Write-Warn "No x64 MSU download URLs found in Microsoft Update Catalog for KB$($latest.KB)."; return $latest }
    foreach ($url in $urls) {
        $fileName = Split-Path ([uri]$url).AbsolutePath -Leaf
        Save-UrlFile -Url $url -Destination (Join-Path $DownloadDir $fileName)
    }
    return $latest
}
function Resolve-PostBootConsoleLauncher {
    $ps5 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $ps5) {
        Write-Ok "System PowerShell console launcher found: $ps5"
        return [pscustomobject]@{ Kind = 'PowerShell'; Path = $ps5 }
    }

    Write-Fail "System PowerShell was not found. Cannot register a visible post-boot console."
}
function Get-CurrentInteractiveUserId {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity -and -not [string]::IsNullOrWhiteSpace($identity.Name)) {
        return $identity.Name
    }

    if (-not [string]::IsNullOrWhiteSpace($env:USERDOMAIN) -and -not [string]::IsNullOrWhiteSpace($env:USERNAME)) {
        return "$env:USERDOMAIN\$env:USERNAME"
    }

    if (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) { return $env:USERNAME }
    Write-Fail "Could not resolve the current interactive user for post-boot registration."
}
function Register-PostBootScheduledTask {
    param(
        [Parameter(Mandatory=$true)][string]$TaskName,
        [Parameter(Mandatory=$true)][string]$RunnerPath,
        [Parameter(Mandatory=$true)][string]$UserId,
        [switch]$Retry
    )

    $cmdPath = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $schtasksPath = Join-Path $env:SystemRoot 'System32\schtasks.exe'
    $taskArguments = "/d /c `"$RunnerPath`""
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $schtasksPath /Delete /TN $TaskName /F >$null 2>$null
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    try {
        $action = New-ScheduledTaskAction -Execute $cmdPath -Argument $taskArguments
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $UserId
        if ($Retry) {
            $trigger.Delay = 'PT1M'
        }
        $principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    } catch {
        Write-Fail "Scheduled task registration failed for ${TaskName}: $($_.Exception.Message)"
    }
}
function Register-PostBootTerminalCommand {
    param(
        [Parameter(Mandatory=$true)][string]$CommandText
    )

    $consoleLauncher = Resolve-PostBootConsoleLauncher
    $currentUserId = Get-CurrentInteractiveUserId

    $postBootRoot = $script:RepairUpgradePostBootRoot
    if (-not (Test-Path -LiteralPath $postBootRoot)) {
        New-Item -ItemType Directory -Path $postBootRoot -Force | Out-Null
    }

    $staleMarkerPath = Join-Path $postBootRoot 'terminal-cleanup-started.marker'
    if (Test-Path -LiteralPath $staleMarkerPath) {
        Remove-Item -LiteralPath $staleMarkerPath -Force -ErrorAction SilentlyContinue
        Write-Warn "Removed stale terminal-cleanup-started.marker from previous run."
    }

    $taskName = 'WinSetupPostBootWindowsOldCleanup'
    $taskNameRetry = 'WinSetupPostBootWindowsOldCleanupRetry'
    $bootstrapPath = Join-Path $postBootRoot 'Start-Terminal-WindowsOld-Cleanup.ps1'
    $cleanupPath = Join-Path $postBootRoot 'Force-Delete-WindowsOld.ps1'
    $terminalCommandPath = Join-Path $postBootRoot 'Invoke-PostBoot-Terminal-Command.ps1'
    $runnerPath = Join-Path $postBootRoot 'Run-Terminal-WindowsOld-Cleanup.cmd'
    $commandShimDir = Join-Path $postBootRoot 'Commands'
    $startedMarker = Join-Path $postBootRoot 'terminal-cleanup-started.marker'
    $runValueName = 'WinSetupPostBootWindowsOldCleanup'
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $runOnceKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    $terminalLauncherLiteral = ([string]$consoleLauncher.Path).Replace("'", "''")
    $terminalLauncherKindLiteral = ([string]$consoleLauncher.Kind).Replace("'", "''")
    $commandLiteral = $CommandText.Replace("'", "''")
    $cleanupPathLiteral = $cleanupPath.Replace("'", "''")
    $terminalCommandPathLiteral = $terminalCommandPath.Replace("'", "''")
    $commandShimDirLiteral = $commandShimDir.Replace("'", "''")
    $startedMarkerLiteral = $startedMarker.Replace("'", "''")
    $sharedRemovalFunctions = @'
function Invoke-BoundedNativeCommand {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $true)][string[]] $ArgumentList,
        [Parameter(Mandatory = $true)][string] $Label,
        [int] $TimeoutSeconds = 120,
        [scriptblock] $PulseScript
    )
    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -WindowStyle Hidden
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $nextPulse = 5
    while (-not $process.HasExited) {
        Start-Sleep -Seconds 1
        if ($stopwatch.Elapsed.TotalSeconds -ge $nextPulse) {
            if ($PulseScript) { & $PulseScript ("{0} running for {1}s" -f $Label, [int]$stopwatch.Elapsed.TotalSeconds) }
            $nextPulse += 5
        }
        if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "{0} timed out after {1} seconds" -f $Label, $TimeoutSeconds
        }
    }
    $process.WaitForExit()
    return $process.ExitCode
}
function Invoke-ForceRemovePath {
    param(
        [Parameter(Mandatory = $true)][string] $TargetPath,
        [scriptblock] $PulseScript,
        [scriptblock] $LogScript
    )
    if (-not $TargetPath) { return }
    if (-not (Test-Path -LiteralPath $TargetPath)) {
        if ($LogScript) { & $LogScript ('SKIP target already absent ' + $TargetPath) }
        return
    }
    if ($LogScript) { & $LogScript ('FAST_RD begin ' + $TargetPath) }
    $fastRdExit = Invoke-BoundedNativeCommand -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/d', '/c', "rd /s /q `"$TargetPath`" >nul 2>nul") -Label ("fast rd {0}" -f $TargetPath) -TimeoutSeconds 60 -PulseScript $PulseScript
    if ($LogScript) { & $LogScript ('FAST_RD exit=' + $fastRdExit) }
    if (-not (Test-Path -LiteralPath $TargetPath)) {
        if ($LogScript) { & $LogScript ('DONE target absent ' + $TargetPath) }
        return
    }
    if ($LogScript) { & $LogScript ('TAKEOWN begin ' + $TargetPath) }
    $takeownExit = Invoke-BoundedNativeCommand -FilePath (Join-Path $env:SystemRoot 'System32\takeown.exe') -ArgumentList @('/f', $TargetPath, '/r', '/d', 'y') -Label ("takeown {0}" -f $TargetPath) -TimeoutSeconds 180 -PulseScript $PulseScript
    if ($LogScript) { & $LogScript ('TAKEOWN exit=' + $takeownExit) }
    if ($LogScript) { & $LogScript ('ICACLS begin ' + $TargetPath) }
    $icaclsExit = Invoke-BoundedNativeCommand -FilePath (Join-Path $env:SystemRoot 'System32\icacls.exe') -ArgumentList @($TargetPath, '/grant', 'administrators:F', 'SYSTEM:F', '/t', '/c', '/q') -Label ("icacls {0}" -f $TargetPath) -TimeoutSeconds 180 -PulseScript $PulseScript
    if ($LogScript) { & $LogScript ('ICACLS exit=' + $icaclsExit) }
    if ($LogScript) { & $LogScript ('ATTRIB/RD begin ' + $TargetPath) }
    $attribRdExit = Invoke-BoundedNativeCommand -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/d', '/c', "attrib -r -s -h `"$TargetPath\*`" /s /d >nul 2>nul & rd /s /q `"$TargetPath`" >nul 2>nul") -Label ("attrib/rd {0}" -f $TargetPath) -TimeoutSeconds 90 -PulseScript $PulseScript
    if ($LogScript) { & $LogScript ('ATTRIB/RD exit=' + $attribRdExit) }
    if (Test-Path -LiteralPath $TargetPath) {
        if ($LogScript) { & $LogScript ('REMOVE_ITEM begin ' + $TargetPath) }
        Remove-Item -LiteralPath $TargetPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $TargetPath) {
        throw "Target still exists after bounded cleanup: $TargetPath"
    }
    if ($LogScript) { & $LogScript ('DONE target absent ' + $TargetPath) }
}
'@
    $terminalCommandContent = @"
`$ErrorActionPreference = 'Stop'
`$commandText = '$commandLiteral'
$sharedRemovalFunctions
function c {
    Set-Location -LiteralPath 'C:\'
}
function rrm {
    param([Parameter(ValueFromRemainingArguments = `$true)] [object[]] `$RemainingArgs)
    if (`$RemainingArgs.Count -eq 1 -and [string]`$RemainingArgs[0] -ieq 'windows.old') { `$RemainingArgs = @('C:\Windows.old') }
    foreach (`$targetToRemove in `$RemainingArgs) {
        if (-not `$targetToRemove) { continue }
        Invoke-ForceRemovePath -TargetPath `$targetToRemove
    }
}
Invoke-Expression `$commandText
"@
    $cleanupContent = @"
# ALLOW_DESTRUCTIVE: requested post-upgrade force cleanup, scoped only to C:\Windows.old.
param([switch]`$SystemWorker)
`$ErrorActionPreference = 'Continue'
`$log = Join-Path (Split-Path -Parent `$PSCommandPath) 'windows-old-cleanup.log'
`$target = 'C:\Windows.old'
`$systemTaskName = '${taskName}System'
`$ps5 = Join-Path `$env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
function Write-CleanupLog([string]`$Message) {
    ('{0} {1}' -f (Get-Date -Format s), `$Message) | Add-Content -LiteralPath `$log -Encoding ASCII
}
function Test-IsSystemContext {
    try {
        return ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18')
    } catch {
        return `$false
    }
}
function Invoke-BoundedNativeCommandWithExitCode {
    param(
        [Parameter(Mandatory = `$true)][string] `$FilePath,
        [Parameter(Mandatory = `$true)][string[]] `$ArgumentList,
        [Parameter(Mandatory = `$true)][string] `$Label,
        [int] `$TimeoutSeconds = 120
    )
    `$process = Start-Process -FilePath `$FilePath -ArgumentList `$ArgumentList -PassThru -WindowStyle Hidden
    `$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    `$nextPulse = 5
    while (-not `$process.HasExited) {
        Start-Sleep -Seconds 1
        if (`$stopwatch.Elapsed.TotalSeconds -ge `$nextPulse) {
            Write-CleanupLog ('PULSE {0} running for {1}s' -f `$Label, [int]`$stopwatch.Elapsed.TotalSeconds)
            `$nextPulse += 5
        }
        if (`$stopwatch.Elapsed.TotalSeconds -ge `$TimeoutSeconds) {
            Stop-Process -Id `$process.Id -Force -ErrorAction SilentlyContinue
            Write-CleanupLog ('TIMEOUT {0} after {1}s' -f `$Label, `$TimeoutSeconds)
            return 124
        }
    }
    `$process.WaitForExit()
    Write-CleanupLog ('EXIT {0} code={1}' -f `$Label, `$process.ExitCode)
    return `$process.ExitCode
}
function Remove-SystemTask {
    schtasks.exe /Delete /TN `$systemTaskName /F >`$null 2>`$null
}
function Remove-PostBootTriggers {
    foreach (`$oneShotTaskName in @('$taskName', '$taskNameRetry', '$taskName' + 'System')) { schtasks.exe /Delete /TN `$oneShotTaskName /F >`$null 2>`$null }
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name '$runValueName' -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name '$runValueName' -Force -ErrorAction SilentlyContinue
}
function Invoke-DrainWindowsOldEntry {
    param([Parameter(Mandatory = `$true)][string] `$EntryPath)
    if (-not (Test-Path -LiteralPath `$EntryPath)) { return }
    if ((Get-Item -LiteralPath `$EntryPath -Force).PSIsContainer) {
        `$emptyDir = Join-Path ([System.IO.Path]::GetTempPath()) ('winold-empty-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path `$emptyDir -Force | Out-Null
        try {
            Write-CleanupLog ('PASS robocopy/mirror begin ' + `$EntryPath)
            `$rc = Invoke-BoundedNativeCommandWithExitCode -FilePath (Join-Path `$env:SystemRoot 'System32\robocopy.exe') -ArgumentList @(`$emptyDir, `$EntryPath, '/MIR', '/XJ', '/R:0', '/W:0', '/NFL', '/NDL', '/NJH', '/NJS', '/NP') -Label ('robocopy ' + `$EntryPath) -TimeoutSeconds 180
            Write-CleanupLog ('PASS robocopy/mirror exit ' + `$EntryPath + ' code=' + `$rc)
        } finally {
            Remove-Item -LiteralPath `$emptyDir -Force -Recurse -ErrorAction SilentlyContinue
        }
        Write-CleanupLog ('PASS rd begin ' + `$EntryPath)
        `$rdCommand = 'rd /s /q "' + `$EntryPath + '"'
        Invoke-BoundedNativeCommandWithExitCode -FilePath (Join-Path `$env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/d', '/c', `$rdCommand) -Label ('rd ' + `$EntryPath) -TimeoutSeconds 90 | Out-Null
        if (Test-Path -LiteralPath `$EntryPath) {
            Write-CleanupLog ('PASS attrib/rd begin ' + `$EntryPath)
            `$attribCommand = 'attrib -r -s -h "' + `$EntryPath + '\*" /s /d >nul 2>nul & rd /s /q "' + `$EntryPath + '" >nul 2>nul'
            Invoke-BoundedNativeCommandWithExitCode -FilePath (Join-Path `$env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/d', '/c', `$attribCommand) -Label ('attrib/rd ' + `$EntryPath) -TimeoutSeconds 120 | Out-Null
        }
    } else {
        Write-CleanupLog ('PASS remove file begin ' + `$EntryPath)
        Remove-Item -LiteralPath `$EntryPath -Force -ErrorAction SilentlyContinue
    }
}
function Start-SystemWorker {
    if (-not (Test-Path -LiteralPath `$ps5)) { `$ps5 = 'powershell.exe' }
    schtasks.exe /Delete /TN `$systemTaskName /F >`$null 2>`$null
    `$workerArgs = '-NoProfile -ExecutionPolicy Bypass -File "' + `$PSCommandPath + '" -SystemWorker'
    `$action = New-ScheduledTaskAction -Execute `$ps5 -Argument `$workerArgs
    `$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    `$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    `$trigger = New-ScheduledTaskTrigger -Once -At ([datetime]::Now.AddMinutes(1))
    Register-ScheduledTask -TaskName `$systemTaskName -Action `$action -Principal `$principal -Settings `$settings -Trigger `$trigger -Force | Out-Null
    Start-ScheduledTask -TaskName `$systemTaskName
    Write-CleanupLog ('SYSTEM_TASK_RUN ' + `$systemTaskName)
}
Write-CleanupLog ('START target=C:\Windows.old system=' + (Test-IsSystemContext) + ' systemWorker=' + `$SystemWorker.IsPresent)
if (-not (Test-Path -LiteralPath `$target)) {
    Write-CleanupLog 'SKIP target already absent'
    Remove-PostBootTriggers
    Remove-SystemTask
    exit 0
}
if (-not `$SystemWorker -and -not (Test-IsSystemContext)) {
    try {
        Start-SystemWorker
        Write-CleanupLog 'DELEGATED cleanup to SYSTEM worker'
        exit 0
    } catch {
        Write-CleanupLog ('SYSTEM_TASK_ERROR ' + `$_.Exception.Message)
    }
}
for (`$iteration = 0; `$iteration -lt 12; `$iteration++) {
    if (-not (Test-Path -LiteralPath `$target)) { break }
    `$entries = @(Get-ChildItem -LiteralPath `$target -Force -ErrorAction SilentlyContinue)
    Write-CleanupLog ('ITERATION ' + `$iteration + ' entries=' + `$entries.Count)
    foreach (`$entry in `$entries) {
        Invoke-DrainWindowsOldEntry -EntryPath `$entry.FullName
    }
    `$rootRdCommand = 'rd /s /q "' + `$target + '" >nul 2>nul'
    Invoke-BoundedNativeCommandWithExitCode -FilePath (Join-Path `$env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/d', '/c', `$rootRdCommand) -Label ('root rd ' + `$target) -TimeoutSeconds 30 | Out-Null
    if (Test-Path -LiteralPath `$target) {
        Start-Sleep -Seconds 2
    }
}
if (Test-Path -LiteralPath `$target) {
    Write-CleanupLog 'FAILED target still exists'
    exit 1
}
Remove-PostBootTriggers
Remove-SystemTask
Write-CleanupLog 'DONE target absent'
exit 0
"@
    $bootstrapContent = @"
# ALLOW_DESTRUCTIVE: removes only the one-shot WinSetupPostBootWindowsOldCleanup triggers created by repair-upgrade.ps1 after Terminal is launched.
`$ErrorActionPreference = 'Continue'
`$terminalLauncher = '$terminalLauncherLiteral'
`$terminalLauncherKind = '$terminalLauncherKindLiteral'
`$commandText = '$commandLiteral'
`$cleanupPath = '$cleanupPathLiteral'
`$terminalCommandPath = '$terminalCommandPathLiteral'
`$commandShimDir = '$commandShimDirLiteral'
`$startedMarker = '$startedMarkerLiteral'
`$taskNames = @('$taskName', '$taskNameRetry')
`$runValueName = '$runValueName'
`$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
`$runOnceKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
`$ps5 = Join-Path `$env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath `$ps5)) { `$ps5 = 'powershell.exe' }
$sharedRemovalFunctions
function Remove-PostBootTriggers {
    foreach (`$oneShotTaskName in `$taskNames) { schtasks.exe /Delete /TN `$oneShotTaskName /F >`$null 2>`$null }
    Remove-ItemProperty -Path `$runKey -Name `$runValueName -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path `$runOnceKey -Name `$runValueName -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path `$commandShimDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path `$commandShimDir 'c.ps1') -Encoding ASCII -Force -Value 'Set-Location -LiteralPath C:\'
Set-Content -LiteralPath (Join-Path `$commandShimDir 'rrm.ps1') -Encoding ASCII -Force -Value @'
$sharedRemovalFunctions
param([Parameter(ValueFromRemainingArguments = `$true)] [object[]] `$RemainingArgs)
if (`$RemainingArgs.Count -eq 1 -and [string]`$RemainingArgs[0] -ieq 'windows.old') { `$RemainingArgs = @('C:\Windows.old') }
foreach (`$targetToRemove in `$RemainingArgs) {
    if (-not `$targetToRemove) { continue }
    Invoke-ForceRemovePath -TargetPath `$targetToRemove
}
'@
Set-Content -LiteralPath `$terminalCommandPath -Encoding ASCII -Force -Value @'
$terminalCommandContent
'@
if (-not (Test-Path -LiteralPath `$cleanupPath)) {
    throw "Generated cleanup script missing: `$cleanupPath"
}
`$env:Path = "`$commandShimDir;`$env:Path"
Start-Sleep -Seconds 3
try {
    Start-Process -FilePath `$ps5 -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', `$cleanupPath) -WindowStyle Hidden
    if (-not (Test-Path -LiteralPath `$startedMarker)) {
        `$visibleTerminalProcess = Start-Process -FilePath `$ps5 -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', `$terminalCommandPath) -WindowStyle Normal -PassThru
        if (`$visibleTerminalProcess -and -not `$visibleTerminalProcess.HasExited) {
            `$null = New-Item -ItemType File -Path `$startedMarker -Force
        }
    }
    Remove-PostBootTriggers
} catch {
    throw
}
"@
    $runnerContent = @"
@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$bootstrapPath"
exit /b %ERRORLEVEL%
"@

    Set-Content -LiteralPath $bootstrapPath -Value $bootstrapContent -Encoding ASCII -Force
    Set-Content -LiteralPath $cleanupPath -Value $cleanupContent -Encoding ASCII -Force
    Set-Content -LiteralPath $terminalCommandPath -Value $terminalCommandContent -Encoding ASCII -Force
    Set-Content -LiteralPath $runnerPath -Value $runnerContent -Encoding ASCII -Force
    $bootstrapItem = Get-Item -LiteralPath $bootstrapPath -Force
    $terminalCommandItem = Get-Item -LiteralPath $terminalCommandPath -Force
    $runnerItem = Get-Item -LiteralPath $runnerPath -Force
    if ($bootstrapItem.Length -lt 300) { Write-Fail "Post-boot Terminal bootstrap was not written correctly: $bootstrapPath" }
    if ($runnerItem.Length -lt 50) { Write-Fail "Post-boot Terminal runner was not written correctly: $runnerPath" }

    if (-not (Test-Path -LiteralPath $runKey)) {
        New-Item -Path $runKey -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $runOnceKey)) {
        New-Item -Path $runOnceKey -Force | Out-Null
    }
    New-ItemProperty -Path $runKey -Name $runValueName -Value "`"$runnerPath`"" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $runOnceKey -Name $runValueName -Value "`"$runnerPath`"" -PropertyType String -Force | Out-Null

    Register-PostBootScheduledTask -TaskName $taskName -RunnerPath $runnerPath -UserId $currentUserId
    Register-PostBootScheduledTask -TaskName $taskNameRetry -RunnerPath $runnerPath -UserId $currentUserId -Retry

    $registeredTask = schtasks.exe /Query /TN $taskName /FO LIST 2>$null
    $registeredRetryTask = schtasks.exe /Query /TN $taskNameRetry /FO LIST 2>$null
    $registeredRun = Get-ItemProperty -Path $runKey -Name $runValueName -ErrorAction SilentlyContinue
    $registeredRunOnce = Get-ItemProperty -Path $runOnceKey -Name $runValueName -ErrorAction SilentlyContinue
    if (-not $registeredTask) { Write-Fail "Post-boot scheduled task registration failed: $taskName" }
    if (-not $registeredRetryTask) { Write-Fail "Post-boot retry scheduled task registration failed: $taskNameRetry" }
    if (-not $registeredRun) { Write-Fail "Post-boot Run-key fallback registration failed: $runValueName" }
    if (-not $registeredRunOnce) { Write-Fail "Post-boot RunOnce fallback registration failed: $runValueName" }

    $writtenBootstrap = Get-Content -LiteralPath $bootstrapPath -Raw
    $writtenCleanup = Get-Content -LiteralPath $cleanupPath -Raw
    $writtenTerminalCommand = Get-Content -LiteralPath $terminalCommandPath -Raw
    $writtenRunner = Get-Content -LiteralPath $runnerPath -Raw
    if ($writtenBootstrap -notmatch [regex]::Escape("'-File', `$terminalCommandPath")) {
        Write-Fail "Post-boot bootstrap does not launch the generated visible Terminal command script."
    }
    if ($writtenTerminalCommand -notmatch [regex]::Escape("`$commandText = '$commandLiteral'")) {
        Write-Fail "Post-boot visible Terminal command script does not contain the exact required command text."
    }
    if ($writtenTerminalCommand -notmatch [regex]::Escape('function c {')) {
        Write-Fail "Post-boot visible Terminal command script does not define the c command."
    }
    if ($writtenTerminalCommand -notmatch [regex]::Escape('function rrm {')) {
        Write-Fail "Post-boot visible Terminal command script does not define the rrm command."
    }
    if ($writtenTerminalCommand -notmatch [regex]::Escape('Invoke-ForceRemovePath -TargetPath')) {
        Write-Fail "Post-boot visible Terminal command script does not use bounded removal."
    }
    if ($writtenRunner -notmatch [regex]::Escape($bootstrapPath)) {
        Write-Fail "Post-boot CMD runner does not call the generated PowerShell bootstrap."
    }
    if ($writtenBootstrap -notmatch [regex]::Escape("Set-Content -LiteralPath (Join-Path `$commandShimDir 'c.ps1')")) {
        Write-Fail "Post-boot bootstrap does not install the c command shim."
    }
    if ($writtenBootstrap -notmatch [regex]::Escape("Set-Content -LiteralPath (Join-Path `$commandShimDir 'rrm.ps1')")) {
        Write-Fail "Post-boot bootstrap does not install the rrm command shim."
    }
    if ($writtenCleanup -notmatch [regex]::Escape("`$target = 'C:\Windows.old'")) {
        Write-Fail "Generated cleanup script does not target C:\Windows.old."
    }
    if ($writtenCleanup -notmatch [regex]::Escape('function Start-SystemWorker {')) {
        Write-Fail "Generated cleanup script does not include the SYSTEM worker path."
    }
    if ($writtenCleanup -notmatch [regex]::Escape('robocopy.exe')) {
        Write-Fail "Generated cleanup script does not include the bounded robocopy drain path."
    }
    if ($writtenBootstrap -notmatch [regex]::Escape('Generated cleanup script missing:')) {
        Write-Fail "Post-boot bootstrap does not validate that the generated cleanup script exists."
    }
    if ($writtenBootstrap -match [regex]::Escape("Set-Content -LiteralPath `$cleanupPath")) {
        Write-Fail "Post-boot bootstrap still rewrites the generated cleanup script."
    }
    if ($writtenBootstrap -notmatch [regex]::Escape('function Remove-PostBootTriggers {')) {
        Write-Fail "Post-boot bootstrap does not include trigger self-cleanup."
    }
    if ($writtenBootstrap -notmatch [regex]::Escape("Start-Process -FilePath `$ps5 -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', `$cleanupPath)")) {
        Write-Fail "Post-boot bootstrap does not start the direct cleanup script."
    }

    Write-Ok "Post-boot command registered by logon task, retry task, Run, and RunOnce."
    Write-Ok "Bootstrap: $bootstrapPath"
    Write-Ok "Visible Terminal command: $terminalCommandPath"
    Write-Ok "Runner: $runnerPath"
}
function New-SetupUpgradeArguments {
    param([switch]$DisableDynamicUpdate)

    $dynamicUpdateValue = if ($DisableDynamicUpdate) { 'Disable' } else { 'Enable' }
    return @(
        '/Auto', 'Upgrade',
        '/EULA', 'Accept',
        '/DynamicUpdate', $dynamicUpdateValue,
        '/MigrateDrivers', 'All',
        '/ShowOOBE', 'None',
        '/Telemetry', 'Disable',
        '/Compat', 'IgnoreWarning',
        '/BitLocker', 'AlwaysSuspend'
    )
}
if ($VerifyAutomationOnly) {
    Write-Step "VERIFY" "Automation-only verification"
    $verifyTerminalLauncher = Resolve-PostBootConsoleLauncher
    $verifyArgs = New-SetupUpgradeArguments -DisableDynamicUpdate:$DisableDynamicUpdate
    Write-Ok "Post-boot console launcher: $($verifyTerminalLauncher.Kind) $($verifyTerminalLauncher.Path)"
    Write-Ok "Post-boot Terminal command text: $PostBootCommand"
    Write-Ok "Post-boot visible console runtime: powershell.exe -NoExit -File <generated postboot wrapper under $script:RepairUpgradePostBootRoot>"
    Write-Ok "Windows Setup UI: real setup.exe window is shown; no custom progress GUI is used."
    Write-Ok "Setup arguments: $($verifyArgs -join ' ')"
    Complete-RepairUpgradeProgress
    return
}
if ($MonitorExistingSetupProcessId -gt 0) {
    Write-Step "MONITOR" "Monitoring existing Windows setup process $MonitorExistingSetupProcessId"
    $existingSetupProcess = Get-Process -Id $MonitorExistingSetupProcessId -ErrorAction Stop
    Wait-RepairUpgradeSetup -Process $existingSetupProcess
    Write-Ok "Existing Windows setup process $MonitorExistingSetupProcessId exited with code $($existingSetupProcess.ExitCode)"
    Complete-RepairUpgradeProgress
    return
}
$activeRepairUpgradeProcess = Get-ActiveRepairUpgradeSetupProcess -ExpectedExtractDir $ExtractDir
if ($activeRepairUpgradeProcess) {
    Write-Warn ("Detected existing Windows setup process {0} (PID {1}); attaching instead of starting a second upgrade." -f $activeRepairUpgradeProcess.Name, $activeRepairUpgradeProcess.ProcessId)
    $attachedProcess = Get-Process -Id $activeRepairUpgradeProcess.ProcessId -ErrorAction Stop
    Write-Step "MONITOR" "Monitoring existing Windows setup process $($attachedProcess.Id)"
    Wait-RepairUpgradeSetup -Process $attachedProcess
    Write-Ok "Existing Windows setup process $($attachedProcess.Id) exited with code $($attachedProcess.ExitCode)"
    Complete-RepairUpgradeProgress
    return
}

Normalize-RepairUpgradeLooseArguments
if ($script:RepairUpgradeNormalizedForceClearAlias) {
    Write-Warn "Normalized loose force-clear switch '$script:RepairUpgradeNormalizedForceClearAlias' to -ForceClearRebootPending."
}

# --- STEP 0: Current build and latest-update check -------------------
Write-Step 0 "Check current Windows build and latest available update"
$CurrentWindows = Get-CurrentWindowsBuildInfo
Write-Ok "Installed: $($CurrentWindows.ProductName) $($CurrentWindows.DisplayVersion) $($CurrentWindows.EditionID) build $($CurrentWindows.FullBuild) ($($CurrentWindows.Architecture))"
if (-not $SkipLatestUpdateDownload) {
    $LatestWindows = Save-LatestWindowsUpdatePackages -CurrentInfo $CurrentWindows -DownloadDir $LatestUpdateDownloadDir
} else {
    Write-Warn "Skipping latest-update download because -SkipLatestUpdateDownload was supplied."
}

# --- STEP 0B: Post-boot automation hook ------------------------------
Write-Step "0B" "Register post-boot Terminal cleanup command"
Register-PostBootTerminalCommand -CommandText $PostBootCommand
if ($RegisterPostBootOnly) {
    Write-Warn "Registration-only mode requested; setup.exe will not be launched."
    Complete-RepairUpgradeProgress
    return
}

# --- STEP 0A: Early reboot-pending gate ------------------------------
Write-Step "0A" "Preflight reboot-pending gate"
if (-not (Invoke-RebootPendingGate -CheckRegistryFlags)) { return }

# ─── STEP 1: Resolve ISO source ──────────────────────────────────────
Write-Step 1 "Resolve ISO source"
$ActiveIso = $null
if ($IsoSource -and (Test-Path -LiteralPath $IsoSource)) {
    $ActiveIso = (Get-Item -LiteralPath $IsoSource -Force).FullName
    Write-Ok "Using requested source ISO $ActiveIso ($([math]::Round((Get-Item -LiteralPath $ActiveIso).Length/1GB,2)) GB)"
} elseif (Test-Path -LiteralPath $LocalIso) {
    $ActiveIso = (Get-Item -LiteralPath $LocalIso -Force).FullName
    Write-Ok "Using cached ISO fallback $ActiveIso ($([math]::Round((Get-Item -LiteralPath $ActiveIso).Length/1GB,2)) GB)"
} else {
    $alt = @("F:\isos\Windows.iso","E:\isos\Windows.iso")
    $found = $alt | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($found) {
        $ActiveIso = (Get-Item -LiteralPath $found -Force).FullName
        Write-Ok "Using alternate source ISO $ActiveIso ($([math]::Round((Get-Item -LiteralPath $ActiveIso).Length/1GB,2)) GB)"
    } else {
        Write-Fail "No Windows ISO found at $IsoSource or alternates"
    }
}

# ─── STEP 2: Mount ISO ───────────────────────────────────────────────
Write-Step 2 "Mount ISO"
Write-TraceLine "STEP[2] enable automount begin"
Enable-VolumeAutomount
Write-TraceLine "STEP[2] enable automount done"
Write-TraceLine "STEP[2] existing setup volume query begin"
$existingSetupDriveLetters = @(
    Get-CdRomDriveLetters |
        Where-Object { Test-WindowsSetupVolume $_ } |
        Select-Object -Unique
)
Write-TraceLine "STEP[2] existing setup volume query done count=$($existingSetupDriveLetters.Count)"
$dl = $null
if ($existingSetupDriveLetters.Count -eq 1) {
    $dl = $existingSetupDriveLetters[0]
    Write-Warn "Reusing existing mounted Windows setup ISO at ${dl}:"
} elseif ($existingSetupDriveLetters.Count -gt 1) {
    Write-Fail "Multiple Windows setup ISO volumes are already mounted; cannot safely choose one: $($existingSetupDriveLetters -join ', ')"
}
# Dismount any stale mount first
if (Get-Command -Name Dismount-DiskImage -ErrorAction SilentlyContinue) {
    Write-TraceLine "STEP[2] stale dismount begin"
    try { Dismount-DiskImage -ImagePath $ActiveIso -ErrorAction SilentlyContinue } catch {}
    Write-TraceLine "STEP[2] stale dismount done"
}
if (-not $dl) {
    $beforeIsoDriveLetters = @(Get-CdRomDriveLetters)
    Write-TraceLine "STEP[2] mount begin"
    try {
        $mountMethod = Mount-WindowsIso -IsoPath $ActiveIso
    } catch {
        Write-Warn "ISO mount attempt reported '$($_.Exception.Message)'; checking whether the ISO attached anyway."
    }
    Write-TraceLine "STEP[2] mount done method=$mountMethod"
    try {
        Write-TraceLine "STEP[2] resolve drive letter begin"
        $dl = Resolve-WindowsIsoDriveLetter -IsoPath $ActiveIso -BeforeDriveLetters $beforeIsoDriveLetters
        Write-TraceLine "STEP[2] resolve drive letter done value=$dl"
    } catch {
        Write-Warn "$($_.Exception.Message); falling back to direct ISO extraction."
    }
}
$MountedIsoRoot = $null
if ($dl) {
    $MountedIsoRoot = "${dl}:\"
    if ($mountMethod) {
        Write-Ok "Mounted at ${dl}: via $mountMethod"
    } else {
        Write-Ok "Mounted at ${dl}:"
    }
}

# ─── STEP 3: Extract ISO to project-owned storage ────────────────────
Write-Step 3 "Extract ISO to $ExtractDir (local NTFS)"
if (Test-RepairUpgradeExtractComplete -Path $ExtractDir) {
    Write-Ok "Existing extracted WinSetup cache is already complete; reusing $ExtractDir"
} else {
if (Test-Path $ExtractDir) {
    # ALLOW_DESTRUCTIVE: removes only the script-owned extracted WinSetup cache under $ExtractDir before rebuilding it from the selected ISO.
    Write-Host "    Removing stale $ExtractDir ..."
    Write-TraceLine "STEP[3] stale extract cleanup begin"
    & cmd.exe /d /c "attrib -r `"$ExtractDir\*`" /s /d >nul 2>nul & rd /s /q `"$ExtractDir`" >nul 2>nul" | Out-Null
    if (Test-Path $ExtractDir) {
        # ALLOW_DESTRUCTIVE: secondary removal attempt for the same script-owned extracted WinSetup cache under $ExtractDir.
        Remove-Item $ExtractDir -Recurse -Force -EA SilentlyContinue
    }
    if (Test-Path $ExtractDir) {
        Write-Fail "Could not clear stale extracted WinSetup cache at $ExtractDir"
    }
    Write-TraceLine "STEP[3] stale extract cleanup done"
}
New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null
if ($MountedIsoRoot) {
    $copyCompleted = $false
    foreach ($attempt in 1..2) {
        Write-Host "    Robocopy $MountedIsoRoot -> $ExtractDir (MT:8) [attempt $attempt/2] ..."
        Invoke-RobocopyTree -SourcePath $MountedIsoRoot -DestinationPath $ExtractDir
        if (Test-Path -LiteralPath (Join-Path $ExtractDir 'setup.exe')) {
            $copyCompleted = $true
            break
        }
        if ($attempt -lt 2) {
            Write-Warn "Mounted ISO copy completed without setup.exe appearing yet; retrying once after a short wait."
            Start-Sleep -Seconds 3
        }
    }
    if (-not $copyCompleted) {
        Write-Fail "Mounted ISO copy did not produce setup.exe under $ExtractDir after retry."
    }
} else {
    $sevenZip = Find-SevenZipExecutable
    if (-not $sevenZip) { Write-Fail "Native ISO mount did not expose a drive letter and no non-C: 7-Zip fallback was found for direct extraction." }
    Write-Warn "Native ISO mount did not expose a setup drive; extracting directly with $sevenZip ..."
    & $sevenZip x $ActiveIso "-o$ExtractDir" -y -bsp1 -bso0
    if ($LASTEXITCODE -ne 0) { Write-Fail "7-Zip ISO extraction failed with exit code $LASTEXITCODE" }
}
}
# Verify critical files
$critical = @(Get-RepairUpgradeCriticalRelativePaths)
$missing = @()
foreach ($f in $critical) {
    $p = Join-Path $ExtractDir $f
    if (-not (Test-Path $p)) { $missing += $f }
}
$imageFiles = @((Get-RepairUpgradeImageRelativePaths) | Where-Object { Test-Path (Join-Path $ExtractDir $_) })
if ($imageFiles.Count -eq 0) { $missing += 'sources\install.esd or sources\install.wim' }
if ($missing.Count -gt 0) { Write-Fail "Missing after extract: $($missing -join ', ')" }
if ($MountedIsoRoot) {
    Repair-InvalidExtractedPortableExecutables $MountedIsoRoot $ExtractDir
} else {
    Write-Ok "Portable executable recopy repair skipped; direct 7-Zip extraction was used."
}
$fileCount = (Get-ChildItem $ExtractDir -Recurse -File -EA SilentlyContinue | Measure-Object).Count
Write-Ok "Extracted $fileCount files. All critical DLLs present. Image: $($imageFiles[0])"

# Dismount ISO (no longer needed)
$dismountMethod = Dismount-WindowsIso -IsoPath $ActiveIso -DriveLetter $dl
if ($dismountMethod) {
    Write-Ok "ISO dismounted via $dismountMethod"
}
if ($VerifyIsoPreparationOnly) {
    Write-Ok "ISO preparation verification completed. setup.exe and required migration files are staged under $ExtractDir"
    Complete-RepairUpgradeProgress
    return
}

# ─── STEP 4: Clean stale upgrade folders ─────────────────────────────
Write-Step 4 "Clean stale upgrade folders"
foreach ($dir in @("C:\`$WINDOWS.~BT", "C:\`$Windows.~WS")) {
    # ALLOW_DESTRUCTIVE: removes only stale Windows setup leftovers C:\$WINDOWS.~BT and C:\$Windows.~WS before launching setup.
    Remove-RepairUpgradeFolderSafely -Path $dir
}
if ($VerifyCleanupOnly) {
    Write-Ok "Cleanup-only verification completed."
    Complete-RepairUpgradeProgress
    return
}

# ─── STEP 5: Check PendingFileRenameOperations ───────────────────────
Write-Step 5 "Check PendingFileRenameOperations"
if (-not (Invoke-RebootPendingGate)) { return }

# ─── STEP 6: Remove blocking legacy drivers ──────────────────────────
Write-Step 6 "Remove blocking legacy printer drivers"
$driverDump = pnputil /enum-drivers 2>&1 | Out-String
# Find all legacy printer drivers with unsigned binaries
$oems = [regex]::Matches($driverDump, 'Published Name:\s+(oem\d+\.inf)\s+.*?Class Name:\s+Printer.*?Attributes:\s+Legacy', 'Singleline')
if ($oems.Count -gt 0) {
    foreach ($m in $oems) {
        $oem = $m.Groups[1].Value
        pnputil /delete-driver $oem /force 2>$null | Out-Null
        Write-Ok "Removed $oem (legacy printer)"
    }
} else {
    Write-Ok "No blocking legacy drivers found"
}

# ─── STEP 7: Stop IIS to prevent migration errors ───────────────────
Write-Step 7 "Stop IIS services"
foreach ($svc in @('W3SVC','WAS','IISADMIN')) {
    $s = Get-Service $svc -EA SilentlyContinue
    if ($s -and $s.Status -eq 'Running') {
        Stop-Service $svc -Force -EA SilentlyContinue
        Write-Ok "Stopped $svc"
    }
}

# ─── STEP 8: Start required services ─────────────────────────────────
Write-Step 8 "Start required services"
$required = @(
    @{Name='wuauserv';      Startup='Manual'},
    @{Name='BITS';          Startup='Manual'},
    @{Name='cryptsvc';      Startup='Automatic'},
    @{Name='TrustedInstaller'; Startup='Manual'},
    @{Name='DiagTrack';     Startup='Manual'},
    @{Name='msiserver';     Startup='Manual'}
)
foreach ($r in $required) {
    $s = Get-Service $r.Name -EA SilentlyContinue
    if ($s) {
        Set-Service $r.Name -StartupType $r.Startup -EA SilentlyContinue
        if ($s.Status -ne 'Running') { Start-Service $r.Name -EA SilentlyContinue }
        $s = Get-Service $r.Name
        if ($s.Status -eq 'Running') { Write-Ok "$($r.Name): Running" }
        else { Write-Host "    [WARN] $($r.Name): $($s.Status)" -ForegroundColor Yellow }
    }
}

# ─── STEP 9: Check reboot-pending flags ─────────────────────────────
Write-Step 9 "Check reboot-pending flags"
if (-not (Invoke-RebootPendingGate -CheckRegistryFlags -PendingFileRenameMessage 'PendingFileRenameOperations exists after service startup ({0} entries).')) { return }
Write-Ok "No reboot-pending flags"

# ─── STEP 10: Disk space check ───────────────────────────────────────
Write-Step 10 "Verify disk space"
$freeGB = [math]::Round((Get-PSDrive C).Free/1GB, 1)
if ($freeGB -lt 20) { Write-Fail "Only $freeGB GB free on C: (need 20+)" }
Write-Ok "$freeGB GB free on C:"

# ─── STEP 11: Pre-flight summary ─────────────────────────────────────
Write-Step 11 "Pre-flight verification"
$checks = @(
    @{Name='setup.exe exists';       OK=(Test-Path "$ExtractDir\setup.exe")},
    @{Name='migcore.dll present';    OK=(Test-Path "$ExtractDir\sources\migcore.dll")},
    @{Name='install image present';  OK=((Test-Path "$ExtractDir\sources\install.esd") -or (Test-Path "$ExtractDir\sources\install.wim"))},
    @{Name='wuauserv Running';       OK=((Get-Service wuauserv).Status -eq 'Running')},
    @{Name='IIS stopped';            OK=((Get-Service W3SVC -EA SilentlyContinue).Status -ne 'Running')},
    @{Name='Disk space OK';          OK=($freeGB -ge 20)}
)
$allPass = $true
foreach ($c in $checks) {
    if ($c.OK) { Write-Ok $c.Name }
    else { Write-Host "    [FAIL] $($c.Name)" -ForegroundColor Red; $allPass = $false }
}
$btPath = "C:\`$WINDOWS.~BT"
if (Test-Path -LiteralPath $btPath) {
    Write-Warn "$btPath is present; continuing because Windows Setup can reuse the workspace."
} else {
    Write-Ok "No stale BT folder"
}
if (-not $allPass) { Write-Fail "Pre-flight checks failed. Aborting." }

# ─── STEP 12: Launch repair upgrade ─────────────────────────────────
Write-Step 12 "Launching repair upgrade from $ExtractDir\setup.exe"
$attemptDisableDynamicUpdate = [bool]$DisableDynamicUpdate
$attemptNumber = 1
while ($true) {
    Write-Host ""
    Write-Host ("    === REPAIR UPGRADE STARTING (attempt {0}) ===" -f $attemptNumber) -ForegroundColor Green
    $dynamicUpdateValue = if ($attemptDisableDynamicUpdate) { 'Disable' } else { 'Enable' }
    Write-Host "    /Auto Upgrade /EULA Accept /DynamicUpdate $dynamicUpdateValue /MigrateDrivers All" -ForegroundColor White
    Write-Host "    /ShowOOBE None /Telemetry Disable" -ForegroundColor White
    Write-Host "    /Compat IgnoreWarning" -ForegroundColor White
    Write-Host ""

    $setupArgs = New-SetupUpgradeArguments -DisableDynamicUpdate:$attemptDisableDynamicUpdate
    $setupPath = Join-Path $ExtractDir 'setup.exe'
    $launchStartedAt = Get-Date
    $proc = Start-Process -FilePath $setupPath -ArgumentList $setupArgs -WorkingDirectory $ExtractDir -PassThru
    New-Item -ItemType Directory -Path $script:RepairUpgradePostBootRoot -Force | Out-Null
    $launchProof = [pscustomobject]@{
        StartedAt = $launchStartedAt.ToString('o')
        LaunchDeadline = $script:RepairUpgradeLaunchDeadline.ToString('o')
        ExpectedWindowsReturnWithinMinutes = 60
        SetupPath = $setupPath
        ProcessId = $proc.Id
        Arguments = ($setupArgs -join ' ')
        PostBootRoot = $script:RepairUpgradePostBootRoot
        PostBootCommand = $PostBootCommand
        Status = 'setup.exe-started'
    }
    $launchProof | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:RepairUpgradeLaunchProofPath -Encoding ASCII
    Write-Ok "setup.exe started as PID $($proc.Id); launch proof: $script:RepairUpgradeLaunchProofPath"
    Start-Sleep -Seconds 5
    $setupStillActive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    $relatedSetup = Get-ActiveRepairUpgradeSetupProcess -ExpectedExtractDir $ExtractDir
    if (-not $setupStillActive -and -not $relatedSetup) {
        Write-Fail "setup.exe did not remain active and no related Windows Setup process was detected after launch; refusing to claim the upgrade started."
    }
    Wait-RepairUpgradeSetup -Process $proc
    $setupExitHex = Convert-RepairUpgradeExitCodeToHex -ExitCode $proc.ExitCode
    $blueBoxSnapshot = Get-RepairUpgradeBlueBoxSnapshot
    $effectiveFailureHex = if ($blueBoxSnapshot.MainHrHex) { $blueBoxSnapshot.MainHrHex } elseif ($proc.ExitCode -ne 0) { $setupExitHex } else { $null }
    $effectiveSuccess = [string]::IsNullOrWhiteSpace($effectiveFailureHex) -or ($effectiveFailureHex -eq '0x00000000')

    Write-Host "`n    Setup exited with code: $($proc.ExitCode) [$setupExitHex]" -ForegroundColor $(if($effectiveSuccess){'Green'}else{'Red'})

    if ($effectiveSuccess) {
        Complete-RepairUpgradeProgress
        break
    }

    if ((-not $attemptDisableDynamicUpdate) -and $blueBoxSnapshot.DynamicUpdateDetected -and ($effectiveFailureHex -eq '0x8007007E')) {
        Write-Warn "Windows Setup failed after Dynamic Update with $effectiveFailureHex; retrying once with Dynamic Update disabled."
        Write-TraceLine ("SETUP retry disable-du because MainHr={0} ProcessExit={1} Diagnostic={2}" -f $blueBoxSnapshot.MainHrHex, $blueBoxSnapshot.ProcessExitHex, $blueBoxSnapshot.DiagnosticFailureHex)
        $attemptDisableDynamicUpdate = $true
        $attemptNumber++
        continue
    }

    $failureDetail = if ($blueBoxSnapshot.TailLine) { $blueBoxSnapshot.TailLine } else { "Windows setup exited with code $($proc.ExitCode) [$setupExitHex]" }
    Update-RepairUpgradeProgress -Status $failureDetail
    throw ("Windows setup failed: {0} (MainHr={1}; ProcessExit={2}; Diagnostic={3})" -f $failureDetail, $blueBoxSnapshot.MainHrHex, $blueBoxSnapshot.ProcessExitHex, $blueBoxSnapshot.DiagnosticFailureHex)
}
