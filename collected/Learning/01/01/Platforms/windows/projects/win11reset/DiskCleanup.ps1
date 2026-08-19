#Requires -RunAsAdministrator
# Windows 11 Disk Cleanup

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "`n  ============ DISK CLEANUP ============" -ForegroundColor Yellow
Write-Host "  Deep cleaning disk space...`n" -ForegroundColor White

$totalFreed = 0

function Clear-Folder {
    param([string]$Name, [string]$Path)
    if (Test-Path $Path) {
        $size = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        Remove-Item "$Path\*" -Recurse -Force -ErrorAction SilentlyContinue
        $freedMB = [math]::Round($size / 1MB, 2)
        $script:totalFreed += $freedMB
        Write-Host "  [OK] $Name - $freedMB MB" -ForegroundColor Green
    }
}

# Windows Temp
Write-Host "[1/6] Clearing Windows Temp..." -ForegroundColor Yellow
Clear-Folder "Windows Temp" "$env:SystemRoot\Temp"

# User Temp
Write-Host "`n[2/6] Clearing User Temp..." -ForegroundColor Yellow
Clear-Folder "User Temp" "$env:TEMP"

# Windows Update Cache
Write-Host "`n[3/6] Clearing Windows Update cache..." -ForegroundColor Yellow
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Clear-Folder "WU Download" "$env:SystemRoot\SoftwareDistribution\Download"
Start-Service -Name wuauserv -ErrorAction SilentlyContinue

# Prefetch
Write-Host "`n[4/6] Clearing Prefetch..." -ForegroundColor Yellow
Clear-Folder "Prefetch" "$env:SystemRoot\Prefetch"

# Thumbnail cache
Write-Host "`n[5/6] Clearing thumbnail cache..." -ForegroundColor Yellow
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Clear-Folder "Thumbnails" "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
Start-Process explorer

# Browser caches
Write-Host "`n[6/6] Clearing browser caches..." -ForegroundColor Yellow
Clear-Folder "Edge Cache" "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
Clear-Folder "Chrome Cache" "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"

# Summary
Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
Write-Host "  Total freed: $([math]::Round($totalFreed, 2)) MB" -ForegroundColor Cyan

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
