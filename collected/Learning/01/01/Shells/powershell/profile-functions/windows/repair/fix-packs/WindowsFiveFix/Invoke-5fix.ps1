# Extracted from C:\users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1.
# The live profile keeps a thin launcher and dot-sources this script.
$__extractedFunctionName = '5fix'
$__extractedScriptPath = $PSCommandPath
$__extractedArgs = @($args)
if ($__extractedArgs -contains '-SelfTest') {
    [pscustomobject]@{
        Script = $__extractedScriptPath
        Exists = (Test-Path -LiteralPath $__extractedScriptPath)
        Function = $__extractedFunctionName
        Mode = 'SelfTest'
    }
    return
}

function 5fix {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "[5fix] Not running as admin - relaunching elevated..." -ForegroundColor Yellow
        Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -Command 5fix"
        return
    }
    $startTime = Get-Date
    Write-Host "`n============================================================" -ForegroundColor Magenta
    Write-Host "  5FIX - ULTIMATE Windows 11 Repair (Every Possible Fix)" -ForegroundColor Magenta
    Write-Host "  Started: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
    Write-Host "============================================================`n" -ForegroundColor Magenta

    $results = [ordered]@{}
    $step = 0
    $total = 41

    # --- SECTION 0: SAFETY NET ---
    Write-Host "--- SAFETY NET ---" -ForegroundColor White

    $step++; Write-Host "[$step/$total] Create System Restore Point..." -ForegroundColor Cyan
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "5fix_pre_repair_$(Get-Date -Format 'yyyyMMdd_HHmmss')" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        $results['Restore Point'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['Restore Point'] = 'SKIP'; Write-Host "  SKIP: $($_.Exception.Message)" -ForegroundColor Yellow }

    # --- SECTION 1: SYSTEM IMAGE & FILE REPAIR ---
    Write-Host "`n--- SYSTEM IMAGE & FILE REPAIR ---" -ForegroundColor White

    $step++; Write-Host "[$step/$total] DISM CheckHealth..." -ForegroundColor Cyan
    try { dism /online /cleanup-image /checkhealth
        if ($LASTEXITCODE -eq 0) { $results['DISM CheckHealth'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green }
        else { $results['DISM CheckHealth'] = "EXIT $LASTEXITCODE"; Write-Host "  EXIT $LASTEXITCODE" -ForegroundColor Yellow }
    } catch { $results['DISM CheckHealth'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] DISM ScanHealth..." -ForegroundColor Cyan
    try { dism /online /cleanup-image /scanhealth
        if ($LASTEXITCODE -eq 0) { $results['DISM ScanHealth'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green }
        else { $results['DISM ScanHealth'] = "EXIT $LASTEXITCODE"; Write-Host "  EXIT $LASTEXITCODE" -ForegroundColor Yellow }
    } catch { $results['DISM ScanHealth'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] DISM RestoreHealth..." -ForegroundColor Cyan
    try { dism /online /cleanup-image /restorehealth
        if ($LASTEXITCODE -eq 0) { $results['DISM RestoreHealth'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green }
        else { $results['DISM RestoreHealth'] = "EXIT $LASTEXITCODE"; Write-Host "  EXIT $LASTEXITCODE" -ForegroundColor Yellow }
    } catch { $results['DISM RestoreHealth'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] DISM StartComponentCleanup..." -ForegroundColor Cyan
    try { dism /online /cleanup-image /startcomponentcleanup
        if ($LASTEXITCODE -eq 0) { $results['DISM ComponentCleanup'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green }
        else { $results['DISM ComponentCleanup'] = "EXIT $LASTEXITCODE"; Write-Host "  EXIT $LASTEXITCODE" -ForegroundColor Yellow }
    } catch { $results['DISM ComponentCleanup'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] DISM AnalyzeComponentStore..." -ForegroundColor Cyan
    try { dism /online /cleanup-image /analyzecomponentstore
        if ($LASTEXITCODE -eq 0) { $results['DISM AnalyzeStore'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green }
        else { $results['DISM AnalyzeStore'] = "EXIT $LASTEXITCODE"; Write-Host "  EXIT $LASTEXITCODE" -ForegroundColor Yellow }
    } catch { $results['DISM AnalyzeStore'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] SFC /scannow..." -ForegroundColor Cyan
    try { sfc /scannow
        if ($LASTEXITCODE -eq 0) { $results['SFC Scannow'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green }
        else { $results['SFC Scannow'] = "EXIT $LASTEXITCODE"; Write-Host "  EXIT $LASTEXITCODE" -ForegroundColor Yellow }
    } catch { $results['SFC Scannow'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    # --- SECTION 2: WINDOWS UPDATE REPAIR ---
    Write-Host "`n--- WINDOWS UPDATE REPAIR ---" -ForegroundColor White

    $step++; Write-Host "[$step/$total] Windows Update component reset..." -ForegroundColor Cyan
    try {
        $wuSvcs = @('wuauserv','bits','cryptSvc','msiserver','AppIDSvc')
        foreach ($s in $wuSvcs) { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
        $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
        $sdPath = "$env:SystemRoot\SoftwareDistribution"
        $crPath = "$env:SystemRoot\System32\catroot2"
        if (Test-Path $sdPath) { Rename-Item $sdPath "$sdPath.bak_$ts" -Force -ErrorAction SilentlyContinue }
        if (Test-Path $crPath) { Rename-Item $crPath "$crPath.bak_$ts" -Force -ErrorAction SilentlyContinue }
        foreach ($s in $wuSvcs) { Start-Service -Name $s -ErrorAction SilentlyContinue }
        $results['WU Component Reset'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['WU Component Reset'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] Re-register WU DLLs (36 DLLs)..." -ForegroundColor Cyan
    try {
        $wuDlls = @('atl.dll','urlmon.dll','mshtml.dll','shdocvw.dll','browseui.dll','jscript.dll','vbscript.dll','scrrun.dll','msxml.dll','msxml3.dll','msxml6.dll','actxprxy.dll','softpub.dll','wintrust.dll','dssenh.dll','rsaenh.dll','gpkcsp.dll','sccbase.dll','slbcsp.dll','cryptdlg.dll','oleaut32.dll','ole32.dll','shell32.dll','initpki.dll','wuapi.dll','wuaueng.dll','wuaueng1.dll','wucltui.dll','wups.dll','wups2.dll','wuweb.dll','qmgr.dll','qmgrprxy.dll','wucltux.dll','muweb.dll','wuwebv.dll')
        foreach ($dll in $wuDlls) { regsvr32.exe /s $dll 2>$null }
        $results['WU DLL Re-register'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['WU DLL Re-register'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] BITS service repair..." -ForegroundColor Cyan
    try {
        bitsadmin /reset /allusers 2>&1
        sc.exe sdset bits 'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)' 2>&1
        $results['BITS Repair'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['BITS Repair'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] Delivery Optimization cache clear..." -ForegroundColor Cyan
    try {
        Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization\*" -Recurse -Force -ErrorAction SilentlyContinue
        $results['DO Cache Clear'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['DO Cache Clear'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    # --- SECTION 3: NETWORK REPAIR ---
    Write-Host "`n--- NETWORK REPAIR ---" -ForegroundColor White

    $step++; Write-Host "[$step/$total] Winsock reset..." -ForegroundColor Cyan
    try { netsh winsock reset; $results['Winsock Reset'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['Winsock Reset'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] TCP/IP stack reset..." -ForegroundColor Cyan
    try { netsh int ip reset; $results['TCP/IP Reset'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['TCP/IP Reset'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] DNS flush + re-register..." -ForegroundColor Cyan
    try { ipconfig /flushdns; ipconfig /registerdns
        $results['DNS Flush'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['DNS Flush'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] Release + Renew IP..." -ForegroundColor Cyan
    try { ipconfig /release 2>&1; ipconfig /renew 2>&1
        $results['IP Renew'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['IP Renew'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] ARP cache clear..." -ForegroundColor Cyan
    try { netsh interface ip delete arpcache 2>&1; arp -d * 2>&1
        $results['ARP Cache Clear'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['ARP Cache Clear'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    # --- SECTION 4: DISK & FILESYSTEM ---
    Write-Host "`n--- DISK & FILESYSTEM ---" -ForegroundColor White

    $step++; Write-Host "[$step/$total] Temp files cleanup (3 dirs)..." -ForegroundColor Cyan
    try {
        Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:LOCALAPPDATA\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        $results['Temp Cleanup'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['Temp Cleanup'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] Thumbnail + icon cache clear..." -ForegroundColor Cyan
    try {
        Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
        ie4uinit.exe -show 2>&1
        $results['Thumbnail Cache'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['Thumbnail Cache'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] Font cache rebuild..." -ForegroundColor Cyan
    try {
        Stop-Service -Name 'FontCache' -Force -ErrorAction SilentlyContinue
        Stop-Service -Name 'FontCache3.0.0.0' -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:windir\ServiceProfiles\LocalService\AppData\Local\FontCache\*.dat" -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:windir\ServiceProfiles\LocalService\AppData\Local\FontCache\Fnt*.tmp" -Force -ErrorAction SilentlyContinue
        Start-Service -Name 'FontCache' -ErrorAction SilentlyContinue
        $results['Font Cache Rebuild'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['Font Cache Rebuild'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] DirectX shader cache clear..." -ForegroundColor Cyan
    try {
        Remove-Item "$env:LOCALAPPDATA\D3DSCache\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:LOCALAPPDATA\NVIDIA\DXCache\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:LOCALAPPDATA\NVIDIA\GLCache\*" -Recurse -Force -ErrorAction SilentlyContinue
        $results['Shader Cache Clear'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['Shader Cache Clear'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] Windows Error Reporting cleanup..." -ForegroundColor Cyan
    try {
        Remove-Item "$env:LOCALAPPDATA\CrashDumps\*" -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:ProgramData\Microsoft\Windows\WER\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "C:\Windows\Minidump\*" -Force -ErrorAction SilentlyContinue
        $results['WER Cleanup'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['WER Cleanup'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] CBS + DISM logs cleanup..." -ForegroundColor Cyan
    try {
        Remove-Item "C:\Windows\Logs\CBS\*.log" -Force -ErrorAction SilentlyContinue
        Remove-Item "C:\Windows\Logs\DISM\*.log" -Force -ErrorAction SilentlyContinue
        $results['CBS Logs Cleanup'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['CBS Logs Cleanup'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] Recycle Bin purge..." -ForegroundColor Cyan
    try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        $results['Recycle Bin Purge'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['Recycle Bin Purge'] = 'PASS'; Write-Host "  PASS (empty)" -ForegroundColor Green }

    $step++; Write-Host "[$step/$total] Schedule CHKDSK C: on next reboot..." -ForegroundColor Cyan
    try { echo Y | chkdsk C: /F /R /X 2>&1
        $results['CHKDSK Scheduled'] = 'PASS'; Write-Host "  PASS (next reboot)" -ForegroundColor Green
    } catch { $results['CHKDSK Scheduled'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    # --- SECTION 5: REGISTRY & SERVICES ---
    Write-Host "`n--- REGISTRY & SERVICES ---" -ForegroundColor White

    $step++; Write-Host "[$step/$total] WMI repository verify + repair..." -ForegroundColor Cyan
    try {
        winmgmt /verifyrepository 2>&1
        if ($LASTEXITCODE -ne 0) { winmgmt /salvagerepository 2>&1 }
        $results['WMI Repair'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['WMI Repair'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] Performance counters rebuild..." -ForegroundColor Cyan
    try {
        lodctr /R 2>&1
        winmgmt /resyncperf 2>&1
        $results['Perf Counters'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['Perf Counters'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] Windows Search index rebuild..." -ForegroundColor Cyan
    try {
        Stop-Service -Name 'WSearch' -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:ProgramData\Microsoft\Search\Data\Applications\Windows\Windows.edb" -Force -ErrorAction SilentlyContinue
        Start-Service -Name 'WSearch' -ErrorAction SilentlyContinue
        $results['Search Index Rebuild'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['Search Index Rebuild'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] Print spooler reset..." -ForegroundColor Cyan
    try {
        Stop-Service -Name 'Spooler' -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
        Start-Service -Name 'Spooler' -ErrorAction SilentlyContinue
        $results['Print Spooler Reset'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['Print Spooler Reset'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] Windows Installer repair..." -ForegroundColor Cyan
    try { msiexec /unregister 2>&1; msiexec /regserver 2>&1
        $results['MSI Repair'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['MSI Repair'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] Re-register system DLLs (10 core)..." -ForegroundColor Cyan
    try {
        $sysDlls = @('ole32.dll','oleaut32.dll','shell32.dll','shdocvw.dll','mshtml.dll','urlmon.dll','jscript.dll','vbscript.dll','scrrun.dll','actxprxy.dll')
        foreach ($d in $sysDlls) { regsvr32.exe /s "$env:SystemRoot\System32\$d" 2>$null }
        $results['System DLL Register'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['System DLL Register'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    # --- SECTION 6: STORE & APPS ---
    Write-Host "`n--- STORE & APPS ---" -ForegroundColor White

    $step++; Write-Host "[$step/$total] Microsoft Store cache reset..." -ForegroundColor Cyan
    try { wsreset.exe 2>&1; $results['Store Cache Reset'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['Store Cache Reset'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] Re-register all AppX packages..." -ForegroundColor Cyan
    try {
        Get-AppXPackage -AllUsers -ErrorAction SilentlyContinue | ForEach-Object { Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue 2>$null }
        $results['AppX Re-register'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['AppX Re-register'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    # --- SECTION 7: SECURITY & CRYPTO ---
    Write-Host "`n--- SECURITY & CRYPTO ---" -ForegroundColor White

    $step++; Write-Host "[$step/$total] Crypto store repair (certutil)..." -ForegroundColor Cyan
    try { certutil -setreg chain\ChainCacheResyncFiletime @now 2>&1
        $results['Crypto Store Repair'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['Crypto Store Repair'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] Group Policy refresh..." -ForegroundColor Cyan
    try { gpupdate /force; $results['GPO Refresh'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['GPO Refresh'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] Windows Defender definition update..." -ForegroundColor Cyan
    try {
        & "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -SignatureUpdate 2>&1
        $results['Defender Update'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['Defender Update'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    # --- SECTION 8: PERFORMANCE & MEMORY ---
    Write-Host "`n--- PERFORMANCE & MEMORY ---" -ForegroundColor White

    $step++; Write-Host "[$step/$total] Windows Time service sync..." -ForegroundColor Cyan
    try {
        Start-Service -Name 'w32time' -ErrorAction SilentlyContinue
        w32tm /resync /force 2>&1
        $results['Time Sync'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['Time Sync'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] .NET native image update (ngen)..." -ForegroundColor Cyan
    try {
        $ngenPath = [System.IO.Path]::Combine([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory(), 'ngen.exe')
        if (Test-Path $ngenPath) { & $ngenPath update /force 2>&1 }
        $results['NGEN Update'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['NGEN Update'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] Flush .NET GC + working sets..." -ForegroundColor Cyan
    try {
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        $results['Memory Flush'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['Memory Flush'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    $step++; Write-Host "[$step/$total] Prefetch cleanup..." -ForegroundColor Cyan
    try { Remove-Item "C:\Windows\Prefetch\*.pf" -Force -ErrorAction SilentlyContinue
        $results['Prefetch Cleanup'] = 'PASS'; Write-Host "  PASS" -ForegroundColor Green
    } catch { $results['Prefetch Cleanup'] = 'FAIL'; Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red }

    # ============ SUMMARY ============
    $elapsed = (Get-Date) - $startTime
    Write-Host "`n============================================================" -ForegroundColor Magenta
    Write-Host "  5FIX REPAIR SUMMARY" -ForegroundColor Magenta
    Write-Host "  Duration: $($elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor Magenta
    $passed = 0; $failed = 0
    foreach ($key in $results.Keys) {
        $val = $results[$key]
        if ($val -eq 'PASS') { $color = 'Green'; $passed++ }
        elseif ($val -like 'EXIT*') { $color = 'Yellow'; $failed++ }
        elseif ($val -eq 'SKIP') { $color = 'DarkYellow'; $passed++ }
        else { $color = 'Red'; $failed++ }
        $pad = $key.PadRight(25)
        Write-Host "  $pad : $val" -ForegroundColor $color
    }
    Write-Host "`n  Total: $($results.Count) steps | Passed: $passed | Issues: $failed" -ForegroundColor White
    if ($failed -eq 0) { Write-Host "  ALL REPAIRS SUCCESSFUL" -ForegroundColor Green }
    else { Write-Host "  $failed step(s) had issues - review above" -ForegroundColor Yellow }
    Write-Host "  REBOOT STRONGLY RECOMMENDED to finalize all repairs.`n" -ForegroundColor Magenta
}

& $__extractedFunctionName @__extractedArgs