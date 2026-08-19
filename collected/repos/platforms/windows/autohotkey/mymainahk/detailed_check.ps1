Write-Host "=== DETAILED FAILED DOWNLOAD INVESTIGATION ==="
Write-Host ""

$session = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()

Write-Host "[1] Searching for ALL available updates (not just pending)..."
try {
    $allUpdates = $searcher.Search("IsInstalled=0 and Type='Software'")
    Write-Host "Total available updates: $($allUpdates.Result.Updates.Count)"
    $allUpdates.Result.Updates | ForEach-Object {
        Write-Host "  - $($_.Title)"
        Write-Host "    State: $($_.InstallationBehavior.Required)"
    }
} catch {
    Write-Host "Error searching: $_"
}

Write-Host ""
Write-Host "[2] Checking Update Services..."
$services = $searcher.GetServices()
Write-Host "Registered services: $($services.Count)"
$services | ForEach-Object {
    Write-Host "  - $($_.Name): $($_.IsRegistered)"
}

Write-Host ""
Write-Host "[3] Checking for hidden updates..."
$searcher2 = $session.CreateUpdateSearcher()
$searcher2.ServerSelection = 3
try {
    $hidden = $searcher2.Search("IsInstalled=0")
    Write-Host "Hidden updates: $($hidden.Result.Updates.Count)"
} catch {
    Write-Host "Error checking hidden: $_"
}

Write-Host ""
Write-Host "[4] Checking Windows Update.log via ETW..."
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-WindowsUpdateClient/Operational'; Id=31; StartTime=(Get-Date).AddHours(-1)} -MaxEvents 10 -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  $($_.TimeCreated): $($_.Message)"
}