[CmdletBinding()]
param(
    [switch]$SkipRuntimeVerify
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$entryPoint = Join-Path $root 'Invoke-allstart.ps1'
$configPath = Join-Path $root 'allstart.config.psd1'
$customConfigPath = Join-Path $root 'allstart.custom.psd1'
$launcherPath = Join-Path $root 'Invoke-custom-startup-target.ps1'
$managerPath = Join-Path (Split-Path -Parent $root) 'Invoke-startup-custom-manager.ps1'
$managerContractPath = Join-Path (Split-Path -Parent $root) 'Test-startup-custom-manager.ps1'
$managerContent = Get-Content -LiteralPath $managerPath -Raw
$quietLauncherPath = 'C:\Users\micha\.claude\scripts\Start-TrayQuietApp.ps1'
$quietWin32DllPath = 'C:\Users\micha\.claude\scripts\TrayQuietWin32.dll'
$quietVbsLauncherPath = 'C:\Users\micha\.claude\scripts\trayquiet-start.vbs'

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

function Test-SafetyInspection {
    param([string]$Path)

    $matches = @(Select-String -LiteralPath $Path -Pattern 'Remove-Item|Remove-ItemProperty|Disable-ScheduledTask|Unregister-ScheduledTask|Stop-Service|Set-Service|winget uninstall|Remove-Appx|Set-ItemProperty|Register-ScheduledTask|schtasks|Set-Content|Move-Item' -ErrorAction SilentlyContinue)
    $unsafe = @()
    foreach ($match in $matches) {
        $line = $match.Line.Trim()
        if ($line -match 'Unregister-ScheduledTask|Stop-Service|Set-Service|winget uninstall|Remove-Appx') {
            $unsafe += $match
            continue
        }
        if ($line -match 'Remove-ItemProperty') {
            continue
        }
        $isGuardedLogRotation = ($line -like '*$oldLog.FullName*')
        if (($line -match 'Remove-Item') -and (-not $isGuardedLogRotation) -and ($line -notmatch 'Remove-Job')) {
            $unsafe += $match
        }
    }
    if ($unsafe.Count -gt 0) {
        $joined = ($unsafe | ForEach-Object { "$($_.LineNumber): $($_.Line.Trim())" }) -join '; '
        throw "Unsafe destructive operation found: $joined"
    }
    return $matches
}

Write-Host '== allstart validation =='

Get-ChildItem -LiteralPath $root -File | Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1') } | ForEach-Object {
    Test-PowerShellParse -Path $_.FullName
    Write-Host "parse ok: $($_.Name)"
}
foreach ($extraPath in @($managerPath, $managerContractPath, $customConfigPath)) {
    if (Test-Path -LiteralPath $extraPath) {
        Test-PowerShellParse -Path $extraPath
        Write-Host "parse ok: $(Split-Path -Leaf $extraPath)"
    }
}
Assert-Condition (Test-Path -LiteralPath $launcherPath) 'Custom startup launcher script is missing.'
Assert-Condition (Test-Path -LiteralPath $quietLauncherPath) 'Shared tray-quiet launcher script is missing.'
Assert-Condition (Test-Path -LiteralPath $quietWin32DllPath) 'Precompiled tray-quiet Win32 helper DLL is missing.'
Assert-Condition (Test-Path -LiteralPath $quietVbsLauncherPath) 'Hidden WScript tray-quiet launcher is missing.'
Test-PowerShellParse -Path $quietLauncherPath
Assert-Condition ($managerContent -match 'function Resolve-QuietStartupEntry') 'Startup manager must define the quiet-startup resolver.'
Assert-Condition ($managerContent -match 'Window-suppressed startup target') 'Startup manager must route custom targets through the window-suppressed scheduled task path.'
Assert-Condition ($managerContent -match 'Native app startup task is still enabled and can pop a GUI') 'Startup manager must reject native packaged startup tasks that can still pop GUI windows.'
Assert-Condition ($managerContent -match 'Add-StartupStartMenuShortcutTargets') 'Startup manager must resolve classic desktop apps from Start Menu shortcuts.'
Assert-Condition ($managerContent -match '\[switch\]\$NoApply') 'Startup manager must keep a no-apply validation path for resolver testing.'
Assert-Condition ($managerContent -match 'System32\\WindowsPowerShell\\v1\.0\\powershell\.exe') 'Startup manager must pin Windows PowerShell 5 by absolute path.'
Assert-Condition ($managerContent -notmatch '&\s+powershell\.exe\b') 'Startup manager must not shell to PATH-resolved powershell.exe.'
Assert-Condition ($managerContent -match 'No current matching startup entries.*already satisfied') '2start must be idempotent when an entry is already absent.'
$quietLauncherContent = Get-Content -LiteralPath $quietLauncherPath -Raw
$quietVbsLauncherContent = Get-Content -LiteralPath $quietVbsLauncherPath -Raw
Assert-Condition ($quietLauncherContent -match 'TrayQuietWin32\.dll') 'Shared tray-quiet launcher must load the precompiled Win32 helper DLL.'
Assert-Condition ($quietLauncherContent -match 'SuppressIntervalMilliseconds') 'Shared tray-quiet launcher must support a fast suppression interval.'
Assert-Condition ($quietLauncherContent -match "WindowStyle\s*=\s*'Hidden'") 'Shared tray-quiet launcher must request hidden startup, not minimized startup.'
Assert-Condition ($quietLauncherContent -match 'ExcludeProcessIds') 'Shared tray-quiet launcher must protect pre-existing/manual app windows from suppression.'
Assert-Condition ($quietLauncherContent -match 'EnumWindows') 'Shared tray-quiet launcher must enumerate every top-level window, not only MainWindowHandle.'
Assert-Condition ($quietLauncherContent -notmatch 'QuietStableMilliseconds|stableSince') 'Shared tray-quiet launcher must suppress for the full quiet window so delayed boot GUIs stay hidden.'
Assert-Condition ($quietLauncherContent -match 'Update-TrayQuietDescendantProcessIdSet') 'Shared tray-quiet launcher must track child processes spawned by startup apps.'
Assert-Condition ($quietLauncherContent -match '\$includeProcessMatch\s+-or\s+\$processMatch\s+-or\s+\$titleMatch') 'Shared tray-quiet launcher must hide launched child windows even when names differ.'
Assert-Condition ($quietVbsLauncherContent -match 'suppressSeconds = "120"') 'Hidden WScript launcher default suppress window must be 120 seconds.'
Assert-Condition ($quietVbsLauncherContent -match 'WScript\.Shell') 'Hidden WScript launcher must use WScript.Shell.'
Assert-Condition ($quietVbsLauncherContent -match 'shell\.Run command, 0, False') 'Hidden WScript launcher must start PowerShell with a hidden window style.'

$config = Import-PowerShellDataFile -LiteralPath $configPath
Import-PowerShellDataFile -LiteralPath $customConfigPath | Out-Null
Assert-Condition ($config.RequiredLaunchPoints.TelegramDmScope -eq 'per-account-channel-peer') 'Config dmScope is not protected.'
Assert-Condition ($config.RequiredLaunchPoints.PhoneLinkStartupTaskId -eq 'YourPhone.Start') 'Config Phone Link startup task id is not protected.'
Assert-Condition (@($config.RequiredAppStartupTasks | Where-Object { $_.PackageFamilyName -eq 'Microsoft.YourPhone_8wekyb3d8bbwe' -and $_.TaskId -eq 'YourPhone.Start' }).Count -eq 1) 'Phone Link packaged startup task must be required.'
Assert-Condition (@($config.RequiredAppStartupTasks | Where-Object { $_.PackageFamilyName -eq 'MicrosoftWindows.CrossDevice_cw5n1h2txyewy' -and $_.TaskId -eq 'CrossDevice.Start' }).Count -eq 1) 'Cross Device packaged startup task must be required.'
Assert-Condition (@($config.RequiredAppStartupTasks | Where-Object { $_.PackageFamilyName -like 'OpenAI.*' }).Count -eq 0) 'OpenAI packaged startup tasks must not be allowed.'
$content = Get-Content -LiteralPath $entryPoint -Raw
Assert-Condition ($content -match 'trayquiet-start\.vbs') 'Custom startup tasks must route through the hidden WScript launcher.'
Assert-Condition ($content -match 'wscript\.exe') 'Custom startup tasks must execute wscript.exe, not powershell.exe.'
Assert-Condition ($content -match '//B //Nologo') 'Custom startup tasks must use non-interactive WScript arguments.'
Assert-Condition ($content -match '120 0 25') 'Custom startup tasks must use an extended bounded tray-quiet suppress window with zero startup delay and fast interval.'
Assert-Condition ($content -notmatch 'Execute\s*=\s*\$powershellExe') 'Custom startup task specs must never execute powershell.exe directly.'
Assert-Condition ($content -match "\.PSObject\.Properties\['State'\]") 'Packaged startup inventory must access State defensively.'
Assert-Condition ($content -notmatch '\$props\.State') 'Packaged startup inventory must not access $props.State directly.'
foreach ($requiredName in @('FullScreenSnip')) {
    Assert-Condition (@($config.RequiredRegistryRun | Where-Object { $_.Name -eq $requiredName }).Count -eq 1) "Missing required Run entry: $requiredName"
}
foreach ($requiredTask in @('Autorun_current_ahk', 'ClawdBotTray', 'OpenSpeedy_Tray', 'Murmure_Tray')) {
    Assert-Condition (@($config.RequiredScheduledTasks | Where-Object { $_.Name -eq $requiredTask }).Count -eq 1) "Missing required scheduled task: $requiredTask"
}
Assert-Condition (@($config.RequiredScheduledTasks | Where-Object { $_.Name -eq 'OpenWhisper_Tray' }).Count -eq 0) 'OpenWhisper_Tray must not remain a required scheduled task.'
Assert-Condition ((@($config.RequiredRegistryRun | Where-Object { $_.Name -eq 'Phone' }).Count) -eq 0) 'Phone Run entry should be absent in the silent-start design.'
Assert-Condition ((@($config.RequiredRegistryRun | Where-Object { $_.Name -eq 'current.ahk' }).Count) -eq 0) 'current.ahk Run entry should be absent in the de-duplicated design.'
Assert-Condition ((@($config.ProtectedNames).Count) -eq 0) 'ProtectedNames should be empty; only exact required launchers should remain allowed.'
Assert-Condition (@($config.ExplicitDisableRules).Count -eq 0) 'Default config must not contain disable rules.'
Write-Host 'config ok'

$selfTest = & $entryPoint -SelfTest
Assert-Condition ($selfTest.Exists -and $selfTest.Function -eq 'allstart' -and $selfTest.Mode -eq 'SelfTest') 'SelfTest did not return expected fields.'
Assert-Condition ($selfTest.CustomConfig -eq $customConfigPath) 'SelfTest custom config path is wrong.'
Write-Host 'self-test ok'

$safetyMatches = Test-SafetyInspection -Path $entryPoint
Write-Host ("safety scan ok: {0} guarded mutation/logging references inspected" -f @($safetyMatches).Count)

& $managerContractPath -SkipLiveTaskState
Write-Host 'startup manager contract ok'

& $entryPoint -Mode Audit -DryRun
Write-Host 'audit dry-run ok'

& $entryPoint -Mode Restore -DryRun
Write-Host 'restore dry-run ok'

if (-not $SkipRuntimeVerify) {
    & $entryPoint -Mode Verify -DryRun
    Write-Host 'verify dry-run ok'
}

Write-Host 'ALLSTART_VALIDATION_PASS'
