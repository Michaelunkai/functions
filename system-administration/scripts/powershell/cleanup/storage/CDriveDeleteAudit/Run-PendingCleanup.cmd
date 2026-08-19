@echo off
set "LOG=C:\Temp\CDriveMaxSafeDeleteAudit\pending-startup-cleanup.log"
set "MANIFEST=C:\Temp\CDriveMaxSafeDeleteAudit\pending-startup-manifest.csv"
echo ==== %DATE% %TIME% ====>>"%LOG%"
if not exist "%MANIFEST%" (
  echo No pending manifest found: %MANIFEST%>>"%LOG%"
  schtasks.exe /Delete /TN CDriveMaxSafeDeleteAudit-PendingCleanup /F >>"%LOG%" 2>&1
  exit /b 0
)
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Platforms\windows\system-administration\scripts\powershell\cleanup\storage\CDriveDeleteAudit\Invoke-CDriveMaxSafeDeleteAudit.ps1" -ForceDeleteListed -DeleteManifest "%MANIFEST%" >>"%LOG%" 2>&1
schtasks.exe /Delete /TN CDriveMaxSafeDeleteAudit-PendingCleanup /F >>"%LOG%" 2>&1
