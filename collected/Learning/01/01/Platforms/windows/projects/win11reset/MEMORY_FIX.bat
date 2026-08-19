@echo off
chcp 437 >nul
title WINDOWS 11 MEMORY FIX
color 0A

echo.
echo    ========================================
echo       WINDOWS 11 MEMORY FIX
echo    ========================================
echo.
echo    Fix memory issues:
echo    * High memory usage
echo    * Memory leaks
echo    * Slow performance
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0MemoryFix.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
