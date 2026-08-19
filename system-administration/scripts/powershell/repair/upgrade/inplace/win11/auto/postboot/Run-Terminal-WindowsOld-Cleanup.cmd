@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "F:\study\Platforms\windows\system-administration\scripts\powershell\repair\upgrade\inplace\win11\auto\postboot\Start-Terminal-WindowsOld-Cleanup.ps1"
exit /b %ERRORLEVEL%
