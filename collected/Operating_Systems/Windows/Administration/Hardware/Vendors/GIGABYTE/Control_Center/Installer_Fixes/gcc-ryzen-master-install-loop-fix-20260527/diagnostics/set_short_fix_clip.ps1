$one='powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\Hermes\Fix-GCCInstallLoop.ps1"'
Set-Clipboard -Value $one
'clip='+((Get-Clipboard) -eq $one)
'one='+$one
