$us = New-Object -ComObject Microsoft.Update.Session
$sb = $us.CreateUpdateSearcher()
$sr = $sb.Search("IsInstalled=0")
Write-Host "Pending updates:" $sr.Result.Updates.Count
$sr.Result.Updates | ForEach-Object { Write-Host $_.Title }