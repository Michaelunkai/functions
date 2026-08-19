@echo off
chcp 437 >nul
title WINDOWS 11 NETWORK FIX
color 0E

echo.
echo    ========================================
echo       WINDOWS 11 NETWORK FIX
echo    ========================================
echo.
echo    Fixes network problems:
echo    * No internet connection
echo    * DNS issues
echo    * Slow network speeds
echo    * WiFi problems
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0NetworkFix.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\" ' -Verb RunAs -Wait"
