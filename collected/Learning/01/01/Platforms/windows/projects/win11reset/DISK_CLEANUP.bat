@echo off
chcp 437 >nul
title WINDOWS 11 DISK CLEANUP
color 0E

echo.
echo    ========================================
echo       WINDOWS 11 DISK CLEANUP
echo    ========================================
echo.
echo    Deep clean disk:
echo    * Temp files
echo    * Windows Update cache
echo    * System cache
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0DiskCleanup.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
