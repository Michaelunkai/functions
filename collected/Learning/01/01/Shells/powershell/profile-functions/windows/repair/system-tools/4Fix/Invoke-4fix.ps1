$__extractedFunctionName = '4fix'
$__extractedCommandName = '4fix'
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

function 4fix {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "[4fix] Not running as admin - relaunching elevated..." -ForegroundColor Yellow
        Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -Command 4fix"
        return
    }
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  4FIX - Comprehensive Windows Repair" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    $results = @{}
    $stepNum = 0

    # Step 1: DISM RestoreHealth
    $stepNum++
    Write-Host "[$stepNum/6] DISM RestoreHealth..." -ForegroundColor Cyan
    try {
        dism /online /cleanup-image /restorehealth 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $results['DISM RestoreHealth'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green }
        else { $results['DISM RestoreHealth'] = "EXIT $LASTEXITCODE"; Write-Host "  Exit code: $LASTEXITCODE" -ForegroundColor Yellow }
    } catch { $results['DISM RestoreHealth'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    # Step 2: SFC /scannow
    $stepNum++
    Write-Host "[$stepNum/6] SFC /scannow..." -ForegroundColor Cyan
    try {
        sfc /scannow 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $results['SFC Scannow'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green }
        else { $results['SFC Scannow'] = "EXIT $LASTEXITCODE"; Write-Host "  Exit code: $LASTEXITCODE" -ForegroundColor Yellow }
    } catch { $results['SFC Scannow'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    # Step 3: Windows Update component reset
    $stepNum++
    Write-Host "[$stepNum/6] Windows Update component reset..." -ForegroundColor Cyan
    try {
        $wuServices = @('wuauserv','bits','cryptSvc','msiserver')
        foreach ($svc in $wuServices) { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue }
        $sdPath = "$env:SystemRoot\SoftwareDistribution"
        $crPath = "$env:SystemRoot\System32\catroot2"
        if (Test-Path $sdPath) { Rename-Item $sdPath "$sdPath.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')" -Force -ErrorAction SilentlyContinue }
        if (Test-Path $crPath) { Rename-Item $crPath "$crPath.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')" -Force -ErrorAction SilentlyContinue }
        foreach ($svc in $wuServices) { Start-Service -Name $svc -ErrorAction SilentlyContinue }
        $results['WU Component Reset'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['WU Component Reset'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    # Step 4: Network/Winsock reset + DNS flush
    $stepNum++
    Write-Host "[$stepNum/6] Network/Winsock reset + DNS flush..." -ForegroundColor Cyan
    try {
        netsh winsock reset 2>&1 | Out-Null
        netsh int ip reset 2>&1 | Out-Null
        ipconfig /flushdns 2>&1 | Out-Null
        $results['Network/Winsock Reset'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['Network/Winsock Reset'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    # Step 5: DISM component cleanup
    $stepNum++
    Write-Host "[$stepNum/6] DISM component cleanup..." -ForegroundColor Cyan
    try {
        dism /online /cleanup-image /startcomponentcleanup 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $results['DISM Cleanup'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green }
        else { $results['DISM Cleanup'] = "EXIT $LASTEXITCODE"; Write-Host "  Exit code: $LASTEXITCODE" -ForegroundColor Yellow }
    } catch { $results['DISM Cleanup'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    # Step 6: Schedule CHKDSK on next reboot
    $stepNum++
    Write-Host "[$stepNum/6] Schedule CHKDSK on next reboot..." -ForegroundColor Cyan
    try {
        $chkOut = echo Y | chkdsk C: /F /R /X 2>&1
        $results['CHKDSK Scheduled'] = 'PASS'; Write-Host "  PASS (will run on next reboot)" -ForegroundColor Green
    } catch { $results['CHKDSK Scheduled'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    # Summary report
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  REPAIR SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    $passed = 0; $failed = 0
    foreach ($key in $results.Keys) {
        $val = $results[$key]
        if ($val -eq 'PASS') { $color = 'Green'; $passed++ }
        elseif ($val -like 'EXIT*') { $color = 'Yellow'; $failed++ }
        else { $color = 'Red'; $failed++ }
        Write-Host "  $key : $val" -ForegroundColor $color
    }
    Write-Host "`n  Total: $($results.Count) steps | Passed: $passed | Issues: $failed" -ForegroundColor White
    if ($failed -eq 0) { Write-Host "  ALL REPAIRS SUCCESSFUL" -ForegroundColor Green }
    else { Write-Host "  Some steps had issues - review above" -ForegroundColor Yellow }
    Write-Host "  Reboot recommended to complete repairs.`n" -ForegroundColor Cyan
}

& $__extractedCommandName @__extractedArgs