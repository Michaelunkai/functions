[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SelfTest,
    [switch]$AutoReboot,
    [string]$SetupPath
)

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$script:Reports = Join-Path $script:Root 'reports'
$script:Runtime = Join-Path $script:Root 'runtime'
$script:Log = Join-Path $script:Reports 'zero-touch-main-windows11.log'
$script:Ps5 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $script:Ps5)) { $script:Ps5 = 'powershell.exe' }

function Write-ZtLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    New-Item -ItemType Directory -Path $script:Reports -Force | Out-Null
    ('{0} {1}' -f (Get-Date -Format s), $Message) | Add-Content -LiteralPath $script:Log -Encoding ASCII
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SetupCandidates {
    $setupName = 'setup' + '.exe'
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($SetupPath) { $candidates.Add($SetupPath) }
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if (-not $drive.IsReady) { continue }
        $candidates.Add((Join-Path $drive.RootDirectory.FullName $setupName))
        $candidates.Add((Join-Path $drive.RootDirectory.FullName ('sources\' + $setupName)))
    }
    foreach ($base in @('F:\Downloads', 'F:\ISO', "$env:USERPROFILE\Downloads", 'C:\ESD', 'C:\$WINDOWS.~BT\Sources')) {
        $candidates.Add((Join-Path $base $setupName))
    }
    $seen = @{}
    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        $full = [System.IO.Path]::GetFullPath($candidate)
        if ($seen.ContainsKey($full)) { continue }
        $seen[$full] = $true
        if (Test-Path -LiteralPath $full -PathType Leaf) { $full }
    }
}

function Resolve-WindowsSetup {
    foreach ($candidate in @(Get-SetupCandidates)) {
        $lower = $candidate.ToLowerInvariant()
        if ($lower -match '\\windows\\system32\\setup\.exe$') { continue }
        if ($lower -match '\\winsxs\\') { continue }
        return $candidate
    }
    throw 'No Windows 11 installer setup file was found automatically. Mount or place a Windows 11 ISO/USB installer, then run the same launcher again.'
}

function Register-PostBootCleanup {
    param([switch]$WhatIfOnly)
    $cleanup = Join-Path $script:Root 'scripts\Force-Delete-WindowsOld.ps1'
    if (-not (Test-Path -LiteralPath $cleanup)) { throw "Cleanup worker missing: $cleanup" }
    $taskName = 'ZeroTouchMainWindows11PostBootWindowsOldCleanup'
    $args = '-NoProfile -ExecutionPolicy Bypass -File "' + $cleanup + '" -SystemWorker'
    if ($WhatIfOnly) {
        Write-ZtLog ('DRYRUN would register SYSTEM task ' + $taskName + ' -> ' + $args)
        return
    }
    $action = New-ScheduledTaskAction -Execute $script:Ps5 -Argument $args
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    $trigger = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Trigger $trigger -Force | Out-Null
    Write-ZtLog ('REGISTERED postboot cleanup task ' + $taskName)
}

function Invoke-Setup {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedSetup,
        [switch]$WhatIfOnly
    )
    $args = @('/auto', 'upgrade', '/quiet', '/eula', 'accept', '/dynamicupdate', 'enable', '/copylogs', $script:Reports)
    if (-not $AutoReboot) { $args += '/noreboot' }
    Write-ZtLog ('SETUP_PATH ' + $ResolvedSetup)
    Write-ZtLog ('SETUP_ARGS ' + ($args -join ' '))
    if ($WhatIfOnly) {
        Write-Output ('DRYRUN setup=' + $ResolvedSetup)
        Write-Output ('DRYRUN args=' + ($args -join ' '))
        Write-Output 'DRYRUN no setup, reboot, BCD write, scheduled task write, or Windows.old deletion was executed.'
        return
    }
    $process = Start-Process -FilePath $ResolvedSetup -ArgumentList $args -Wait -PassThru
    Write-ZtLog ('SETUP_EXIT code=' + $process.ExitCode)
    exit $process.ExitCode
}

function Invoke-SelfTest {
    $scriptText = Get-Content -LiteralPath $PSCommandPath -Raw
    foreach ($forbidden in @(('Read' + '-Host'), ('pa' + 'use'))) {
        if ($scriptText -match [regex]::Escape($forbidden)) { throw "Forbidden interactive token found: $forbidden" }
    }
    if ($scriptText -notmatch '/auto'', ''upgrade') { throw 'Setup keep-mode arguments are missing.' }
    if ($scriptText -notmatch 'Register-PostBootCleanup') { throw 'Postboot cleanup registration is missing.' }
    Write-Output 'SELFTEST PASS Start-ZeroTouchMainWindows11.ps1'
}

if ($SelfTest) {
    Invoke-SelfTest
    exit 0
}

New-Item -ItemType Directory -Path $script:Reports,$script:Runtime -Force | Out-Null
Write-ZtLog ('START dryRun=' + $DryRun.IsPresent + ' autoReboot=' + $AutoReboot.IsPresent)

if (-not $DryRun -and -not (Test-IsAdmin)) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-AutoReboot')
    if ($SetupPath) { $argList += @('-SetupPath', $SetupPath) }
    Write-ZtLog 'ELEVATE relaunching as administrator'
    Start-Process -FilePath $script:Ps5 -ArgumentList $argList -Verb RunAs
    exit 0
}

$resolved = if ($DryRun -and -not $SetupPath) { '<auto-detected Windows 11 installer at real run>' } else { Resolve-WindowsSetup }
Register-PostBootCleanup -WhatIfOnly:$DryRun
Invoke-Setup -ResolvedSetup $resolved -WhatIfOnly:$DryRun
