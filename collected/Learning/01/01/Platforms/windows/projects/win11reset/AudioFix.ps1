#Requires -RunAsAdministrator
# Windows 11 Audio Fix
# Fixes common audio problems

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "`n  ============ AUDIO FIX ============" -ForegroundColor Yellow
Write-Host "  Fixing common audio issues...`n" -ForegroundColor White

# Step 1: Restart audio services
Write-Host "[1/5] Restarting audio services..." -ForegroundColor Yellow
$audioServices = @("AudioSrv", "AudioEndpointBuilder", "Audiosrv")
foreach ($svc in $audioServices) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        Restart-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Write-Host "  Restarted: $svc" -ForegroundColor Gray
    }
}
Write-Host "  [OK] Audio services restarted" -ForegroundColor Green

# Step 2: Reset audio endpoint
Write-Host "`n[2/5] Resetting audio endpoint..." -ForegroundColor Yellow
Stop-Service -Name "AudioEndpointBuilder" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Service -Name "AudioEndpointBuilder" -ErrorAction SilentlyContinue
Write-Host "  [OK] Endpoint reset" -ForegroundColor Green

# Step 3: Re-enable audio devices
Write-Host "`n[3/5] Re-enabling audio devices..." -ForegroundColor Yellow
Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Error" } | ForEach-Object {
    Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  Enabled: $($_.FriendlyName)" -ForegroundColor Gray
}
Get-PnpDevice -Class Media -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Error" } | ForEach-Object {
    Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  Enabled: $($_.FriendlyName)" -ForegroundColor Gray
}
Write-Host "  [OK] Devices checked" -ForegroundColor Green

# Step 4: Reset audio settings
Write-Host "`n[4/5] Resetting audio settings..." -ForegroundColor Yellow
# Reset spatial sound
$regPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Audio"
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name "EnableSpatialAudio" -Value 0 -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Settings reset" -ForegroundColor Green

# Step 5: Run audio troubleshooter
Write-Host "`n[5/5] Running audio troubleshooter..." -ForegroundColor Yellow
Start-Process "msdt.exe" -ArgumentList "/id AudioPlaybackDiagnostic" -Wait -ErrorAction SilentlyContinue
Write-Host "  [OK] Troubleshooter launched" -ForegroundColor Green

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
Write-Host "  Audio should now be working." -ForegroundColor White
Write-Host "  If not, check Settings > Sound" -ForegroundColor Gray

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
