@echo off
chcp 437 >nul
title WINDOWS 11 PRIVACY
color 0C

echo.
echo    ========================================
echo       WINDOWS 11 PRIVACY
echo    ========================================
echo.
echo    Adjust privacy settings:
echo    * Disable telemetry
echo    * Limit data collection
echo    * Remove advertising ID
echo    
echo    Safe and reversible with -Undo
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0Privacy.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
