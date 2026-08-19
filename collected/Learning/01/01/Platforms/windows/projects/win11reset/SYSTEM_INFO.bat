@echo off
chcp 437 >nul
title WINDOWS 11 SYSTEM INFO
color 0F

echo.
echo    ========================================
echo       WINDOWS 11 SYSTEM INFO
echo    ========================================
echo.
echo    Gathering system info for diagnostics...
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0SystemInfo.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
