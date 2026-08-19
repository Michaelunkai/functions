# Safe startup/bootstrap optimizer for this Windows profile.
# Extracted from C:\users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1.
$__extractedFunctionName = 'allstart'
$__extractedScriptPath = $PSCommandPath
if (-not $__extractedScriptPath) { $__extractedScriptPath = $MyInvocation.MyCommand.Path }
$__extractedArgs = @($args)
$__projectRoot = Split-Path -Parent $__extractedScriptPath
$__configPath = Join-Path $__projectRoot 'allstart.config.psd1'
$__customConfigPath = Join-Path $__projectRoot 'allstart.custom.psd1'

if ($__extractedArgs -contains '-SelfTest') {
    [pscustomobject]@{
        Script = $__extractedScriptPath
        Exists = (Test-Path -LiteralPath $__extractedScriptPath)
        Function = $__extractedFunctionName
        Mode = 'SelfTest'
        Config = $__configPath
        ConfigExists = (Test-Path -LiteralPath $__configPath)
        CustomConfig = $__customConfigPath
        CustomConfigExists = (Test-Path -LiteralPath $__customConfigPath)
    }
    return
}

function allstart {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [ValidateSet('Startup', 'Audit', 'SafeApply', 'Verify', 'Restore')]
        [string]$Mode = 'Startup',

        [switch]$DryRun,
        [string]$ConfigPath,
        [string]$SnapshotPath
    )

    Invoke-AllStartMain -Mode $Mode -DryRun:$DryRun -ConfigPath $ConfigPath -SnapshotPath $SnapshotPath
}

function Invoke-AllStartMain {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [ValidateSet('Startup', 'Audit', 'SafeApply', 'Verify', 'Restore')]
        [string]$Mode,
        [switch]$DryRun,
        [string]$ConfigPath,
        [string]$SnapshotPath
    )

    $started = Get-Date
    $context = New-AllStartContext -Mode $Mode -DryRun:$DryRun -ConfigPath $ConfigPath
    try {
        Write-AllStartLog $context 'INFO' "allstart mode started: $Mode"
        Write-AllStartLog $context 'INFO' "Admin: $($context.IsAdmin); DryRun: $($context.DryRun); PowerShell: $($PSVersionTable.PSVersion)"

        if ($Mode -eq 'Restore') {
            Invoke-AllStartRestore -Context $context -SnapshotPath $SnapshotPath
            return
        }

        if ($Mode -eq 'Audit') {
            $snapshot = New-AllStartSnapshot -Context $context -Reason $Mode -IncludeAudit
            Write-AllStartLog $context 'INFO' "Snapshot ready: $snapshot"
            $inventory = Get-AllStartInventory -Context $context -IncludeAudit
            $classifications = Classify-AllStartInventory -Context $context -Inventory $inventory
            Write-AllStartClassificationSummary -Context $context -Classifications $classifications
        } elseif ($Mode -in @('Startup', 'SafeApply')) {
            Ensure-RequiredRunEntries -Context $context
            Ensure-RequiredScheduledTasks -Context $context
            Ensure-PhoneLinkReadiness -Context $context
            Ensure-RequiredAppStartupTasks -Context $context
            Ensure-ClawdBotStartup -Context $context -AllowRepair:($Mode -eq 'SafeApply' -or $Mode -eq 'Startup')
            Invoke-ExplicitStartupRules -Context $context
            Invoke-StartupAllowlistEnforcement -Context $context
        }

        if ($Mode -eq 'Verify') {
            Test-AllStartProtectedLaunchers -Context $context
        }

        $elapsed = [int]((Get-Date) - $started).TotalMilliseconds
        Write-AllStartLog $context 'INFO' "allstart mode completed in ${elapsed}ms"
    } catch {
        Write-AllStartLog $context 'ERROR' "allstart failed: $($_.Exception.Message)"
        throw
    }
}

function New-AllStartContext {
    param(
        [string]$Mode,
        [switch]$DryRun,
        [string]$ConfigPath
    )

    $root = Split-Path -Parent $__extractedScriptPath
    if (-not $ConfigPath) { $ConfigPath = Join-Path $root 'allstart.config.psd1' }
    if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config not found: $ConfigPath" }
    $config = Import-PowerShellDataFile -LiteralPath $ConfigPath
    Assert-AllStartConfig -Config $config -ConfigPath $ConfigPath
    $config = Convert-AllStartConfigToMurmure -Config $config
    $config = Merge-AllStartCustomScheduledTasks -Config $config -Root $root -CustomConfigPath (Join-Path $root 'allstart.custom.psd1')

    $logsDir = Join-Path $root 'logs'
    $snapshotsDir = Join-Path $root 'snapshots'
    $quarantineDir = Join-Path $root 'quarantine'
    foreach ($dir in @($logsDir, $snapshotsDir, $quarantineDir)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    $logPath = Join-Path $logsDir ("allstart-{0}-latest.jsonl" -f $Mode.ToLowerInvariant())
    Set-Content -LiteralPath $logPath -Value '' -Encoding UTF8

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    [pscustomobject]@{
        Root = $root
        ConfigPath = $ConfigPath
        CustomConfigPath = (Join-Path $root 'allstart.custom.psd1')
        Config = $config
        Mode = $Mode
        DryRun = [bool]$DryRun
        LogsDir = $logsDir
        LogPath = $logPath
        SnapshotsDir = $snapshotsDir
        QuarantineDir = $quarantineDir
        IsAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        Hostname = [Environment]::MachineName
        Started = Get-Date
        SnapshotPath = $null
    }
}

function Convert-AllStartConfigToMurmure {
    param([hashtable]$Config)

    $murmurePath = 'C:\Program Files\murmure\murmure.exe'
    $murmureVbsPath = 'C:\Users\micha\.claude\scripts\murmure-silent.vbs'

    if ($Config.Settings.ContainsKey('SnapshotTaskNames')) {
        $Config.Settings.SnapshotTaskNames = @(
            foreach ($name in @($Config.Settings.SnapshotTaskNames)) {
                if ($name -eq 'OpenWhisper_Tray') { 'Murmure_Tray' } else { $name }
            }
        )
    }

    if ($Config.RequiredLaunchPoints.ContainsKey('OpenWhisperExe')) {
        $Config.RequiredLaunchPoints.Remove('OpenWhisperExe')
    }
    if ($Config.RequiredLaunchPoints.ContainsKey('OpenWhisperVbs')) {
        $Config.RequiredLaunchPoints.Remove('OpenWhisperVbs')
    }
    $Config.RequiredLaunchPoints['MurmureExe'] = $murmurePath
    $Config.RequiredLaunchPoints['MurmureVbs'] = $murmureVbsPath

    $Config.RequiredScheduledTasks = @(
        foreach ($task in @($Config.RequiredScheduledTasks)) {
            if ($task.Name -eq 'OpenWhisper_Tray') {
                @{
                    Name = 'Murmure_Tray'
                    Execute = 'C:\Windows\System32\wscript.exe'
                    Arguments = "`"$murmureVbsPath`""
                    Description = 'Murmure tray launcher at logon'
                }
            } else {
                $task
            }
        }
    )

    return $Config
}

function Merge-AllStartCustomScheduledTasks {
    param(
        [hashtable]$Config,
        [string]$Root,
        [string]$CustomConfigPath
    )

    if (-not (Test-Path -LiteralPath $CustomConfigPath)) {
        return $Config
    }

    $customConfig = Import-PowerShellDataFile -LiteralPath $CustomConfigPath
    $customTasks = @()
    if ($customConfig.ContainsKey('CustomScheduledTasks')) {
        $customTasks = @($customConfig.CustomScheduledTasks)
    }
    $disabledBuiltIns = @()
    if ($customConfig.ContainsKey('DisabledBuiltIns')) {
        $disabledBuiltIns = @($customConfig.DisabledBuiltIns)
    }
    if (@($customTasks).Count -eq 0) {
        if (@($disabledBuiltIns).Count -eq 0) {
            return $Config
        }
    }

    $scheduledTaskSpecs = @(
        foreach ($task in $customTasks) {
            if ($task.ContainsKey('EntryType') -and $task.EntryType -eq 'AppStartupTask') { continue }
            New-AllStartCustomScheduledTaskSpec -Root $Root -Task $task
        }
    )
    $appStartupTaskSpecs = @(
        foreach ($task in $customTasks) {
            if (-not ($task.ContainsKey('EntryType') -and $task.EntryType -eq 'AppStartupTask')) { continue }
            New-AllStartCustomAppStartupTaskSpec -Task $task
        }
    )

    $Config.RequiredScheduledTasks = @(
        @($Config.RequiredScheduledTasks)
        @($scheduledTaskSpecs)
    )
    $Config.RequiredAppStartupTasks = @(
        @($Config.RequiredAppStartupTasks)
        @($appStartupTaskSpecs)
    )
    $Config.Settings.SnapshotTaskNames = @(
        @($Config.Settings.SnapshotTaskNames)
        @($scheduledTaskSpecs | ForEach-Object { $_.Name })
    ) | Where-Object { $_ } | Sort-Object -Unique

    if (@($disabledBuiltIns).Count -gt 0) {
        $Config.RequiredScheduledTasks = @(
            foreach ($task in @($Config.RequiredScheduledTasks)) {
                if ($disabledBuiltIns -contains $task.Name) { continue }
                $task
            }
        )
        $Config.Settings.SnapshotTaskNames = @(
            foreach ($name in @($Config.Settings.SnapshotTaskNames)) {
                if ($disabledBuiltIns -contains $name) { continue }
                $name
            }
        ) | Where-Object { $_ } | Sort-Object -Unique
    }

    return $Config
}

function Resolve-AllStartCurrentWindowsAppsTargetPath {
    param([string]$TargetPath)

    if ([string]::IsNullOrWhiteSpace($TargetPath)) { return $null }
    $expanded = [Environment]::ExpandEnvironmentVariables($TargetPath)
    if (Test-Path -LiteralPath $expanded -PathType Leaf) {
        return (Resolve-Path -LiteralPath $expanded).ProviderPath
    }
    if ($expanded -notmatch '(?i)\\WindowsApps\\([^\\]+)\\(.+)$') { return $null }

    $oldPackageFolder = $matches[1]
    $relativePath = $matches[2]
    $packageName = $null
    $publisherSuffix = $null
    if ($oldPackageFolder -match '^(.+?)_[0-9]') { $packageName = $matches[1] }
    if ($oldPackageFolder -match '__(.+)$') { $publisherSuffix = $matches[1] }

    $packages = @(
        Get-AppxPackage -ErrorAction SilentlyContinue |
            Where-Object {
                $_.InstallLocation -and
                (Test-Path -LiteralPath $_.InstallLocation) -and
                (
                    ($packageName -and $_.Name.Equals($packageName, [System.StringComparison]::OrdinalIgnoreCase)) -or
                    ($publisherSuffix -and $_.PackageFamilyName.EndsWith("_$publisherSuffix", [System.StringComparison]::OrdinalIgnoreCase))
                )
            } |
            Sort-Object PackageFullName -Descending
    )

    foreach ($package in $packages) {
        $sameRelativePath = Join-Path $package.InstallLocation $relativePath
        if (Test-Path -LiteralPath $sameRelativePath -PathType Leaf) {
            return (Resolve-Path -LiteralPath $sameRelativePath).ProviderPath
        }

        $leaf = [IO.Path]::GetFileName($expanded)
        if (-not [string]::IsNullOrWhiteSpace($leaf)) {
            $match = Get-ChildItem -LiteralPath $package.InstallLocation -Filter $leaf -File -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($match) { return $match.FullName }
        }
    }

    return $null
}

function Resolve-AllStartCurrentTargetPath {
    param([string]$TargetPath)

    if ([string]::IsNullOrWhiteSpace($TargetPath)) { return $TargetPath }
    $expanded = [Environment]::ExpandEnvironmentVariables($TargetPath)
    if (Test-Path -LiteralPath $expanded -PathType Leaf) {
        return (Resolve-Path -LiteralPath $expanded).ProviderPath
    }

    $windowsAppsTarget = Resolve-AllStartCurrentWindowsAppsTargetPath -TargetPath $expanded
    if ($windowsAppsTarget) { return $windowsAppsTarget }

    return $TargetPath
}

function New-AllStartCustomScheduledTaskSpec {
    param(
        [string]$Root,
        [hashtable]$Task
    )

    $launcherPath = 'C:\Users\micha\.claude\scripts\trayquiet-start.vbs'
    $wscriptExe = Get-AllStartWindowsScriptHostExe
    $targetPath = Resolve-AllStartCurrentTargetPath -TargetPath ([string]$Task.TargetPath)

    @{
        Name = [string]$Task.Name
        Execute = $wscriptExe
        Arguments = "//B //Nologo `"$launcherPath`" `"$targetPath`" 120 0 25"
        Description = if ($Task.ContainsKey('Description') -and $Task.Description) { [string]$Task.Description } else { "Custom startup target: $targetPath" }
    }
}

function New-AllStartCustomAppStartupTaskSpec {
    param([hashtable]$Task)

    @{
        Name = [string]$Task.Name
        PackageFamilyName = [string]$Task.PackageFamilyName
        TaskId = [string]$Task.TaskId
        EnabledState = if ($Task.ContainsKey('EnabledState')) { [int]$Task.EnabledState } else { 2 }
    }
}

function Get-AllStartWindowsPowerShellExe {
    $powershellExe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $powershellExe)) {
        throw "Windows PowerShell executable not found: $powershellExe"
    }
    return $powershellExe
}

function Get-AllStartWindowsScriptHostExe {
    $wscriptExe = Join-Path $env:SystemRoot 'System32\wscript.exe'
    if (-not (Test-Path -LiteralPath $wscriptExe)) {
        throw "Windows Script Host executable not found: $wscriptExe"
    }
    return $wscriptExe
}

function Assert-AllStartConfig {
    param(
        [hashtable]$Config,
        [string]$ConfigPath
    )

    foreach ($key in @('Settings', 'RequiredLaunchPoints', 'RequiredRegistryRun', 'RequiredScheduledTasks', 'RequiredAppStartupTasks', 'ProtectedNames', 'ExplicitDisableRules', 'DelayRules')) {
        if (-not $Config.ContainsKey($key)) { throw "Config $ConfigPath is missing key: $key" }
    }
    foreach ($key in @('AhkScript', 'AutoHotkeyExe', 'FullScreenSnipExe', 'OpenSpeedyExe', 'OpenSpeedyVbs', 'MurmureExe', 'MurmureVbs', 'PhoneLinkAppId', 'PhoneLinkPackageFamilyName', 'PhoneLinkStartupTaskId', 'CrossDevicePackageFamilyName', 'ClawdBotTrayVbs', 'ClawdBotManagerExe', 'ClawdBotConfigPath', 'ClawdBotRestartScript')) {
        if (-not $Config.RequiredLaunchPoints.ContainsKey($key)) { throw "Config RequiredLaunchPoints is missing key: $key" }
    }
    foreach ($entry in @($Config.RequiredRegistryRun)) {
        foreach ($key in @('Name', 'Command', 'Hive')) {
            if (-not $entry.ContainsKey($key)) { throw "Every RequiredRegistryRun entry must include $key." }
        }
        if ($entry.Hive -notin @('HKCU', 'HKLM')) { throw "Unsupported RequiredRegistryRun hive: $($entry.Hive)" }
    }
    foreach ($task in @($Config.RequiredScheduledTasks)) {
        foreach ($key in @('Name', 'Execute', 'Description')) {
            if (-not $task.ContainsKey($key)) { throw "Every RequiredScheduledTasks entry must include $key." }
        }
    }
    foreach ($task in @($Config.RequiredAppStartupTasks)) {
        foreach ($key in @('Name', 'PackageFamilyName', 'TaskId')) {
            if (-not $task.ContainsKey($key)) { throw "Every RequiredAppStartupTasks entry must include $key." }
        }
    }
    foreach ($rule in @($Config.ExplicitDisableRules)) {
        if (-not $rule.ExactName -or -not $rule.Surface) {
            throw 'Every ExplicitDisableRules entry must include Surface and ExactName.'
        }
    }
    foreach ($rule in @($Config.DelayRules)) {
        if (-not $rule.ExactName -or -not $rule.Surface -or -not $rule.DelaySeconds) {
            throw 'Every DelayRules entry must include Surface, ExactName, and DelaySeconds.'
        }
    }
}

function Resolve-AllStartFolderPath {
    param(
        [ValidateSet('Startup', 'CommonStartup')]
        [string]$FolderName
    )

    $path = [Environment]::GetFolderPath($FolderName)
    if ($path) { return $path }

    switch ($FolderName) {
        'Startup' {
            if ($env:APPDATA) {
                return (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup')
            }
        }
        'CommonStartup' {
            if ($env:ProgramData) {
                return (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup')
            }
        }
    }

    return $path
}

function Write-AllStartLog {
    param(
        [pscustomobject]$Context,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'ACTION', 'SKIP', 'VERIFY')]
        [string]$Level,
        [string]$Message,
        $Data
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    Write-Host $line
    if ($Context -and $Context.LogPath) {
        $entry = [ordered]@{
            timestamp = (Get-Date).ToString('o')
            level = $Level
            mode = $Context.Mode
            hostname = $Context.Hostname
            message = $Message
        }
        if ($PSBoundParameters.ContainsKey('Data')) { $entry.data = $Data }
        ($entry | ConvertTo-Json -Depth 12 -Compress) | Add-Content -LiteralPath $Context.LogPath -Encoding UTF8
    }
}

function New-AllStartSnapshot {
    param(
        [pscustomobject]$Context,
        [string]$Reason,
        [switch]$IncludeAudit
    )

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $snapshotDir = Join-Path $Context.SnapshotsDir ("{0}-{1}" -f $stamp, $Reason.ToLowerInvariant())
    New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $snapshotDir 'tasks') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $snapshotDir 'startup-user') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $snapshotDir 'startup-common') -Force | Out-Null

    $registry = @(Get-RunKeySnapshot)
    $startup = @(Copy-StartupFolderSnapshot -SnapshotDir $snapshotDir)
    $tasks = @(Export-AllStartTaskSnapshot -Context $Context -SnapshotDir $snapshotDir -IncludeAudit:$IncludeAudit)
    $appStartupTasks = @(Get-AppStartupTaskSnapshot)

    $manifest = [ordered]@{
        createdAt = (Get-Date).ToString('o')
        reason = $Reason
        script = $__extractedScriptPath
        config = $Context.ConfigPath
        isAdmin = $Context.IsAdmin
        registryRun = $registry
        startupFolders = $startup
        scheduledTasks = $tasks
        appStartupTasks = $appStartupTasks
    }
    $manifestPath = Join-Path $snapshotDir 'manifest.json'
    ($manifest | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    return $snapshotDir
}

function Ensure-AllStartMutationSnapshot {
    param(
        [pscustomobject]$Context,
        [string]$Reason
    )

    if ($Context.DryRun) { return $null }
    if ($Context.SnapshotPath -and (Test-Path -LiteralPath $Context.SnapshotPath)) {
        return $Context.SnapshotPath
    }
    $snapshot = New-AllStartSnapshot -Context $Context -Reason $Reason
    $Context.SnapshotPath = $snapshot
    Write-AllStartLog $Context 'INFO' "Pre-mutation snapshot ready: $snapshot"
    return $snapshot
}

function Get-RunKeySnapshot {
    $paths = @(
        @{ Hive = 'HKCU'; Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' },
        @{ Hive = 'HKLM'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' }
    )
    foreach ($entry in $paths) {
        try {
            $props = Get-ItemProperty -Path $entry.Path -ErrorAction Stop
            foreach ($prop in @($props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' })) {
                [pscustomobject]@{
                    hive = $entry.Hive
                    path = $entry.Path
                    name = $prop.Name
                    value = [string]$prop.Value
                }
            }
        } catch {
            [pscustomobject]@{
                hive = $entry.Hive
                path = $entry.Path
                error = $_.Exception.Message
            }
        }
    }
}

function Copy-StartupFolderSnapshot {
    param([string]$SnapshotDir)

    $folders = @(
        @{ Scope = 'User'; Path = Resolve-AllStartFolderPath -FolderName 'Startup'; CopyDir = Join-Path $SnapshotDir 'startup-user' },
        @{ Scope = 'Common'; Path = Resolve-AllStartFolderPath -FolderName 'CommonStartup'; CopyDir = Join-Path $SnapshotDir 'startup-common' }
    )
    foreach ($folder in $folders) {
        if (-not $folder.Path -or -not (Test-Path -LiteralPath $folder.Path)) {
            [pscustomobject]@{ scope = $folder.Scope; path = $folder.Path; readable = $false }
            continue
        }
        foreach ($item in @(Get-ChildItem -LiteralPath $folder.Path -Force -ErrorAction SilentlyContinue)) {
            $copiedTo = $null
            if (-not $item.PSIsContainer) {
                $copiedTo = Join-Path $folder.CopyDir $item.Name
                Copy-Item -LiteralPath $item.FullName -Destination $copiedTo -Force -ErrorAction SilentlyContinue
            }
            [pscustomobject]@{
                scope = $folder.Scope
                path = $folder.Path
                name = $item.Name
                fullName = $item.FullName
                attributes = [string]$item.Attributes
                length = if ($item.PSIsContainer) { $null } else { $item.Length }
                copiedTo = $copiedTo
            }
        }
    }
}

function Export-AllStartTaskSnapshot {
    param(
        [pscustomobject]$Context,
        [string]$SnapshotDir,
        [switch]$IncludeAudit
    )

    $taskNames = @($Context.Config.Settings.SnapshotTaskNames)
    if ($IncludeAudit) {
        Write-AllStartLog $Context 'INFO' 'Audit snapshot keeps task XML export limited to configured protected/relevant tasks.'
    }

    foreach ($taskName in $taskNames) {
        try {
            $task = Get-ScheduledTaskSafe -TaskName $taskName
            if (-not $task) {
                [pscustomobject]@{ taskName = $taskName; exists = $false }
                continue
            }
            $safeName = ($taskName -replace '[\\/:*?"<>| ]', '_')
            $xmlPath = Join-Path (Join-Path $SnapshotDir 'tasks') "$safeName.xml"
            $xml = Export-ScheduledTask -TaskName $taskName -TaskPath $task.TaskPath -ErrorAction Stop
            $xml | Set-Content -LiteralPath $xmlPath -Encoding UTF8
            [pscustomobject]@{
                taskName = $task.TaskName
                taskPath = $task.TaskPath
                state = [string]$task.State
                xmlPath = $xmlPath
                exists = $true
            }
        } catch {
            [pscustomobject]@{ taskName = $taskName; exists = $null; error = $_.Exception.Message }
        }
    }
}

function Get-ScheduledTaskSafe {
    param([string]$TaskName)

    try {
        Import-Module ScheduledTasks -ErrorAction SilentlyContinue
        return Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Select-Object -First 1
    } catch {
        return $null
    }
}

function Get-ScheduledTaskInfoFast {
    param([string]$TaskName)

    $quotedTaskName = $TaskName.Replace('"', '""')
    $output = & cmd.exe /d /c "schtasks.exe /query /tn ""$quotedTaskName"" /v /fo list 2>nul"
    if ($LASTEXITCODE -ne 0 -or -not $output) { return $null }

    $taskToRun = $null
    $status = $null
    $scheduledState = $null
    foreach ($line in $output) {
        if ($line -match '^Task To Run:\s*(.*)$') { $taskToRun = $Matches[1].Trim() }
        elseif ($line -match '^Status:\s*(.*)$') { $status = $Matches[1].Trim() }
        elseif ($line -match '^Scheduled Task State:\s*(.*)$') { $scheduledState = $Matches[1].Trim() }
    }
    [pscustomobject]@{
        TaskName = $TaskName
        TaskPath = '\'
        State = if ($scheduledState -eq 'Disabled') { 'Disabled' } elseif ($status) { $status } else { $scheduledState }
        ScheduledTaskState = $scheduledState
        Action = $taskToRun
        Exists = $true
    }
}

function Get-AllStartInventory {
    param(
        [pscustomobject]$Context,
        [switch]$IncludeAudit
    )

    [pscustomobject]@{
        registryRun = @(Get-RunKeySnapshot)
        startupFolders = @(Get-StartupFolderInventory)
        scheduledTasks = @(Get-ScheduledTaskInventory -Context $Context -IncludeAudit:$IncludeAudit)
    }
}

function Get-StartupFolderInventory {
    $folders = @(
        @{ Scope = 'User'; Path = Resolve-AllStartFolderPath -FolderName 'Startup' },
        @{ Scope = 'Common'; Path = Resolve-AllStartFolderPath -FolderName 'CommonStartup' }
    )
    foreach ($folder in $folders) {
        if (-not $folder.Path -or -not (Test-Path -LiteralPath $folder.Path)) {
            [pscustomobject]@{ surface = 'StartupFolder'; scope = $folder.Scope; readable = $false; path = $folder.Path }
            continue
        }
        foreach ($item in @(Get-ChildItem -LiteralPath $folder.Path -Force -ErrorAction SilentlyContinue)) {
            $target = $null
            $arguments = $null
            if ($item.Extension -ieq '.lnk') {
                try {
                    $shell = New-Object -ComObject WScript.Shell
                    $shortcut = $shell.CreateShortcut($item.FullName)
                    $target = $shortcut.TargetPath
                    $arguments = $shortcut.Arguments
                } catch {}
            }
            [pscustomobject]@{
                surface = 'StartupFolder'
                scope = $folder.Scope
                name = $item.Name
                baseName = $item.BaseName
                fullName = $item.FullName
                target = $target
                arguments = $arguments
            }
        }
    }
}

function Get-ScheduledTaskInventory {
    param(
        [pscustomobject]$Context,
        [switch]$IncludeAudit
    )

    if ($IncludeAudit) {
        try {
            Import-Module ScheduledTasks -ErrorAction SilentlyContinue
            foreach ($task in @(Get-ScheduledTask | Where-Object { $_.Triggers })) {
                $actions = @($task.Actions | ForEach-Object { (($_.Execute, $_.Arguments) -join ' ').Trim() })
                [pscustomobject]@{
                    surface = 'ScheduledTask'
                    name = $task.TaskName
                    taskPath = $task.TaskPath
                    state = [string]$task.State
                    author = $task.Author
                    actions = $actions -join '; '
                    exists = $true
                }
            }
            return
        } catch {
            Write-AllStartLog $Context 'WARN' "Broad scheduled-task audit failed: $($_.Exception.Message)"
        }
    }
    $names = @($Context.Config.Settings.SnapshotTaskNames)
    foreach ($name in @($names | Where-Object { $_ } | Sort-Object -Unique)) {
        $task = Get-ScheduledTaskSafe -TaskName $name
        if (-not $task) {
            [pscustomobject]@{ surface = 'ScheduledTask'; name = $name; exists = $false }
            continue
        }
        $actions = @($task.Actions | ForEach-Object { (($_.Execute, $_.Arguments) -join ' ').Trim() })
        [pscustomobject]@{
            surface = 'ScheduledTask'
            name = $task.TaskName
            taskPath = $task.TaskPath
            state = [string]$task.State
            author = $task.Author
            actions = $actions -join '; '
            exists = $true
        }
    }
}

function Classify-AllStartInventory {
    param(
        [pscustomobject]$Context,
        [pscustomobject]$Inventory
    )

    $protected = @($Context.Config.ProtectedNames)
    $requiredNames = @(Get-AllStartAllowedNames -Context $Context)
    foreach ($entry in @($Inventory.registryRun)) {
        if ($entry.error) { continue }
        $classification = 'unknown-keep-report'
        if ($requiredNames -contains $entry.name) { $classification = 'required' }
        elseif ($protected -contains $entry.name) { $classification = 'protected-system' }
        elseif (Find-AllStartExactRule -Config $Context.Config -Surface 'RegistryRun' -ExactName $entry.name -RuleSet 'DelayRules') { $classification = 'safe-delay-candidate' }
        elseif (Find-AllStartExactRule -Config $Context.Config -Surface 'RegistryRun' -ExactName $entry.name -RuleSet 'ExplicitDisableRules') { $classification = 'explicit-disable-candidate' }
        [pscustomobject]@{ surface = 'RegistryRun'; name = $entry.name; value = $entry.value; classification = $classification }
    }
    foreach ($entry in @($Inventory.startupFolders)) {
        if (-not $entry.name) { continue }
        $classification = 'unknown-keep-report'
        if ($entry.name -ieq 'desktop.ini') { $classification = 'protected-system' }
        elseif ($entry.baseName -ieq 'current.ahk') { $classification = 'required' }
        elseif ($protected -contains $entry.baseName) { $classification = 'protected-system' }
        elseif (Find-AllStartExactRule -Config $Context.Config -Surface 'StartupFolder' -ExactName $entry.name -RuleSet 'DelayRules') { $classification = 'safe-delay-candidate' }
        elseif (Find-AllStartExactRule -Config $Context.Config -Surface 'StartupFolder' -ExactName $entry.name -RuleSet 'ExplicitDisableRules') { $classification = 'explicit-disable-candidate' }
        [pscustomobject]@{ surface = 'StartupFolder'; name = $entry.name; value = $entry.fullName; classification = $classification }
    }
    foreach ($entry in @($Inventory.scheduledTasks)) {
        if (-not $entry.name) { continue }
        $classification = 'unknown-keep-report'
        if ($requiredNames -contains $entry.name) { $classification = 'required' }
        elseif ($protected -contains $entry.name) { $classification = 'protected-system' }
        elseif (Find-AllStartExactRule -Config $Context.Config -Surface 'ScheduledTask' -ExactName $entry.name -RuleSet 'DelayRules') { $classification = 'safe-delay-candidate' }
        elseif (Find-AllStartExactRule -Config $Context.Config -Surface 'ScheduledTask' -ExactName $entry.name -RuleSet 'ExplicitDisableRules') { $classification = 'explicit-disable-candidate' }
        [pscustomobject]@{ surface = 'ScheduledTask'; name = $entry.name; value = $entry.actions; state = $entry.state; classification = $classification }
    }
}

function Find-AllStartExactRule {
    param(
        [hashtable]$Config,
        [string]$Surface,
        [string]$ExactName,
        [ValidateSet('DelayRules', 'ExplicitDisableRules')]
        [string]$RuleSet
    )

    foreach ($rule in @($Config[$RuleSet])) {
        if ($rule.Surface -eq $Surface -and $rule.ExactName -eq $ExactName) { return $rule }
    }
    return $null
}

function Write-AllStartClassificationSummary {
    param(
        [pscustomobject]$Context,
        [object[]]$Classifications
    )

    $groups = @($Classifications | Group-Object classification | Sort-Object Name)
    foreach ($group in $groups) {
        Write-AllStartLog $Context 'INFO' ("Classification {0}: {1}" -f $group.Name, $group.Count)
    }
    foreach ($unknown in @($Classifications | Where-Object { $_.classification -eq 'unknown-keep-report' })) {
        Write-AllStartLog $Context 'SKIP' ("Unknown startup entry kept: {0} / {1}" -f $unknown.surface, $unknown.name)
    }
}

function Get-AllStartAllowedNames {
    param([pscustomobject]$Context)

    @(
        @($Context.Config.ProtectedNames)
        @($Context.Config.RequiredRegistryRun | ForEach-Object { $_.Name })
        @($Context.Config.RequiredScheduledTasks | ForEach-Object { $_.Name })
    ) | Where-Object { $_ } | Sort-Object -Unique
}

function Resolve-AllStartRunPath {
    param([string]$Hive)

    switch ($Hive) {
        'HKCU' { 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' }
        'HKLM' { 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' }
        default { throw "Unsupported Run hive: $Hive" }
    }
}

function Ensure-RequiredRunEntries {
    param([pscustomobject]$Context)

    foreach ($entry in @($Context.Config.RequiredRegistryRun)) {
        $runPath = Resolve-AllStartRunPath -Hive $entry.Hive
        $current = Get-ItemProperty -Path $runPath -Name $entry.Name -ErrorAction SilentlyContinue
        if ($current -and $current.($entry.Name) -eq $entry.Command) {
            Write-AllStartLog $Context 'VERIFY' "$($entry.Hive) Run $($entry.Name) is already correct"
            continue
        }
        if ($Context.DryRun) {
            Write-AllStartLog $Context 'ACTION' "DryRun: would set $($entry.Hive) Run $($entry.Name) to $($entry.Command)"
            continue
        }
        Ensure-AllStartMutationSnapshot -Context $Context -Reason 'startup-pre-required-run-change' | Out-Null
        Set-ItemProperty -Path $runPath -Name $entry.Name -Value $entry.Command -Force
        Write-AllStartLog $Context 'ACTION' "Set $($entry.Hive) Run $($entry.Name)"
    }
}

function Ensure-RequiredScheduledTasks {
    param([pscustomobject]$Context)

    foreach ($task in @($Context.Config.RequiredScheduledTasks)) {
        Ensure-RequiredScheduledTask -Context $Context -TaskSpec $task
    }
}

function Ensure-RequiredScheduledTask {
    param(
        [pscustomobject]$Context,
        [hashtable]$TaskSpec
    )

    $taskName = $TaskSpec.Name
    $execute = [string]$TaskSpec.Execute
    $arguments = if ($TaskSpec.ContainsKey('Arguments')) { [string]$TaskSpec.Arguments } else { '' }
    if ($execute -and -not (Test-Path -LiteralPath $execute)) {
        Write-AllStartLog $Context 'WARN' "Required task executable missing for $taskName`: $execute"
        return
    }

    $task = Get-ScheduledTaskInfoFast -TaskName $taskName
    $taskActionText = if ($task) { Get-ScheduledTaskActionTextExact -TaskName $taskName } else { $null }
    if (-not $taskActionText -and $task) { $taskActionText = $task.Action }
    $needsRegister = $false
    $reason = $null
    if (-not $task) {
        $needsRegister = $true
        $reason = 'missing'
    } elseif (-not (Test-TaskActionMatches -ActionText $taskActionText -Execute $execute -Arguments $arguments)) {
        $needsRegister = $true
        $reason = 'wrong-action'
    } elseif (Test-RequiredTaskHasDelayOrNoLogonTrigger -TaskName $taskName) {
        $needsRegister = $true
        $reason = 'delayed-or-not-logon'
    }

    if ($needsRegister) {
        if ($Context.DryRun) {
            Write-AllStartLog $Context 'ACTION' "DryRun: would register $taskName at logon with zero delay ($reason)"
            return
        }
        Ensure-AllStartMutationSnapshot -Context $Context -Reason 'startup-pre-required-task-change' | Out-Null
        $action = if ($arguments) {
            New-ScheduledTaskAction -Execute $execute -Argument $arguments
        } else {
            New-ScheduledTaskAction -Execute $execute
        }
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description ([string]$TaskSpec.Description) -Force | Out-Null
        Write-AllStartLog $Context 'ACTION' "Registered $taskName at logon with zero delay ($reason)"
        return
    }

    if ($task.State -eq 'Disabled') {
        if ($Context.DryRun) {
            Write-AllStartLog $Context 'ACTION' "DryRun: would enable scheduled task $taskName"
        } else {
            Ensure-AllStartMutationSnapshot -Context $Context -Reason 'startup-pre-required-task-enable' | Out-Null
            & schtasks.exe /change /tn $taskName /ENABLE | Out-Null
            Write-AllStartLog $Context 'ACTION' "Enabled scheduled task $taskName"
        }
    } else {
        Write-AllStartLog $Context 'VERIFY' "Scheduled task $taskName is enabled, at logon, zero delay"
    }
}

function Get-ScheduledTaskActionTextExact {
    param([string]$TaskName)

    try {
        $task = Get-ScheduledTaskSafe -TaskName $TaskName
        if (-not $task) { return $null }
        return (@($task.Actions | ForEach-Object { (($_.Execute, $_.Arguments) -join ' ').Trim() }) -join '; ')
    } catch {
        return $null
    }
}

function Test-TaskActionMatches {
    param(
        [string]$ActionText,
        [string]$Execute,
        [string]$Arguments
    )

    if (-not $ActionText) { return $false }
    $executeLeaf = Split-Path -Leaf $Execute
    $executeMatches = ($ActionText -match [regex]::Escape($Execute)) -or ($executeLeaf -and $ActionText -match [regex]::Escape($executeLeaf))
    if (-not $executeMatches) { return $false }

    if ($Arguments) {
        $normalizedAction = ($ActionText -replace '\s+', ' ').Trim()
        $normalizedArguments = ($Arguments -replace '\s+', ' ').Trim()
        return ($normalizedAction -match [regex]::Escape($normalizedArguments))
    }
    return $true
}

function Test-RequiredTaskHasDelayOrNoLogonTrigger {
    param([string]$TaskName)

    try {
        $task = Get-ScheduledTaskSafe -TaskName $TaskName
        if (-not $task) { return $true }
        $logonTriggers = @($task.Triggers | Where-Object { $_.CimClass.CimClassName -match 'LogonTrigger' })
        if (@($logonTriggers).Count -eq 0) { return $true }
        foreach ($trigger in $logonTriggers) {
            if ($trigger.Delay -and [string]$trigger.Delay -notin @('', 'PT0S')) { return $true }
        }
        return $false
    } catch {
        return $false
    }
}

function Ensure-PhoneLinkReadiness {
    param([pscustomobject]$Context)

    $required = $Context.Config.RequiredLaunchPoints
    $phoneOk = Test-AppxPackageFamilyInstalled -PackageFamilyName $required.PhoneLinkPackageFamilyName
    $crossDeviceOk = Test-AppxPackageFamilyInstalled -PackageFamilyName $required.CrossDevicePackageFamilyName
    if ($phoneOk) {
        Write-AllStartLog $Context 'VERIFY' "Phone Link package exists: $($required.PhoneLinkPackageFamilyName)"
    } else {
        Write-AllStartLog $Context 'WARN' "Phone Link package missing: $($required.PhoneLinkPackageFamilyName)"
    }
    if ($crossDeviceOk) {
        Write-AllStartLog $Context 'VERIFY' "Cross-device package exists: $($required.CrossDevicePackageFamilyName)"
    } else {
        Write-AllStartLog $Context 'WARN' "Cross-device package missing: $($required.CrossDevicePackageFamilyName)"
    }
}

function Ensure-RequiredAppStartupTasks {
    param([pscustomobject]$Context)

    foreach ($task in @($Context.Config.RequiredAppStartupTasks)) {
        $state = Get-AppStartupTaskState -PackageFamilyName $task.PackageFamilyName -TaskId $task.TaskId
        $stateLabel = Get-AppStartupTaskStateLabel -State $state
        $desiredState = if ($task.ContainsKey('EnabledState')) { [int]$task.EnabledState } else { 2 }
        if ($state -eq $desiredState -or ($desiredState -eq 2 -and $state -eq 4)) {
            Write-AllStartLog $Context 'VERIFY' "Required app startup task ready: $($task.PackageFamilyName) / $($task.TaskId) is $stateLabel"
            continue
        }
        if ($null -eq $state) {
            Write-AllStartLog $Context 'WARN' "Required app startup task missing: $($task.PackageFamilyName) / $($task.TaskId)"
            continue
        }
        if ($Context.DryRun) {
            Write-AllStartLog $Context 'ACTION' "DryRun: would set app startup task $($task.PackageFamilyName) / $($task.TaskId) from $stateLabel to $(Get-AppStartupTaskStateLabel -State $desiredState)"
            continue
        }
        try {
            Ensure-AllStartMutationSnapshot -Context $Context -Reason 'startup-pre-app-startup-enable' | Out-Null
            Set-AppStartupTaskState -PackageFamilyName $task.PackageFamilyName -TaskId $task.TaskId -State $desiredState
            $after = Get-AppStartupTaskState -PackageFamilyName $task.PackageFamilyName -TaskId $task.TaskId
            Write-AllStartLog $Context 'ACTION' "Set app startup task $($task.PackageFamilyName) / $($task.TaskId) to $(Get-AppStartupTaskStateLabel -State $after)"
        } catch {
            Write-AllStartLog $Context 'WARN' "Failed to set app startup task $($task.PackageFamilyName) / $($task.TaskId): $($_.Exception.Message)"
        }
    }
}

function Get-AppStartupTaskState {
    param(
        [string]$PackageFamilyName,
        [string]$TaskId
    )

    if (-not $PackageFamilyName -or -not $TaskId) { return $null }
    $statePath = Get-AppStartupTaskRegistryPath -PackageFamilyName $PackageFamilyName -TaskId $TaskId
    try {
        $item = Get-ItemProperty -Path $statePath -Name State -ErrorAction Stop
        return [int]$item.State
    } catch {
        return $null
    }
}

function Get-AppStartupTaskStateLabel {
    param([Nullable[int]]$State)

    switch ($State) {
        0 { 'Disabled' }
        1 { 'DisabledByUser' }
        2 { 'Enabled' }
        3 { 'DisabledByPolicy' }
        4 { 'EnabledByPolicy' }
        default { 'Unknown' }
    }
}

function Get-AppStartupTaskRegistryPath {
    param(
        [string]$PackageFamilyName,
        [string]$TaskId
    )

    "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$PackageFamilyName\$TaskId"
}

function Set-AppStartupTaskState {
    param(
        [string]$PackageFamilyName,
        [string]$TaskId,
        [int]$State,
        [Nullable[int]]$UserEnabledStartupOnce
    )

    $statePath = Get-AppStartupTaskRegistryPath -PackageFamilyName $PackageFamilyName -TaskId $TaskId
    Set-ItemProperty -Path $statePath -Name State -Value $State -Force -ErrorAction Stop
    if ($PSBoundParameters.ContainsKey('UserEnabledStartupOnce') -and $null -ne $UserEnabledStartupOnce) {
        Set-ItemProperty -Path $statePath -Name UserEnabledStartupOnce -Value $UserEnabledStartupOnce.Value -Force -ErrorAction SilentlyContinue
    }
}

function Get-AllStartAppStartupTaskKey {
    param(
        [string]$PackageFamilyName,
        [string]$TaskId
    )

    ('{0}|{1}' -f ([string]$PackageFamilyName).ToLowerInvariant(), ([string]$TaskId).ToLowerInvariant())
}

function Get-AllStartAllowedAppStartupTaskKeys {
    param([pscustomobject]$Context)

    @($Context.Config.RequiredAppStartupTasks | ForEach-Object {
        Get-AllStartAppStartupTaskKey -PackageFamilyName $_.PackageFamilyName -TaskId $_.TaskId
    }) | Sort-Object -Unique
}

function Get-AppStartupTaskInventory {
    $base = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'
    if (-not (Test-Path -LiteralPath $base)) { return @() }

    foreach ($packageKey in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
        foreach ($taskKey in @(Get-ChildItem -LiteralPath $packageKey.PSPath -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -LiteralPath $taskKey.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $props) { continue }
            $stateProperty = $props.PSObject.Properties['State']
            if ($null -eq $stateProperty) { continue }
            $userEnabledProperty = $props.PSObject.Properties['UserEnabledStartupOnce']
            [pscustomobject]@{
                PackageFamilyName = $packageKey.PSChildName
                TaskId = $taskKey.PSChildName
                State = [int]$stateProperty.Value
                UserEnabledStartupOnce = if ($null -ne $userEnabledProperty) { [int]$userEnabledProperty.Value } else { $null }
                RegistryPath = $taskKey.PSPath
            }
        }
    }
}

function Get-AppStartupTaskSnapshot {
    @(Get-AppStartupTaskInventory | ForEach-Object {
        [pscustomobject]@{
            packageFamilyName = $_.PackageFamilyName
            taskId = $_.TaskId
            state = $_.State
            userEnabledStartupOnce = $_.UserEnabledStartupOnce
        }
    })
}

function Test-AppxPackageFamilyInstalled {
    param([string]$PackageFamilyName)

    if (-not $PackageFamilyName) { return $false }
    try {
        $script = "Get-AppxPackage | Where-Object { `$_.PackageFamilyName -eq '$PackageFamilyName' } | Select-Object -First 1 -ExpandProperty PackageFamilyName"
        $result = & powershell.exe -NoProfile -Command $script 2>$null
        return ($result -contains $PackageFamilyName)
    } catch {
        return $false
    }
}

function Ensure-CurrentAhkStartup {
    param([pscustomobject]$Context)

    $ahkPath = $Context.Config.RequiredLaunchPoints.AhkScript
    $ahkName = 'current.ahk'
    $runPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    if (-not (Test-Path -LiteralPath $ahkPath)) {
        Write-AllStartLog $Context 'WARN' "Required AutoHotkey script is missing: $ahkPath"
        return
    }

    $desiredRunValue = "`"$ahkPath`""
    $currentRun = Get-ItemProperty -Path $runPath -Name $ahkName -ErrorAction SilentlyContinue
    if (-not $currentRun -or $currentRun.$ahkName -ne $desiredRunValue) {
        if ($Context.DryRun) {
            Write-AllStartLog $Context 'ACTION' "DryRun: would set HKCU Run $ahkName to $desiredRunValue"
        } else {
            Ensure-AllStartMutationSnapshot -Context $Context -Reason 'startup-pre-registry-run-change' | Out-Null
            Set-ItemProperty -Path $runPath -Name $ahkName -Value $desiredRunValue -Force
            Write-AllStartLog $Context 'ACTION' "Set HKCU Run $ahkName"
        }
    } else {
        Write-AllStartLog $Context 'VERIFY' "HKCU Run current.ahk is already correct"
    }

    Ensure-CurrentAhkShortcut -Context $Context -AhkPath $ahkPath
    Ensure-CurrentAhkTask -Context $Context -AhkPath $ahkPath
}

function Ensure-CurrentAhkShortcut {
    param(
        [pscustomobject]$Context,
        [string]$AhkPath
    )

    $startupFolder = Resolve-AllStartFolderPath -FolderName 'Startup'
    $shortcutPath = Join-Path $startupFolder 'current.ahk.lnk'
    $needsWrite = $true
    if (Test-Path -LiteralPath $shortcutPath) {
        try {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $needle = [regex]::Escape($AhkPath)
            if (($shortcut.TargetPath -eq $AhkPath) -or ($shortcut.Arguments -match $needle)) {
                $needsWrite = $false
            }
        } catch {}
    }
    if (-not $needsWrite) {
        Write-AllStartLog $Context 'VERIFY' 'Startup folder current.ahk shortcut is already valid'
        return
    }
    if ($Context.DryRun) {
        Write-AllStartLog $Context 'ACTION' "DryRun: would create/update shortcut $shortcutPath"
        return
    }

    Ensure-AllStartMutationSnapshot -Context $Context -Reason 'startup-pre-shortcut-change' | Out-Null
    if (-not (Test-Path -LiteralPath $startupFolder)) {
        New-Item -ItemType Directory -Path $startupFolder -Force | Out-Null
    }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $autoHotkeyExe = $Context.Config.RequiredLaunchPoints.AutoHotkeyExe
    if ($autoHotkeyExe -and (Test-Path -LiteralPath $autoHotkeyExe)) {
        $shortcut.TargetPath = $autoHotkeyExe
        $shortcut.Arguments = "`"$AhkPath`""
    } else {
        $shortcut.TargetPath = $AhkPath
        $shortcut.Arguments = ''
    }
    $shortcut.WorkingDirectory = Split-Path -Parent $AhkPath
    $shortcut.Save()
    Write-AllStartLog $Context 'ACTION' "Created/updated startup shortcut $shortcutPath"
}

function Ensure-CurrentAhkTask {
    param(
        [pscustomobject]$Context,
        [string]$AhkPath
    )

    $taskName = 'Autorun_current_ahk'
    $task = Get-ScheduledTaskInfoFast -TaskName $taskName
    if (-not $task) {
        if ($Context.DryRun) {
            Write-AllStartLog $Context 'ACTION' "DryRun: would create scheduled task $taskName"
            return
        }
        Ensure-AllStartMutationSnapshot -Context $Context -Reason 'startup-pre-task-change' | Out-Null
        $action = New-ScheduledTaskAction -Execute $AhkPath
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
        Write-AllStartLog $Context 'ACTION' "Created scheduled task $taskName"
        return
    }
    if ($task.State -eq 'Disabled') {
        if ($Context.DryRun) {
            Write-AllStartLog $Context 'ACTION' "DryRun: would enable scheduled task $taskName"
        } else {
            Ensure-AllStartMutationSnapshot -Context $Context -Reason 'startup-pre-task-change' | Out-Null
            & schtasks.exe /change /tn $taskName /ENABLE | Out-Null
            Write-AllStartLog $Context 'ACTION' "Enabled scheduled task $taskName"
        }
    } else {
        Write-AllStartLog $Context 'VERIFY' "Scheduled task $taskName exists and is $($task.State)"
    }
}

function Ensure-ClawdBotStartup {
    param(
        [pscustomobject]$Context,
        [switch]$AllowRepair
    )

    $required = $Context.Config.RequiredLaunchPoints
    foreach ($pathKey in @('ClawdBotTrayVbs', 'ClawdBotManagerExe', 'ClawdBotRestartScript')) {
        $path = $required[$pathKey]
        if (-not (Test-Path -LiteralPath $path)) {
            Write-AllStartLog $Context 'WARN' "Missing ClawdBot path $pathKey`: $path"
            return
        }
    }

    Ensure-ClawdBotDmScope -Context $Context
    Ensure-ClawdBotTask -Context $Context -AllowRepair:$AllowRepair
    Test-ClawdBotReadinessBounded -Context $Context
}

function Ensure-ClawdBotDmScope {
    param([pscustomobject]$Context)

    $configPath = $Context.Config.RequiredLaunchPoints.ClawdBotConfigPath
    $desired = $Context.Config.RequiredLaunchPoints.TelegramDmScope
    if (-not (Test-Path -LiteralPath $configPath)) {
        Write-AllStartLog $Context 'WARN' "ClawdBot config missing: $configPath"
        return
    }
    try {
        $raw = Get-Content -LiteralPath $configPath -Raw
        $json = $raw | ConvertFrom-Json
        $current = $null
        if ($json.session -and $json.session.PSObject.Properties['dmScope']) { $current = $json.session.dmScope }
        if ($current -eq $desired) {
            Write-AllStartLog $Context 'VERIFY' "Telegram dmScope already $desired"
        } elseif ($Context.DryRun) {
            Write-AllStartLog $Context 'ACTION' "DryRun: would set Telegram dmScope to $desired"
        } else {
            Ensure-AllStartMutationSnapshot -Context $Context -Reason 'startup-pre-openclaw-config-change' | Out-Null
            $backupPath = Join-Path $Context.SnapshotsDir ("openclaw-json-before-dmscope-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
            Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
            if ($raw -match '"dmScope"\s*:\s*"[^"]*"') {
                $updated = [regex]::Replace($raw, '"dmScope"\s*:\s*"[^"]*"', ('"dmScope": "{0}"' -f $desired), 1)
                Set-Content -LiteralPath $configPath -Value $updated -Encoding UTF8
            } else {
                if ($null -eq $json.session) { $json | Add-Member -MemberType NoteProperty -Name session -Value ([pscustomobject]@{}) -Force }
                $json.session | Add-Member -MemberType NoteProperty -Name dmScope -Value $desired -Force
                $json | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $configPath -Encoding UTF8
            }
            Write-AllStartLog $Context 'ACTION' "Set Telegram dmScope to $desired; backup: $backupPath"
        }
        $accountCount = 0
        $bindingCount = 0
        if ($json.channels -and $json.channels.telegram -and $json.channels.telegram.accounts) {
            $accountCount = @($json.channels.telegram.accounts.PSObject.Properties.Name).Count
        }
        if ($json.bindings) {
            $bindingCount = @($json.bindings | Where-Object { $_.match -and $_.match.channel -eq 'telegram' }).Count
        }
        Write-AllStartLog $Context 'VERIFY' "Telegram mapping: $accountCount accounts / $bindingCount bindings"
    } catch {
        Write-AllStartLog $Context 'WARN' "Failed to inspect ClawdBot config: $($_.Exception.Message)"
    }
}

function Ensure-ClawdBotTask {
    param(
        [pscustomobject]$Context,
        [switch]$AllowRepair
    )

    $taskName = 'ClawdBotTray'
    $vbs = $Context.Config.RequiredLaunchPoints.ClawdBotTrayVbs
    $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $task = Get-ScheduledTaskInfoFast -TaskName $taskName
    if (-not $task) {
        if (-not $AllowRepair) {
            Write-AllStartLog $Context 'WARN' "ClawdBotTray task missing; repair not allowed in this mode"
            return
        }
        if ($Context.DryRun) {
            Write-AllStartLog $Context 'ACTION' "DryRun: would create $taskName with hidden VBS launcher"
            return
        }
        Ensure-AllStartMutationSnapshot -Context $Context -Reason 'startup-pre-clawdbot-task-change' | Out-Null
        $action = New-ScheduledTaskAction -Execute $wscript -Argument ("//B //Nologo `"$vbs`"")
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
        Write-AllStartLog $Context 'ACTION' "Created ClawdBotTray scheduled task"
        return
    }
    $actions = $task.Action
    if ($actions -notmatch [regex]::Escape($vbs) -or $actions -notmatch 'wscript') {
        Write-AllStartLog $Context 'WARN' "ClawdBotTray task exists but target was not the expected hidden VBS launcher: $actions"
        return
    }
    if ($task.State -eq 'Disabled') {
        if ($Context.DryRun) {
            Write-AllStartLog $Context 'ACTION' "DryRun: would enable ClawdBotTray"
        } else {
            Ensure-AllStartMutationSnapshot -Context $Context -Reason 'startup-pre-clawdbot-task-change' | Out-Null
            & schtasks.exe /change /tn $taskName /ENABLE | Out-Null
            Write-AllStartLog $Context 'ACTION' 'Enabled ClawdBotTray task'
        }
    } else {
        Write-AllStartLog $Context 'VERIFY' 'ClawdBotTray task targets the hidden VBS launcher and is enabled'
    }
}

function Test-ClawdBotReadinessBounded {
    param([pscustomobject]$Context)

    $script = $Context.Config.RequiredLaunchPoints.ClawdBotRestartScript
    if ($Context.Mode -eq 'Startup' -and (Test-OpenClawGatewayPort -TimeoutMs 750)) {
        Write-AllStartLog $Context 'VERIFY' 'OpenClaw gateway port 18789 is listening; full readiness remains available in Verify mode'
        return
    }

    $timeout = [int]$Context.Config.Settings.StartupOpenClawCheckTimeoutSec
    if ($Context.Mode -in @('Verify', 'Audit')) { $timeout = [int]$Context.Config.Settings.VerifyOpenClawCheckTimeoutSec }
    $job = $null
    try {
        $job = Start-Job -ScriptBlock {
            param($RestartScript)
            & $RestartScript -CheckOnly -Quiet
        } -ArgumentList $script
        $completed = Wait-Job -Job $job -Timeout $timeout
        if (-not $completed) {
            Write-AllStartLog $Context 'WARN' "ClawdBot readiness check timed out after ${timeout}s; startup continues"
            return
        }
        $result = Receive-Job -Job $job
        if ($result -contains $true) {
            Write-AllStartLog $Context 'VERIFY' 'ClawdBot readiness check passed'
        } else {
            Write-AllStartLog $Context 'WARN' 'ClawdBot readiness check did not confirm healthy gateway'
        }
    } catch {
        Write-AllStartLog $Context 'WARN' "ClawdBot readiness check failed: $($_.Exception.Message)"
    } finally {
        if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    }
}

function Test-OpenClawGatewayPort {
    param(
        [int]$TimeoutMs = 750
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect('127.0.0.1', 18789, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Invoke-ExplicitStartupRules {
    param(
        [pscustomobject]$Context,
        [object[]]$Classifications = @()
    )

    if (@($Context.Config.DelayRules).Count -eq 0 -and @($Context.Config.ExplicitDisableRules).Count -eq 0) {
        Write-AllStartLog $Context 'VERIFY' 'No extra delay/disable rules configured; required startup allowlist is enforced separately'
        return
    }
    if (-not $Classifications -or @($Classifications).Count -eq 0) {
        $inventory = Get-AllStartInventory -Context $Context
        $Classifications = Classify-AllStartInventory -Context $Context -Inventory $inventory
    }
    $disableCandidates = @($Classifications | Where-Object { $_.classification -eq 'explicit-disable-candidate' })
    $delayCandidates = @($Classifications | Where-Object { $_.classification -eq 'safe-delay-candidate' })
    foreach ($entry in $delayCandidates) {
        Write-AllStartLog $Context 'SKIP' "Delay rule is configured but automatic delay migration is report-only in this safe build: $($entry.surface) / $($entry.name)"
    }
    foreach ($entry in $disableCandidates) {
        Write-AllStartLog $Context 'SKIP' "Disable rule is configured but automatic disable is report-only in this safe build: $($entry.surface) / $($entry.name)"
    }
}

function Invoke-StartupAllowlistEnforcement {
    param([pscustomobject]$Context)

    $allowed = @(Get-AllStartAllowedNames -Context $Context)
    Disable-UnauthorizedRunEntries -Context $Context -AllowedNames $allowed
    Quarantine-UnauthorizedStartupFolderEntries -Context $Context -AllowedNames $allowed
    Disable-UnauthorizedRootLogonTasks -Context $Context -AllowedNames $allowed
    Disable-UnauthorizedAppStartupTasks -Context $Context
}

function Disable-UnauthorizedRunEntries {
    param(
        [pscustomobject]$Context,
        [string[]]$AllowedNames
    )

    foreach ($runPath in @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
        $props = Get-ItemProperty -Path $runPath -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($prop in @($props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' })) {
            if ($AllowedNames -contains $prop.Name) { continue }
            if ($Context.DryRun) {
                Write-AllStartLog $Context 'ACTION' "DryRun: would remove unauthorized Run entry $runPath / $($prop.Name)"
                continue
            }
            try {
                Ensure-AllStartMutationSnapshot -Context $Context -Reason 'startup-pre-unauthorized-run-disable' | Out-Null
                Remove-ItemProperty -Path $runPath -Name $prop.Name -Force -ErrorAction Stop
                Write-AllStartLog $Context 'ACTION' "Removed unauthorized Run entry $runPath / $($prop.Name)"
            } catch {
                Write-AllStartLog $Context 'WARN' "Failed to remove unauthorized Run entry $runPath / $($prop.Name): $($_.Exception.Message)"
            }
        }
    }
}

function Quarantine-UnauthorizedStartupFolderEntries {
    param(
        [pscustomobject]$Context,
        [string[]]$AllowedNames
    )

    $folders = @(
        (Resolve-AllStartFolderPath -FolderName 'Startup')
        (Resolve-AllStartFolderPath -FolderName 'CommonStartup')
    )
    foreach ($folder in $folders) {
        if (-not $folder -or -not (Test-Path -LiteralPath $folder)) { continue }
        foreach ($item in @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue)) {
            if ($item.PSIsContainer) { continue }
            if ($item.Name -ieq 'desktop.ini') { continue }
            if (($AllowedNames -contains $item.BaseName) -or ($AllowedNames -contains $item.Name)) { continue }
            if ($Context.DryRun) {
                Write-AllStartLog $Context 'ACTION' "DryRun: would quarantine startup-folder entry $($item.FullName)"
                continue
            }
            try {
                Ensure-AllStartMutationSnapshot -Context $Context -Reason 'startup-pre-folder-quarantine' | Out-Null
                $quarantineDir = New-AllStartQuarantineDir -Context $Context -Surface 'startup-folder'
                $destination = Join-Path $quarantineDir $item.Name
                Move-Item -LiteralPath $item.FullName -Destination $destination -Force -ErrorAction Stop
                Write-AllStartLog $Context 'ACTION' "Quarantined startup-folder entry $($item.FullName) -> $destination"
            } catch {
                Write-AllStartLog $Context 'WARN' "Failed to quarantine startup-folder entry $($item.FullName): $($_.Exception.Message)"
            }
        }
    }
}

function Disable-UnauthorizedRootLogonTasks {
    param(
        [pscustomobject]$Context,
        [string[]]$AllowedNames
    )

    try {
        Import-Module ScheduledTasks -ErrorAction SilentlyContinue
        $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
            $_.TaskPath -eq '\' -and
            $_.State -ne 'Disabled' -and
            $_.Triggers -and
            @($_.Triggers | Where-Object { $_.CimClass.CimClassName -match 'LogonTrigger' }).Count -gt 0
        })
    } catch {
        Write-AllStartLog $Context 'WARN' "Could not enumerate root logon scheduled tasks for allowlist enforcement: $($_.Exception.Message)"
        return
    }

    foreach ($task in $tasks) {
        if ($AllowedNames -contains $task.TaskName) { continue }
        if ($Context.DryRun) {
            Write-AllStartLog $Context 'ACTION' "DryRun: would disable unauthorized root logon task $($task.TaskName)"
            continue
        }
        try {
            Ensure-AllStartMutationSnapshot -Context $Context -Reason 'startup-pre-unauthorized-task-disable' | Out-Null
            Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop | Out-Null
            Write-AllStartLog $Context 'ACTION' "Disabled unauthorized root logon task $($task.TaskName)"
        } catch {
            Write-AllStartLog $Context 'WARN' "Failed to disable unauthorized root logon task $($task.TaskName): $($_.Exception.Message)"
        }
    }
}

function Disable-UnauthorizedAppStartupTasks {
    param([pscustomobject]$Context)

    $allowedKeys = @(Get-AllStartAllowedAppStartupTaskKeys -Context $Context)
    foreach ($task in @(Get-AppStartupTaskInventory)) {
        $taskKey = Get-AllStartAppStartupTaskKey -PackageFamilyName $task.PackageFamilyName -TaskId $task.TaskId
        if ($allowedKeys -contains $taskKey) { continue }
        if ($task.State -notin @(2, 4)) { continue }
        if ($Context.DryRun) {
            Write-AllStartLog $Context 'ACTION' "DryRun: would disable unauthorized app startup task $($task.PackageFamilyName) / $($task.TaskId)"
            continue
        }
        try {
            Ensure-AllStartMutationSnapshot -Context $Context -Reason 'startup-pre-app-startup-disable' | Out-Null
            Set-AppStartupTaskState -PackageFamilyName $task.PackageFamilyName -TaskId $task.TaskId -State 1 -UserEnabledStartupOnce 0
            $after = Get-AppStartupTaskState -PackageFamilyName $task.PackageFamilyName -TaskId $task.TaskId
            Write-AllStartLog $Context 'ACTION' "Disabled unauthorized app startup task $($task.PackageFamilyName) / $($task.TaskId) -> $(Get-AppStartupTaskStateLabel -State $after)"
        } catch {
            Write-AllStartLog $Context 'WARN' "Failed to disable unauthorized app startup task $($task.PackageFamilyName) / $($task.TaskId): $($_.Exception.Message)"
        }
    }
}

function New-AllStartQuarantineDir {
    param(
        [pscustomobject]$Context,
        [string]$Surface
    )

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $Context.QuarantineDir "$stamp-$Surface"
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Test-AllStartProtectedLaunchers {
    param([pscustomobject]$Context)

    $required = $Context.Config.RequiredLaunchPoints
    foreach ($pathKey in @('AhkScript', 'FullScreenSnipExe', 'OpenSpeedyExe', 'OpenSpeedyVbs', 'MurmureExe', 'MurmureVbs', 'ClawdBotTrayVbs', 'ClawdBotManagerExe', 'ClawdBotConfigPath', 'ClawdBotRestartScript')) {
        $path = $required[$pathKey]
        if (Test-Path -LiteralPath $path) {
            Write-AllStartLog $Context 'VERIFY' "$pathKey exists: $path"
        } else {
            Write-AllStartLog $Context 'WARN' "$pathKey missing: $path"
        }
    }
    foreach ($entry in @($Context.Config.RequiredRegistryRun)) {
        $runPath = Resolve-AllStartRunPath -Hive $entry.Hive
        $run = Get-ItemProperty -Path $runPath -Name $entry.Name -ErrorAction SilentlyContinue
        if ($run -and $run.($entry.Name) -eq $entry.Command) {
            Write-AllStartLog $Context 'VERIFY' "$($entry.Hive) Run $($entry.Name) exists and is correct"
        } else {
            Write-AllStartLog $Context 'WARN' "$($entry.Hive) Run $($entry.Name) missing or wrong"
        }
    }
    foreach ($taskName in @($Context.Config.RequiredScheduledTasks | ForEach-Object { $_.Name })) {
        $task = Get-ScheduledTaskSafe -TaskName $taskName
        if ($task -and $task.State -ne 'Disabled') {
            Write-AllStartLog $Context 'VERIFY' "$taskName exists and is $($task.State)"
        } else {
            Write-AllStartLog $Context 'WARN' "$taskName missing or disabled"
        }
    }
    Ensure-PhoneLinkReadiness -Context $Context
    foreach ($task in @($Context.Config.RequiredAppStartupTasks)) {
        $state = Get-AppStartupTaskState -PackageFamilyName $task.PackageFamilyName -TaskId $task.TaskId
        $label = Get-AppStartupTaskStateLabel -State $state
        if ($state -in @(2, 4)) {
            Write-AllStartLog $Context 'VERIFY' "Required app startup task enabled: $($task.PackageFamilyName) / $($task.TaskId) is $label"
        } else {
            Write-AllStartLog $Context 'WARN' "Required app startup task not enabled: $($task.PackageFamilyName) / $($task.TaskId) is $label"
        }
    }
    Test-StartupResidue -Context $Context -DisallowedRunNames @('current.ahk', 'Phone', 'SecurityHealth', 'RtkAudUService') -DisallowedStartupNames @('current.ahk.lnk') -DisallowedTaskNames @()
    Test-ClawdBotReadinessBounded -Context $Context
}

function Test-StartupResidue {
    param(
        [pscustomobject]$Context,
        [string[]]$DisallowedRunNames,
        [string[]]$DisallowedStartupNames,
        [string[]]$DisallowedTaskNames
    )

    foreach ($runPath in @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
        foreach ($name in @($DisallowedRunNames | Where-Object { $_ })) {
            $entry = Get-ItemProperty -Path $runPath -Name $name -ErrorAction SilentlyContinue
            if ($entry) {
                Write-AllStartLog $Context 'WARN' "Unexpected legacy Run entry still present: $runPath / $name"
            } else {
                Write-AllStartLog $Context 'VERIFY' "Legacy Run entry absent: $runPath / $name"
            }
        }
    }

    foreach ($folderName in @('Startup', 'CommonStartup')) {
        $folder = Resolve-AllStartFolderPath -FolderName $folderName
        if (-not $folder -or -not (Test-Path -LiteralPath $folder)) { continue }
        foreach ($name in @($DisallowedStartupNames | Where-Object { $_ })) {
            $path = Join-Path $folder $name
            if (Test-Path -LiteralPath $path) {
                Write-AllStartLog $Context 'WARN' "Unexpected startup-folder entry still present: $path"
            } else {
                Write-AllStartLog $Context 'VERIFY' "Legacy startup-folder entry absent: $path"
            }
        }
        foreach ($item in @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue)) {
            if ($item.PSIsContainer -or $item.Name -ieq 'desktop.ini') { continue }
            $allowed = Get-AllStartAllowedNames -Context $Context
            if (($allowed -contains $item.Name) -or ($allowed -contains $item.BaseName)) { continue }
            Write-AllStartLog $Context 'WARN' "Unexpected startup-folder entry still present: $($item.FullName)"
        }
    }

    foreach ($name in @($DisallowedTaskNames | Where-Object { $_ })) {
        $task = Get-ScheduledTaskInfoFast -TaskName $name
        if ($task -and $task.State -ne 'Disabled') {
            Write-AllStartLog $Context 'WARN' "Unexpected scheduled task still enabled: $name"
        } else {
            Write-AllStartLog $Context 'VERIFY' "Legacy scheduled task not enabled: $name"
        }
    }

    $allowedAppStartupKeys = @(Get-AllStartAllowedAppStartupTaskKeys -Context $Context)
    foreach ($task in @(Get-AppStartupTaskInventory)) {
        $taskKey = Get-AllStartAppStartupTaskKey -PackageFamilyName $task.PackageFamilyName -TaskId $task.TaskId
        if ($allowedAppStartupKeys -contains $taskKey) { continue }
        if ($task.State -in @(2, 4)) {
            Write-AllStartLog $Context 'WARN' "Unexpected app startup task still enabled: $($task.PackageFamilyName) / $($task.TaskId)"
        }
    }
}

function Invoke-AllStartRestore {
    param(
        [pscustomobject]$Context,
        [string]$SnapshotPath
    )

    if (-not $SnapshotPath) {
        $latest = Get-ChildItem -LiteralPath $Context.SnapshotsDir -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $SnapshotPath = $latest.FullName }
    }
    if (-not $SnapshotPath -or -not (Test-Path -LiteralPath $SnapshotPath)) {
        throw "Snapshot not found. Provide -SnapshotPath or create one with -Mode Audit -DryRun."
    }
    $manifestPath = Join-Path $SnapshotPath 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Snapshot manifest missing: $manifestPath" }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

    Write-AllStartLog $Context 'INFO' "Restore source: $SnapshotPath"
    if (-not $Context.DryRun) {
        Ensure-AllStartMutationSnapshot -Context $Context -Reason 'pre-restore-current-state' | Out-Null
    }
    foreach ($reg in @($manifest.registryRun | Where-Object { $_.name })) {
        if ($Context.DryRun) {
            Write-AllStartLog $Context 'ACTION' "DryRun: would restore registry $($reg.path) / $($reg.name)"
        } else {
            Set-ItemProperty -Path $reg.path -Name $reg.name -Value $reg.value -Force
            Write-AllStartLog $Context 'ACTION' "Restored registry $($reg.path) / $($reg.name)"
        }
    }
    foreach ($file in @($manifest.startupFolders | Where-Object { $_.copiedTo -and $_.fullName })) {
        if ($Context.DryRun) {
            Write-AllStartLog $Context 'ACTION' "DryRun: would restore startup file $($file.fullName)"
        } else {
            Copy-Item -LiteralPath $file.copiedTo -Destination $file.fullName -Force
            Write-AllStartLog $Context 'ACTION' "Restored startup file $($file.fullName)"
        }
    }
    foreach ($task in @($manifest.scheduledTasks | Where-Object { $_.exists -eq $true -and $_.xmlPath })) {
        if ($Context.DryRun) {
            Write-AllStartLog $Context 'ACTION' "DryRun: would restore scheduled task $($task.taskName) from $($task.xmlPath)"
        } else {
            $xml = Get-Content -LiteralPath $task.xmlPath -Raw
            Register-ScheduledTask -TaskName $task.taskName -TaskPath $task.taskPath -Xml $xml -Force | Out-Null
            Write-AllStartLog $Context 'ACTION' "Restored scheduled task $($task.taskName)"
        }
    }
    foreach ($task in @($manifest.appStartupTasks | Where-Object { $_.packageFamilyName -and $_.taskId })) {
        if ($Context.DryRun) {
            Write-AllStartLog $Context 'ACTION' "DryRun: would restore app startup task $($task.packageFamilyName) / $($task.taskId)"
        } else {
            Set-AppStartupTaskState -PackageFamilyName $task.packageFamilyName -TaskId $task.taskId -State ([int]$task.state) -UserEnabledStartupOnce ([Nullable[int]]$task.userEnabledStartupOnce)
            Write-AllStartLog $Context 'ACTION' "Restored app startup task $($task.packageFamilyName) / $($task.taskId)"
        }
    }
}

& $__extractedFunctionName @__extractedArgs
