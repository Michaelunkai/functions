[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Root = "",
    [switch]$RemoveScripts
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$ScriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
} elseif (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
    Split-Path -Parent $PSCommandPath
} else {
    (Get-Location).Path
}
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Join-Path $ScriptRoot ".gophish-runtime"
}

$Root = [System.IO.Path]::GetFullPath($Root)
$SetupScriptPath = Join-Path $ScriptRoot "setup-gophish.ps1"
$CleanupScriptPath = $PSCommandPath
$PidPath = Join-Path $Root "state\gophish.pid"
$BrowserPidPath = Join-Path $Root "state\browser.pid"
$BrowserProfileDir = Join-Path $Root "browser-profile"

function Write-Step {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

function Get-WorkspaceGophishProcesses {
    if (-not (Test-Path -LiteralPath $Root)) {
        return @()
    }

    $escaped = $Root.TrimEnd("\")
    @(Get-CimInstance Win32_Process -Filter "Name = 'gophish.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and
            ([System.IO.Path]::GetFullPath($_.ExecutablePath)).StartsWith($escaped, [System.StringComparison]::OrdinalIgnoreCase)
        })
}

function Get-WorkspaceBrowserProcesses {
    $needle = $BrowserProfileDir
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        })
}

function Stop-WorkspaceBrowser {
    $processes = @(Get-WorkspaceBrowserProcesses)

    if (Test-Path -LiteralPath $BrowserPidPath) {
        $pidText = (Get-Content -LiteralPath $BrowserPidPath -Raw).Trim()
        if ($pidText -match "^\d+$") {
            $pidProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $pidText" -ErrorAction SilentlyContinue
            if ($pidProcess -and $pidProcess.CommandLine -and $pidProcess.CommandLine.IndexOf($BrowserProfileDir, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $processes += $pidProcess
            }
        }
    }

    $processes = @($processes | Sort-Object ProcessId -Unique)
    foreach ($proc in $processes) {
        Write-Step "Stopping workspace browser process PID $($proc.ProcessId)"
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }

    $deadline = (Get-Date).AddSeconds(20)
    do {
        $remaining = @(Get-WorkspaceBrowserProcesses)
        if ($remaining.Count -eq 0) {
            return
        }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)

    throw "Timed out stopping workspace browser process."
}

function Stop-WorkspaceGophish {
    $processes = @(Get-WorkspaceGophishProcesses)

    if (Test-Path -LiteralPath $PidPath) {
        $pidText = (Get-Content -LiteralPath $PidPath -Raw).Trim()
        if ($pidText -match "^\d+$") {
            $pidProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $pidText" -ErrorAction SilentlyContinue
            if ($pidProcess -and $pidProcess.ExecutablePath -and ([System.IO.Path]::GetFullPath($pidProcess.ExecutablePath)).StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
                $processes += $pidProcess
            }
        }
    }

    $processes = @($processes | Sort-Object ProcessId -Unique)
    foreach ($proc in $processes) {
        Write-Step "Stopping workspace GoPhish process PID $($proc.ProcessId)"
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }

    $deadline = (Get-Date).AddSeconds(20)
    do {
        $remaining = @(Get-WorkspaceGophishProcesses)
        if ($remaining.Count -eq 0) {
            return
        }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)

    throw "Timed out stopping workspace GoPhish process."
}

function Remove-PathFully {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop

    $deadline = (Get-Date).AddSeconds(20)
    do {
        if (-not (Test-Path -LiteralPath $Path)) {
            return
        }
        Start-Sleep -Milliseconds 300
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    } while ((Get-Date) -lt $deadline)

    throw "Path still exists after forced deletion: $Path"
}

Stop-WorkspaceBrowser
Stop-WorkspaceGophish

if ($PSCmdlet.ShouldProcess($Root, "Remove workspace GoPhish runtime tree")) {
    Write-Step "Removing $Root"
    Remove-PathFully -Path $Root
}

$leftoverProcesses = @(Get-WorkspaceGophishProcesses)
if ($leftoverProcesses.Count -ne 0) {
    throw "Workspace GoPhish process leftovers remain: $($leftoverProcesses.ProcessId -join ', ')"
}

$leftoverBrowserProcesses = @(Get-WorkspaceBrowserProcesses)
if ($leftoverBrowserProcesses.Count -ne 0) {
    throw "Workspace browser process leftovers remain: $($leftoverBrowserProcesses.ProcessId -join ', ')"
}

if (Test-Path -LiteralPath $Root) {
    throw "Runtime root still exists after cleanup: $Root"
}

if ($RemoveScripts) {
    Write-Step "Scheduling script self-removal"
    $cmd = "/c timeout /t 2 /nobreak >nul & del /f /q `"$SetupScriptPath`" >nul 2>nul & del /f /q `"$CleanupScriptPath`" >nul 2>nul"
    Start-Process -FilePath $env:ComSpec -ArgumentList $cmd -WindowStyle Hidden
}

Write-Host "CLEANUP_COMPLETE=$Root"
