$ErrorActionPreference='Stop'
$script:GMenuPayloadSource=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'GMenuPayload.cs'))
. (Join-Path $PSScriptRoot 'GMenuRuntime.ps1')
Initialize-GMenuRuntime
$root=Join-Path $PSScriptRoot ('.gmenu-work-'+[guid]::NewGuid().ToString('N'))
Protect-GMenuDirectory $root
$savedUser=$env:USERPROFILE;$savedMode=$env:HERMES_MMENU_GMENU
$savedData=@{APPDATA=$env:APPDATA;LOCALAPPDATA=$env:LOCALAPPDATA;ProgramData=$env:ProgramData}
$passed=New-Object 'Collections.Generic.List[string]'
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAILED: $Name"};$passed.Add($Name)}
try {
    $fixtureCode=Join-Path $root 'code';[void][IO.Directory]::CreateDirectory($fixtureCode)
    foreach($name in @('gmenu.ps1','GMenuRuntime.ps1','GMenuPayload.cs','Invoke-InstalledAppDockerRestoreAndLaunch.ps1','InstalledAppRestoreCatalog.json')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $fixtureCode}
    $override=@'
function Get-GMenuOwnedProcess {return @()}
function Stop-GMenuApp {}
function Get-GMenuLocalHubCredential {return $null}
function Get-GMenuHubToken {return 'fixture-token'}
function Get-GMenuManifest {return [pscustomobject]@{Digest=('sha256:'+('1'*64))}}
function Register-GMenuPortableCommand($Ticket,[string]$SourceScript,[switch]$UpgradeExisting) {
    if(-not (Test-Path -LiteralPath $SourceScript)){throw 'Missing generated command'}
    Save-GMenuFunctionDefinition $Ticket.Function (Join-Path $env:USERPROFILE 'saved-profile.ps1') -UpgradeExisting:$UpgradeExisting
}
function Invoke-GMenuRestore {throw 'Automatic restore must not run in the publish-only test'}
'@
    Add-Content -LiteralPath (Join-Path $fixtureCode 'GMenuRuntime.ps1') -Value $override
    $env:USERPROFILE=Join-Path $root 'user';[void][IO.Directory]::CreateDirectory($env:USERPROFILE)
    foreach($variable in $savedData.Keys){$value=Join-Path $env:USERPROFILE $variable;[void][IO.Directory]::CreateDirectory($value);[Environment]::SetEnvironmentVariable($variable,$value,'Process')}
    $app=Join-Path $root 'FixturePublish';[void][IO.Directory]::CreateDirectory($app)
    [IO.File]::WriteAllText((Join-Path $app 'FixturePublish.exe'),'synthetic executable, never launched')
    [IO.File]::WriteAllText((Join-Path $app 'Start-FixturePublish.exe'),'synthetic portable launcher, never launched')
    [IO.File]::WriteAllText((Join-Path $app 'state.txt'),'fake session fixture')
    $global:GMenuTestPushCalls=0;$global:GMenuTestFailPush=$false;$global:GMenuTestDropResume=$false
    function mmenu([string]$Path,[int]$TargetLayerMiB) {
        $global:GMenuTestPushCalls++
        if($env:HERMES_MMENU_GMENU -ne '1'){throw 'Missing scoped live progress mode'}
        if(-not @(Get-ChildItem -LiteralPath $Path -Filter 'gmenu-payload-*.bin').Count){throw 'Missing encrypted parts'}
        if(@(Get-ChildItem -LiteralPath $Path | Where-Object Extension -ne '.bin').Count){throw 'Unencrypted file reached publish directory'}
        if($global:GMenuTestDropResume){Remove-Item -LiteralPath Function:\Resume-GMenuServices -Force -ErrorAction SilentlyContinue;$global:GMenuTestDropResume=$false}
        $global:LASTEXITCODE=if($global:GMenuTestFailPush){1}else{0}
    }
    $messages=New-Object 'Collections.Generic.List[string]'
    function gFixturePublish { 'original restore command' }
    $plan=& (Join-Path $fixtureCode 'gmenu.ps1') $app -Plan 6>$null
    Check ($plan.Launcher -eq 'Start-FixturePublish.exe') 'portable app startup launcher takes precedence over same-name CLI'
    $buzz=Join-Path $root 'Buzz';[void][IO.Directory]::CreateDirectory($buzz)
    foreach($file in @('Start Buzz.cmd','Start Buzz.bat','Start Buzz.ps1','buzz.exe','buzz-desktop.exe')) {
        [IO.File]::WriteAllText((Join-Path $buzz $file),'fixture; never executed')
    }
    $buzzPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $buzz -Plan 6>$null
    Check ($buzzPlan.Launcher -eq 'Start Buzz.cmd' -and $buzzPlan.LaunchKind -eq 'Command') 'same-name shell launchers prefer cmd over bat and PowerShell and internal executables'
    $buzzOverride=& (Join-Path $fixtureCode 'gmenu.ps1') $buzz -Launcher 'Start Buzz.ps1' -Plan 6>$null
    Check ($buzzOverride.Launcher -eq 'Start Buzz.ps1' -and $buzzOverride.LaunchKind -eq 'PowerShell') 'explicit launcher overrides shell format preference'
    foreach($case in @(
        @('Jackett','Start-JackettPortable.ps1','HttpScript'),
        @('Prowlarr','Start-ProwlarrPortable.ps1','HttpScript'),
        @('FlareSolverr','Start-FlareSolverrPortable.ps1','HttpScript'),
        @('BleachBitAutoClean','Invoke-BleachAutoClean.ps1','PowerShell'),
        @('scoop','shims\scoop.cmd','Command'),
        @('qBittorrentSearchPluginsWiki','Home.md','Content'),
        @('Process Lasso','ProcessLassoLauncher.exe','Exe')
    )) {
        $caseRoot=Join-Path $root $case[0];$caseFile=Join-Path $caseRoot $case[1]
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($caseFile));[IO.File]::WriteAllText($caseFile,'fixture; never executed')
        $casePlan=& (Join-Path $fixtureCode 'gmenu.ps1') $caseRoot -Plan 6>$null
        Check ($casePlan.Launcher -eq $case[1] -and $casePlan.LaunchKind -eq $case[2]) ('registered '+$case[0]+' preserves its launcher kind')
        if($case[0] -eq 'BleachBitAutoClean'){Check ($casePlan.Arguments -contains '-SelfTest') 'catalog arguments prevent unintended default maintenance actions'}
    }
    $plugins=Join-Path $root 'qBittorrentSearchPlugins';[void][IO.Directory]::CreateDirectory($plugins);[IO.File]::WriteAllText((Join-Path $plugins 'plugin.py'),'fixture')
    $pluginPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $plugins -Plan 6>$null
    Check ($pluginPlan.LaunchKind -eq 'Directory') 'registered plugin content is restored as content without inventing an executable'
    $special=Join-Path $root "Spaced App [1] O'Brien";[void][IO.Directory]::CreateDirectory($special);[IO.File]::WriteAllText((Join-Path $special 'Run.ps1'),'fixture')
    Push-Location $root
    try {
        $specialPlan=& (Join-Path $fixtureCode 'gmenu.ps1') ".\Spaced App [1] O'Brien" -Launcher 'Run.ps1' -LaunchArguments @('two words','literal&value') -Plan 6>$null
        Check ($specialPlan.Source -eq $special -and $specialPlan.LaunchKind -eq 'PowerShell' -and $specialPlan.Arguments[1] -eq 'literal&value') 'relative paths with spaces brackets and apostrophes preserve explicit script arguments'
        Check ((Assert-GMenuPath '.\new destination') -eq (Join-Path $root 'new destination')) 'relative restore paths resolve against PowerShell location'
    }finally{Pop-Location}
    $escaped=$false;try{& (Join-Path $fixtureCode 'gmenu.ps1') $special -Launcher '..\FixturePublish\FixturePublish.exe' -Plan 6>$null | Out-Null}catch{$escaped=$true}
    Check $escaped 'launcher outside source is rejected before backup or publication'
    $tv=Join-Path $root 'tv';$tvRelative='tizen\moonlight-setup-guardian\bin\MoonlightSetupGuardian.exe'
    $tvExe=Join-Path $tv $tvRelative;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($tvExe));[IO.File]::WriteAllText($tvExe,'synthetic GUI, never launched')
    [IO.File]::WriteAllText((Join-Path $tv 'unrelated-helper.exe'),'synthetic helper')
    $tvPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $tv -Plan 6>$null
    Check ($tvPlan.Launcher -eq $tvRelative) 'TV uses registered GUI launcher despite different name and setup substring'
    $tvCommand=Join-Path $env:USERPROFILE '.gmenu\Commands\gtv.ps1';[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($tvCommand))
    [IO.File]::WriteAllText($tvCommand,"# GMENU GENERATED RESTORE COMMAND - fixture`r`nthrow 'Catalog lookup executed restore'")
    [IO.File]::WriteAllText((Join-Path $env:USERPROFILE '.gmenu\Commands\gtv.receipt.json'),'{}')
    $entry=& (Join-Path $fixtureCode 'Invoke-InstalledAppDockerRestoreAndLaunch.ps1') -Folder tv -CatalogOnly
    Check ($entry.Path -eq $tvRelative) 'catalog lookup never invokes an already registered restore command'
    $whisper=Join-Path $root 'Whisper';[void][IO.Directory]::CreateDirectory($whisper);[IO.File]::WriteAllText((Join-Path $whisper 'WhisperSTT.exe'),'synthetic GUI');[IO.File]::WriteAllText((Join-Path $whisper 'other.exe'),'synthetic helper')
    $whisperPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $whisper -Plan 6>$null
    Check ($whisperPlan.Launcher -eq 'WhisperSTT.exe') 'registered launcher selection also covers other app names'
    $nested=Join-Path $root 'NestedApp'
    foreach($relative in @('App\4.6.8\NestedApp.exe','App\4.5.1\NestedApp.exe','App\4.6.8\helper.exe','App\4.6.8\console.exe','Archive\NestedApp.exe','downloads\NestedApp.exe')) {
        $file=Join-Path $nested $relative;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file));[IO.File]::WriteAllText($file,'fixture, never launched')
    }
    $nestedPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $nested -Plan 6>$null
    Check ($nestedPlan.Launcher -eq 'App\4.6.8\NestedApp.exe') 'nested launcher uses newest release and ignores archived and downloaded copies'
    $explicitPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $nested -Plan -Launcher 'App\4.5.1\NestedApp.exe' 6>$null
    Check ($explicitPlan.Launcher -eq 'App\4.5.1\NestedApp.exe') 'explicit launcher selection overrides automatic release selection'
    $other=Join-Path $nested 'Other\NestedApp.exe';[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($other));[IO.File]::WriteAllText($other,'fixture')
    $ambiguous=$false;try{& (Join-Path $fixtureCode 'gmenu.ps1') $nested -Plan 6>$null | Out-Null}catch{$ambiguous=$_.Exception.Message -match 'Multiple installed launchers'}
    Check $ambiguous 'unrelated duplicate launcher is not selected arbitrarily'
    [IO.File]::WriteAllText((Join-Path $env:USERPROFILE 'saved-profile.ps1'),"function global:gFixturePublish { 'original restore command' }; function untouched { 'keep' }")
    $global:GMenuTestFailPush=$true;$failed=$false
    try{& (Join-Path $fixtureCode 'gmenu.ps1') $app 6>$null | Out-Null}catch{$failed=$true}
    Check ($failed -and (gFixturePublish) -eq 'original restore command' -and [IO.File]::ReadAllText((Join-Path $env:USERPROFILE 'saved-profile.ps1')).Contains('original restore command')) 'failed first publish preserves legacy function and saved profile'
    $retainedWork=@(Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.gmenu') -Filter '.gmenu-work-*' -Directory)
    $retainedPending=@(Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.gmenu') -Filter 'Pending-*.json' -File)
    Check ($retainedWork.Count -eq 1 -and $retainedPending.Count -eq 1 -and @(Get-ChildItem -LiteralPath (Join-Path $retainedWork[0].FullName 'FixturePublish') -Filter 'gmenu-payload-*.bin').Count -gt 0) 'failed publish retains its encrypted payload and pending recovery ticket'
    Remove-GMenuWork $retainedWork[0].FullName (Join-Path $env:USERPROFILE '.gmenu')
    Remove-Item -LiteralPath $retainedPending[0].FullName -Force
    $global:GMenuTestPushCalls=0;$global:GMenuTestFailPush=$false
    $result=@(& (Join-Path $fixtureCode 'gmenu.ps1') $app -PassThru 6>&1 | ForEach-Object {if($_ -is [Management.Automation.InformationRecord]){$messages.Add($_.ToString())}else{$_}})
    Check ($global:GMenuTestPushCalls -eq 1 -and $result[-1].Function -eq 'gFixturePublish') 'actual gmenu entry point invokes mmenu and returns the generated function receipt'
    Check (-not $result[-1].VerifiedRestore) 'default publish completes without invoking restore'
    Check ([IO.File]::ReadAllText((Join-Path $env:USERPROFILE 'saved-profile.ps1')).Contains('function gFixturePublish')) 'publish saves a discoverable function definition before returning'
    $savedProfile=[IO.File]::ReadAllText((Join-Path $env:USERPROFILE 'saved-profile.ps1'))
    Check ($savedProfile.Contains('function untouched') -and -not $savedProfile.Contains('original restore command') -and @(Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.gmenu\CommandHistory\ProfileSources') -Filter '*.ps1').Count -gt 0) 'legacy global function upgrades with source backup and unrelated functions preserved'
    Check (@($messages | Where-Object {$_ -match '^GMENU complete 100\.000%'}).Count -eq 1) 'completion progress follows successful publish and registration'
    Check (@(Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.gmenu') -Filter '.gmenu-work-*').Count -eq 0) 'publish returns after removing its temporary payload work'
    Check ($env:HERMES_MMENU_GMENU -eq $savedMode) 'publish restores caller environment settings'
    $global:GMenuTestDropResume=$true;$dropResult=@(& (Join-Path $fixtureCode 'gmenu.ps1') $app -PassThru 6>$null | Where-Object {$_ -isnot [Management.Automation.ErrorRecord]})
    Check ($dropResult[-1].Function -eq 'gFixturePublish') 'publish cleanup survives dispatcher module refresh that removes the named resume command'
    $command=$result[-1].Script;$before=[GMenuPayload20260907]::Hash($command)
    $global:GMenuTestFailPush=$true;$failed=$false
    try{& (Join-Path $fixtureCode 'gmenu.ps1') $app 6>$null | Out-Null}catch{$failed=$true}
    Check ($failed -and [GMenuPayload20260907]::Hash($command) -eq $before) 'failed push preserves the previously saved restore command'
    $dispatch=Join-Path $env:USERPROFILE '.gmenu\Commands\gDispatchFixture.ps1'
    [IO.File]::WriteAllText($dispatch,"# GMENU GENERATED RESTORE COMMAND - synthetic fixture`r`n'NEW_MANAGED_BACKUP'")
    [IO.File]::WriteAllText((Join-Path $env:USERPROFILE '.gmenu\Commands\gDispatchFixture.receipt.json'),'{}')
    $route=& (Join-Path $PSScriptRoot 'Invoke-InstalledAppDockerRestoreAndLaunch.ps1') -Folder DispatchFixture
    Check ($route -eq 'NEW_MANAGED_BACKUP') 'legacy cached wrapper dispatches to newly registered gmenu backup'
    $managed=Join-Path $env:USERPROFILE '.gmenu\Commands\gtailscale.ps1'
    [IO.File]::WriteAllText($managed,"# GMENU GENERATED RESTORE COMMAND - synthetic fixture`r`n'MANAGED_LOADER_ROUTE'")
    [IO.File]::WriteAllText((Join-Path $env:USERPROFILE '.gmenu\Commands\gtailscale.receipt.json'),'{}')
    . (Join-Path $PSScriptRoot 'InstalledAppRestoreFunctions.ps1')
    Check ((gtailscale) -eq 'MANAGED_LOADER_ROUTE') 'installed-app loader preserves the managed restore function during profile reload'

    # Execute production upload orchestration with deterministic workers. One fails;
    # its healthy peer must complete without being cancelled or restarted.
    $mmenuPath=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\mmenu_chunked_push.ps1'
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($mmenuPath,[ref]$tokens,[ref]$errors)
    foreach($name in @('Invoke-MmenuCCurlRegistryPushLayersUntilSuccess','Write-MmenuCDashboard')) {
        $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name}.GetNewClosure(),$true)
        . ([scriptblock]::Create($node.Extent.Text))
    }
    $layerPushAst=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-MmenuCCurlRegistryPushLayersUntilSuccess'},$true)
    Check ($layerPushAst.Extent.Text -notmatch 'overallDeadline|Registry upload deadline exceeded') 'large multilayer registry push has no fixed wall-clock cutoff while byte-progress guards remain active'
    $env:HERMES_MMENU_GMENU='1';$EntryPoint='fixture';$script:TokenCalls=0;$script:UploadStarts=@{};$script:CancelledHealthy=0
    [IO.File]::WriteAllText((Join-Path $root 'docker-credential-desktop.exe'),'fixture')
    $layerA=Join-Path $root 'a.tar';$layerB=Join-Path $root 'b.tar'
    [IO.File]::WriteAllText($layerA,'a');[IO.File]::WriteAllText($layerB,'bb')
    function Get-MmenuCWindowsRoot {return $env:SystemRoot}
    function Split-MmenuCImageRef {return @{Repository='fixture/test';Tag='fixture'}}
    function Get-MmenuCFileSha256WithProgress {param($FilePath)return 'sha256:'+([GMenuPayload20260907]::Hash($FilePath))}
    function Get-MmenuCDockerHubToken {$script:TokenCalls++;$script:MmenuCTokenRefreshAt=(Get-Date).AddMinutes(1);return 'fixture-token'}
    function Test-MmenuCRegistryBlobExists {return $false}
    function Start-MmenuCRegistryUpload {return 'https://registry.invalid/upload'}
    function Add-MmenuCRegistryDigestQuery {return 'https://registry.invalid/upload'}
    function Start-MmenuCRegistryCurlUploadProcess {
        param($CurlExe,$UploadUri,$Token,$FilePath,$LayerName)
        if(-not $script:UploadStarts.ContainsKey($LayerName)){$script:UploadStarts[$LayerName]=0};$script:UploadStarts[$LayerName]++
        $exitCode=if($LayerName -eq 'b.tar' -and $script:UploadStarts[$LayerName] -eq 1){22}else{0}
        $process=[pscustomobject]@{HasExited=$true;ExitCode=$exitCode;StandardError=(New-Object IO.StringReader('fixture 401'))}
        return [pscustomobject]@{Process=$process;FileSize=(Get-Item $FilePath).Length;LastReadBytes=0;BaselineRead=0;LayerName=$LayerName}
    }
    function Get-MmenuCProcessReadBytes {return 0}
    function Update-MmenuCLowSpeedGuard {return $false}
    function Remove-MmenuCRegistryCurlUploadProcessFiles {param($Upload)if($Upload.LayerName -eq 'a.tar' -and $script:UploadStarts['b.tar'] -eq 1 -and $Upload.Process.ExitCode -ne 0){$script:CancelledHealthy++}}
    function Invoke-MmenuCRegistryPutBlobBytes {return @{Digest=('sha256:'+('2'*64));Size=1}}
    function Invoke-MmenuCRegistryWebRequest {}
    function Write-MmenuC {}
    $code=Invoke-MmenuCCurlRegistryPushLayersUntilSuccess -DockerExe (Join-Path $root 'docker.exe') -LayerPaths @($layerA,$layerB) -ImageRef 'fixture/test:fixture' -Labels @{} 6>$null
    Check ($code -eq 0 -and $script:UploadStarts['b.tar'] -eq 2 -and $script:UploadStarts['a.tar'] -eq 1 -and $script:CancelledHealthy -eq 0) 'failed layer retries without restarting healthy parallel upload'
    Check ($script:TokenCalls -ge 3) '401 upload failure refreshes the token before retry'
    $display=(& {Write-MmenuCDashboard -Name 'fixture' -Phase 'test' -Started (Get-Date).AddSeconds(-1) -DoneBytes 1 -TotalBytes 3} 6>&1 | Out-String)
    Check ($display -match '33\.333%') 'mmenu upload dashboard preserves three decimal precision'
    $largeDisplay=(& {Write-MmenuCDashboard -Name 'fixture' -Phase 'large-test' -Started (Get-Date).AddSeconds(-1) -DoneBytes 3GB -TotalBytes 4GB} 6>&1 | Out-String)
    Check ($largeDisplay -match '75\.000%') 'progress accepts payload sizes above the 32-bit integer limit'
    [pscustomobject]@{Status='PASSED';PowerShell=$PSVersionTable.PSVersion.ToString();Tests=$passed.Count;Cases=$passed.ToArray();Transport='isolated fixture; no app backup or registry mutation'} | ConvertTo-Json -Depth 5
}finally {
    $env:USERPROFILE=$savedUser;$env:HERMES_MMENU_GMENU=$savedMode
    foreach($variable in $savedData.Keys){[Environment]::SetEnvironmentVariable($variable,$savedData[$variable],'Process')}
    Remove-Item -LiteralPath 'Function:\gFixturePublish' -ErrorAction SilentlyContinue
    Remove-GMenuWork $root $PSScriptRoot
}
