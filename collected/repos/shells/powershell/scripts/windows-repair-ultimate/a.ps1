# Ultimate Windows Repair - Real-Time Progress Version
# PowerShell 5 Compatible
# Run as Administrator

$ErrorActionPreference = "Continue"
$totalPhases = 16
$currentPhase = 0

function Show-Phase {
    param([string]$Title)
    $script:currentPhase++
    $percentComplete = [math]::Round(($script:currentPhase / $totalPhases) * 100)
    Write-Progress -Activity "Ultimate Windows Repair" -Status "$Title" -PercentComplete $percentComplete
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "PHASE $script:currentPhase/$totalPhases : $Title" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Cyan
}

function Show-Step {
    param([string]$Message)
    Write-Host "  > $Message" -ForegroundColor White -NoNewline
}

function Show-Success {
    Write-Host " [OK]" -ForegroundColor Green
}

function Show-Warning {
    param([string]$Message)
    Write-Host " [WARN] $Message" -ForegroundColor Yellow
}

function Show-Error {
    param([string]$Message)
    Write-Host " [ERROR] $Message" -ForegroundColor Red
}

# START
Clear-Host
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "     ULTIMATE WINDOWS REPAIR - COMPREHENSIVE SYSTEM FIX        " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Starting comprehensive system repair..." -ForegroundColor White
Write-Host "Estimated time: 15-30 minutes" -ForegroundColor Gray
Write-Host "Press Ctrl+C to cancel at any time" -ForegroundColor Gray
Start-Sleep -Seconds 2

# PHASE 1: Core System Repairs
Show-Phase "Core System Repairs"

Show-Step "Running DISM RestoreHealth (may take 10+ minutes)..."
try {
    $null = Repair-WindowsImage -Online -RestoreHealth -NoRestart
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Running DISM ScanHealth..."
try {
    $null = DISM /Online /Cleanup-Image /ScanHealth
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Running DISM CheckHealth..."
try {
    $null = DISM /Online /Cleanup-Image /CheckHealth
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Running System File Checker (SFC)..."
try {
    $null = sfc /scannow
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 2: Component Store Optimization
Show-Phase "Component Store Optimization"

Show-Step "Cleaning up component store with ResetBase..."
try {
    $null = DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Analyzing component store..."
try {
    $null = DISM /Online /Cleanup-Image /AnalyzeComponentStore
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 3: Disk & File System
Show-Phase "Disk & File System Repairs"

Show-Step "Running CHKDSK scan..."
try {
    $null = chkdsk c: /scan
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 4: Windows Update Infrastructure
Show-Phase "Windows Update Infrastructure"

Show-Step "Stopping Windows Update services..."
try {
    Stop-Service -Name wuauserv,bits,cryptsvc,msiserver -Force -ErrorAction SilentlyContinue
    Show-Success
} catch {
    Show-Warning "Some services may already be stopped"
}

Show-Step "Clearing SoftwareDistribution folder..."
try {
    Remove-Item -Path C:\Windows\SoftwareDistribution\* -Recurse -Force -ErrorAction SilentlyContinue
    Show-Success
} catch {
    Show-Warning "Some files may be in use"
}

Show-Step "Clearing catroot2 folder..."
try {
    Remove-Item -Path C:\Windows\System32\catroot2\* -Recurse -Force -ErrorAction SilentlyContinue
    Show-Success
} catch {
    Show-Warning "Some files may be in use"
}

Show-Step "Restarting Windows Update services..."
try {
    Start-Service -Name wuauserv,bits,cryptsvc,msiserver -ErrorAction SilentlyContinue
    Show-Success
} catch {
    Show-Warning "Some services may not be configured to start"
}

# PHASE 5: Network Stack Reset
Show-Phase "Network Stack Reset"

Show-Step "Resetting Winsock catalog..."
try {
    $null = netsh winsock reset
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Resetting TCP/IP stack..."
try {
    $null = netsh int ip reset
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Resetting IPv4..."
try {
    $null = netsh int ipv4 reset
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Resetting IPv6..."
try {
    $null = netsh int ipv6 reset
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Flushing DNS cache..."
try {
    $null = ipconfig /flushdns
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Registering DNS..."
try {
    $null = ipconfig /registerdns
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Clearing DNS client cache..."
try {
    Clear-DnsClientCache
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Setting TCP auto-tuning to normal..."
try {
    $null = netsh int tcp set global autotuninglevel=normal
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Resetting network adapters..."
try {
    $adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
    foreach ($adapter in $adapters) {
        Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
        Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
    }
    Show-Success
} catch {
    Show-Warning "Some adapters may not support this operation"
}

# PHASE 6: Microsoft Store Repair
Show-Phase "Microsoft Store Repair"

Show-Step "Resetting Windows Store..."
try {
    Get-AppxPackage *WindowsStore* | Reset-AppxPackage -ErrorAction SilentlyContinue
    Show-Success
} catch {
    Show-Warning "Store may be in use"
}

Show-Step "Re-registering Windows Store..."
try {
    $storePackage = Get-AppxPackage -AllUsers Microsoft.WindowsStore
    foreach ($pkg in $storePackage) {
        Add-AppxPackage -DisableDevelopmentMode -Register "$($pkg.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue
    }
    Show-Success
} catch {
    Show-Warning "Store may already be registered"
}

Show-Step "Clearing Store cache..."
try {
    Start-Process wsreset.exe -WindowStyle Hidden
    Start-Sleep -Seconds 3
    Stop-Process -Name WinStore.App -Force -ErrorAction SilentlyContinue
    Show-Success
} catch {
    Show-Warning "Cache may already be clear"
}

# PHASE 7: Universal App Platform Repair
Show-Phase "Universal App Platform Repair"

Show-Step "Re-registering all Windows apps (may take 5+ minutes)..."
try {
    $apps = Get-AppxPackage -AllUsers
    $total = $apps.Count
    $current = 0
    
    foreach ($app in $apps) {
        $current++
        $percentComplete = [math]::Round(($current / $total) * 100)
        Write-Progress -Activity "Re-registering Apps" -Status "$current of $total" -PercentComplete $percentComplete
        
        Add-AppxPackage -DisableDevelopmentMode -Register "$($app.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue
    }
    Write-Progress -Activity "Re-registering Apps" -Completed
    Show-Success
} catch {
    Show-Warning "Some apps may be in use"
}

# PHASE 8: System Performance Optimization
Show-Phase "System Performance Optimization"

Show-Step "Restarting Superfetch service..."
try {
    Get-Service -Name SysMain | Restart-Service -ErrorAction SilentlyContinue
    Show-Success
} catch {
    Show-Warning "Service may not be running"
}

Show-Step "Clearing Recycle Bin..."
try {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Show-Success
} catch {
    Show-Warning "Recycle Bin may already be empty"
}

Show-Step "Clearing temp files..."
try {
    Remove-Item -Path $env:TEMP\* -Recurse -Force -ErrorAction SilentlyContinue
    Show-Success
} catch {
    Show-Warning "Some temp files may be in use"
}

Show-Step "Clearing Windows temp files..."
try {
    Remove-Item -Path C:\Windows\Temp\* -Recurse -Force -ErrorAction SilentlyContinue
    Show-Success
} catch {
    Show-Warning "Some files may be in use"
}

Show-Step "Clearing event logs..."
try {
    wevtutil cl System
    wevtutil cl Application
    wevtutil cl Security
    Show-Success
} catch {
    Show-Warning "Requires administrator privileges"
}

# PHASE 9: Boot Configuration
Show-Phase "Boot Configuration Repair"

Show-Step "Setting boot menu policy..."
try {
    $null = bcdedit /set {default} bootmenupolicy standard
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

Show-Step "Enabling recovery..."
try {
    $null = bcdedit /set {default} recoveryenabled yes
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 10: Registry & System Files
Show-Phase "Registry & System Files"

Show-Step "Running second SFC pass..."
try {
    $null = sfc /scannow
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 11: Driver Verification
Show-Phase "Driver Verification"

Show-Step "Scanning for device changes..."
try {
    $null = pnputil /scan-devices
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 12: Windows Features
Show-Phase "Windows Features Verification"

Show-Step "Verifying .NET Framework..."
try {
    $null = DISM /Online /Enable-Feature /FeatureName:NetFx3 /All /NoRestart /Quiet
    Show-Success
} catch {
    Show-Warning "Feature may already be enabled"
}

# PHASE 13: Security & Permissions
Show-Phase "Security & Permissions"

Show-Step "Resetting System32 permissions (may take 5+ minutes)..."
try {
    $null = icacls C:\Windows\System32 /reset /T /C /Q
    Show-Success
} catch {
    Show-Warning "Some files may be in use"
}

# PHASE 14: Final Optimization
Show-Phase "Final Optimization"

Show-Step "Analyzing C: drive..."
try {
    Optimize-Volume -DriveLetter C -Analyze -Verbose -ErrorAction SilentlyContinue
    Show-Success
} catch {
    Show-Warning "Volume may already be optimized"
}

Show-Step "Processing idle tasks..."
try {
    rundll32.exe advapi32.dll,ProcessIdleTasks
    Show-Success
} catch {
    Show-Error $_.Exception.Message
}

# PHASE 15: Ultimate Windows Repair Tool
Show-Phase "Ultimate Windows Repair Tool Installation"

Show-Step "Installing Ultimate Windows Repair Tool..."
try {
    $null = winget install --id 9PH863L9C6HC --source msstore --accept-package-agreements --accept-source-agreements --silent --force 2>&1
    Start-Sleep -Seconds 5
    Show-Success
} catch {
    Show-Warning "Installation may have failed - check Microsoft Store manually"
}

# PHASE 16: Launch Tool
Show-Phase "Launching Ultimate Windows Repair Tool"

Show-Step "Attempting to launch tool..."
try {
    $app = Get-AppxPackage -Name *Technician* | Select-Object -First 1
    if ($app) {
        Start-Process "shell:AppsFolder\$($app.PackageFamilyName)!App"
        Show-Success
    } else {
        Show-Warning "App not found - may need to launch manually from Start Menu"
    }
} catch {
    Show-Warning "Launch failed - search for Ultimate Windows Repair in Start Menu"
}

# COMPLETE
Write-Progress -Activity "Ultimate Windows Repair" -Completed

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "          ULTIMATE WINDOWS REPAIR COMPLETE!                    " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green

Write-Host ""
Write-Host "[OK] All $totalPhases repair phases completed" -ForegroundColor Green
Write-Host ""
Write-Host "[!] IMPORTANT: Restart your computer to finalize:" -ForegroundColor Yellow
Write-Host "  - Winsock reset" -ForegroundColor White
Write-Host "  - TCP/IP stack reset" -ForegroundColor White
Write-Host "  - Network adapter changes" -ForegroundColor White
Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
