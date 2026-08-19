$ErrorActionPreference='SilentlyContinue'
$exe='F:\backup\windowsapps\installed\gamesavemanager\gs_mngr_3.exe'
$p=Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -eq $exe } | Select-Object -First 1 ProcessId,ExecutablePath,CommandLine
$v=(Get-Item -LiteralPath $exe).VersionInfo
[PSCustomObject]@{RunningPid=$p.ProcessId; Path=$p.ExecutablePath; FileVersion=$v.FileVersion; ProductVersion=$v.ProductVersion; Size=(Get-Item -LiteralPath $exe).Length; LastWriteTime=(Get-Item -LiteralPath $exe).LastWriteTime} | Format-List
Get-Content -LiteralPath 'C:\Temp\gsm_latest_repair\last_run.log' -Tail 12
