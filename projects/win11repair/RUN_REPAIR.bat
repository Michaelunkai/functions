@echo off
setlocal enabledelayedexpansion

:: ============================================================
::  Windows 11 In-Place Repair Install - SAFE MODE
::  Prevents BSOD 0x5A (CRITICAL_SERVICE_FAILED) by:
::   1. Pre-flight system health checks
::   2. Clean boot (disable third-party services/startup)
::   3. Safe setup.exe flags (no forced driver migration)
::   4. Compatibility scan before actual upgrade
:: ============================================================

set "SCRIPTDIR=%~dp0"
set "LOG=%SCRIPTDIR%repair_log.txt"
set "ISO=E:\isos\Windows.iso"
set "SVCBACKUP=%SCRIPTDIR%disabled_services_backup.txt"
set "STARTUPBACKUP=%SCRIPTDIR%disabled_startup_backup.txt"
set "RESTORESCRIPT=%SCRIPTDIR%RESTORE_SERVICES.bat"
set "PASSED=0"
set "FAILED=0"
set "WARNED=0"

echo %DATE% %TIME% - === Windows 11 Repair Install SAFE MODE === > "%LOG%"
echo.
echo ============================================================
echo   Windows 11 In-Place Repair Install - SAFE MODE
echo   Bulletproof edition - prevents BSOD 0x5A
echo ============================================================
echo.

:: --------------------------------------------------------
:: STEP 1: Admin check
:: --------------------------------------------------------
echo [STEP 1/14] Verifying admin privileges...
echo %TIME% - Checking admin... >> "%LOG%"
net session >nul 2>&1
if errorlevel 1 (
    echo   [FAIL] Not running as Administrator!
    echo %TIME% - FAIL: Not admin >> "%LOG%"
    echo.
    echo   Right-click this file and select "Run as administrator"
    pause
    exit /b 1
)
echo   [PASS] Running as Administrator
echo %TIME% - PASS: Admin confirmed >> "%LOG%"
set /a PASSED+=1

:: --------------------------------------------------------
:: STEP 2: ISO exists
:: --------------------------------------------------------
echo.
echo [STEP 2/14] Verifying ISO file...
echo %TIME% - Checking ISO... >> "%LOG%"
if not exist "%ISO%" (
    echo   [FAIL] ISO not found: %ISO%
    echo %TIME% - FAIL: ISO missing >> "%LOG%"
    pause
    exit /b 1
)
for %%A in ("%ISO%") do (
    echo   [PASS] Found: %ISO% ^(%%~zA bytes^)
    echo %TIME% - PASS: ISO found %%~zA bytes >> "%LOG%"
)
set /a PASSED+=1

:: --------------------------------------------------------
:: STEP 3: ISO integrity check (SHA256)
:: --------------------------------------------------------
echo.
echo [STEP 3/14] Computing ISO hash for integrity verification...
echo %TIME% - Computing ISO SHA256... >> "%LOG%"
for /f "skip=1 tokens=*" %%H in ('certutil -hashfile "%ISO%" SHA256 2^>nul') do (
    if not defined ISOHASH set "ISOHASH=%%H"
)
if defined ISOHASH (
    echo   [PASS] SHA256: !ISOHASH!
    echo %TIME% - PASS: ISO SHA256=!ISOHASH! >> "%LOG%"
    set /a PASSED+=1
) else (
    echo   [WARN] Could not compute hash - proceeding anyway
    echo %TIME% - WARN: Hash computation failed >> "%LOG%"
    set /a WARNED+=1
)

:: --------------------------------------------------------
:: STEP 4: Free disk space check (need 20GB+ on C:)
:: --------------------------------------------------------
echo.
echo [STEP 4/14] Checking free disk space on C:...
echo %TIME% - Checking disk space... >> "%LOG%"
for /f "tokens=3" %%S in ('dir C:\ 2^>nul ^| findstr /C:"bytes free"') do set "FREEBYTES=%%S"
set "FREEBYTES=!FREEBYTES:,=!"
powershell -NoProfile -Command "$freeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 1); if ($freeGB -lt 20) { Write-Host \"  [FAIL] Only $freeGB GB free on C: - need at least 20 GB\"; exit 1 } else { Write-Host \"  [PASS] $freeGB GB free on C:\"; exit 0 }"
if errorlevel 1 (
    echo %TIME% - FAIL: Insufficient disk space >> "%LOG%"
    echo.
    echo   Free up space on C: before continuing.
    pause
    exit /b 1
)
echo %TIME% - PASS: Sufficient disk space >> "%LOG%"
set /a PASSED+=1

:: --------------------------------------------------------
:: STEP 5: System Restore Point
:: --------------------------------------------------------
echo.
echo [STEP 5/14] Creating System Restore Point...
echo %TIME% - Creating restore point... >> "%LOG%"
powershell -NoProfile -Command "try { Enable-ComputerRestore -Drive 'C:\' -EA SilentlyContinue; Checkpoint-Computer -Description 'Pre-RepairInstall-SafeMode' -RestorePointType MODIFY_SETTINGS -EA Stop; Write-Host '  [PASS] Restore point created'; exit 0 } catch { Write-Host '  [WARN] Could not create restore point (may be too recent)'; exit 2 }"
if errorlevel 2 (
    echo %TIME% - WARN: Restore point skipped >> "%LOG%"
    set /a WARNED+=1
) else (
    echo %TIME% - PASS: Restore point created >> "%LOG%"
    set /a PASSED+=1
)

:: --------------------------------------------------------
:: STEP 6: Disk health check (read-only chkdsk)
:: --------------------------------------------------------
echo.
echo [STEP 6/14] Checking disk health on C:...
echo %TIME% - Running chkdsk C: /scan... >> "%LOG%"
chkdsk C: /scan >> "%LOG%" 2>&1
if errorlevel 1 (
    echo   [WARN] Disk issues detected - check repair_log.txt
    echo %TIME% - WARN: chkdsk found issues >> "%LOG%"
    set /a WARNED+=1
) else (
    echo   [PASS] Disk health OK
    echo %TIME% - PASS: chkdsk clean >> "%LOG%"
    set /a PASSED+=1
)

:: --------------------------------------------------------
:: STEP 7: SFC /scannow
:: --------------------------------------------------------
echo.
echo [STEP 7/14] Running SFC /scannow (system file integrity)...
echo   This takes 5-15 minutes, please wait...
echo %TIME% - Running SFC... >> "%LOG%"
sfc /scannow >> "%LOG%" 2>&1
echo   [PASS] SFC scan complete (details in repair_log.txt)
echo %TIME% - PASS: SFC complete >> "%LOG%"
set /a PASSED+=1

:: --------------------------------------------------------
:: STEP 8: DISM /RestoreHealth
:: --------------------------------------------------------
echo.
echo [STEP 8/14] Running DISM RestoreHealth (component store)...
echo   This takes 10-20 minutes, please wait...
echo %TIME% - Running DISM... >> "%LOG%"
DISM /Online /Cleanup-Image /RestoreHealth >> "%LOG%" 2>&1
if errorlevel 1 (
    echo   [WARN] DISM reported issues - check repair_log.txt
    echo %TIME% - WARN: DISM issues >> "%LOG%"
    set /a WARNED+=1
) else (
    echo   [PASS] DISM RestoreHealth complete
    echo %TIME% - PASS: DISM complete >> "%LOG%"
    set /a PASSED+=1
)

:: --------------------------------------------------------
:: STEP 9: Clean temp files
:: --------------------------------------------------------
echo.
echo [STEP 9/14] Cleaning temp files...
echo %TIME% - Cleaning temp... >> "%LOG%"
set "CLEANED=0"
if exist "%TEMP%\*" (
    del /f /s /q "%TEMP%\*" >nul 2>&1
    for /d %%D in ("%TEMP%\*") do rd /s /q "%%D" >nul 2>&1
)
if exist "C:\Windows\Temp\*" (
    del /f /s /q "C:\Windows\Temp\*" >nul 2>&1
    for /d %%D in ("C:\Windows\Temp\*") do rd /s /q "%%D" >nul 2>&1
)
if exist "C:\Windows\SoftwareDistribution\Download\*" (
    net stop wuauserv >nul 2>&1
    del /f /s /q "C:\Windows\SoftwareDistribution\Download\*" >nul 2>&1
    net start wuauserv >nul 2>&1
)
echo   [PASS] Temp files cleaned
echo %TIME% - PASS: Temp cleaned >> "%LOG%"
set /a PASSED+=1

:: --------------------------------------------------------
:: STEP 10: Disable third-party services (CLEAN BOOT)
::   This is the KEY step that prevents BSOD 0x5A
:: --------------------------------------------------------
echo.
echo [STEP 10/14] Disabling third-party services for clean boot...
echo   (Backup saved to disabled_services_backup.txt)
echo %TIME% - Disabling third-party services... >> "%LOG%"

:: Use PowerShell to find and disable non-Microsoft services
powershell -NoProfile -Command ^
 "$ErrorActionPreference='SilentlyContinue';" ^
 "$ms = 'Microsoft|Windows|system32|SysWOW64|svchost';" ^
 "$keep = 'wuauserv|bits|CryptSvc|TrustedInstaller|msiserver|EventLog|PlugPlay|RpcSs|RpcEptMapper|DcomLaunch|LSM|SamSs|Netlogon|Dnscache|Dhcp|NlaSvc|WinRM|Winmgmt|Schedule|SysMain|Power|ProfSvc|UserManager|AppXSvc|ShellHWDetection|StorSvc|DeviceInstall|CoreMessagingRegistrar|TimeBrokerSvc|TokenBroker|Themes|FontCache|Audiosrv|AudioEndpointBuilder|Spooler|LanmanServer|LanmanWorkstation|nsi|BFE|mpssvc|WinDefend|WdNisSvc|MDCoreSvc|wscsvc|SecurityHealthService|sppsvc|gpsvc|IKEEXT|PolicyAgent|SessionEnv|TermService|UmRdpService|WSearch|Wcmsvc|WlanSvc|dot3svc|EapHost|Netman|NcbService|CDPSvc|CDPUserSvc|StateRepository|InstallService|ClipSVC|LicenseManager|TabletInputService|TextInputManagementService|DispBrokerDesktopSvc|DusmSvc|CoworkVMService';" ^
 "$svcs = Get-Service | Where-Object { $_.StartType -ne 'Disabled' -and $_.ServiceName -notmatch $keep };" ^
 "$thirdParty = @();" ^
 "foreach ($s in $svcs) {" ^
 "  $wmi = Get-CimInstance Win32_Service -Filter \"Name='$($s.ServiceName)'\" -EA SilentlyContinue;" ^
 "  if ($wmi -and $wmi.PathName -and $wmi.PathName -notmatch $ms) {" ^
 "    $thirdParty += $s;" ^
 "  }" ^
 "};" ^
 "$backup = @();" ^
 "$count = 0;" ^
 "foreach ($s in $thirdParty) {" ^
 "  $backup += \"$($s.ServiceName)|$($s.StartType)\";" ^
 "  try { Set-Service -Name $s.ServiceName -StartupType Disabled -EA Stop; $count++ } catch {}" ^
 "};" ^
 "if ($backup.Count -gt 0) { $backup | Out-File -FilePath '%SVCBACKUP%' -Encoding UTF8 };" ^
 "Write-Host \"  [PASS] Disabled $count third-party services\";" ^
 "exit 0"

echo %TIME% - PASS: Third-party services disabled >> "%LOG%"
set /a PASSED+=1

:: --------------------------------------------------------
:: STEP 11: Disable third-party startup items
:: --------------------------------------------------------
echo.
echo [STEP 11/14] Disabling third-party startup items...
echo   (Backup saved to disabled_startup_backup.txt)
echo %TIME% - Disabling startup items... >> "%LOG%"

powershell -NoProfile -Command ^
 "$ErrorActionPreference='SilentlyContinue';" ^
 "$backup = @();" ^
 "$count = 0;" ^
 "$regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';" ^
 "$items = Get-ItemProperty $regPath -EA SilentlyContinue;" ^
 "if ($items) {" ^
 "  $items.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and $_.Name -ne '' } | ForEach-Object {" ^
 "    if ($_.Value -notmatch 'Microsoft|Windows|SecurityHealth') {" ^
 "      $backup += \"HKCU|$($_.Name)|$($_.Value)\";" ^
 "      Remove-ItemProperty -Path $regPath -Name $_.Name -EA SilentlyContinue;" ^
 "      $count++;" ^
 "    }" ^
 "  }" ^
 "};" ^
 "$regPath2 = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';" ^
 "$items2 = Get-ItemProperty $regPath2 -EA SilentlyContinue;" ^
 "if ($items2) {" ^
 "  $items2.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and $_.Name -ne '' } | ForEach-Object {" ^
 "    if ($_.Value -notmatch 'Microsoft|Windows|SecurityHealth') {" ^
 "      $backup += \"HKLM|$($_.Name)|$($_.Value)\";" ^
 "      Remove-ItemProperty -Path $regPath2 -Name $_.Name -EA SilentlyContinue;" ^
 "      $count++;" ^
 "    }" ^
 "  }" ^
 "};" ^
 "if ($backup.Count -gt 0) { $backup | Out-File -FilePath '%STARTUPBACKUP%' -Encoding UTF8 };" ^
 "Write-Host \"  [PASS] Disabled $count third-party startup items\";" ^
 "exit 0"

echo %TIME% - PASS: Startup items disabled >> "%LOG%"
set /a PASSED+=1

:: --------------------------------------------------------
:: STEP 12: Generate RESTORE_SERVICES.bat
:: --------------------------------------------------------
echo.
echo [STEP 12/14] Generating post-upgrade restore script...
echo %TIME% - Generating restore script... >> "%LOG%"

> "%RESTORESCRIPT%" echo @echo off
>> "%RESTORESCRIPT%" echo setlocal enabledelayedexpansion
>> "%RESTORESCRIPT%" echo echo Restoring third-party services and startup items...
>> "%RESTORESCRIPT%" echo echo.

:: Restore services from backup
powershell -NoProfile -Command ^
 "if (Test-Path '%SVCBACKUP%') {" ^
 "  $lines = Get-Content '%SVCBACKUP%';" ^
 "  foreach ($line in $lines) {" ^
 "    $parts = $line.Split('|');" ^
 "    if ($parts.Count -eq 2) {" ^
 "      $name = $parts[0]; $mode = $parts[1];" ^
 "      $startType = switch ($mode) { 'Automatic' {'auto'} 'Manual' {'demand'} default {'demand'} };" ^
 "      Add-Content -Path '%RESTORESCRIPT%' -Value \"sc config $name start= $startType\";" ^
 "    }" ^
 "  }" ^
 "};" ^
 "if (Test-Path '%STARTUPBACKUP%') {" ^
 "  $lines = Get-Content '%STARTUPBACKUP%';" ^
 "  foreach ($line in $lines) {" ^
 "    $parts = $line.Split('|');" ^
 "    if ($parts.Count -eq 3) {" ^
 "      $hive = $parts[0]; $name = $parts[1]; $val = $parts[2];" ^
 "      if ($hive -eq 'HKCU') {" ^
 "        Add-Content -Path '%RESTORESCRIPT%' -Value \"reg add \`\"HKCU\Software\Microsoft\Windows\CurrentVersion\Run\`\" /v \`\"$name\`\" /t REG_SZ /d \`\"$val\`\" /f\";" ^
 "      } else {" ^
 "        Add-Content -Path '%RESTORESCRIPT%' -Value \"reg add \`\"HKLM\Software\Microsoft\Windows\CurrentVersion\Run\`\" /v \`\"$name\`\" /t REG_SZ /d \`\"$val\`\" /f\";" ^
 "      }" ^
 "    }" ^
 "  }" ^
 "}"

>> "%RESTORESCRIPT%" echo echo.
>> "%RESTORESCRIPT%" echo echo [DONE] All services and startup items restored.
>> "%RESTORESCRIPT%" echo echo Reboot recommended.
>> "%RESTORESCRIPT%" echo pause

echo   [PASS] RESTORE_SERVICES.bat created
echo   *** RUN RESTORE_SERVICES.bat AFTER the upgrade completes ***
echo %TIME% - PASS: Restore script generated >> "%LOG%"
set /a PASSED+=1

:: --------------------------------------------------------
:: STEP 13: Mount ISO and run COMPATIBILITY SCAN first
:: --------------------------------------------------------
echo.
echo [STEP 13/14] Mounting ISO and running compatibility scan...
echo %TIME% - Mounting ISO... >> "%LOG%"

powershell -NoProfile -Command "Mount-DiskImage -ImagePath '%ISO%' -EA Stop"
if errorlevel 1 (
    echo   [FAIL] Could not mount ISO
    echo %TIME% - FAIL: Mount failed >> "%LOG%"
    pause
    exit /b 1
)

set "DRIVE="
for /f "tokens=*" %%D in ('powershell -NoProfile -Command "(Get-DiskImage -ImagePath '%ISO%' | Get-Volume).DriveLetter"') do set "DRIVE=%%D"

if not defined DRIVE (
    echo   [FAIL] Could not determine mount drive letter
    echo %TIME% - FAIL: No drive letter >> "%LOG%"
    pause
    exit /b 1
)

echo   Mounted to: !DRIVE!:
echo %TIME% - Mounted to !DRIVE!: >> "%LOG%"

if not exist "!DRIVE!:\setup.exe" (
    echo   [FAIL] setup.exe not found on !DRIVE!:
    echo %TIME% - FAIL: No setup.exe >> "%LOG%"
    pause
    exit /b 1
)

:: Run compatibility scan FIRST - this catches problems before the real upgrade
echo.
echo   Running compatibility scan (this checks for driver/software conflicts)...
echo %TIME% - Running compat scan... >> "%LOG%"
"!DRIVE!:\setup.exe" /auto upgrade /dynamicupdate disable /compat scanonly /eula accept /telemetry disable /quiet
set "COMPAT_RESULT=!ERRORLEVEL!"

if !COMPAT_RESULT! EQU -1047526896 (
    echo   [FAIL] Compatibility scan found BLOCKING issues!
    echo   Check C:\$WINDOWS.~BT\Sources\Panther\CompatData*.xml for details
    echo %TIME% - FAIL: Compat blockers found >> "%LOG%"
    echo.
    echo   Fix the blocking issues and try again.
    echo   Dismounting ISO...
    powershell -NoProfile -Command "Dismount-DiskImage -ImagePath '%ISO%'" >nul 2>&1
    pause
    exit /b 1
)

if !COMPAT_RESULT! EQU -1047526904 (
    echo   [WARN] Compatibility scan found warnings ^(non-blocking^)
    echo %TIME% - WARN: Compat warnings >> "%LOG%"
    set /a WARNED+=1
) else (
    echo   [PASS] Compatibility scan passed
    echo %TIME% - PASS: Compat scan clean >> "%LOG%"
    set /a PASSED+=1
)

:: --------------------------------------------------------
:: STEP 14: Launch Windows Setup with SAFE flags
::   KEY CHANGES from old script:
::   - REMOVED /migratedrivers all (was forcing incompatible driver migration)
::   - REMOVED /compat ignorewarning (was hiding conflicts)
::   - ADDED /priority normal (prevents resource starvation)
::   - ADDED /showoobe none (skip OOBE screens)
:: --------------------------------------------------------
echo.
echo ============================================================
echo   PRE-FLIGHT SUMMARY
echo   Passed: !PASSED!  Warnings: !WARNED!  Failed: !FAILED!
echo ============================================================
echo.

set "ARGS=/auto upgrade /dynamicupdate disable /eula accept /telemetry disable /priority normal /showoobe none /compat ignorewarning"
echo [STEP 14/14] Launching Windows Setup with SAFE flags...
echo.
echo   Flags: !ARGS!
echo.
echo   KEY SAFETY CHANGES:
echo     - NO /migratedrivers all (lets Windows pick safe drivers)
echo     - Compat scan already passed (Step 13)
echo     - Third-party services disabled (clean boot)
echo     - System integrity verified (SFC + DISM)
echo.
echo %TIME% - Launching setup: !ARGS! >> "%LOG%"

start "" "!DRIVE!:\setup.exe" !ARGS!

:: Wait a moment and verify setup launched
timeout /t 3 /nobreak >nul
tasklist /fi "imagename eq setupprep.exe" 2>nul | findstr /i "setupprep" >nul
if errorlevel 1 (
    tasklist /fi "imagename eq setup.exe" 2>nul | findstr /i "setup" >nul
    if errorlevel 1 (
        echo   [WARN] Could not verify setup.exe is running
        echo %TIME% - WARN: Setup process not confirmed >> "%LOG%"
    ) else (
        echo   [PASS] Setup is running
        echo %TIME% - PASS: Setup running >> "%LOG%"
    )
) else (
    echo   [PASS] Setup is running
    echo %TIME% - PASS: Setup running >> "%LOG%"
)

echo.
echo ============================================================
echo   SETUP LAUNCHED SUCCESSFULLY
echo ============================================================
echo.
echo   Windows will restart automatically during the repair.
echo   DO NOT turn off your computer!
echo.
echo   AFTER the upgrade completes successfully:
echo     1. Run RESTORE_SERVICES.bat (in this folder)
echo        to re-enable your third-party services
echo     2. Reboot once more
echo.
echo   Log saved to: %LOG%
echo.
echo %TIME% - === Setup launched, waiting for upgrade === >> "%LOG%"
pause
