[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$main = Join-Path $root 'scripts\Start-ZeroTouchMainWindows11.ps1'
$cleanup = Join-Path $root 'scripts\Force-Delete-WindowsOld.ps1'
$launcher = Join-Path $root 'RUN-ZERO-TOUCH-MAIN-WINDOWS11.cmd'

foreach ($path in @($main, $cleanup, $launcher)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing required file: $path" }
}

foreach ($script in @($main, $cleanup)) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw ('Parse failed for ' + $script + ': ' + ($errors | Select-Object -First 1 -ExpandProperty Message)) }
    $text = Get-Content -LiteralPath $script -Raw
    foreach ($forbidden in @('Read-Host', 'pause')) {
        if ($text -match [regex]::Escape($forbidden)) { throw "Forbidden interactive token '$forbidden' in $script" }
    }
}

$mainText = Get-Content -LiteralPath $main -Raw
foreach ($required in @("'/auto', 'upgrade'", "'/quiet'", "'/eula', 'accept'", 'Register-PostBootCleanup', 'ZeroTouchMainWindows11PostBootWindowsOldCleanup')) {
    if ($mainText -notmatch [regex]::Escape($required)) { throw "Missing required main-script marker: $required" }
}

$cleanupText = Get-Content -LiteralPath $cleanup -Raw
foreach ($required in @('C:\Windows.old', 'SYSTEM_TASK_RUN', 'DELEGATED cleanup to SYSTEM worker', 'SKIP target already absent', 'DONE target absent')) {
    if ($cleanupText -notmatch [regex]::Escape($required)) { throw "Missing cleanup marker: $required" }
}

& $main -SelfTest
& $main -DryRun -AutoReboot
& $cleanup -DryRun

Write-Output 'TEST PASS zero-touch-main-windows11'
