[CmdletBinding()]
param([switch]$SelfTest)
$ErrorActionPreference='Stop'
$roots=@((Join-Path $env:LOCALAPPDATA 'Docker\run'),(Join-Path $env:LOCALAPPDATA 'Docker\vm-data'),(Join-Path $env:LOCALAPPDATA 'docker-secrets-engine'))
if($SelfTest){Write-Output 'DOCKER_SOCKET_REPAIR_SELFTEST backend=windows-native wsl=false';return}
if(@(Get-Process -Name 'com.docker.backend','Docker Desktop','com.docker.sailor','sailor' -ErrorAction SilentlyContinue).Count){throw 'Docker must be stopped before repairing its runtime sockets.'}
$count=0
foreach($root in $roots){
 if(-not [IO.Directory]::Exists($root)){continue}
 $directory=Get-Item -LiteralPath $root -Force
 if($directory.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Socket directory is redirected: $root"}
 $failed=$false
 foreach($entry in @(Get-ChildItem -LiteralPath $root -Force)){
  if($entry.Name -match '(\.sock(\.stale)?$)|(^[0-9a-fA-F]{8}\.[0-9a-fA-F]{8}(\.stale)?$)' -or $entry.Name -in @('dockerEthernetVfkit','dockerInference')){
   if($entry.PSIsContainer){throw "Unexpected directory at socket path: $($entry.FullName)"}
   try{[IO.File]::Delete($entry.FullName);$count++}catch{$failed=$true}
  }
 }
 if($failed){
  $recoveryRoot=Join-Path $env:LOCALAPPDATA 'DockerSocketRecovery'
  [void][IO.Directory]::CreateDirectory($recoveryRoot)
  if((Get-Item -LiteralPath $recoveryRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Socket recovery directory is redirected'}
  $destination=Join-Path $recoveryRoot ((Split-Path -Leaf $root)+'-'+[guid]::NewGuid().ToString('N'))
  if([IO.Path]::GetDirectoryName($destination) -ne $recoveryRoot){throw 'Socket recovery target escaped its root'}
  [IO.Directory]::Move($root,$destination)
  [void][IO.Directory]::CreateDirectory($root)
  foreach($item in @(Get-ChildItem -LiteralPath $destination -Force)){
   if($item.Name -match '(\.sock(\.stale)?$)|(^[0-9a-fA-F]{8}\.[0-9a-fA-F]{8}(\.stale)?$)' -or $item.Name -in @('dockerEthernetVfkit','dockerInference')){continue}
   if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Unexpected redirected state: $($item.FullName)"}
   Move-Item -LiteralPath $item.FullName -Destination $root -ErrorAction Stop
  }
  Write-Output "DOCKER_STALE_SOCKET_DIRECTORY_ISOLATED=$destination"
 }
}
Write-Output "DOCKER_STALE_SOCKETS_DELETED=$count"