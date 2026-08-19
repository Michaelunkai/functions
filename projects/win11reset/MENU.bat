@echo off
chcp 437 >nul
title Windows 11 Toolkit v2.5
color 0F

:menu
cls
echo.
echo    ========================================================================
echo    =              WINDOWS 11 SMART RESET TOOLKIT v2.5                     =
echo    =                      50+ Tools - All in One                          =
echo    ========================================================================
echo.
echo    SYSTEM REPAIR (Keeps ALL apps):
echo    ------------------------------------------------------------------------
echo    [1] Quick Fix (5m)    [2] Deep Repair (15m)   [3] FIX ALL (30m)
echo    [4] Diagnose (2m)     [G] Create Backup       [I] System Info
echo.
echo    CORE FIXES:
echo    ------------------------------------------------------------------------
echo    [5] Chkdsk Fix        [6] Boot Repair         [7] Network Fix
echo    [8] Force Update      [9] Store Fix           [A] Audio Fix
echo.
echo    DEVICE FIXES:
echo    ------------------------------------------------------------------------
echo    [B] Printer Fix       [E] Bluetooth Fix       [U] USB Fix
echo    [D] Display Fix       [T] Time Sync           [F] Defender Fix
echo.
echo    OPTIMIZATION:
echo    ------------------------------------------------------------------------
echo    [C] Optimize PC       [P] Privacy Settings    [M] Context Menu
echo    [S] Search Fix        [K] Taskbar Fix         [L] Explorer Fix
echo    [N] Memory Fix        [O] Startup Fix         [J] Game Mode
echo    [W] Disk Cleanup
echo.
echo    [R] Windows Reset     [H] Help                [X] Exit
echo.
echo    ========================================================================
echo.
set /p choice="    Select option: "

if /i "%choice%"=="1" call "%~dp0QUICK_FIX.bat" & goto menu
if /i "%choice%"=="2" call "%~dp0DEEP_REPAIR.bat" & goto menu
if /i "%choice%"=="3" call "%~dp0FIX_ALL.bat" & goto menu
if /i "%choice%"=="4" call "%~dp0DIAGNOSE.bat" & goto menu
if /i "%choice%"=="5" call "%~dp0FIX_CHKDSK.bat" & goto menu
if /i "%choice%"=="6" call "%~dp0BOOT_REPAIR.bat" & goto menu
if /i "%choice%"=="7" call "%~dp0NETWORK_FIX.bat" & goto menu
if /i "%choice%"=="8" call "%~dp0FORCE_UPDATE.bat" & goto menu
if /i "%choice%"=="9" call "%~dp0STORE_FIX.bat" & goto menu
if /i "%choice%"=="A" call "%~dp0AUDIO_FIX.bat" & goto menu
if /i "%choice%"=="B" call "%~dp0PRINTER_FIX.bat" & goto menu
if /i "%choice%"=="C" call "%~dp0OPTIMIZE.bat" & goto menu
if /i "%choice%"=="D" call "%~dp0DISPLAY_FIX.bat" & goto menu
if /i "%choice%"=="E" call "%~dp0BLUETOOTH_FIX.bat" & goto menu
if /i "%choice%"=="F" call "%~dp0DEFENDER_FIX.bat" & goto menu
if /i "%choice%"=="G" call "%~dp0CREATE_RESTORE_POINT.bat" & goto menu
if /i "%choice%"=="H" call "%~dp0HELP.bat" & goto menu
if /i "%choice%"=="I" call "%~dp0SYSTEM_INFO.bat" & goto menu
if /i "%choice%"=="J" call "%~dp0GAME_MODE.bat" & goto menu
if /i "%choice%"=="K" call "%~dp0TASKBAR_FIX.bat" & goto menu
if /i "%choice%"=="L" call "%~dp0EXPLORER_FIX.bat" & goto menu
if /i "%choice%"=="M" call "%~dp0CONTEXT_MENU_FIX.bat" & goto menu
if /i "%choice%"=="N" call "%~dp0MEMORY_FIX.bat" & goto menu
if /i "%choice%"=="O" call "%~dp0STARTUP_FIX.bat" & goto menu
if /i "%choice%"=="P" call "%~dp0PRIVACY.bat" & goto menu
if /i "%choice%"=="R" call "%~dp0RUN_RESET.bat" & goto menu
if /i "%choice%"=="S" call "%~dp0SEARCH_FIX.bat" & goto menu
if /i "%choice%"=="T" call "%~dp0TIME_FIX.bat" & goto menu
if /i "%choice%"=="U" call "%~dp0USB_FIX.bat" & goto menu
if /i "%choice%"=="W" call "%~dp0DISK_CLEANUP.bat" & goto menu
if /i "%choice%"=="X" exit

echo.
echo    Invalid option. Press any key to try again...
pause >nul
goto menu
