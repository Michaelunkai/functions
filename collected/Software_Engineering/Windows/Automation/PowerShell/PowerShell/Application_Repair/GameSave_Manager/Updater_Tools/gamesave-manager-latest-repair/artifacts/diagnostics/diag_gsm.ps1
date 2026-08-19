$ErrorActionPreference='Continue'
$paths = @('F:\backup\windowsapps\installed\gamesavemanager','E:\games\KingdomComeDeliverance2\FLiNG Trainer')
foreach($p in $paths){
  Write-Host "--- DIR $p ---"
  if(Test-Path $p){ Get-ChildItem -LiteralPath $p -Force | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize } else { Write-Host 'MISSING' }
}
Write-Host '--- FILE VERSIONS ---'
@('F:\backup\windowsapps\installed\gamesavemanager\gs_mngr_3.exe','E:\games\KingdomComeDeliverance2\FLiNG Trainer\Kingdom Come Deliverance II v1.1-v1.4 Plus 41 Trainer.exe') | ForEach-Object { if(Test-Path $_){ $v=(Get-Item $_).VersionInfo; [PSCustomObject]@{Path=$_; FileVersion=$v.FileVersion; ProductVersion=$v.ProductVersion; Description=$v.FileDescription; Company=$v.CompanyName; Size=(Get-Item $_).Length} } } | Format-List
Write-Host '--- RECENT APP ERRORS ---'
Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddHours(-3)} -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'gs_mngr|GameSave|Kingdom Come|Trainer|File not found' } | Select-Object TimeCreated,ProviderName,Id,Message -First 20 | Format-List
