# Extracted from C:\users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1.
# The live profile keeps a thin launcher and dot-sources this script.
$__extractedFunctionName = 'ccc5'
$__extractedScriptPath = $PSCommandPath
$__extractedArgs = @($args)
if ($__extractedArgs -contains '-SelfTest') {
    [pscustomobject]@{
        Script = $__extractedScriptPath
        Exists = (Test-Path -LiteralPath $__extractedScriptPath)
        Function = $__extractedFunctionName
        Mode = 'SelfTest'
    }
    return
}

function ccc5 {
    $ErrorActionPreference='SilentlyContinue'; $ProgressPreference='SilentlyContinue'
    $t=Get-Date; $freed=0
    function SZ($p){if(Test-Path $p -EA 0){(Get-ChildItem $p -Recurse -Force -EA 0|Measure-Object Length -Sum -EA 0).Sum}else{0}}
    function FR($label,$paths){$b=0;foreach($p in $paths){if(Test-Path $p -EA 0){$s=SZ $p;if($s -gt 0){Write-Host "    $p ($([math]::Round($s/1MB))MB)" -ForegroundColor DarkGray};$b+=$s;Get-ChildItem $p -Force -EA 0|Remove-Item -Recurse -Force -EA 0}};$script:freed+=$b;if($b -gt 0){Write-Host "  -> $label freed: $([math]::Round($b/1MB))MB" -ForegroundColor $(if($b -gt 50MB){'Green'}elseif($b -gt 1MB){'Yellow'}else{'Gray'})}}

    Write-Host '==========================================================' -ForegroundColor Magenta
    Write-Host '=== CCC5: ULTIMATE OLD-VERSION PURGE (ALL APPS ON C:) ===' -ForegroundColor Magenta
    Write-Host '==========================================================' -ForegroundColor Magenta
    Write-Host "Started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor White

    $volBefore=(Get-Volume -DriveLetter C -EA 0).SizeRemaining

    # [1/14] WINDOWS COMPONENT STORE (WinSxS) - old superseded components
    Write-Host '[1/14] WinSxS component cleanup...' -ForegroundColor Cyan
    $jDism=Start-Job{dism /online /cleanup-image /startcomponentcleanup /resetbase 2>&1|Select-Object -Last 3}
    $dismWaitStarted = Get-Date
    $done = $null
    while (-not $done) {
        $done = Wait-Job $jDism -Timeout 1 -EA 0
        $waited = [int]((Get-Date) - $dismWaitStarted).TotalSeconds
        if ($done) { break }
        Write-Host ("    DISM component cleanup still running: waited={0}s timeout=120s jobState={1}" -f $waited, $jDism.State) -ForegroundColor DarkGray
        if ($waited -ge 120) { break }
    }
    if($done){$out=Receive-Job $jDism -EA 0;$out|ForEach-Object{Write-Host "    $_" -ForegroundColor DarkGray}}
    else{Stop-Job $jDism -EA 0;Write-Host "    DISM: timeout after 120s; stopped this ccc5 background job and continued." -ForegroundColor Yellow}
    Remove-Job $jDism -Force -EA 0

    # [2/14] WINDOWS.OLD
    Write-Host '[2/14] Windows.old removal...' -ForegroundColor Cyan
    if(Test-Path 'C:\Windows.old'){
        $s=SZ 'C:\Windows.old';$script:freed+=$s
        Write-Host "    Windows.old ($([math]::Round($s/1GB,2))GB)" -ForegroundColor DarkGray
        takeown /F 'C:\Windows.old' /R /D Y 2>$null|Out-Null
        icacls 'C:\Windows.old' /grant Administrators:F /T 2>$null|Out-Null
        Remove-Item 'C:\Windows.old' -Recurse -Force -EA 0
    } else {Write-Host '    Not found - skipped' -ForegroundColor DarkGray}

    # [3/14] WINDOWS INSTALLER PATCH CACHE
    Write-Host '[3/14] Installer patch cache...' -ForegroundColor Cyan
    FR 'PatchCache' @('C:\Windows\Installer\$PatchCache$')

    # [4/14] WINDOWS UPDATE DOWNLOADS
    Write-Host '[4/14] Windows Update downloads...' -ForegroundColor Cyan
    Stop-Service wuauserv -Force -EA 0
    FR 'WUDownloads' @('C:\Windows\SoftwareDistribution\Download')
    Start-Service wuauserv -EA 0

    # [5/14] APPDATA\LOCAL - OLD VERSIONED FOLDERS (Chrome, Edge, Discord, Teams, etc.)
    Write-Host '[5/14] AppData\Local old versions...' -ForegroundColor Cyan
    $b=$freed
    Get-ChildItem "$env:LOCALAPPDATA" -Directory -EA 0 | ForEach-Object {
        $app=$_.FullName
        $verDirs=@(Get-ChildItem $app -Directory -EA 0 | Where-Object{$_.Name -match '^\d+\.\d+[\.\d]*'})
        if($verDirs.Count -gt 1){
            $sorted=@($verDirs|Sort-Object{try{[version]($_.Name -replace '[^\d\.]','')}catch{[version]'0.0'}} -EA 0)
            $old=$sorted|Select-Object -SkipLast 1
            foreach($d in $old){$s=SZ $d.FullName;$script:freed+=$s;Write-Host "    $($d.FullName) ($([math]::Round($s/1MB))MB)" -ForegroundColor DarkGray;Remove-Item $d.FullName -Recurse -Force -EA 0}
        }
    }
    Write-Host "  -> AppData old versions freed: $([math]::Round(($freed-$b)/1MB))MB" -ForegroundColor Green

    # [6/14] PROGRAMDATA - OLD VERSIONED FOLDERS
    Write-Host '[6/14] ProgramData old versions...' -ForegroundColor Cyan
    $b=$freed
    Get-ChildItem 'C:\ProgramData' -Directory -EA 0 | ForEach-Object {
        $app=$_.FullName
        $verDirs=@(Get-ChildItem $app -Directory -EA 0 | Where-Object{$_.Name -match '^\d+\.\d+[\.\d]*'})
        if($verDirs.Count -gt 1){
            $sorted=@($verDirs|Sort-Object{try{[version]($_.Name -replace '[^\d\.]','')}catch{[version]'0.0'}} -EA 0)
            $old=$sorted|Select-Object -SkipLast 1
            foreach($d in $old){$s=SZ $d.FullName;$script:freed+=$s;Write-Host "    $($d.FullName) ($([math]::Round($s/1MB))MB)" -ForegroundColor DarkGray;Remove-Item $d.FullName -Recurse -Force -EA 0}
        }
    }
    Write-Host "  -> ProgramData old versions freed: $([math]::Round(($freed-$b)/1MB))MB" -ForegroundColor Green

    # [7/14] .NET RUNTIMES - KEEP ONLY LATEST PER FRAMEWORK
    Write-Host '[7/14] .NET old runtimes...' -ForegroundColor Cyan
    $b=$freed
    foreach($base in @('C:\Program Files\dotnet\shared','C:\Program Files\dotnet\packs','C:\Program Files\dotnet\sdk')){
        if(Test-Path $base){
            Get-ChildItem $base -Directory -EA 0 | ForEach-Object {
                $vers=@(Get-ChildItem $_.FullName -Directory -EA 0|Sort-Object{try{[version]($_.Name -replace '[^\d\.]','')}catch{[version]'0.0'}} -EA 0)
                if($vers.Count -gt 1){$vers|Select-Object -SkipLast 1|ForEach-Object{$s=SZ $_.FullName;$script:freed+=$s;Write-Host "    $($_.FullName) ($([math]::Round($s/1MB))MB)" -ForegroundColor DarkGray;Remove-Item $_.FullName -Recurse -Force -EA 0}}
            }
        }
    }
    Write-Host "  -> .NET old versions freed: $([math]::Round(($freed-$b)/1MB))MB" -ForegroundColor Green

    # [8/14] NUGET OLD PACKAGE VERSIONS
    Write-Host '[8/14] NuGet old package versions...' -ForegroundColor Cyan
    $b=$freed
    $nugetPath="$env:USERPROFILE\.nuget\packages"
    if(Test-Path $nugetPath){
        Get-ChildItem $nugetPath -Directory -EA 0 | ForEach-Object {
            $vers=@(Get-ChildItem $_.FullName -Directory -EA 0|Sort-Object Name)
            if($vers.Count -gt 1){$vers|Select-Object -SkipLast 1|ForEach-Object{$s=SZ $_.FullName;$script:freed+=$s;Write-Host "    $($_.FullName) ($([math]::Round($s/1MB))MB)" -ForegroundColor DarkGray;Remove-Item $_.FullName -Recurse -Force -EA 0}}
        }
    }
    Write-Host "  -> NuGet old versions freed: $([math]::Round(($freed-$b)/1MB))MB" -ForegroundColor Green

    # [9/14] NPM CACHE PURGE
    Write-Host '[9/14] npm cache purge...' -ForegroundColor Cyan
    npm cache clean --force 2>$null|Out-Null
    FR 'NpmCache' @("$env:LOCALAPPDATA\npm-cache")

    # [10/14] PIP CACHE PURGE
    Write-Host '[10/14] pip cache purge...' -ForegroundColor Cyan
    pip cache purge 2>$null|Out-Null
    FR 'PipCache' @("$env:LOCALAPPDATA\pip\cache")

    # [11/14] AMD RYZEN MASTER EXTRACTED
    Write-Host '[11/14] AMD RyzenMaster extracted...' -ForegroundColor Cyan
    FR 'RyzenMaster' @("$env:LOCALAPPDATA\AMD\RyzenMasterExtracted")

    # [12/14] CHOCOLATEY OLD .NUPKG FILES
    Write-Host '[12/14] Chocolatey .nupkg cleanup...' -ForegroundColor Cyan
    $b=$freed
    Get-ChildItem "$env:ProgramData\chocolatey\lib" -Filter '*.nupkg' -Recurse -Force -EA 0 | ForEach-Object {
        $s=$_.Length;$script:freed+=$s
        Write-Host "    $($_.FullName) ($([math]::Round($s/1MB))MB)" -ForegroundColor DarkGray
        Remove-Item $_.FullName -Force -EA 0
    }
    Write-Host "  -> Chocolatey nupkg freed: $([math]::Round(($freed-$b)/1MB))MB" -ForegroundColor Green

    # [13/14] VOLUME SHADOW COPIES
    Write-Host '[13/14] Purging Volume Shadow Copies...' -ForegroundColor Cyan
    vssadmin delete shadows /all /quiet 2>$null|Out-Null
    Write-Host '    All shadow copies deleted' -ForegroundColor DarkGray

    # [14/14] TEMP + DISK CLEANUP
    Write-Host '[14/14] Temp files + Disk Cleanup...' -ForegroundColor Cyan
    FR 'WinTemp' @('C:\Windows\Temp')
    FR 'UserTemp' @("$env:TEMP")
    $vols=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\*' -EA 0
    $vols|ForEach-Object{Set-ItemProperty $_.PSPath -Name StateFlags0099 -Value 2 -EA 0}
    Start-Job { Start-Process cleanmgr -ArgumentList '/sagerun:99','/D','C' -WindowStyle Hidden -Wait -EA 0 } | Out-Null

    # SUMMARY
    $elapsed=(Get-Date)-$t
    $volAfter=(Get-Volume -DriveLetter C -EA 0).SizeRemaining
    $actualFreed=if($volBefore -and $volAfter){$volAfter-$volBefore}else{0}
    Write-Host '==========================================================' -ForegroundColor Green
    Write-Host '=== CCC5 ULTIMATE PURGE COMPLETE ===' -ForegroundColor Green
    Write-Host '==========================================================' -ForegroundColor Green
    Write-Host "Finished: $(Get-Date -Format 'HH:mm:ss') | Elapsed: $([math]::Floor($elapsed.TotalMinutes))m $($elapsed.Seconds)s" -ForegroundColor White
    Write-Host "Tracked freed: $([math]::Round($freed/1GB,2)) GB" -ForegroundColor Yellow
    if($actualFreed -gt 0){Write-Host "Actual disk freed: $([math]::Round($actualFreed/1GB,2)) GB" -ForegroundColor Yellow}
    $vol=Get-Volume -DriveLetter C -EA 0
    if($vol){$freeGB=$vol.SizeRemaining/1GB;$totalGB=$vol.Size/1GB;$pct=($vol.SizeRemaining/$vol.Size)*100;Write-Host "C: Free: $([math]::Round($freeGB,2)) GB / $([math]::Round($totalGB,2)) GB ($([math]::Round($pct,1))% free)" -ForegroundColor $(if($pct -gt 20){'Green'}elseif($pct -gt 10){'Yellow'}else{'Red'})}
}

& $__extractedFunctionName @__extractedArgs
