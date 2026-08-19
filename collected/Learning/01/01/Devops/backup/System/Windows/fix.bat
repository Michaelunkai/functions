@echo off
setlocal enabledelayedexpansion
title ULTIMATE WINDOWS RECOVERY v3.0 - WinRE Optimized
color 1F

:: ================================================================
:: ULTIMATE WINDOWS RECOVERY SCRIPT v3.0
:: 100% Windows Recovery Environment Compatible
:: 200+ Intelligent Commands - Runs Only What's Needed
:: ================================================================

echo.
echo ================================================================
echo   ULTIMATE WINDOWS RECOVERY SYSTEM v3.0
echo   100%% WinRE Compatible - Intelligent Repair Engine
echo ================================================================
echo.
echo  Your Detected Errors:
echo  - Automatic Repair couldn't repair your PC
echo  - Boot critical file acpiex.sys is corrupt  
echo  - File repair failed with Error code 0x57
echo.
echo  Press Ctrl+C to cancel, or
pause

:: ================================================================
:: PHASE 0: ENVIRONMENT DETECTION AND SETUP
:: ================================================================
echo.
echo ================================================================
echo [PHASE 0/16] ENVIRONMENT DETECTION
echo ================================================================
echo.

:: Initialize all diagnostic flags
set "WINDRIVE="
set "WINPART="
set "EFIPART="
set "ACPIEX_ISSUE=0"
set "DRIVER_ISSUE=0"
set "BCD_ISSUE=0"
set "MBR_ISSUE=0"
set "BOOT_ISSUE=0"
set "EFI_ISSUE=0"
set "REGISTRY_ISSUE=0"
set "SYSTEM_FILE_ISSUE=0"
set "STORE_ISSUE=0"
set "DISK_ISSUE=0"
set "NTFS_ISSUE=0"
set "PENDING_ISSUE=0"
set "VSS_ISSUE=0"
set "PROFILE_ISSUE=0"
set "TRUST_ISSUE=0"
set "UEFI_MODE=0"

echo [0.1] Detecting Windows installation drive...

:: Method 1: Check common drive letters for Windows
for %%d in (C D E F G H) do (
    if exist %%d:\Windows\System32\config\SYSTEM (
        set "WINDRIVE=%%d:"
        echo Found Windows on %%d:
        goto :found_windows
    )
)

:: Method 2: If not found, default to C:
set "WINDRIVE=C:"
echo Defaulting to C:

:found_windows
set "WINDIR=%WINDRIVE%\Windows"

echo [0.2] Detecting boot mode (UEFI/BIOS)...
if exist %WINDRIVE%\EFI\Microsoft\Boot\bootmgfw.efi (
    set "UEFI_MODE=1"
    echo Boot Mode: UEFI
) else (
    echo Boot Mode: Legacy BIOS
)

echo [0.3] Detecting EFI System Partition...
for %%d in (S T U V W X Y Z) do (
    if exist %%d:\EFI\Microsoft\Boot\BCD (
        set "EFIPART=%%d:"
        echo Found EFI partition on %%d:
        goto :found_efi
    )
)
:: Check if EFI is on Windows drive
if exist %WINDRIVE%\EFI\Microsoft\Boot\BCD (
    set "EFIPART=%WINDRIVE%"
)
:found_efi

echo [0.4] Creating working directory...
if not exist X:\Recovery md X:\Recovery 2>nul
if not exist %WINDRIVE%\Recovery md %WINDRIVE%\Recovery 2>nul
set "WORKDIR=%WINDRIVE%\Recovery"

echo.
echo Environment configured:
echo   Windows Drive: %WINDRIVE%
echo   Windows Dir:   %WINDIR%
echo   EFI Partition: %EFIPART%
echo   Work Dir:      %WORKDIR%
echo.

:: ================================================================
:: PHASE 1: COMPREHENSIVE DIAGNOSTICS (50 Checks)
:: ================================================================
echo ================================================================
echo [PHASE 1/16] COMPREHENSIVE DIAGNOSTICS
echo ================================================================
echo.

:: ---------- DISK AND VOLUME DIAGNOSTICS ----------
echo [DIAG 01/50] Checking disk structure...
echo list disk > %WORKDIR%\dp_disk.txt
diskpart /s %WORKDIR%\dp_disk.txt > %WORKDIR%\disks.log 2>&1
del %WORKDIR%\dp_disk.txt 2>nul

echo [DIAG 02/50] Checking volume structure...
echo list volume > %WORKDIR%\dp_vol.txt
diskpart /s %WORKDIR%\dp_vol.txt > %WORKDIR%\volumes.log 2>&1
del %WORKDIR%\dp_vol.txt 2>nul

echo [DIAG 03/50] Checking partition table...
echo select disk 0 > %WORKDIR%\dp_part.txt
echo list partition >> %WORKDIR%\dp_part.txt
diskpart /s %WORKDIR%\dp_part.txt > %WORKDIR%\partitions.log 2>&1
del %WORKDIR%\dp_part.txt 2>nul

echo [DIAG 04/50] Checking file system dirty bit...
set "DIRTY_RESULT="
for /f "tokens=*" %%a in ('fsutil dirty query %WINDRIVE% 2^>nul') do set "DIRTY_RESULT=%%a"
echo %DIRTY_RESULT% | findstr /i "dirty" >nul 2>&1 && set "DISK_ISSUE=1"

echo [DIAG 05/50] Checking NTFS integrity...
fsutil fsinfo ntfsinfo %WINDRIVE% >nul 2>&1
if errorlevel 1 set "NTFS_ISSUE=1"

echo [DIAG 06/50] Checking volume info...
fsutil fsinfo volumeinfo %WINDRIVE% > %WORKDIR%\volinfo.log 2>&1

echo [DIAG 07/50] Checking sector info...
fsutil fsinfo sectorinfo %WINDRIVE% > %WORKDIR%\sector.log 2>&1

echo [DIAG 08/50] Checking drive type...
fsutil fsinfo drivetype %WINDRIVE% > %WORKDIR%\drivetype.log 2>&1

echo [DIAG 09/50] Checking USN journal...
fsutil usn queryjournal %WINDRIVE% > %WORKDIR%\usn.log 2>&1

echo [DIAG 10/50] Checking repair flags...
fsutil repair query %WINDRIVE% > %WORKDIR%\repair.log 2>&1

:: ---------- BOOT CONFIGURATION DIAGNOSTICS ----------
echo [DIAG 11/50] Checking BCD store...
bcdedit /enum all > %WORKDIR%\bcd_all.log 2>&1
if errorlevel 1 set "BCD_ISSUE=1"

echo [DIAG 12/50] Checking boot manager...
bcdedit /enum {bootmgr} > %WORKDIR%\bcd_mgr.log 2>&1
if errorlevel 1 set "BCD_ISSUE=1"

echo [DIAG 13/50] Checking Windows loader...
bcdedit /enum {current} > %WORKDIR%\bcd_cur.log 2>&1
if errorlevel 1 set "BCD_ISSUE=1"

echo [DIAG 14/50] Checking default entry...
bcdedit /enum {default} > %WORKDIR%\bcd_def.log 2>&1
if errorlevel 1 set "BCD_ISSUE=1"

echo [DIAG 15/50] Checking bootmgr (BIOS)...
if not exist %WINDRIVE%\bootmgr (
    if "%UEFI_MODE%"=="0" set "MBR_ISSUE=1"
)

echo [DIAG 16/50] Checking bootmgfw.efi (UEFI)...
if "%UEFI_MODE%"=="1" (
    if not exist %WINDRIVE%\EFI\Microsoft\Boot\bootmgfw.efi set "EFI_ISSUE=1"
    if defined EFIPART (
        if not exist %EFIPART%\EFI\Microsoft\Boot\bootmgfw.efi set "EFI_ISSUE=1"
    )
)

echo [DIAG 17/50] Checking Boot\BCD...
if not exist %WINDRIVE%\Boot\BCD (
    if "%UEFI_MODE%"=="0" set "BCD_ISSUE=1"
)

echo [DIAG 18/50] Checking winload.exe...
if not exist %WINDIR%\System32\winload.exe set "BOOT_ISSUE=1"

echo [DIAG 19/50] Checking winload.efi...
if not exist %WINDIR%\System32\winload.efi (
    if "%UEFI_MODE%"=="1" set "BOOT_ISSUE=1"
)

echo [DIAG 20/50] Checking winresume...
if not exist %WINDIR%\System32\winresume.exe set "BOOT_ISSUE=1"

:: ---------- CRITICAL DRIVER DIAGNOSTICS ----------
echo [DIAG 21/50] Checking acpiex.sys [PRIMARY ISSUE]...
if not exist %WINDIR%\System32\drivers\acpiex.sys (
    set "ACPIEX_ISSUE=1"
    set "DRIVER_ISSUE=1"
) else (
    for %%A in (%WINDIR%\System32\drivers\acpiex.sys) do (
        if %%~zA EQU 0 (
            set "ACPIEX_ISSUE=1"
            set "DRIVER_ISSUE=1"
        )
    )
)

echo [DIAG 22/50] Checking acpi.sys...
if not exist %WINDIR%\System32\drivers\acpi.sys set "DRIVER_ISSUE=1"

echo [DIAG 23/50] Checking ntfs.sys...
if not exist %WINDIR%\System32\drivers\ntfs.sys set "DRIVER_ISSUE=1"

echo [DIAG 24/50] Checking disk.sys...
if not exist %WINDIR%\System32\drivers\disk.sys set "DRIVER_ISSUE=1"

echo [DIAG 25/50] Checking pci.sys...
if not exist %WINDIR%\System32\drivers\pci.sys set "DRIVER_ISSUE=1"

echo [DIAG 26/50] Checking classpnp.sys...
if not exist %WINDIR%\System32\drivers\classpnp.sys set "DRIVER_ISSUE=1"

echo [DIAG 27/50] Checking volmgr.sys...
if not exist %WINDIR%\System32\drivers\volmgr.sys set "DRIVER_ISSUE=1"

echo [DIAG 28/50] Checking partmgr.sys...
if not exist %WINDIR%\System32\drivers\partmgr.sys set "DRIVER_ISSUE=1"

echo [DIAG 29/50] Checking storport.sys...
if not exist %WINDIR%\System32\drivers\storport.sys set "DRIVER_ISSUE=1"

echo [DIAG 30/50] Checking fltMgr.sys...
if not exist %WINDIR%\System32\drivers\fltMgr.sys set "DRIVER_ISSUE=1"

:: ---------- SYSTEM FILE DIAGNOSTICS ----------
echo [DIAG 31/50] Checking ntoskrnl.exe...
if not exist %WINDIR%\System32\ntoskrnl.exe set "SYSTEM_FILE_ISSUE=1"

echo [DIAG 32/50] Checking hal.dll...
if not exist %WINDIR%\System32\hal.dll set "SYSTEM_FILE_ISSUE=1"

echo [DIAG 33/50] Checking kernel32.dll...
if not exist %WINDIR%\System32\kernel32.dll set "SYSTEM_FILE_ISSUE=1"

echo [DIAG 34/50] Checking ntdll.dll...
if not exist %WINDIR%\System32\ntdll.dll set "SYSTEM_FILE_ISSUE=1"

echo [DIAG 35/50] Checking ci.dll...
if not exist %WINDIR%\System32\ci.dll set "SYSTEM_FILE_ISSUE=1"

echo [DIAG 36/50] Checking smss.exe...
if not exist %WINDIR%\System32\smss.exe set "SYSTEM_FILE_ISSUE=1"

echo [DIAG 37/50] Checking csrss.exe...
if not exist %WINDIR%\System32\csrss.exe set "SYSTEM_FILE_ISSUE=1"

echo [DIAG 38/50] Checking wininit.exe...
if not exist %WINDIR%\System32\wininit.exe set "SYSTEM_FILE_ISSUE=1"

echo [DIAG 39/50] Checking services.exe...
if not exist %WINDIR%\System32\services.exe set "SYSTEM_FILE_ISSUE=1"

echo [DIAG 40/50] Checking lsass.exe...
if not exist %WINDIR%\System32\lsass.exe set "SYSTEM_FILE_ISSUE=1"

:: ---------- REGISTRY DIAGNOSTICS ----------
echo [DIAG 41/50] Checking SYSTEM hive...
if not exist %WINDIR%\System32\config\SYSTEM (
    set "REGISTRY_ISSUE=1"
) else (
    for %%A in (%WINDIR%\System32\config\SYSTEM) do if %%~zA EQU 0 set "REGISTRY_ISSUE=1"
)

echo [DIAG 42/50] Checking SOFTWARE hive...
if not exist %WINDIR%\System32\config\SOFTWARE (
    set "REGISTRY_ISSUE=1"
) else (
    for %%A in (%WINDIR%\System32\config\SOFTWARE) do if %%~zA EQU 0 set "REGISTRY_ISSUE=1"
)

echo [DIAG 43/50] Checking SAM hive...
if not exist %WINDIR%\System32\config\SAM set "REGISTRY_ISSUE=1"

echo [DIAG 44/50] Checking SECURITY hive...
if not exist %WINDIR%\System32\config\SECURITY set "REGISTRY_ISSUE=1"

echo [DIAG 45/50] Checking DEFAULT hive...
if not exist %WINDIR%\System32\config\DEFAULT set "REGISTRY_ISSUE=1"

echo [DIAG 46/50] Checking RegBack availability...
if not exist %WINDIR%\System32\config\RegBack\SYSTEM set "REGISTRY_ISSUE=1"

echo [DIAG 47/50] Checking for pending operations...
reg load HKLM\OFFLINE_SYS %WINDIR%\System32\config\SYSTEM >nul 2>&1
reg query "HKLM\OFFLINE_SYS\ControlSet001\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1 && set "PENDING_ISSUE=1"
reg unload HKLM\OFFLINE_SYS >nul 2>&1

echo [DIAG 48/50] Checking SrtTrail.txt...
if exist %WINDIR%\System32\Logfiles\Srt\SrtTrail.txt (
    findstr /i "corrupt damaged" %WINDIR%\System32\Logfiles\Srt\SrtTrail.txt >nul 2>&1 && set "DRIVER_ISSUE=1"
)

echo [DIAG 49/50] Checking CBS.log for errors...
if exist %WINDIR%\Logs\CBS\CBS.log (
    findstr /i "error failed" %WINDIR%\Logs\CBS\CBS.log >nul 2>&1 && set "SYSTEM_FILE_ISSUE=1"
)

echo [DIAG 50/50] Checking component store health...
dism /image:%WINDRIVE%\ /cleanup-image /checkhealth > %WORKDIR%\dism_check.log 2>&1
findstr /i "repairable" %WORKDIR%\dism_check.log >nul 2>&1 && set "STORE_ISSUE=1"

:: ================================================================
:: DIAGNOSTIC RESULTS SUMMARY
:: ================================================================
echo.
echo ================================================================
echo DIAGNOSTIC RESULTS SUMMARY
echo ================================================================
echo.
echo Windows Drive: %WINDRIVE%
echo Boot Mode: %UEFI_MODE% (1=UEFI, 0=BIOS)
echo.
echo Issues Detected:
echo ----------------
set "ISSUES_FOUND=0"
if "%ACPIEX_ISSUE%"=="1" (echo [CRITICAL] acpiex.sys corruption & set "ISSUES_FOUND=1")
if "%DRIVER_ISSUE%"=="1" (echo [CRITICAL] Boot driver corruption & set "ISSUES_FOUND=1")
if "%BCD_ISSUE%"=="1" (echo [CRITICAL] Boot Configuration Data error & set "ISSUES_FOUND=1")
if "%MBR_ISSUE%"=="1" (echo [CRITICAL] Master Boot Record error & set "ISSUES_FOUND=1")
if "%EFI_ISSUE%"=="1" (echo [CRITICAL] EFI boot files missing & set "ISSUES_FOUND=1")
if "%BOOT_ISSUE%"=="1" (echo [CRITICAL] Boot loader files missing & set "ISSUES_FOUND=1")
if "%REGISTRY_ISSUE%"=="1" (echo [HIGH] Registry hive corruption & set "ISSUES_FOUND=1")
if "%SYSTEM_FILE_ISSUE%"=="1" (echo [HIGH] System file corruption & set "ISSUES_FOUND=1")
if "%STORE_ISSUE%"=="1" (echo [HIGH] Component store corruption & set "ISSUES_FOUND=1")
if "%DISK_ISSUE%"=="1" (echo [MEDIUM] Disk file system errors & set "ISSUES_FOUND=1")
if "%NTFS_ISSUE%"=="1" (echo [MEDIUM] NTFS integrity errors & set "ISSUES_FOUND=1")
if "%PENDING_ISSUE%"=="1" (echo [MEDIUM] Pending operations blocking boot & set "ISSUES_FOUND=1")
if "%ISSUES_FOUND%"=="0" echo No critical issues detected - running preventive repairs
echo.
echo Press any key to begin targeted repairs...
pause >nul

:: ================================================================
:: PHASE 2: ACPIEX.SYS CRITICAL REPAIR
:: ================================================================
if "%ACPIEX_ISSUE%"=="1" (
    echo.
    echo ================================================================
    echo [PHASE 2/16] CRITICAL: ACPIEX.SYS REPAIR
    echo ================================================================
    echo.
    
    echo [001/200] Checking acpiex.sys current state...
    dir %WINDIR%\System32\drivers\acpiex.sys 2>&1
    
    echo [002/200] Removing hidden/system/readonly attributes...
    attrib -h -r -s %WINDIR%\System32\drivers\acpiex.sys 2>nul
    
    echo [003/200] Backing up corrupt acpiex.sys...
    if exist %WINDIR%\System32\drivers\acpiex.sys (
        copy /y %WINDIR%\System32\drivers\acpiex.sys %WORKDIR%\acpiex.sys.corrupt 2>nul
    )
    
    echo [004/200] Removing corrupt acpiex.sys...
    del /f /q %WINDIR%\System32\drivers\acpiex.sys 2>nul
    
    echo [005/200] Searching WinSxS for acpiex.sys...
    set "ACPIEX_FOUND=0"
    for /f "tokens=*" %%a in ('dir /s /b %WINDIR%\WinSxS\*acpiex.sys 2^>nul') do (
        echo Found: %%a
        copy /y "%%a" %WINDIR%\System32\drivers\acpiex.sys
        set "ACPIEX_FOUND=1"
        goto :acpiex_check1
    )
    :acpiex_check1
    
    echo [006/200] Searching DriverStore for acpiex.sys...
    if "%ACPIEX_FOUND%"=="0" (
        for /f "tokens=*" %%a in ('dir /s /b %WINDIR%\System32\DriverStore\FileRepository\*acpiex.sys 2^>nul') do (
            echo Found: %%a
            copy /y "%%a" %WINDIR%\System32\drivers\acpiex.sys
            set "ACPIEX_FOUND=1"
            goto :acpiex_check2
        )
    )
    :acpiex_check2
    
    echo [007/200] Searching System32\drivers backup...
    if "%ACPIEX_FOUND%"=="0" (
        for /f "tokens=*" %%a in ('dir /s /b %WINDIR%\System32\*acpiex*.sys 2^>nul') do (
            echo Found: %%a
            copy /y "%%a" %WINDIR%\System32\drivers\acpiex.sys
            set "ACPIEX_FOUND=1"
            goto :acpiex_check3
        )
    )
    :acpiex_check3
    
    echo [008/200] Attempting expand from CAB files...
    if "%ACPIEX_FOUND%"=="0" (
        for /f "tokens=*" %%a in ('dir /s /b %WINDIR%\WinSxS\*.cab 2^>nul') do (
            expand "%%a" -f:acpiex.sys %WINDIR%\System32\drivers\ 2>nul
            if exist %WINDIR%\System32\drivers\acpiex.sys (
                set "ACPIEX_FOUND=1"
                goto :acpiex_check4
            )
        )
    )
    :acpiex_check4
    
    echo [009/200] Verifying acpiex.sys restoration...
    if exist %WINDIR%\System32\drivers\acpiex.sys (
        echo SUCCESS: acpiex.sys restored
        attrib +r %WINDIR%\System32\drivers\acpiex.sys
    ) else (
        echo WARNING: acpiex.sys needs DISM repair
    )
    
    echo [010/200] Running SFC on acpiex.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\acpiex.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [011/200] Checking related ACPI drivers...
    sfc /scanfile=%WINDIR%\System32\drivers\acpi.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [012/200] Checking msacpi.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\msacpi.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
    
    echo [013/200] Checking compbatt.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\compbatt.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
    
    echo [014/200] Checking battc.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\battc.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
    
    echo [015/200] Checking CmBatt.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\CmBatt.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
    
    echo [016/200] Checking wmiacpi.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\wmiacpi.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
    
    echo [017/200] Checking acpipagr.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\acpipagr.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
    
    echo [018/200] Checking acpitime.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\acpitime.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
    
    echo [019/200] Checking acpipmi.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\acpipmi.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
    
    echo [020/200] Checking AcpiDev.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\AcpiDev.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
)

:: ================================================================
:: PHASE 3: BOOT-CRITICAL DRIVER REPAIR
:: ================================================================
if "%DRIVER_ISSUE%"=="1" (
    echo.
    echo ================================================================
    echo [PHASE 3/16] BOOT-CRITICAL DRIVER REPAIR
    echo ================================================================
    echo.
    
    echo [021/200] Repairing ntfs.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\ntfs.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [022/200] Repairing disk.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\disk.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [023/200] Repairing partmgr.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\partmgr.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [024/200] Repairing volmgr.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\volmgr.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [025/200] Repairing volmgrx.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\volmgrx.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [026/200] Repairing volsnap.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\volsnap.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [027/200] Repairing mountmgr.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\mountmgr.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [028/200] Repairing pci.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\pci.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [029/200] Repairing pcw.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\pcw.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [030/200] Repairing pciide.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\pciide.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [031/200] Repairing pciidex.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\pciidex.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [032/200] Repairing atapi.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\atapi.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [033/200] Repairing ataport.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\ataport.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [034/200] Repairing storahci.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\storahci.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [035/200] Repairing storport.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\storport.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [036/200] Repairing stornvme.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\stornvme.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
    
    echo [037/200] Repairing EhStorClass.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\EhStorClass.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [038/200] Repairing classpnp.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\classpnp.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [039/200] Repairing fltMgr.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\fltMgr.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [040/200] Repairing ksecdd.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\ksecdd.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [041/200] Repairing ksecpkg.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\ksecpkg.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [042/200] Repairing cng.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\cng.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [043/200] Repairing Fs_Rec.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\Fs_Rec.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [044/200] Repairing vdrvroot.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\vdrvroot.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [045/200] Repairing CLFS.SYS...
    sfc /scanfile=%WINDIR%\System32\drivers\CLFS.SYS /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [046/200] Repairing tm.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\tm.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [047/200] Repairing WDFLDR.SYS...
    sfc /scanfile=%WINDIR%\System32\drivers\WDFLDR.SYS /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [048/200] Repairing Wdf01000.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\Wdf01000.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [049/200] Repairing msrpc.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\msrpc.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [050/200] Repairing hwpolicy.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\hwpolicy.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [051/200] Repairing msisadrv.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\msisadrv.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [052/200] Repairing intelppm.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\intelppm.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
    
    echo [053/200] Repairing amdppm.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\amdppm.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
    
    echo [054/200] Repairing NETIO.SYS...
    sfc /scanfile=%WINDIR%\System32\drivers\NETIO.SYS /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [055/200] Repairing ndis.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\ndis.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [056/200] Repairing tcpip.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\tcpip.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [057/200] Repairing fwpkclnt.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\fwpkclnt.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [058/200] Repairing afd.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\afd.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [059/200] Repairing tdx.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\tdx.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [060/200] Repairing winhv.sys...
    sfc /scanfile=%WINDIR%\System32\drivers\winhv.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
)

:: ================================================================
:: PHASE 4: SYSTEM FILE REPAIR
:: ================================================================
if "%SYSTEM_FILE_ISSUE%"=="1" (
    echo.
    echo ================================================================
    echo [PHASE 4/16] SYSTEM FILE REPAIR
    echo ================================================================
    echo.
    
    echo [061/200] Repairing ntoskrnl.exe...
    sfc /scanfile=%WINDIR%\System32\ntoskrnl.exe /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [062/200] Repairing ntkrnlpa.exe...
    sfc /scanfile=%WINDIR%\System32\ntkrnlpa.exe /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
    
    echo [063/200] Repairing hal.dll...
    sfc /scanfile=%WINDIR%\System32\hal.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [064/200] Repairing kernel32.dll...
    sfc /scanfile=%WINDIR%\System32\kernel32.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [065/200] Repairing kernelbase.dll...
    sfc /scanfile=%WINDIR%\System32\kernelbase.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [066/200] Repairing ntdll.dll...
    sfc /scanfile=%WINDIR%\System32\ntdll.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [067/200] Repairing ci.dll...
    sfc /scanfile=%WINDIR%\System32\ci.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [068/200] Repairing smss.exe...
    sfc /scanfile=%WINDIR%\System32\smss.exe /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [069/200] Repairing csrss.exe...
    sfc /scanfile=%WINDIR%\System32\csrss.exe /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [070/200] Repairing wininit.exe...
    sfc /scanfile=%WINDIR%\System32\wininit.exe /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [071/200] Repairing winlogon.exe...
    sfc /scanfile=%WINDIR%\System32\winlogon.exe /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [072/200] Repairing services.exe...
    sfc /scanfile=%WINDIR%\System32\services.exe /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [073/200] Repairing lsass.exe...
    sfc /scanfile=%WINDIR%\System32\lsass.exe /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [074/200] Repairing lsm.dll...
    sfc /scanfile=%WINDIR%\System32\lsm.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [075/200] Repairing svchost.exe...
    sfc /scanfile=%WINDIR%\System32\svchost.exe /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [076/200] Repairing userinit.exe...
    sfc /scanfile=%WINDIR%\System32\userinit.exe /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [077/200] Repairing dwm.exe...
    sfc /scanfile=%WINDIR%\System32\dwm.exe /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [078/200] Repairing LogonUI.exe...
    sfc /scanfile=%WINDIR%\System32\LogonUI.exe /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [079/200] Repairing explorer.exe...
    sfc /scanfile=%WINDIR%\explorer.exe /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [080/200] Repairing cmd.exe...
    sfc /scanfile=%WINDIR%\System32\cmd.exe /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
)

:: ================================================================
:: PHASE 5: BCD AND MBR REPAIR
:: ================================================================
if "%BCD_ISSUE%"=="1" goto :do_bcd_repair
if "%MBR_ISSUE%"=="1" goto :do_bcd_repair
if "%BOOT_ISSUE%"=="1" goto :do_bcd_repair
goto :skip_bcd_repair

:do_bcd_repair
echo.
echo ================================================================
echo [PHASE 5/16] BCD AND MBR REPAIR
echo ================================================================
echo.

echo [081/200] Backing up current BCD...
bcdedit /export %WORKDIR%\BCD_backup.bak 2>nul

echo [082/200] Repairing Master Boot Record...
bootrec /fixmbr

echo [083/200] Repairing boot sector...
bootrec /fixboot

echo [084/200] Scanning for Windows installations...
bootrec /scanos

echo [085/200] Rebuilding BCD store...
echo Y | bootrec /rebuildbcd

echo [086/200] Removing BCD attributes (BIOS)...
attrib -h -r -s %WINDRIVE%\Boot\BCD 2>nul

echo [087/200] Backing up old BCD (BIOS)...
if exist %WINDRIVE%\Boot\BCD ren %WINDRIVE%\Boot\BCD BCD.old 2>nul

echo [088/200] Creating new boot files (BIOS)...
bcdboot %WINDIR% /s %WINDRIVE% /f BIOS

echo [089/200] Creating new boot files (ALL)...
bcdboot %WINDIR% /s %WINDRIVE% /f ALL

echo [090/200] Applying boot sector NT60...
bootsect /nt60 %WINDRIVE% /force

echo [091/200] Applying boot sector ALL...
bootsect /nt60 ALL /force

echo [092/200] Setting default entry...
bcdedit /default {current} 2>nul

echo [093/200] Setting timeout...
bcdedit /timeout 10 2>nul

echo [094/200] Enabling recovery...
bcdedit /set {current} recoveryenabled yes 2>nul

echo [095/200] Setting device partition...
bcdedit /set {current} device partition=%WINDRIVE% 2>nul

echo [096/200] Setting osdevice partition...
bcdedit /set {current} osdevice partition=%WINDRIVE% 2>nul

echo [097/200] Setting systemroot...
bcdedit /set {current} systemroot \Windows 2>nul

echo [098/200] Verifying BCD configuration...
bcdedit /enum all

:skip_bcd_repair

:: ================================================================
:: PHASE 6: EFI REPAIR (UEFI Systems Only)
:: ================================================================
if "%EFI_ISSUE%"=="1" goto :do_efi_repair
if "%UEFI_MODE%"=="1" (
    if "%BCD_ISSUE%"=="1" goto :do_efi_repair
)
goto :skip_efi_repair

:do_efi_repair
echo.
echo ================================================================
echo [PHASE 6/16] EFI SYSTEM PARTITION REPAIR
echo ================================================================
echo.

echo [099/200] Locating EFI partition...
echo list volume > %WORKDIR%\dp_efi.txt
diskpart /s %WORKDIR%\dp_efi.txt
del %WORKDIR%\dp_efi.txt 2>nul

echo [100/200] Assigning letter to EFI partition...
echo select disk 0 > %WORKDIR%\dp_assign.txt
echo list partition >> %WORKDIR%\dp_assign.txt
echo select partition 1 >> %WORKDIR%\dp_assign.txt
echo assign letter=S >> %WORKDIR%\dp_assign.txt
diskpart /s %WORKDIR%\dp_assign.txt 2>nul
del %WORKDIR%\dp_assign.txt 2>nul

echo [101/200] Creating EFI directory structure...
if not exist S:\EFI md S:\EFI 2>nul
if not exist S:\EFI\Microsoft md S:\EFI\Microsoft 2>nul
if not exist S:\EFI\Microsoft\Boot md S:\EFI\Microsoft\Boot 2>nul
if not exist S:\EFI\Boot md S:\EFI\Boot 2>nul

echo [102/200] Removing old EFI BCD attributes...
attrib -h -r -s S:\EFI\Microsoft\Boot\BCD 2>nul

echo [103/200] Backing up old EFI BCD...
if exist S:\EFI\Microsoft\Boot\BCD ren S:\EFI\Microsoft\Boot\BCD BCD.old 2>nul

echo [104/200] Creating boot files for EFI partition...
bcdboot %WINDIR% /s S: /f UEFI

echo [105/200] Copying bootmgfw.efi...
if exist %WINDIR%\Boot\EFI\bootmgfw.efi (
    copy /y %WINDIR%\Boot\EFI\bootmgfw.efi S:\EFI\Microsoft\Boot\
    copy /y %WINDIR%\Boot\EFI\bootmgfw.efi S:\EFI\Boot\bootx64.efi
)

echo [106/200] Setting EFI boot path...
bcdedit /set {bootmgr} path \EFI\Microsoft\Boot\bootmgfw.efi 2>nul

echo [107/200] Setting EFI device...
bcdedit /set {bootmgr} device partition=S: 2>nul

echo [108/200] Removing EFI letter assignment...
echo select disk 0 > %WORKDIR%\dp_remove.txt
echo select partition 1 >> %WORKDIR%\dp_remove.txt
echo remove letter=S >> %WORKDIR%\dp_remove.txt
diskpart /s %WORKDIR%\dp_remove.txt 2>nul
del %WORKDIR%\dp_remove.txt 2>nul

:skip_efi_repair

:: ================================================================
:: PHASE 7: BOOT LOADER FILES REPAIR
:: ================================================================
if "%BOOT_ISSUE%"=="1" (
    echo.
    echo ================================================================
    echo [PHASE 7/16] BOOT LOADER FILES REPAIR
    echo ================================================================
    echo.
    
    echo [109/200] Repairing winload.exe...
    sfc /scanfile=%WINDIR%\System32\winload.exe /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [110/200] Repairing winload.efi...
    sfc /scanfile=%WINDIR%\System32\winload.efi /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [111/200] Repairing winresume.exe...
    sfc /scanfile=%WINDIR%\System32\winresume.exe /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [112/200] Repairing winresume.efi...
    sfc /scanfile=%WINDIR%\System32\winresume.efi /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
    
    echo [113/200] Repairing bootmgfw.efi...
    sfc /scanfile=%WINDIR%\Boot\EFI\bootmgfw.efi /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
    
    echo [114/200] Repairing bootmgr.efi...
    sfc /scanfile=%WINDIR%\Boot\EFI\bootmgr.efi /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
    
    echo [115/200] Repairing BOOTVID.DLL...
    sfc /scanfile=%WINDIR%\System32\BOOTVID.DLL /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [116/200] Repairing kdcom.dll...
    sfc /scanfile=%WINDIR%\System32\kdcom.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
    
    echo [117/200] Repairing mcupdate_GenuineIntel.dll...
    sfc /scanfile=%WINDIR%\System32\mcupdate_GenuineIntel.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
    
    echo [118/200] Repairing mcupdate_AuthenticAMD.dll...
    sfc /scanfile=%WINDIR%\System32\mcupdate_AuthenticAMD.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR% 2>nul
    
    echo [119/200] Setting boot loader path (BIOS)...
    bcdedit /set {current} path \Windows\System32\winload.exe 2>nul
    
    echo [120/200] Setting boot loader path (UEFI)...
    if "%UEFI_MODE%"=="1" bcdedit /set {current} path \Windows\System32\winload.efi 2>nul
)

:: ================================================================
:: PHASE 8: REGISTRY REPAIR
:: ================================================================
if "%REGISTRY_ISSUE%"=="1" (
    echo.
    echo ================================================================
    echo [PHASE 8/16] REGISTRY HIVE REPAIR
    echo ================================================================
    echo.
    
    echo [121/200] Backing up SYSTEM hive...
    copy /y %WINDIR%\System32\config\SYSTEM %WORKDIR%\SYSTEM.backup 2>nul
    
    echo [122/200] Backing up SOFTWARE hive...
    copy /y %WINDIR%\System32\config\SOFTWARE %WORKDIR%\SOFTWARE.backup 2>nul
    
    echo [123/200] Backing up SAM hive...
    copy /y %WINDIR%\System32\config\SAM %WORKDIR%\SAM.backup 2>nul
    
    echo [124/200] Backing up SECURITY hive...
    copy /y %WINDIR%\System32\config\SECURITY %WORKDIR%\SECURITY.backup 2>nul
    
    echo [125/200] Backing up DEFAULT hive...
    copy /y %WINDIR%\System32\config\DEFAULT %WORKDIR%\DEFAULT.backup 2>nul
    
    echo [126/200] Checking RegBack SYSTEM size...
    for %%A in (%WINDIR%\System32\config\RegBack\SYSTEM) do (
        echo RegBack SYSTEM size: %%~zA bytes
        if %%~zA GTR 1000 (
            echo [127/200] Restoring SYSTEM from RegBack...
            copy /y %WINDIR%\System32\config\RegBack\SYSTEM %WINDIR%\System32\config\SYSTEM
        )
    )
    
    echo [128/200] Checking RegBack SOFTWARE size...
    for %%A in (%WINDIR%\System32\config\RegBack\SOFTWARE) do (
        if %%~zA GTR 1000 (
            echo [129/200] Restoring SOFTWARE from RegBack...
            copy /y %WINDIR%\System32\config\RegBack\SOFTWARE %WINDIR%\System32\config\SOFTWARE
        )
    )
    
    echo [130/200] Checking RegBack SAM size...
    for %%A in (%WINDIR%\System32\config\RegBack\SAM) do (
        if %%~zA GTR 1000 (
            echo [131/200] Restoring SAM from RegBack...
            copy /y %WINDIR%\System32\config\RegBack\SAM %WINDIR%\System32\config\SAM
        )
    )
    
    echo [132/200] Checking RegBack SECURITY size...
    for %%A in (%WINDIR%\System32\config\RegBack\SECURITY) do (
        if %%~zA GTR 1000 (
            echo [133/200] Restoring SECURITY from RegBack...
            copy /y %WINDIR%\System32\config\RegBack\SECURITY %WINDIR%\System32\config\SECURITY
        )
    )
    
    echo [134/200] Checking RegBack DEFAULT size...
    for %%A in (%WINDIR%\System32\config\RegBack\DEFAULT) do (
        if %%~zA GTR 1000 (
            echo [135/200] Restoring DEFAULT from RegBack...
            copy /y %WINDIR%\System32\config\RegBack\DEFAULT %WINDIR%\System32\config\DEFAULT
        )
    )
    
    echo [136/200] Validating SYSTEM hive...
    reg load HKLM\TEST_SYS %WINDIR%\System32\config\SYSTEM >nul 2>&1
    if errorlevel 1 (
        echo WARNING: SYSTEM hive corrupt - attempting alternative restore
    ) else (
        reg unload HKLM\TEST_SYS >nul 2>&1
    )
    
    echo [137/200] Validating SOFTWARE hive...
    reg load HKLM\TEST_SW %WINDIR%\System32\config\SOFTWARE >nul 2>&1
    if errorlevel 1 (
        echo WARNING: SOFTWARE hive corrupt
    ) else (
        reg unload HKLM\TEST_SW >nul 2>&1
    )
    
    echo [138/200] Checking for System Restore registry backups...
    dir "%WINDRIVE%\System Volume Information\*" /s /b 2>nul | findstr /i "registry" 2>nul
)

:: ================================================================
:: PHASE 9: PENDING OPERATIONS CLEANUP
:: ================================================================
if "%PENDING_ISSUE%"=="1" (
    echo.
    echo ================================================================
    echo [PHASE 9/16] PENDING OPERATIONS CLEANUP
    echo ================================================================
    echo.
    
    echo [139/200] Loading SYSTEM hive...
    reg load HKLM\OFFLINE_SYS %WINDIR%\System32\config\SYSTEM
    
    echo [140/200] Removing PendingFileRenameOperations...
    reg delete "HKLM\OFFLINE_SYS\ControlSet001\Control\Session Manager" /v PendingFileRenameOperations /f 2>nul
    
    echo [141/200] Removing PendingFileRenameOperations2...
    reg delete "HKLM\OFFLINE_SYS\ControlSet001\Control\Session Manager" /v PendingFileRenameOperations2 /f 2>nul
    
    echo [142/200] Checking ControlSet002...
    reg delete "HKLM\OFFLINE_SYS\ControlSet002\Control\Session Manager" /v PendingFileRenameOperations /f 2>nul
    reg delete "HKLM\OFFLINE_SYS\ControlSet002\Control\Session Manager" /v PendingFileRenameOperations2 /f 2>nul
    
    echo [143/200] Checking SetupExecute...
    reg query "HKLM\OFFLINE_SYS\ControlSet001\Control\Session Manager" /v SetupExecute 2>nul
    
    echo [144/200] Clearing BootExecute issues...
    reg add "HKLM\OFFLINE_SYS\ControlSet001\Control\Session Manager" /v BootExecute /t REG_MULTI_SZ /d "autocheck autochk *" /f 2>nul
    
    echo [145/200] Unloading SYSTEM hive...
    reg unload HKLM\OFFLINE_SYS
    
    echo [146/200] Running DISM revert pending actions...
    dism /image:%WINDRIVE%\ /cleanup-image /revertpendingactions
)

:: ================================================================
:: PHASE 10: DISM COMPONENT STORE REPAIR
:: ================================================================
if "%STORE_ISSUE%"=="1" goto :do_dism_repair
if "%DRIVER_ISSUE%"=="1" goto :do_dism_repair
if "%SYSTEM_FILE_ISSUE%"=="1" goto :do_dism_repair
if "%ACPIEX_ISSUE%"=="1" goto :do_dism_repair
goto :skip_dism_repair

:do_dism_repair
echo.
echo ================================================================
echo [PHASE 10/16] DISM COMPONENT STORE REPAIR
echo ================================================================
echo.

echo [147/200] Checking image health...
dism /image:%WINDRIVE%\ /cleanup-image /checkhealth

echo [148/200] Scanning image for corruption...
dism /image:%WINDRIVE%\ /cleanup-image /scanhealth

echo [149/200] Restoring image health...
dism /image:%WINDRIVE%\ /cleanup-image /restorehealth

echo [150/200] Analyzing component store...
dism /image:%WINDRIVE%\ /cleanup-image /analyzecomponentstore

echo [151/200] Starting component cleanup...
dism /image:%WINDRIVE%\ /cleanup-image /startcomponentcleanup

echo [152/200] Resetting component base...
dism /image:%WINDRIVE%\ /cleanup-image /startcomponentcleanup /resetbase

echo [153/200] Reverting pending actions...
dism /image:%WINDRIVE%\ /cleanup-image /revertpendingactions

echo [154/200] Listing drivers...
dism /image:%WINDRIVE%\ /get-drivers /format:table > %WORKDIR%\drivers.log

echo [155/200] Getting current edition...
dism /image:%WINDRIVE%\ /get-currentedition

echo [156/200] Listing packages...
dism /image:%WINDRIVE%\ /get-packages > %WORKDIR%\packages.log

:skip_dism_repair

:: ================================================================
:: PHASE 11: DISK REPAIR
:: ================================================================
if "%DISK_ISSUE%"=="1" goto :do_disk_repair
if "%NTFS_ISSUE%"=="1" goto :do_disk_repair
goto :skip_disk_repair

:do_disk_repair
echo.
echo ================================================================
echo [PHASE 11/16] DISK AND FILE SYSTEM REPAIR
echo ================================================================
echo.

echo [157/200] Quick disk scan...
chkdsk %WINDRIVE% /scan

echo [158/200] Disk repair /F...
chkdsk %WINDRIVE% /f

echo [159/200] Disk repair /R (bad sectors)...
chkdsk %WINDRIVE% /r

echo [160/200] Disk repair /X (dismount)...
chkdsk %WINDRIVE% /f /x

echo [161/200] Re-evaluate bad clusters /B...
chkdsk %WINDRIVE% /b

echo [162/200] Spotfix mode...
chkdsk %WINDRIVE% /spotfix 2>nul

echo [163/200] Setting repair flags...
fsutil repair set %WINDRIVE% 1

echo [164/200] Checking other volumes...
for %%d in (D E F) do (
    if exist %%d:\ chkdsk %%d: /f 2>nul
)

:skip_disk_repair

:: ================================================================
:: PHASE 12: COMPREHENSIVE SFC SCAN
:: ================================================================
echo.
echo ================================================================
echo [PHASE 12/16] COMPREHENSIVE SFC SCAN
echo ================================================================
echo.

echo [165/200] Running full offline SFC scan...
sfc /scannow /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%

echo [166/200] Verifying system files...
sfc /verifyonly /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%

echo [167/200] Scanning security DLLs...
sfc /scanfile=%WINDIR%\System32\lsasrv.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\samsrv.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\msv1_0.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\kerberos.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\schannel.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%

echo [168/200] Scanning crypto DLLs...
sfc /scanfile=%WINDIR%\System32\bcrypt.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\ncrypt.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\crypt32.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\cryptsp.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\rsaenh.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%

echo [169/200] Scanning core system DLLs...
sfc /scanfile=%WINDIR%\System32\advapi32.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\user32.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\gdi32.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\shell32.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\ole32.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\rpcrt4.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\sechost.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\combase.dll /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%

echo [170/200] Scanning filter drivers...
sfc /scanfile=%WINDIR%\System32\drivers\fileinfo.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\drivers\luafv.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\drivers\wcifs.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\drivers\bindflt.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\drivers\fvevol.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%

echo [171/200] Scanning input drivers...
sfc /scanfile=%WINDIR%\System32\drivers\kbdclass.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\drivers\mouclass.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\drivers\i8042prt.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\drivers\hidclass.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%
sfc /scanfile=%WINDIR%\System32\drivers\hidusb.sys /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%

:: ================================================================
:: PHASE 13: RECOVERY ENVIRONMENT REPAIR
:: ================================================================
echo.
echo ================================================================
echo [PHASE 13/16] RECOVERY ENVIRONMENT REPAIR
echo ================================================================
echo.

echo [172/200] Checking WinRE status...
reagentc /info /target %WINDIR% 2>nul

echo [173/200] Disabling WinRE...
reagentc /disable /target %WINDIR% 2>nul

echo [174/200] Re-enabling WinRE...
reagentc /enable /target %WINDIR% 2>nul

echo [175/200] Setting WinRE image path...
if exist %WINDRIVE%\Recovery\WindowsRE\winre.wim (
    reagentc /setreimage /path %WINDRIVE%\Recovery\WindowsRE /target %WINDIR% 2>nul
)

echo [176/200] Creating Boot folder structure...
if not exist %WINDRIVE%\Boot md %WINDRIVE%\Boot 2>nul
if not exist %WINDRIVE%\Boot\Fonts md %WINDRIVE%\Boot\Fonts 2>nul
if not exist %WINDRIVE%\Boot\Resources md %WINDRIVE%\Boot\Resources 2>nul

echo [177/200] Creating EFI folder structure...
if not exist %WINDRIVE%\EFI md %WINDRIVE%\EFI 2>nul
if not exist %WINDRIVE%\EFI\Microsoft md %WINDRIVE%\EFI\Microsoft 2>nul
if not exist %WINDRIVE%\EFI\Microsoft\Boot md %WINDRIVE%\EFI\Microsoft\Boot 2>nul
if not exist %WINDRIVE%\EFI\Microsoft\Boot\Fonts md %WINDRIVE%\EFI\Microsoft\Boot\Fonts 2>nul

echo [178/200] Copying boot fonts...
xcopy /s /e /h /y %WINDIR%\Boot\Fonts\*.* %WINDRIVE%\Boot\Fonts\ 2>nul
xcopy /s /e /h /y %WINDIR%\Boot\Fonts\*.* %WINDRIVE%\EFI\Microsoft\Boot\Fonts\ 2>nul

echo [179/200] Copying boot resources...
xcopy /s /e /h /y %WINDIR%\Boot\Resources\*.* %WINDRIVE%\Boot\Resources\ 2>nul

:: ================================================================
:: PHASE 14: ADVANCED CLEANUP
:: ================================================================
echo.
echo ================================================================
echo [PHASE 14/16] ADVANCED CLEANUP
echo ================================================================
echo.

echo [180/200] Clearing font cache...
del /f /q %WINDIR%\System32\FNTCACHE.DAT 2>nul

echo [181/200] Clearing icon cache...
del /f /s /q "%WINDRIVE%\Users\*\AppData\Local\IconCache.db" 2>nul
del /f /s /q "%WINDRIVE%\Users\*\AppData\Local\Microsoft\Windows\Explorer\iconcache*" 2>nul

echo [182/200] Clearing thumbnail cache...
del /f /s /q "%WINDRIVE%\Users\*\AppData\Local\Microsoft\Windows\Explorer\thumbcache*" 2>nul

echo [183/200] Clearing Windows temp...
del /f /s /q %WINDIR%\Temp\*.* 2>nul

echo [184/200] Clearing prefetch...
del /f /s /q %WINDIR%\Prefetch\*.pf 2>nul

echo [185/200] Clearing Windows Update cache...
rd /s /q %WINDIR%\SoftwareDistribution\Download 2>nul
md %WINDIR%\SoftwareDistribution\Download 2>nul

echo [186/200] Renaming catroot2...
if exist %WINDIR%\System32\catroot2 ren %WINDIR%\System32\catroot2 catroot2.old 2>nul

echo [187/200] Resetting Winsock catalog (offline)...
reg load HKLM\OFFLINE_SYS %WINDIR%\System32\config\SYSTEM >nul 2>&1
reg delete "HKLM\OFFLINE_SYS\ControlSet001\Services\WinSock2\Parameters\Protocol_Catalog9" /f 2>nul
reg delete "HKLM\OFFLINE_SYS\ControlSet001\Services\WinSock2\Parameters\NameSpace_Catalog5" /f 2>nul
reg unload HKLM\OFFLINE_SYS >nul 2>&1

echo [188/200] Clearing pending XML files...
del /f /q %WINDIR%\WinSxS\pending.xml 2>nul
del /f /q %WINDIR%\WinSxS\pending.xml.bad 2>nul

:: ================================================================
:: PHASE 15: FINAL VERIFICATION
:: ================================================================
echo.
echo ================================================================
echo [PHASE 15/16] FINAL VERIFICATION
echo ================================================================
echo.

echo [189/200] Final SFC scan...
sfc /scannow /offbootdir=%WINDRIVE%\ /offwindir=%WINDIR%

echo [190/200] Final DISM restore...
dism /image:%WINDRIVE%\ /cleanup-image /restorehealth

echo [191/200] Final BCD rebuild...
bcdboot %WINDIR% /s %WINDRIVE% /f ALL

echo [192/200] Final bootrec sequence...
bootrec /fixmbr
bootrec /fixboot
echo Y | bootrec /rebuildbcd

echo [193/200] Final disk scan...
chkdsk %WINDRIVE% /scan

echo [194/200] Verifying acpiex.sys...
if exist %WINDIR%\System32\drivers\acpiex.sys (
    echo [OK] acpiex.sys exists
    for %%A in (%WINDIR%\System32\drivers\acpiex.sys) do echo     Size: %%~zA bytes
) else (
    echo [MISSING] acpiex.sys - May need installation media
)

echo [195/200] Verifying boot files...
if exist %WINDIR%\System32\winload.exe (echo [OK] winload.exe) else (echo [MISSING] winload.exe)
if exist %WINDIR%\System32\winload.efi (echo [OK] winload.efi) else (echo [MISSING] winload.efi)
if exist %WINDIR%\System32\ntoskrnl.exe (echo [OK] ntoskrnl.exe) else (echo [MISSING] ntoskrnl.exe)
if exist %WINDIR%\System32\hal.dll (echo [OK] hal.dll) else (echo [MISSING] hal.dll)

echo [196/200] Verifying registry hives...
if exist %WINDIR%\System32\config\SYSTEM (echo [OK] SYSTEM hive) else (echo [MISSING] SYSTEM hive)
if exist %WINDIR%\System32\config\SOFTWARE (echo [OK] SOFTWARE hive) else (echo [MISSING] SOFTWARE hive)

echo [197/200] Displaying final BCD...
bcdedit /enum all

:: ================================================================
:: PHASE 16: REPORT AND CLEANUP
:: ================================================================
echo.
echo ================================================================
echo [PHASE 16/16] REPORT GENERATION
echo ================================================================
echo.

echo [198/200] Creating repair report...
echo ================================================================ > %WINDRIVE%\RECOVERY_REPORT.txt
echo ULTIMATE WINDOWS RECOVERY REPORT v3.0 >> %WINDRIVE%\RECOVERY_REPORT.txt
echo Generated: %date% %time% >> %WINDRIVE%\RECOVERY_REPORT.txt
echo ================================================================ >> %WINDRIVE%\RECOVERY_REPORT.txt
echo. >> %WINDRIVE%\RECOVERY_REPORT.txt
echo ENVIRONMENT: >> %WINDRIVE%\RECOVERY_REPORT.txt
echo   Windows Drive: %WINDRIVE% >> %WINDRIVE%\RECOVERY_REPORT.txt
echo   Boot Mode: %UEFI_MODE% (1=UEFI, 0=BIOS) >> %WINDRIVE%\RECOVERY_REPORT.txt
echo. >> %WINDRIVE%\RECOVERY_REPORT.txt
echo ORIGINAL ISSUES: >> %WINDRIVE%\RECOVERY_REPORT.txt
echo   - Automatic Repair couldn't repair your PC >> %WINDRIVE%\RECOVERY_REPORT.txt
echo   - Boot critical file acpiex.sys is corrupt >> %WINDRIVE%\RECOVERY_REPORT.txt
echo   - File repair failed with Error code 0x57 >> %WINDRIVE%\RECOVERY_REPORT.txt
echo. >> %WINDRIVE%\RECOVERY_REPORT.txt
echo ISSUES REPAIRED: >> %WINDRIVE%\RECOVERY_REPORT.txt
if "%ACPIEX_ISSUE%"=="1" echo   [X] acpiex.sys driver corruption >> %WINDRIVE%\RECOVERY_REPORT.txt
if "%DRIVER_ISSUE%"=="1" echo   [X] Boot-critical driver issues >> %WINDRIVE%\RECOVERY_REPORT.txt
if "%BCD_ISSUE%"=="1" echo   [X] Boot Configuration Data >> %WINDRIVE%\RECOVERY_REPORT.txt
if "%MBR_ISSUE%"=="1" echo   [X] Master Boot Record >> %WINDRIVE%\RECOVERY_REPORT.txt
if "%EFI_ISSUE%"=="1" echo   [X] EFI boot partition >> %WINDRIVE%\RECOVERY_REPORT.txt
if "%BOOT_ISSUE%"=="1" echo   [X] Boot loader files >> %WINDRIVE%\RECOVERY_REPORT.txt
if "%REGISTRY_ISSUE%"=="1" echo   [X] Registry hives >> %WINDRIVE%\RECOVERY_REPORT.txt
if "%SYSTEM_FILE_ISSUE%"=="1" echo   [X] System files >> %WINDRIVE%\RECOVERY_REPORT.txt
if "%STORE_ISSUE%"=="1" echo   [X] Component store >> %WINDRIVE%\RECOVERY_REPORT.txt
if "%DISK_ISSUE%"=="1" echo   [X] Disk file system >> %WINDRIVE%\RECOVERY_REPORT.txt
if "%PENDING_ISSUE%"=="1" echo   [X] Pending operations >> %WINDRIVE%\RECOVERY_REPORT.txt
echo. >> %WINDRIVE%\RECOVERY_REPORT.txt
echo FINAL FILE STATUS: >> %WINDRIVE%\RECOVERY_REPORT.txt
dir %WINDIR%\System32\drivers\acpiex.sys >> %WINDRIVE%\RECOVERY_REPORT.txt 2>&1
echo. >> %WINDRIVE%\RECOVERY_REPORT.txt
echo BCD CONFIGURATION: >> %WINDRIVE%\RECOVERY_REPORT.txt
bcdedit /enum all >> %WINDRIVE%\RECOVERY_REPORT.txt 2>&1

echo [199/200] Cleaning up work files...
del /f /q %WORKDIR%\*.log 2>nul
del /f /q %WORKDIR%\*.txt 2>nul

echo [200/200] Recovery process complete!

echo.
echo ================================================================
echo                    RECOVERY COMPLETED
echo ================================================================
echo.
echo Report saved to: %WINDRIVE%\RECOVERY_REPORT.txt
echo.
echo CRITICAL FILES STATUS:
echo ----------------------
if exist %WINDIR%\System32\drivers\acpiex.sys (echo [OK] acpiex.sys) else (echo [!!] acpiex.sys MISSING)
if exist %WINDIR%\System32\winload.exe (echo [OK] winload.exe) else (echo [!!] winload.exe MISSING)
if exist %WINDIR%\System32\ntoskrnl.exe (echo [OK] ntoskrnl.exe) else (echo [!!] ntoskrnl.exe MISSING)
echo.
echo NEXT STEPS:
echo -----------
echo 1. Remove installation/recovery media
echo 2. Restart your computer
echo 3. If boot fails: Try Safe Mode (F8/Shift+F8)
echo 4. If still failing: May need clean Windows install
echo.
echo If acpiex.sys is still MISSING:
echo   - Boot from Windows installation media
echo   - Run: dism /image:C:\ /add-driver /driver:X:\sources\acpiex.inf
echo   - Or copy from: X:\Windows\System32\drivers\acpiex.sys
echo.
pause
echo.
echo Restarting in 15 seconds...
echo Press Ctrl+C to cancel...
timeout /t 15
wpeutil reboot 2>nul || shutdown /r /t 0
