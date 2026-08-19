@echo off
chcp 437 >nul
title WINDOWS 11 TASKBAR FIX
color 0B

echo.
echo    ========================================
echo       WINDOWS 11 TASKBAR FIX
echo    ========================================
echo.
echo    Fix taskbar issues:
echo    * Taskbar not responding
echo    * Icons missing
echo    * Start menu broken
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0TaskbarFix.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
