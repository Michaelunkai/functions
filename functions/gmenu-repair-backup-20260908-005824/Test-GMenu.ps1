$ErrorActionPreference='Stop'
$script:GMenuPayloadSource=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'GMenuPayload.cs'))
. (Join-Path $PSScriptRoot 'GMenuRuntime.ps1')
Initialize-GMenuRuntime
$root=Join-Path $PSScriptRoot ('.gmenu-work-'+[guid]::NewGuid().ToString('N'))
Protect-GMenuDirectory $root
$passed=New-Object 'Collections.Generic.List[string]'
function Check([bool]$Condition,[string]$Name) {if(-not $Condition){throw "FAILED: $Name"};$passed.Add($Name)}
try {
    $source=Join-Path $root 'source'
    [void][IO.Directory]::CreateDirectory((Join-Path $source 'empty'))
    [void][IO.Directory]::CreateDirectory((Join-Path $source 'nested'))
    [IO.File]::WriteAllText((Join-Path $source 'nested\state.json'),'{"private":"fake-session-test-only"}')
    [IO.File]::WriteAllBytes((Join-Path $source 'binary.bin'),[GMenuPayload20260907]::Random(8193))
    $key=[GMenuPayload20260907]::Random(32);$iv=[GMenuPayload20260907]::Random(16);$macKey=[GMenuPayload20260907]::Random(32)
    $encrypted=Join-Path $root 'payload.enc'
    $counts=[GMenuPayload20260907]::Pack([string[]]@($source),'{"Schema":1}',$encrypted,$key,$iv)
    $mac=[GMenuPayload20260907]::Mac($encrypted,$macKey)
    Check ($counts[0] -eq 2) 'all source files counted'
    $zip=Join-Path $root 'payload.zip'
    [GMenuPayload20260907]::Decrypt($encrypted,$zip,$key,$iv,$macKey,$mac)
    $expanded=Join-Path $root 'expanded'
    [void][IO.Directory]::CreateDirectory($expanded)
    [GMenuPayload20260907]::Extract($zip,$expanded,$counts[1],$counts[0])
    Check ([GMenuPayload20260907]::Hash((Join-Path $source 'binary.bin')) -eq [GMenuPayload20260907]::Hash((Join-Path $expanded 'app\binary.bin'))) 'encrypted round trip preserves binary bytes'
    Check (Test-Path -LiteralPath (Join-Path $expanded 'app\empty')) 'empty directories preserved'
    $wrong=[GMenuPayload20260907]::Random(32)
    $rejected=$false
    try{[GMenuPayload20260907]::Decrypt($encrypted,(Join-Path $root 'bad.zip'),$key,$iv,$wrong,$mac)}catch{$rejected=$true}
    Check ($rejected -and -not (Test-Path -LiteralPath (Join-Path $root 'bad.zip'))) 'wrong recovery key rejected before extraction'
    $stream=[IO.File]::Open($encrypted,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite)
    try{$first=$stream.ReadByte();$stream.Position=0;$stream.WriteByte([byte]($first -bxor 1))}finally{$stream.Dispose()}
    $rejected=$false
    try{[GMenuPayload20260907]::Decrypt($encrypted,(Join-Path $root 'bad.zip'),$key,$iv,$macKey,$mac)}catch{$rejected=$true}
    Check $rejected 'tampered ciphertext rejected'
    $evil=Join-Path $root 'evil.zip'
    $archive=[IO.Compression.ZipFile]::Open($evil,[IO.Compression.ZipArchiveMode]::Create)
    try{[void]$archive.CreateEntry('../escape.txt')}finally{$archive.Dispose()}
    $rejected=$false
    try{[GMenuPayload20260907]::Extract($evil,(Join-Path $root 'evil-out'),0,0)}catch{$rejected=$true}
    Check ($rejected -and -not (Test-Path -LiteralPath (Join-Path $root 'escape.txt'))) 'archive traversal rejected'
    $rejected=$false
    try{[void](Assert-GMenuPath 'C:\')}catch{$rejected=$true}
    Check $rejected 'drive-root restore rejected'
    $rejected=$false
    try{Remove-GMenuWork $source $root}catch{$rejected=$true}
    Check ($rejected -and (Test-Path -LiteralPath $source)) 'cleanup cannot delete ordinary app folder'
    $outside=Join-Path $root 'link-target'
    [void][IO.Directory]::CreateDirectory($outside)
    [IO.File]::WriteAllText((Join-Path $outside 'keep.txt'),'keep')
    $disposable=Join-Path $root ('.gmenu-stage-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($disposable)
    [void](New-Item -ItemType Junction -Path (Join-Path $disposable 'link') -Target $outside)
    Remove-GMenuWork $disposable $root
    Check (Test-Path -LiteralPath (Join-Path $outside 'keep.txt')) 'cleanup removes junction without traversing target'
    $linkPath=Join-Path $source 'cache-link'
    [void](New-Item -ItemType Junction -Path $linkPath -Target (Join-Path $source 'nested'))
    $bareLink=[pscustomobject]@{FullName=$linkPath;PSIsContainer=$true;LinkType=$null;Target=$null}
    $record=Get-GMenuLinkRecord $source $bareLink
    Check ($record.Path -eq 'cache-link' -and $record.Target -eq 'nested' -and $record.Kind -eq 'Junction') 'native junction capture works without PowerShell link metadata'
    Restore-GMenuLink (Join-Path $expanded 'app') $record
    Check (Test-Path -LiteralPath (Join-Path $expanded 'app\cache-link\state.json')) 'captured native junction restores to the captured internal target'
    $externalLink=Join-Path $source 'external-link'
    [void](New-Item -ItemType Junction -Path $externalLink -Target $outside)
    $rejected=$false
    try {Get-GMenuLinkRecord $source (Get-Item -LiteralPath $externalLink -Force)} catch {$rejected=$_.Exception.Message -like '*outside*'}
    Check $rejected 'native link capture still rejects external targets'
    $clear=[GMenuPayload20260907]::Random(32)
    $protected=[Security.Cryptography.ProtectedData]::Protect($clear,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    $unprotected=[Security.Cryptography.ProtectedData]::Unprotect($protected,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    Check ([Convert]::ToBase64String($clear) -eq [Convert]::ToBase64String($unprotected)) 'Windows session rewrap preserves underlying encryption key'
    $memberRoot=Join-Path $root 'tar-source'
    [void][IO.Directory]::CreateDirectory((Join-Path $memberRoot 'home'))
    $part=Join-Path $memberRoot 'home\gmenu-payload-00000.bin'
    [IO.File]::WriteAllBytes($part,[GMenuPayload20260907]::Random(16384))
    $tar=Join-Path $env:SystemRoot 'System32\tar.exe'
    $layer=Join-Path $root 'layer.tar'
    & $tar -cf $layer -C $memberRoot home
    if($LASTEXITCODE -ne 0){throw 'Test tar failed'}
    $out=Join-Path $root 'member.bin'
    [GMenuPayload20260907]::TarMember($tar,$layer,'home/gmenu-payload-00000.bin',$out,16384)
    Check ([GMenuPayload20260907]::Hash($part) -eq [GMenuPayload20260907]::Hash($out)) 'registry tar member copied without binary PowerShell pipeline corruption'
    $partsRoot=Join-Path $root 'fast-parts'
    $events=New-Object 'Collections.Generic.List[string]'
    $callback=[Action[string,long,long]]{param($phase,$done,$total)$events.Add(("{0}:{1}:{2}" -f $phase,$done,$total))}
    $packed=[GMenuPayload20260907]::PackParts([string[]]@($source),'{"Schema":1}',$partsRoot,$key,$iv,$macKey,1024,$callback)
    Check ($packed.Parts.Count -gt 1 -and $packed.Files -eq 2) 'fast pack splits ciphertext into multiple parts'
    $joined=Join-Path $root 'fast.enc';$output=[IO.File]::Create($joined)
    try{foreach($p in $packed.Parts){$partFile=Join-Path $partsRoot $p.Name;Check ([GMenuPayload20260907]::Hash($partFile) -eq $p.Sha256) ('streamed part checksum '+$p.Name);$input=[IO.File]::OpenRead($partFile);try{$input.CopyTo($output)}finally{$input.Dispose()}}}finally{$output.Dispose()}
    Check ([GMenuPayload20260907]::Mac($joined,$macKey) -eq $packed.Mac) 'streamed HMAC matches independent full-file HMAC'
    $fastZip=Join-Path $root 'fast.zip';[GMenuPayload20260907]::Decrypt($joined,$fastZip,$key,$iv,$macKey,$packed.Mac)
    $fastOut=Join-Path $root 'fast-out';[void][IO.Directory]::CreateDirectory($fastOut)
    [GMenuPayload20260907]::Extract($fastZip,$fastOut,$packed.Bytes,[int]$packed.Files)
    Check ([GMenuPayload20260907]::Hash((Join-Path $fastOut 'app\binary.bin')) -eq [GMenuPayload20260907]::Hash((Join-Path $source 'binary.bin'))) 'fast encrypted multipart archive restores exact binary bytes'
    Check (Test-Path -LiteralPath (Join-Path $fastOut 'app\empty')) 'fast archive preserves empty directories'
    Check (-not (Test-Path -LiteralPath (Join-Path $partsRoot 'payload.zip.partial'))) 'plaintext temporary archive removed'
    Check (@($events | Where-Object {$_ -match '^archive:|^encrypt:|^verify-snapshot:'}).Count -ge 6) 'packing reports archive, encryption and snapshot verification progress'
    $mutate=[Action[string,long,long]]{param($phase,$done,$total)if($phase -eq 'archive' -and $done -eq 0){[IO.File]::AppendAllText((Join-Path $source 'binary.bin'),'changed')}}
    $rejected=$false
    try{[void][GMenuPayload20260907]::PackParts([string[]]@($source),'{}',(Join-Path $root 'changed'),$key,$iv,$macKey,1024,$mutate)}catch{$rejected=$true}
    Check $rejected 'source mutation during archive aborts backup'
    $profileFixture=Join-Path $root 'profile.ps1'
    [IO.File]::WriteAllText($profileFixture,"function existing { 'keep' }")
    Save-GMenuFunctionDefinition 'gfixture' $profileFixture
    $beforeSave=[IO.File]::ReadAllText($profileFixture);$beforeTime=[IO.File]::GetLastWriteTimeUtc($profileFixture)
    Save-GMenuFunctionDefinition 'gfixture' $profileFixture
    Check ($beforeSave -ceq [IO.File]::ReadAllText($profileFixture) -and $beforeTime -eq [IO.File]::GetLastWriteTimeUtc($profileFixture)) 'saved function registration is idempotent'
    Check ($beforeSave.Contains('function gfixture') -and $beforeSave.Contains('function existing') -and $beforeSave.Contains('$env:USERPROFILE') -and -not $beforeSave.Contains('MacKey')) 'saved profile wrapper preserves existing commands and excludes recovery secrets'
    $rejected=$false;try{Save-GMenuFunctionDefinition 'gmenu' $profileFixture}catch{$rejected=$true}
    Check $rejected 'generated registration cannot overwrite gmenu'
    $progressText=(& {Write-GMenuProgress 'fixture' 1 3} 6>&1 | Out-String)
    Check ($progressText -match '33\.333%') 'live progress has three decimal places'
    $result=[pscustomobject]@{Status='PASSED';PowerShell=$PSVersionTable.PSVersion.ToString();Tests=$passed.Count;Cases=$passed.ToArray()}
    $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'GMenu-test-results.json') -Encoding UTF8
    $result | ConvertTo-Json -Depth 4
} finally {Remove-GMenuWork $root $PSScriptRoot}
