$Session = New-Object -ComObject Microsoft.Update.Session
$Searcher = $Session.CreateUpdateSearcher()
$Updates = $Searcher.Search("IsInstalled=0").Updates
Write-Host "Uninstalled updates (pending install): $($Updates.Count)"
if ($Updates.Count -gt 0) {
    foreach ($Update in $Updates) {
        Write-Host "Title: $($Update.Title)"
        Write-Host "State: $($Update.InstallationBehavior.AsyncState)"
        Write-Host "---"
    }
}

$Downloader = $Session.CreateUpdateDownloader()
$Downloader.Queries = $Updates
$Downloader.IsForced = $true
try {
    $result = $Downloader.BeginDownload($null, $null)
    Write-Host "Download check started..."
} catch {
    Write-Host "No pending downloads to start"
}

$Searcher2 = $Session.CreateUpdateSearcher()
$Pending = $Searcher2.GetTotalHistoryCount()
Write-Host "Total history: $Pending"