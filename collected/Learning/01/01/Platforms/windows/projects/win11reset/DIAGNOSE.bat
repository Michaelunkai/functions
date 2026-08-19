@echo off
chcp 437 >nul
title WINDOWS 11 SYSTEM DIAGNOSIS
color 0D

echo.
echo    ========================================
echo       WINDOWS 11 SYSTEM DIAGNOSIS
echo    ========================================
echo.
echo    Analyzes your system for issues:
echo    * Disk health
echo    * System file integrity
echo    * Windows Update status
echo    * Boot configuration
echo    
echo    No changes will be made!
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0Win11SmartReset_v2.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\" -Mode Diagnose' -Verb RunAs -Wait"
