@echo off
chcp 437 >nul
title WINDOWS 11 USB FIX
color 0B

echo.
echo    ========================================
echo       WINDOWS 11 USB FIX
echo    ========================================
echo.
echo    Fix USB devices:
echo    * Devices not recognized
echo    * USB power issues
echo    * Driver problems
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0USBFix.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
