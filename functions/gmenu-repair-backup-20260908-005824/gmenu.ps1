[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Path,
    [string]$Launcher,
    [string[]]$LaunchArguments=@(),
    [string[]]$DataPath=@(),
    [switch]$Plan,
    [switch]$NoRestore,
    [switch]$VerifyRestore,
    [switch]$PassThru
)
$ErrorActionPreference='Stop'
$script:GMenuPayloadSource=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'GMenuPayload.cs'))
. (Join-Path $PSScriptRoot 'GMenuRuntime.ps1')
Initialize-GMenuRuntime
# The profile dispatcher can hot-reload its module while mmenu is running.
# Keep a private copy of the runtime resume body so a module refresh cannot
# make the cleanup path lose the service recovery command.
$gmenuResumeServicesBody = ${function:Resume-GMenuServices}
if(-not $gmenuResumeServicesBody){throw 'GMenu runtime did not provide its service recovery handler.'}
$gmenuEnsureResumeServices = {
    if(-not (Get-Command Resume-GMenuServices -CommandType Function -ErrorAction SilentlyContinue)) {
        Set-Item -LiteralPath Function:\Resume-GMenuServices -Value $gmenuResumeServicesBody -Force
    }
}
& $gmenuEnsureResumeServices
if($NoRestore -and $VerifyRestore){throw 'Use either -NoRestore or -VerifyRestore, not both.'}
Write-GMenuProgress 'prepare'
if(-not $Path) {$Path=Read-Host 'Application folder to back up'}
if(-not (Test-Path -LiteralPath $Path -PathType Container) -and -not [IO.Path]::IsPathRooted($Path) -and $Path -notmatch '[\\/]') {
    $candidate=Join-Path 'F:\backup\windowsapps\installed' $Path
    if(Test-Path -LiteralPath $candidate -PathType Container) {$Path=$candidate}
}
if(-not (Test-Path -LiteralPath $Path -PathType Container)) {throw "Application folder does not exist: $Path"}
$source=Assert-GMenuPath ((Get-Item -LiteralPath $Path -Force).FullName)
$folder=[IO.Path]::GetFileName($source)
$name='g'+($folder -replace '[^a-zA-Z0-9]','')
if($name -eq 'g' -or $name -eq 'gmenu') {throw 'Folder does not produce a valid, distinct restore function name.'}
$slug=($folder.ToLowerInvariant() -replace '[^a-z0-9._-]+','-' -replace '^[._-]+|[._-]+$','')
if(-not $slug -or $slug.Length -gt 100) {throw 'Folder cannot be mapped to a Docker Hub repository.'}
$repository='michadockermisha/'+$slug
$launch=Get-GMenuLaunchSpec $source $folder $Launcher
$relativeLauncher=$launch.Path
$launcherPath=Join-Path $source $relativeLauncher
if(-not $PSBoundParameters.ContainsKey('LaunchArguments')){$LaunchArguments=@($launch.Arguments)}
$stateRoot=Join-Path $env:USERPROFILE '.gmenu'
$commandRoot=Join-Path $stateRoot 'Commands'
$commandPath=Join-Path $commandRoot ($name+'.ps1')
$receiptPath=Join-Path $commandRoot ($name+'.receipt.json')
$existing=Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
if($existing -and $existing.CommandType -ne 'Function' -and -not (Test-Path -LiteralPath $receiptPath)) {throw "Existing command $name is a $($existing.CommandType), not an app restore function."}
$upgradeExisting=[bool]($existing -and -not (Test-Path -LiteralPath $receiptPath))
if($upgradeExisting){Write-Host ("GMENU upgrade-function name={0}; previous definition retained until publish succeeds" -f $name)}
if(Test-Path -LiteralPath $receiptPath) {
    $old=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if($old.Source -ine $source) {throw "$name belongs to a different source folder."}
}
$links=@()
$sourceFiles=New-Object 'Collections.Generic.List[IO.FileInfo]'
$scanClock=[Diagnostics.Stopwatch]::StartNew();$scanCount=0
Write-GMenuProgress 'scan-files'
Get-ChildItem -LiteralPath $source -Recurse -Force | ForEach-Object {
    $link=$_
    $scanCount++
    if($scanClock.ElapsedMilliseconds -ge 250){Write-GMenuProgress 'scan-files' $scanCount;$scanClock.Restart()}
    if(-not ($link.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        if(-not $link.PSIsContainer){$sourceFiles.Add($link)}
        return
    }
    $links+=Get-GMenuLinkRecord $source $link
}
$roots=@($source)
$dataRoots=@()
$dataCandidates=@($DataPath)
foreach($environmentName in @('APPDATA','LOCALAPPDATA','ProgramData')) {
    $base=[Environment]::GetEnvironmentVariable($environmentName)
    if($base) {
        $auto=Join-Path $base $folder
        if(Test-Path -LiteralPath $auto -PathType Container) {$dataCandidates+=$auto}
    }
}
foreach($candidate in $dataCandidates | Select-Object -Unique) {
    $data=Assert-GMenuPath $candidate
    if($data -eq $source -or $data.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)) {continue}
    if($source.StartsWith($data+'\',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $data -PathType Container)) {throw 'External data path must be an existing app-specific folder, not an ancestor of the application.'}
    $binding=$null
    foreach($environmentName in @('APPDATA','LOCALAPPDATA','ProgramData','USERPROFILE')) {
        $base=[Environment]::GetEnvironmentVariable($environmentName)
        if($base -and $data.StartsWith($base.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) {
            $binding=[pscustomobject]@{Environment=$environmentName;Relative=$data.Substring($base.TrimEnd('\').Length+1)}
            break
        }
    }
    if(-not $binding) {throw 'External data must be below the user profile or ProgramData so it can map to a fresh Windows account.'}
    if($roots -contains $data) {continue}
    foreach($link in Get-ChildItem -LiteralPath $data -Recurse -Force -Attributes ReparsePoint){$links+=Get-GMenuLinkRecord $data $link $dataRoots.Count}
    $roots+=$data;$dataRoots+=$binding
}
$scanClock=[Diagnostics.Stopwatch]::StartNew();$scanCount=0
$files=@($sourceFiles.ToArray())+@(foreach($r in $roots | Select-Object -Skip 1){Get-ChildItem -LiteralPath $r -File -Recurse -Force | ForEach-Object {
    if($_.Attributes -band [IO.FileAttributes]::ReparsePoint){return}
    $scanCount++
    if($scanClock.ElapsedMilliseconds -ge 250){Write-GMenuProgress 'scan-files' $scanCount;$scanClock.Restart()}
    $_
}})
Write-GMenuProgress 'scan-files' $files.Count ([Math]::Max(1,$files.Count))
$bytes=[long](($files | Measure-Object Length -Sum).Sum)
$manifest=[ordered]@{Schema=1;Folder=$folder;Launcher=$relativeLauncher;LaunchKind=$launch.Kind;ReadinessUri=$launch.Uri;Arguments=$LaunchArguments;DataRoots=$dataRoots;Links=$links;WindowsKeys=@();DaymarkSyncKey=$null;Source=$source}
if($Plan) {
    [pscustomobject]@{Function=$name;Source=$source;Repository=$repository;Launcher=$relativeLauncher;LaunchKind=$launch.Kind;ReadinessUri=$launch.Uri;Arguments=$LaunchArguments;Files=$files.Count;Bytes=$bytes;Junctions=$links.Count;ExternalData=$dataRoots;Encrypted=$true;RestoreRequiresDocker=$false;SessionPortability='Windows Electron keys can be rewrapped; arbitrary app/server credentials are not universally portable'}
    return
}
$mmenu=Get-Command mmenu -CommandType Function -ErrorAction SilentlyContinue
if(-not $mmenu) {
    $module=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules\CodexProfileFunctions\CodexProfileFunctions.psd1'
    if(-not (Test-Path -LiteralPath $module)) {throw 'mmenu is not loaded and its profile module is unavailable.'}
    Import-Module $module -DisableNameChecking
    Initialize-CodexProfileFunctions
}
Protect-GMenuDirectory $stateRoot
Protect-GMenuDirectory $commandRoot
$id=[guid]::NewGuid().ToString('N')
$parent=[IO.Path]::GetDirectoryName($source)
$workParent=$stateRoot
$work=Join-Path $workParent ('.gmenu-work-'+$id)
if($env:GMENU_RESUME_WORK) {
    $resume=Assert-GMenuPath $env:GMENU_RESUME_WORK
    if([IO.Path]::GetDirectoryName($resume) -ne $workParent -or [IO.Path]::GetFileName($resume) -notmatch '^\.gmenu-work-[a-f0-9]{32}$' -or
       @(Get-ChildItem -LiteralPath $resume -Force | Where-Object Name -NotMatch '^snapshot-[0-9]+$').Count) {throw 'Only an unpublished snapshot workspace can be resumed.'}
    $work=$resume
}
Protect-GMenuDirectory $work
$pending=Join-Path $stateRoot ('Pending-'+$id+'.json')
$wasRunning=@(Get-GMenuOwnedProcess $source).Count -gt 0
$published=$false;$completed=$false;$payloadCreated=$false
$appWasStopped=$false;$appWasRestarted=$false
try {
    $manifest.WindowsServices=@(Get-GMenuServiceManifest $source)
    Stop-GMenuApp $source
    $appWasStopped=$true
    foreach($file in $files | Where-Object { $_.Name -eq 'Local State' -and -not $_.FullName.StartsWith($source+'\Archive\',[StringComparison]::OrdinalIgnoreCase) }) {
        $state=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        if($state.os_crypt -and $state.os_crypt.app_bound_encrypted_key) {throw 'This app uses machine-bound app encryption; a verified application migration adapter is required.'}
        if($state.os_crypt -and $state.os_crypt.encrypted_key) {
            $protected=[Convert]::FromBase64String([string]$state.os_crypt.encrypted_key)
            if([Text.Encoding]::ASCII.GetString($protected,0,5) -ne 'DPAPI') {throw 'Unsupported saved Windows session key format.'}
            $clear=[Security.Cryptography.ProtectedData]::Unprotect($protected[5..($protected.Length-1)],$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
            $keyPath=$null
            for($rootIndex=0;$rootIndex -lt $roots.Count;$rootIndex++) {
                if($file.FullName.StartsWith($roots[$rootIndex]+'\',[StringComparison]::OrdinalIgnoreCase)) {
                    $prefix=if($rootIndex -eq 0){'app\'}else{'data'+($rootIndex-1)+'\'}
                    $keyPath=$prefix+$file.FullName.Substring($roots[$rootIndex].Length+1);break
                }
            }
            if(-not $keyPath){throw 'Could not map a Windows session key into the backup.'}
            try { $manifest.WindowsKeys += [pscustomobject]@{Path=$keyPath;Key=[Convert]::ToBase64String($clear)} }
            finally {[Array]::Clear($clear,0,$clear.Length)}
        }
    }
    if($folder -ieq 'daymark') {
        $capture=Join-Path $work 'daymark-session.json'
        $node=Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
        if(-not $node) {$node=Join-Path $env:ProgramFiles 'nodejs\node.exe'}
        & $node --no-warnings (Join-Path $PSScriptRoot 'GMenuDaymarkCapture.cjs') (Join-Path $source 'UserData') $capture | Out-Host
        if($LASTEXITCODE -ne 0) {throw 'Daymark session capture failed.'}
        $session=Get-Content -LiteralPath $capture -Raw | ConvertFrom-Json
        $manifest.DaymarkSyncKey=$session.SyncKey
        Remove-Item -LiteralPath $capture -Force
    }
    $key=[GMenuPayload20260907]::Random(32);$iv=[GMenuPayload20260907]::Random(16);$macKey=[GMenuPayload20260907]::Random(32)
    $publishRoot=Join-Path $work $folder
    [void][IO.Directory]::CreateDirectory($publishRoot)
    $progress=[Action[string,long,long]]{param($phase,$done,$total) Write-GMenuProgress $phase $done $total}
    $packed=[GMenuPayload20260907]::PackParts([string[]]$roots,($manifest | ConvertTo-Json -Depth 100 -Compress),$publishRoot,$key,$iv,$macKey,256MB,$progress)
    $tag='gmenu-'+(Get-Date -Format 'yyyyMMddHHmmss')+'-'+$id.Substring(0,8)
    $ticket=[ordered]@{Schema=1;Function=$name;Folder=$folder;Target=$source;Repository=$repository;Tag=$tag;Digest=$null;Files=$packed.Files;Bytes=$packed.Bytes;Key=[Convert]::ToBase64String($key);IV=[Convert]::ToBase64String($iv);MacKey=[Convert]::ToBase64String($macKey);Mac=$packed.Mac;Parts=@($packed.Parts)}
    [IO.File]::WriteAllText($pending,($ticket | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
    $payloadCreated=$true
    & $gmenuResumeServicesBody $source
    if($wasRunning){& $gmenuEnsureResumeServices;[void](Start-GMenuApp $source $manifest -NoWait);$appWasRestarted=$true}
    $oldRepo=$env:HERMES_MMENU_REPOSITORY_OVERRIDE;$oldTag=$env:HERMES_MMENU_TAG_OVERRIDE
    $oldProgress=$env:HERMES_MMENU_GMENU
    try {
        $env:HERMES_MMENU_REPOSITORY_OVERRIDE=$repository
        $env:HERMES_MMENU_TAG_OVERRIDE=$tag
        $env:HERMES_MMENU_GMENU='1'
        Write-GMenuProgress 'publish'
        $global:LASTEXITCODE=0
        mmenu -Path $publishRoot -TargetLayerMiB 256 | Out-Host
        if($LASTEXITCODE -ne 0) {throw 'mmenu failed; no restore function was registered.'}
    } finally {$env:HERMES_MMENU_REPOSITORY_OVERRIDE=$oldRepo;$env:HERMES_MMENU_TAG_OVERRIDE=$oldTag;$env:HERMES_MMENU_GMENU=$oldProgress}
    Write-GMenuProgress 'verify-published-manifest'
    $credential=Get-GMenuLocalHubCredential
    $token=Get-GMenuHubToken $repository $credential
    $remote=Get-GMenuManifest $repository $tag $work $token
    $ticket.Digest=$remote.Digest
    $published=$true
    [IO.File]::WriteAllText($pending,($ticket | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
    $ticketBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($ticket | ConvertTo-Json -Depth 20 -Compress)))
    $sourceBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script:GMenuPayloadSource))
    $runtime=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'GMenuRuntime.ps1'))
    $header=@'
# GMENU GENERATED RESTORE COMMAND - PRIVATE RECOVERY KEY INCLUDED. Do not publish this script.
[CmdletBinding()]
param([string]$Destination,[pscredential]$Credential,[switch]$RestoreOnly)
$ErrorActionPreference='Stop'
'@
    $text=$header+[Environment]::NewLine+
        ('$script:GMenuPayloadSource=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+$sourceBase64+'''))')+[Environment]::NewLine+
        ('$script:GMenuTicket=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+$ticketBase64+''')) | ConvertFrom-Json')+[Environment]::NewLine+
        $runtime+[Environment]::NewLine+
        'Invoke-GMenuRestore -Ticket $script:GMenuTicket -Destination $Destination -Credential $Credential -RestoreOnly:$RestoreOnly'
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
    if($errors.Count) {throw 'Generated restore command failed parser validation.'}
    [IO.File]::WriteAllText(($commandPath+'.tmp'),$text,(New-Object Text.UTF8Encoding($false)))
    if(Test-Path -LiteralPath $commandPath) {
        $historyRoot=Join-Path $stateRoot ('CommandHistory\'+$name)
        Protect-GMenuDirectory $historyRoot
        $historyPath=Join-Path $historyRoot ((Get-Date -Format 'yyyyMMddHHmmss')+'-'+[guid]::NewGuid().ToString('N')+'.ps1')
        Copy-Item -LiteralPath $commandPath -Destination $historyPath
    }
    Move-Item -LiteralPath ($commandPath+'.tmp') -Destination $commandPath -Force
    Write-GMenuProgress 'save-function'
    Register-GMenuPortableCommand -Ticket ([pscustomobject]$ticket) -SourceScript $commandPath -UpgradeExisting
    $receipt=[pscustomobject]@{Function=$name;Source=$source;Repository=$repository;Tag=$tag;Digest=$ticket.Digest;Files=$ticket.Files;Bytes=$ticket.Bytes;CreatedAt=(Get-Date).ToString('o');Script=$commandPath;VerifiedRestore=$false}
    $receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    $definition=[scriptblock]::Create("& '"+$commandPath.Replace("'","''")+"' @args")
    Set-Item -LiteralPath ('Function:\global:'+$name) -Value $definition -Force
    if($VerifyRestore) {
        $restoreResult=& $commandPath -Credential $credential
        $restoreResult | Out-Host
        $receipt.VerifiedRestore=[bool](@($restoreResult | Where-Object {$_.Status -eq 'RESTORE_LAUNCHED'}).Count)
        $receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    }
    Remove-Item -LiteralPath $pending -Force
    $completed=$true
} finally {
    & $gmenuResumeServicesBody $source
    if($wasRunning -and $appWasStopped -and -not $appWasRestarted -and (Test-Path -LiteralPath $launcherPath)) {
        try {& $gmenuEnsureResumeServices;[void](Start-GMenuApp $source $manifest -NoWait)}catch{Write-Warning 'Original app did not reopen; its files remain available.'}
    }
    if($completed -or -not $payloadCreated) {Remove-GMenuWork $work $workParent}
    else {Write-Warning ('Verified encrypted pending payload retained after publish failure: '+$work+' and '+$pending)}
}
Write-GMenuProgress 'complete' 1 1
Write-Host ("GMENU_SAVED function={0} image={1}:{2}" -f $name,$repository,$tag)
if($PassThru){$receipt}
