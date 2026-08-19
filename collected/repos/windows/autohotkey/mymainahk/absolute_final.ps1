Write-Host "=== ABSOLUTE FINAL VERIFICATION ===" -ForegroundColor Cyan

Write-Host "`n[Checking Registry for Pending Updates]"
$pendingReg = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install"
if (Test-Path $pendingReg) {
    $regData = Get-ItemProperty $pendingReg
    Write-Host "Last install result: $($regData.LastSuccessTime)"
    Write-Host "Last error code: $($regData.LastErrorCode)"
}

$downloadReg = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Download"
if (Test-Path $downloadReg) {
    $dlData = Get-ItemProperty $downloadReg
    Write-Host "Last download result: $($dlData.LastSuccessTime)"
    Write-Host "Last download error: $($dlData.LastErrorCode)"
}

Write-Host "`n[Checking SUSDB Database]"
$session = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()
$searcher.ServerSelection = 2

$allUpdates = $searcher.Search("IsInstalled=0")
Write-Host "Updates in all categories: $($allUpdates.Result.Updates.Count)"

if ($allUpdates.Result.Updates.Count -gt 0) {
    Write-Host "FOUND PENDING UPDATES:"
    $allUpdates.Result.Updates | ForEach-Object {
        Write-Host "  - $($_.Title)"
        Write-Host "    KB: $($_.KBArticleIDs)"
    }
} else {
    Write-Host "NO PENDING UPDATES IN DATABASE"
}

Write-Host "`n[Checking Windows Update Client State]"
$clientState = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Client\State"
if (Test-Path $clientState) {
    Get-ItemProperty $clientState | Format-List
}

Write-Host "`n[Checking Pending Scan]"
$scanPath = "C:\Windows\SoftwareDistribution\ReportingEvents"
$events = Get-ChildItem $scanPath -Filter "*.xml" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3
Write-Host "Recent reporting events: $($events.Count)"
$events | ForEach-Object { Write-Host "  $($_.Name) - $($_.LastWriteTime)" }

Write-Host "`n[Final COM Check]"
$final = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher().Search("IsInstalled=0")
Write-Host "FINAL RESULT: $($final.Result.Updates.Count) pending updates"

if ($final.Result.Updates.Count -eq 0) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "ABSOLUTELY ZERO PENDING UPDATES" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "PENDING UPDATES FOUND!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
}