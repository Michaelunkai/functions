@echo off
chcp 437 >nul
title WINDOWS 11 OPTIMIZATION
color 0A

echo.
echo    ========================================
echo       WINDOWS 11 OPTIMIZATION
echo    ========================================
echo.
echo    Optimize Windows 11:
echo    * Disable unnecessary services
echo    * Clean up disk space
echo    * Optimize startup
echo    * Improve performance
echo    
echo    Safe and reversible!
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0Optimize.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
