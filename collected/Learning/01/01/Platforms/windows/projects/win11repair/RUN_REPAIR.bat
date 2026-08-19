@echo off
title Windows 11 Repair Install
color 0A
echo.
echo  ========================================
echo   WINDOWS 11 REPAIR INSTALL
echo  ========================================
echo.
echo  This will repair Windows 11 keeping all
echo  your files, apps, and settings.
echo.
echo  Launching as Administrator...
echo.
powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%~dp0Win11RepairInstall.ps1\"' -Verb RunAs"
