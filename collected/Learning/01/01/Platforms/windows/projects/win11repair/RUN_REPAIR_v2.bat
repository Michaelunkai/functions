@echo off
title Windows 11 ULTIMATE Repair v2.0
color 0A
echo.
echo  ==========================================================
echo   WINDOWS 11 ULTIMATE REPAIR v2.0
echo  ==========================================================
echo.
echo  This performs a COMPLETE system repair:
echo    * DISM Component Store repair
echo    * SFC System File Checker
echo    * Windows Update full reset
echo    * Registry repairs
echo    * Disk health check
echo    * In-place repair upgrade
echo.
echo  Launching as Administrator...
echo.
powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%~dp0Win11RepairInstall_v2.ps1\"' -Verb RunAs"
