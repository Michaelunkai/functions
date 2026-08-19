@echo off
chcp 437 >nul
title WINDOWS 11 BOOT REPAIR
color 0C

echo.
echo    ========================================
echo       WINDOWS 11 BOOT REPAIR
echo    ========================================
echo.
echo    Repairs boot issues:
echo    * Master Boot Record (MBR)
echo    * Boot Configuration Data (BCD)
echo    * Boot files and UEFI entries
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0BootRepair.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\" ' -Verb RunAs -Wait"
