$ErrorActionPreference='SilentlyContinue'
$paths=@('E:\games\KingdomComeDeliverance2\user.cfg','E:\games\KingdomComeDeliverance2\system.cfg')
foreach($p in $paths){ if(Test-Path $p){ 'FILE|{0}|{1}|{2}' -f (Get-Item $p).Length,(Get-Item $p).LastWriteTime.ToString('s'),$p } else { 'MISSING|'+$p } }
Write-Host '=== recent logs under game root ==='
Get-ChildItem 'E:\games\KingdomComeDeliverance2' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.(log|txt)$' -or $_.Name -match 'log|crash|game' } | Sort-Object LastWriteTime -Descending | Select-Object -First 40 | ForEach-Object { '{0}|{1}|{2}' -f $_.Length,$_.LastWriteTime.ToString('s'),$_.FullName }
