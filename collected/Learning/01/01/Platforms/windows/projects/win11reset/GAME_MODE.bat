@echo off
chcp 437 >nul
title WINDOWS 11 GAME MODE
color 0D

echo.
echo    ========================================
echo       WINDOWS 11 GAME MODE
echo    ========================================
echo.
echo    Optimize for gaming:
echo    * Disable background processes
echo    * Maximize performance
echo    * Enable Game Mode
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0GameMode.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
