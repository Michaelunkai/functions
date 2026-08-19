$ErrorActionPreference='SilentlyContinue'
$pidGame=23472
$p=Get-Process -Id $pidGame -ErrorAction SilentlyContinue
Write-Host '=== Game process ==='
if($p){ '{0}|pid={1}|responding={2}|path={3}' -f $p.ProcessName,$p.Id,$p.Responding,$p.Path }
Write-Host '=== Input-related loaded modules ==='
if($p){ $p.Modules | Where-Object { $_.ModuleName -match 'xinput|dinput|input|gameinput|steam|xbox|hid|SDL|pad' -or $_.FileName -match 'xinput|dinput|input|gameinput|steam|xbox|hid|SDL|pad' } | Sort-Object ModuleName | ForEach-Object { '{0}|{1}' -f $_.ModuleName,$_.FileName } }
Write-Host '=== Nearby DLLs/config ==='
$root='E:\games\KingdomComeDeliverance2'
Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'xinput|dinput|gameinput|steam_api|controller|gamepad|input|profile|system\.cfg|user\.cfg' } | Select-Object -First 80 | ForEach-Object { '{0}|{1}|{2}' -f $_.Length,$_.LastWriteTime.ToString('s'),$_.FullName }
Write-Host '=== AppData/Documents candidate configs recent ==='
$dirs=@($env:USERPROFILE+'\Saved Games',$env:USERPROFILE+'\Documents',$env:LOCALAPPDATA,$env:APPDATA)
foreach($d in $dirs){ if(Test-Path $d){ Get-ChildItem -Path $d -Recurse -File -ErrorAction SilentlyContinue | Where-Object { ($_.FullName -match 'Kingdom|KCD|Warhorse|Deliverance') -and ($_.Name -match '\.(cfg|ini|xml|json|txt|log)$|profile|input|controller|gamepad') } | Sort-Object LastWriteTime -Descending | Select-Object -First 60 | ForEach-Object { '{0}|{1}|{2}' -f $_.Length,$_.LastWriteTime.ToString('s'),$_.FullName } } }
