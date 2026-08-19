@echo off
chcp 437 >nul
title Windows 11 Smart Reset
color 0B

echo.
echo    ========================================
echo       WINDOWS 11 SMART RESET
echo    ========================================
echo.
echo    This will reset/repair Windows 11 using
echo    the LIGHTEST options to preserve your
echo    apps and settings where possible.
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0Win11SmartReset.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
