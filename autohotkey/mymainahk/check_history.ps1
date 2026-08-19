$UpdateSession = New-Object -ComObject Microsoft.Update.Session
$UpdateServiceManager = New-Object -ComObject Microsoft.Update.ServiceManager
$UpdateService = $UpdateSession.CreateUpdateSearcher()
$TotalHistoryCount = $UpdateService.GetTotalHistoryCount()
$History = $UpdateService.QueryHistory(0, $TotalHistoryCount)
Write-Host "Total update history: $TotalHistoryCount"
Write-Host "Last 10 updates:"
$History | Select-Object -First 10 | ForEach-Object { Write-Host $_.Title "-" $_.ResultCode "-" $_.Date }