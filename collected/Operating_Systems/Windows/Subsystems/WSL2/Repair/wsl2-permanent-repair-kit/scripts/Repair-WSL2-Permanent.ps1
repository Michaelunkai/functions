[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$AuditOnly,
    [switch]$DeepVerify,
    [switch]$NoDownload,
    [string]$WslVersion = '2.7.10',
    [string]$InstallRoot = 'C:\Program Files\WSL',
    [string]$ProjectRoot,
    [int]$PopupWatchSeconds = 90
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        throw 'Cannot determine script path. Run this script from a saved .ps1 file, not from pasted inline text.'
    }
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)
}

$LogRoot = Join-Path $ProjectRoot 'logs'
$LogPath = Join-Path $LogRoot ("Repair-WSL-And-WSLg-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    if (Test-Path -LiteralPath $LogRoot) {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    }
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-LoggedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [int[]]$AllowedExitCodes = @(0)
    )
    Write-Log ("Running: {0} {1}" -f $FilePath, ($ArgumentList -join ' '))
    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -NoNewWindow
    Write-Log ("Exit code: {0}" -f $process.ExitCode)
    if ($process.ExitCode -notin $AllowedExitCodes) {
        throw "{0} failed with exit code {1}" -f $FilePath, $process.ExitCode
    }
}

function Add-WindowApi {
    if ('Codex.WslRepair.WindowApi' -as [type]) {
        return
    }
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

namespace Codex.WslRepair {
    public static class WindowApi {
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
        [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, UInt32 Msg, IntPtr wParam, IntPtr lParam);
        public const UInt32 WM_CLOSE = 0x0010;
    }
}
'@
}

function Close-RemoteDesktopPopups {
    param([int]$Seconds = 0)
    Add-WindowApi
    $deadline = (Get-Date).AddSeconds([Math]::Max(0, $Seconds))
    $closed = 0
    do {
        $handles = New-Object System.Collections.Generic.List[IntPtr]
        [Codex.WslRepair.WindowApi]::EnumWindows({
            param([IntPtr]$hWnd, [IntPtr]$lParam)
            if (-not [Codex.WslRepair.WindowApi]::IsWindowVisible($hWnd)) { return $true }
            $titleBuilder = [Text.StringBuilder]::new(512)
            $classBuilder = [Text.StringBuilder]::new(256)
            [void][Codex.WslRepair.WindowApi]::GetWindowText($hWnd, $titleBuilder, $titleBuilder.Capacity)
            [void][Codex.WslRepair.WindowApi]::GetClassName($hWnd, $classBuilder, $classBuilder.Capacity)
            $title = $titleBuilder.ToString()
            $class = $classBuilder.ToString()
            if ($title -match 'Remote Desktop|msrdc|RemoteApp' -or (($class -eq '#32770') -and ($title -match 'Remote'))) {
                $handles.Add($hWnd)
            }
            return $true
        }, [IntPtr]::Zero) | Out-Null

        foreach ($handle in $handles) {
            [void][Codex.WslRepair.WindowApi]::PostMessage($handle, [Codex.WslRepair.WindowApi]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)
            $closed++
        }
        if ($Seconds -le 0) { break }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    if ($closed -gt 0) {
        Write-Log ("Closed Remote Desktop popup/window count: {0}" -f $closed)
    }
    return $closed
}

function Stop-StaleWslgClients {
    $targets = Get-CimInstance Win32_Process -Filter "Name = 'msrdc.exe' OR Name = 'mstsc.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match '/wslg|wslg\.rdp|WSLDVC_PACKAGE|hvsocketserviceid' }
    foreach ($target in $targets) {
        Write-Log ("Stopping stale WSLg Remote Desktop client PID {0}: {1}" -f $target.ProcessId, $target.CommandLine)
        Stop-Process -Id $target.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Get-WslMsiUrl {
    param([Parameter(Mandatory)][string]$Version)
    return 'https://github.com/microsoft/WSL/releases/download/{0}/wsl.{0}.0.x64.msi' -f $Version
}

function Get-DefaultWslgRdpContent {
    @'
screen mode id:i:1
use multimon:i:0
desktopwidth:i:1920
desktopheight:i:1080
session bpp:i:32
winposstr:s:0,1,0,0,1920,1080
compression:i:1
keyboardhook:i:2
audiocapturemode:i:0
videoplaybackmode:i:1
connection type:i:7
networkautodetect:i:0
bandwidthautodetect:i:0
displayconnectionbar:i:0
disable wallpaper:i:1
allow font smoothing:i:1
allow desktop composition:i:1
disable full window drag:i:0
disable menu anims:i:0
disable themes:i:0
disable cursor setting:i:0
bitmapcachepersistenable:i:1
full address:s:WSLg
prompt for credentials:i:0
authentication level:i:0
enablecredsspsupport:i:0
redirectclipboard:i:1
redirectprinters:i:0
redirectcomports:i:0
redirectsmartcards:i:0
redirectwebauthn:i:0
drivestoredirect:s:
autoreconnection enabled:i:0
administrative session:i:0
remoteapplicationmode:i:0
alternate shell:s:
shell working directory:s:
gatewayhostname:s:
gatewayusagemethod:i:4
gatewaycredentialssource:i:4
gatewayprofileusagemethod:i:0
promptcredentialonce:i:0
use redirection server name:i:0
'@
}

function Get-WindowsPowerShell5Path {
    $path = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Windows PowerShell 5 was not found at $path"
    }
    return $path
}

function Get-SystemWslPath {
    $path = Join-Path $env:WINDIR 'System32\wsl.exe'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Windows system WSL shim was not found at $path"
    }
    return $path
}

function Backup-IfExists {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    $backup = '{0}.bak-{1}' -f $Path, (Get-Date -Format 'yyyyMMdd-HHmmss')
    Copy-Item -LiteralPath $Path -Destination $backup -Force
    Write-Log ("Backed up {0} to {1}" -f $Path, $backup)
    return $backup
}

function Repair-WslgRdp {
    param([Parameter(Mandatory)][string]$Root)
    $rdpPath = Join-Path $Root 'wslg.rdp'
    $configPath = Join-Path $env:USERPROFILE '.wslgconfig'

    if (-not (Test-Path -LiteralPath $Root)) {
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
    }

    $needsWrite = $true
    if (Test-Path -LiteralPath $rdpPath) {
        $existing = Get-Content -LiteralPath $rdpPath -Raw -ErrorAction SilentlyContinue
        $needsWrite = [string]::IsNullOrWhiteSpace($existing) -or ($existing -notmatch 'screen mode id:i:') -or ($existing -notmatch 'authentication level:i:')
        if ($needsWrite) {
            Backup-IfExists -Path $rdpPath | Out-Null
        }
    }

    if ($needsWrite) {
        Write-Log ("Writing valid WSLg RDP file: {0}" -f $rdpPath)
        [IO.File]::WriteAllText($rdpPath, (Get-DefaultWslgRdpContent), [Text.Encoding]::ASCII)
    } else {
        Write-Log ("Existing WSLg RDP file already looks valid: {0}" -f $rdpPath)
    }

    $config = @'
[system-distro-env]
WSL2_RDP_CONFIG_OVERRIDE=wslg.rdp
'@
    $configNeedsWrite = $true
    if (Test-Path -LiteralPath $configPath) {
        $existingConfig = Get-Content -LiteralPath $configPath -Raw -ErrorAction SilentlyContinue
        $configNeedsWrite = ($existingConfig -notmatch '(?m)^\[system-distro-env\]\s*$') -or ($existingConfig -notmatch '(?m)^WSL2_RDP_CONFIG_OVERRIDE=wslg\.rdp\s*$')
        if ($configNeedsWrite) {
            Backup-IfExists -Path $configPath | Out-Null
        }
    }
    if ($configNeedsWrite) {
        Write-Log ("Writing WSLg config override: {0}" -f $configPath)
        [IO.File]::WriteAllText($configPath, $config, [Text.Encoding]::ASCII)
    } else {
        Write-Log ("Existing WSLg config override already present: {0}" -f $configPath)
    }

    if (-not (Test-Path -LiteralPath $rdpPath)) {
        throw "WSLg RDP file was not created: $rdpPath"
    }
}

function Repair-AppPathRegistration {
    param([Parameter(Mandatory)][string]$Root)
    $wslExe = Join-Path $Root 'wsl.exe'
    if (-not (Test-Path -LiteralPath $wslExe)) {
        Write-Log ("WSL package executable not present yet for App Paths registration: {0}" -f $wslExe)
        return
    }
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\wsl.exe'
    New-Item -Path $key -Force | Out-Null
    Set-ItemProperty -Path $key -Name '(default)' -Value $wslExe
    Set-ItemProperty -Path $key -Name 'Path' -Value $Root
    Write-Log ("Registered HKCU App Paths wsl.exe -> {0}" -f $wslExe)
}

function Repair-WslServices {
    param([Parameter(Mandatory)][string]$Root)
    $serviceExe = Join-Path $Root 'wslservice.exe'
    if (-not (Test-Path -LiteralPath $serviceExe)) {
        Write-Log ("WSL service executable is not present yet: {0}" -f $serviceExe)
        return
    }
    Invoke-LoggedProcess -FilePath sc.exe -ArgumentList @('config', 'WSLService', 'start=', 'auto', 'binPath=', ('"{0}"' -f $serviceExe)) -AllowedExitCodes @(0)
    Invoke-LoggedProcess -FilePath sc.exe -ArgumentList @('failure', 'WSLService', 'reset=', '86400', 'actions=', 'restart/60000/restart/60000/none/60000') -AllowedExitCodes @(0)
}

function Repair-RdpAssociation {
    $mstsc = Join-Path $env:WINDIR 'System32\mstsc.exe'
    if (-not (Test-Path -LiteralPath $mstsc)) {
        Write-Log "mstsc.exe not found; skipping .rdp association repair"
        return
    }
    Invoke-LoggedProcess -FilePath cmd.exe -ArgumentList @('/c', 'assoc', '.rdp=RDP.File') -AllowedExitCodes @(0)
    Invoke-LoggedProcess -FilePath cmd.exe -ArgumentList @('/c', 'ftype', ('RDP.File="{0}" "%1"' -f $mstsc)) -AllowedExitCodes @(0)
    Write-Log 'Repaired .rdp file association to mstsc.exe'
}

function Get-WslDiagnostics {
    param([Parameter(Mandatory)][string]$Root)
    [ordered]@{
        Timestamp = (Get-Date).ToString('o')
        ProjectRoot = $ProjectRoot
        InstallRoot = $Root
        SystemWsl = (Join-Path $env:WINDIR 'System32\wsl.exe')
        SystemWslExists = (Test-Path -LiteralPath (Join-Path $env:WINDIR 'System32\wsl.exe'))
        PackageWslExists = (Test-Path -LiteralPath (Join-Path $Root 'wsl.exe'))
        WslgExeExists = (Test-Path -LiteralPath (Join-Path $Root 'wslg.exe'))
        WslgRdpExists = (Test-Path -LiteralPath (Join-Path $Root 'wslg.rdp'))
        MstscExists = (Test-Path -LiteralPath (Join-Path $env:WINDIR 'System32\mstsc.exe'))
        MsrdcExists = (Test-Path -LiteralPath (Join-Path $Root 'msrdc.exe'))
        WslService = (Get-Service WSLService -ErrorAction SilentlyContinue | Select-Object -First 1 Name, Status, StartType)
        LxssManager = (Get-Service LxssManager -ErrorAction SilentlyContinue | Select-Object -First 1 Name, Status, StartType)
        VmCompute = (Get-Service vmcompute -ErrorAction SilentlyContinue | Select-Object -First 1 Name, Status, StartType)
    }
}

function Save-WslDiagnostics {
    param([Parameter(Mandatory)][string]$Root)
    $diagPath = Join-Path $LogRoot ("diagnostics-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $diag = Get-WslDiagnostics -Root $Root
    $diag | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $diagPath -Encoding UTF8
    Write-Log ("Saved diagnostics: {0}" -f $diagPath)
}

function Test-RepairScript {
    $errors = @()
    $url = Get-WslMsiUrl -Version $WslVersion
    if ($url -notmatch '^https://github\.com/microsoft/WSL/releases/download/[0-9]+\.[0-9]+\.[0-9]+/wsl\.[0-9]+\.[0-9]+\.[0-9]+\.0\.x64\.msi$') {
        $errors += "Unexpected MSI URL: $url"
    }
    $rdp = Get-DefaultWslgRdpContent
    foreach ($needle in @('screen mode id:i:', 'authentication level:i:', 'redirectclipboard:i:', 'full address:s:WSLg')) {
        if ($rdp -notmatch [regex]::Escape($needle)) {
            $errors += "RDP template missing $needle"
        }
    }
    if (-not (Get-Command dism.exe -ErrorAction SilentlyContinue)) {
        $errors += 'dism.exe is not available'
    }
    if (-not (Test-Path -LiteralPath "$env:WINDIR\System32\msiexec.exe")) {
        $errors += 'msiexec.exe is not available'
    }
    try {
        Add-WindowApi
    } catch {
        $errors += "Window popup API failed to compile: $($_.Exception.Message)"
    }
    if ($errors.Count -gt 0) {
        $errors | ForEach-Object { Write-Error $_ }
        exit 1
    }
    Write-Host 'SELFTEST_OK'
    Write-Host ("MSI_URL={0}" -f $url)
    Write-Host ("TARGET_RDP={0}" -f (Join-Path $InstallRoot 'wslg.rdp'))
    Write-Host ("PROJECT_ROOT={0}" -f $ProjectRoot)
}

if ($SelfTest) {
    Test-RepairScript
    return
}

if ($AuditOnly) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    Write-Log 'Starting WSL audit-only check'
    Save-WslDiagnostics -Root $InstallRoot
    $required = @(
        (Join-Path $InstallRoot 'wsl.exe'),
        (Join-Path $InstallRoot 'wslg.exe'),
        (Join-Path $InstallRoot 'msrdc.exe'),
        (Join-Path $InstallRoot 'wslg.rdp'),
        (Join-Path $env:WINDIR 'System32\wsl.exe'),
        (Join-Path $env:WINDIR 'System32\mstsc.exe')
    )
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_) })
    if ($missing.Count -gt 0) {
        Write-Host 'AUDIT_NEEDS_REPAIR'
        $missing | ForEach-Object { Write-Host ("MISSING={0}" -f $_) }
        exit 2
    }
    & (Get-SystemWslPath) --status
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("AUDIT_WSL_STATUS_FAILED={0}" -f $LASTEXITCODE)
        exit 3
    }
    Write-Host 'AUDIT_OK'
    return
}

if (-not (Test-IsAdmin)) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($AuditOnly) { $argList += '-AuditOnly' }
    if ($DeepVerify) { $argList += '-DeepVerify' }
    if ($NoDownload) { $argList += '-NoDownload' }
    if ($WslVersion) { $argList += @('-WslVersion', $WslVersion) }
    if ($InstallRoot) { $argList += @('-InstallRoot', $InstallRoot) }
    if ($ProjectRoot) { $argList += @('-ProjectRoot', $ProjectRoot) }
    Start-Process -FilePath (Get-WindowsPowerShell5Path) -Verb RunAs -ArgumentList $argList -Wait
    return
}

New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
Write-Log 'Starting WSL and WSLg repair'
Write-Log ("Log file: {0}" -f $LogPath)
Close-RemoteDesktopPopups -Seconds 2 | Out-Null
Stop-StaleWslgClients

$workDir = Join-Path $ProjectRoot 'cache'
$msi = Join-Path $workDir ("wsl.{0}.0.x64.msi" -f $WslVersion)
$msiUrl = Get-WslMsiUrl -Version $WslVersion

New-Item -ItemType Directory -Path $workDir -Force | Out-Null

if (-not $NoDownload) {
    Write-Log ("Downloading WSL MSI from {0}" -f $msiUrl)
    try {
        Invoke-WebRequest -Uri $msiUrl -OutFile $msi -UseBasicParsing
    } catch {
        Write-Log ("Invoke-WebRequest failed: {0}" -f $_.Exception.Message)
        if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
            Start-BitsTransfer -Source $msiUrl -Destination $msi
        } else {
            throw
        }
    }
}

if (-not (Test-Path -LiteralPath $msi)) {
    throw "WSL MSI not found: $msi"
}

Invoke-LoggedProcess -FilePath dism.exe -ArgumentList @('/online', '/enable-feature', '/featurename:Microsoft-Windows-Subsystem-Linux', '/all', '/norestart') -AllowedExitCodes @(0, 3010)
Invoke-LoggedProcess -FilePath dism.exe -ArgumentList @('/online', '/enable-feature', '/featurename:VirtualMachinePlatform', '/all', '/norestart') -AllowedExitCodes @(0, 3010)

Write-Log 'Stopping WSL before MSI repair'
& (Get-SystemWslPath) --shutdown 2>$null
Stop-Service WSLService -Force -ErrorAction SilentlyContinue

Invoke-LoggedProcess -FilePath msiexec.exe -ArgumentList @('/i', $msi, '/qn', '/norestart') -AllowedExitCodes @(0, 3010)

Repair-WslgRdp -Root $InstallRoot
Repair-AppPathRegistration -Root $InstallRoot
Repair-WslServices -Root $InstallRoot
Repair-RdpAssociation
Close-RemoteDesktopPopups -Seconds 5 | Out-Null
Stop-StaleWslgClients

Write-Log 'Starting WSL service'
Start-Service WSLService -ErrorAction SilentlyContinue

Write-Log 'Verifying WSL install paths'
foreach ($requiredPath in @(
    (Join-Path $InstallRoot 'wsl.exe'),
    (Join-Path $InstallRoot 'wslg.exe'),
    (Join-Path $InstallRoot 'msrdc.exe'),
    (Join-Path $InstallRoot 'wslg.rdp'),
    (Get-SystemWslPath)
)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required WSL file is missing after repair: $requiredPath"
    }
    Write-Log ("Verified file exists: {0}" -f $requiredPath)
}

Write-Log 'Verifying wsl --status'
& (Get-SystemWslPath) --status
if ($LASTEXITCODE -ne 0) {
    throw "wsl --status failed after repair with exit code $LASTEXITCODE"
}

if ($DeepVerify) {
    Write-Log 'Deep verification: listing registered WSL distributions'
    & (Get-SystemWslPath) -l -v
    if ($LASTEXITCODE -ne 0) {
        throw "wsl -l -v failed after repair with exit code $LASTEXITCODE"
    }
}

Save-WslDiagnostics -Root $InstallRoot
Close-RemoteDesktopPopups -Seconds $PopupWatchSeconds | Out-Null

Write-Log 'Repair complete'
Write-Host "REPAIR_OK"
Write-Host "LOG=$LogPath"
