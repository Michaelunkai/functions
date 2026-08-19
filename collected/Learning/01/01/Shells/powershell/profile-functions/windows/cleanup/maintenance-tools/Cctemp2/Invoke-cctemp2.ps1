$__extractedFunctionName = 'cctemp2'
$__extractedCommandName = 'cctemp2'
$__extractedScriptPath = $PSCommandPath
$__extractedArgs = @($args)
if ($__extractedArgs -contains '-SelfTest') {
    [pscustomobject]@{
        Function = $__extractedFunctionName
        Command = $__extractedCommandName
        Script = $__extractedScriptPath
        Exists = [bool](Test-Path -LiteralPath $__extractedScriptPath)
        Mode = 'SelfTest'
    } | ConvertTo-Json -Compress
    return
}

function cctemp2 {
    $before = (Get-PSDrive C).Free
    Write-Host "`nSTEP 2: High-value directory cleanup..." -ForegroundColor Green
    $dirs = @(
        "C:\Windows\System32\winevt\Logs",
        "C:\Windows\Prefetch",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer",
        "$env:LOCALAPPDATA\Microsoft\Windows\WebCache",
        "C:\Windows\WinSxS\Temp",
        "$env:LOCALAPPDATA\Temp",
        "$env:WINDIR\Temp",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
        "$env:LOCALAPPDATA\CrashDumps",
        "$env:WINDIR\Minidump",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
    )
    $i = 0
    foreach ($dir in $dirs) {
        $i++
        Write-Progress -Activity "Cleaning directories" -Status "$dir ($i of $($dirs.Count))" -PercentComplete (($i / $dirs.Count) * 100)
        if (Test-Path $dir) {
            Remove-Item "$dir\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Progress -Activity "Cleaning directories" -Completed
    Write-Host "`nSTEP 3: Windows Update cleanup..." -ForegroundColor Green
    Write-Host "Stopping update services..." -ForegroundColor Yellow
    Stop-Service UsoSvc, cryptsvc, bits, msiserver, dosvc, wuauserv -Force -ErrorAction SilentlyContinue
    Write-Progress -Activity "Windows Update cleanup" -Status "Deleting old folders" -PercentComplete 30
    if (Test-Path "C:\Windows\SoftwareDistribution.old") { Remove-Item "C:\Windows\SoftwareDistribution.old" -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path "C:\Windows\System32\catroot2.old") { Remove-Item "C:\Windows\System32\catroot2.old" -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path "C:\Windows\SoftwareDistribution") { Remove-Item "C:\Windows\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path "C:\Windows\System32\catroot2") { Remove-Item "C:\Windows\System32\catroot2\*" -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Progress -Activity "Windows Update cleanup" -Status "Restarting services" -PercentComplete 70
    Start-Service UsoSvc, cryptsvc, bits, msiserver, dosvc, wuauserv -ErrorAction SilentlyContinue
    Write-Progress -Activity "Windows Update cleanup" -Completed
    Write-Host "`nSTEP 4: System optimization..." -ForegroundColor Green
    Write-Progress -Activity "Component Store Cleanup" -Status "Running DISM" -PercentComplete 10
    Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase | Out-Null
    Write-Progress -Activity "System File Check" -Status "Running SFC" -PercentComplete 40
    sfc /scannow | Out-Null
    Write-Progress -Activity "Disk Optimization" -Status "Optimizing storage" -PercentComplete 70
    if ((Get-PhysicalDisk | Where-Object MediaType -eq 'SSD')) {
        Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue
    } else {
        Start-Process -FilePath "defrag.exe" -ArgumentList "C: /O /H" -Wait
    }
    Write-Host "`nSTEP 5: Event log cleanup..." -ForegroundColor Green
    $logs = @(wevtutil el)
    $j = 0
    foreach ($log in $logs) {
        $j++
        Write-Progress -Activity "Clearing logs" -Status "$log ($j of $($logs.Count))" -PercentComplete (($j / $logs.Count) * 100)
        try { wevtutil cl "$log" } catch {}
    }
    Write-Progress -Activity "Clearing logs" -Completed
    Write-Host "`nSTEP 6: DNS & Store cache cleanup..." -ForegroundColor Green
    ipconfig /flushdns | Out-Null
    wsreset.exe -i
    $after = (Get-PSDrive C).Free
    Write-Host ("`nFreed: " + [math]::Round(($after - $before) / 1MB, 2) + " MB") -ForegroundColor Green
}

& $__extractedCommandName @__extractedArgs
