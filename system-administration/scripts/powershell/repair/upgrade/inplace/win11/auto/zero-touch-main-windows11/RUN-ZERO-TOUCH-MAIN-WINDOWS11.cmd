@echo off
setlocal
set "ROOT=%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\Start-ZeroTouchMainWindows11.ps1" -AutoReboot
exit /b %ERRORLEVEL%
