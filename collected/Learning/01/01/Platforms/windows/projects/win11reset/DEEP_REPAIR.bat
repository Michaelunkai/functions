@echo off
chcp 437 >nul
title WINDOWS 11 DEEP REPAIR
color 0B

echo.
echo    ========================================
echo       WINDOWS 11 DEEP REPAIR
echo    ========================================
echo.
echo    Comprehensive system repair:
echo    * Full DISM repair and cleanup
echo    * Complete SFC scan
echo    * Windows Update reset
echo    * Network stack reset
echo    * Registry cleanup
echo    
echo    Keeps ALL apps and settings!
echo    Time: 15-20 minutes
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0Win11SmartReset_v2.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\" -Mode DeepRepair -Force' -Verb RunAs -Wait"
