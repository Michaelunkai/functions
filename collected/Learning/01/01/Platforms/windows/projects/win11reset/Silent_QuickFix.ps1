#Requires -RunAsAdministrator
# Silent Quick Fix - For scheduled tasks or automation
# No prompts, no output, just fixes

$logFile = "$PSScriptRoot\silent_quickfix_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$ErrorActionPreference = "Continue"

function Log($msg) { "$(Get-Date -Format 'HH:mm:ss') $msg" | Out-File $logFile -Append }

Log "=== Silent QuickFix Started ==="

# Stop services
@("wuauserv", "bits", "cryptsvc") | ForEach-Object { Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue }
Log "Services stopped"

# Fix chkdsk
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name BootExecute -Value "autocheck autochk *" -Type MultiString -ErrorAction SilentlyContinue
Log "Chkdsk registry fixed"

# DISM
$dism = Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -Wait -PassThru -WindowStyle Hidden
Log "DISM exit: $($dism.ExitCode)"

# SFC
$sfc = Start-Process "sfc.exe" -ArgumentList "/scannow" -Wait -PassThru -WindowStyle Hidden
Log "SFC exit: $($sfc.ExitCode)"

# Reset WU cache
$ts = Get-Date -Format 'yyyyMMddHHmmss'
$sdPath = "$env:SystemRoot\SoftwareDistribution"
if (Test-Path $sdPath) { Rename-Item $sdPath "$sdPath.old.$ts" -Force -ErrorAction SilentlyContinue }
@("wuapi.dll", "wuaueng.dll", "wups.dll") | ForEach-Object { regsvr32.exe /s $_ 2>$null }
Log "WU reset"

# Restart services
@("cryptsvc", "bits", "wuauserv") | ForEach-Object { Start-Service -Name $_ -ErrorAction SilentlyContinue }
Log "Services restarted"

Log "=== Silent QuickFix Complete ==="
