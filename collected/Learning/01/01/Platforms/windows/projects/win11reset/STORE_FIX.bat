@echo off
chcp 437 >nul
title WINDOWS STORE FIX
color 0D

echo.
echo    ========================================
echo       WINDOWS STORE FIX
echo    ========================================
echo.
echo    Fix Microsoft Store:
echo    * Store won't open
echo    * Apps won't download or update
echo    * Error codes
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0StoreFix.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\" ' -Verb RunAs -Wait"
