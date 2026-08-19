[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SelfTest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$registryWrites = @(
    @{ Path = 'SYSTEM\CurrentControlSet\Services\i8042prt\Parameters'; Name = 'CrashOnCtrlScroll'; Value = 1 },
    @{ Path = 'SYSTEM\CurrentControlSet\Services\kbdhid\Parameters'; Name = 'CrashOnCtrlScroll'; Value = 1 },
    @{ Path = 'SYSTEM\CurrentControlSet\Services\hyperkbd\Parameters'; Name = 'CrashOnCtrlScroll'; Value = 1 },
    @{ Path = 'SYSTEM\CurrentControlSet\Control\CrashControl'; Name = 'AutoReboot'; Value = 1 },
    @{ Path = 'SYSTEM\CurrentControlSet\Control\CrashControl'; Name = 'CrashDumpEnabled'; Value = 0 }
)

function Test-RunningAsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-LocalMachineDword {
    param(
        [Parameter(Mandatory = $true)][string]$SubKeyPath,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Value
    )

    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Default
    )

    try {
        $key = $baseKey.CreateSubKey($SubKeyPath)
        if ($null -eq $key) {
            throw "Could not open HKLM\$SubKeyPath for writing."
        }

        try {
            $key.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]::DWord)
        }
        finally {
            $key.Dispose()
        }
    }
    finally {
        $baseKey.Dispose()
    }
}

if ($SelfTest) {
    $scriptPath = $MyInvocation.MyCommand.Path
    [pscustomobject]@{
        ScriptPath = $scriptPath
        ScriptDrive = ([System.IO.Path]::GetPathRoot($scriptPath))
        UsesExternalExecutables = $false
        RegistryWriteCount = $registryWrites.Count
        Trigger = 'Hold right Ctrl and press Scroll Lock twice after reboot'
        RequiresAdministrator = $true
        RequiresRebootBeforeHotkeyWorks = $true
    }
    return
}

if (-not (Test-RunningAsAdministrator)) {
    throw 'Run this from an elevated Windows PowerShell 5 session. HKLM writes require administrator rights.'
}

foreach ($write in $registryWrites) {
    $target = 'HKLM:\' + $write.Path + '\' + $write.Name
    if ($PSCmdlet.ShouldProcess($target, 'Set DWORD to ' + $write.Value)) {
        Set-LocalMachineDword -SubKeyPath $write.Path -Name $write.Name -Value $write.Value
        Write-Host ("Set {0} = {1}" -f $target, $write.Value)
    }
}

Write-Host 'Crash hotkey configured. Reboot once, then hold right Ctrl and press Scroll Lock twice to trigger a crash and automatic reboot.'
