[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$entryPoint = Join-Path $root 'Invoke-allstart2.ps1'
$customConfigPath = Join-Path $root 'allstart2.custom.psd1'
$launcherPath = Join-Path $root 'Invoke-custom-startup-target.ps1'
$managerPath = Join-Path (Split-Path -Parent $root) 'Invoke-startup-custom-manager.ps1'
$managerContractPath = Join-Path (Split-Path -Parent $root) 'Test-startup-custom-manager.ps1'
$managerContent = Get-Content -LiteralPath $managerPath -Raw
$content = Get-Content -LiteralPath $entryPoint -Raw
$quietLauncherPath = 'C:\Users\micha\.claude\scripts\Start-TrayQuietApp.ps1'
$quietWin32DllPath = 'C:\Users\micha\.claude\scripts\TrayQuietWin32.dll'
$quietVbsLauncherPath = 'C:\Users\micha\.claude\scripts\trayquiet-start.vbs'
$allowedNamesBlock = [regex]::Match($content, 'AllowedNames\s*=\s*@\((?<body>.*?)\)\s*}', [System.Text.RegularExpressions.RegexOptions]::Singleline).Groups['body'].Value
$requiredRunBlock = [regex]::Match($content, 'RequiredRegistryRun\s*=\s*@\((?<body>.*?)\)\s*RequiredScheduledTasks', [System.Text.RegularExpressions.RegexOptions]::Singleline).Groups['body'].Value

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

Write-Host '== allstart2 validation =='

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
Assert-Condition ($quietVbsLauncherContent -match 'suppressSeconds = "120"') 'Hidden WScript launcher default suppress window must be 120 seconds in allstart2.'
Assert-Condition ($quietVbsLauncherContent -match 'WScript\.Shell') 'Hidden WScript launcher must use WScript.Shell.'
Assert-Condition ($quietVbsLauncherContent -match 'shell\.Run command, 0, False') 'Hidden WScript launcher must start PowerShell with a hidden window style.'
Import-PowerShellDataFile -LiteralPath $customConfigPath | Out-Null

Assert-Condition ($content -match 'trayquiet-start\.vbs') 'Custom startup tasks must route through the hidden WScript launcher in allstart2.'
Assert-Condition ($content -match 'wscript\.exe') 'Custom startup tasks must execute wscript.exe, not powershell.exe, in allstart2.'
Assert-Condition ($content -match '//B //Nologo') 'Custom startup tasks must use non-interactive WScript arguments in allstart2.'
Assert-Condition ($content -match '120 0 25') 'Custom startup tasks must use an extended bounded tray-quiet suppress window with zero startup delay and fast interval in allstart2.'
Assert-Condition ($content -notmatch 'Execute\s*=\s*\$powershellExe') 'Custom startup task specs must never execute powershell.exe directly in allstart2.'
Assert-Condition ($content -match 'Invoke-AllStartTwoImmediateLaunch') 'allstart2 must force-launch every allowlisted startup item immediately after registration.'
Assert-Condition ($content -match 'Start-ScheduledTask\s+-TaskName\s+\$taskName') 'allstart2 must immediately start every required scheduled task.'
Assert-Condition ($content -match 'Start-AllStartTwoRequiredRunEntry') 'allstart2 must immediately start every required Run entry.'
Assert-Condition ($content -match 'Test-AllStartTwoLauncherArtifacts') 'allstart2 must validate the hidden tray-quiet launcher artifact chain before task registration.'
Assert-Condition ($content -match "PhoneLinkStartupTaskId\s*=\s*'YourPhone\.Start'") 'Phone Link startup task id is not pinned in allstart2.'
Assert-Condition ($content -match "PackageFamilyName\s*=\s*'Microsoft\.YourPhone_8wekyb3d8bbwe'\s*;\s*TaskId\s*=\s*'YourPhone\.Start'") 'Phone Link packaged startup task must be required in allstart2.'
Assert-Condition ($content -match "PackageFamilyName\s*=\s*'MicrosoftWindows\.CrossDevice_cw5n1h2txyewy'\s*;\s*TaskId\s*=\s*'CrossDevice\.Start'") 'Cross Device packaged startup task must be required in allstart2.'
Assert-Condition ($content -notmatch "PackageFamilyName\s*=\s*'OpenAI\.") 'OpenAI packaged startup tasks must not be allowed in allstart2.'
Assert-Condition ($content -match "\.PSObject\.Properties\['State'\]") 'Packaged startup inventory must access State defensively in allstart2.'
Assert-Condition ($content -notmatch '\$props\.State') 'Packaged startup inventory must not access $props.State directly in allstart2.'
Assert-Condition ($requiredRunBlock -match "Name\s*=\s*'FullScreenSnip'") 'FullScreenSnip should be the only required Run entry in allstart2.'
Assert-Condition ($requiredRunBlock -notmatch "Name\s*=\s*'Phone'") 'Phone Run entry should be absent in allstart2.'
Assert-Condition ($requiredRunBlock -notmatch "Name\s*=\s*'current\.ahk'") 'current.ahk Run entry should be absent in allstart2.'
Assert-Condition ($allowedNamesBlock -notmatch "'SecurityHealth'") 'SecurityHealth should not remain in allstart2 allowed names.'
Assert-Condition ($allowedNamesBlock -notmatch "'RtkAudUService'") 'RtkAudUService should not remain in allstart2 allowed names.'
Write-Host 'content checks ok'

& $managerContractPath -SkipProfileBinding -SkipLiveTaskState
Write-Host 'startup manager contract ok'

$selfTest = & $entryPoint -SelfTest
Assert-Condition ($selfTest.Exists -and $selfTest.Function -eq 'allstart2' -and $selfTest.Mode -eq 'SelfTest') 'SelfTest did not return expected fields.'
Assert-Condition ($selfTest.CustomConfig -eq $customConfigPath) 'SelfTest custom config path is wrong.'
Write-Host 'self-test ok'

& $entryPoint -Mode Startup -DryRun
Write-Host 'startup dry-run ok'

& $entryPoint -Mode Verify -DryRun
Write-Host 'verify dry-run ok'

Write-Host 'ALLSTART2_VALIDATION_PASS'
