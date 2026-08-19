@echo off
chcp 437 >nul
title Windows 11 FIX ALL
color 0C

echo.
echo    ========================================
echo       WINDOWS 11 FIX ALL - NUCLEAR OPTION
echo    ========================================
echo.
echo    Run ALL repair operations:
echo    * Fix chkdsk configuration
echo    * DISM repair and cleanup
echo    * SFC system file check
echo    * Windows Update reset
echo    * Network stack reset
echo    * Registry cleanup
echo    * System cleanup
echo.
echo    Time: 20-30 minutes
echo    Keeps ALL apps and settings!
echo.
echo    Press any key to start or Ctrl+C to cancel...
pause >nul

set "SCRIPT=%~dp0FixAll.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\" -Force' -Verb RunAs -Wait"
