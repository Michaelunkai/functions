@echo off
chcp 437 >nul
title WINDOWS 11 FORCE UPDATE
color 0B

echo.
echo    ========================================
echo       WINDOWS 11 FORCE UPDATE
echo    ========================================
echo.
echo    Force Windows Update:
echo    * Reset Windows Update completely
echo    * Force check for updates
echo    * Download and install pending updates
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0ForceUpdate.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\" ' -Verb RunAs -Wait"
