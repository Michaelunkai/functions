@echo off
chcp 437 >nul
title WINDOWS DEFENDER FIX
color 0C

echo.
echo    ========================================
echo       WINDOWS DEFENDER FIX
echo    ========================================
echo.
echo    Fix Windows Defender:
echo    * Defender not starting
echo    * Scans not working
echo    * Definition update failures
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0DefenderFix.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
