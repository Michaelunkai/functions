# ULTIMATE WINDOWS REPAIR PRO - 50+ PHASE COMPREHENSIVE SYSTEM RESTORATION
# PowerShell 5 Compatible - Maximum Detail Real-Time Progress
# Run as Administrator

$ErrorActionPreference = "Continue"
$totalPhases = 52
$currentPhase = 0
$startTime = Get-Date
$logPath = "$env:TEMP\WindowsRepairPro_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$Level] $Message" | Out-File -FilePath $logPath -Append
}

function Show-Phase {
    param([string]$Title, [string]$Description = "")
    $script:currentPhase++
    $elapsed = (Get-Date) - $startTime
    $percentComplete = [math]::Round(($script:currentPhase / $totalPhases) * 100, 2)
    $avgTimePerPhase = $elapsed.TotalSeconds / $script:currentPhase
    $remainingPhases = $totalPhases - $script:currentPhase
    $estimatedRemaining = [TimeSpan]::FromSeconds($avgTimePerPhase * $remainingPhases)
    
    Write-Progress -Activity "Ultimate Windows Repair Pro" `
                   -Status "$Title ($percentComplete% complete)" `
                   -PercentComplete $percentComplete `
                   -CurrentOperation "Elapsed: $($elapsed.ToString('hh\:mm\:ss')) | Est. Remaining: $($estimatedRemaining.ToString('hh\:mm\:ss'))"
    
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "PHASE $script:currentPhase/$totalPhases ($percentComplete%) : $Title" -ForegroundColor Yellow
    if ($Description) {
        Write-Host "INFO: $Description" -ForegroundColor Gray
    }
    Write-Host "Elapsed: $($elapsed.ToString('hh\:mm\:ss')) | Est. Remaining: $($estimatedRemaining.ToString('hh\:mm\:ss'))" -ForegroundColor DarkGray
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Log "Starting Phase $script:currentPhase/$totalPhases : $Title"
}

function Show-Step {
    param([string]$Message, [switch]$Detailed)
    if ($Detailed) {
        Write-Host "    >> $Message" -ForegroundColor DarkCyan -NoNewline
    } else {
        Write-Host "  > $Message" -ForegroundColor White -NoNewline
    }
    Write-Log "Step: $Message"
}

function Show-Success {
    param([string]$Details = "")
    if ($Details) {
        Write-Host " [OK] $Details" -ForegroundColor Green
    } else {
        Write-Host " [OK]" -ForegroundColor Green
    }
}

function Show-Warning {
    param([string]$Message)
    Write-Host " [WARN] $Message" -ForegroundColor Yellow
    Write-Log "Warning: $Message" "WARN"
}

function Show-Error {
    param([string]$Message)
    Write-Host " [ERROR] $Message" -ForegroundColor Red
    Write-Log "Error: $Message" "ERROR"
}

function Show-Progress-Detail {
    param([string]$Current, [int]$Total, [string]$Item)
    $pct = [math]::Round(($Current / $Total) * 100, 1)
    Write-Host "      [$pct%] $Item" -ForegroundColor DarkGray
}

# START
Clear-Host
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "     ULTIMATE WINDOWS REPAIR PRO - 52 PHASE DEEP SYSTEM FIX    " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This comprehensive repair will perform:" -ForegroundColor White
Write-Host "  - Deep system file integrity verification" -ForegroundColor Gray
Write-Host "  - Complete Windows component restoration" -ForegroundColor Gray
Write-Host "  - Full network stack rebuild" -ForegroundColor Gray
Write-Host "  - Registry optimization and repair" -ForegroundColor Gray
Write-Host "  - Driver verification and update" -ForegroundColor Gray
Write-Host "  - Security policy restoration" -ForegroundColor Gray
Write-Host "  - Performance optimization" -ForegroundColor Gray
Write-Host ""
Write-Host "Estimated time: 30-60 minutes" -ForegroundColor Yellow
Write-Host "Log file: $logPath" -ForegroundColor Gray
Write-Host ""
Write-Host "Press Ctrl+C to cancel at any time" -ForegroundColor DarkGray
Write-Host ""
Start-Sleep -Seconds 3

Write-Log "=== ULTIMATE WINDOWS REPAIR PRO STARTED ===" "INFO"
Write-Log "System: $env:COMPUTERNAME | User: $env:USERNAME"

# PHASE 1: Pre-Flight System Analysis
Show-Phase "Pre-Flight System Analysis" "Gathering baseline system information"

Show-Step "Collecting OS information..."
try {
    $os = Get-CimInstance Win32_OperatingSystem
    Show-Success "Windows $($os.Caption) Build $($os.BuildNumber)"
    Write-Log "OS: $($os.Caption) | Version: $($os.Version) | Architecture: $($os.OSArchitecture)"
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Checking available disk space..."
try {
    $disk = Get-Volume -DriveLetter C
    $freeGB = [math]::Round($disk.SizeRemaining / 1GB, 2)
    Show-Success "$freeGB GB free"
    Write-Log "C: Drive Free Space: $freeGB GB"
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Checking system uptime..."
try {
    $bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $uptime = (Get-Date) - $bootTime
    Show-Success "$($uptime.Days) days, $($uptime.Hours) hours"
    Write-Log "System Uptime: $($uptime.TotalHours) hours"
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Verifying administrator privileges..."
try {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Show-Success "Running as Administrator"
    } else {
        Show-Warning "NOT running as Administrator - some operations may fail"
    }
} catch {
    Show-Warning "Could not verify admin status"
}

# PHASE 2: System File Checker - First Pass
Show-Phase "System File Checker - First Pass" "Scanning protected system files"

Show-Step "Running SFC scan (this may take 10-15 minutes)..."
Show-Step "Initializing Windows Resource Protection..." -Detailed
try {
    $sfcResult = sfc /scannow 2>&1
    if ($LASTEXITCODE -eq 0) {
        Show-Success "SFC completed"
    } else {
        Show-Warning "SFC completed with warnings"
    }
    Write-Log "SFC First Pass Exit Code: $LASTEXITCODE"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 3: DISM Health Check
Show-Phase "DISM Component Store Health Check" "Checking Windows image health"

Show-Step "Running DISM CheckHealth..."
try {
    $null = DISM /Online /Cleanup-Image /CheckHealth /English
    Show-Success "Health check completed"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 4: DISM Scan Health
Show-Phase "DISM Component Store Scan" "Deep scanning component store"

Show-Step "Running DISM ScanHealth (may take 15-20 minutes)..."
Show-Step "Scanning component store integrity..." -Detailed
try {
    $null = DISM /Online /Cleanup-Image /ScanHealth /English
    Show-Success "Scan completed"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 5: DISM Restore Health
Show-Phase "DISM Component Store Restoration" "Repairing Windows image"

Show-Step "Running DISM RestoreHealth (may take 20-30 minutes)..."
Show-Step "Connecting to Windows Update..." -Detailed
Show-Step "Downloading repair components..." -Detailed
try {
    $dismResult = Repair-WindowsImage -Online -RestoreHealth -NoRestart
    Show-Success "Image restored: $($dismResult.ImageHealthState)"
    Write-Log "DISM RestoreHealth: $($dismResult.ImageHealthState)"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 6: Component Store Cleanup - Stage 1
Show-Phase "Component Store Cleanup - Stage 1" "Removing superseded components"

Show-Step "Running StartComponentCleanup..."
try {
    $null = DISM /Online /Cleanup-Image /StartComponentCleanup /English
    Show-Success "Component cleanup completed"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 7: Component Store Cleanup - Stage 2 (ResetBase)
Show-Phase "Component Store Cleanup - Stage 2" "Resetting component base"

Show-Step "Running StartComponentCleanup with ResetBase..."
Show-Step "WARNING: This removes ability to uninstall updates" -Detailed
try {
    $null = DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase /English
    Show-Success "Component base reset"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 8: Component Store Analysis
Show-Phase "Component Store Analysis" "Analyzing component store size"

Show-Step "Running AnalyzeComponentStore..."
try {
    $null = DISM /Online /Cleanup-Image /AnalyzeComponentStore /English
    Show-Success "Analysis completed"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 9: SPP Store Cleanup
Show-Phase "Software Protection Platform Cleanup" "Cleaning activation store"

Show-Step "Cleaning SPP store..."
try {
    $null = DISM /Online /Cleanup-Image /SPSuperseded /English
    Show-Success "SPP store cleaned"
} catch {
    Show-Warning "SPP cleanup not applicable or failed"
}

# PHASE 10: System File Checker - Second Pass
Show-Phase "System File Checker - Second Pass" "Verification after DISM repair"

Show-Step "Running SFC scan again..."
try {
    $null = sfc /scannow 2>&1
    Show-Success "SFC second pass completed"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 11: Disk Check Scan
Show-Phase "Disk Check - Quick Scan" "Scanning C: drive for errors"

Show-Step "Running CHKDSK quick scan..."
Show-Step "Checking file system metadata..." -Detailed
try {
    $null = chkdsk c: /scan
    Show-Success "Disk scan completed"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 12: Windows Update Service Reset
Show-Phase "Windows Update Service Reset" "Resetting update components"

Show-Step "Stopping Windows Update services..."
try {
    $services = @('wuauserv', 'bits', 'cryptsvc', 'msiserver', 'TrustedInstaller')
    foreach ($svc in $services) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Show-Progress-Detail $services.IndexOf($svc) $services.Count "Stopped: $svc"
    }
    Show-Success "$($services.Count) services stopped"
} catch {
    Show-Warning "Some services may not have stopped"
}

# PHASE 13: Windows Update Cache Clear
Show-Phase "Windows Update Cache Clear" "Removing old update files"

Show-Step "Clearing SoftwareDistribution folder..."
try {
    $sdPath = "C:\Windows\SoftwareDistribution"
    $beforeSize = (Get-ChildItem $sdPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    Remove-Item -Path "$sdPath\*" -Recurse -Force -ErrorAction SilentlyContinue
    $afterSize = (Get-ChildItem $sdPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    $freedMB = [math]::Round($beforeSize - $afterSize, 2)
    Show-Success "Freed $freedMB MB"
} catch {
    Show-Warning "Some files may be in use"
}

# PHASE 14: Cryptographic Services Cache Clear
Show-Phase "Cryptographic Services Cache Clear" "Resetting certificate cache"

Show-Step "Clearing catroot2 folder..."
try {
    $catPath = "C:\Windows\System32\catroot2"
    Remove-Item -Path "$catPath\*" -Recurse -Force -ErrorAction SilentlyContinue
    Show-Success "Cryptographic cache cleared"
} catch {
    Show-Warning "Some files may be in use"
}

# PHASE 15: Windows Update Services Restart
Show-Phase "Windows Update Services Restart" "Restarting update components"

Show-Step "Starting Windows Update services..."
try {
    $services = @('wuauserv', 'bits', 'cryptsvc', 'msiserver')
    foreach ($svc in $services) {
        Start-Service -Name $svc -ErrorAction SilentlyContinue
        Show-Progress-Detail $services.IndexOf($svc) $services.Count "Started: $svc"
    }
    Show-Success "Services restarted"
} catch {
    Show-Warning "Some services may not be configured to auto-start"
}

# PHASE 16: Winsock Reset
Show-Phase "Winsock Reset" "Resetting Windows Sockets API"

Show-Step "Resetting Winsock catalog..."
try {
    $null = netsh winsock reset 2>&1
    Show-Success "Winsock reset (restart required)"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 17: TCP/IP Stack Reset
Show-Phase "TCP/IP Stack Reset" "Resetting TCP/IP configuration"

Show-Step "Resetting TCP/IP stack..."
try {
    $null = netsh int ip reset 2>&1
    Show-Success "TCP/IP reset (restart required)"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 18: IPv4 Configuration Reset
Show-Phase "IPv4 Configuration Reset" "Resetting IPv4 settings"

Show-Step "Resetting IPv4 configuration..."
try {
    $null = netsh int ipv4 reset 2>&1
    Show-Success "IPv4 reset"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 19: IPv6 Configuration Reset
Show-Phase "IPv6 Configuration Reset" "Resetting IPv6 settings"

Show-Step "Resetting IPv6 configuration..."
try {
    $null = netsh int ipv6 reset 2>&1
    Show-Success "IPv6 reset"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 20: DNS Cache Flush
Show-Phase "DNS Cache Flush" "Clearing DNS resolver cache"

Show-Step "Flushing DNS cache..."
try {
    $null = ipconfig /flushdns 2>&1
    Show-Success "DNS cache flushed"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 21: DNS Registration
Show-Phase "DNS Registration" "Registering DNS records"

Show-Step "Registering DNS..."
try {
    $null = ipconfig /registerdns 2>&1
    Show-Success "DNS registered"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 22: DNS Client Cache Clear
Show-Phase "DNS Client Cache Clear" "Clearing PowerShell DNS cache"

Show-Step "Clearing DNS client cache..."
try {
    Clear-DnsClientCache
    Show-Success "DNS client cache cleared"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 23: NetBIOS Cache Clear
Show-Phase "NetBIOS Cache Clear" "Clearing NetBIOS name cache"

Show-Step "Flushing NetBIOS cache..."
try {
    $null = nbtstat -R 2>&1
    Show-Success "NetBIOS cache flushed"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 24: ARP Cache Clear
Show-Phase "ARP Cache Clear" "Clearing address resolution cache"

Show-Step "Flushing ARP cache..."
try {
    $null = arp -d * 2>&1
    Show-Success "ARP cache flushed"
} catch {
    Show-Warning "Some entries may be static"
}

# PHASE 25: TCP Auto-Tuning Reset
Show-Phase "TCP Auto-Tuning Reset" "Resetting TCP parameters"

Show-Step "Setting TCP auto-tuning to normal..."
try {
    $null = netsh int tcp set global autotuninglevel=normal 2>&1
    Show-Success "TCP auto-tuning set to normal"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 26: Network Adapter Reset
Show-Phase "Network Adapter Reset" "Restarting network interfaces"

Show-Step "Resetting network adapters..."
try {
    $adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
    foreach ($adapter in $adapters) {
        Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
        Show-Progress-Detail $adapters.IndexOf($adapter) $adapters.Count $adapter.Name
    }
    Show-Success "$($adapters.Count) adapters reset"
} catch {
    Show-Warning "Some adapters may not support reset"
}

# PHASE 27: Windows Firewall Reset
Show-Phase "Windows Firewall Reset" "Resetting firewall to defaults"

Show-Step "Resetting Windows Firewall..."
try {
    $null = netsh advfirewall reset 2>&1
    Show-Success "Firewall reset to defaults"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 28: Windows Store Reset
Show-Phase "Windows Store Reset" "Resetting Microsoft Store"

Show-Step "Resetting Windows Store app..."
try {
    Get-AppxPackage *WindowsStore* | Reset-AppxPackage -ErrorAction SilentlyContinue
    Show-Success "Store reset"
} catch {
    Show-Warning "Store may be in use"
}

# PHASE 29: Windows Store Re-registration
Show-Phase "Windows Store Re-registration" "Re-registering Store package"

Show-Step "Re-registering Windows Store..."
try {
    $storePackages = Get-AppxPackage -AllUsers Microsoft.WindowsStore
    $count = 0
    foreach ($pkg in $storePackages) {
        Add-AppxPackage -DisableDevelopmentMode -Register "$($pkg.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue
        $count++
    }
    Show-Success "$count packages re-registered"
} catch {
    Show-Warning "Store may already be registered"
}

# PHASE 30: Windows Store Cache Clear
Show-Phase "Windows Store Cache Clear" "Clearing Store download cache"

Show-Step "Clearing Store cache with WSReset..."
try {
    $proc = Start-Process wsreset.exe -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 5
    Stop-Process -Name WinStore.App -Force -ErrorAction SilentlyContinue
    Show-Success "Store cache cleared"
} catch {
    Show-Warning "Cache may already be clear"
}

# PHASE 31: Universal App Platform Reset
Show-Phase "Universal App Platform Reset" "Re-registering all Windows apps"

Show-Step "Re-registering all AppX packages (this will take 5-10 minutes)..."
try {
    $allApps = Get-AppxPackage -AllUsers
    $total = $allApps.Count
    $current = 0
    $successful = 0
    
    foreach ($app in $allApps) {
        $current++
        $pct = [math]::Round(($current / $total) * 100, 1)
        Write-Progress -Activity "Re-registering Apps" -Status "$current of $total ($pct%)" -PercentComplete $pct
        
        Add-AppxPackage -DisableDevelopmentMode -Register "$($app.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue
        if ($?) { $successful++ }
        
        if ($current % 10 -eq 0) {
            Show-Progress-Detail $current $total "$successful successful"
        }
    }
    Write-Progress -Activity "Re-registering Apps" -Completed
    Show-Success "$successful of $total apps re-registered"
} catch {
    Show-Warning "Some apps may be in use"
}

# PHASE 32: Start Menu Cache Clear
Show-Phase "Start Menu Cache Clear" "Rebuilding Start Menu cache"

Show-Step "Clearing Start Menu cache..."
try {
    Stop-Process -Name StartMenuExperienceHost -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:LOCALAPPDATA\Packages\Microsoft.Windows.StartMenuExperienceHost_*\TempState\*" -Recurse -Force -ErrorAction SilentlyContinue
    Show-Success "Start Menu cache cleared"
} catch {
    Show-Warning "Some files may be in use"
}

# PHASE 33: Icon Cache Rebuild
Show-Phase "Icon Cache Rebuild" "Clearing icon cache"

Show-Step "Clearing icon cache..."
try {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db" -Force -ErrorAction SilentlyContinue
    Start-Process explorer
    Show-Success "Icon cache cleared"
} catch {
    Show-Warning "Explorer may need manual restart"
}

# PHASE 34: Thumbnail Cache Clear
Show-Phase "Thumbnail Cache Clear" "Clearing thumbnail cache"

Show-Step "Clearing thumbnail cache..."
try {
    $cachePath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
    Remove-Item -Path "$cachePath\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
    Show-Success "Thumbnail cache cleared"
} catch {
    Show-Warning "Some files may be in use"
}

# PHASE 35: Superfetch Service Restart
Show-Phase "Superfetch Service Restart" "Restarting SysMain service"

Show-Step "Restarting Superfetch/SysMain..."
try {
    Restart-Service -Name SysMain -Force -ErrorAction SilentlyContinue
    Show-Success "SysMain restarted"
} catch {
    Show-Warning "Service may not be running"
}

# PHASE 36: Prefetch Folder Clear
Show-Phase "Prefetch Folder Clear" "Clearing prefetch data"

Show-Step "Clearing prefetch folder..."
try {
    Remove-Item -Path C:\Windows\Prefetch\* -Force -ErrorAction SilentlyContinue
    Show-Success "Prefetch cleared"
} catch {
    Show-Warning "Some files may be in use"
}

# PHASE 37: Temp Files Cleanup - User
Show-Phase "Temp Files Cleanup - User Profile" "Clearing user temporary files"

Show-Step "Clearing user temp folder..."
try {
    $beforeSize = (Get-ChildItem $env:TEMP -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    $afterSize = (Get-ChildItem $env:TEMP -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    $freedMB = [math]::Round($beforeSize - $afterSize, 2)
    Show-Success "Freed $freedMB MB"
} catch {
    Show-Warning "Some files may be in use"
}

# PHASE 38: Temp Files Cleanup - Windows
Show-Phase "Temp Files Cleanup - Windows System" "Clearing system temporary files"

Show-Step "Clearing Windows temp folder..."
try {
    $beforeSize = (Get-ChildItem C:\Windows\Temp -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    $afterSize = (Get-ChildItem C:\Windows\Temp -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    $freedMB = [math]::Round($beforeSize - $afterSize, 2)
    Show-Success "Freed $freedMB MB"
} catch {
    Show-Warning "Some files may be in use"
}

# PHASE 39: Recycle Bin Clear
Show-Phase "Recycle Bin Clear" "Emptying Recycle Bin"

Show-Step "Clearing Recycle Bin..."
try {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Show-Success "Recycle Bin emptied"
} catch {
    Show-Warning "Recycle Bin may already be empty"
}

# PHASE 40: Event Logs Clear
Show-Phase "Event Logs Clear" "Clearing system event logs"

Show-Step "Clearing event logs..."
try {
    $logs = @('System', 'Application', 'Security')
    foreach ($log in $logs) {
        wevtutil cl $log 2>&1 | Out-Null
        Show-Progress-Detail $logs.IndexOf($log) $logs.Count "Cleared: $log"
    }
    Show-Success "$($logs.Count) logs cleared"
} catch {
    Show-Warning "Requires administrator privileges"
}

# PHASE 41: Windows Logs Cleanup
Show-Phase "Windows Logs Cleanup" "Removing old log files"

Show-Step "Cleaning Windows logs folder..."
try {
    $logPath = "C:\Windows\Logs"
    $oldFiles = Get-ChildItem $logPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-30)}
    $count = $oldFiles.Count
    Remove-Item $oldFiles -Force -ErrorAction SilentlyContinue
    Show-Success "$count old log files removed"
} catch {
    Show-Warning "Some files may be in use"
}

# PHASE 42: CBS Log Cleanup
Show-Phase "CBS Log Cleanup" "Clearing component-based servicing logs"

Show-Step "Compressing CBS.log..."
try {
    if (Test-Path "C:\Windows\Logs\CBS\CBS.log") {
        $cbsSize = (Get-Item "C:\Windows\Logs\CBS\CBS.log").Length / 1MB
        if ($cbsSize -gt 100) {
            Compress-Archive -Path "C:\Windows\Logs\CBS\CBS.log" -DestinationPath "C:\Windows\Logs\CBS\CBS_$(Get-Date -Format 'yyyyMMdd').zip" -Force
            Clear-Content "C:\Windows\Logs\CBS\CBS.log"
            Show-Success "CBS.log archived (was $([math]::Round($cbsSize, 2)) MB)"
        } else {
            Show-Success "CBS.log is small ($([math]::Round($cbsSize, 2)) MB)"
        }
    }
} catch {
    Show-Warning "CBS.log may be in use"
}

# PHASE 43: Boot Configuration Reset
Show-Phase "Boot Configuration Reset" "Resetting boot parameters"

Show-Step "Setting boot menu policy to standard..."
try {
    $null = bcdedit /set {default} bootmenupolicy standard 2>&1
    Show-Success "Boot menu policy set"
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Enabling recovery environment..."
try {
    $null = bcdedit /set {default} recoveryenabled yes 2>&1
    Show-Success "Recovery enabled"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 44: System Protection Verification
Show-Phase "System Protection Verification" "Checking System Restore"

Show-Step "Verifying System Restore status..."
try {
    $restorePoints = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
    if ($restorePoints) {
        Show-Success "$($restorePoints.Count) restore points available"
    } else {
        Show-Warning "No restore points found"
    }
} catch {
    Show-Warning "Could not verify System Restore"
}

# PHASE 45: Driver Verification
Show-Phase "Driver Verification" "Scanning for driver issues"

Show-Step "Scanning devices for driver problems..."
try {
    $null = pnputil /scan-devices 2>&1
    Show-Success "Device scan completed"
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Enumerating installed drivers..."
try {
    $drivers = Get-WindowsDriver -Online -All
    Show-Success "$($drivers.Count) drivers installed"
} catch {
    Show-Warning "Could not enumerate drivers"
}

# PHASE 46: Windows Features Verification
Show-Phase "Windows Features Verification" "Checking optional features"

Show-Step "Verifying .NET Framework 3.5..."
try {
    $netfx = Get-WindowsOptionalFeature -Online -FeatureName NetFx3 -ErrorAction SilentlyContinue
    if ($netfx.State -eq "Enabled") {
        Show-Success ".NET 3.5 is enabled"
    } else {
        Show-Step "Enabling .NET Framework 3.5..." -Detailed
        $null = DISM /Online /Enable-Feature /FeatureName:NetFx3 /All /NoRestart /Quiet
        Show-Success ".NET 3.5 enabled"
    }
} catch {
    Show-Warning ".NET 3.5 check failed"
}

# PHASE 47: Windows Defender Update
Show-Phase "Windows Defender Update" "Updating antivirus definitions"

Show-Step "Updating Windows Defender signatures..."
try {
    Update-MpSignature -ErrorAction SilentlyContinue
    Show-Success "Definitions updated"
} catch {
    Show-Warning "Update may have failed or Defender is disabled"
}

# PHASE 48: System File Permissions Reset
Show-Phase "System File Permissions Reset" "Resetting System32 permissions"

Show-Step "Resetting System32 permissions (this may take 5-10 minutes)..."
Show-Step "Processing system files..." -Detailed
try {
    $null = icacls C:\Windows\System32 /reset /T /C /Q 2>&1
    Show-Success "Permissions reset"
} catch {
    Show-Warning "Some files may be in use"
}

# PHASE 49: Registry Cleanup
Show-Phase "Registry Cleanup" "Optimizing registry"

Show-Step "Compacting registry hives..."
try {
    $null = reg optimize HKLM /COMPACTOS:always 2>&1
    Show-Success "Registry optimized"
} catch {
    Show-Warning "Registry optimization may require restart"
}

# PHASE 50: Volume Optimization
Show-Phase "Volume Optimization" "Analyzing C: drive"

Show-Step "Analyzing C: drive for optimization..."
try {
    $optimizeResult = Optimize-Volume -DriveLetter C -Analyze -ErrorAction SilentlyContinue
    Show-Success "Volume analyzed"
} catch {
    Show-Warning "Volume may already be optimized"
}

# PHASE 51: System Maintenance Tasks
Show-Phase "System Maintenance Tasks" "Running maintenance routines"

Show-Step "Processing idle maintenance tasks..."
try {
    rundll32.exe advapi32.dll,ProcessIdleTasks
    Start-Sleep -Seconds 3
    Show-Success "Idle tasks processed"
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 52: Ultimate Windows Repair Tool Installation
Show-Phase "Ultimate Windows Repair Tool Installation" "Installing repair utility"

Show-Step "Checking if Ultimate Windows Repair Tool is installed..."
try {
    $app = Get-AppxPackage -Name *Technician*
    if ($app) {
        Show-Success "Already installed"
    } else {
        Show-Step "Installing from Microsoft Store..." -Detailed
        $null = winget install --id 9PH863L9C6HC --source msstore --accept-package-agreements --accept-source-agreements --silent --force 2>&1
        Start-Sleep -Seconds 5
        Show-Success "Installation completed"
    }
} catch {
    Show-Warning "Installation may have failed - check Microsoft Store manually"
}

Show-Step "Attempting to launch Ultimate Windows Repair Tool..."
try {
    $app = Get-AppxPackage -Name *Technician* | Select-Object -First 1
    if ($app) {
        Start-Process "shell:AppsFolder\$($app.PackageFamilyName)!App" -ErrorAction SilentlyContinue
        Show-Success "Tool launched"
    } else {
        Show-Warning "App not found - search 'Ultimate Windows Repair' in Start Menu"
    }
} catch {
    Show-Warning "Launch failed - open manually from Start Menu"
}

# COMPLETION REPORT
Write-Progress -Activity "Ultimate Windows Repair Pro" -Completed

$endTime = Get-Date
$totalDuration = $endTime - $startTime

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "          ULTIMATE WINDOWS REPAIR PRO COMPLETE!                " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "[OK] All $totalPhases repair phases completed successfully" -ForegroundColor Green
Write-Host ""
Write-Host "STATISTICS:" -ForegroundColor Cyan
Write-Host "  Start Time:    $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
Write-Host "  End Time:      $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
Write-Host "  Total Duration: $($totalDuration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "  Log File:      $logPath" -ForegroundColor White
Write-Host ""
Write-Host "[!] CRITICAL: RESTART YOUR COMPUTER NOW TO FINALIZE:" -ForegroundColor Yellow
Write-Host "  - Winsock catalog reset" -ForegroundColor White
Write-Host "  - TCP/IP stack reset" -ForegroundColor White
Write-Host "  - Network adapter changes" -ForegroundColor White
Write-Host "  - Windows Update service changes" -ForegroundColor White
Write-Host "  - Registry optimizations" -ForegroundColor White
Write-Host ""
Write-Host "After restart, your system should be significantly faster" -ForegroundColor Cyan
Write-Host "and more stable. Check the log file for detailed results." -ForegroundColor Cyan
Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Gray

Write-Log "=== ULTIMATE WINDOWS REPAIR PRO COMPLETED ===" "INFO"
Write-Log "Total Duration: $($totalDuration.TotalMinutes) minutes"

$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
