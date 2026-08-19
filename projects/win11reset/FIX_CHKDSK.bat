@echo off
chcp 437 >nul
title FIX CHKDSK NOT RUNNING
color 0E

echo.
echo    ========================================
echo       FIX CHKDSK NOT RUNNING
echo    ========================================
echo.
echo    This will fix the common issue where
echo    chkdsk fails to run at Windows startup.
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0FixChkdsk.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\" ' -Verb RunAs -Wait"
