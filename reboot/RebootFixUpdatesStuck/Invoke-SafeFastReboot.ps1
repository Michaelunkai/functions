#requires -Version 5.1

<#!
.SYNOPSIS
    Fail-closed reboot guard for Windows Update and component servicing.

.DESCRIPTION
    This script does not try to make Windows abandon an update.  That would
    risk data loss and component-store corruption, and Windows does not expose
    a safe way to guarantee a reboot duration.  Instead, it audits the known
    pending-reboot signals and active servicing processes, waits no longer than
    the requested bounded interval, and refuses to request a reboot while the
    state is unresolved.

    InstallGuard mode only enforces the narrow Windows Update policy that
    prevents automatic reboot while a user is logged on.  It does not disable
    updates, terminate servicing, edit pending-file queues, create a scheduled
    task, or reboot the computer.

.EXAMPLE
    powershell.exe -NoProfile -File .\Invoke-SafeFastReboot.ps1 -Mode Audit

.EXAMPLE
    powershell.exe -NoProfile -File .\Invoke-SafeFastReboot.ps1 -Mode InstallGuard

.EXAMPLE
    powershell.exe -NoProfile -File .\Invoke-SafeFastReboot.ps1 -Mode Reboot
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Audit', 'InstallGuard', 'RemoveGuard', 'Reboot')]
    [string]$Mode = 'Audit',

    [ValidateRange(0, 10)]
    [int]$WaitSeconds = 0,

    [string]$LogPath,

    [string]$BackupPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ScriptRoot = if ($PSScriptRoot) {
    $PSScriptRoot
}
else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
$script:ScriptPath = if ($MyInvocation.MyCommand.Path) {
    [System.IO.Path]::GetFullPath($MyInvocation.MyCommand.Path)
}
else {
    $null
}

if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = Join-Path $script:ScriptRoot 'logs\SafeRebootGuard.log'
}
if ([string]::IsNullOrWhiteSpace($BackupPath)) {
    $BackupPath = Join-Path $script:ScriptRoot 'state\SafeRebootGuard.policy-backup.json'
}

$script:PolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
$script:PolicyValue = 'NoAutoRebootWithLoggedOnUsers'

function Ensure-ParentDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Write-LogLine {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffK'), $Level, $Message
    Write-Host $line
    try {
        Ensure-ParentDirectory -Path $LogPath
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    }
    catch {
        Write-Host ('[{0}] [WARN] Could not write log file: {1}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffK'), $_.Exception.Message)
    }
}

function Get-RegistrySnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$KeyPath,
        [Parameter(Mandatory = $true)][string]$ValueName
    )

    $keyExists = Test-Path -LiteralPath $KeyPath -PathType Container
    $valueExists = $false
    $value = $null
    $valueKind = 'None'

    if ($keyExists) {
        try {
            $props = Get-ItemProperty -LiteralPath $KeyPath -ErrorAction Stop
            $property = $props.PSObject.Properties | Where-Object { $_.Name -eq $ValueName } | Select-Object -First 1
            if ($null -ne $property) {
                $valueExists = $true
                $value = $property.Value
            }

            $subPath = $KeyPath -replace '^HKLM:\\', ''
            $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                [Microsoft.Win32.RegistryHive]::LocalMachine,
                [Microsoft.Win32.RegistryView]::Default
            )
            try {
                $nativeKey = $baseKey.OpenSubKey($subPath, $false)
                if ($nativeKey) {
                    try {
                        if ($valueExists) {
                            $valueKind = [string]$nativeKey.GetValueKind($ValueName)
                        }
                    }
                    finally {
                        $nativeKey.Dispose()
                    }
                }
            }
            finally {
                $baseKey.Dispose()
            }
        }
        catch {
            throw ('Could not read registry state {0}\{1}: {2}' -f $KeyPath, $ValueName, $_.Exception.Message)
        }
    }

    [pscustomobject]@{
        KeyPath     = $KeyPath
        ValueName   = $ValueName
        KeyExists   = [bool]$keyExists
        ValueExists = [bool]$valueExists
        Value       = $value
        ValueKind   = $valueKind
    }
}

function Get-PendingRebootSignals {
    $signals = @()

    $cbsKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    if (Test-Path -LiteralPath $cbsKey -PathType Container) {
        $signals += [pscustomobject]@{ Name = 'CBS RebootPending key'; Detail = $cbsKey }
    }

    foreach ($cbsMarker in @('PackagesPending', 'RebootInProgress', 'AdvancedInstallersNeedResolving')) {
        $cbsMarkerPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\{0}' -f $cbsMarker
        if (Test-Path -LiteralPath $cbsMarkerPath -PathType Container) {
            $signals += [pscustomobject]@{ Name = ('CBS {0} key' -f $cbsMarker); Detail = $cbsMarkerPath }
        }
    }

    $wuKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    if (Test-Path -LiteralPath $wuKey -PathType Container) {
        $signals += [pscustomobject]@{ Name = 'Windows Update RebootRequired key'; Detail = $wuKey }
    }

    $sessionManager = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    try {
        $renameOperations = (Get-ItemProperty -LiteralPath $sessionManager -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue).PendingFileRenameOperations
        if ($renameOperations) {
            $signals += [pscustomobject]@{ Name = 'PendingFileRenameOperations'; Detail = $sessionManager }
        }
    }
    catch {
        $signals += [pscustomobject]@{ Name = 'Unable to read PendingFileRenameOperations'; Detail = $_.Exception.Message }
    }

    $updateVolatileKey = 'HKLM:\SOFTWARE\Microsoft\Updates'
    try {
        $updateProperties = Get-ItemProperty -LiteralPath $updateVolatileKey -ErrorAction SilentlyContinue
        $updateVolatileProperty = $updateProperties.PSObject.Properties | Where-Object { $_.Name -eq 'UpdateExeVolatile' } | Select-Object -First 1
        if ($null -ne $updateVolatileProperty -and $null -ne $updateVolatileProperty.Value -and [int]$updateVolatileProperty.Value -ne 0) {
            $signals += [pscustomobject]@{ Name = 'UpdateExeVolatile'; Detail = [string]$updateVolatileProperty.Value }
        }
    }
    catch {
        $signals += [pscustomobject]@{ Name = 'Unable to read UpdateExeVolatile'; Detail = $_.Exception.Message }
    }

    $pendingXml = Join-Path $env:windir 'WinSxS\pending.xml'
    if (Test-Path -LiteralPath $pendingXml -PathType Leaf) {
        $signals += [pscustomobject]@{ Name = 'WinSxS pending.xml'; Detail = $pendingXml }
    }

    return @($signals)
}

function Get-ActiveServicingProcesses {
    $names = @(
        'TrustedInstaller',
        'TiWorker',
        'dism',
        'MoUsoCoreWorker',
        'UsoClient',
        'wuauclt',
        'MusNotification',
        'MusNotificationUx',
        'setuphost',
        'Windows10UpgraderApp'
    )
    $found = @()

    foreach ($name in $names) {
        try {
            foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
                $found += [pscustomobject]@{
                    Name = $process.ProcessName
                    Id   = $process.Id
                }
            }
        }
        catch {
            $found += [pscustomobject]@{
                Name = $name
                Id   = 'unreadable'
            }
        }
    }

    return @($found)
}

function Get-RunningUpdateTasks {
    $found = @()
    $getScheduledTask = Get-Command -Name 'Get-ScheduledTask' -ErrorAction SilentlyContinue
    if ($null -eq $getScheduledTask) {
        return @($found)
    }

    try {
        $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
            ([string]$_.State) -eq 'Running' -and
            $_.TaskPath -match '\\Microsoft\\Windows\\(UpdateOrchestrator|WindowsUpdate)\\'
        })
        foreach ($task in $tasks) {
            $found += [pscustomobject]@{
                TaskPath = $task.TaskPath
                TaskName = $task.TaskName
                State    = [string]$task.State
            }
        }
    }
    catch {
        $found += [pscustomobject]@{
            TaskPath = 'unreadable'
            TaskName = 'Get-ScheduledTask'
            State    = $_.Exception.Message
        }
    }

    return @($found)
}

function Get-RebootGate {
    $pending = @(Get-PendingRebootSignals)
    $processes = @(Get-ActiveServicingProcesses)
    $tasks = @(Get-RunningUpdateTasks)
    $reasons = @()
    $policy = Get-RegistrySnapshot -KeyPath $script:PolicyKey -ValueName $script:PolicyValue

    foreach ($item in $pending) {
        $reasons += ('Pending reboot signal: {0} ({1})' -f $item.Name, $item.Detail)
    }
    foreach ($item in $processes) {
        $reasons += ('Active servicing/update process: {0} (PID {1})' -f $item.Name, $item.Id)
    }
    foreach ($item in $tasks) {
        $reasons += ('Running update task: {0}{1}' -f $item.TaskPath, $item.TaskName)
    }

    [pscustomobject]@{
        CheckedAt         = Get-Date
        SafeToRequestReboot = ($reasons.Count -eq 0)
        PendingSignals     = $pending
        ActiveProcesses    = $processes
        RunningTasks       = $tasks
        Policy             = $policy
        Reasons            = @($reasons)
    }
}

function Write-GateReport {
    param([Parameter(Mandatory = $true)]$Gate)

    Write-LogLine -Level 'INFO' -Message ('SafeToRequestReboot={0}; PendingSignals={1}; ActiveProcesses={2}; RunningTasks={3}' -f `
        $Gate.SafeToRequestReboot, @($Gate.PendingSignals).Count, @($Gate.ActiveProcesses).Count, @($Gate.RunningTasks).Count)
    Write-LogLine -Level 'INFO' -Message ('Policy {0}\{1}: Exists={2}; ValueExists={3}; Value={4}; Type={5}' -f `
        $Gate.Policy.KeyPath, $Gate.Policy.ValueName, $Gate.Policy.KeyExists, $Gate.Policy.ValueExists, $Gate.Policy.Value, $Gate.Policy.ValueKind)

    foreach ($reason in @($Gate.Reasons)) {
        Write-LogLine -Level 'WARN' -Message $reason
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-TrustedExecutionPath {
    $expectedRoot = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'SafeRebootGuard'
    if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) {
        Write-LogLine -Level 'ERROR' -Message 'The script has no resolvable file path; refusing a mutating mode.'
        return $false
    }

    try {
        $scriptItem = Get-Item -LiteralPath $script:ScriptPath -Force -ErrorAction Stop
        $rootItem = Get-Item -LiteralPath $expectedRoot -Force -ErrorAction Stop
        if ([string]::Compare($scriptItem.DirectoryName, $rootItem.FullName, $true) -ne 0) {
            Write-LogLine -Level 'ERROR' -Message ('Mutating modes require the script directly under the protected path {0}; current path is {1}.' -f $expectedRoot, $scriptItem.FullName)
            return $false
        }
        if (($scriptItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Write-LogLine -Level 'ERROR' -Message 'The script or its protected directory is a reparse point; refusing a mutating mode.'
            return $false
        }

        $acl = Get-Acl -LiteralPath $rootItem.FullName -ErrorAction Stop
        foreach ($rule in @($acl.Access)) {
            $identity = [string]$rule.IdentityReference
            $rights = [string]$rule.FileSystemRights
            $isBroadPrincipal = $identity -match '(?i)(^|\\)(Everyone|Authenticated Users|Users)$' -or $identity -match '(?i)^BUILTIN\\Users$'
            $isWriteRight = $rights -match '(?i)(Write|Modify|FullControl|Delete)'
            if ($rule.AccessControlType -eq 'Allow' -and $isBroadPrincipal -and $isWriteRight) {
                Write-LogLine -Level 'ERROR' -Message ('Protected path ACL grants {0} write-like rights ({1}); refusing a mutating mode.' -f $identity, $rights)
                return $false
            }
        }
    }
    catch {
        Write-LogLine -Level 'ERROR' -Message ('Could not validate protected execution path: {0}' -f $_.Exception.Message)
        return $false
    }

    return $true
}

function Save-PolicyBackup {
    param([Parameter(Mandatory = $true)]$Snapshot)

    if (Test-Path -LiteralPath $BackupPath -PathType Leaf) {
        try {
            $existing = Get-Content -LiteralPath $BackupPath -Raw -ErrorAction Stop | ConvertFrom-Json
            if ([string]$existing.MachineName -ne [Environment]::MachineName -or [string]$existing.KeyPath -ne $script:PolicyKey) {
                throw 'An existing backup belongs to a different machine or policy key.'
            }
            Write-LogLine -Level 'INFO' -Message ('Preserving existing policy backup: {0}' -f $BackupPath)
            return
        }
        catch {
            throw ('Refusing to overwrite or trust the existing policy backup: {0}' -f $_.Exception.Message)
        }
    }

    Ensure-ParentDirectory -Path $BackupPath
    $backup = [pscustomobject]@{
        Schema      = 1
        MachineName = [Environment]::MachineName
        CapturedAt  = (Get-Date).ToUniversalTime().ToString('o')
        KeyPath     = $Snapshot.KeyPath
        ValueName   = $Snapshot.ValueName
        KeyExists   = $Snapshot.KeyExists
        ValueExists = $Snapshot.ValueExists
        Value       = $Snapshot.Value
        ValueKind   = $Snapshot.ValueKind
    }
    $backup | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $BackupPath -Encoding UTF8
    Write-LogLine -Level 'INFO' -Message ('Saved policy backup: {0}' -f $BackupPath)
}

function Set-NoAutoRebootPolicy {
    $snapshot = Get-RegistrySnapshot -KeyPath $script:PolicyKey -ValueName $script:PolicyValue
    if ($snapshot.ValueExists -and $snapshot.ValueKind -eq 'DWord' -and [int]$snapshot.Value -eq 1) {
        Write-LogLine -Level 'INFO' -Message 'NoAutoRebootWithLoggedOnUsers is already REG_DWORD 1; no registry change required.'
        return $true
    }

    if ($WhatIfPreference) {
        Write-LogLine -Level 'INFO' -Message ('WHATIF: would back up and set {0}\{1} to REG_DWORD 1.' -f $script:PolicyKey, $script:PolicyValue)
        return $true
    }

    Save-PolicyBackup -Snapshot $snapshot
    if (-not (Test-Path -LiteralPath $script:PolicyKey -PathType Container)) {
        New-Item -Path $script:PolicyKey -Force | Out-Null
    }

    if ($snapshot.ValueExists -and $snapshot.ValueKind -ne 'DWord') {
        Remove-ItemProperty -LiteralPath $script:PolicyKey -Name $script:PolicyValue -Force
    }
    New-ItemProperty -LiteralPath $script:PolicyKey -Name $script:PolicyValue -PropertyType DWord -Value 1 -Force | Out-Null

    $verified = Get-RegistrySnapshot -KeyPath $script:PolicyKey -ValueName $script:PolicyValue
    if (-not ($verified.ValueExists -and $verified.ValueKind -eq 'DWord' -and [int]$verified.Value -eq 1)) {
        throw 'Policy write verification failed.'
    }

    Write-LogLine -Level 'INFO' -Message 'Verified NoAutoRebootWithLoggedOnUsers=1.'
    return $true
}

function Restore-NoAutoRebootPolicy {
    if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
        throw ('No policy backup exists at {0}; refusing to remove an unowned policy value.' -f $BackupPath)
    }

    $backup = Get-Content -LiteralPath $BackupPath -Raw -ErrorAction Stop | ConvertFrom-Json
    if ([string]$backup.MachineName -ne [Environment]::MachineName -or [string]$backup.KeyPath -ne $script:PolicyKey) {
        throw 'The policy backup does not belong to this machine or policy key.'
    }

    if ($WhatIfPreference) {
        Write-LogLine -Level 'INFO' -Message ('WHATIF: would restore {0}\{1} from {2}.' -f $script:PolicyKey, $script:PolicyValue, $BackupPath)
        return $true
    }

    if ($backup.ValueExists) {
        if (-not (Test-Path -LiteralPath $script:PolicyKey -PathType Container)) {
            New-Item -Path $script:PolicyKey -Force | Out-Null
        }
        if ((Get-RegistrySnapshot -KeyPath $script:PolicyKey -ValueName $script:PolicyValue).ValueExists) {
            Remove-ItemProperty -LiteralPath $script:PolicyKey -Name $script:PolicyValue -Force
        }
        $restoreType = [string]$backup.ValueKind
        if (@('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord') -notcontains $restoreType) {
            throw ('Unsupported registry value kind in backup: {0}' -f $restoreType)
        }
        New-ItemProperty -LiteralPath $script:PolicyKey -Name $script:PolicyValue -PropertyType $restoreType -Value $backup.Value -Force | Out-Null
    }
    elseif (Test-Path -LiteralPath $script:PolicyKey -PathType Container) {
        Remove-ItemProperty -LiteralPath $script:PolicyKey -Name $script:PolicyValue -Force -ErrorAction SilentlyContinue
    }

    $verified = Get-RegistrySnapshot -KeyPath $script:PolicyKey -ValueName $script:PolicyValue
    if ([bool]$backup.ValueExists -ne [bool]$verified.ValueExists) {
        throw 'Policy restore verification failed.'
    }
    if ($backup.ValueExists -and ([string]$verified.ValueKind -ne [string]$backup.ValueKind -or [string]$verified.Value -ne [string]$backup.Value)) {
        throw 'Policy restore value verification failed.'
    }

    Write-LogLine -Level 'INFO' -Message 'Verified restoration of the previously captured policy value.'
    return $true
}

function Invoke-RebootRequest {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $gate = $null

    do {
        $gate = Get-RebootGate
        Write-GateReport -Gate $gate
        if ($gate.SafeToRequestReboot) {
            break
        }
        if ($WaitSeconds -le 0 -or (Get-Date) -ge $deadline) {
            break
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    if (-not $gate.SafeToRequestReboot) {
        Write-LogLine -Level 'ERROR' -Message ('Refusing reboot after a bounded {0}-second preflight; servicing state is unresolved.' -f $WaitSeconds)
        return 3
    }

    $shutdownPath = Join-Path ([Environment]::SystemDirectory) 'shutdown.exe'
    $shutdownArguments = @(
        '/r',
        '/t',
        '0',
        '/d',
        'p:0:0',
        '/c',
        'SafeRebootGuard approved restart after a clean servicing preflight'
    )

    if ($WhatIfPreference) {
        Write-LogLine -Level 'INFO' -Message ('WHATIF: would run {0} {1}' -f $shutdownPath, ($shutdownArguments -join ' '))
        return 0
    }

    if (-not $PSCmdlet.ShouldProcess('local computer', 'request a restart after a clean servicing preflight')) {
        Write-LogLine -Level 'INFO' -Message 'Restart request declined by ShouldProcess.'
        return 0
    }

    & $shutdownPath @shutdownArguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-LogLine -Level 'ERROR' -Message ('shutdown.exe failed with exit code {0}.' -f $exitCode)
        return 5
    }

    Write-LogLine -Level 'INFO' -Message 'shutdown.exe accepted the restart request. Actual reboot duration is not proven by this script.'
    return 0
}

function Invoke-SafeFastReboot {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Audit', 'InstallGuard', 'RemoveGuard', 'Reboot')][string]$RequestedMode,
        [Parameter(Mandatory = $true)][int]$RequestedWaitSeconds
    )

    try {
        switch ($RequestedMode) {
            'Audit' {
                $gate = Get-RebootGate
                Write-GateReport -Gate $gate
                if ($gate.SafeToRequestReboot) {
                    Write-LogLine -Level 'INFO' -Message 'Audit result: no known pending or active servicing signal was found.'
                    return 0
                }
                Write-LogLine -Level 'WARN' -Message 'Audit result: reboot is not approved by this guard.'
                return 3
            }

            'InstallGuard' {
                if (-not (Test-TrustedExecutionPath)) {
                    return 6
                }
                if (-not (Test-IsAdministrator)) {
                    Write-LogLine -Level 'ERROR' -Message 'InstallGuard requires an elevated PowerShell session.'
                    return 4
                }
                [void](Set-NoAutoRebootPolicy)
                Write-LogLine -Level 'INFO' -Message 'InstallGuard completed; no reboot was requested.'
                return 0
            }

            'RemoveGuard' {
                if (-not (Test-TrustedExecutionPath)) {
                    return 6
                }
                if (-not (Test-IsAdministrator)) {
                    Write-LogLine -Level 'ERROR' -Message 'RemoveGuard requires an elevated PowerShell session.'
                    return 4
                }
                [void](Restore-NoAutoRebootPolicy)
                Write-LogLine -Level 'INFO' -Message 'RemoveGuard completed; no reboot was requested.'
                return 0
            }

            'Reboot' {
                if (-not (Test-TrustedExecutionPath)) {
                    return 6
                }
                if (-not (Test-IsAdministrator)) {
                    Write-LogLine -Level 'ERROR' -Message 'Reboot mode requires an elevated PowerShell session.'
                    return 4
                }
                return (Invoke-RebootRequest)
            }
        }
    }
    catch {
        Write-LogLine -Level 'ERROR' -Message $_.Exception.Message
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $resultCode = Invoke-SafeFastReboot -RequestedMode $Mode -RequestedWaitSeconds $WaitSeconds
    exit ([int]$resultCode)
}
