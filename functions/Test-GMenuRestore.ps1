$ErrorActionPreference='Stop'
$script:GMenuPayloadSource=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'GMenuPayload.cs'))
. (Join-Path $PSScriptRoot 'GMenuRuntime.ps1')
Initialize-GMenuRuntime
$root=Join-Path $PSScriptRoot ('.gmenu-work-'+[guid]::NewGuid().ToString('N'))
Protect-GMenuDirectory $root
$savedLocal=$env:LOCALAPPDATA
$passed=New-Object 'Collections.Generic.List[string]'
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAILED: $Name"};$passed.Add($Name)}
try {
    $runtimeText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'GMenuRuntime.ps1'))
    Check ($runtimeText -match '\$script:GMenuTokenRefreshAt' -and $runtimeText -match 'Get-GMenuHubToken \$Ticket\.Repository \$Credential') 'long Docker Hub restore refreshes expiring pull tokens between layers'
    Check ($runtimeText -match '\$maxAttempts=20' -and $runtimeText -match 'GRESTORE_RETRY') 'Docker Hub restore reports and retries transient download failures'
    $restoreScript=Join-Path $PSScriptRoot 'Invoke-InstalledAppDockerRestoreAndLaunch.ps1'
    $restoreTokens=$null;$restoreErrors=$null
    $restoreAst=[Management.Automation.Language.Parser]::ParseFile($restoreScript,[ref]$restoreTokens,[ref]$restoreErrors)
    $targetLabelNode=$restoreAst.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-InstalledAppDockerTargetLabel'},$true)
    Check ($null -ne $targetLabelNode) 'restore exposes a dedicated Docker target-label validator'
    . ([scriptblock]::Create($targetLabelNode.Extent.Text))
    $labelTarget='F:\backup\windowsapps\installed\HereticAI'
    $exactLabel=Test-InstalledAppDockerTargetLabel -Labels ([pscustomobject]@{'backup.source.path'=$labelTarget}) -Folder 'HereticAI' -FullTarget $labelTarget
    $legacyLabel=Join-Path (Join-Path (Join-Path $env:USERPROFILE '.gmenu') '.gmenu-work-970c6e0e85104d37970dea142e09d18a') 'HereticAI'
    $legacyCheck=Test-InstalledAppDockerTargetLabel -Labels ([pscustomobject]@{'backup.source.path'=$legacyLabel}) -Folder 'HereticAI' -FullTarget $labelTarget
    $mismatchCheck=Test-InstalledAppDockerTargetLabel -Labels ([pscustomobject]@{'backup.source.path'='C:\temp\other\HereticAI'}) -Folder 'HereticAI' -FullTarget $labelTarget
    Check ($exactLabel.Accepted -and $exactLabel.Kind -eq 'target') 'exact installed target label is accepted'
    Check ($legacyCheck.Accepted -and $legacyCheck.Kind -eq 'legacy-gmenu-work') 'strict legacy GMenu staging label is accepted for migration'
    Check (-not $mismatchCheck.Accepted -and $mismatchCheck.Kind -eq 'mismatch') 'arbitrary target-path label mismatch remains rejected'
    $source=Join-Path $root 'source';$data=Join-Path $root 'data'
    [void][IO.Directory]::CreateDirectory((Join-Path $source 'UserData'))
    [void][IO.Directory]::CreateDirectory($data)
    [IO.File]::WriteAllText((Join-Path $source 'Demo.exe'),'synthetic executable placeholder, never launched')
    [IO.File]::WriteAllText((Join-Path $source 'UserData\Local State'),'{"os_crypt":{"encrypted_key":"old-machine-placeholder"}}')
    [IO.File]::WriteAllText((Join-Path $data 'session.txt'),'fake saved session')
    $cookieKey=[GMenuPayload20260907]::Random(32)
    $meta=@{Schema=1;Folder='Demo';Launcher='Demo.exe';Arguments=@();DaymarkSyncKey=$null;Links=@();DataRoots=@(@{Environment='LOCALAPPDATA';Relative='DemoData'});WindowsKeys=@(@{Path='app\UserData\Local State';Key=[Convert]::ToBase64String($cookieKey)})}
    $meta.Links=@(@{Path='Alias';Target='UserData';Kind='Junction';DataIndex=-1},@{Path='state-alias.txt';Target='session.txt';Kind='File';DataIndex=0})
    [void](New-Item -ItemType Junction -Path (Join-Path $source 'Alias') -Target (Join-Path $source 'UserData'))
    [void](New-Item -ItemType Junction -Path (Join-Path $source 'AliasChain') -Target (Join-Path $source 'Alias'))
    $chainRecord=Get-GMenuLinkRecord $source (Get-Item -LiteralPath (Join-Path $source 'AliasChain') -Force)
    $meta.Links=@($chainRecord)+$meta.Links
    $key=[GMenuPayload20260907]::Random(32);$iv=[GMenuPayload20260907]::Random(16);$macKey=[GMenuPayload20260907]::Random(32)
    $tree=Join-Path $root 'registry'
    [void][IO.Directory]::CreateDirectory((Join-Path $tree 'home'))
    $part=Join-Path $tree 'home\gmenu-payload-00000.bin'
    $counts=[GMenuPayload20260907]::Pack([string[]]@($source,$data),($meta | ConvertTo-Json -Depth 10 -Compress),$part,$key,$iv)
    $script:GMenuFixtureLayer=Join-Path $root 'fixture-layer.tar'
    & (Join-Path $env:SystemRoot 'System32\tar.exe') -cf $script:GMenuFixtureLayer -C $tree home
    if($LASTEXITCODE -ne 0){throw 'Fixture layer generation failed'}
    $registryManifest=@{schemaVersion=2;layers=@(@{digest=('sha256:'+([GMenuPayload20260907]::Hash($script:GMenuFixtureLayer)));size=(Get-Item -LiteralPath $script:GMenuFixtureLayer).Length})}
    $manifestFile=Join-Path $root 'fixture-manifest.json'
    [IO.File]::WriteAllText($manifestFile,($registryManifest | ConvertTo-Json -Depth 5 -Compress),(New-Object Text.UTF8Encoding($false)))
    $ticket=[pscustomobject]@{Folder='Demo';Repository='michadockermisha/gmenu-test';Digest=('sha256:'+([GMenuPayload20260907]::Hash($manifestFile)));Target=(Join-Path $root 'restore');Key=[Convert]::ToBase64String($key);IV=[Convert]::ToBase64String($iv);MacKey=[Convert]::ToBase64String($macKey);Mac=[GMenuPayload20260907]::Mac($part,$macKey);Bytes=$counts[1];Files=$counts[0];Parts=@(@{Name='gmenu-payload-00000.bin';Length=(Get-Item -LiteralPath $part).Length;Sha256=[GMenuPayload20260907]::Hash($part)})}
    # Fixture transport only. The complete production digest/decrypt/extract/replace path runs below.
    function Get-GMenuLocalHubCredential{return $null}
    function Get-GMenuHubToken{return 'synthetic-token'}
    function Receive-GMenuHttp([string]$Uri,[string]$Destination,[string]$Token,[string]$Accept){
        if($Uri -match '/manifests/'){Copy-Item -LiteralPath $manifestFile -Destination $Destination}
        elseif($Uri -match '/blobs/'){Copy-Item -LiteralPath $script:GMenuFixtureLayer -Destination $Destination}
        else{throw 'Unexpected fixture request'}
    }
    function Stop-GMenuApp{}
    $env:LOCALAPPDATA=Join-Path $root 'new-windows-user'
    [void][IO.Directory]::CreateDirectory($env:LOCALAPPDATA)
    $result=Invoke-GMenuRestore -Ticket $ticket -RestoreOnly
    Check ($result.Status -eq 'RESTORED_NOT_LAUNCHED') 'missing-folder restore reports launch status accurately'
    Check ((Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'DemoData\session.txt') -Raw) -eq 'fake saved session') 'external app data maps to destination Windows account'
    Check ((Get-Item -LiteralPath (Join-Path $ticket.Target 'Alias')).LinkType -eq 'Junction') 'internal directory junction survives actual encrypted restore'
    Check (Test-Path -LiteralPath (Join-Path $ticket.Target 'AliasChain\Local State')) 'captured link chain survives encrypted restore before its intermediate link exists'
    Check ((Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'DemoData\state-alias.txt') -Raw) -eq 'fake saved session') 'external data file link survives actual encrypted restore'
    $restoredState=Get-Content -LiteralPath (Join-Path $ticket.Target 'UserData\Local State') -Raw | ConvertFrom-Json
    $protected=[Convert]::FromBase64String($restoredState.os_crypt.encrypted_key)
    $rewrapped=[Security.Cryptography.ProtectedData]::Unprotect($protected[5..($protected.Length-1)],$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    Check ([Convert]::ToBase64String($rewrapped) -eq [Convert]::ToBase64String($cookieKey)) 'restore rewraps saved Electron key for current Windows identity'
    [IO.File]::WriteAllText((Join-Path $ticket.Target 'newer.txt'),'preserve on failed launch')
    [IO.File]::WriteAllText((Join-Path $env:LOCALAPPDATA 'DemoData\session.txt'),'newer local session')
    function Start-GMenuApp{throw 'synthetic launch failure'}
    $rejected=$false
    try{Invoke-GMenuRestore -Ticket $ticket | Out-Null}catch{$rejected=$true}
    Check ($rejected -and (Test-Path -LiteralPath (Join-Path $ticket.Target 'newer.txt'))) 'failed launch rolls back original app'
    Check ((Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'DemoData\session.txt') -Raw) -eq 'newer local session') 'existing external session is preserved'
    Check (@(Get-ChildItem -LiteralPath $root -Directory -Force -Filter '.gmenu-*').Count -eq 0) 'successful and failed restores clean temporary work'
    $ticket.Digest='sha256:'+('0'*64)
    $rejected=$false
    try{Invoke-GMenuRestore -Ticket $ticket -RestoreOnly | Out-Null}catch{$rejected=$true}
    Check ($rejected -and (Test-Path -LiteralPath (Join-Path $ticket.Target 'newer.txt'))) 'wrong remote manifest digest rejected before replacement'
    $ticket.Digest='sha256:'+([GMenuPayload20260907]::Hash($manifestFile))
    function Start-GMenuApp {$script:GMenuLaunchHealth=[pscustomobject]@{Status='NeedsAttention';Detail='fixture host dependency missing'};return 999}
    $attention=Invoke-GMenuRestore -Ticket $ticket 3>$null
    $recovery=@(Get-ChildItem -LiteralPath $root -Directory -Force -Filter '.gmenu-previous-*')
    Check ($attention.Status -eq 'RESTORE_LAUNCHED_NEEDS_ATTENTION' -and $attention.AppHealth -eq 'NeedsAttention') 'responsive app with failed health is not reported fully ready'
    Check ($recovery.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $recovery[0].FullName 'newer.txt'))) 'unverified app health retains the previous installation for recovery'
    foreach($folder in $recovery){Remove-GMenuWork $folder.FullName $root}
    & {
        . (Join-Path $PSScriptRoot 'GMenuRuntime.ps1')
        $serviceRoot=Join-Path $root 'tailscale'
        $global:GMenuServiceTest=@{Running=$true;Tray=$true;FailStop=$false;Events=(New-Object 'Collections.Generic.List[string]')}
        function Get-GMenuOwnedServices { [pscustomobject]@{Name='FixtureService';State=if($global:GMenuServiceTest.Running){'Running'}else{'Stopped'}} }
        function Get-GMenuOwnedProcess {
            if($global:GMenuServiceTest.Running){[pscustomobject]@{Id=101;ProcessName='tailscaled';MainWindowHandle=0}}
            if($global:GMenuServiceTest.Tray){[pscustomobject]@{Id=102;ProcessName='tailscale-ipn';MainWindowHandle=0}}
        }
        function Get-Service {
            $value=[pscustomobject]@{Status=if($global:GMenuServiceTest.Running){'Running'}else{'Stopped'}}
            $value | Add-Member ScriptMethod WaitForStatus {param($status,$timeout)} -PassThru
        }
        function Stop-Service { $global:GMenuServiceTest.Events.Add('stop-service');if($global:GMenuServiceTest.FailStop){throw 'fixture stop failure'};$global:GMenuServiceTest.Running=$false }
        function Start-Service {$global:GMenuServiceTest.Events.Add('start-service');$global:GMenuServiceTest.Running=$true}
        function Stop-Process {param($Id)if($Id -ne 102){throw 'wrong process stopped'};$global:GMenuServiceTest.Events.Add('stop-tray');$global:GMenuServiceTest.Tray=$false}
        Stop-GMenuApp $serviceRoot 6>$null
        Check (-not $global:GMenuServiceTest.Running -and -not $global:GMenuServiceTest.Tray -and ($global:GMenuServiceTest.Events -join ',') -eq 'stop-service,stop-tray') 'service flush precedes Tailscale tray shutdown'
        Resume-GMenuServices $serviceRoot 6>$null
        Resume-GMenuServices $serviceRoot 6>$null
        Check ($global:GMenuServiceTest.Running -and @($global:GMenuServiceTest.Events | Where-Object {$_ -eq 'start-service'}).Count -eq 1) 'service resumes once and repeated recovery is harmless'
        $global:GMenuServiceTest.FailStop=$true;$failed=$false
        try{Stop-GMenuApp $serviceRoot 6>$null}catch{$failed=$true}
        Check ($failed -and $global:GMenuServiceTest.Running -and $global:GMenuServiceTest.Events[-1] -eq 'start-service') 'service stop failure restores previous running state'
        Remove-Variable -Name GMenuServiceTest -Scope Global
    }
    & {
        . (Join-Path $PSScriptRoot 'GMenuRuntime.ps1')
        $serviceRoot=Join-Path $root 'owned'
        $owned=Resolve-GMenuOwnedServiceBinary $serviceRoot ('"'+$serviceRoot+'\daemon.exe" --flag')
        $other=Resolve-GMenuOwnedServiceBinary $serviceRoot ('"'+$serviceRoot+'-other\daemon.exe"')
        Check ($owned -and -not $other) 'service ownership checks the full folder boundary'
    }
    & {
        . (Join-Path $PSScriptRoot 'GMenuRuntime.ps1')
        $scriptRoot=Join-Path $root "Script App [1] O'Brien";[void][IO.Directory]::CreateDirectory($scriptRoot)
        $launcher=Join-Path $scriptRoot 'Start-Fixture.ps1'
        [IO.File]::WriteAllText($launcher,'param([string]$Value) if($Value -ne "two words & literal"){exit 9}; exit 0')
        $manifest=[pscustomobject]@{Folder='ScriptFixture';LaunchKind='PowerShell';ReadinessUri=$null}
        $child=Start-GMenuScriptOrContent $scriptRoot $manifest $launcher @('two words & literal')
        Check ($child -gt 0 -and $script:GMenuLaunchHealth.Status -eq 'NotVerified') 'real script launcher preserves spaced arguments and does not invent app readiness'
        [IO.File]::WriteAllText($launcher,'exit 7')
        $failed=$false;try{Start-GMenuScriptOrContent $scriptRoot $manifest $launcher @() | Out-Null}catch{$failed=$_.Exception.Message -match 'code 7'}
        Check $failed 'real script nonzero exit propagates before restore success'
        [IO.File]::WriteAllText($launcher,'exit 0')
        $manifest.LaunchKind='HttpScript';$manifest.ReadinessUri='http://127.0.0.1:12345/health'
        function Get-GMenuOwnedListener {[pscustomobject]@{OwningProcess=54321;Port=12345}}
        function Get-GMenuWebHealth {return 'AuthenticationRequired'}
        $child=Start-GMenuScriptOrContent $scriptRoot $manifest $launcher @() 3>$null
        Check ($child -eq 54321 -and $script:GMenuLaunchHealth.Status -eq 'AuthenticationRequired') 'web login response returns owned service with authentication still required'
    }
    & {
        . (Join-Path $PSScriptRoot 'GMenuRuntime.ps1')
        $health=Get-GMenuGuardianHealth @('old Guardian pass complete.','2026-09-07 04:00:00 === Guardian pass repairAllowed=True ===','2026-09-07 04:00:01 FAILED: Missing recovery script')
        Check ($health.Status -eq 'NeedsAttention') 'old Guardian success cannot hide current startup failure'
        $health=Get-GMenuGuardianHealth @('2026-09-07 04:00:00 === Guardian pass repairAllowed=True ===','2026-09-07 04:00:01 FAILED: old failure','2026-09-07 04:05:00 === Guardian pass repairAllowed=False ===','2026-09-07 04:05:01 Guardian pass complete.')
        Check ($health.Status -eq 'Verified') 'completed latest Guardian pass supersedes old failure'
        Check ((Get-GMenuGuardianHealth @()).Status -eq 'NotVerified') 'missing Guardian log never verifies readiness'
        Check ((Get-GMenuGuardianHealth @('=== Guardian pass repairAllowed=True ===')).Status -eq 'Checking') 'incomplete Guardian verification stays pending'
        $trayRoot=Join-Path $root 'tv'
        function Get-GMenuOwnedProcess {
            [pscustomobject]@{Id=201;ProcessName='MoonlightSetupGuardian';Path=(Join-Path $trayRoot 'tizen\moonlight-setup-guardian\bin\MoonlightSetupGuardian.exe')}
            [pscustomobject]@{Id=202;ProcessName='MoonlightSetupGuardian';Path=(Join-Path $trayRoot 'other\MoonlightSetupGuardian.exe')}
        }
        $matched=@(Get-GMenuGuardianProcess $trayRoot)
        Check ($matched.Count -eq 1 -and $matched[0].Id -eq 201) 'tray adapter requires exact owned launcher path'
        $config=Join-Path $source 'Demo.runtimeconfig.json'
        [IO.File]::WriteAllText($config,'{"runtimeOptions":{"tfm":"net7.0","frameworks":[{"name":"Microsoft.WindowsDesktop.App","version":"7.0.0"}]}}')
        Initialize-GMenuGuardianRuntime (Join-Path $source 'Demo.exe')
        $first=[IO.File]::ReadAllText($config)
        Initialize-GMenuGuardianRuntime (Join-Path $source 'Demo.exe')
        Check (($first | ConvertFrom-Json).runtimeOptions.rollForward -eq 'Major' -and [IO.File]::ReadAllText($config) -eq $first) 'Guardian runtime repair is durable and idempotent'
        [IO.File]::WriteAllText($config,'{"runtimeOptions":{"tfm":"net7.0","rollForward":"Disable"}}')
        Initialize-GMenuGuardianRuntime (Join-Path $source 'Demo.exe')
        Check ((Get-Content $config -Raw | ConvertFrom-Json).runtimeOptions.rollForward -eq 'Disable') 'explicit runtime selection is preserved'
        $shutdownWindow=Select-GMenuWhisperShutdownWindow @(
            [pscustomobject]@{Handle=11;Thread=3;Title='Whisper STT'},
            [pscustomobject]@{Handle=12;Thread=3;Title=''},
            [pscustomobject]@{Handle=13;Thread=3;Title='Whisper.cpp STT'}
        )
        Check ($shutdownWindow.Handle -eq 13) 'Whisper shutdown selects its dedicated graceful-close window'
        $ambiguous=$false;try{Select-GMenuWhisperShutdownWindow @([pscustomobject]@{Handle=13;Title='Whisper.cpp STT'},[pscustomobject]@{Handle=14;Title='Whisper.cpp STT'}) | Out-Null}catch{$ambiguous=$_.Exception.Message -match 'exactly one'}
        Check $ambiguous 'Whisper shutdown refuses an ambiguous window target'
        $whisperStopRoot=Join-Path $root 'whisper shutdown fixture';[void][IO.Directory]::CreateDirectory((Join-Path $whisperStopRoot 'Startup'));[IO.File]::WriteAllBytes((Join-Path $whisperStopRoot 'Startup\WhisperSTTWatchdog.exe'),[byte[]]@(0))
        $visibleProcess=[pscustomobject]@{MainWindowHandle=99}
        Check (@(Get-GMenuGenericCloseProcess $whisperStopRoot @($visibleProcess)).Count -eq 0) 'Whisper dedicated shutdown is not raced by a generic window close'
        Check (@(Get-GMenuGenericCloseProcess (Join-Path $root 'ordinary app') @($visibleProcess)).Count -eq 1) 'ordinary GUI apps retain generic window close behavior'
        $linkRoot=Join-Path $root 'link source';[void][IO.Directory]::CreateDirectory((Join-Path $linkRoot 'snapshot'));[IO.File]::WriteAllText((Join-Path $linkRoot 'blob'),'model fixture')
        $link=[pscustomobject]@{FullName=(Join-Path $linkRoot 'snapshot\model.bin');DirectoryName=(Join-Path $linkRoot 'snapshot');PSIsContainer=$false;LinkType='SymbolicLink';Target=@('..\blob')}
        $record=Get-GMenuLinkRecord $linkRoot $link
        Restore-GMenuLink $linkRoot $record
        Check ((Get-Content -LiteralPath $link.FullName -Raw) -eq 'model fixture') 'relative model-cache symbolic link restores shared local bytes'
        $link.Target=@('..\missing-blob');$rejected=$false;try{Get-GMenuLinkRecord $linkRoot $link | Out-Null}catch{$rejected=$_.Exception.Message -match 'missing'}
        Check $rejected 'missing model bytes cannot be reported as a complete backup'
    }
    [pscustomobject]@{Status='PASSED';Tests=$passed.Count;Cases=$passed.ToArray();Transport='local fixture; no real Docker Hub claim'} | ConvertTo-Json -Depth 5
} finally {$env:LOCALAPPDATA=$savedLocal;Remove-GMenuWork $root $PSScriptRoot}
