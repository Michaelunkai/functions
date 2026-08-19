[CmdletBinding()]
param(
    [switch]$SkipSfc,
    [int]$StallMinutes = 15,
    [switch]$DeepVerify
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-ServiceRunning {
    param([string]$Name)

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $service) {
        return
    }

    if ($service.Status -ne 'Running') {
        Write-Step "Starting service $Name"
        Start-Service -Name $Name -ErrorAction Stop
    }
}

function Get-ServicingProcessRecords {
    $targets = @('dism.exe', 'DismHost.exe', 'sfc.exe', 'TiWorker.exe', 'TrustedInstaller.exe')
    $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -in $targets })
    $byId = @{}

    foreach ($process in $processes) {
        $byId[[int]$process.ProcessId] = $process
    }

    foreach ($process in $processes) {
        $parent = $null
        if ($process.ParentProcessId) {
            $parent = $byId[[int]$process.ParentProcessId]
            if (-not $parent) {
                $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $($process.ParentProcessId)" -ErrorAction SilentlyContinue
            }
        }

        $parentName = if ($parent) { $parent.Name } else { '' }
        $parentCommandLine = if ($parent) { [string]$parent.CommandLine } else { '' }
        $commandLine = [string]$process.CommandLine
        $isInteractiveParent = $parentName -in @('powershell.exe', 'pwsh.exe', 'cmd.exe', 'wt.exe', 'WindowsTerminal.exe', 'conhost.exe')
        $isOneShotServicingParent = $isInteractiveParent -and $parentCommandLine -match 'cleanup-image|restorehealth|checkhealth|scanhealth|scannow|versionedindex-fixer|unstuck-command|rerundism'
        $isUserServicingCommand = $commandLine -match 'cleanup-image|restorehealth|checkhealth|scanhealth|scannow'
        $safeToStop = $process.Name -in @('dism.exe', 'sfc.exe') -and ($isOneShotServicingParent -or $isUserServicingCommand)

        [pscustomobject]@{
            Name            = $process.Name
            ProcessId       = [int]$process.ProcessId
            ParentProcessId = [int]$process.ParentProcessId
            ParentName      = $parentName
            ParentCommandLine = $parentCommandLine
            CommandLine     = $commandLine
            SafeToStop      = $safeToStop
            SafeToStopParent = $isOneShotServicingParent
        }
    }
}

function Format-ServicingProcessRecords {
    param([object[]]$Records)

    if (-not $Records) {
        return 'none'
    }

    return (($Records | ForEach-Object {
        if ($_.ParentName) {
            '{0}({1})<-{2}({3})' -f $_.Name, $_.ProcessId, $_.ParentName, $_.ParentProcessId
        }
        else {
            '{0}({1})' -f $_.Name, $_.ProcessId
        }
    }) -join ', ')
}

function Stop-ServicingProcessSet {
    param([object[]]$Records)

    $targetIds = @($Records | Select-Object -ExpandProperty ProcessId -Unique)
    $children = @(Get-ServicingProcessRecords | Where-Object {
        $_.Name -eq 'DismHost.exe' -and $_.ParentProcessId -in $targetIds
    })
    $parentIds = @($Records | Where-Object { $_.SafeToStopParent } | Select-Object -ExpandProperty ParentProcessId -Unique)
    $stopIds = @($children | Select-Object -ExpandProperty ProcessId -Unique) + $targetIds
    $stopIds = @($stopIds | Where-Object { $_ -and $_ -ne $PID } | Select-Object -Unique)

    foreach ($id in $stopIds) {
        $proc = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Step "Stopping servicing process $($proc.ProcessName) ($id)"
            Stop-Process -Id $id -Force -ErrorAction Stop
        }
    }

    foreach ($parentId in $parentIds) {
        if (-not $parentId -or $parentId -eq $PID) {
            continue
        }

        $parentProc = Get-Process -Id $parentId -ErrorAction SilentlyContinue
        if ($parentProc) {
            Write-Step "Stopping stale servicing parent $($parentProc.ProcessName) ($parentId)"
            Stop-Process -Id $parentId -Force -ErrorAction Stop
        }
    }

    Start-Sleep -Seconds 2

    $remaining = @(Get-ServicingProcessRecords | Where-Object { $_.ProcessId -in $stopIds })
    if ($remaining) {
        throw "Failed to stop servicing processes cleanly: $(Format-ServicingProcessRecords -Records $remaining)"
    }
}

function Resolve-OtherServicingActivity {
    param(
        [int]$WaitSeconds = 45
    )

    $startedAt = Get-Date
    $announcedWait = $false

    while ($true) {
        $records = @(Get-ServicingProcessRecords | Where-Object { $_.ProcessId -ne $PID })
        $blocking = @($records | Where-Object { $_.Name -in @('dism.exe', 'sfc.exe') })

        if (-not $blocking) {
            return
        }

        $elapsed = ((Get-Date) - $startedAt).TotalSeconds
        if ($elapsed -lt $WaitSeconds) {
            if (-not $announcedWait) {
                Write-Step "Waiting up to $WaitSeconds seconds for existing servicing commands to finish: $(Format-ServicingProcessRecords -Records $blocking)"
                $announcedWait = $true
            }

            Start-Sleep -Seconds 5
            continue
        }

        $killable = @($blocking | Where-Object { $_.SafeToStop })
        if ($killable) {
            Write-Step "Stopping stale interactive servicing commands: $(Format-ServicingProcessRecords -Records $killable)"
            Stop-ServicingProcessSet -Records $killable
            $startedAt = Get-Date
            $announcedWait = $false
            continue
        }

        throw "Another non-interactive servicing command is still active: $(Format-ServicingProcessRecords -Records $blocking)"
    }
}

function Wait-ServicingRelease {
    param(
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $blocking = @(Get-ServicingProcessRecords | Where-Object {
            $_.ProcessId -ne $PID -and $_.Name -in @('dism.exe', 'sfc.exe')
        })

        if (-not $blocking) {
            return
        }

        Start-Sleep -Seconds 2
    }

    $remaining = @(Get-ServicingProcessRecords | Where-Object {
        $_.ProcessId -ne $PID -and $_.Name -in @('dism.exe', 'sfc.exe')
    })

    if (-not $remaining) {
        return
    }

    $killable = @($remaining | Where-Object { $_.SafeToStop })
    if ($killable) {
        Write-Step "Clearing lingering interactive servicing commands before exit: $(Format-ServicingProcessRecords -Records $killable)"
        Stop-ServicingProcessSet -Records $killable
        return
    }

    throw "Servicing commands are still active at script exit: $(Format-ServicingProcessRecords -Records $remaining)"
}

function Write-StallDiagnosis {
    param(
        [string]$ProjectRoot,
        [string]$Reason
    )

    $diagDir = Join-Path $ProjectRoot 'diagnostics'
    New-Item -ItemType Directory -Path $diagDir -Force | Out-Null
    $diagPath = Join-Path $diagDir ("stall-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

    $lines = @()
    $lines += "Reason: $Reason"
    $lines += "Timestamp: $(Get-Date -Format o)"
    $lines += ''
    $lines += 'Processes:'
    $lines += (Get-Process dism,TiWorker,sfc -ErrorAction SilentlyContinue | Select-Object ProcessName,Id,CPU,StartTime | Out-String)
    $lines += 'Services:'
    $lines += (Get-Service trustedinstaller,wuauserv,bits,cryptsvc -ErrorAction SilentlyContinue | Select-Object Name,Status,StartType | Out-String)
    $lines += 'Recent DISM log:'
    $lines += ((Get-Content "$env:SystemRoot\Logs\DISM\dism.log" -Tail 80 -ErrorAction SilentlyContinue) -join [Environment]::NewLine)
    $lines += ''
    $lines += 'Recent CBS log:'
    $lines += ((Get-Content "$env:SystemRoot\Logs\CBS\CBS.log" -Tail 120 -ErrorAction SilentlyContinue) -join [Environment]::NewLine)
    Set-Content -Path $diagPath -Value $lines -Encoding ASCII
    Write-Step "Wrote stall diagnosis to $diagPath"
}

function Get-LatestDismSession {
    param([string[]]$Lines)

    $startIndex = -1
    for ($i = $Lines.Count - 1; $i -ge 0; $i--) {
        if ($Lines[$i] -like '*<----- Starting Dism.exe session ----->*') {
            $startIndex = $i
            break
        }
    }

    if ($startIndex -lt 0) {
        return $Lines
    }

    return $Lines[$startIndex..($Lines.Count - 1)]
}

function Get-RepairSignal {
    param(
        [string[]]$DismLines,
        [string[]]$CbsLines
    )

    $dismError = $DismLines | Where-Object {
        $_ -match 'RestoreHealth\(hr:0x80070002\)' -or
        $_ -match 'Failed to restore the image health' -or
        $_ -match 'HRESULT=80070002'
    }

    $cbsMatch = $CbsLines |
        Select-String -Pattern '\\Registry\\Machine\\COMPONENTS\\DerivedData\\VersionedIndex\\(?<version>[^\\]+)\\ComponentFamilies\\(?<family>[^'']+)' -AllMatches |
        Select-Object -Last 1

    if (-not $dismError -or -not $cbsMatch) {
        return $null
    }

    $match = $cbsMatch.Matches[0]
    [pscustomobject]@{
        VersionFolder = $match.Groups['version'].Value
        FamilyName    = $match.Groups['family'].Value
    }
}

function Backup-ComponentsHive {
    param(
        [string]$ProjectRoot,
        [string]$MountName
    )

    $backupDir = Join-Path $ProjectRoot 'backups'
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path $backupDir ("COMPONENTS-{0}.hiv" -f $timestamp)

    Write-Step "Saving HKLM\\$MountName backup to $backupPath"
    & reg.exe save "HKLM\$MountName" $backupPath /y | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $backupPath)) {
        throw "Failed to create COMPONENTS hive backup at $backupPath"
    }

    return $backupPath
}

function Remove-VersionedIndex {
    param(
        [string]$MountName,
        [string]$VersionFolder
    )

    $baseKey = "HKLM\$MountName\DerivedData\VersionedIndex"
    $targetKey = "$baseKey\$VersionFolder"

    if (-not (Test-Path "Registry::$targetKey")) {
        Write-Step "VersionedIndex entry $targetKey is already absent"
        return
    }

    Write-Step "Deleting cache key $targetKey"
    & reg.exe delete $targetKey /f | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed deleting $targetKey"
    }
}

function Invoke-Dism {
    param(
        [int]$StallMinutes,
        [string]$ScratchDir,
        [string]$ProjectRoot
    )

    $dismLogPath = "$env:SystemRoot\Logs\DISM\dism.log"
    $cbsLogPath = "$env:SystemRoot\Logs\CBS\CBS.log"

    Write-Step 'Running DISM /Online /Cleanup-Image /RestoreHealth'
    $process = Start-Process -FilePath "$env:SystemRoot\System32\dism.exe" `
        -ArgumentList @('/Online', '/Cleanup-Image', '/RestoreHealth', "/ScratchDir:$ScratchDir") `
        -NoNewWindow `
        -PassThru

    $lastSignalAt = Get-Date
    $lastDigest = ''

    while (-not $process.HasExited) {
        Start-Sleep -Seconds 15
        $process.Refresh()

        $dismTail = @(Get-Content $dismLogPath -Tail 80 -ErrorAction SilentlyContinue)
        $cbsTail = @(Get-Content $cbsLogPath -Tail 80 -ErrorAction SilentlyContinue)

        $signalLines = @(
            $dismTail | Where-Object { $_ -match '\[\=+' -or $_ -match 'The restore operation completed successfully' -or $_ -match 'Failed to restore the image health' }
            $cbsTail | Where-Object { $_ -match 'WULib DownloadProgress' -or $_ -match 'DWLD:' -or $_ -match 'DPX' -or $_ -match 'Executing operation in uplevel stack' -or $_ -match 'HydrateOnly' }
        ) | Select-Object -Last 3

        $digest = ($signalLines -join "`n")
        if ($digest -and $digest -ne $lastDigest) {
            $lastDigest = $digest
            $lastSignalAt = Get-Date
            Write-Step ("DISM heartbeat: {0}" -f (($signalLines -join ' | ') -replace '\s+', ' ').Trim())
        }

        if (((Get-Date) - $lastSignalAt).TotalMinutes -ge $StallMinutes) {
            Write-StallDiagnosis -ProjectRoot $ProjectRoot -Reason "No new DISM/CBS progress signals for $StallMinutes minutes"
            throw "DISM appears stalled: no new DISM/CBS progress signals for $StallMinutes minutes."
        }
    }

    return $process.ExitCode
}

function Invoke-DismCheckHealth {
    param([string]$ScratchDir)

    Write-Step 'Running DISM /Online /Cleanup-Image /CheckHealth'
    $process = Start-Process -FilePath "$env:SystemRoot\System32\dism.exe" `
        -ArgumentList @('/Online', '/Cleanup-Image', '/CheckHealth', "/ScratchDir:$ScratchDir") `
        -NoNewWindow `
        -Wait `
        -PassThru

    return $process.ExitCode
}

function Invoke-Sfc {
    Write-Step 'Running SFC /SCANNOW'
    $process = Start-Process -FilePath "$env:SystemRoot\System32\sfc.exe" `
        -ArgumentList @('/SCANNOW') `
        -NoNewWindow `
        -Wait `
        -PassThru
    return $process.ExitCode
}

function Invoke-RegBestEffortUnload {
    param([string]$MountName)

    $process = Start-Process -FilePath "$env:SystemRoot\System32\reg.exe" `
        -ArgumentList @('unload', "HKLM\$MountName") `
        -WindowStyle Hidden `
        -Wait `
        -PassThru

    return $process.ExitCode
}

function Test-RegKeyExists {
    param([string]$KeyPath)

    $process = Start-Process -FilePath "$env:SystemRoot\System32\reg.exe" `
        -ArgumentList @('query', $KeyPath) `
        -WindowStyle Hidden `
        -Wait `
        -PassThru

    return ($process.ExitCode -eq 0)
}

function Mount-ComponentsHive {
    param([string]$PreferredMountName)

    if (Test-RegKeyExists -KeyPath "HKLM\$PreferredMountName\DerivedData") {
        Write-Step "Reusing already loaded hive mount HKLM\\$PreferredMountName"
        return $PreferredMountName
    }

    foreach ($candidate in @('TempComponents', 'COMPONENTS')) {
        if (Test-RegKeyExists -KeyPath "HKLM\$candidate\DerivedData") {
            Write-Step "Reusing existing hive mount HKLM\\$candidate"
            return $candidate
        }
    }

    Write-Step 'Loading COMPONENTS hive for repair'
    & reg.exe load "HKLM\$PreferredMountName" "$env:windir\System32\config\COMPONENTS" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to load COMPONENTS hive for repair.'
    }

    return $PreferredMountName
}

function Install-SessionServicingWrappers {
    param([string]$ScriptPath)

    $global:VersionedIndexFixerPath = $ScriptPath
    $global:VersionedIndexRealDismPath = "$env:SystemRoot\System32\dism.exe"
    $global:VersionedIndexRealSfcPath = "$env:SystemRoot\System32\sfc.exe"

    function global:dism {
        param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

        $joined = ($Arguments -join ' ').ToLowerInvariant()
        $isRestoreHealth = $joined -match '(^|\s)/online(\s|$)' -and
            $joined -match '(^|\s)/cleanup-image(\s|$)' -and
            $joined -match '(^|\s)/restorehealth(\s|$)'

        if ($isRestoreHealth) {
            & $global:VersionedIndexFixerPath -SkipSfc
            $global:LASTEXITCODE = if ($?) { 0 } else { 1 }
            return
        }

        & $global:VersionedIndexRealDismPath @Arguments
        $global:LASTEXITCODE = $LASTEXITCODE
    }

    function global:sfc {
        param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

        & $global:VersionedIndexRealSfcPath @Arguments
        $global:LASTEXITCODE = $LASTEXITCODE
    }
}

if (-not (Test-Administrator)) {
    throw 'This repair must be run from an elevated Administrator session.'
}

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$scratchRoot = Join-Path $projectRoot 'scratch'
$tempRoot = Join-Path $projectRoot 'temp'
$logDir = Join-Path $projectRoot 'run-logs'
New-Item -ItemType Directory -Path $scratchRoot -Force | Out-Null
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Install-SessionServicingWrappers -ScriptPath $MyInvocation.MyCommand.Path
$transcriptPath = Join-Path $logDir ("run-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Start-Transcript -Path $transcriptPath -Force | Out-Null

try {
    Resolve-OtherServicingActivity
    Ensure-ServiceRunning -Name 'wuauserv'
    Ensure-ServiceRunning -Name 'bits'
    Ensure-ServiceRunning -Name 'TrustedInstaller'
    Ensure-ServiceRunning -Name 'cryptsvc'
    $env:TEMP = $tempRoot
    $env:TMP = $tempRoot
    $checkExit = Invoke-DismCheckHealth -ScratchDir $scratchRoot
    Write-Step "CheckHealth exit code: $checkExit"

    if ($checkExit -eq 0 -and -not $DeepVerify) {
        Write-Step 'Fast path: CheckHealth reported no component-store corruption. Skipping RestoreHealth and SFC.'
        Write-Step 'Repair completed successfully.'
        return
    }

    $dismExit = Invoke-Dism -StallMinutes $StallMinutes -ScratchDir $scratchRoot -ProjectRoot $projectRoot
    Write-Step "RestoreHealth exit code: $dismExit"

    if ($dismExit -ne 0) {
        $dismLines = Get-Content "$env:windir\Logs\DISM\dism.log" -Tail 400
        $cbsLines = Get-Content "$env:windir\Logs\CBS\CBS.log" -Tail 400
        $latestDism = Get-LatestDismSession -Lines $dismLines
        $signal = Get-RepairSignal -DismLines $latestDism -CbsLines $cbsLines

        if (-not $signal) {
            throw "DISM failed with exit code $dismExit, but the logs do not match the known VersionedIndex Error 2 pattern."
        }

        Write-Step ("Detected missing ComponentFamilies entry: {0}\\{1}" -f $signal.VersionFolder, $signal.FamilyName)
        $mountName = Mount-ComponentsHive -PreferredMountName 'DismFixComponents'
        $shouldUnload = ($mountName -eq 'DismFixComponents')

        try {
            $backupPath = Backup-ComponentsHive -ProjectRoot $projectRoot -MountName $mountName
            Write-Step "Backup complete: $backupPath"
            Remove-VersionedIndex -MountName $mountName -VersionFolder $signal.VersionFolder
        }
        finally {
            if ($shouldUnload) {
                Write-Step 'Unloading repaired COMPONENTS hive'
                $unloadExit = Invoke-RegBestEffortUnload -MountName $mountName
                if ($unloadExit -ne 0) {
                    throw 'Failed to unload repaired COMPONENTS hive.'
                }
            }
        }

        $dismExit = Invoke-Dism -StallMinutes $StallMinutes -ScratchDir $scratchRoot -ProjectRoot $projectRoot
        Write-Step "Post-repair DISM exit code: $dismExit"
        if ($dismExit -ne 0) {
            throw "DISM still failed with exit code $dismExit after VersionedIndex repair"
        }
    }

    if (-not $SkipSfc) {
        $sfcExit = Invoke-Sfc
        Write-Step "SFC exit code: $sfcExit"
        if ($sfcExit -gt 1) {
            throw "SFC returned unexpected exit code $sfcExit"
        }
    }

    Wait-ServicingRelease
    Write-Step 'Repair completed successfully.'
}
finally {
    Stop-Transcript | Out-Null
}
