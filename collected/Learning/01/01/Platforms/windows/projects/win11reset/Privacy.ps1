#Requires -RunAsAdministrator
# Windows 11 Privacy Settings

param(
    [switch]$Undo  # Restore default settings
)

$ErrorActionPreference = "Continue"

Clear-Host
$mode = if ($Undo) { "RESTORE DEFAULTS" } else { "ENHANCE PRIVACY" }
Write-Host "`n  ============ PRIVACY SETTINGS ($mode) ============" -ForegroundColor Red
Write-Host "  Adjusting Windows privacy settings...`n" -ForegroundColor White

function Set-Privacy {
    param([string]$Name, [string]$Path, [string]$Key, $Value, $Default)
    
    if ($Undo) {
        if ($null -ne $Default) {
            if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
            Set-ItemProperty -Path $Path -Name $Key -Value $Default -Force -ErrorAction SilentlyContinue
            Write-Host "  [RESTORED] $Name" -ForegroundColor Yellow
        }
    } else {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $Key -Value $Value -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] $Name" -ForegroundColor Green
    }
}

# Telemetry
Write-Host "[1/5] Telemetry settings..." -ForegroundColor Yellow
Set-Privacy "Disable telemetry" "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0 3

# Advertising ID
Write-Host "`n[2/5] Advertising settings..." -ForegroundColor Yellow
Set-Privacy "Disable Advertising ID" "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0 1
Set-Privacy "Disable tailored experiences" "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" 0 1

# Location
Write-Host "`n[3/5] Location settings..." -ForegroundColor Yellow
Set-Privacy "Disable location tracking" "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" "Value" "Deny" "Allow"

# Activity History
Write-Host "`n[4/5] Activity settings..." -ForegroundColor Yellow
Set-Privacy "Disable Activity History" "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" 0 1
Set-Privacy "Disable timeline" "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0 1

# Cortana
Write-Host "`n[5/5] Cortana settings..." -ForegroundColor Yellow
Set-Privacy "Disable Cortana" "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" 0 1

# Services (only in enhance mode)
if (-not $Undo) {
    Write-Host "`n>>> Disabling telemetry services..." -ForegroundColor Yellow
    @("DiagTrack", "dmwappushservice") | ForEach-Object {
        Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue
        Set-Service -Name $_ -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "  [OK] Disabled: $_" -ForegroundColor Green
    }
} else {
    Write-Host "`n>>> Restoring telemetry services..." -ForegroundColor Yellow
    @("DiagTrack", "dmwappushservice") | ForEach-Object {
        Set-Service -Name $_ -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name $_ -ErrorAction SilentlyContinue
        Write-Host "  [OK] Restored: $_" -ForegroundColor Yellow
    }
}

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
if ($Undo) {
    Write-Host "  Default privacy settings restored." -ForegroundColor White
} else {
    Write-Host "  Privacy settings enhanced." -ForegroundColor White
    Write-Host "  Run with -Undo to restore defaults." -ForegroundColor Gray
}

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
