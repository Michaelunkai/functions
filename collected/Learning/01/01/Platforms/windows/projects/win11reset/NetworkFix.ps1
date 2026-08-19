#Requires -RunAsAdministrator
# Windows 11 Network Fix
# Comprehensive network troubleshooting

$ErrorActionPreference = "Continue"
$logFile = "$PSScriptRoot\network_fix_log.txt"

function Log {
    param([string]$msg, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $msg"
    $color = switch($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } "SUCCESS" { "Green" } default { "White" } }
    Write-Host $line -ForegroundColor $color
    $line | Out-File -FilePath $logFile -Append -Encoding UTF8
}

Clear-Host
Write-Host "`n  ============ NETWORK FIX ============" -ForegroundColor Cyan
Write-Host "  Fixing common network issues...`n" -ForegroundColor White

Remove-Item $logFile -Force -ErrorAction SilentlyContinue
Log "=== Network Fix Started ==="

# Step 1: Diagnose current state
Write-Host "[1/8] Diagnosing current network state..." -ForegroundColor Yellow
$adapters = Get-NetAdapter | Where-Object Status -eq "Up"
Log "Active adapters: $($adapters.Count)"
$adapters | ForEach-Object { Log "  - $($_.Name): $($_.InterfaceDescription)" }

# Check internet connectivity
$ping = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction SilentlyContinue
if ($ping) {
    Log "Internet: Connected" "SUCCESS"
} else {
    Log "Internet: NOT connected" "WARN"
}

# Check DNS
$dns = Resolve-DnsName google.com -ErrorAction SilentlyContinue
if ($dns) {
    Log "DNS: Working" "SUCCESS"
} else {
    Log "DNS: NOT working" "WARN"
}

# Step 2: Release/Renew IP
Write-Host "`n[2/8] Releasing and renewing IP address..." -ForegroundColor Yellow
ipconfig /release 2>&1 | Out-Null
Start-Sleep -Seconds 2
ipconfig /renew 2>&1 | Out-Null
Log "IP renewed"

# Step 3: Flush DNS
Write-Host "`n[3/8] Flushing DNS cache..." -ForegroundColor Yellow
ipconfig /flushdns 2>&1 | Out-Null
Clear-DnsClientCache
Log "DNS cache flushed"

# Step 4: Reset Winsock
Write-Host "`n[4/8] Resetting Winsock catalog..." -ForegroundColor Yellow
netsh winsock reset 2>&1 | Out-Null
Log "Winsock reset (needs reboot)"

# Step 5: Reset IP stack
Write-Host "`n[5/8] Resetting TCP/IP stack..." -ForegroundColor Yellow
netsh int ip reset 2>&1 | Out-Null
Log "IP stack reset (needs reboot)"

# Step 6: Reset firewall
Write-Host "`n[6/8] Resetting Windows Firewall..." -ForegroundColor Yellow
netsh advfirewall reset 2>&1 | Out-Null
Log "Firewall reset to defaults"

# Step 7: Set DNS to Cloudflare/Google (often fixes issues)
Write-Host "`n[7/8] Optimizing DNS servers..." -ForegroundColor Yellow
$adapters | ForEach-Object {
    # Primary: Cloudflare (1.1.1.1), Secondary: Google (8.8.8.8)
    Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses ("1.1.1.1","8.8.8.8") -ErrorAction SilentlyContinue
    Log "Set DNS for $($_.Name): 1.1.1.1, 8.8.8.8"
}

# Step 8: Restart network adapters
Write-Host "`n[8/8] Restarting network adapters..." -ForegroundColor Yellow
$adapters | ForEach-Object {
    Restart-NetAdapter -Name $_.Name -ErrorAction SilentlyContinue
    Log "Restarted: $($_.Name)"
}
Start-Sleep -Seconds 5

# Final check
Write-Host "`n>>> Final Connectivity Check..." -ForegroundColor Cyan
$pingFinal = Test-Connection -ComputerName 8.8.8.8 -Count 3 -Quiet -ErrorAction SilentlyContinue
$dnsFinal = Resolve-DnsName google.com -ErrorAction SilentlyContinue

Write-Host ""
if ($pingFinal) {
    Write-Host "  [OK] Internet: Connected" -ForegroundColor Green
} else {
    Write-Host "  [!] Internet: Still not connected (try rebooting)" -ForegroundColor Red
}

if ($dnsFinal) {
    Write-Host "  [OK] DNS: Working" -ForegroundColor Green
} else {
    Write-Host "  [!] DNS: Still not working (try rebooting)" -ForegroundColor Red
}

Log "=== Network Fix Complete ==="
Write-Host "`n  A reboot is recommended to complete all fixes." -ForegroundColor Yellow
Write-Host "  Log: $logFile" -ForegroundColor Gray

Write-Host "`n  Reboot now? (Y/N): " -NoNewline -ForegroundColor Cyan
$reboot = Read-Host
if ($reboot -eq "Y") {
    Write-Host "  Rebooting in 5 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    Restart-Computer -Force
} else {
    Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
