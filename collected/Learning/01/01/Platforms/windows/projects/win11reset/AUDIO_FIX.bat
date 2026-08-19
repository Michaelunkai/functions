@echo off
chcp 437 >nul
title WINDOWS 11 AUDIO FIX
color 0E

echo.
echo    ========================================
echo       WINDOWS 11 AUDIO FIX
echo    ========================================
echo.
echo    Fix audio problems:
echo    * No sound
echo    * Crackling or distortion
echo    * Audio services not working
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0AudioFix.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
