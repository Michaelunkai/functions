#requires -version 5.0
[CmdletBinding()]
param(
    [ValidateRange(1,240)]
    [int]$DurationMinutes = 10,
    [ValidateRange(30,7200)]
    [int]$TimeoutSeconds = 900,
    [switch]$NoGui
)

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$mainScript = Join-Path $scriptRoot 'a.ps1'
$reportRoot = Join-Path $scriptRoot 'reports'
$argsList = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $mainScript,
    '-Mode', 'FullStress',
    '-DurationMinutes', $DurationMinutes,
    '-TimeoutSeconds', $TimeoutSeconds,
    '-RootDir', $reportRoot
)
if ($NoGui) { $argsList += '-NoGui' }
& powershell.exe @argsList
exit $LASTEXITCODE
