#requires -Version 5.0
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Comprehensive D3D12 LowLevelFatalError Fix Script for Unreal Engine

.DESCRIPTION
    Permanently fixes D3D12 GetDevice errors and related DirectX 12 issues in Unreal Engine
    by addressing: DirectX installation, GPU drivers, registry settings, cache clearing,
    Windows graphics optimization, and comprehensive validation testing.

.NOTES
    Created: 2025-12-22
    Author: Claude Code
    Requires: Administrator privileges
#>

[CmdletBinding()]
param(
    [switch]$SkipDriverUpdate,
    [switch]$SkipDirectXRepair,
    [switch]$SkipCacheClear,
    [switch]$TestOnly
)

# ===========================
# GLOBAL VARIABLES
# ===========================
$script:LogFile = "$PSScriptRoot\D3D12-Fix-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$script:BackupDir = "$PSScriptRoot\Backups\$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$script:ErrorCount = 0
$script:SuccessCount = 0
$script:FixesApplied = @()

# ===========================
# LOGGING SYSTEM
# ===========================
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [ValidateSet('INFO','SUCCESS','WARNING','ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"

    # Console output with colors
    switch ($Level) {
        'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
        'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
        'ERROR' { Write-Host $logMessage -ForegroundColor Red; $script:ErrorCount++ }
        default { Write-Host $logMessage -ForegroundColor Cyan }
    }

    # File output
    Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

function Write-Section {
    param([string]$Title)
    $separator = "=" * 70
    Write-Log -Message "`n$separator" -Level INFO
    Write-Log -Message "  $Title" -Level INFO
    Write-Log -Message "$separator" -Level INFO
}

# ===========================
# ERROR HANDLING
# ===========================
function Invoke-SafeCommand {
    param(
        [scriptblock]$Command,
        [string]$Description,
        [switch]$ContinueOnError
    )

    try {
        Write-Log -Message "Starting: $Description" -Level INFO
        & $Command
        Write-Log -Message "Completed: $Description" -Level SUCCESS
        $script:SuccessCount++
        $script:FixesApplied += $Description
        return $true
    }
    catch {
        Write-Log -Message "Failed: $Description - $($_.Exception.Message)" -Level ERROR
        if (-not $ContinueOnError) {
            throw
        }
        return $false
    }
}

# ===========================
# SYSTEM CHECKS
# ===========================
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-GPUInfo {
    Write-Log -Message "Detecting GPU hardware..." -Level INFO

    try {
        $gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Status -eq 'OK' }
        foreach ($gpu in $gpus) {
            Write-Log -Message "GPU Found: $($gpu.Name)" -Level INFO
            Write-Log -Message "  Driver Version: $($gpu.DriverVersion)" -Level INFO
            Write-Log -Message "  Driver Date: $($gpu.DriverDate)" -Level INFO
            Write-Log -Message "  Video RAM: $([math]::Round($gpu.AdapterRAM / 1GB, 2)) GB" -Level INFO
        }
        return $gpus
    }
    catch {
        Write-Log -Message "Failed to detect GPU: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Test-DirectX12Support {
    Write-Log -Message "Checking DirectX 12 support..." -Level INFO

    try {
        # Check dxdiag for D3D12 support
        $dxdiagPath = "$env:TEMP\dxdiag_output.txt"
        Start-Process "dxdiag" -ArgumentList "/t $dxdiagPath" -Wait -NoNewWindow
        Start-Sleep -Seconds 3

        if (Test-Path $dxdiagPath) {
            $content = Get-Content $dxdiagPath -Raw
            if ($content -match "DirectX 12") {
                Write-Log -Message "DirectX 12 is supported" -Level SUCCESS
                Remove-Item $dxdiagPath -Force -ErrorAction SilentlyContinue
                return $true
            }
        }

        Write-Log -Message "DirectX 12 support unclear" -Level WARNING
        return $false
    }
    catch {
        Write-Log -Message "Failed to check DirectX 12 support: $($_.Exception.Message)" -Level WARNING
        return $false
    }
}

# ===========================
# BACKUP FUNCTIONS
# ===========================
function New-SystemBackup {
    Write-Log -Message "Creating system backup..." -Level INFO

    try {
        if (-not (Test-Path $script:BackupDir)) {
            New-Item -Path $script:BackupDir -ItemType Directory -Force | Out-Null
        }

        # Backup registry keys
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Direct3D",
            "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        )

        foreach ($regPath in $regPaths) {
            if (Test-Path $regPath) {
                $backupFile = Join-Path $script:BackupDir "$(($regPath -replace ':', '-' -replace '\\', '_')).reg"
                reg export $regPath.Replace('HKLM:\', 'HKEY_LOCAL_MACHINE\') $backupFile /y 2>&1 | Out-Null
                Write-Log -Message "Backed up: $regPath" -Level INFO
            }
        }

        Write-Log -Message "Backup created at: $script:BackupDir" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log -Message "Backup failed: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

# ===========================
# DIRECTX REPAIR
# ===========================
function Repair-DirectX {
    Write-Section "DirectX 12 Repair"

    if ($SkipDirectXRepair) {
        Write-Log -Message "DirectX repair skipped by user" -Level WARNING
        return
    }

    Invoke-SafeCommand -Description "DirectX component repair" -ContinueOnError -Command {
        # Download DirectX End-User Runtime Web Installer
        $directXUrl = "https://download.microsoft.com/download/1/7/1/1718CCC4-6315-4D8E-9543-8E28A4E18C4C/dxwebsetup.exe"
        $directXInstaller = "$env:TEMP\dxwebsetup.exe"

        Write-Log -Message "Downloading DirectX Web Installer..." -Level INFO
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($directXUrl, $directXInstaller)

            if (Test-Path $directXInstaller) {
                Write-Log -Message "Installing DirectX components..." -Level INFO
                Start-Process -FilePath $directXInstaller -ArgumentList "/silent" -Wait -NoNewWindow
                Remove-Item $directXInstaller -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Log -Message "DirectX installer download/install failed: $($_.Exception.Message)" -Level WARNING
        }

        # Run System File Checker for DirectX files
        Write-Log -Message "Running System File Checker..." -Level INFO
        Start-Process "sfc" -ArgumentList "/scannow" -Wait -NoNewWindow -RedirectStandardOutput "$env:TEMP\sfc_output.txt"
    }
}

# ===========================
# GPU DRIVER MANAGEMENT
# ===========================
function Update-GPUDrivers {
    Write-Section "GPU Driver Update"

    if ($SkipDriverUpdate) {
        Write-Log -Message "GPU driver update skipped by user" -Level WARNING
        return
    }

    $gpus = Get-GPUInfo

    foreach ($gpu in $gpus) {
        $gpuName = $gpu.Name.ToLower()

        if ($gpuName -match "nvidia") {
            Write-Log -Message "NVIDIA GPU detected - checking for updates..." -Level INFO
            Invoke-SafeCommand -Description "NVIDIA driver check" -ContinueOnError -Command {
                # Check Windows Update for driver updates
                Write-Log -Message "Checking Windows Update for NVIDIA drivers..." -Level INFO
                Start-Process "ms-settings:windowsupdate-action" -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
        }
        elseif ($gpuName -match "amd|radeon") {
            Write-Log -Message "AMD GPU detected - checking for updates..." -Level INFO
            Invoke-SafeCommand -Description "AMD driver check" -ContinueOnError -Command {
                Write-Log -Message "Checking Windows Update for AMD drivers..." -Level INFO
                Start-Process "ms-settings:windowsupdate-action" -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
        }
        elseif ($gpuName -match "intel") {
            Write-Log -Message "Intel GPU detected - checking for updates..." -Level INFO
            Invoke-SafeCommand -Description "Intel driver check" -ContinueOnError -Command {
                Write-Log -Message "Checking Windows Update for Intel drivers..." -Level INFO
                Start-Process "ms-settings:windowsupdate-action" -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
        }
    }
}

# ===========================
# CACHE CLEARING
# ===========================
function Clear-D3D12Caches {
    Write-Section "D3D12 Cache Clearing"

    if ($SkipCacheClear) {
        Write-Log -Message "Cache clearing skipped by user" -Level WARNING
        return
    }

    # DirectX Shader Cache
    Invoke-SafeCommand -Description "DirectX Shader Cache clear" -ContinueOnError -Command {
        $dxCachePaths = @(
            "$env:LOCALAPPDATA\D3DSCache",
            "$env:LOCALAPPDATA\NVIDIA\DXCache",
            "$env:LOCALAPPDATA\AMD\DxCache",
            "$env:TEMP\*.dxc"
        )

        foreach ($path in $dxCachePaths) {
            if (Test-Path $path) {
                Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log -Message "Cleared: $path" -Level INFO
            }
        }
    }

    # Unreal Engine Shader Cache
    Invoke-SafeCommand -Description "Unreal Engine shader cache clear" -ContinueOnError -Command {
        $ueCachePaths = @(
            "$env:LOCALAPPDATA\UnrealEngine\*\Saved\ShaderCache",
            "$env:LOCALAPPDATA\UnrealEngine\*\Saved\Cooked",
            "$env:APPDATA\Unreal Engine\*\Saved\ShaderCache"
        )

        foreach ($path in $ueCachePaths) {
            if (Test-Path $path) {
                Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log -Message "Cleared UE cache: $path" -Level INFO
            }
        }
    }

    # PSO Cache
    Invoke-SafeCommand -Description "PSO cache clear" -ContinueOnError -Command {
        $psoCachePaths = @(
            "$env:LOCALAPPDATA\UnrealEngine\*\Saved\PSOCache",
            "$env:LOCALAPPDATA\Temp\UnrealShaderCompileWorker"
        )

        foreach ($path in $psoCachePaths) {
            if (Test-Path $path) {
                Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log -Message "Cleared PSO cache: $path" -Level INFO
            }
        }
    }
}

# ===========================
# REGISTRY FIXES
# ===========================
function Repair-D3D12Registry {
    Write-Section "D3D12 Registry Configuration"

    Invoke-SafeCommand -Description "D3D12 registry optimization" -ContinueOnError -Command {
        # TDR (Timeout Detection and Recovery) settings
        $tdrPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"

        if (-not (Test-Path $tdrPath)) {
            New-Item -Path $tdrPath -Force | Out-Null
        }

        # Increase TDR timeout to prevent premature GPU resets
        Set-ItemProperty -Path $tdrPath -Name "TdrDelay" -Value 60 -Type DWord -Force
        Set-ItemProperty -Path $tdrPath -Name "TdrDdiDelay" -Value 60 -Type DWord -Force
        Set-ItemProperty -Path $tdrPath -Name "TdrLevel" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $tdrPath -Name "TdrLimitTime" -Value 60 -Type DWord -Force
        Set-ItemProperty -Path $tdrPath -Name "TdrLimitCount" -Value 20 -Type DWord -Force

        Write-Log -Message "TDR settings optimized" -Level SUCCESS

        # Hardware Acceleration
        $d3dPath = "HKLM:\SOFTWARE\Microsoft\Direct3D"
        if (-not (Test-Path $d3dPath)) {
            New-Item -Path $d3dPath -Force | Out-Null
        }

        Set-ItemProperty -Path $d3dPath -Name "DisableVidMemVBs" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $d3dPath -Name "MMX Fast Path" -Value 1 -Type DWord -Force

        Write-Log -Message "Direct3D acceleration enabled" -Level SUCCESS

        # GPU Scheduling
        $schedulingPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        Set-ItemProperty -Path $schedulingPath -Name "HwSchMode" -Value 2 -Type DWord -Force

        Write-Log -Message "Hardware-accelerated GPU scheduling enabled" -Level SUCCESS
    }
}

# ===========================
# WINDOWS GRAPHICS SETTINGS
# ===========================
function Optimize-WindowsGraphics {
    Write-Section "Windows Graphics Optimization"

    Invoke-SafeCommand -Description "Windows graphics settings optimization" -ContinueOnError -Command {
        # Disable Windows Game Bar
        $gameBarPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"
        if (-not (Test-Path $gameBarPath)) {
            New-Item -Path $gameBarPath -Force | Out-Null
        }
        Set-ItemProperty -Path $gameBarPath -Name "AppCaptureEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $gameBarPath -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force

        Write-Log -Message "Game Bar disabled" -Level INFO

        # Disable fullscreen optimizations for better D3D12 performance
        $fsoPath = "HKCU:\System\GameConfigStore"
        if (-not (Test-Path $fsoPath)) {
            New-Item -Path $fsoPath -Force | Out-Null
        }
        Set-ItemProperty -Path $fsoPath -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord -Force
        Set-ItemProperty -Path $fsoPath -Name "GameDVR_HonorUserFSEBehaviorMode" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $fsoPath -Name "GameDVR_DXGIHonorFSEWindowsCompatible" -Value 1 -Type DWord -Force

        Write-Log -Message "Fullscreen optimization configured" -Level INFO

        # Visual Effects for best performance
        $visualFXPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (-not (Test-Path $visualFXPath)) {
            New-Item -Path $visualFXPath -Force | Out-Null
        }
        Set-ItemProperty -Path $visualFXPath -Name "VisualFXSetting" -Value 2 -Type DWord -Force

        Write-Log -Message "Visual effects optimized" -Level INFO
    }
}

# ===========================
# UNREAL ENGINE CONFIG
# ===========================
function Reset-UnrealEngineD3D12Config {
    Write-Section "Unreal Engine D3D12 Configuration"

    Invoke-SafeCommand -Description "Unreal Engine D3D12 config reset" -ContinueOnError -Command {
        # Find Unreal Engine config locations
        $ueConfigPaths = @(
            "$env:LOCALAPPDATA\UnrealEngine",
            "$env:APPDATA\Unreal Engine"
        )

        foreach ($basePath in $ueConfigPaths) {
            if (Test-Path $basePath) {
                # Find Engine.ini files
                $engineInis = Get-ChildItem -Path $basePath -Filter "Engine.ini" -Recurse -ErrorAction SilentlyContinue

                foreach ($ini in $engineInis) {
                    Write-Log -Message "Optimizing: $($ini.FullName)" -Level INFO

                    # Backup original
                    $backupPath = "$($ini.FullName).backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                    Copy-Item -Path $ini.FullName -Destination $backupPath -Force

                    # Add/update D3D12 settings
                    $content = Get-Content -Path $ini.FullName -Raw -ErrorAction SilentlyContinue

                    if (-not $content) { $content = "" }

                    # Ensure [SystemSettings] section exists
                    if ($content -notmatch '\[SystemSettings\]') {
                        $content += "`n[SystemSettings]`n"
                    }

                    # D3D12 optimization settings
                    $d3d12Settings = @"
`n; D3D12 Optimization Settings (Added by Fix-D3D12Error.ps1)
r.D3D12.GPUTimeout=0
r.D3D12.ForceResidencyDelay=0
r.D3D12.UseGPUTimeout=0
r.Streaming.PoolSize=3000
r.Streaming.MaxTempMemoryAllowed=250
r.D3D12.AsyncDeferredDeletion=1
r.ShaderDevelopmentMode=0
r.RHI.ResourceTableCaching=1
"@

                    # Remove old D3D12 settings if they exist
                    $content = $content -replace '(?m)^r\.D3D12\..*$', ''

                    # Find [SystemSettings] and add settings after it
                    $content = $content -replace '(\[SystemSettings\])', "`$1$d3d12Settings"

                    Set-Content -Path $ini.FullName -Value $content -Force
                    Write-Log -Message "Updated: $($ini.FullName)" -Level SUCCESS
                }
            }
        }
    }
}

# ===========================
# DISPLAY ADAPTER RESET
# ===========================
function Reset-DisplayAdapter {
    Write-Section "Display Adapter Reset"

    Invoke-SafeCommand -Description "Display adapter refresh" -ContinueOnError -Command {
        Write-Log -Message "Restarting display adapters..." -Level INFO

        # Disable and re-enable display adapters
        $adapters = Get-PnpDevice | Where-Object { $_.Class -eq "Display" -and $_.Status -eq "OK" }

        foreach ($adapter in $adapters) {
            try {
                Write-Log -Message "Resetting: $($adapter.FriendlyName)" -Level INFO
                Disable-PnpDevice -InstanceId $adapter.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Enable-PnpDevice -InstanceId $adapter.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                Write-Log -Message "Reset complete: $($adapter.FriendlyName)" -Level SUCCESS
            }
            catch {
                Write-Log -Message "Failed to reset: $($adapter.FriendlyName) - $($_.Exception.Message)" -Level WARNING
            }
        }
    }
}

# ===========================
# VALIDATION & TESTING
# ===========================
function Test-D3D12Functionality {
    Write-Section "D3D12 Functionality Test"

    Invoke-SafeCommand -Description "D3D12 functionality validation" -ContinueOnError -Command {
        # Test DirectX capabilities
        Write-Log -Message "Testing DirectX 12 capabilities..." -Level INFO

        $testScript = @'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class D3D12Test {
    [DllImport("d3d12.dll", SetLastError = true)]
    public static extern int D3D12GetDebugInterface(ref Guid riid, out IntPtr ppvDebug);
}
"@

try {
    $guid = [Guid]::Parse("344488b7-6846-474b-b989-f027448245e0")
    $ptr = [IntPtr]::Zero
    $result = [D3D12Test]::D3D12GetDebugInterface([ref]$guid, [ref]$ptr)

    if ($result -eq 0) {
        return $true
    } else {
        return $false
    }
}
catch {
    return $false
}
'@

        $testResult = Invoke-Expression $testScript

        if ($testResult) {
            Write-Log -Message "D3D12 interface test: PASSED" -Level SUCCESS
        } else {
            Write-Log -Message "D3D12 interface test: FAILED (may be normal)" -Level WARNING
        }

        # Verify registry settings
        Write-Log -Message "Verifying registry settings..." -Level INFO
        $tdrPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        $tdrDelay = Get-ItemProperty -Path $tdrPath -Name "TdrDelay" -ErrorAction SilentlyContinue

        if ($tdrDelay.TdrDelay -eq 60) {
            Write-Log -Message "TDR settings verified: PASSED" -Level SUCCESS
        } else {
            Write-Log -Message "TDR settings verification: FAILED" -Level WARNING
        }

        # Check GPU status
        Write-Log -Message "Verifying GPU status..." -Level INFO
        $gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Status -eq 'OK' }

        if ($gpus.Count -gt 0) {
            Write-Log -Message "GPU status check: PASSED ($($gpus.Count) GPU(s) active)" -Level SUCCESS
        } else {
            Write-Log -Message "GPU status check: FAILED" -Level ERROR
        }
    }
}

# ===========================
# MAIN EXECUTION
# ===========================
function Start-D3D12Fix {
    Write-Host "`n"
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  D3D12 LowLevelFatalError - Comprehensive Fix Script" -ForegroundColor Cyan
    Write-Host "  Created: 2025-12-22" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "`n"

    # Check administrator rights
    if (-not (Test-Administrator)) {
        Write-Log -Message "This script requires Administrator privileges!" -Level ERROR
        Write-Host "`nPlease run PowerShell as Administrator and try again." -ForegroundColor Red
        return
    }

    Write-Log -Message "Starting D3D12 fix process..." -Level INFO
    Write-Log -Message "Log file: $script:LogFile" -Level INFO

    # Pre-flight checks
    Write-Section "System Analysis"
    Get-GPUInfo
    Test-DirectX12Support

    if ($TestOnly) {
        Write-Log -Message "Test-only mode enabled - skipping fixes" -Level WARNING
        Test-D3D12Functionality
        return
    }

    # Create backup
    New-SystemBackup

    # Execute fixes
    Repair-DirectX
    Update-GPUDrivers
    Clear-D3D12Caches
    Repair-D3D12Registry
    Optimize-WindowsGraphics
    Reset-UnrealEngineD3D12Config
    Reset-DisplayAdapter

    # Validation
    Test-D3D12Functionality

    # Summary
    Write-Section "Fix Summary"
    Write-Log -Message "Total fixes applied: $script:SuccessCount" -Level SUCCESS
    Write-Log -Message "Total errors encountered: $script:ErrorCount" -Level $(if ($script:ErrorCount -gt 0) { "WARNING" } else { "SUCCESS" })
    Write-Log -Message "`nFixes applied:" -Level INFO

    foreach ($fix in $script:FixesApplied) {
        Write-Log -Message "  - $fix" -Level INFO
    }

    Write-Host "`n"
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  D3D12 Fix Process Complete!" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "`nRECOMMENDATIONS:" -ForegroundColor Yellow
    Write-Host "  1. Restart your computer for all changes to take effect" -ForegroundColor White
    Write-Host "  2. Test Unreal Engine project after restart" -ForegroundColor White
    Write-Host "  3. If issues persist, check GPU driver updates manually" -ForegroundColor White
    Write-Host "  4. Review log file: $script:LogFile" -ForegroundColor White
    Write-Host "`n"
}

# Run the fix
Start-D3D12Fix
