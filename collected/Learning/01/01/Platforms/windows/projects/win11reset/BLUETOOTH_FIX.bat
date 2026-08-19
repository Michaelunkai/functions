@echo off
chcp 437 >nul
title WINDOWS 11 BLUETOOTH FIX
color 0B

echo.
echo    ========================================
echo       WINDOWS 11 BLUETOOTH FIX
echo    ========================================
echo.
echo    Fix Bluetooth:
echo    * Bluetooth not working
echo    * Devices not pairing
echo    * Connection drops
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0BluetoothFix.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
