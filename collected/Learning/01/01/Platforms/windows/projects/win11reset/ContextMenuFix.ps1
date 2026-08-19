#Requires -RunAsAdministrator
# Windows 11 Context Menu Fix

param(
    [switch]$RestoreNew  # Restore new Win11 menu
)

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "`n  ============ CONTEXT MENU FIX ============" -ForegroundColor Green
Write-Host "  Fixing right-click context menu...`n" -ForegroundColor White

$regPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"

if ($RestoreNew) {
    # Restore Windows 11 new context menu
    Write-Host "[1/2] Restoring Windows 11 context menu..." -ForegroundColor Yellow
    if (Test-Path $regPath) {
        Remove-Item $regPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] New menu restored" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Already using new menu" -ForegroundColor Gray
    }
} else {
    # Enable classic Windows 10 context menu
    Write-Host "[1/2] Enabling classic (Win10) context menu..." -ForegroundColor Yellow
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "(Default)" -Value "" -Force
    Write-Host "  [OK] Classic menu enabled" -ForegroundColor Green
}

# Clear icon cache
Write-Host "`n[2/2] Refreshing shell..." -ForegroundColor Yellow
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Process explorer
Write-Host "  [OK] Explorer restarted" -ForegroundColor Green

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
if ($RestoreNew) {
    Write-Host "  Windows 11 new context menu restored." -ForegroundColor White
} else {
    Write-Host "  Classic Windows 10 context menu enabled." -ForegroundColor White
}
Write-Host "  Run with -RestoreNew to switch back." -ForegroundColor Gray

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
