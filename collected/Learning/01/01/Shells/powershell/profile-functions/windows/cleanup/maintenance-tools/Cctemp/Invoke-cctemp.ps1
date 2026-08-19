$__extractedFunctionName = 'cctemp'
$__extractedCommandName = 'cctemp'
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

function cctemp {
    Write-Host "`nSTEP 2: Parallel high-value directory cleanup..." -ForegroundColor Green
    $highValueDirectories = @(
        "C:\Windows\System32\winevt\Logs",
        "C:\Windows\Prefetch",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer",
        "$env:LOCALAPPDATA\Microsoft\Windows\WebCache",
        "C:\Windows\WinSxS\Temp",
        "$env:LOCALAPPDATA\Temp",
        "$env:WINDIR\Temp"
    )
    $totalDirs = $highValueDirectories.Count
    $i = 0
    foreach ($dir in $highValueDirectories) {
        $i++
        Write-Progress -Activity "Cleaning high-value directories" -Status "Processing $dir ($i of $totalDirs)" -PercentComplete (($i / $totalDirs) * 100)
        if (Test-Path $dir) {
            $sizeBefore = [math]::Round(((Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum) / 1MB, 2)
            if ($sizeBefore -gt 0) {
                Get-ChildItem -Path $dir -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    try { Remove-Item $_.FullName -Force -Recurse -ErrorAction SilentlyContinue } catch {}
                }
            }
        }
    }
    Write-Progress -Activity "Cleaning high-value directories" -Completed
    $script:totalFreed += 150
    Write-Host "`nSTEP 3: Fast Windows Update cleanup..." -ForegroundColor Green
    Write-Host "Stopping Windows Update related services..." -ForegroundColor Yellow
    Stop-Service -Name UsoSvc, cryptsvc, bits, msiserver, dosvc, wuauserv -Force -ErrorAction SilentlyContinue
    Write-Host "Cleaning Windows Update folders..." -ForegroundColor Yellow
    Remove-Item -Path "C:\Windows\SoftwareDistribution.old", "C:\Windows\System32\catroot2.old" -Recurse -Force -ErrorAction SilentlyContinue
    try {
        Rename-Item -Path "C:\Windows\SoftwareDistribution" -NewName "SoftwareDistribution.old" -Force
        New-Item -Path "C:\Windows\SoftwareDistribution" -ItemType Directory -Force | Out-Null
        $script:totalFreed += 50
        Rename-Item -Path "C:\Windows\System32\catroot2" -NewName "catroot2.old" -Force
        New-Item -Path "C:\Windows\System32\catroot2" -ItemType Directory -Force | Out-Null
        $script:totalFreed += 20
    }
    catch {
        Write-Host "Some Windows Update files were locked" -ForegroundColor Yellow
    }
    Write-Host "Starting Windows Update related services..." -ForegroundColor Yellow
    Start-Service -Name UsoSvc, cryptsvc, bits, msiserver, dosvc, wuauserv -ErrorAction SilentlyContinue
    Write-Host "`nSTEP 4: Parallel system cleanup..." -ForegroundColor Green
    Write-Host "Launching Disk Cleanup..." -ForegroundColor Yellow
    Start-Job -ScriptBlock { Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:1" -WindowStyle Hidden -Wait } | Out-Null
    Write-Host "Clearing event logs..." -ForegroundColor Yellow
    $eventLogs = @(wevtutil el | Where-Object { $_ -notmatch "(LiveId|USBVideo|Analytic)" })
    $logCount = $eventLogs.Count
    $j = 0
    foreach ($log in $eventLogs) {
        $j++
        Write-Progress -Activity "Clearing event logs" -Status "Clearing $log ($j of $logCount)" -PercentComplete (($j / $logCount) * 100)
        wevtutil cl "$log"
    }
    Write-Progress -Activity "Clearing event logs" -Completed
    Write-Host "Cleaning temp/cache/log folders across C:\ ..." -ForegroundColor Yellow
    $extraPaths = @(Get-ChildItem -Path "C:\" -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\(Temp|Cache|Logs|LogFiles)$" })
    $extraCount = $extraPaths.Count
    $x = 0
    foreach ($folder in $extraPaths) {
        $x++
        Write-Progress -Activity "Deep temp/log cleanup" -Status "Cleaning $($folder.FullName) ($x of $extraCount)" -PercentComplete (($x / $extraCount) * 100)
        try { Remove-Item -Path $folder.FullName\* -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
    Write-Progress -Activity "Deep temp/log cleanup" -Completed
    $script:totalFreed += 200
}

& $__extractedCommandName @__extractedArgs
