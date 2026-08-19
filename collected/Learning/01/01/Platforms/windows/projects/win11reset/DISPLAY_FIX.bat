@echo off
chcp 437 >nul
title WINDOWS 11 DISPLAY FIX
color 0D

echo.
echo    ========================================
echo       WINDOWS 11 DISPLAY FIX
echo    ========================================
echo.
echo    Fix display issues:
echo    * Flickering screen
echo    * Resolution issues
echo    * Graphics driver problems
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0DisplayFix.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
