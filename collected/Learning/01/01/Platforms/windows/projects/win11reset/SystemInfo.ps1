#Requires -RunAsAdministrator
# Windows 11 System Information Collector
# Gathers comprehensive system info for troubleshooting

$reportPath = "$PSScriptRoot\system_info_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

function Section { param([string]$Title) 
    "`n" + "=" * 60 + "`n$Title`n" + "=" * 60
}

Clear-Host
Write-Host "`n  ============ SYSTEM INFO COLLECTOR ============" -ForegroundColor Cyan
Write-Host "  Gathering comprehensive system information...`n" -ForegroundColor White

$report = @()
$report += "WINDOWS 11 SYSTEM INFORMATION REPORT"
$report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$report += "Computer: $env:COMPUTERNAME"

# OS Info
Write-Host "[1/10] Operating System..." -ForegroundColor Yellow
$os = Get-CimInstance Win32_OperatingSystem
$report += Section "OPERATING SYSTEM"
$report += "Name: $($os.Caption)"
$report += "Version: $($os.Version)"
$report += "Build: $($os.BuildNumber)"
$report += "Architecture: $($os.OSArchitecture)"
$report += "Install Date: $($os.InstallDate)"
$report += "Last Boot: $($os.LastBootUpTime)"
$uptime = (Get-Date) - $os.LastBootUpTime
$report += "Uptime: $([math]::Floor($uptime.TotalDays)) days, $($uptime.Hours) hours, $($uptime.Minutes) minutes"

# Hardware
Write-Host "[2/10] Hardware Info..." -ForegroundColor Yellow
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$report += Section "HARDWARE"
$report += "Manufacturer: $($cs.Manufacturer)"
$report += "Model: $($cs.Model)"
$report += "CPU: $($cpu.Name)"
$report += "CPU Cores: $($cpu.NumberOfCores) cores, $($cpu.NumberOfLogicalProcessors) threads"
$report += "RAM: $([math]::Round($cs.TotalPhysicalMemory / 1GB, 2)) GB"

# Disk
Write-Host "[3/10] Disk Info..." -ForegroundColor Yellow
$report += Section "DISK STORAGE"
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $free = [math]::Round($_.FreeSpace / 1GB, 2)
    $total = [math]::Round($_.Size / 1GB, 2)
    $used = $total - $free
    $pct = [math]::Round(($used / $total) * 100, 1)
    $report += "$($_.DeviceID) $used GB used / $total GB total ($pct% full, $free GB free)"
}

# Disk Health
Write-Host "[4/10] Disk Health..." -ForegroundColor Yellow
$report += Section "DISK HEALTH"
$physicalDisks = Get-PhysicalDisk
foreach ($disk in $physicalDisks) {
    $report += "Disk: $($disk.FriendlyName)"
    $report += "  Media Type: $($disk.MediaType)"
    $report += "  Health: $($disk.HealthStatus)"
    $report += "  Operational: $($disk.OperationalStatus)"
    $report += "  Size: $([math]::Round($disk.Size / 1GB, 2)) GB"
}

# Chkdsk Status
Write-Host "[5/10] Chkdsk Status..." -ForegroundColor Yellow
$report += Section "CHKDSK CONFIGURATION"
$bootExec = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name BootExecute -ErrorAction SilentlyContinue).BootExecute
$report += "BootExecute: $bootExec"
if ($bootExec -match "autocheck autochk \*") {
    $report += "Status: PROPERLY CONFIGURED"
} else {
    $report += "Status: !!! NOT PROPERLY CONFIGURED !!!"
}
$fsutil = & fsutil dirty query C: 2>&1
$report += "Volume C: $fsutil"

# Windows Update
Write-Host "[6/10] Windows Update..." -ForegroundColor Yellow
$report += Section "WINDOWS UPDATE"
$wuService = Get-Service wuauserv -ErrorAction SilentlyContinue
$report += "Service Status: $($wuService.Status)"
$sdPath = "$env:SystemRoot\SoftwareDistribution"
if (Test-Path $sdPath) {
    $size = [math]::Round((Get-ChildItem $sdPath -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 2)
    $report += "Cache Size: $size MB"
}
# Last update check
try {
    $au = New-Object -ComObject Microsoft.Update.AutoUpdate
    $report += "Last Search: $($au.Results.LastSearchSuccessDate)"
    $report += "Last Install: $($au.Results.LastInstallationSuccessDate)"
} catch { }

# Pending Reboots
Write-Host "[7/10] Pending Operations..." -ForegroundColor Yellow
$report += Section "PENDING OPERATIONS"
$pendingReboot = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
$pendingUpdate = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
$pendingRename = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
$report += "Reboot Pending (CBS): $(if($pendingReboot){'YES'}else{'No'})"
$report += "Reboot Pending (WU): $(if($pendingUpdate){'YES'}else{'No'})"
$report += "File Rename Pending: $(if($pendingRename){'YES'}else{'No'})"

# Services
Write-Host "[8/10] Critical Services..." -ForegroundColor Yellow
$report += Section "CRITICAL SERVICES"
$criticalServices = @("wuauserv", "bits", "cryptsvc", "TrustedInstaller", "WSearch", "Winmgmt", "EventLog")
foreach ($svc in $criticalServices) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s) {
        $report += "$($svc): $($s.Status) ($($s.StartType))"
    }
}

# Recent Errors
Write-Host "[9/10] Recent System Errors..." -ForegroundColor Yellow
$report += Section "RECENT SYSTEM ERRORS (Last 24h)"
$since = (Get-Date).AddHours(-24)
$errors = Get-WinEvent -FilterHashtable @{LogName='System'; Level=2; StartTime=$since} -MaxEvents 10 -ErrorAction SilentlyContinue
if ($errors) {
    foreach ($e in $errors) {
        $report += "[$($e.TimeCreated.ToString('HH:mm:ss'))] $($e.ProviderName): $($e.Message.Split("`n")[0])"
    }
} else {
    $report += "No critical errors in the last 24 hours"
}

# Startup Programs
Write-Host "[10/10] Startup Programs..." -ForegroundColor Yellow
$report += Section "STARTUP PROGRAMS (Registry)"
$startupReg = Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
if ($startupReg) {
    $startupReg.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
        $report += "$($_.Name): $($_.Value)"
    }
}

# Summary
$report += Section "SUMMARY"
$issues = @()
if (-not ($bootExec -match "autocheck autochk \*")) { $issues += "Chkdsk not properly configured" }
if ($pendingReboot -or $pendingUpdate) { $issues += "Reboot pending" }
if ($size -gt 500) { $issues += "Windows Update cache bloated ($size MB)" }
if ($wuService.Status -ne "Running") { $issues += "Windows Update service not running" }

if ($issues.Count -eq 0) {
    $report += "No major issues detected!"
} else {
    $report += "Issues Found:"
    $issues | ForEach-Object { $report += "  - $_" }
    $report += "`nRecommendation: Run QUICK_FIX.bat or DEEP_REPAIR.bat"
}

# Save report
$report | Out-File $reportPath -Encoding UTF8
Write-Host "`n  Report saved to:" -ForegroundColor Green
Write-Host "  $reportPath" -ForegroundColor Cyan

# Display summary
Write-Host "`n  ============ SUMMARY ============" -ForegroundColor Cyan
if ($issues.Count -eq 0) {
    Write-Host "  No major issues detected!" -ForegroundColor Green
} else {
    Write-Host "  Issues Found:" -ForegroundColor Yellow
    $issues | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
}

Write-Host "`nPress any key to open the report..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
notepad $reportPath
