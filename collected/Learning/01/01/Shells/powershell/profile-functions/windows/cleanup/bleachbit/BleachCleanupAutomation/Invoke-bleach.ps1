# Extracted from C:\users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1.
# The live profile keeps a thin launcher and dot-sources this script.
$__extractedFunctionName = 'bleach'
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

function bleach {
    $bb = 'C:\Users\micha\AppData\Local\BleachBit\bleachbit_console.exe'
    $script:bleachStart = [datetime]::Now
    $before = (Get-PSDrive C).Used
    function ts { $e=[int]([datetime]::Now.Subtract($script:bleachStart).TotalSeconds); $mins=[int]($e/60); $secs=[int]($e%60); "[" + ("{0:D2}" -f $mins) + ":" + ("{0:D2}" -f $secs) + "]" }
    function log($msg,$col='Cyan'){ Write-Host "$(ts) $msg" -ForegroundColor $col }
    Write-Host ""
    Write-Host "=== MEGA BLEACH | TARGET: FREE 10GB IN UNDER 3 MIN ===" -ForegroundColor Magenta
    Write-Host ""
    log ("C: before: {0:N2} GB used  |  {1:N2} GB free" -f ($before/1GB),([math]::Round((Get-PSDrive C).Free/1GB,2))) Yellow
    # PHASE 1: Direct folder nukes
    Write-Host ""
    Write-Host "--- PHASE 1: DIRECT FOLDER CLEANUP ---" -ForegroundColor Yellow
    $targets = @(
        @{p="$env:TEMP";                                         label="User Temp (%TEMP%)";             recurse=$true}
        @{p="C:\Windows\Temp";                                   label="Windows Temp";                   recurse=$true}
        @{p="C:\Windows\Prefetch";                               label="Prefetch";                       recurse=$false}
        @{p="C:\Windows\Minidump";                               label="Minidumps";                      recurse=$true}
        @{p="C:\ProgramData\Microsoft\Windows\WER\ReportArchive";label="WER Reports Archive";            recurse=$true}
        @{p="C:\ProgramData\Microsoft\Windows\WER\ReportQueue";  label="WER Reports Queue";              recurse=$true}
        @{p="C:\Windows\Logs\CBS";                               label="CBS Logs";                       recurse=$true}
        @{p="C:\Windows\SoftwareDistribution\DataStore\Logs";    label="WU DataStore Logs";              recurse=$true}
        @{p="C:\Windows\LiveKernelReports";                      label="Live Kernel Reports";            recurse=$true}
        @{p="C:\ProgramData\Microsoft\Windows Defender\Scans\History\Service"; label="Defender Scan History"; recurse=$true}
        @{p="C:\Windows\system32\LogFiles";                      label="System LogFiles";                recurse=$true}
        @{p="C:\Windows\Logs\DISM";                              label="DISM Logs";                      recurse=$true}
        @{p="$env:LOCALAPPDATA\CrashDumps";                      label="App CrashDumps";                 recurse=$true}
        @{p="$env:LOCALAPPDATA\Microsoft\Windows\INetCache";     label="IE/Edge INetCache";              recurse=$true}
        @{p="$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"; label="Chrome Cache";            recurse=$true}
        @{p="$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache"; label="Chrome Code Cache"; recurse=$true}
        @{p="$env:LOCALAPPDATA\Google\Chrome\User Data\ShaderCache"; label="Chrome ShaderCache";       recurse=$true}
        @{p="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"; label="Edge Cache";            recurse=$true}
        @{p="$env:APPDATA\discord\Cache";                        label="Discord Cache";                  recurse=$true}
        @{p="$env:APPDATA\discord\Code Cache";                   label="Discord Code Cache";             recurse=$true}
        @{p="$env:APPDATA\Slack\Cache";                          label="Slack Cache";                    recurse=$true}
        @{p="$env:APPDATA\Zoom\data\Log";                        label="Zoom Logs";                      recurse=$true}
        @{p="$env:APPDATA\Microsoft\Teams\Cache";                label="Teams Cache";                    recurse=$true}
        @{p="$env:APPDATA\Microsoft\Teams\blob_storage";         label="Teams Blob Storage";             recurse=$true}
        @{p="$env:APPDATA\Microsoft\Teams\GPUCache";             label="Teams GPUCache";                 recurse=$true}
        @{p="$env:LOCALAPPDATA\npm-cache";                       label="NPM Cache";                      recurse=$true}
        @{p="$env:LOCALAPPDATA\pip\Cache";                       label="PIP Cache";                      recurse=$true}
        @{p="$env:LOCALAPPDATA\NuGet\Cache";                     label="NuGet Cache";                    recurse=$true}
        @{p="$env:LOCALAPPDATA\Microsoft\Windows\Explorer";      label="Explorer Thumbnails"; recurse=$false; filter="thumbcache_*"}
    )
    $p1freed = 0
    foreach ($t in $targets) {
        if (-not (Test-Path $t.p)) { continue }
        try {
            if ($t.filter) { $items = @(Get-ChildItem $t.p -Filter $t.filter -ErrorAction SilentlyContinue) }
            elseif ($t.recurse) { $items = @(Get-ChildItem $t.p -Recurse -Force -ErrorAction SilentlyContinue) }
            else { $items = @(Get-ChildItem $t.p -Force -ErrorAction SilentlyContinue) }
            $mb = [math]::Round(($items | Where-Object {-not $_.PSIsContainer} | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB, 1)
            if ($t.filter) { $items | Remove-Item -Force -ErrorAction SilentlyContinue }
            else { Remove-Item "$($t.p)\*" -Recurse -Force -ErrorAction SilentlyContinue }
            $p1freed += $mb
            if ($mb -gt 0.5) { log ("  [FREED] {0,-48} {1:N1} MB" -f $t.label,$mb) Green }
            else { log ("  [    ] {0,-48} 0 MB" -f $t.label) DarkGray }
        } catch { log "  [WARN] $($t.label): $_" DarkYellow }
    }
    log ("Phase 1 done -- {0:N1} MB freed" -f $p1freed) Green
    # PHASE 2: BleachBit parallel
    Write-Host ""
    Write-Host "--- PHASE 2: BLEACHBIT PARALLEL (89 CLEANERS) ---" -ForegroundColor Yellow
    if (-not (Test-Path $bb)) {
        log "BleachBit not found -- skipping" Red
    } else {
        $cls = @('system.recycle_bin','system.tmp','system.logs','system.prefetch','system.muicache','system.updates','system.memory_dump','system.clipboard','system.event_logs','system.localizations','deepscan.tmp','deepscan.ds_store','deepscan.thumbs_db','deepscan.backup','windows_explorer.thumbnails','windows_explorer.mru','windows_explorer.recent_documents','windows_explorer.run','windows_explorer.search_history','windows_explorer.shellbags','google_chrome.cache','google_chrome.dom','google_chrome.form_history','google_chrome.history','google_chrome.session','google_chrome.cookies','google_chrome.vacuum','firefox.cache','firefox.crash_reports','firefox.cookies','firefox.dom','firefox.forms','firefox.session_restore','firefox.url_history','firefox.vacuum','microsoft_edge.cache','microsoft_edge.history','microsoft_edge.dom','microsoft_edge.form_history','microsoft_edge.session','microsoft_edge.cookies','brave.cache','opera.cache','windows_media_player.cache','windows_media_player.mru','vlc.mru','winamp.mru','windows_defender.logs','windows_defender.temp','windows_defender.history','zoom.cache','zoom.logs','discord.cache','discord.history','slack.cache','slack.history','skype.installers','teamviewer.logs','microsoft_office.debug_logs','microsoft_office.mru','libreoffice.history','openofficeorg.cache','openofficeorg.recent_documents','wordpad.mru','paint.mru','winrar.history','winrar.temp','winzip.mru','flash.cache','java.cache','internet_explorer.cache','internet_explorer.downloads','internet_explorer.logs','internet_explorer.history','gimp.tmp','thunderbird.cache','thunderbird.index','adobe_reader.cache','adobe_reader.tmp','adobe_reader.recent_documents','filezilla.logs','notepadplusplus.recent_documents','notepadplusplus.session_files','7zip.history','python.cache','virtualbox.logs','putty.sessions','winscp.com.mru')
        $batchSize = 5; $batches = @()
        for ($i = 0; $i -lt $cls.Count; $i += $batchSize) { $batches += ,($cls[$i..[Math]::Min($i+$batchSize-1,$cls.Count-1)]) }
        $pDir = 'C:\ProgramData\bb_progress'
        New-Item -ItemType Directory -Path $pDir -Force | Out-Null
        $jobs = @(); $bi = 0
        foreach ($batch in $batches) {
            $bi++; $pf = "$pDir\$bi.json"
            $jobs += Start-Job -ScriptBlock {
                param($bb,$cleaners,$pf,$jid)
                $mb = 0; $res = @()
                foreach ($c in $cleaners) {
                    @{s='run';cur=$c;freed=$mb;jid=$jid} | ConvertTo-Json | Set-Content $pf
                    $out = & $bb --clean $c 2>&1; $cmb = 0
                    $out | ForEach-Object { if ($_ -match 'Disk space recovered: (\d+\.?\d*)(kB|MB|GB)') { $v=[double]$Matches[1]; if($Matches[2]-eq'GB'){$v*=1024}elseif($Matches[2]-eq'kB'){$v/=1024}; $cmb+=$v } }
                    $mb += $cmb; $res += @{c=$c;f=$cmb}
                }
                @{s='done';cur='';freed=$mb;jid=$jid;res=$res} | ConvertTo-Json -Depth 3 | Set-Content $pf; return $mb
            } -ArgumentList $bb,$batch,$pf,$bi
        }
        while ($jobs | Where-Object {$_.State -eq 'Running'}) {
            $doneC = @($jobs | Where-Object {$_.State -in @('Completed','Failed')}).Count
            $elapsed = [int]([datetime]::Now.Subtract($script:bleachStart).TotalSeconds); $bbMB = 0; $active = @()
            Get-ChildItem $pDir -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object {
                try { $p = Get-Content $_.FullName -Raw | ConvertFrom-Json; $bbMB += $p.freed; if ($p.s -eq 'run' -and $p.cur) { $active += $p.cur } } catch {}
            }
            $freed = ($before - (Get-PSDrive C).Used) / 1MB
            $pct = [int](($doneC/$jobs.Count)*100); $bar = ('#'*[int]($pct/5)).PadRight(20,'-')
            $act = if ($active.Count -gt 0) { $active[0..([Math]::Min(2,$active.Count-1))] -join ' | ' } else { 'finishing...' }
            Write-Host ("`r[{0:D3}s] [{1}] {2,3}% | {3}/{4} batches | {5:N0} MB freed | {6}" -f $elapsed,$bar,$pct,$doneC,$jobs.Count,$freed,$act).PadRight(130) -NoNewline -ForegroundColor Cyan
            Start-Sleep -Milliseconds 500
        }
        Write-Host ""
        $bbFreed = 0; $allRes = @()
        foreach ($job in $jobs) { $r = Receive-Job $job -ErrorAction SilentlyContinue; if ($r) { $bbFreed += $r }; Remove-Job $job -Force }
        Get-ChildItem $pDir -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object { try { $p = Get-Content $_.FullName -Raw | ConvertFrom-Json; if ($p.res) { $allRes += $p.res } } catch {} }
        Remove-Item $pDir -Recurse -Force -ErrorAction SilentlyContinue
        log ("BleachBit done -- {0:N1} MB freed" -f $bbFreed) Green
    }
    # PHASE 3: Cleanmgr
    Write-Host ""
    Write-Host "--- PHASE 3: CLEANMGR SILENT ---" -ForegroundColor Yellow
    log "Running cleanmgr sageset 99..." Cyan
    $sagePath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    $safeKeys = @('Temporary Files','Temporary Setup Files','Downloaded Program Files','Internet Cache Files','Recycle Bin','Thumbnails','Old ChkDsk Files','Windows Error Reporting Files','Delivery Optimization Files')
    foreach ($k in (Get-ChildItem $sagePath -ErrorAction SilentlyContinue)) { if ($safeKeys -contains $k.PSChildName) { try { Set-ItemProperty -Path $k.PSPath -Name StateFlags0099 -Value 2 -Type DWORD -ErrorAction SilentlyContinue } catch {} } }
    $cmbefore = (Get-PSDrive C).Used
    $cmproc = Start-Process 'cleanmgr.exe' -ArgumentList '/sagerun:99' -PassThru -ErrorAction SilentlyContinue
    if ($cmproc) {
        $waited = 0
        while (-not $cmproc.HasExited -and $waited -lt 90) {
            $cmf = ($cmbefore - (Get-PSDrive C).Used) / 1MB
            Write-Host ("`r[{0:D3}s] cleanmgr running... {1:N0} MB freed so far   " -f ([int]([datetime]::Now.Subtract($script:bleachStart).TotalSeconds)),$cmf) -NoNewline -ForegroundColor Cyan
            Start-Sleep -Seconds 2; $waited += 2
        }
        Write-Host ""
        log ("Cleanmgr done -- {0:N1} MB freed" -f (($cmbefore - (Get-PSDrive C).Used) / 1MB)) Green
    }
    # SUMMARY
    $after = (Get-PSDrive C).Used; $tf = ($before - $after) / 1MB; $el = [int]([datetime]::Now.Subtract($script:bleachStart).TotalSeconds)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ("  MEGA BLEACH COMPLETE in {0}s" -f $el) -ForegroundColor Green
    Write-Host ("  FREED: {0:N0} MB  ({1:N2} GB)" -f $tf,($tf/1024)) -ForegroundColor Green
    Write-Host ("  C: {0:N2} GB used  ->  {1:N2} GB used" -f ($before/1GB),($after/1GB)) -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    if ($allRes) {
        $top = $allRes | Where-Object {$_.f -gt 0.5} | Sort-Object f -Descending | Select-Object -First 12
        if ($top) { Write-Host ""; Write-Host "TOP FREED:" -ForegroundColor Yellow; $top | ForEach-Object { Write-Host ("  {0,-54} {1:N1} MB" -f $_.c,$_.f) -ForegroundColor Green } }
    }
    Write-Host ""; Write-Host "=== FINAL DISK STATE ===" -ForegroundColor Cyan
    Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Used -gt 0} | ForEach-Object { $total=($_.Used+$_.Free)/1GB; Write-Host ("{0}: {1:N2}GB total | {2:N2}GB used | {3:N2}GB free ({4}%)" -f $_.Name,$total,($_.Used/1GB),($_.Free/1GB),[int](($_.Used/($_.Used+$_.Free))*100)) }
}

& $__extractedFunctionName @__extractedArgs
