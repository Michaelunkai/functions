$ErrorActionPreference='SilentlyContinue'
$roots=@($env:USERPROFILE+'\Saved Games',$env:USERPROFILE+'\Documents',$env:LOCALAPPDATA,$env:APPDATA,'E:\games\KingdomComeDeliverance2')
foreach($root in $roots){
 if(Test-Path $root){
  Write-Host "=== ROOT $root ==="
  Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'Kingdom|Warhorse|KCD|Deliverance|WHGame|profile|attributes|action|input|controller|gamepad|user\.cfg' -or $_.Name -match 'attributes\.xml|profile.*\.xml|user\.cfg|game\.cfg' } | Sort-Object LastWriteTime -Descending | Select-Object -First 120 | ForEach-Object { '{0}|{1}|{2}' -f $_.Length,$_.LastWriteTime.ToString('s'),$_.FullName }
 }
}
