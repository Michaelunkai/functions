@echo off
chcp 437 >nul
title WINDOWS 11 PRINTER FIX
color 0B

echo.
echo    ========================================
echo       WINDOWS 11 PRINTER FIX
echo    ========================================
echo.
echo    Fix printer problems:
echo    * Print spooler crashes
echo    * Printer offline
echo    * Jobs stuck in queue
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0PrinterFix.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
