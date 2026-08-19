$key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install"
if (Test-Path $key) {
    $install = Get-ItemProperty $key
    Write-Host "Last install result: $($install.LastSuccessTime) - $($install.LastErrorCode)"
}

$key2 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Download"
if (Test-Path $key2) {
    $download = Get-ItemProperty $key2
    Write-Host "Last download result: $($download.LastSuccessTime) - $($download.LastErrorCode)"
}

$key3 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services\Pending"
if (Test-Path $key3) {
    $pending = Get-ItemProperty $key3
    Write-Host "Pending service count: $($pending.ServiceID.Count)"
} else {
    Write-Host "No pending services in registry"
}

Write-Host "`n=== Checking Windows Update services ==="
Get-Service wuauserv, BITS, CryptSvc, TrustedInstaller | Select-Object Name, Status, StartType | Format-Table -AutoSize