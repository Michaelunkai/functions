#requires -version 5.0
<#
.SYNOPSIS
  Permanently fixes the old Microsoft Visual C++ 2005 Redistributable error:
  "The cluster size in this system is not supported."

.DESCRIPTION
  Old VC++ 2005/InstallShield installers can crash when TEMP/TMP points to exFAT/FAT/ReFS
  or a volume with an unsupported allocation-unit/cluster size. This script makes Windows
  use a safe local NTFS 4 KB temp folder (default C:\Temp) for the current process,
  the current user, and (when elevated) the machine. It also provides a wrapper to run
  old installers with the safe temp variables immediately.

  Compatible with Windows PowerShell 5.1. No PowerShell 7 syntax is used.

.USAGE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File F:\DOWNOADS\a.ps1
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File F:\DOWNOADS\a.ps1 -InstallerPath "F:\Downloads\vcredist_x86.exe","F:\Downloads\vcredist_x64.exe"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File F:\DOWNOADS\a.ps1 -AutoRunVCRedist
#>

[CmdletBinding()]
param(
    [string]$SafeTemp = "$env:SystemDrive\Temp",
    [string[]]$InstallerPath = @(),
    [switch]$AutoRunVCRedist,
    [switch]$SelfTestOnly,
    [switch]$Quiet
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-Status {
    param([string]$Message, [string]$Level = 'INFO')
    if (-not $Quiet) { Write-Host ("[{0}] {1}" -f $Level, $Message) }
}

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-VolumeFactsForPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrWhiteSpace($root)) { throw "Cannot determine drive root for: $Path" }
    $drive = $root.Substring(0,2)
    $result = New-Object PSObject -Property @{
        Path = $full
        Root = $root
        Drive = $drive
        FileSystem = $null
        BytesPerCluster = $null
        IsSupportedForLegacyInstallers = $false
        Reason = $null
    }

    try {
        $vol = Get-WmiObject Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $drive.Replace("'","''"))
        if ($vol) { $result.FileSystem = $vol.FileSystem }
    } catch { }

    if ($result.FileSystem -ne 'NTFS') {
        $result.Reason = "File system is $($result.FileSystem), not NTFS"
        return $result
    }

    try {
        $out = & fsutil fsinfo ntfsinfo $drive 2>$null
        foreach ($line in $out) {
            if ($line -match 'Bytes Per Cluster\s*:\s*([0-9]+)') {
                $result.BytesPerCluster = [int]$matches[1]
                break
            }
        }
    } catch { }

    if ($null -eq $result.BytesPerCluster) {
        $result.Reason = 'Could not read NTFS cluster size'
        return $result
    }
    if ($result.BytesPerCluster -ne 4096) {
        $result.Reason = "NTFS cluster size is $($result.BytesPerCluster), expected 4096"
        return $result
    }

    $result.IsSupportedForLegacyInstallers = $true
    $result.Reason = 'NTFS with 4096-byte clusters'
    return $result
}

function Ensure-SafeTempFolder {
    param([Parameter(Mandatory=$true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $full)) {
        New-Item -ItemType Directory -Path $full -Force | Out-Null
    }
    $item = Get-Item -LiteralPath $full -ErrorAction Stop
    if (-not $item.PSIsContainer) { throw "SafeTemp path exists but is not a directory: $full" }

    $facts = Get-VolumeFactsForPath -Path $full
    if (-not $facts.IsSupportedForLegacyInstallers) {
        throw "SafeTemp is not safe for legacy VC++ installers: $full ($($facts.Reason)). Choose an NTFS 4 KB cluster path such as C:\Temp."
    }

    try {
        $testFile = Join-Path $full ("vc2005-temp-test-{0}.tmp" -f ([guid]::NewGuid().ToString('N')))
        Set-Content -LiteralPath $testFile -Value 'ok' -Encoding ASCII
        Remove-Item -LiteralPath $testFile -Force
    } catch {
        throw "SafeTemp is not writable: $full ($($_.Exception.Message))"
    }
    return $full.TrimEnd('\')
}

function Set-EnvironmentValueSafe {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('User','Machine')][string]$Target,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Value
    )
    [Environment]::SetEnvironmentVariable($Name, $Value, $Target)
    $after = [Environment]::GetEnvironmentVariable($Name, $Target)
    if ($after -ne $Value) { throw "Failed to set $Target $Name to $Value (actual: $after)" }
}

function Send-EnvironmentBroadcast {
    # Notify Explorer/new processes about environment changes. Best-effort only.
    # Keep this intentionally non-blocking. Some broken systems hang while compiling Add-Type
    # or while broadcasting WM_SETTINGCHANGE, so the permanent registry environment change is
    # the authoritative fix and future processes/restarts will pick it up even if this is skipped.
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shell.Environment('USER').Item('TEMP') = [Environment]::GetEnvironmentVariable('TEMP','User')
        $shell.Environment('USER').Item('TMP')  = [Environment]::GetEnvironmentVariable('TMP','User')
    } catch { }
}

function Repair-VCRedist2005ClusterSizeError {
    [CmdletBinding()]
    param([string]$SafeTempPath = "$env:SystemDrive\Temp")

    Write-Status "Repairing legacy VC++/InstallShield temp location problem..."
    $safe = Ensure-SafeTempFolder -Path $SafeTempPath
    $safeFacts = Get-VolumeFactsForPath -Path $safe
    Write-Status "Safe temp verified: $safe ($($safeFacts.Reason))"

    $isAdmin = Test-IsAdmin
    $before = New-Object PSObject -Property @{
        ProcessTEMP = $env:TEMP
        ProcessTMP = $env:TMP
        UserTEMP = [Environment]::GetEnvironmentVariable('TEMP','User')
        UserTMP = [Environment]::GetEnvironmentVariable('TMP','User')
        MachineTEMP = [Environment]::GetEnvironmentVariable('TEMP','Machine')
        MachineTMP = [Environment]::GetEnvironmentVariable('TMP','Machine')
        IsAdmin = $isAdmin
    }

    # Current process: this fixes installers started from the same shell immediately.
    $env:TEMP = $safe
    $env:TMP = $safe

    # Current user: permanent for normal future shells/apps after restart/sign-out or environment broadcast.
    Set-EnvironmentValueSafe -Target User -Name TEMP -Value $safe
    Set-EnvironmentValueSafe -Target User -Name TMP -Value $safe

    # Machine: permanent for elevated/system-launched installers when script is run as admin.
    $machineChanged = $false
    if ($isAdmin) {
        Set-EnvironmentValueSafe -Target Machine -Name TEMP -Value $safe
        Set-EnvironmentValueSafe -Target Machine -Name TMP -Value $safe
        $machineChanged = $true
    } else {
        Write-Status "Not elevated: machine-wide TEMP/TMP not changed. Re-run as Administrator for all users/system installers." "WARN"
    }

    Send-EnvironmentBroadcast

    $after = New-Object PSObject -Property @{
        ProcessTEMP = $env:TEMP
        ProcessTMP = $env:TMP
        UserTEMP = [Environment]::GetEnvironmentVariable('TEMP','User')
        UserTMP = [Environment]::GetEnvironmentVariable('TMP','User')
        MachineTEMP = [Environment]::GetEnvironmentVariable('TEMP','Machine')
        MachineTMP = [Environment]::GetEnvironmentVariable('TMP','Machine')
        MachineChanged = $machineChanged
    }

    foreach ($name in @('TEMP','TMP')) {
        if ((Get-Item "env:$name").Value -ne $safe) { throw "Process $name did not update to $safe" }
        if ([Environment]::GetEnvironmentVariable($name,'User') -ne $safe) { throw "User $name did not update to $safe" }
        if ($isAdmin -and ([Environment]::GetEnvironmentVariable($name,'Machine') -ne $safe)) { throw "Machine $name did not update to $safe" }
    }

    Write-Status "Repair complete. New installers launched after this will use $safe instead of unsupported exFAT/FAT/large-cluster temp paths."
    return New-Object PSObject -Property @{ Before = $before; After = $after; SafeTempFacts = $safeFacts }
}

function Invoke-LegacyInstallerWithSafeTemp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$Arguments = ''
    )
    $safe = Ensure-SafeTempFolder -Path $env:TEMP
    if (-not (Test-Path -LiteralPath $Path)) { throw "Installer not found: $Path" }
    $src = (Resolve-Path -LiteralPath $Path).ProviderPath
    $work = Join-Path $safe 'LegacyInstallerSafeRun'
    if (-not (Test-Path -LiteralPath $work)) { New-Item -ItemType Directory -Path $work -Force | Out-Null }
    $dest = Join-Path $work ([IO.Path]::GetFileName($src))

    # Copying avoids old self-extractors reading/running from exFAT/Ventoy or other unsupported source volumes.
    Copy-Item -LiteralPath $src -Destination $dest -Force
    Unblock-File -LiteralPath $dest -ErrorAction SilentlyContinue

    Write-Status "Running installer from safe NTFS temp: $dest $Arguments"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $dest
    $psi.Arguments = $Arguments
    $psi.WorkingDirectory = $work
    $psi.UseShellExecute = $false
    $psi.EnvironmentVariables['TEMP'] = $safe
    $psi.EnvironmentVariables['TMP'] = $safe
    $p = [Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    Write-Status "Installer exit code: $($p.ExitCode)"
    return $p.ExitCode
}

function Find-VCRedistInstallersNearScript {
    $roots = @()
    if ($PSScriptRoot) { $roots += $PSScriptRoot }
    $roots += (Get-Location).Path
    $roots += 'F:\Downloads','F:\DOWNOADS','E:\games','F:\'
    $seen = @{}
    $found = @()
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        try {
            Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '(?i)(vcredist|vc_red|visual.*c).*2005|vcredist.*(x86|x64)\.exe|vc.*red.*\.exe' } |
                ForEach-Object {
                    if (-not $seen.ContainsKey($_.FullName)) { $seen[$_.FullName] = $true; $found += $_.FullName }
                }
        } catch { }
    }
    return $found
}

try {
    $repair = Repair-VCRedist2005ClusterSizeError -SafeTempPath $SafeTemp

    if (-not $SelfTestOnly) {
        $toRun = @()
        if ($InstallerPath -and $InstallerPath.Count -gt 0) { $toRun += $InstallerPath }
        elseif ($AutoRunVCRedist) { $toRun += (Find-VCRedistInstallersNearScript) }

        if ($toRun.Count -gt 0) {
            foreach ($installer in $toRun) { Invoke-LegacyInstallerWithSafeTemp -Path $installer | Out-Null }
        } elseif ($AutoRunVCRedist) {
            Write-Status "No VC++ redistributable installers found near the script/download folders." "WARN"
        }
    }

    Write-Host 'RESULT=PASS'
    Write-Host ("SAFE_TEMP={0}" -f $env:TEMP)
    Write-Host ("USER_TEMP={0}" -f ([Environment]::GetEnvironmentVariable('TEMP','User')))
    Write-Host ("USER_TMP={0}" -f ([Environment]::GetEnvironmentVariable('TMP','User')))
    Write-Host ("MACHINE_TEMP={0}" -f ([Environment]::GetEnvironmentVariable('TEMP','Machine')))
    Write-Host ("MACHINE_TMP={0}" -f ([Environment]::GetEnvironmentVariable('TMP','Machine')))
    exit 0
} catch {
    Write-Host 'RESULT=FAIL'
    Write-Host ("ERROR={0}" -f $_.Exception.Message)
    exit 1
}
