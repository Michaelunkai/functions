@echo off
chcp 437 >nul
title CONTEXT MENU FIX
color 0A

echo.
echo    ========================================
echo       CONTEXT MENU FIX
echo    ========================================
echo.
echo    Fix right-click menu:
echo    * Restore classic menu (Win10 style)
echo    * Fix slow context menu
echo    * Reset to default
echo.
echo    Launching as Administrator...
echo.

set "SCRIPT=%~dp0ContextMenuFix.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%SCRIPT%\"' -Verb RunAs -Wait"
