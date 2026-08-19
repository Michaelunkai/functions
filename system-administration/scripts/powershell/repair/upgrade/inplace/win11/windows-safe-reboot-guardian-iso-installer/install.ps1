<#
.SYNOPSIS
  Installs Windows Safe Reboot Guardian from the release ISO.
.DESCRIPTION
  Copies the toolkit to ProgramData, creates stable launcher commands, and verifies the installed script.
  No reboot/shutdown is performed by this installer. The default install is per-user and does not require Administrator/UAC.
#>
[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$SelfTest,
    [switch]$Silent
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$AppName = 'WindowsSafeRebootGuardian'
$InstallRoot = Join-Path $env:LOCALAPPDATA $AppName
$SourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceFix = Join-Path $SourceRoot 'fix.ps1'
$TargetFix = Join-Path $InstallRoot 'fix.ps1'
$RunCmd = Join-Path $InstallRoot 'Run-WindowsSafeRebootGuardian.cmd'
$MaxCmd = Join-Path $InstallRoot 'Run-WindowsSafeRebootGuardian-MaximumProtection.cmd'
$StartMenuDir = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Windows Safe Reboot Guardian'

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Source {
    if (-not (Test-Path -LiteralPath $SourceFix -PathType Leaf)) {
        throw "Missing source fix.ps1 beside installer: $SourceFix"
    }
}

function Test-FixParse([string]$Path) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $messages = ($errors | ForEach-Object { $_.Message }) -join '; '
        throw "PowerShell parser errors in ${Path}: $messages"
    }
}

function Invoke-SelfTest {
    Assert-Source
    Test-FixParse -Path $SourceFix
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $SourceFix -SelfTest | Out-String | Write-Host
    Write-Host 'INSTALLER_SELFTEST_OK'
}

function Invoke-Install {
    Assert-Source
    Test-FixParse -Path $SourceFix
    New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
    Copy-Item -LiteralPath $SourceFix -Destination $TargetFix -Force
    Test-FixParse -Path $TargetFix

    $run = '@echo off' + "`r`n" + 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ProgramData%\WindowsSafeRebootGuardian\fix.ps1" %*' + "`r`n"
    [IO.File]::WriteAllText($RunCmd, $run, [Text.Encoding]::ASCII)
    $max = '@echo off' + "`r`n" + 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ProgramData%\WindowsSafeRebootGuardian\fix.ps1" -MaximumProtection %*' + "`r`n"
    [IO.File]::WriteAllText($MaxCmd, $max, [Text.Encoding]::ASCII)

    New-Item -ItemType Directory -Force -Path $StartMenuDir | Out-Null
    $shortcutPath = Join-Path $StartMenuDir 'Windows Safe Reboot Guardian.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = 'powershell.exe'
    $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $TargetFix + '"'
    $shortcut.WorkingDirectory = $InstallRoot
    $shortcut.IconLocation = 'powershell.exe,0'
    $shortcut.Save()

    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $TargetFix).Hash
    Write-Host "INSTALLED_OK"
    Write-Host "InstallRoot=$InstallRoot"
    Write-Host "RunCommand=$RunCmd"
    Write-Host "SHA256=$hash"
}

if ($SelfTest) { Invoke-SelfTest; exit 0 }
if ($Install) { Invoke-Install; exit 0 }
Write-Host 'Usage: powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Install'
Write-Host '       powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1 -SelfTest'
exit 0
