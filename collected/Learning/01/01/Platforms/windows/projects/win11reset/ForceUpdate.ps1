#Requires -RunAsAdministrator
# Windows 11 Force Update
# Reset and force Windows Update

$ErrorActionPreference = "Continue"
$logFile = "$PSScriptRoot\force_update_log.txt"

function Log {
    param([string]$msg, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $msg"
    $color = switch($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } "SUCCESS" { "Green" } default { "White" } }
    Write-Host $line -ForegroundColor $color
    $line | Out-File -FilePath $logFile -Append -Encoding UTF8
}

Clear-Host
Write-Host "`n  ============ FORCE UPDATE ============" -ForegroundColor Cyan
Write-Host "  Resetting and forcing Windows Update...`n" -ForegroundColor White

Remove-Item $logFile -Force -ErrorAction SilentlyContinue
Log "=== Force Update Started ==="

# Step 1: Stop services
Write-Host "[1/6] Stopping Windows Update services..." -ForegroundColor Yellow
$services = @("wuauserv", "bits", "cryptsvc", "msiserver", "dosvc")
$services | ForEach-Object { 
    Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue
    Log "Stopped: $_"
}

# Step 2: Clear update cache
Write-Host "`n[2/6] Clearing update cache..." -ForegroundColor Yellow
$ts = Get-Date -Format 'yyyyMMddHHmmss'
$sdPath = "$env:SystemRoot\SoftwareDistribution"
if (Test-Path $sdPath) {
    Rename-Item $sdPath "$sdPath.old.$ts" -Force -ErrorAction SilentlyContinue
    Log "SoftwareDistribution renamed"
}

$crPath = "$env:SystemRoot\System32\catroot2"
if (Test-Path $crPath) {
    Rename-Item $crPath "$crPath.old.$ts" -Force -ErrorAction SilentlyContinue
    Log "catroot2 renamed"
}

# Step 3: Re-register DLLs
Write-Host "`n[3/6] Re-registering update DLLs..." -ForegroundColor Yellow
$dlls = @("wuapi.dll","wuaueng.dll","wucltui.dll","wups.dll","wups2.dll","wuweb.dll","qmgr.dll","qmgrprxy.dll","wucltux.dll","muweb.dll","wuwebv.dll")
$dlls | ForEach-Object { regsvr32.exe /s $_ 2>$null }
Log "DLLs registered"

# Step 4: Reset BITS
Write-Host "`n[4/6] Resetting BITS..." -ForegroundColor Yellow
bitsadmin /reset /allusers 2>&1 | Out-Null
Log "BITS reset"

# Step 5: Start services
Write-Host "`n[5/6] Starting services..." -ForegroundColor Yellow
@("cryptsvc", "bits", "wuauserv", "dosvc") | ForEach-Object { 
    Start-Service -Name $_ -ErrorAction SilentlyContinue
    Log "Started: $_"
}

# Step 6: Force update check
Write-Host "`n[6/6] Forcing update check..." -ForegroundColor Yellow
Log "Triggering Windows Update scan..."

# Method 1: UsoClient (Windows 10/11)
Start-Process "UsoClient.exe" -ArgumentList "StartScan" -NoNewWindow -Wait -ErrorAction SilentlyContinue
Start-Process "UsoClient.exe" -ArgumentList "StartDownload" -NoNewWindow -ErrorAction SilentlyContinue
Log "Update scan triggered via UsoClient"

# Method 2: Windows Update COM object
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    
    Write-Host "`nSearching for updates..." -ForegroundColor Cyan
    $searchResult = $updateSearcher.Search("IsInstalled=0")
    
    if ($searchResult.Updates.Count -eq 0) {
        Write-Host "  No pending updates found" -ForegroundColor Green
        Log "No updates available"
    } else {
        Write-Host "  Found $($searchResult.Updates.Count) updates:" -ForegroundColor Yellow
        $searchResult.Updates | ForEach-Object {
            Write-Host "    - $($_.Title)" -ForegroundColor Gray
            Log "Update: $($_.Title)"
        }
        
        Write-Host "`nDownloading updates..." -ForegroundColor Cyan
        $downloader = $updateSession.CreateUpdateDownloader()
        $downloader.Updates = $searchResult.Updates
        $downloadResult = $downloader.Download()
        Log "Download complete"
        
        Write-Host "Installing updates..." -ForegroundColor Cyan
        $installer = $updateSession.CreateUpdateInstaller()
        $installer.Updates = $searchResult.Updates
        $installResult = $installer.Install()
        Log "Installation complete - Result: $($installResult.ResultCode)"
        
        if ($installResult.RebootRequired) {
            Write-Host "`n  Reboot required to complete installation!" -ForegroundColor Red
            Log "Reboot required"
        }
    }
} catch {
    Log "COM method failed: $($_.Exception.Message)" "WARN"
    Write-Host "  Update check via Settings..." -ForegroundColor Gray
    Start-Process "ms-settings:windowsupdate"
}

Log "=== Force Update Complete ==="
Write-Host "`n  Windows Update has been reset and triggered." -ForegroundColor Green
Write-Host "  Check Settings > Windows Update for status." -ForegroundColor Gray
Write-Host "  Log: $logFile" -ForegroundColor Gray

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
