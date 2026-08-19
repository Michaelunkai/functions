@echo off
chcp 437 >nul
title WINDOWS 11 QUICK FIX
color 0A

echo.
echo    ========================================
echo       WINDOWS 11 QUICK FIX
echo    ========================================
echo.
echo    Fast fixes for common issues:
echo    * Chkdsk not running
echo    * Corrupted system files
echo    * Windows Update problems
echo    
echo    Keeps ALL apps and settings!
echo    Time: 5 minutes
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0Win11SmartReset_v2.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\" -Mode QuickFix -Force' -Verb RunAs -Wait"
