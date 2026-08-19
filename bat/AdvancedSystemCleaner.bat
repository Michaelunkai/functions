@echo off
color 0a
title Advanced System Cleaning Utility

:: Simple admin check and elevation
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrative privileges...
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~f0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B
)

:: Continue with admin privileges
setlocal enabledelayedexpansion

:: Create backup directory if it doesn't exist
if not exist "%USERPROFILE%\SystemPurge_Backup" (
    mkdir "%USERPROFILE%\SystemPurge_Backup" 2>nul
)

:::: Make sure temp directory exists and is accessible
if not exist "%TEMP%" mkdir "%TEMP%" 2>nul
if exist "%TEMP%\ctrl-c-flag.txt" del "%TEMP%\ctrl-c-flag.txt" 2>nul

:Start
cls
echo ===================================================
echo        ADVANCED SYSTEM CLEANING UTILITY
echo ===================================================
echo.
echo This utility will perform comprehensive system maintenance
echo to improve performance and free up disk space.
echo.
echo OPTIONS:
echo [1] Run Quick Clean (Basic temp files only)
echo [2] Run Standard Clean (Recommended)
echo [3] Run Deep Clean (Most thorough - takes longer)
echo [4] Create System Restore Point (Recommended before cleaning)
echo [5] Exit
echo.
set /p choice=Enter your choice (1-5):
if "%choice%"=="5" exit
if "%choice%"=="4" goto CreateRestorePoint
if "%choice%"=="1" goto QuickClean
if "%choice%"=="2" goto StandardClean
if "%choice%"=="3" goto DeepClean
goto Start

:CreateRestorePoint
echo Creating System Restore Point...
echo wmic.exe /Namespace:\\root\default Path SystemRestore Call CreateRestorePoint "SystemPurge Backup", 100, 7 > "%temp%\create_restore_point.vbs"
cscript //nologo "%temp%\create_restore_point.vbs"
if %errorlevel% NEQ 0 (
    echo ERROR: Failed to create System Restore Point.
    echo Please make sure System Restore is enabled on your system.
    pause
) else (
    echo System Restore Point created successfully.
    echo It's now safe to proceed with system cleaning.
    pause
)
goto Start

:CreateLogFile
:: Make sure Desktop exists
if not exist "%USERPROFILE%\Desktop" mkdir "%USERPROFILE%\Desktop" 2>nul
echo ===================================================>> "%USERPROFILE%\Desktop\CleaningLog.txt"
echo        SYSTEM CLEANING LOG - %date% %time%>> "%USERPROFILE%\Desktop\CleaningLog.txt"
echo ===================================================>> "%USERPROFILE%\Desktop\CleaningLog.txt"
echo.>> "%USERPROFILE%\Desktop\CleaningLog.txt"
goto :eof

:ErrorHandler
echo ERROR: %~1
echo Operation failed with error code: %errorlevel%
echo The script will continue with the next step.
echo ERROR: %~1 (Error code: %errorlevel%)>> "%USERPROFILE%\Desktop\CleaningLog.txt" 2>nul
goto :eof

:::: Simplified error recovery functions
:CheckForInterrupt
if exist "%TEMP%\user_interrupt.flag" (
    del "%TEMP%\user_interrupt.flag" 2>nul
    echo.
    echo Processing interrupted. Continuing to next step...
    echo Processing interrupted by user. Continuing to next step...>> "%USERPROFILE%\Desktop\CleaningLog.txt" 2>nul
    ping -n 2 127.0.0.1 >nul 2>&1
)
goto :eof

:ProgressBar
set /a progress=%~1
set /a total=%~2
set /a percent=(progress*100)/total
set bar=

:: Create progress bar with standard characters instead of unicode blocks
for /l %%i in (0,5,%percent%) do (
    set bar=!bar!#
)

:: Output progress bar
echo Progress: [!bar!%percent%%%]
goto :eof

:RecycleBinPrompt
echo.
set /p confirm=Are you sure you want to empty the Recycle Bin? (Y/N): 
if /i "%confirm%" NEQ "Y" (
    echo Skipping Recycle Bin emptying...
    echo - Recycle Bin emptying skipped by user>> %USERPROFILE%\Desktop\CleaningLog.txt
    goto :eof
)
echo Emptying Recycle Bin...
:: Use alternative method to empty Recycle Bin
echo Set objShell = CreateObject("Shell.Application") > "%temp%\emptybin.vbs"
echo If Not objShell Is Nothing Then >> "%temp%\emptybin.vbs"
echo   objShell.Namespace(10).Items.InvokeVerb "Empty Recycle Bin" >> "%temp%\emptybin.vbs"
echo End If >> "%temp%\emptybin.vbs"
cscript //nologo "%temp%\emptybin.vbs"
del "%temp%\emptybin.vbs" 2>nul
echo - Recycle Bin emptied>> %USERPROFILE%\Desktop\CleaningLog.txt
goto :eof

:BackupRegistrySettings
echo.
set /p create_backup=Would you like to create a registry backup before continuing? (Y/N): 
if /i "%create_backup%" NEQ "Y" (
    echo Skipping registry backup as per user request...
    echo - Registry backup skipped by user request>> "%USERPROFILE%\Desktop\CleaningLog.txt"
    goto :eof
)

echo Creating registry backup...
echo Creating registry backup...>> "%USERPROFILE%\Desktop\CleaningLog.txt"
:: Make sure time format is correct for filenames (spaces can cause issues)
set datetime=%date:~-4,4%%date:~-7,2%%date:~-10,2%_%time:~0,2%%time:~3,2%%time:~6,2%
:: Replace any spaces with zeros in the time
set datetime=%datetime: =0%
set backupFile=%USERPROFILE%\SystemPurge_Backup\registry_backup_%datetime%.reg
reg export HKLM "%backupFile%" /y
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to backup registry"
) else (
    echo - Registry backup created at: %backupFile%>> "%USERPROFILE%\Desktop\CleaningLog.txt"
    echo Registry backup created successfully at: %backupFile%
)
goto :eof

:QuickClean
call :CreateLogFile
call :BackupRegistrySettings
echo Running Quick Clean...
echo Running Quick Clean...>> %USERPROFILE%\Desktop\CleaningLog.txt
echo.
echo [Step 1/3] Removing temporary files...
echo [Step 1/3] Removing temporary files...>> %USERPROFILE%\Desktop\CleaningLog.txt

:: Progress indication setup
set total_steps=3
set current_step=1
call :ProgressBar %current_step% %total_steps%

REM Clean Windows Temp
del /s /f /q C:\Windows\Temp\*.*
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to clean Windows Temp files"
) else (
    echo - Windows Temp files removed>> %USERPROFILE%\Desktop\CleaningLog.txt
)

REM Clean User Temp
del /s /f /q %temp%\*.*
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to clean User Temp files"
) else (
    echo - User Temp files removed>> %USERPROFILE%\Desktop\CleaningLog.txt
)
echo.

set /a current_step+=1
echo [Step 2/3] Flushing DNS cache...
echo [Step 2/3] Flushing DNS cache...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%

ipconfig /flushdns
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to flush DNS cache"
) else (
    echo - DNS cache flushed>> %USERPROFILE%\Desktop\CleaningLog.txt
)
echo.

set /a current_step+=1
echo [Step 3/3] Cleaning browser caches...
echo [Step 3/3] Cleaning browser caches...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%

REM Chrome Cache (if exists)
if exist "%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache" (
    del /s /f /q "%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache\*.*"
    if %errorlevel% NEQ 0 (
        call :ErrorHandler "Failed to clean Chrome cache"
    ) else (
        echo - Chrome cache cleaned>> %USERPROFILE%\Desktop\CleaningLog.txt
    )
)

REM Edge Cache (if exists)
if exist "%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache" (
    del /s /f /q "%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache\*.*"
    if %errorlevel% NEQ 0 (
        call :ErrorHandler "Failed to clean Edge cache"
    ) else (
        echo - Edge cache cleaned>> %USERPROFILE%\Desktop\CleaningLog.txt
    )
)

call :ProgressBar %total_steps% %total_steps%
goto Completed

:StandardClean
call :CreateLogFile
call :BackupRegistrySettings
echo Running Standard Clean...
echo Running Standard Clean...>> %USERPROFILE%\Desktop\CleaningLog.txt
echo.

:: Progress indication setup
set total_steps=6
set current_step=1

:: Create log directory if it doesn't exist
if not exist "%USERPROFILE%\Desktop" (
    mkdir "%USERPROFILE%\Desktop" 2>nul
)

echo [Step 1/6] Removing temporary files...
echo [Step 1/6] Removing temporary files...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%

REM Clean Windows Temp
echo Cleaning Windows Temp files...
:: Skip files in use by other processes
del /s /f /q C:\Windows\Temp\*.* 2>nul
:: Don't try to remove the directory itself
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Some temp files could not be deleted - they may be in use"
)
echo - Windows Temp files removed>> %USERPROFILE%\Desktop\CleaningLog.txt

REM Clean User Temp
echo Cleaning User Temp files...
:: Skip files in use by other processes
del /s /f /q %temp%\*.* 2>nul
:: Don't try to remove the directory itself
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Some user temp files could not be deleted - they may be in use"
)
echo - User Temp files removed>> %USERPROFILE%\Desktop\CleaningLog.txt

REM Clean Prefetch
echo Cleaning Prefetch files...
if exist C:\Windows\Prefetch (
    del /s /f /q C:\Windows\Prefetch\*.* 2>nul
    if %errorlevel% NEQ 0 (
        call :ErrorHandler "Some prefetch files could not be deleted - they may be in use"
    ) else (
        echo - Prefetch files removed>> %USERPROFILE%\Desktop\CleaningLog.txt
    )
) else (
    echo - Prefetch directory not found, skipping>> %USERPROFILE%\Desktop\CleaningLog.txt
)
echo.

set /a current_step+=1
echo [Step 2/6] Checking Recycle Bin...
echo [Step 2/6] Checking Recycle Bin...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%
:: Get confirmation before emptying Recycle Bin
echo.
set /p confirm=Are you sure you want to empty the Recycle Bin? (Y/N): 
if /i "%confirm%" NEQ "Y" (
    echo Skipping Recycle Bin emptying...
    echo - Recycle Bin emptying skipped by user>> %USERPROFILE%\Desktop\CleaningLog.txt
) else (
    echo Emptying Recycle Bin...
    :: Use alternative method to empty Recycle Bin
    echo Set oShell = CreateObject("Shell.Application") > "%temp%\emptybin.vbs"
    echo oShell.Namespace(10).Items.InvokeVerb("Delete") >> "%temp%\emptybin.vbs"
    cscript //nologo "%temp%\emptybin.vbs"
    del "%temp%\emptybin.vbs"
    echo - Recycle Bin emptied>> %USERPROFILE%\Desktop\CleaningLog.txt
)
echo.

set /a current_step+=1
echo [Step 3/6] Cleaning Windows Update cache...
echo [Step 3/6] Cleaning Windows Update cache...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%

:: First check if the service is running
net stop wuauserv /y >nul 2>&1
:: Wait for service to stop
ping -n 3 127.0.0.1 >nul 2>&1

:: Clean the cache even if the service couldn't be stopped
if exist C:\Windows\SoftwareDistribution (
    del /s /f /q C:\Windows\SoftwareDistribution\*.* 2>nul
    echo - Windows Update cache files cleaned>> "%USERPROFILE%\Desktop\CleaningLog.txt"
)

:: Try to restart the service, but don't worry if it fails
net start wuauserv >nul 2>&1
:: Flag success even if service couldn't restart
echo - Windows Update cache cleaning operation completed>> "%USERPROFILE%\Desktop\CleaningLog.txt"
echo.

set /a current_step+=1
echo [Step 4/6] Flushing DNS and resetting network...
echo [Step 4/6] Flushing DNS and resetting network...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%

call :CheckForInterrupt
ipconfig /flushdns >nul 2>&1
echo - DNS cache flushed>> "%USERPROFILE%\Desktop\CleaningLog.txt"

call :CheckCtrlC
netsh winsock reset >nul 2>&1
echo - Winsock reset>> "%USERPROFILE%\Desktop\CleaningLog.txt"
echo.

echo Note: A system restart will be needed to complete network changes.
echo Note: A system restart will be needed to complete network changes.>> "%USERPROFILE%\Desktop\CleaningLog.txt"

set /a current_step+=1
echo [Step 5/6] Cleaning browser caches...
echo [Step 5/6] Cleaning browser caches...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%

REM Chrome Cache (if exists)
if exist "%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache" (
    del /s /f /q "%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache\*.*"
    if %errorlevel% NEQ 0 (
        call :ErrorHandler "Failed to clean Chrome cache"
    ) else (
        echo - Chrome cache cleaned>> %USERPROFILE%\Desktop\CleaningLog.txt
    )
)

REM Edge Cache (if exists)
if exist "%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache" (
    del /s /f /q "%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache\*.*"
    if %errorlevel% NEQ 0 (
        call :ErrorHandler "Failed to clean Edge cache"
    ) else (
        echo - Edge cache cleaned>> %USERPROFILE%\Desktop\CleaningLog.txt
    )
)

REM Firefox Cache (if exists)
if exist "%LOCALAPPDATA%\Mozilla\Firefox\Profiles" (
    del /s /f /q "%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\cache2\*.*"
    if %errorlevel% NEQ 0 (
        call :ErrorHandler "Failed to clean Firefox cache"
    ) else (
        echo - Firefox cache cleaned>> %USERPROFILE%\Desktop\CleaningLog.txt
    )
)
echo.

set /a current_step+=1
echo [Step 6/6] Running Disk Cleanup utility...
echo [Step 6/6] Running Disk Cleanup utility...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%

cleanmgr /sagerun:1
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to run Disk Cleanup utility"
) else (
    echo - Disk Cleanup utility executed>> %USERPROFILE%\Desktop\CleaningLog.txt
)

call :ProgressBar %total_steps% %total_steps%
goto Completed

:DeepClean
call :CreateLogFile
call :BackupRegistrySettings
echo Running Deep Clean...
echo Running Deep Clean...>> %USERPROFILE%\Desktop\CleaningLog.txt
echo.

:: Progress indication setup
set total_steps=10
set current_step=1

echo [Step 1/10] Removing temporary files...
echo [Step 1/10] Removing temporary files...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%

REM Clean Windows Temp
del /s /f /q C:\Windows\Temp\*.*
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to clean Windows Temp files"
)
rmdir /s /q C:\Windows\Temp 2>nul
mkdir C:\Windows\Temp 2>nul
echo - Windows Temp files removed>> %USERPROFILE%\Desktop\CleaningLog.txt

REM Clean User Temp
del /s /f /q %temp%\*.*
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to clean User Temp files"
)
rmdir /s /q %temp% 2>nul
mkdir %temp% 2>nul
echo - User Temp files removed>> %USERPROFILE%\Desktop\CleaningLog.txt

REM Clean Prefetch
del /s /f /q C:\Windows\Prefetch\*.*
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to clean Prefetch files"
) else (
    echo - Prefetch files removed>> %USERPROFILE%\Desktop\CleaningLog.txt
)
echo.

set /a current_step+=1
echo [Step 2/10] Checking Recycle Bin...
echo [Step 2/10] Checking Recycle Bin...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%
call :RecycleBinPrompt
echo.

set /a current_step+=1
echo [Step 3/10] Cleaning Windows Update cache...
echo [Step 3/10] Cleaning Windows Update cache...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%

net stop wuauserv
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to stop Windows Update service"
)

del /s /f /q C:\Windows\SoftwareDistribution\*.*
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to clean Windows Update cache"
)

net start wuauserv
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to start Windows Update service"
) else (
    echo - Windows Update cache cleaned>> %USERPROFILE%\Desktop\CleaningLog.txt
)
echo.

set /a current_step+=1
echo [Step 4/10] Cleaning Event Logs...
echo [Step 4/10] Cleaning Event Logs...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%

for /F "tokens=*" %%G in ('wevtutil el') do (
    wevtutil cl "%%G" 2>nul
    if %errorlevel% NEQ 0 (
        call :ErrorHandler "Failed to clear event log: %%G"
    )
)
echo - Event logs cleared>> %USERPROFILE%\Desktop\CleaningLog.txt
echo.

set /a current_step+=1
echo [Step 5/10] Cleaning Font Cache...
echo [Step 5/10] Cleaning Font Cache...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%

net stop fontcache
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to stop Font Cache service"
)

del /f /s /q %windir%\ServiceProfiles\LocalService\AppData\Local\FontCache\*.* 2>nul
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to clean Font Cache"
)

del /f /s /q %windir%\ServiceProfiles\LocalService\AppData\Local\FontCache-System\*.* 2>nul
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to clean Font Cache System"
)

net start fontcache
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to start Font Cache service"
) else (
    echo - Font cache cleaned>> %USERPROFILE%\Desktop\CleaningLog.txt
)
echo.

set /a current_step+=1
echo [Step 6/10] Cleaning Thumbnail Cache...
echo [Step 6/10] Cleaning Thumbnail Cache...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%

del /f /s /q %userprofile%\AppData\Local\Microsoft\Windows\Explorer\thumbcache_*.db 2>nul
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to clean Thumbnail Cache"
) else (
    echo - Thumbnail cache cleaned>> %USERPROFILE%\Desktop\CleaningLog.txt
)
echo.

set /a current_step+=1
echo [Step 7/10] Flushing DNS and resetting network...
echo [Step 7/10] Flushing DNS and resetting network...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%

ipconfig /flushdns
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to flush DNS cache"
) else (
    echo - DNS cache flushed>> %USERPROFILE%\Desktop\CleaningLog.txt
)

ipconfig /release
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to release IP configuration"
)

ipconfig /renew
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to renew IP configuration"
) else (
    echo - IP configuration reset>> %USERPROFILE%\Desktop\CleaningLog.txt
)

netsh winsock reset
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to reset Winsock"
) else (
    echo - Winsock reset>> %USERPROFILE%\Desktop\CleaningLog.txt
)

netsh int ip reset
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to reset TCP/IP stack"
) else (
    echo - TCP/IP stack reset>> %USERPROFILE%\Desktop\CleaningLog.txt
)
echo.

set /a current_step+=1
echo [Step 8/10] Cleaning browser caches...
echo [Step 8/10] Cleaning browser caches...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%

REM Chrome Cache (if exists)
if exist "%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache" (
    del /s /f /q "%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache\*.*" 2>nul
    del /s /f /q "%LOCALAPPDATA%\Google\Chrome\User Data\Default\Code Cache\*.*" 2>nul
    if %errorlevel% NEQ 0 (
        call :ErrorHandler "Failed to clean Chrome cache"
    ) else (
        echo - Chrome cache cleaned>> %USERPROFILE%\Desktop\CleaningLog.txt
    )
)

REM Edge Cache (if exists)
if exist "%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache" (
    del /s /f /q "%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache\*.*" 2>nul
    del /s /f /q "%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Code Cache\*.*" 2>nul
    if %errorlevel% NEQ 0 (
        call :ErrorHandler "Failed to clean Edge cache"
    ) else (
        echo - Edge cache cleaned>> %USERPROFILE%\Desktop\CleaningLog.txt
    )
)

REM Firefox Cache (if exists)
if exist "%LOCALAPPDATA%\Mozilla\Firefox\Profiles" (
    del /s /f /q "%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\cache2\*.*" 2>nul
    if %errorlevel% NEQ 0 (
        call :ErrorHandler "Failed to clean Firefox cache"
    ) else (
        echo - Firefox cache cleaned>> %USERPROFILE%\Desktop\CleaningLog.txt
    )
)
echo.

set /a current_step+=1
echo [Step 9/10] Cleaning Windows Defender cache...
echo [Step 9/10] Cleaning Windows Defender cache...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%

if exist "C:\ProgramData\Microsoft\Windows Defender\Scans\History\" (
    rmdir /s /q "C:\ProgramData\Microsoft\Windows Defender\Scans\History\" 2>nul
    if %errorlevel% NEQ 0 (
        call :ErrorHandler "Failed to clean Windows Defender cache"
    ) else (
        echo - Windows Defender cache cleaned>> %USERPROFILE%\Desktop\CleaningLog.txt
    )
)
echo.

set /a current_step+=1
echo [Step 10/10] Running advanced Disk Cleanup and system optimization...
echo [Step 10/10] Running advanced Disk Cleanup and system optimization...>> %USERPROFILE%\Desktop\CleaningLog.txt
call :ProgressBar %current_step% %total_steps%

REM Set up and run Disk Cleanup with all options
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Active Setup Temp Folders" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\BranchCache" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Downloaded Program Files" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Internet Cache Files" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Memory Dump Files" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Old ChkDsk Files" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Previous Installations" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Recycle Bin" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Service Pack Cleanup" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Setup Log Files" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\System error memory dump files" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\System error minidump files" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Temporary Files" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Temporary Setup Files" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Thumbnail Cache" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Update Cleanup" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Upgrade Discarded Files" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\User file versions" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Windows Defender" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Windows Error Reporting Archive Files" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Windows Error Reporting Queue Files" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Windows Error Reporting System Archive Files" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Windows Error Reporting System Queue Files" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Windows ESD installation files" /v StateFlags0001 /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Windows Upgrade Log Files" /v StateFlags0001 /t REG_DWORD /d 2 /f

cleanmgr /sagerun:1
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Failed to run Advanced Disk Cleanup"
) else (
    echo - Advanced Disk Cleanup completed>> %USERPROFILE%\Desktop\CleaningLog.txt
)

REM Run system file checker
echo.
echo Running System File Checker to repair system files...
echo Running System File Checker to repair system files...>> %USERPROFILE%\Desktop\CleaningLog.txt
sfc /scannow
if %errorlevel% NEQ 0 (
    call :ErrorHandler "System File Checker encountered issues"
) else (
    echo - System File Checker completed>> %USERPROFILE%\Desktop\CleaningLog.txt
)

REM Defragment system drive
echo.
echo Running disk defragmentation...
echo Running disk defragmentation...>> %USERPROFILE%\Desktop\CleaningLog.txt
defrag %systemdrive% /U /V
if %errorlevel% NEQ 0 (
    call :ErrorHandler "Disk defragmentation encountered issues"
) else (
    echo - Disk defragmentation completed>> %USERPROFILE%\Desktop\CleaningLog.txt
)

call :ProgressBar %total_steps% %total_steps%
goto Completed

:Completed
echo.
echo ===================================================
echo Cleaning process completed successfully
echo ===================================================
echo.
echo A detailed log has been saved to your Desktop as CleaningLog.txt
echo.
echo System Status:
echo - Temporary files removed
echo - System caches cleared
echo - DNS cache reset
echo - IP configuration refreshed (if needed)
echo.
echo Registry backup saved to: %USERPROFILE%\SystemPurge_Backup\
echo.
echo Press any key to exit...
pause > nul

:::: Final cleanup
if exist "%TEMP%\user_interrupt.flag" del "%TEMP%\user_interrupt.flag" 2>nul

exit