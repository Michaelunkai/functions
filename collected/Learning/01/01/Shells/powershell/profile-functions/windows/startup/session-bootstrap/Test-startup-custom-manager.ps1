[CmdletBinding()]
param(
    [switch]$SkipProfileBinding,
    [switch]$SkipLiveTaskState,
    [switch]$RunPopupProbe,
    [string]$ProbeTargetPath = 'C:\Windows\System32\notepad.exe'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$managerPath = Join-Path $root 'Invoke-startup-custom-manager.ps1'
$allstartPath = Join-Path $root 'AllStartBootstrap\Invoke-allstart.ps1'
$allstart2Path = Join-Path $root 'AllStartTwoBootstrap\Invoke-allstart2.ps1'
$allstartCustomConfigPath = Join-Path $root 'AllStartBootstrap\allstart.custom.psd1'
$allstart2CustomConfigPath = Join-Path $root 'AllStartTwoBootstrap\allstart2.custom.psd1'
$quietLauncherPath = 'C:\Users\micha\.claude\scripts\Start-TrayQuietApp.ps1'
$quietVbsLauncherPath = 'C:\Users\micha\.claude\scripts\trayquiet-start.vbs'
$quietWin32DllPath = 'C:\Users\micha\.claude\scripts\TrayQuietWin32.dll'
$windowsPowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$wscriptExe = Join-Path $env:SystemRoot 'System32\wscript.exe'

function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Test-PowerShellParse {
    param([string]$Path)

    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        $joined = ($errors | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" }) -join '; '
        throw "Parse failed for $Path - $joined"
    }
}

function Get-CustomStartupEntries {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $config = Import-PowerShellDataFile -LiteralPath $Path
    if ($config.ContainsKey('CustomScheduledTasks')) { return @($config.CustomScheduledTasks) }
    return @()
}

function Get-StartupCustomField {
    param(
        [object]$Entry,
        [string]$Name
    )

    if ($Entry -is [hashtable] -and $Entry.ContainsKey($Name)) { return $Entry[$Name] }
    $property = $Entry.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Import-TrayQuietWin32ForProbe {
    try {
        Add-Type -Path $quietWin32DllPath -ErrorAction Stop
        return
    } catch {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class TrayQuietWin32 {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, ref uint lpdwProcessId);
}
'@ -ErrorAction Stop
    }
}

function Get-VisibleStartupProbeWindows {
    param(
        [string]$TargetProcessName,
        [string]$TargetTitleNeedle
    )

    $windows = New-Object System.Collections.Generic.List[object]
    [TrayQuietWin32]::EnumWindows({
        param([IntPtr]$Handle, [IntPtr]$Param)

        if (-not [TrayQuietWin32]::IsWindowVisible($Handle)) { return $true }
        $titleBuilder = New-Object System.Text.StringBuilder 512
        [void][TrayQuietWin32]::GetWindowText($Handle, $titleBuilder, $titleBuilder.Capacity)
        $title = $titleBuilder.ToString()
        [uint32]$windowProcessId = 0
        [void][TrayQuietWin32]::GetWindowThreadProcessId($Handle, [ref]$windowProcessId)
        $process = Get-Process -Id $windowProcessId -ErrorAction SilentlyContinue
        if (-not $process) { return $true }

        $isTerminal = ($process.ProcessName -match '^(powershell|pwsh|cmd|conhost|WindowsTerminal|wt|wscript|cscript)$') -or
            ($title -match '(?i)(PowerShell|Command Prompt|cmd\.exe|Start-TrayQuietApp|trayquiet|wscript|cscript)')
        $isTarget = (
            (-not [string]::IsNullOrWhiteSpace($TargetProcessName) -and $process.ProcessName -like $TargetProcessName) -or
            (-not [string]::IsNullOrWhiteSpace($TargetTitleNeedle) -and $title -like "*$TargetTitleNeedle*")
        )

        if ($isTerminal -or $isTarget) {
            $windows.Add([pscustomobject]@{
                Handle = $Handle.ToInt64()
                ProcessId = [int]$windowProcessId
                Process = $process.ProcessName
                Title = $title
                Kind = if ($isTerminal) { 'Terminal' } else { 'TargetApp' }
            })
        }
        return $true
    }, [IntPtr]::Zero) | Out-Null
    return $windows.ToArray()
}

function Invoke-TrayQuietNoPopupProbe {
    param([string]$TargetPath)

    Assert-Condition (Test-Path -LiteralPath $TargetPath -PathType Leaf) "Popup probe target missing: $TargetPath"
    Assert-Condition (Test-Path -LiteralPath $quietWin32DllPath -PathType Leaf) "Popup probe Win32 helper missing: $quietWin32DllPath"
    Import-TrayQuietWin32ForProbe
    $targetLeaf = [IO.Path]::GetFileNameWithoutExtension($TargetPath)
    $targetProcessPattern = "$targetLeaf*"
    $existingTargetProcessIds = @(Get-Process -Name $targetLeaf -ErrorAction SilentlyContinue | ForEach-Object { [int]$_.Id })

    $initial = @{}
    foreach ($window in @(Get-VisibleStartupProbeWindows -TargetProcessName $targetProcessPattern -TargetTitleNeedle $targetLeaf)) {
        $initial[[string]$window.Handle] = $true
    }

    $probeTaskName = 'CodexTrayQuietContractProbe'
    try {
        Unregister-ScheduledTask -TaskName $probeTaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        $arguments = "//B //Nologo `"$quietVbsLauncherPath`" `"$TargetPath`" 8 0 25"
        $action = New-ScheduledTaskAction -Execute $wscriptExe -Argument $arguments
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(30)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName $probeTaskName -Action $action -Trigger $trigger -Settings $settings -Description 'Temporary Codex tray-quiet no-popup contract probe' -Force | Out-Null
        Start-ScheduledTask -TaskName $probeTaskName

        $newWindows = New-Object System.Collections.Generic.List[object]
        $deadline = (Get-Date).AddSeconds(10)
        do {
            foreach ($window in @(Get-VisibleStartupProbeWindows -TargetProcessName $targetProcessPattern -TargetTitleNeedle $targetLeaf)) {
                if (-not $initial.ContainsKey([string]$window.Handle)) {
                    $newWindows.Add($window)
                }
            }
            Start-Sleep -Milliseconds 25
        } while ((Get-Date) -lt $deadline)

        $taskInfo = Get-ScheduledTaskInfo -TaskName $probeTaskName
        Assert-Condition ($taskInfo.LastTaskResult -eq 0) "Tray-quiet popup probe task failed: $($taskInfo.LastTaskResult)"
        $uniqueWindows = @($newWindows | Sort-Object Kind, ProcessId, Handle, Title -Unique)
        if ($uniqueWindows.Count -gt 0) {
            $details = ($uniqueWindows | Select-Object -First 12 | ForEach-Object { "$($_.Kind):$($_.Process):$($_.ProcessId):$($_.Title)" }) -join '; '
            throw "New visible terminal/app windows appeared during tray-quiet probe: $details"
        }
    } finally {
        Unregister-ScheduledTask -TaskName $probeTaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        Get-Process -Name $targetLeaf -ErrorAction SilentlyContinue |
            Where-Object { $existingTargetProcessIds -notcontains [int]$_.Id } |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

Write-Host '== startup custom manager contract =='

foreach ($path in @($managerPath, $quietLauncherPath, $quietVbsLauncherPath)) {
    Assert-Condition (Test-Path -LiteralPath $path -PathType Leaf) "Required startup script missing: $path"
    if ($path -like '*.ps1') { Test-PowerShellParse -Path $path }
}
Assert-Condition (Test-Path -LiteralPath $windowsPowerShellExe -PathType Leaf) "Windows PowerShell 5 executable missing: $windowsPowerShellExe"
Assert-Condition (Test-Path -LiteralPath $wscriptExe -PathType Leaf) "Windows Script Host executable missing: $wscriptExe"

$managerContent = Get-Content -LiteralPath $managerPath -Raw
$quietLauncherContent = Get-Content -LiteralPath $quietLauncherPath -Raw
$quietVbsContent = Get-Content -LiteralPath $quietVbsLauncherPath -Raw
Assert-Condition ($managerContent -match [regex]::Escape("System32\WindowsPowerShell\v1.0\powershell.exe")) 'Startup manager must pin Windows PowerShell 5 by absolute path.'
Assert-Condition ($managerContent -notmatch '&\s+powershell\.exe\b') 'Startup manager must not shell to PATH-resolved powershell.exe.'
Assert-Condition ($managerContent -match 'No current matching startup entries.*already satisfied') '2start removals must be idempotent when an entry is already absent.'
Assert-Condition ($managerContent -match '\$Action -eq ''Remove'' -and \$noRemoveMatches') '2start no-op removals must return before validation/apply side effects.'
Assert-Condition ($managerContent -match 'Disable-MatchingStartupScheduledTasks') '2start must still disable stale custom scheduled tasks.'
Assert-Condition ($managerContent -match 'Select-BestStartupResolvedTarget') '1start must rank ambiguous app-name resolver matches instead of failing.'
Assert-Condition ($managerContent -match 'Find-StartupExecutableOnLocalDrives') '1start must include a fast local-drive executable fallback resolver.'
Assert-Condition ($managerContent -match 'Wait-Job\s+-Job\s+\$job\s+-Timeout') '1start full-drive executable fallback must be timeout bounded.'
Assert-Condition ($managerContent -match 'Resolve-StartupCurrentWindowsAppsTargetPath') '1start/allstart config manager must self-heal stale WindowsApps package-version target paths.'
Assert-Condition ($managerContent -match 'Update-StartupCustomConfigsToCurrentTargets') '1start must rewrite stale custom startup target paths before validation/apply.'
Assert-Condition ($managerContent -notmatch '1start app name is ambiguous') '1start must not throw ambiguity errors for app names like chrome.'
Assert-Condition ($quietLauncherContent -match 'Update-TrayQuietDescendantProcessIdSet') 'Tray-quiet launcher must track descendant processes spawned by startup apps.'
Assert-Condition ($quietLauncherContent -match 'Update-TrayQuietNewMatchingProcessIdSet') 'Tray-quiet launcher must discover newly launched matching process IDs during the boot launch window.'
Assert-Condition ($quietLauncherContent -match 'BroadMatchSeconds') 'Tray-quiet launcher must bound broad process/title matching so manual GUI opens are not hidden for the full boot suppression window.'
Assert-Condition ($quietLauncherContent -match '\$useBroadMatch') 'Tray-quiet launcher must gate broad process/title hiding behind a boot-only discovery flag.'
Assert-Condition ($quietLauncherContent -match '\$includeProcessMatch\s+-or\s+\$processMatch\s+-or\s+\$titleMatch') 'Tray-quiet launcher must still hide launched child windows even when names differ.'
Assert-Condition ($quietLauncherContent -match 'ForceLaunchIfRunning') 'Tray-quiet launcher must support an explicit opt-in before relaunching an already running app.'
Assert-Condition ($quietLauncherContent -match 'skipping relaunch to avoid surfacing an existing GUI') 'Tray-quiet launcher must skip default relaunch when the target is already running.'
Assert-Condition ($quietLauncherContent -match 'ExcludeProcessIds') 'Tray-quiet launcher must protect manual/pre-existing app windows.'
Assert-Condition ($quietLauncherContent -match 'EnumWindows') 'Tray-quiet launcher must enumerate every top-level window, not only MainWindowHandle.'
Assert-Condition ($quietLauncherContent -notmatch 'QuietStableMilliseconds|stableSince') 'Tray-quiet launcher must not stop suppressing early before delayed boot GUIs appear.'
Assert-Condition ($quietVbsContent -match 'suppressSeconds = "120"') 'VBS launcher default suppress window must be 120 seconds for delayed boot GUIs.'
Assert-Condition ($quietVbsContent -match 'shell\.Run command, 0, False') 'VBS launcher must run hidden and non-blocking.'

$allstartContent = Get-Content -LiteralPath $allstartPath -Raw
$allstart2Content = Get-Content -LiteralPath $allstart2Path -Raw
Assert-Condition ($allstartContent -match 'Resolve-AllStartCurrentWindowsAppsTargetPath') 'allstart must self-heal stale WindowsApps package-version paths at boot.'
Assert-Condition ($allstart2Content -match 'Resolve-AllStartTwoCurrentWindowsAppsTargetPath') 'allstart2 must self-heal stale WindowsApps package-version paths at boot.'

$processLassoPath = 'F:\backup\windowsapps\installed\Process Lasso\ProcessLasso.exe'
if (Test-Path -LiteralPath $processLassoPath -PathType Leaf) {
    & $managerPath -Action Add -Value @($processLassoPath, 'murmure') -NoApply | Out-Host
}
$chromeResolveOutput = & $managerPath -Action Add -Value 'chrome' -NoApply 6>&1
$chromeResolveOutput | Out-Host
$chromeResolveText = [string]::Join("`n", @($chromeResolveOutput | ForEach-Object { [string]$_ }))
Assert-Condition ($chromeResolveText.IndexOf('chrome.exe', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) '1start chrome must resolve to a real Chrome executable without requiring a full path.'
Assert-Condition ($chromeResolveText.IndexOf('ambiguous', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) '1start chrome must not report ambiguity.'
$missingResolveOutput = & $managerPath -Action Add -Value '__definitely_not_a_startup_app__' -NoApply 6>&1
$missingResolveOutput | Out-Host
$missingResolveText = [string]::Join("`n", @($missingResolveOutput | ForEach-Object { [string]$_ }))
Assert-Condition ($missingResolveText.IndexOf('startup configuration is unchanged', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) '1start unresolved app names must exit cleanly without changing startup.'
& $managerPath -Action Remove -Value @('todoist', 'ascendara', 'telegram', '__definitely_not_a_startup_app__') -NoApply | Out-Host
& $managerPath -Action Remove -Value @('__definitely_not_a_startup_app__') -NoApply | Out-Host
Write-Host 'absent removal idempotence check ok'
Write-Host 'manager no-apply checks ok'

foreach ($configPath in @($allstartCustomConfigPath, $allstart2CustomConfigPath)) {
    $raw = if (Test-Path -LiteralPath $configPath) { Get-Content -LiteralPath $configPath -Raw } else { '' }
    Assert-Condition ($raw -notmatch '(?i)Todoist|Telegram|Ascendara') "Removed apps must not remain in custom config: $configPath"
    foreach ($entry in @(Get-CustomStartupEntries -Path $configPath)) {
        $name = [string]$entry.Name
        $targetPath = [string]$entry.TargetPath
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($name)) "Custom entry missing Name in $configPath"
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($targetPath)) "Custom entry missing TargetPath in $configPath"
        Assert-Condition ($targetPath -notmatch '(?i)Todoist|Telegram|Ascendara') "Removed app target remains in $configPath`: $targetPath"
    }
}
Write-Host 'custom config checks ok'

if (-not $SkipProfileBinding) {
    $profileProbe = @"
`$commands = Get-Command 1start,2start -ErrorAction Stop | ForEach-Object {
    [pscustomobject]@{
        Name = `$_.Name
        CommandType = [string]`$_.CommandType
        Definition = [string]`$_.Definition
        FullProfileLibraryPath = [string]`$script:FullProfileLibraryPath
    }
}
'STARTUP_PROFILE_BINDING_JSON=' + (`$commands | ConvertTo-Json -Compress)
"@
    $profileOutput = & $windowsPowerShellExe -NoLogo -ExecutionPolicy Bypass -Command $profileProbe
    $jsonLine = @($profileOutput | Where-Object { $_ -like 'STARTUP_PROFILE_BINDING_JSON=*' } | Select-Object -Last 1)
    Assert-Condition ($jsonLine.Count -eq 1) 'Could not read 1start/2start profile binding from Windows PowerShell 5.'
    $commands = ($jsonLine -replace '^STARTUP_PROFILE_BINDING_JSON=', '') | ConvertFrom-Json
    foreach ($name in @('1start', '2start')) {
        $command = @($commands | Where-Object { $_.Name -eq $name }) | Select-Object -First 1
        Assert-Condition ($null -ne $command) "Profile function missing: $name"
        $definition = [string]$command.Definition
        $fullProfileLibraryPath = [string]$command.FullProfileLibraryPath
        $fullDefinition = ''
        if ($definition -notmatch [regex]::Escape($managerPath)) {
            Assert-Condition (Test-Path -LiteralPath $fullProfileLibraryPath -PathType Leaf) "Profile function $name is a proxy, but the full profile library is missing."
            $fullDefinition = Get-Content -LiteralPath $fullProfileLibraryPath -Raw
        }

        Assert-Condition (
            $definition -match [regex]::Escape($managerPath) -or
            $fullDefinition -match [regex]::Escape($managerPath)
        ) "Profile function $name is not bound to the startup manager."
        Assert-Condition (
            $definition -match 'ValueFromRemainingArguments' -or
            $fullDefinition -match "function\s+global:$name[\s\S]*?ValueFromRemainingArguments"
        ) "Profile function $name must accept multiple targets in one call."
    }
    Write-Host 'profile binding checks ok'
}

if (-not $SkipLiveTaskState) {
    $customEntries = @()
    $customEntries += @(Get-CustomStartupEntries -Path $allstartCustomConfigPath)
    $customEntries += @(Get-CustomStartupEntries -Path $allstart2CustomConfigPath)
    $customEntries = @($customEntries | Sort-Object { [string](Get-StartupCustomField -Entry $_ -Name 'Name') } -Unique)
    $allowedRootLogonNames = @(
        'Autorun_current_ahk'
        'ClawdBotTray'
        'OpenSpeedy_Tray'
        'Murmure_Tray'
    )
    $allowedRootLogonNames += @($customEntries | ForEach-Object { [string](Get-StartupCustomField -Entry $_ -Name 'Name') })
    $allowedRootLogonNames = @($allowedRootLogonNames | Where-Object { $_ } | Sort-Object -Unique)

    foreach ($task in @(Get-ScheduledTask -TaskName 'CustomStartup_*' -ErrorAction SilentlyContinue)) {
        $action = @($task.Actions)[0]
        $execute = [string]$action.Execute
        $arguments = [string]$action.Arguments
        if ($task.State -ne 'Disabled') {
            Assert-Condition ($execute -match 'wscript\.exe$') "Enabled custom startup task must execute wscript.exe: $($task.TaskName)"
            Assert-Condition ($arguments -match 'trayquiet-start\.vbs') "Enabled custom startup task must route through trayquiet-start.vbs: $($task.TaskName)"
            Assert-Condition ($arguments -match '120 0 25') "Enabled custom startup task must use 120 0 25 zero-delay tray-quiet args: $($task.TaskName)"
            Assert-Condition ($execute -notmatch 'powershell\.exe' -and $arguments -notmatch 'Start-TrayQuietApp\.ps1') "Enabled custom startup task must not expose PowerShell directly: $($task.TaskName)"
        }
    }

    foreach ($oldName in @('CustomStartup_Todoist_0d3d78ba', 'CustomStartup_Telegram_acf6eb58', 'CustomStartup_Ascendara_8f30f765', 'OpenWhisper_Tray')) {
        $oldTask = Get-ScheduledTask -TaskName $oldName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($oldTask) {
            Assert-Condition ($oldTask.State -eq 'Disabled') "Removed/non-required startup task is still enabled: $oldName"
        }
    }

    $enabledRootLogonTasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
        $_.TaskPath -eq '\' -and
        $_.State -ne 'Disabled' -and
        $_.Triggers -and
        @($_.Triggers | Where-Object { $_.CimClass.CimClassName -match 'LogonTrigger' }).Count -gt 0
    })
    foreach ($task in $enabledRootLogonTasks) {
        Assert-Condition ($allowedRootLogonNames -contains $task.TaskName) "Unauthorized enabled root logon task remains: $($task.TaskName)"
    }

    $enabledAppStartupTasks = @()
    $appStartupBase = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'
    if (Test-Path -LiteralPath $appStartupBase) {
        foreach ($packageKey in @(Get-ChildItem -LiteralPath $appStartupBase -ErrorAction SilentlyContinue)) {
            foreach ($taskKey in @(Get-ChildItem -LiteralPath $packageKey.PSPath -ErrorAction SilentlyContinue)) {
                $props = Get-ItemProperty -LiteralPath $taskKey.PSPath -ErrorAction SilentlyContinue
                if ($null -eq $props -or $null -eq $props.PSObject.Properties['State']) { continue }
                if ([int]$props.State -in @(2, 4)) {
                    $enabledAppStartupTasks += "$($packageKey.PSChildName)|$($taskKey.PSChildName)"
                }
            }
        }
    }
    $allowedAppStartupTasks = @(
        'Microsoft.YourPhone_8wekyb3d8bbwe|YourPhone.Start'
        'MicrosoftWindows.CrossDevice_cw5n1h2txyewy|CrossDevice.Start'
    )
    foreach ($taskKey in $enabledAppStartupTasks) {
        Assert-Condition ($allowedAppStartupTasks -contains $taskKey) "Unauthorized enabled packaged app startup task remains: $taskKey"
    }

    $runEntries = @()
    foreach ($runPath in @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
        $item = Get-ItemProperty -Path $runPath -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        foreach ($property in $item.PSObject.Properties) {
            if ($property.Name -in @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) { continue }
            $runEntries += $property.Name
        }
    }
    foreach ($runEntry in $runEntries) {
        Assert-Condition ($runEntry -eq 'FullScreenSnip') "Unauthorized enabled Run entry remains: $runEntry"
    }

    $startupFolders = @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup'))
    foreach ($folder in $startupFolders) {
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        foreach ($item in @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue)) {
            Assert-Condition ($item.Name -eq 'desktop.ini') "Unauthorized startup-folder entry remains: $($item.FullName)"
        }
    }
    Write-Host 'live startup state checks ok'
}

if ($RunPopupProbe) {
    Invoke-TrayQuietNoPopupProbe -TargetPath $ProbeTargetPath
    Write-Host 'tray-quiet popup probe ok'
}

Write-Host 'STARTUP_CUSTOM_MANAGER_CONTRACT_PASS'
