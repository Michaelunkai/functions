[CmdletBinding()]
param(
    [ValidateSet('Startup', 'Verify')]
    [string]$Mode = 'Startup',
    [switch]$DryRun,
    [switch]$SelfTest
)

# Safe startup/bootstrap optimizer for the non-agent startup profile.
# Extracted from C:\users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1.
$__extractedFunctionName = 'allstart2'
$__extractedScriptPath = $PSCommandPath
if (-not $__extractedScriptPath) { $__extractedScriptPath = $MyInvocation.MyCommand.Path }
$__extractedArgs = @($args)
$__customConfigPath = Join-Path (Split-Path -Parent $__extractedScriptPath) 'allstart2.custom.psd1'

if ($SelfTest -or ($__extractedArgs -contains '-SelfTest')) {
    [pscustomobject]@{
        Script = $__extractedScriptPath
        Exists = (Test-Path -LiteralPath $__extractedScriptPath)
        Function = $__extractedFunctionName
        Mode = 'SelfTest'
        CustomConfig = $__customConfigPath
        CustomConfigExists = (Test-Path -LiteralPath $__customConfigPath)
    }
    return
}

function allstart2 {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [ValidateSet('Startup', 'Verify')]
        [string]$Mode = 'Startup',

        [switch]$DryRun
    )

    Invoke-AllStartTwoMain -Mode $Mode -DryRun:$DryRun
}

function Invoke-AllStartTwoMain {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [ValidateSet('Startup', 'Verify')]
        [string]$Mode,
        [switch]$DryRun
    )

    $started = Get-Date
    $context = New-AllStartTwoContext -Mode $Mode -DryRun:$DryRun
    try {
        Write-AllStartTwoLog $context 'INFO' "allstart2 mode started: $Mode"
        Write-AllStartTwoLog $context 'INFO' "Admin: $($context.IsAdmin); DryRun: $($context.DryRun); PowerShell: $($PSVersionTable.PSVersion)"

        if ($Mode -eq 'Startup') {
            Ensure-AllStartTwoRunEntries -Context $context
            Ensure-AllStartTwoScheduledTasks -Context $context
            Ensure-AllStartTwoPhoneReadiness -Context $context
            Ensure-AllStartTwoRequiredAppStartupTasks -Context $context
            Invoke-AllStartTwoAllowlistEnforcement -Context $context
        } else {
            Test-AllStartTwoRequiredStartup -Context $context
        }

        $elapsed = [int]((Get-Date) - $started).TotalMilliseconds
        Write-AllStartTwoLog $context 'INFO' "allstart2 mode completed in ${elapsed}ms"
    } catch {
        Write-AllStartTwoLog $context 'ERROR' "allstart2 failed: $($_.Exception.Message)"
        throw
    }
}

function New-AllStartTwoContext {
    param(
        [string]$Mode,
        [switch]$DryRun
    )

    $root = Split-Path -Parent $__extractedScriptPath
    $logsDir = Join-Path $root 'logs'
    $snapshotsDir = Join-Path $root 'snapshots'
    $quarantineDir = Join-Path $root 'quarantine'
    foreach ($dir in @($logsDir, $snapshotsDir, $quarantineDir)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $logPath = Join-Path $logsDir ("allstart2-{0}-latest.jsonl" -f $Mode.ToLowerInvariant())
    Set-Content -LiteralPath $logPath -Value '' -Encoding UTF8

    $context = [pscustomobject]@{
        Root = $root
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
        RequiredPaths = [ordered]@{
            AhkScript = 'F:\study\Platforms\windows\autohotkey\mymainahk\current.ahk'
            AutoHotkeyExe = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
            FullScreenSnipExe = 'F:\study\Platforms\windows\snipping\SnipToClipBoard\FullScreenSnip.exe'
            OpenSpeedyExe = 'F:\backup\windowsapps\installed\OpenSpeedy\Speedy.exe'
            OpenSpeedyVbs = 'F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\allstart2-silent-launchers-20260604\openspeedy-silent\openspeedy-silent.vbs'
            MurmureExe = 'C:\Program Files\murmure\murmure.exe'
            MurmureVbs = 'F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\allstart2-silent-launchers-20260604\murmure-silent\murmure-silent.vbs'
            PhoneLinkPackageFamilyName = 'Microsoft.YourPhone_8wekyb3d8bbwe'
            PhoneLinkStartupTaskId = 'YourPhone.Start'
            CrossDevicePackageFamilyName = 'MicrosoftWindows.CrossDevice_cw5n1h2txyewy'
        }
        RequiredRegistryRun = @(
            @{ Name = 'FullScreenSnip'; Command = '"F:\study\Platforms\windows\snipping\SnipToClipBoard\FullScreenSnip.exe"'; Hive = 'HKCU' }
        )
        RequiredScheduledTasks = @(
            @{ Name = 'Autorun_current_ahk'; Execute = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'; Arguments = '"F:\study\Platforms\windows\autohotkey\mymainahk\current.ahk"'; Description = 'current.ahk hidden launcher at logon' },
            @{ Name = 'OpenSpeedy_Tray'; Execute = 'C:\Windows\System32\wscript.exe'; Arguments = '"F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\allstart2-silent-launchers-20260604\openspeedy-silent\openspeedy-silent.vbs"'; Description = 'OpenSpeedy tray hidden launcher at logon' },
            @{ Name = 'Murmure_Tray'; Execute = 'C:\Windows\System32\wscript.exe'; Arguments = '"F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\allstart2-silent-launchers-20260604\murmure-silent\murmure-silent.vbs"'; Description = 'Murmure tray launcher at logon' }
        )
        RequiredAppStartupTasks = @(
            @{ Name = 'PhoneLinkNative'; PackageFamilyName = 'Microsoft.YourPhone_8wekyb3d8bbwe'; TaskId = 'YourPhone.Start'; EnabledState = 2 },
            @{ Name = 'CrossDeviceNative'; PackageFamilyName = 'MicrosoftWindows.CrossDevice_cw5n1h2txyewy'; TaskId = 'CrossDevice.Start'; EnabledState = 2 }
        )
        AllowedNames = @(
            'FullScreenSnip',
            'Autorun_current_ahk',
            'OpenSpeedy_Tray',
            'Murmure_Tray',
            'Hermes Quiet All Five Sync At Logon',
            'Hermes Quiet Native Fallback Manager'
        )
    }
    Merge-AllStartTwoCustomScheduledTasks -Context $context
    return $context
}

function Write-AllStartTwoLog {
    param(
        [pscustomobject]$Context,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'ACTION', 'VERIFY')]
        [string]$Level,
        [string]$Message
    )

    Write-Host ('[{0}] [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message)
    if ($Context -and $Context.LogPath) {
        [ordered]@{
            timestamp = (Get-Date).ToString('o')
            level = $Level
            mode = $Context.Mode
            hostname = $Context.Hostname
            message = $Message
        } | ConvertTo-Json -Depth 8 -Compress | Add-Content -LiteralPath $Context.LogPath -Encoding UTF8
    }
}

function Ensure-AllStartTwoMutationSnapshot {
    param(
        [pscustomobject]$Context,
        [string]$Reason
    )

    if ($Context.DryRun) { return $null }
    if ($Context.SnapshotPath -and (Test-Path -LiteralPath $Context.SnapshotPath)) { return $Context.SnapshotPath }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $snapshotDir = Join-Path $Context.SnapshotsDir "$stamp-$Reason"
    New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $snapshotDir 'startup-user') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $snapshotDir 'startup-common') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $snapshotDir 'tasks') -Force | Out-Null

    $manifest = [ordered]@{
        createdAt = (Get-Date).ToString('o')
        reason = $Reason
        script = $__extractedScriptPath
        registryRun = @(Get-AllStartTwoRunSnapshot)
        startupFolders = @(Copy-AllStartTwoStartupFolders -SnapshotDir $snapshotDir)
        scheduledTasks = @(Export-AllStartTwoTaskSnapshots -Context $Context -SnapshotDir $snapshotDir)
        appStartupTasks = @(Get-AllStartTwoAppStartupTaskSnapshot)
    }
    $manifestPath = Join-Path $snapshotDir 'manifest.json'
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $Context.SnapshotPath = $snapshotDir
    Write-AllStartTwoLog $Context 'INFO' "Pre-mutation snapshot ready: $snapshotDir"
    return $snapshotDir
}

function Merge-AllStartTwoCustomScheduledTasks {
    param([pscustomobject]$Context)

    $customConfigPath = Join-Path $Context.Root 'allstart2.custom.psd1'
    $Context | Add-Member -NotePropertyName CustomConfigPath -NotePropertyValue $customConfigPath -Force
    if (-not (Test-Path -LiteralPath $customConfigPath)) {
        return
    }

    $customConfig = Import-PowerShellDataFile -LiteralPath $customConfigPath
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
            return
        }
    }

    $scheduledTaskSpecs = @(
        foreach ($task in $customTasks) {
            if ($task.ContainsKey('EntryType') -and $task.EntryType -eq 'AppStartupTask') { continue }
            New-AllStartTwoCustomScheduledTaskSpec -Root $Context.Root -Task $task
        }
    )
    $appStartupTaskSpecs = @(
        foreach ($task in $customTasks) {
            if (-not ($task.ContainsKey('EntryType') -and $task.EntryType -eq 'AppStartupTask')) { continue }
            New-AllStartTwoCustomAppStartupTaskSpec -Task $task
        }
    )

    $Context.RequiredScheduledTasks = @(
        @($Context.RequiredScheduledTasks)
        @($scheduledTaskSpecs)
    )
    $Context.RequiredAppStartupTasks = @(
        @($Context.RequiredAppStartupTasks)
        @($appStartupTaskSpecs)
    )
    $Context.AllowedNames = @(
        @($Context.AllowedNames)
        @($scheduledTaskSpecs | ForEach-Object { $_.Name })
    ) | Where-Object { $_ } | Sort-Object -Unique

    if (@($disabledBuiltIns).Count -gt 0) {
        $Context.RequiredScheduledTasks = @(
            foreach ($task in @($Context.RequiredScheduledTasks)) {
                if ($disabledBuiltIns -contains $task.Name) { continue }
                $task
            }
        )
        $Context.AllowedNames = @(
            foreach ($name in @($Context.AllowedNames)) {
                if ($disabledBuiltIns -contains $name) { continue }
                $name
            }
        ) | Where-Object { $_ } | Sort-Object -Unique
    }
}

function New-AllStartTwoCustomScheduledTaskSpec {
    param(
        [string]$Root,
        [hashtable]$Task
    )

    $launcherPath = 'F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\allstart2-silent-launchers-20260604\trayquiet-start\trayquiet-start.vbs'
    $wscriptExe = Get-AllStartTwoWindowsScriptHostExe
    $targetPath = [string]$Task.TargetPath

    @{
        Name = [string]$Task.Name
        Execute = $wscriptExe
        Arguments = "//B //Nologo `"$launcherPath`" `"$targetPath`" 30 0 25"
        Description = if ($Task.ContainsKey('Description') -and $Task.Description) { [string]$Task.Description } else { "Custom startup target: $targetPath" }
    }
}

function New-AllStartTwoCustomAppStartupTaskSpec {
    param([hashtable]$Task)

    @{
        Name = [string]$Task.Name
        PackageFamilyName = [string]$Task.PackageFamilyName
        TaskId = [string]$Task.TaskId
        EnabledState = if ($Task.ContainsKey('EnabledState')) { [int]$Task.EnabledState } else { 2 }
    }
}

function Get-AllStartTwoWindowsPowerShellExe {
    $powershellExe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $powershellExe)) {
        throw "Windows PowerShell executable not found: $powershellExe"
    }
    return $powershellExe
}

function Get-AllStartTwoWindowsScriptHostExe {
    $wscriptExe = Join-Path $env:SystemRoot 'System32\wscript.exe'
    if (-not (Test-Path -LiteralPath $wscriptExe)) {
        throw "Windows Script Host executable not found: $wscriptExe"
    }
    return $wscriptExe
}

function Get-AllStartTwoRunSnapshot {
    foreach ($entry in @(
        @{ Hive = 'HKCU'; Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' },
        @{ Hive = 'HKLM'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' }
    )) {
        $props = Get-ItemProperty -Path $entry.Path -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($prop in @($props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' })) {
            [pscustomobject]@{
                hive = $entry.Hive
                path = $entry.Path
                name = $prop.Name
                value = [string]$prop.Value
            }
        }
    }
}

function Copy-AllStartTwoStartupFolders {
    param([string]$SnapshotDir)

    foreach ($folder in @(
        @{ Scope = 'User'; Path = [Environment]::GetFolderPath('Startup'); CopyDir = Join-Path $SnapshotDir 'startup-user' },
        @{ Scope = 'Common'; Path = [Environment]::GetFolderPath('CommonStartup'); CopyDir = Join-Path $SnapshotDir 'startup-common' }
    )) {
        if (-not $folder.Path -or -not (Test-Path -LiteralPath $folder.Path)) { continue }
        foreach ($item in @(Get-ChildItem -LiteralPath $folder.Path -Force -ErrorAction SilentlyContinue)) {
            $copiedTo = $null
            if (-not $item.PSIsContainer) {
                $copiedTo = Join-Path $folder.CopyDir $item.Name
                Copy-Item -LiteralPath $item.FullName -Destination $copiedTo -Force -ErrorAction SilentlyContinue
            }
            [pscustomobject]@{
                scope = $folder.Scope
                name = $item.Name
                fullName = $item.FullName
                copiedTo = $copiedTo
            }
        }
    }
}

function Export-AllStartTwoTaskSnapshots {
    param(
        [pscustomobject]$Context,
        [string]$SnapshotDir
    )

    try {
        $names = @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
            $_.TaskPath -eq '\' -and $_.Triggers -and
            @($_.Triggers | Where-Object { $_.CimClass.CimClassName -match 'LogonTrigger' }).Count -gt 0
        } | Select-Object -ExpandProperty TaskName -Unique)
    } catch {
        $names = @($Context.RequiredScheduledTasks | ForEach-Object { $_.Name })
    }

    foreach ($name in $names) {
        try {
            $task = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $task) {
                [pscustomobject]@{ taskName = $name; exists = $false }
                continue
            }
            $safeName = ($name -replace '[\\/:*?"<>| ]', '_')
            $xmlPath = Join-Path (Join-Path $SnapshotDir 'tasks') "$safeName.xml"
            Export-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop | Set-Content -LiteralPath $xmlPath -Encoding UTF8
            [pscustomobject]@{ taskName = $task.TaskName; taskPath = $task.TaskPath; state = [string]$task.State; xmlPath = $xmlPath; exists = $true }
        } catch {
            [pscustomobject]@{ taskName = $name; exists = $null; error = $_.Exception.Message }
        }
    }
}

function Resolve-AllStartTwoRunPath {
    param([string]$Hive)

    switch ($Hive) {
        'HKCU' { 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' }
        'HKLM' { 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' }
        default { throw "Unsupported Run hive: $Hive" }
    }
}

function Ensure-AllStartTwoRunEntries {
    param([pscustomobject]$Context)

    foreach ($entry in @($Context.RequiredRegistryRun)) {
        $runPath = Resolve-AllStartTwoRunPath -Hive $entry.Hive
        $current = Get-ItemProperty -Path $runPath -Name $entry.Name -ErrorAction SilentlyContinue
        if ($current -and $current.($entry.Name) -eq $entry.Command) {
            Write-AllStartTwoLog $Context 'VERIFY' "$($entry.Hive) Run $($entry.Name) is already correct"
            continue
        }
        if ($Context.DryRun) {
            Write-AllStartTwoLog $Context 'ACTION' "DryRun: would set $($entry.Hive) Run $($entry.Name) to $($entry.Command)"
            continue
        }
        Ensure-AllStartTwoMutationSnapshot -Context $Context -Reason 'startup-pre-required-run-change' | Out-Null
        Set-ItemProperty -Path $runPath -Name $entry.Name -Value $entry.Command -Force
        Write-AllStartTwoLog $Context 'ACTION' "Set $($entry.Hive) Run $($entry.Name)"
    }
}

function Ensure-AllStartTwoAhkShortcut {
    param([pscustomobject]$Context)

    $ahkPath = $Context.RequiredPaths.AhkScript
    if (-not (Test-Path -LiteralPath $ahkPath)) {
        Write-AllStartTwoLog $Context 'WARN' "Required AutoHotkey script missing: $ahkPath"
        return
    }

    $startupFolder = [Environment]::GetFolderPath('Startup')
    $shortcutPath = Join-Path $startupFolder 'current.ahk.lnk'
    $needsWrite = $true
    if (Test-Path -LiteralPath $shortcutPath) {
        try {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($shortcutPath)
            if (($shortcut.TargetPath -eq $ahkPath) -or ($shortcut.Arguments -match [regex]::Escape($ahkPath))) {
                $needsWrite = $false
            }
        } catch {}
    }
    if (-not $needsWrite) {
        Write-AllStartTwoLog $Context 'VERIFY' 'Startup folder current.ahk shortcut is already valid'
        return
    }
    if ($Context.DryRun) {
        Write-AllStartTwoLog $Context 'ACTION' "DryRun: would create/update shortcut $shortcutPath"
        return
    }

    Ensure-AllStartTwoMutationSnapshot -Context $Context -Reason 'startup-pre-shortcut-change' | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    if ($Context.RequiredPaths.AutoHotkeyExe -and (Test-Path -LiteralPath $Context.RequiredPaths.AutoHotkeyExe)) {
        $shortcut.TargetPath = $Context.RequiredPaths.AutoHotkeyExe
        $shortcut.Arguments = "`"$ahkPath`""
    } else {
        $shortcut.TargetPath = $ahkPath
        $shortcut.Arguments = ''
    }
    $shortcut.WorkingDirectory = Split-Path -Parent $ahkPath
    $shortcut.Save()
    Write-AllStartTwoLog $Context 'ACTION' "Created/updated startup shortcut $shortcutPath"
}

function Ensure-AllStartTwoScheduledTasks {
    param([pscustomobject]$Context)

    foreach ($taskSpec in @($Context.RequiredScheduledTasks)) {
        Ensure-AllStartTwoScheduledTask -Context $Context -TaskSpec $taskSpec
    }
}

function Ensure-AllStartTwoScheduledTask {
    param(
        [pscustomobject]$Context,
        [hashtable]$TaskSpec
    )

    $taskName = $TaskSpec.Name
    $execute = [string]$TaskSpec.Execute
    $arguments = if ($TaskSpec.ContainsKey('Arguments')) { [string]$TaskSpec.Arguments } else { '' }
    if ($execute -and -not (Test-Path -LiteralPath $execute)) {
        Write-AllStartTwoLog $Context 'WARN' "Required task executable missing for $taskName`: $execute"
        return
    }

    $task = Get-AllStartTwoScheduledTaskInfoFast -TaskName $taskName
    $taskActionText = if ($task) { Get-AllStartTwoScheduledTaskActionTextExact -TaskName $taskName } else { $null }
    if (-not $taskActionText -and $task) { $taskActionText = $task.Action }
    $needsRegister = $false
    $reason = $null
    if (-not $task) {
        $needsRegister = $true
        $reason = 'missing'
    } elseif (-not (Test-AllStartTwoTaskActionMatches -ActionText $taskActionText -Execute $execute -Arguments $arguments)) {
        $needsRegister = $true
        $reason = 'wrong-action'
    } elseif (Test-AllStartTwoTaskHasDelayOrNoLogonTrigger -TaskName $taskName) {
        $needsRegister = $true
        $reason = 'delayed-or-not-logon'
    }

    if ($needsRegister) {
        if ($Context.DryRun) {
            Write-AllStartTwoLog $Context 'ACTION' "DryRun: would register $taskName at logon with zero delay ($reason)"
            return
        }
        Ensure-AllStartTwoMutationSnapshot -Context $Context -Reason 'startup-pre-required-task-change' | Out-Null
        $action = if ($arguments) {
            New-ScheduledTaskAction -Execute $execute -Argument $arguments
        } else {
            New-ScheduledTaskAction -Execute $execute
        }
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description ([string]$TaskSpec.Description) -Force | Out-Null
        Write-AllStartTwoLog $Context 'ACTION' "Registered $taskName at logon with zero delay ($reason)"
        return
    }

    if ($task.State -eq 'Disabled') {
        if ($Context.DryRun) {
            Write-AllStartTwoLog $Context 'ACTION' "DryRun: would enable scheduled task $taskName"
        } else {
            Ensure-AllStartTwoMutationSnapshot -Context $Context -Reason 'startup-pre-required-task-enable' | Out-Null
            & schtasks.exe /change /tn $taskName /ENABLE | Out-Null
            Write-AllStartTwoLog $Context 'ACTION' "Enabled scheduled task $taskName"
        }
    } else {
        Write-AllStartTwoLog $Context 'VERIFY' "Scheduled task $taskName is enabled, at logon, zero delay"
    }
}

function Get-AllStartTwoScheduledTaskActionTextExact {
    param([string]$TaskName)

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $task) { return $null }
        return (@($task.Actions | ForEach-Object { (($_.Execute, $_.Arguments) -join ' ').Trim() }) -join '; ')
    } catch {
        return $null
    }
}

function Get-AllStartTwoScheduledTaskInfoFast {
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
        State = if ($scheduledState -eq 'Disabled') { 'Disabled' } elseif ($status) { $status } else { $scheduledState }
        Action = $taskToRun
    }
}

function Test-AllStartTwoTaskActionMatches {
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

function Test-AllStartTwoTaskHasDelayOrNoLogonTrigger {
    param([string]$TaskName)

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Select-Object -First 1
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

function Ensure-AllStartTwoPhoneReadiness {
    param([pscustomobject]$Context)

    foreach ($name in @('PhoneLinkPackageFamilyName', 'CrossDevicePackageFamilyName')) {
        $family = $Context.RequiredPaths[$name]
        if (Test-AllStartTwoAppxPackageFamilyInstalled -PackageFamilyName $family) {
            Write-AllStartTwoLog $Context 'VERIFY' "Package exists: $family"
        } else {
            Write-AllStartTwoLog $Context 'WARN' "Package missing: $family"
        }
    }
}

function Ensure-AllStartTwoRequiredAppStartupTasks {
    param([pscustomobject]$Context)

    foreach ($task in @($Context.RequiredAppStartupTasks)) {
        $state = Get-AllStartTwoAppStartupTaskState -PackageFamilyName $task.PackageFamilyName -TaskId $task.TaskId
        $stateLabel = Get-AllStartTwoAppStartupTaskStateLabel -State $state
        $desiredState = if ($task.ContainsKey('EnabledState')) { [int]$task.EnabledState } else { 2 }
        if ($state -eq $desiredState -or ($desiredState -eq 2 -and $state -eq 4)) {
            Write-AllStartTwoLog $Context 'VERIFY' "Required app startup task ready: $($task.PackageFamilyName) / $($task.TaskId) is $stateLabel"
            continue
        }
        if ($null -eq $state) {
            Write-AllStartTwoLog $Context 'WARN' "Required app startup task missing: $($task.PackageFamilyName) / $($task.TaskId)"
            continue
        }
        if ($Context.DryRun) {
            Write-AllStartTwoLog $Context 'ACTION' "DryRun: would set app startup task $($task.PackageFamilyName) / $($task.TaskId) from $stateLabel to $(Get-AllStartTwoAppStartupTaskStateLabel -State $desiredState)"
            continue
        }
        try {
            Ensure-AllStartTwoMutationSnapshot -Context $Context -Reason 'startup-pre-app-startup-enable' | Out-Null
            Set-AllStartTwoAppStartupTaskState -PackageFamilyName $task.PackageFamilyName -TaskId $task.TaskId -State $desiredState
            $after = Get-AllStartTwoAppStartupTaskState -PackageFamilyName $task.PackageFamilyName -TaskId $task.TaskId
            Write-AllStartTwoLog $Context 'ACTION' "Set app startup task $($task.PackageFamilyName) / $($task.TaskId) to $(Get-AllStartTwoAppStartupTaskStateLabel -State $after)"
        } catch {
            Write-AllStartTwoLog $Context 'WARN' "Failed to set app startup task $($task.PackageFamilyName) / $($task.TaskId): $($_.Exception.Message)"
        }
    }
}

function Get-AllStartTwoAppStartupTaskState {
    param(
        [string]$PackageFamilyName,
        [string]$TaskId
    )

    if (-not $PackageFamilyName -or -not $TaskId) { return $null }
    $statePath = Get-AllStartTwoAppStartupTaskRegistryPath -PackageFamilyName $PackageFamilyName -TaskId $TaskId
    try {
        $item = Get-ItemProperty -Path $statePath -Name State -ErrorAction Stop
        return [int]$item.State
    } catch {
        return $null
    }
}

function Get-AllStartTwoAppStartupTaskStateLabel {
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

function Get-AllStartTwoAppStartupTaskRegistryPath {
    param(
        [string]$PackageFamilyName,
        [string]$TaskId
    )

    "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$PackageFamilyName\$TaskId"
}

function Set-AllStartTwoAppStartupTaskState {
    param(
        [string]$PackageFamilyName,
        [string]$TaskId,
        [int]$State,
        [Nullable[int]]$UserEnabledStartupOnce
    )

    $statePath = Get-AllStartTwoAppStartupTaskRegistryPath -PackageFamilyName $PackageFamilyName -TaskId $TaskId
    Set-ItemProperty -Path $statePath -Name State -Value $State -Force -ErrorAction Stop
    if ($PSBoundParameters.ContainsKey('UserEnabledStartupOnce') -and $null -ne $UserEnabledStartupOnce) {
        Set-ItemProperty -Path $statePath -Name UserEnabledStartupOnce -Value $UserEnabledStartupOnce.Value -Force -ErrorAction SilentlyContinue
    }
}

function Get-AllStartTwoAppStartupTaskKey {
    param(
        [string]$PackageFamilyName,
        [string]$TaskId
    )

    ('{0}|{1}' -f ([string]$PackageFamilyName).ToLowerInvariant(), ([string]$TaskId).ToLowerInvariant())
}

function Get-AllStartTwoAllowedAppStartupTaskKeys {
    param([pscustomobject]$Context)

    @($Context.RequiredAppStartupTasks | ForEach-Object {
        Get-AllStartTwoAppStartupTaskKey -PackageFamilyName $_.PackageFamilyName -TaskId $_.TaskId
    }) | Sort-Object -Unique
}

function Get-AllStartTwoAppStartupTaskInventory {
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
            }
        }
    }
}

function Get-AllStartTwoAppStartupTaskSnapshot {
    @(Get-AllStartTwoAppStartupTaskInventory | ForEach-Object {
        [pscustomobject]@{
            packageFamilyName = $_.PackageFamilyName
            taskId = $_.TaskId
            state = $_.State
            userEnabledStartupOnce = $_.UserEnabledStartupOnce
        }
    })
}

function Test-AllStartTwoAppxPackageFamilyInstalled {
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

function Invoke-AllStartTwoAllowlistEnforcement {
    param([pscustomobject]$Context)

    Disable-AllStartTwoUnauthorizedRunEntries -Context $Context
    Quarantine-AllStartTwoUnauthorizedStartupFolderEntries -Context $Context
    Disable-AllStartTwoUnauthorizedRootLogonTasks -Context $Context
    Disable-AllStartTwoUnauthorizedAppStartupTasks -Context $Context
}

function Disable-AllStartTwoUnauthorizedRunEntries {
    param([pscustomobject]$Context)

    foreach ($runPath in @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
        $props = Get-ItemProperty -Path $runPath -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($prop in @($props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' })) {
            if ($Context.AllowedNames -contains $prop.Name) { continue }
            if ($Context.DryRun) {
                Write-AllStartTwoLog $Context 'ACTION' "DryRun: would remove unauthorized Run entry $runPath / $($prop.Name)"
                continue
            }
            try {
                Ensure-AllStartTwoMutationSnapshot -Context $Context -Reason 'startup-pre-unauthorized-run-disable' | Out-Null
                Remove-ItemProperty -Path $runPath -Name $prop.Name -Force -ErrorAction Stop
                Write-AllStartTwoLog $Context 'ACTION' "Removed unauthorized Run entry $runPath / $($prop.Name)"
            } catch {
                Write-AllStartTwoLog $Context 'WARN' "Failed to remove unauthorized Run entry $runPath / $($prop.Name): $($_.Exception.Message)"
            }
        }
    }
}

function Quarantine-AllStartTwoUnauthorizedStartupFolderEntries {
    param([pscustomobject]$Context)

    foreach ($folder in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup'))) {
        if (-not $folder -or -not (Test-Path -LiteralPath $folder)) { continue }
        foreach ($item in @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue)) {
            if ($item.PSIsContainer) { continue }
            if ($item.Name -ieq 'desktop.ini') { continue }
            if (($Context.AllowedNames -contains $item.BaseName) -or ($Context.AllowedNames -contains $item.Name)) { continue }
            if ($Context.DryRun) {
                Write-AllStartTwoLog $Context 'ACTION' "DryRun: would quarantine startup-folder entry $($item.FullName)"
                continue
            }
            try {
                Ensure-AllStartTwoMutationSnapshot -Context $Context -Reason 'startup-pre-folder-quarantine' | Out-Null
                $quarantineDir = New-AllStartTwoQuarantineDir -Context $Context -Surface 'startup-folder'
                $destination = Join-Path $quarantineDir $item.Name
                Move-Item -LiteralPath $item.FullName -Destination $destination -Force -ErrorAction Stop
                Write-AllStartTwoLog $Context 'ACTION' "Quarantined startup-folder entry $($item.FullName) -> $destination"
            } catch {
                Write-AllStartTwoLog $Context 'WARN' "Failed to quarantine startup-folder entry $($item.FullName): $($_.Exception.Message)"
            }
        }
    }
}

function Disable-AllStartTwoUnauthorizedRootLogonTasks {
    param([pscustomobject]$Context)

    try {
        Import-Module ScheduledTasks -ErrorAction SilentlyContinue
        $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
            $_.TaskPath -eq '\' -and
            $_.State -ne 'Disabled' -and
            $_.Triggers -and
            @($_.Triggers | Where-Object { $_.CimClass.CimClassName -match 'LogonTrigger' }).Count -gt 0
        })
    } catch {
        Write-AllStartTwoLog $Context 'WARN' "Could not enumerate root logon scheduled tasks for allowlist enforcement: $($_.Exception.Message)"
        return
    }

    foreach ($task in $tasks) {
        if ($Context.AllowedNames -contains $task.TaskName) { continue }
        if ($Context.DryRun) {
            Write-AllStartTwoLog $Context 'ACTION' "DryRun: would disable unauthorized root logon task $($task.TaskName)"
            continue
        }
        try {
            Ensure-AllStartTwoMutationSnapshot -Context $Context -Reason 'startup-pre-unauthorized-task-disable' | Out-Null
            & schtasks.exe /change /tn $task.TaskName /DISABLE | Out-Null
            $after = Get-AllStartTwoScheduledTaskInfoFast -TaskName $task.TaskName
            if ($after -and $after.State -eq 'Disabled') {
                Write-AllStartTwoLog $Context 'ACTION' "Disabled unauthorized root logon task $($task.TaskName)"
            } else {
                Write-AllStartTwoLog $Context 'WARN' "Disable command did not leave task disabled: $($task.TaskName)"
            }
        } catch {
            Write-AllStartTwoLog $Context 'WARN' "Failed to disable unauthorized root logon task $($task.TaskName): $($_.Exception.Message)"
        }
    }
}

function Disable-AllStartTwoUnauthorizedAppStartupTasks {
    param([pscustomobject]$Context)

    $allowedKeys = @(Get-AllStartTwoAllowedAppStartupTaskKeys -Context $Context)
    foreach ($task in @(Get-AllStartTwoAppStartupTaskInventory)) {
        $taskKey = Get-AllStartTwoAppStartupTaskKey -PackageFamilyName $task.PackageFamilyName -TaskId $task.TaskId
        if ($allowedKeys -contains $taskKey) { continue }
        if ($task.State -notin @(2, 4)) { continue }
        if ($Context.DryRun) {
            Write-AllStartTwoLog $Context 'ACTION' "DryRun: would disable unauthorized app startup task $($task.PackageFamilyName) / $($task.TaskId)"
            continue
        }
        try {
            Ensure-AllStartTwoMutationSnapshot -Context $Context -Reason 'startup-pre-app-startup-disable' | Out-Null
            Set-AllStartTwoAppStartupTaskState -PackageFamilyName $task.PackageFamilyName -TaskId $task.TaskId -State 1 -UserEnabledStartupOnce 0
            $after = Get-AllStartTwoAppStartupTaskState -PackageFamilyName $task.PackageFamilyName -TaskId $task.TaskId
            Write-AllStartTwoLog $Context 'ACTION' "Disabled unauthorized app startup task $($task.PackageFamilyName) / $($task.TaskId) -> $(Get-AllStartTwoAppStartupTaskStateLabel -State $after)"
        } catch {
            Write-AllStartTwoLog $Context 'WARN' "Failed to disable unauthorized app startup task $($task.PackageFamilyName) / $($task.TaskId): $($_.Exception.Message)"
        }
    }
}

function New-AllStartTwoQuarantineDir {
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

function Test-AllStartTwoRequiredStartup {
    param([pscustomobject]$Context)

    foreach ($key in @($Context.RequiredPaths.Keys | Where-Object { $_ -like '*Exe' -or $_ -like '*Script' -or $_ -like '*Vbs' })) {
        $path = $Context.RequiredPaths[$key]
        if (Test-Path -LiteralPath $path) {
            Write-AllStartTwoLog $Context 'VERIFY' "$key exists: $path"
        } else {
            Write-AllStartTwoLog $Context 'WARN' "$key missing: $path"
        }
    }

    foreach ($entry in @($Context.RequiredRegistryRun)) {
        $runPath = Resolve-AllStartTwoRunPath -Hive $entry.Hive
        $run = Get-ItemProperty -Path $runPath -Name $entry.Name -ErrorAction SilentlyContinue
        if ($run -and $run.($entry.Name) -eq $entry.Command) {
            Write-AllStartTwoLog $Context 'VERIFY' "$($entry.Hive) Run $($entry.Name) exists and is correct"
        } else {
            Write-AllStartTwoLog $Context 'WARN' "$($entry.Hive) Run $($entry.Name) missing or wrong"
        }
    }

    foreach ($taskSpec in @($Context.RequiredScheduledTasks)) {
        $task = Get-ScheduledTask -TaskName $taskSpec.Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($task -and $task.State -ne 'Disabled') {
            Write-AllStartTwoLog $Context 'VERIFY' "$($taskSpec.Name) exists and is $($task.State)"
        } else {
            Write-AllStartTwoLog $Context 'WARN' "$($taskSpec.Name) missing or disabled"
        }
    }

    Ensure-AllStartTwoPhoneReadiness -Context $Context
    foreach ($task in @($Context.RequiredAppStartupTasks)) {
        $state = Get-AllStartTwoAppStartupTaskState -PackageFamilyName $task.PackageFamilyName -TaskId $task.TaskId
        $label = Get-AllStartTwoAppStartupTaskStateLabel -State $state
        if ($state -in @(2, 4)) {
            Write-AllStartTwoLog $Context 'VERIFY' "Required app startup task enabled: $($task.PackageFamilyName) / $($task.TaskId) is $label"
        } else {
            Write-AllStartTwoLog $Context 'WARN' "Required app startup task not enabled: $($task.PackageFamilyName) / $($task.TaskId) is $label"
        }
    }
    Test-AllStartTwoStartupResidue -Context $Context
}

function Test-AllStartTwoStartupResidue {
    param([pscustomobject]$Context)

    foreach ($runPath in @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
        foreach ($name in @('current.ahk', 'Phone', 'SecurityHealth', 'RtkAudUService')) {
            $entry = Get-ItemProperty -Path $runPath -Name $name -ErrorAction SilentlyContinue
            if ($entry) {
                Write-AllStartTwoLog $Context 'WARN' "Unexpected legacy Run entry still present: $runPath / $name"
            } else {
                Write-AllStartTwoLog $Context 'VERIFY' "Legacy Run entry absent: $runPath / $name"
            }
        }
    }

    foreach ($folder in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup'))) {
        if (-not $folder -or -not (Test-Path -LiteralPath $folder)) { continue }
        $legacyShortcut = Join-Path $folder 'current.ahk.lnk'
        if (Test-Path -LiteralPath $legacyShortcut) {
            Write-AllStartTwoLog $Context 'WARN' "Unexpected startup-folder entry still present: $legacyShortcut"
        } else {
            Write-AllStartTwoLog $Context 'VERIFY' "Legacy startup-folder entry absent: $legacyShortcut"
        }
        foreach ($item in @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue)) {
            if ($item.PSIsContainer -or $item.Name -ieq 'desktop.ini') { continue }
            if (($Context.AllowedNames -contains $item.Name) -or ($Context.AllowedNames -contains $item.BaseName)) { continue }
            Write-AllStartTwoLog $Context 'WARN' "Unexpected startup-folder entry still present: $($item.FullName)"
        }
    }

    $clawdBotTask = Get-AllStartTwoScheduledTaskInfoFast -TaskName 'ClawdBotTray'
    if ($clawdBotTask -and $clawdBotTask.State -ne 'Disabled') {
        Write-AllStartTwoLog $Context 'WARN' 'ClawdBotTray is still enabled in the non-agent startup profile'
    } else {
        Write-AllStartTwoLog $Context 'VERIFY' 'ClawdBotTray is not enabled in the non-agent startup profile'
    }

    $allowedAppStartupKeys = @(Get-AllStartTwoAllowedAppStartupTaskKeys -Context $Context)
    foreach ($task in @(Get-AllStartTwoAppStartupTaskInventory)) {
        $taskKey = Get-AllStartTwoAppStartupTaskKey -PackageFamilyName $task.PackageFamilyName -TaskId $task.TaskId
        if ($allowedAppStartupKeys -contains $taskKey) { continue }
        if ($task.State -in @(2, 4)) {
            Write-AllStartTwoLog $Context 'WARN' "Unexpected app startup task still enabled: $($task.PackageFamilyName) / $($task.TaskId)"
        }
    }
}

& $__extractedFunctionName -Mode $Mode -DryRun:$DryRun
