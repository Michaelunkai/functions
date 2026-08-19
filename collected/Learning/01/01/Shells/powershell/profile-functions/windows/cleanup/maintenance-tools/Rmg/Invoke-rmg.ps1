$__extractedFunctionName = 'rmg'
$__extractedCommandName = 'rmg'
$__extractedScriptPath = $PSCommandPath
$__extractedArgs = @($args)
if ($__extractedArgs -contains '-SelfTest') {
    [pscustomobject]@{
        Function = $__extractedFunctionName
        Command = $__extractedCommandName
        Script = $__extractedScriptPath
        Exists = [bool](Test-Path -LiteralPath $__extractedScriptPath)
        Mode = 'SelfTest'
    } | ConvertTo-Json -Compress
    return
}

function rmg {
    # Requires admin privileges
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "This script requires administrator privileges. Please run PowerShell as Administrator."
        return
    }
    Write-Output "Starting complete removal of NVIDIA GeForce Experience..." -ForegroundColor Yellow
    # Stop related processes
    $processesToKill = @(
        "NVIDIA GeForce Experience",
        "NVIDIA Share",
        "NVIDIA Web Helper",
        "NVDisplay.Container",
        "NvTelemetryContainer"
    )
    foreach ($process in $processesToKill) {
        Get-Process | Where-Object {$_.ProcessName -like "*$process*"} | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Output "Attempting to stop process: $process" -ForegroundColor Cyan
    }
    # Uninstall using WMI
    Write-Output "Uninstalling GeForce Experience using WMI..." -ForegroundColor Yellow
    try {
        Get-WmiObject -Class Win32_Product |
            Where-Object {$_.Name -like "*NVIDIA GeForce Experience*"} |
            ForEach-Object {
                Write-Output "Uninstalling: $($_.Name)" -ForegroundColor Cyan
                $_.Uninstall()
            }
    }
    catch {
        Write-Output "WMI uninstall method failed, trying alternative removal methods..." -ForegroundColor Red
    }
    # Additional uninstall using Get-Package
    Write-Output "Checking for remaining packages..." -ForegroundColor Yellow
    Get-Package -Name "*NVIDIA GeForce Experience*" -ErrorAction SilentlyContinue |
        Uninstall-Package -Force -ErrorAction SilentlyContinue
    # Registry cleanup
    Write-Output "Cleaning registry entries..." -ForegroundColor Yellow
    $registryPaths = @(
        "HKLM:\SOFTWARE\NVIDIA Corporation\Global\GFExperience",
        "HKLM:\SOFTWARE\NVIDIA Corporation\NVIDIA GeForce Experience",
        "HKCU:\SOFTWARE\NVIDIA Corporation\Global\GFExperience",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NVIDIA GeForce Experience"
    )
    foreach ($path in $registryPaths) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            Write-Output "Removed registry path: $path" -ForegroundColor Cyan
        }
    }
    # File system cleanup
    Write-Output "Removing leftover files..." -ForegroundColor Yellow
    $pathsToRemove = @(
        "${env:ProgramFiles}\NVIDIA Corporation\NVIDIA GeForce Experience",
        "${env:ProgramFiles(x86)}\NVIDIA Corporation\NVIDIA GeForce Experience",
        "${env:ProgramData}\NVIDIA Corporation\GeForce Experience",
        "${env:APPDATA}\NVIDIA\GeForceExperience",
        "${env:LOCALAPPDATA}\NVIDIA\GeForceExperience",
        "${env:ProgramData}\NVIDIA Corporation\Installer2"
    )
    foreach ($path in $pathsToRemove) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            Write-Output "Removed directory: $path" -ForegroundColor Cyan
        }
    }
    # Clean temporary files
    Write-Output "Cleaning temporary files..." -ForegroundColor Yellow
    Remove-Item -Path "$env:TEMP\NVIDIA*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:TEMP\GFExperience*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "`nNVIDIA GeForce Experience removal complete!" -ForegroundColor Green
    Write-Output "Please restart your computer to complete the cleanup process." -ForegroundColor Yellow
}

& $__extractedCommandName @__extractedArgs