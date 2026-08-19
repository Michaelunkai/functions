$ErrorActionPreference='SilentlyContinue'
$out=[ordered]@{}
$out.IsAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$out.Time=(Get-Date).ToString('s')
$out.OS=(Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber)
$out.CPU=(Get-CimInstance Win32_Processor | Select-Object Name)
$un=@()
$unPaths=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')
foreach($p in $unPaths){ $un += Get-ItemProperty $p | Where-Object { $_.DisplayName -match 'Ryzen|AMD|GIGABYTE|Control Center' } | Select-Object PSChildName,DisplayName,DisplayVersion,Publisher,InstallLocation,UninstallString,QuietUninstallString,InstallDate }
$out.Uninstall=$un
$out.Services=Get-CimInstance Win32_SystemDriver | Where-Object { $_.Name -match 'Ryzen|AMD|GIGABYTE|gdrv|AMDRyzen' -or $_.DisplayName -match 'Ryzen|AMD|GIGABYTE|gdrv|AMDRyzen' } | Select-Object Name,DisplayName,State,StartMode,PathName
$out.Processes=Get-Process | Where-Object { $_.ProcessName -match 'Ryzen|AMD|GIGABYTE|GCC|ControlCenter|UpdPack|mb_|GBT' } | Select-Object ProcessName,Id,Path
$paths=@($env:ProgramFiles+'\AMD\RyzenMaster',$env:ProgramFiles+'\AMD',$env:ProgramFiles+'\GIGABYTE',$env:ProgramFiles+'\GIGABYTE\Control Center',$env:ProgramFilesX86+'\GIGABYTE',$env:ProgramData+'\GIGABYTE',$env:ProgramData+'\AMD',$env:LOCALAPPDATA+'\GIGABYTE',$env:APPDATA+'\GIGABYTE','C:\AMD')
$out.Paths=$paths | ForEach-Object { if(Test-Path $_){ $i=Get-Item $_; [pscustomobject]@{Path=$i.FullName; Exists=$true; LastWrite=$i.LastWriteTime; ChildCount=@(Get-ChildItem $_ -Force -ErrorAction SilentlyContinue).Count} } else { [pscustomobject]@{Path=$_;Exists=$false} } }
$roots=@($env:ProgramFiles+'\GIGABYTE',$env:ProgramData+'\GIGABYTE',$env:LOCALAPPDATA+'\GIGABYTE',$env:APPDATA+'\GIGABYTE')
$hits=@()
foreach($r in $roots){ if(Test-Path $r){ $hits += Get-ChildItem $r -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Ryzen|AMD|Update|Package|software|version|install|manifest|json|xml|db|ini|log' } | Select-Object -First 120 FullName,Length,LastWriteTime } }
$out.GigabyteCandidateFiles=$hits
$out | ConvertTo-Json -Depth 6
