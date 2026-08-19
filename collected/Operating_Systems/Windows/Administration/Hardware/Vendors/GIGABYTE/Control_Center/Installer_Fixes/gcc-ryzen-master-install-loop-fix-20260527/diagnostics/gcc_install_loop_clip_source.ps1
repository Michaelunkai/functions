$ErrorActionPreference='SilentlyContinue'
if(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run this from an elevated PowerShell 5 window (Run as administrator).'}
$fixes=@()
$un=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -and $_.DisplayVersion}
function Set-VerMarker($display,$regPath,$valueName){
  $app=$un | Where-Object {$_.DisplayName -eq $display -or $_.DisplayName -like "*$display*" -or $display -like "*$($_.DisplayName)*"} | Sort-Object {[version](($_.DisplayVersion -replace '[^0-9\.]','').Trim('.'))} -Descending | Select-Object -First 1
  if($app){
    $key='HKLM:\'+($regPath -replace '^HKEY_LOCAL_MACHINE\\','' -replace '^HKLM\\','' -replace '^HKLM:\\','')
    New-Item -Path $key -Force | Out-Null
    $old=(Get-ItemProperty -Path $key -Name $valueName -ErrorAction SilentlyContinue).$valueName
    if($old -ne $app.DisplayVersion){ New-ItemProperty -Path $key -Name $valueName -Value $app.DisplayVersion -PropertyType String -Force | Out-Null; $script:fixes += "$display => $key\$valueName=$($app.DisplayVersion)" }
  }
}
Set-VerMarker 'AMD Ryzen Master' 'SOFTWARE\AMD\RyzenMaster' 'VersionNumber'
$base='C:\Program Files\GIGABYTE\Control Center\Lib\GBT_MB_Update\Drvdata'
$pkg=Join-Path $base 'Package.csv'; $dt=Join-Path $base 'DriverTable.csv'; $dd=Join-Path $base 'DriverDesp.csv'
if((Test-Path $pkg) -and (Test-Path $dt) -and (Test-Path $dd)){
  $desc=@{}; Get-Content $dd | ForEach-Object { $p=$_ -split ',',3; if($p.Count -ge 2){$desc[$p[0]]=$p[1]} }
  $dmap=@{}; Get-Content $dt | ForEach-Object { $p=$_ -split ','; if($p.Count -ge 3 -and $desc.ContainsKey($p[2])){$dmap[$p[0]]=$desc[$p[2]]} }
  Get-Content $pkg | ForEach-Object { $p=$_ -split ','; if($p.Count -ge 6 -and $dmap.ContainsKey($p[0])){ Set-VerMarker $dmap[$p[0]] (($p[4] -replace '\\\\','\')) $p[5] } }
}
Get-Process GCC,GigabyteUpdateService,GBT_DL_LIB -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$cache='C:\Program Files\GIGABYTE\Control Center\GCCUpdate.txt'; if(Test-Path $cache){ Copy-Item $cache "$cache.bak.$(Get-Date -Format yyyyMMddHHmmss)" -Force; Remove-Item $cache -Force }
"GCC install-loop markers fixed: $($fixes -join '; ')"
