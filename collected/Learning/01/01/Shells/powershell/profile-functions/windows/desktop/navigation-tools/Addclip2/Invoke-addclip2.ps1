$__extractedFunctionName = 'addclip2'
$__extractedCommandName = 'addclip2'
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

function addclip2 {
    Write-Host "[1/8] Setting HKCU clipboard registry..." -ForegroundColor Cyan
    New-Item -Path "HKCU:\Software\Microsoft\Clipboard" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 1 -Type DWord -Force

    Write-Host "[2/8] Setting group policy AllowClipboardHistory..." -ForegroundColor Cyan
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "AllowClipboardHistory" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v AllowClipboardHistory /t REG_DWORD /d 1 /f 2>$null

    Write-Host "[3/8] Enabling cbdhsvc template service (Manual start)..." -ForegroundColor Cyan
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\cbdhsvc" -Name "Start" -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue

    Write-Host "[4/8] Enabling all cbdhsvc per-user instances..." -ForegroundColor Cyan
    Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services" | Where-Object { $_.PSChildName -like "cbdhsvc_*" } | ForEach-Object {
        Set-ItemProperty -Path $_.PSPath -Name "Start" -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "  Set $($_.PSChildName) Start=3" -ForegroundColor Gray
    }

    Write-Host "[5/8] Creating logon scheduled task to auto-enable on every login..." -ForegroundColor Cyan
    $taskName = "EnableClipboardHistory"
    $scriptPath = Join-Path $env:USERPROFILE "EnableClipboardHistory.ps1"
    @'
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 1 -Type DWord -Force
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services" | Where-Object { $_.PSChildName -like "cbdhsvc_*" } | ForEach-Object {
    Set-ItemProperty -Path $_.PSPath -Name "Start" -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue
}
Start-Sleep 5
Get-Service cbdhsvc_* | Where-Object Status -eq Stopped | Start-Service -ErrorAction SilentlyContinue
'@ | Set-Content -Path $scriptPath -Force
    schtasks.exe /Delete /TN $taskName /F 2>$null
    $tr = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    schtasks.exe /Create /TN $taskName /TR $tr /SC ONLOGON /RL HIGHEST /F | Out-Null
    Write-Host "  Task '$taskName' registered (script: $scriptPath)" -ForegroundColor Green

    Write-Host "[6/8] Trying to start cbdhsvc now..." -ForegroundColor Cyan
    Get-Service cbdhsvc_* -ErrorAction SilentlyContinue | ForEach-Object {
        try { Start-Service $_.Name -ErrorAction Stop; Write-Host "  $($_.Name) started!" -ForegroundColor Green }
        catch { Write-Host "  $($_.Name) needs relogon to start (expected)" -ForegroundColor Yellow }
    }

    Write-Host "[7/8] Running gpupdate..." -ForegroundColor Cyan
    gpupdate /force 2>$null | Out-Null

    Write-Host "[8/8] Restarting explorer to pick up changes..." -ForegroundColor Cyan
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep 2
    Start-Process explorer
    Start-Sleep 2

    Write-Host "`nVerification:" -ForegroundColor Cyan
    $regVal = (Get-ItemProperty "HKCU:\Software\Microsoft\Clipboard" -ErrorAction SilentlyContinue).EnableClipboardHistory
    $svcTemplate = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\cbdhsvc" -ErrorAction SilentlyContinue).Start
    $svcStatus = Get-Service cbdhsvc_* -ErrorAction SilentlyContinue | Select-Object -First 1
    $task = Get-ScheduledTask -TaskName "EnableClipboardHistory" -ErrorAction SilentlyContinue
    Write-Host "  Registry EnableClipboardHistory = $regVal (want 1)" -ForegroundColor $(if($regVal -eq 1){'Green'}else{'Red'})
    Write-Host "  cbdhsvc template Start = $svcTemplate (want 3=Manual)" -ForegroundColor $(if($svcTemplate -eq 3){'Green'}else{'Red'})
    Write-Host "  Service status = $($svcStatus.Status) / $($svcStatus.StartType)" -ForegroundColor $(if($svcStatus.Status -eq 'Running'){'Green'}else{'Yellow'})
    Write-Host "  Scheduled task = $($task.State)" -ForegroundColor $(if($task){'Green'}else{'Red'})

    if ($svcStatus.Status -ne 'Running') {
        Write-Host "`n>>> Service needs a RELOGON to fully activate. Sign out and back in. <<<" -ForegroundColor Yellow
    } else {
        Write-Host "`nClipboard history is ACTIVE! Press Win+V to test." -ForegroundColor Green
    }
    Start-Process "ms-settings:clipboard"
}

& $__extractedCommandName @__extractedArgs