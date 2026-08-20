[CmdletBinding()]
param([string[]]$IncludeFolder)
$ErrorActionPreference='Stop'
$root='F:\backup\windowsapps\installed'; $docker='C:\Program Files\Docker\Docker\resources\bin\docker.exe'
$dockerfile=Join-Path $PSScriptRoot 'InstalledAppBackup.Dockerfile'; $uploader=Join-Path $PSScriptRoot 'Push-DockerImageChunked.ps1'; $ledger=Join-Path $PSScriptRoot 'installed-app-docker-publish.jsonl'
$tar="$env:SystemRoot\System32\tar.exe"; $importRoot='F:\backup\windowsapps\.docker-import'
$spec=@'
CodexMonitor|codexmonitor|1|overlay
WhisperKeyLocal|whisperkeylocal|1|replace
Whisper|whisper|1|replace
tv|tv|1|replace
reflect|reflect|3|overlay
FlareSolverr|flaresolverr|1|replace
Obsidian|obsidian|1|replace
telegram|telegram|2|replace
Prowlarr|prowlarr|2|replace
cloudflare|cloudflare|3|replace
Jackett|jackett|1|replace
kvrt|kvrt|1|replace
scoop|scoop|1|replace
BleachBitAutoClean|bleachbitautoclean|1|replace
tailscale|tailscale|3|replace
Process Lasso|process-lasso|1|replace
OpenSpeedy|openspeedy|2|replace
gamesavemanager|gamesavemanager|2|replace
adw|adw|2|replace
Everything|everything|2|replace
qBittorrentSearchPluginsWiki|qbittorrentsearchpluginswiki|1|replace
qBittorrentSearchPlugins|qbittorrentsearchplugins|1|replace
'@
$apps=@($spec.Trim() -split "`n" | ForEach-Object {$v=$_.Trim() -split '\|'; [pscustomobject]@{Folder=$v[0];Slug=$v[1];Tag=$v[2];Mode=$v[3]}})
if($IncludeFolder){$apps=@($apps|Where-Object {$IncludeFolder -contains $_.Folder}); if($apps.Count -ne $IncludeFolder.Count){throw 'Unknown publishing folder requested.'}}
foreach($path in @($docker,$dockerfile,$uploader,$tar)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Required file not found: $path"}}
foreach($app in $apps){
 $digest=$null
 $source=Join-Path $root $app.Folder; if(-not(Test-Path -LiteralPath $source -PathType Container)){throw "Source folder not found: $source"}
 $files=@(Get-ChildItem -LiteralPath $source -File -Recurse -Force); $bytes=[long](($files|Measure-Object Length -Sum).Sum); $image="michadockermisha/$($app.Slug):$($app.Tag)"
 Write-Host "[publish] $($app.Folder) -> $image"
 if($bytes -ge 2GB){
  New-Item -ItemType Directory -Path $importRoot -Force | Out-Null; $archive=Join-Path $importRoot ("{0}-{1}.tar" -f $app.Slug,[guid]::NewGuid().ToString('N'))
  try {
   $tarArgs=@('-cf',$archive)
   if($app.Folder -eq 'CodexMonitor'){
    $tarArgs += @('--exclude','CodexMonitor/data/windows-profile/AppData/Local/com.dimillian.codexmonitor','--exclude','CodexMonitor/data/windows-profile/AppData/Roaming/com.dimillian.codexmonitor')
   }
   $tarArgs += @('-C',$root,$app.Folder); & $tar @tarArgs; if($LASTEXITCODE -ne 0){throw "Source archive failed: $image"}
   & $tar -tf $archive | Out-Null; if($LASTEXITCODE -ne 0){throw "Source archive validation failed: $image"}
   $labels=@{'backup.source.path'=$source;'backup.source.repo'="michadockermisha/$($app.Slug)";'backup.source.tag'=$app.Tag;'backup.source.bytes'=[string]$bytes;'backup.source.files'=[string]$files.Count;'backup.restore.mode'=$app.Mode;'backup.payload.directory'=$app.Folder}
   $digest=& $uploader -Image $image -LayerArchive $archive -Labels $labels -ChunkMiB 32; if(-not $digest){throw "Upload failed: $image"}
  } finally { if($digest -and (Test-Path -LiteralPath $archive -PathType Leaf)){Remove-Item -LiteralPath $archive -Force} }
 } else {
  & $docker build --file $dockerfile --label "backup.source.path=$source" --label "backup.source.repo=michadockermisha/$($app.Slug)" --label "backup.source.tag=$($app.Tag)" --label "backup.source.bytes=$bytes" --label "backup.source.files=$($files.Count)" --label "backup.restore.mode=$($app.Mode)" --tag $image $source
  if($LASTEXITCODE -ne 0){throw "Docker build failed: $image"}
 }
 if(-not $digest){$digest=& $uploader -Image $image; if(-not $digest){throw "Upload failed: $image"}}
 [pscustomobject]@{Timestamp=(Get-Date).ToString('o');Protected=($app.Mode -eq 'overlay');Bytes=$bytes;Digest=[string]$digest;Files=$files.Count;Status='PUBLISHED';Image=$image;Folder=$app.Folder}|ConvertTo-Json -Compress|Add-Content -LiteralPath $ledger -Encoding UTF8
}
