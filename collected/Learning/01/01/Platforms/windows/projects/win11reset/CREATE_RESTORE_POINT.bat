@echo off
chcp 437 >nul
title CREATE RESTORE POINT
color 0A

echo.
echo    ========================================
echo       CREATE RESTORE POINT
echo    ========================================
echo.
echo    Create a backup restore point
echo    before making any system changes.
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0CreateRestorePoint.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
