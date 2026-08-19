@echo off
chcp 437 >nul
title WINDOWS 11 SEARCH FIX
color 0E

echo.
echo    ========================================
echo       WINDOWS 11 SEARCH FIX
echo    ========================================
echo.
echo    Fix Windows Search:
echo    * Search not working
echo    * Blank search results
echo    * High CPU usage by search
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0SearchFix.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
