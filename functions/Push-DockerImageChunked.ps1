[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Image,
    [int]$ChunkMiB=16,
    [string]$SavedArchive,
    [string]$LayerArchive,
    [hashtable]$Labels,
    [string]$WorkRoot='F:\backup\windowsapps\.docker-upload-work'
)
$ErrorActionPreference='Stop'; $bin='C:\Program Files\Docker\Docker\resources\bin'; $docker=Join-Path $bin 'docker.exe'; $helper=Join-Path $bin 'docker-credential-desktop.exe'; $tar=Join-Path $env:SystemRoot 'System32\tar.exe'
if($Image -notmatch '^([^/]+)/([^:]+):(.+)$'){throw "Expected namespace/repository:tag: $Image"}; $repository="$($Matches[1])/$($Matches[2])"; $tag=$Matches[3]
$work=Join-Path $WorkRoot ('.docker-chunk-push-'+[guid]::NewGuid().ToString('N')); $archive=Join-Path $work 'image.tar'; $expanded=Join-Path $work 'expanded'
function GetToken {
 $scope=[Uri]::EscapeDataString("repository:$repository`:pull,push"); $nonce=[guid]::NewGuid().ToString('N'); $ar=[Net.HttpWebRequest]::Create("https://auth.docker.io/token?service=registry.docker.io&scope=$scope&client_id=installed-app-backup-$nonce"); $ar.Headers['Authorization']='Basic '+$script:Basic
 $ax=$ar.GetResponse(); $rd=New-Object IO.StreamReader($ax.GetResponseStream()); try{$script:RegistryToken=($rd.ReadToEnd()|ConvertFrom-Json).token; $script:TokenAt=Get-Date}finally{$rd.Dispose();$ax.Dispose()}; $script:RegistryToken
}
function Request([string]$Method,[string]$Uri,[string]$Token,[string]$Type,[string]$File,[long]$Offset,[long]$Count,[byte[]]$Body,[int]$Retry=0){
 if($Token -and $script:TokenAt -and ((Get-Date)-$script:TokenAt).TotalSeconds -gt 180){$Token=GetToken}
 $r=[Net.HttpWebRequest]::Create($Uri); $r.Method=$Method; $r.Timeout=300000; $r.ReadWriteTimeout=300000; $r.AllowAutoRedirect=$false; if($Token){$r.Headers['Authorization']='Bearer '+$Token}; if($Type){$r.ContentType=$Type}
 if($Method -in @('PATCH','PUT','POST')){$r.ContentLength=if($Body){$Body.Length}else{$Count}; if($Count -gt 0){$r.Headers['Content-Range']="$Offset-$($Offset+$Count-1)"}; $s=$r.GetRequestStream(); try{if($Body){$s.Write($Body,0,$Body.Length)}elseif($Count -gt 0){$f=[IO.File]::OpenRead($File); try{[void]$f.Seek($Offset,0); $left=$Count; $buf=New-Object byte[] 1048576; while($left -gt 0){$n=$f.Read($buf,0,[int][Math]::Min($buf.Length,$left)); if($n -le 0){throw 'Unexpected end of blob.'}; $s.Write($buf,0,$n); $left-=$n}}finally{$f.Dispose()}}}finally{$s.Dispose()}}
 try{$x=$r.GetResponse()}catch [Net.WebException]{$x=$_.Exception.Response; if(-not $x){throw}; $rd=New-Object IO.StreamReader($x.GetResponseStream()); try{$detail=$rd.ReadToEnd()}finally{$rd.Dispose()}; $code=[int]$x.StatusCode; $x.Dispose(); if($code -eq 401 -and $Token -and $Retry -eq 0){$fresh=GetToken; return Request $Method $Uri $fresh $Type $File $Offset $Count $Body 1}; throw "Registry $Method failed ($code): $detail"}
 $rd=New-Object IO.StreamReader($x.GetResponseStream()); try{$text=$rd.ReadToEnd()}finally{$rd.Dispose()}; $o=[pscustomobject]@{Status=[int]$x.StatusCode;Location=[string]$x.Headers['Location'];Digest=[string]$x.Headers['Docker-Content-Digest'];Body=$text}; $x.Dispose(); $o
}
function Absolute([string]$u){if($u -match '^https?://'){return $u}; 'https://registry-1.docker.io'+$u}
function Get-Sha256([string]$Path){
 $stream=[IO.File]::OpenRead($Path); $sha=[Security.Cryptography.SHA256]::Create(); try{($sha.ComputeHash($stream)|ForEach-Object {$_.ToString('x2')}) -join ''}finally{$sha.Dispose();$stream.Dispose()}
}
function PushBlob([string]$Path,[string]$Digest,[string]$Token){
 try{$h=Request HEAD "https://registry-1.docker.io/v2/$repository/blobs/$Digest" $Token $null $null 0 0 $null; if($h.Status -eq 200){Write-Host "[blob] exists $Digest"; return}}catch{}
 $x=Request POST "https://registry-1.docker.io/v2/$repository/blobs/uploads/" $Token 'application/octet-stream' $null 0 0 $null; $location=Absolute $x.Location; $size=(Get-Item -LiteralPath $Path).Length; $offset=0L; $chunk=[long]$ChunkMiB*1MB
 while($offset -lt $size){$count=[Math]::Min($chunk,$size-$offset); $x=Request PATCH $location $Token 'application/octet-stream' $Path $offset $count $null; if($x.Status -ne 202){throw "Unexpected PATCH status $($x.Status)"}; $location=Absolute $x.Location; $offset+=$count; Write-Host ("[blob] {0:N1}%" -f (100*$offset/$size))}
 $join=if($location.Contains('?')){'&'}else{'?'}; $x=Request PUT ($location+$join+'digest='+[Uri]::EscapeDataString($Digest)) $Token 'application/octet-stream' $null 0 0 $null; if($x.Status -ne 201){throw "Unexpected commit status $($x.Status)"}
}
New-Item -ItemType Directory -Path $expanded -Force|Out-Null
try{
 $directLayer=[bool]$LayerArchive
 if($directLayer){
  $layerPath=[IO.Path]::GetFullPath($LayerArchive); if(-not(Test-Path -LiteralPath $layerPath -PathType Leaf)){throw "Layer archive not found: $layerPath"}
  & $tar -tf $layerPath *> $null; if($LASTEXITCODE -ne 0){throw 'Layer archive validation failed.'}
  if(-not $Labels){throw 'Labels are required with LayerArchive.'}
  $layerDigest='sha256:'+(Get-Sha256 $layerPath)
  $config=Join-Path $work 'config.json'; $configObject=[ordered]@{created=(Get-Date).ToUniversalTime().ToString('o');architecture='amd64';os='linux';config=@{Labels=$Labels};rootfs=@{type='layers';diff_ids=@($layerDigest)};history=@(@{created=(Get-Date).ToUniversalTime().ToString('o');created_by='installed-app direct archive publisher'})}
  [IO.File]::WriteAllText($config,($configObject|ConvertTo-Json -Depth 8 -Compress),(New-Object Text.UTF8Encoding($false)))
 }elseif($SavedArchive){
  $archive=[IO.Path]::GetFullPath($SavedArchive); if(-not(Test-Path -LiteralPath $archive -PathType Leaf)){throw "Saved image archive not found: $archive"}
 }else{
  & $docker save --output $archive $Image; if($LASTEXITCODE -ne 0){throw "docker save failed: $Image"}
 }
 if(-not $directLayer){
  & $tar -tf $archive *> $null; if($LASTEXITCODE -ne 0){throw 'Image archive validation failed.'}
  & $tar -xf $archive -C $expanded; if($LASTEXITCODE -ne 0){throw 'Image extraction failed.'}
  $saved=Get-Content -LiteralPath (Join-Path $expanded 'manifest.json') -Raw|ConvertFrom-Json|Select-Object -First 1; $config=Join-Path $expanded ([string]$saved.Config)
 }
 $configDigest='sha256:'+(Get-Sha256 $config)
 $cred=('https://index.docker.io/v1/'|& $helper get|ConvertFrom-Json); $script:Basic=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($cred.Username):$($cred.Secret)")); $token=GetToken
 PushBlob $config $configDigest $token; $layers=@(); if($directLayer){PushBlob $layerPath $layerDigest $token; $layers+=@{mediaType='application/vnd.oci.image.layer.v1.tar';digest=$layerDigest;size=(Get-Item -LiteralPath $layerPath).Length}}else{foreach($rel in @($saved.Layers)){$path=Join-Path $expanded ([string]$rel); $digest='sha256:'+(Get-Sha256 $path); PushBlob $path $digest $token; $layers+=@{mediaType='application/vnd.oci.image.layer.v1.tar';digest=$digest;size=(Get-Item -LiteralPath $path).Length}}}
 $manifest=[ordered]@{schemaVersion=2;mediaType='application/vnd.oci.image.manifest.v1+json';config=@{mediaType='application/vnd.oci.image.config.v1+json';digest=$configDigest;size=(Get-Item $config).Length};layers=$layers}; $body=[Text.Encoding]::UTF8.GetBytes(($manifest|ConvertTo-Json -Depth 8 -Compress))
 $x=Request PUT "https://registry-1.docker.io/v2/$repository/manifests/$tag" $token 'application/vnd.oci.image.manifest.v1+json' $null 0 0 $body; if($x.Status -ne 201 -or -not $x.Digest){throw 'Manifest publication was not confirmed.'}; Write-Output $x.Digest
}finally{if(Test-Path -LiteralPath $work){Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue}}
