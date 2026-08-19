[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$SelfTest,
    [switch]$SkipDownload,
    [switch]$SkipInstall,
    [switch]$SkipReindex,
    [switch]$AllowDestructiveRepair
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host ('[EverythingFix] ' + $Message)
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-EverythingStableDownload {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
    $page = (Invoke-WebRequest -UseBasicParsing 'https://www.voidtools.com/downloads/').Content
    $match = [regex]::Match($page, 'Everything-\d+\.\d+\.\d+\.\d+\.x64-Setup\.exe')
    if (-not $match.Success) {
        throw 'Could not find latest stable x64 Everything setup on voidtools downloads page.'
    }

    [pscustomobject]@{
        FileName = $match.Value
        Url = 'https://www.voidtools.com/' + $match.Value
    }
}

function Stop-EverythingProcessesAndService {
    Get-Process everything -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $service = Get-CimInstance Win32_Service -Filter "Name='Everything'" -ErrorAction SilentlyContinue
    if ($service) {
        cmd /c 'sc stop Everything >nul 2>nul'
        cmd /c 'sc delete Everything >nul 2>nul'
    }

    for ($i = 0; $i -lt 45; $i++) {
        Get-Process everything -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        $service = Get-CimInstance Win32_Service -Filter "Name='Everything'" -ErrorAction SilentlyContinue
        if (-not $service) {
            return
        }
        Start-Sleep -Seconds 2
    }

    throw 'Everything service stayed present after delete wait. Close every Everything window and rerun.'
}

function Backup-And-Remove-StaleEverythingState {
    $stamp = Get-Date -Format yyyyMMdd_HHmmss
    $backup = Join-Path $env:LOCALAPPDATA ('EverythingRepairBackup_' + $stamp)
    New-Item -ItemType Directory -Force -Path $backup | Out-Null

    $targets = @(
        (Join-Path $env:APPDATA 'Everything\Everything.ini'),
        (Join-Path $env:LOCALAPPDATA 'Everything\Everything.db'),
        'F:\backup\windowsapps\installed\Everything\Everything.ini',
        'F:\backup\windowsapps\installed\Everything\Everything.db'
    )

    foreach ($target in $targets) {
        if (Test-Path -LiteralPath $target) {
            Copy-Item -LiteralPath $target -Destination (Join-Path $backup ((Split-Path $target -Leaf) + '.bak')) -Force
            Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        }
    }

    return $backup
}

function Get-EverythingExe {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Everything\Everything.exe'),
        'F:\backup\windowsapps\installed\Everything\Everything.exe'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw 'Everything.exe not found after install.'
}

function Install-Or-UpdateEverything {
    param(
        [string]$InstallerPath
    )

    Write-Step 'Installing current stable Everything silently.'
    Start-Process -FilePath $InstallerPath -ArgumentList '/S' -Wait
}

function Repair-EverythingService {
    param(
        [string]$EverythingExe
    )

    Get-Process everything -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $binaryPath = '"' + $EverythingExe + '" -svc'
    $service = Get-CimInstance Win32_Service -Filter "Name='Everything'" -ErrorAction SilentlyContinue

    if ($service) {
        Write-Step 'Configuring existing Everything service with sc.exe.'
        & sc.exe config Everything binPath= $binaryPath start= auto obj= LocalSystem | Out-Host
    } else {
        Write-Step 'Creating Everything service with sc.exe.'
        & sc.exe create Everything binPath= $binaryPath start= auto obj= LocalSystem DisplayName= Everything | Out-Host
    }

    & sc.exe failure Everything reset= 86400 actions= restart/5000/restart/30000/""/60000 | Out-Host
    & sc.exe description Everything 'Everything search index service' | Out-Null
    & sc.exe start Everything | Out-Host

    for ($i = 0; $i -lt 30; $i++) {
        $serviceController = Get-Service Everything -ErrorAction SilentlyContinue
        if ($serviceController -and $serviceController.Status -eq 'Running') {
            return $serviceController
        }
        Start-Sleep -Seconds 2
    }

    $final = Get-Service Everything -ErrorAction SilentlyContinue
    if ($final) {
        throw ('Everything service did not reach Running. Current=' + $final.Status)
    }

    throw 'Everything service did not reach Running. Current=missing'
}

function Invoke-EverythingReindex {
    param(
        [string]$EverythingExe
    )

    Write-Step 'Forcing clean reindex and background launch.'
    Start-Process -FilePath $EverythingExe -ArgumentList '-reindex' -Wait
    Start-Process -FilePath $EverythingExe -ArgumentList '-startup'
}

function Invoke-SelfTest {
    Write-Step 'Running self-test.'
    $download = Get-EverythingStableDownload
    Write-Step ('Current stable installer detected: ' + $download.FileName)

    $service = Get-CimInstance Win32_Service -Filter "Name='Everything'" -ErrorAction SilentlyContinue
    if ($service) {
        Write-Step ('Current service state: ' + $service.State + '; start mode: ' + $service.StartMode + '; path: ' + $service.PathName)
    } else {
        Write-Step 'Current service state: missing.'
    }

    $exe = $null
    try {
        $exe = Get-EverythingExe
        Write-Step ('Current Everything.exe: ' + $exe + '; version: ' + (Get-Item $exe).VersionInfo.FileVersion)
    } catch {
        Write-Step ('Current Everything.exe: not found yet. ' + $_.Exception.Message)
    }

    Write-Step 'SELFTEST_OK'
}

if ($SelfTest) {
    Invoke-SelfTest
    return
}

if (-not $AllowDestructiveRepair) {
    $message = 'BLOCKED destructive repair: rerun with -AllowDestructiveRepair only during approved maintenance.'
    Write-Step $message

    try {
        $logDirectory = Join-Path $env:LOCALAPPDATA 'Everything'
        $logPath = Join-Path $logDirectory 'EverythingRepairBlocked.log'
        New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
        Add-Content -LiteralPath $logPath -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') + ' ' + $message)
    } catch {
        # A logging failure must not turn the safety guard into a visible error.
    }

    return
}

if (-not (Test-IsAdmin)) {
    throw 'Run this script from an elevated PowerShell prompt, or right-click PowerShell and choose Run as administrator.'
}

$downloadInfo = Get-EverythingStableDownload
$installer = Join-Path $env:TEMP $downloadInfo.FileName

if (-not $SkipDownload) {
    Write-Step ('Downloading ' + $downloadInfo.FileName)
    Invoke-WebRequest -UseBasicParsing $downloadInfo.Url -OutFile $installer
} elseif (-not (Test-Path -LiteralPath $installer)) {
    throw ('SkipDownload was used, but installer is missing: ' + $installer)
}

Write-Step 'Stopping Everything and clearing half-deleted service states.'
Stop-EverythingProcessesAndService

$backupPath = Backup-And-Remove-StaleEverythingState
Write-Step ('Backed up stale state to ' + $backupPath)

if (-not $SkipInstall) {
    Install-Or-UpdateEverything -InstallerPath $installer
}

$everythingExe = Get-EverythingExe
$serviceResult = Repair-EverythingService -EverythingExe $everythingExe

if (-not $SkipReindex) {
    Invoke-EverythingReindex -EverythingExe $everythingExe
}

Start-Sleep -Seconds 8

Write-Step ('DONE installed=' + $everythingExe + ' version=' + (Get-Item $everythingExe).VersionInfo.FileVersion + ' service=' + $serviceResult.Status + ' backup=' + $backupPath)
