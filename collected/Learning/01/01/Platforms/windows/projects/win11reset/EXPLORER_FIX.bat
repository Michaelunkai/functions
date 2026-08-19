@echo off
chcp 437 >nul
title WINDOWS 11 EXPLORER FIX
color 0A

echo.
echo    ========================================
echo       WINDOWS 11 EXPLORER FIX
echo    ========================================
echo.
echo    Fix File Explorer:
echo    * Explorer crashing
echo    * Slow to open
echo    * Not responding
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0ExplorerFix.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
