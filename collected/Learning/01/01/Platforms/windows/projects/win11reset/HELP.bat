@echo off
chcp 437 >nul
title Windows 11 Smart Reset - Help
color 0F

cls
echo.
echo    ========================================================================
echo                   WINDOWS 11 SMART RESET TOOLKIT - HELP
echo    ========================================================================
echo.
echo    QUICK LAUNCHERS (Double-click to run):
echo    ------------------------------------------------------------------------
echo    FIX_CHKDSK.bat     Fix chkdsk not running at startup (1 min)
echo    QUICK_FIX.bat      Fast fix for common issues (5 min)
echo    DEEP_REPAIR.bat    Comprehensive repair (15-20 min)
echo    FIX_ALL.bat        Nuclear option, run everything (20-30 min)
echo    DIAGNOSE.bat       Analyze without making changes (2 min)
echo    SYSTEM_INFO.bat    Generate full system report
echo    MENU.bat           Interactive menu with all tools
echo.
echo    POWERSHELL FUNCTIONS (type in any terminal):
echo    ------------------------------------------------------------------------
echo    winmenu            Launch full interactive menu
echo    winfix             Quick 5-minute fix
echo    winchk             Fix chkdsk issues
echo    winrst             Windows Reset options
echo.
echo    ALL REPAIR MODES KEEP YOUR APPS AND SETTINGS!
echo    (except LightReset/FullReset/CloudReset which are Windows Reset)
echo.
echo    ========================================================================
echo.
pause
