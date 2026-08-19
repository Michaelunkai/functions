#Requires -RunAsAdministrator
# Windows 11 Game Mode Optimization

param([switch]$Undo)

$ErrorActionPreference = "Continue"

Clear-Host
$mode = if ($Undo) { "RESTORE" } else { "ENABLE" }
Write-Host "`n  ============ GAME MODE ($mode) ============" -ForegroundColor Magenta
Write-Host "  Optimizing for gaming performance...`n" -ForegroundColor White

function Set-GameSetting {
    param([string]$Name, [string]$Path, [string]$Key, $Value, $Default)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    $val = if ($Undo -and $Default) { $Default } else { $Value }
    Set-ItemProperty -Path $Path -Name $Key -Value $val -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] $Name" -ForegroundColor Green
}

# Game Mode
Write-Host "[1/5] Game Mode settings..." -ForegroundColor Yellow
Set-GameSetting "Enable Game Mode" "HKCU:\SOFTWARE\Microsoft\GameBar" "AllowAutoGameMode" 1 1
Set-GameSetting "Enable Game Bar" "HKCU:\SOFTWARE\Microsoft\GameBar" "AutoGameModeEnabled" 1 1

# Performance
Write-Host "`n[2/5] Performance settings..." -ForegroundColor Yellow
Set-GameSetting "Hardware-accelerated GPU scheduling" "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2 2

# Power plan
Write-Host "`n[3/5] Power plan..." -ForegroundColor Yellow
if (-not $Undo) {
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null  # High Performance
    Write-Host "  [OK] High Performance power plan" -ForegroundColor Green
} else {
    powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>&1 | Out-Null  # Balanced
    Write-Host "  [OK] Balanced power plan restored" -ForegroundColor Green
}

# Disable background apps
Write-Host "`n[4/5] Background apps..." -ForegroundColor Yellow
$val = if ($Undo) { 1 } else { 0 }
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value $val -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Background apps $(if($Undo){'enabled'}else{'disabled'})" -ForegroundColor Green

# Xbox/Gaming services
Write-Host "`n[5/5] Gaming services..." -ForegroundColor Yellow
if (-not $Undo) {
    # Stop non-essential gaming services for lower latency
    @("XblAuthManager", "XblGameSave", "XboxGipSvc", "XboxNetApiSvc") | ForEach-Object {
        Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue
    }
    Write-Host "  [OK] Background Xbox services stopped" -ForegroundColor Green
}

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
if ($Undo) {
    Write-Host "  Normal mode restored." -ForegroundColor White
} else {
    Write-Host "  Gaming mode enabled!" -ForegroundColor White
    Write-Host "  Run with -Undo to restore normal settings." -ForegroundColor Gray
}

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
