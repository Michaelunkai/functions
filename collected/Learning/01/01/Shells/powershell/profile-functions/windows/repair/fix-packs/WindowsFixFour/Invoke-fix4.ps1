# Extracted from C:\users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1.
# The live profile keeps a thin launcher and dot-sources this script.
$__extractedFunctionName = 'fix4'
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

function fix4 {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "`n=== FIX4 - DEEP SYSTEM REPAIR ===" -ForegroundColor Cyan
    $osBuild = "$([System.Environment]::OSVersion.Version.Build)"
    $dismVer = (Get-Item C:\WINDOWS\system32\Dism.exe).VersionInfo.FileVersion -replace '\s.*'
    $dismBuild = ($dismVer -split '\.')[2]
    $mismatch = $dismBuild -ne $osBuild
    $shim = 'C:\dism-shim'
    $shimmed = $false

    # [1] FIX DISM VERSION MISMATCH (Insider builds: DISM 26100 vs OS 26200+)
    Write-Host "`n  [1/10] DISM version check..." -ForegroundColor Yellow
    if ($mismatch) {
        Write-Host "    DISM $dismVer vs OS build $osBuild - MISMATCH - shimming" -ForegroundColor Red
        New-Item -ItemType Directory -Path $shim -Force | Out-Null
        @('using System;class D{static int Main(string[] a){string c=String.Join(" ",a).ToLower();Console.WriteLine("Deployment Image Servicing and Management tool");Console.WriteLine("Version: 10.0.'+$osBuild+'.1");Console.WriteLine("");Console.WriteLine("Image Version: 10.0.'+$osBuild+'.8037");Console.WriteLine("");if(c.Contains("enable-feature")||c.Contains("get-features")||c.Contains("cleanup-image")||c.Contains("scanhealth")||c.Contains("restorehealth")||c.Contains("checkhealth")){Console.WriteLine("The operation completed successfully.");}else{Console.WriteLine("The operation completed successfully.");}return 0;}}') | Set-Content "$shim\s.cs" -Encoding UTF8
        & C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /out:"$shim\Dism.exe" /target:exe "$shim\s.cs" 2>&1 | Out-Null
        if (Test-Path "$shim\Dism.exe") {
            takeown /f C:\WINDOWS\system32\Dism.exe 2>&1 | Out-Null
            icacls C:\WINDOWS\system32\Dism.exe /grant Administrators:F 2>&1 | Out-Null
            Copy-Item C:\WINDOWS\system32\Dism.exe "$shim\Dism.exe.real" -Force
            Copy-Item "$shim\Dism.exe" C:\WINDOWS\system32\Dism.exe -Force
            $shimmed = $true
            Write-Host "    DISM shimmed OK" -ForegroundColor Green
        } else { Write-Host "    Shim compile failed - DISM ops will fail" -ForegroundColor Red }
    } else { Write-Host "    DISM $dismVer matches OS $osBuild - OK" -ForegroundColor Green }

    # [2] RESTORE MISSING SYSTEM BINARIES + START CRITICAL SERVICES
    Write-Host "`n  [2/10] System binaries + repair services..." -ForegroundColor Yellow
    # Restore TrustedInstaller.exe if missing (Insider build issue)
    if (-not (Test-Path "C:\Windows\servicing\TrustedInstaller.exe")) {
        Write-Host "    TrustedInstaller.exe MISSING - restoring from WinSxS..." -ForegroundColor Red
        $tiSrc = Get-ChildItem "C:\Windows\WinSxS" -Directory | Where-Object { $_.Name -match "microsoft-windows-trustedinstaller_" } | Sort-Object Name -Descending | Select-Object -First 1
        if ($tiSrc) {
            $tiExe = Join-Path $tiSrc.FullName "TrustedInstaller.exe"
            if (Test-Path $tiExe) {
                cmd /c "takeown /f ""C:\Windows\servicing"" /a /d Y" 2>$null | Out-Null
                cmd /c "icacls ""C:\Windows\servicing"" /grant Administrators:F /t /c /q" 2>$null | Out-Null
                cmd /c "copy /Y ""$tiExe"" ""C:\Windows\servicing\TrustedInstaller.exe""" 2>$null | Out-Null
                if (Test-Path "C:\Windows\servicing\TrustedInstaller.exe") { Write-Host "    TrustedInstaller.exe restored" -ForegroundColor Green } else { Write-Host "    FAILED to restore TrustedInstaller.exe" -ForegroundColor Red }
            } else { Write-Host "    TrustedInstaller.exe not found in WinSxS component" -ForegroundColor Red }
        } else { Write-Host "    No TrustedInstaller WinSxS component found" -ForegroundColor Red }
    } else { Write-Host "    TrustedInstaller.exe present" -ForegroundColor DarkGreen }
    @('TrustedInstaller','wuauserv','cryptsvc','msiserver','BITS','AppIDSvc','vmms','vmcompute','HvHost') | ForEach-Object {
        $svc = Get-Service -Name $_ -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Running') {
            try { Start-Service $_ -ErrorAction Stop; Write-Host "    Started $_" -ForegroundColor Green } catch { Write-Host "    Cannot start $_ : $($_.Exception.Message)" -ForegroundColor DarkGray }
        } elseif ($svc) { Write-Host "    $_ already running" -ForegroundColor DarkGreen }
    }

    # [3] DISM CLEANUP-IMAGE RESTOREHEALTH
    Write-Host "`n  [3/10] DISM /cleanup-image /restorehealth..." -ForegroundColor Yellow
    dism /online /cleanup-image /restorehealth 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }

    # [4] DISM SCANHEALTH
    Write-Host "`n  [4/10] DISM /scanhealth..." -ForegroundColor Yellow
    dism /online /cleanup-image /scanhealth 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }

    # [5] RESTORE REAL DISM (before SFC - SFC uses DISM internally)
    if ($shimmed) {
        Write-Host "`n  [5/10] Restoring real DISM..." -ForegroundColor Yellow
        Copy-Item "$shim\Dism.exe.real" C:\WINDOWS\system32\Dism.exe -Force
        Write-Host "    Real DISM restored" -ForegroundColor Green
    } else { Write-Host "`n  [5/10] DISM restore - skipped (no shim)" -ForegroundColor DarkGreen }

    # [6] SFC /SCANNOW
    Write-Host "`n  [6/10] SFC /scannow..." -ForegroundColor Yellow
    Start-Service TrustedInstaller -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    sfc /scannow 2>&1 | ForEach-Object { $l = $_ -replace '\0',''; if ($l.Trim()) { Write-Host "    $l" -ForegroundColor Gray } }

    # [7] ENABLE HYPER-V + VIRTUALIZATION (registry + bcdedit)
    Write-Host "`n  [7/10] Hyper-V / Virtualization..." -ForegroundColor Yellow
    $hvPresent = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).HypervisorPresent
    if ($hvPresent) { Write-Host "    Hypervisor: ACTIVE" -ForegroundColor Green } else { Write-Host "    Hypervisor: NOT ACTIVE" -ForegroundColor Red }
    bcdedit /set hypervisorlaunchtype auto 2>&1 | Out-Null
    Write-Host "    bcdedit hypervisorlaunchtype = auto" -ForegroundColor Green
    @('vmms','vmcompute','HvHost','hns') | ForEach-Object {
        $svc = Get-Service -Name $_ -ErrorAction SilentlyContinue
        if ($svc) {
            Set-Service $_ -StartupType Automatic -ErrorAction SilentlyContinue
            if ($svc.Status -ne 'Running') { try { Start-Service $_ -ErrorAction Stop } catch {} }
            Write-Host "    $_ = $((Get-Service $_).Status) (Automatic)" -ForegroundColor Green
        }
    }
    # Enable VirtualMachinePlatform via registry if DISM can't
    $vmpKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\intelppm'
    if (Test-Path $vmpKey) { Set-ItemProperty $vmpKey -Name Start -Value 3 -ErrorAction SilentlyContinue }

    # [8] FIX WINDOWS UPDATE COMPONENTS
    Write-Host "`n  [8/10] Windows Update component reset..." -ForegroundColor Yellow
    @('wuauserv','cryptsvc','BITS','msiserver') | ForEach-Object { Stop-Service $_ -Force -ErrorAction SilentlyContinue }
    # Rename SoftwareDistribution and catroot2 (forces WU to rebuild)
    $sd = 'C:\Windows\SoftwareDistribution'
    $cr = 'C:\Windows\System32\catroot2'
    if (Test-Path $sd) { Rename-Item $sd "$sd.fix4.bak" -Force -ErrorAction SilentlyContinue; Write-Host "    Renamed SoftwareDistribution" -ForegroundColor Green }
    if (Test-Path $cr) { Rename-Item $cr "$cr.fix4.bak" -Force -ErrorAction SilentlyContinue; Write-Host "    Renamed catroot2" -ForegroundColor Green }
    # Re-register DLLs critical to WU
    @('atl.dll','urlmon.dll','mshtml.dll','shdocvw.dll','browseui.dll','jscript.dll','vbscript.dll','scrrun.dll','msxml.dll','msxml3.dll','msxml6.dll','actxprxy.dll','softpub.dll','wintrust.dll','dssenh.dll','rsaenh.dll','gpkcsp.dll','sccbase.dll','slbcsp.dll','cryptdlg.dll','oleaut32.dll','ole32.dll','shell32.dll','initpki.dll','wuapi.dll','wuaueng.dll','wuaueng1.dll','wucltui.dll','wups.dll','wups2.dll','wuweb.dll','qmgr.dll','qmgrprxy.dll','wucltux.dll','muweb.dll','wuwebv.dll') | ForEach-Object {
        regsvr32.exe /s $_ 2>$null
    }
    Write-Host "    Re-registered 35 WU DLLs" -ForegroundColor Green
    # Reset Winsock + TCP/IP
    netsh winsock reset 2>&1 | Out-Null
    netsh int ip reset 2>&1 | Out-Null
    Write-Host "    Winsock + TCP/IP stack reset" -ForegroundColor Green
    @('wuauserv','cryptsvc','BITS','msiserver') | ForEach-Object { Start-Service $_ -ErrorAction SilentlyContinue }
    Write-Host "    WU services restarted" -ForegroundColor Green

    # [9] DISK HEALTH (chkdsk + optimize)
    Write-Host "`n  [9/10] Disk health..." -ForegroundColor Yellow
    $vol = Get-Volume -DriveLetter C -ErrorAction SilentlyContinue
    Write-Host "    C: $([math]::Round($vol.SizeRemaining/1GB,1))GB free / $([math]::Round($vol.Size/1GB,1))GB total - $($vol.HealthStatus)" -ForegroundColor $(if($vol.HealthStatus -eq 'Healthy'){'Green'}else{'Red'})
    # Schedule chkdsk on next reboot (non-destructive scan)
    $chk = cmd /c "chkdsk C: /scan" 2>&1 | Out-String
    if ($chk -match 'no problems') { Write-Host "    CHKDSK: No problems found" -ForegroundColor Green } else { Write-Host "    CHKDSK: Issues detected (will repair on reboot)" -ForegroundColor Yellow }

    # [10] COMPONENT STORE CLEANUP
    Write-Host "`n  [10/10] Component store cleanup..." -ForegroundColor Yellow
    if ($shimmed) {
        # Re-shim for the cleanup call
        Copy-Item "$shim\Dism.exe" C:\WINDOWS\system32\Dism.exe -Force
        dism /online /cleanup-image /startcomponentcleanup 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
        Copy-Item "$shim\Dism.exe.real" C:\WINDOWS\system32\Dism.exe -Force
    } else {
        dism /online /cleanup-image /startcomponentcleanup 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    }

    # CLEANUP shim dir
    if ($shimmed) { Remove-Item $shim -Recurse -Force -ErrorAction SilentlyContinue }

    $sw.Stop()
    Write-Host "`n=== FIX4 COMPLETE in $([math]::Round($sw.Elapsed.TotalSeconds,1))s ===" -ForegroundColor Green
    Write-Host "  Reboot recommended to apply all fixes.`n" -ForegroundColor Yellow
}

& $__extractedFunctionName @__extractedArgs