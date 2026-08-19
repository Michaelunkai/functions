$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$App=Join-Path $Root 'dist\app.exe'
$Victim='C:\Temp\HermesFastPurge_smoke_victim'
if(Test-Path -LiteralPath $Victim){ Remove-Item -LiteralPath $Victim -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $Victim | Out-Null
1..1000 | ForEach-Object { $d=Join-Path $Victim ('d'+($_%25)); New-Item -ItemType Directory -Force -Path $d | Out-Null; Set-Content -LiteralPath (Join-Path $d ('f'+$_+'.txt')) -Value ('x'*200) }
$sw=[Diagnostics.Stopwatch]::StartNew()
$out = & $App $Victim 2>&1
$code=$LASTEXITCODE
$sw.Stop()
$exists=Test-Path -LiteralPath $Victim
Write-Host "exit=$code elapsedMs=$($sw.ElapsedMilliseconds) originalExists=$exists"
$out | ForEach-Object { Write-Host $_ }
if($code -ne 0 -or $exists -or $sw.Elapsed.TotalSeconds -ge 5){ exit 1 }
Start-Sleep -Milliseconds 700
$left = Get-ChildItem 'C:\Temp\.fastpurge-graveyard' -Directory -ErrorAction SilentlyContinue
Write-Host "graveyardDirs=$(@($left).Count)"
