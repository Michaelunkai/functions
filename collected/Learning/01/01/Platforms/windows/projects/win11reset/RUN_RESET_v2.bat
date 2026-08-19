@echo off
chcp 437 >nul
title Windows 11 Smart Reset v2.0
color 0B

cls
echo.
echo    ========================================
echo       WINDOWS 11 SMART RESET v2.0
echo    ========================================
echo.
echo    MODES:
echo      [1] Quick Fix     Fix common issues (5 min)
echo      [2] Deep Repair   Full repair, keep apps (15 min)
echo      [3] Light Reset   Keep files, remove apps
echo      [4] Full Reset    Fresh Windows install
echo      [5] Cloud Reset   Download fresh Windows
echo.

set /p choice="    Select mode (1-5): "

set "SCRIPT=%~dp0Win11SmartReset_v2.ps1"
set "SCRIPT1=%~dp0Win11SmartReset.ps1"

if "%choice%"=="1" (
    powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\" -Mode QuickFix -Force' -Verb RunAs -Wait"
    goto end
)
if "%choice%"=="2" (
    powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\" -Mode DeepRepair -Force' -Verb RunAs -Wait"
    goto end
)
if "%choice%"=="3" (
    powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT1%\" -Mode LightReset' -Verb RunAs -Wait"
    goto end
)
if "%choice%"=="4" (
    powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT1%\" -Mode FullReset' -Verb RunAs -Wait"
    goto end
)
if "%choice%"=="5" (
    powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT1%\" -Mode CloudReset' -Verb RunAs -Wait"
    goto end
)

echo.
echo    Invalid choice.
pause
exit

:end
echo.
echo    Done.
timeout /t 3 >nul
