[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)][string]$Game,
    [switch]$VerifyOnly,
    [switch]$SelfTest,
    [Parameter(DontShow = $true)][string]$BackupRoot = 'F:\backup\gamesaves'
)

$ErrorActionPreference = 'Stop'
$backupRoot = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')
$mutex = New-Object System.Threading.Mutex($false, 'Global\ReassLatestGameRestore')
$ownsMutex = $false

function Write-ReassState([string]$Stage, [string]$Text) {
    Write-Host (("REASS_PROGRESS stage={0} {1}" -f $Stage, $Text).TrimEnd()) -ForegroundColor Cyan
}

function Get-ReassHash([string]$Path) {
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'Read')
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '') }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-ReassFiles([string]$Path) {
    if ([IO.File]::Exists($Path)) { return ,(Get-Item -LiteralPath $Path -Force -ErrorAction Stop) }
    if (-not [IO.Directory]::Exists($Path)) { return @() }
    @(Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction Stop |
        Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })
}

function Get-ReassManifest([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $isFile = [IO.File]::Exists($full)
    $items = foreach ($file in @(Get-ReassFiles $full)) {
        $relative = if ($isFile) { [IO.Path]::GetFileName($full) } else { $file.FullName.Substring($full.Length).TrimStart('\') }
        [pscustomobject]@{Path=$relative;Bytes=[int64]$file.Length;Sha256=(Get-ReassHash $file.FullName)}
    }
    @($items | Sort-Object Path)
}

function Test-ReassEqual([string]$Expected, [string]$Actual) {
    $a = @(Get-ReassManifest $Expected); $b = @(Get-ReassManifest $Actual)
    if ($a.Count -ne $b.Count) { return $false }
    for ($i = 0; $i -lt $a.Count; $i++) {
        if ($a[$i].Path -cne $b[$i].Path -or $a[$i].Bytes -ne $b[$i].Bytes -or $a[$i].Sha256 -ne $b[$i].Sha256) { return $false }
    }
    $true
}

function Copy-ReassItem([string]$Source, [string]$Destination) {
    if ([IO.File]::Exists($Source)) {
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destination)) | Out-Null
        [IO.File]::Copy($Source, $Destination, $true)
        [IO.File]::SetLastWriteTimeUtc($Destination, [IO.File]::GetLastWriteTimeUtc($Source))
    } elseif ([IO.Directory]::Exists($Source)) {
        [IO.Directory]::CreateDirectory($Destination) | Out-Null
        $root = [IO.Path]::GetFullPath($Source).TrimEnd('\')
        foreach ($file in @(Get-ReassFiles $root)) {
            $relative = $file.FullName.Substring($root.Length).TrimStart('\')
            $target = Join-Path $Destination $relative
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
            [IO.File]::Copy($file.FullName, $target, $true)
            [IO.File]::SetLastWriteTimeUtc($target, $file.LastWriteTimeUtc)
        }
    } else { throw "reass: backup payload is missing: $Source" }
    if (-not (Test-ReassEqual $Source $Destination)) { throw "reass: copy verification failed: $Destination" }
}

function Remove-ReassItem([string]$Path) {
    if ([IO.File]::Exists($Path)) { [IO.File]::Delete($Path) }
    elseif ([IO.Directory]::Exists($Path)) { [IO.Directory]::Delete($Path, $true) }
}

function Move-ReassItem([string]$Source, [string]$Destination) {
    if ([IO.File]::Exists($Source)) { [IO.File]::Move($Source, $Destination) }
    elseif ([IO.Directory]::Exists($Source)) { [IO.Directory]::Move($Source, $Destination) }
    else { throw "reass: move source vanished: $Source" }
}

function Invoke-ReassReg([string[]]$Arguments) {
    $regExe = Join-Path ([Environment]::SystemDirectory) 'reg.exe'
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $regExe @Arguments 2>&1 | ForEach-Object {[string]$_})
        [pscustomobject]@{ExitCode=[int]$LASTEXITCODE;Output=($output -join ' | ')}
    } finally { $ErrorActionPreference = $previous }
}

function Assert-ReassTarget([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $root = [IO.Path]::GetPathRoot($full).TrimEnd('\')
    if ($full -ieq $root -or $full.Length -le ($root.Length + 2)) { throw "reass: unsafe restore target: $full" }
    $backupPrefix = [IO.Path]::GetFullPath($backupRoot).TrimEnd('\') + '\'
    if (($full + '\').StartsWith($backupPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "reass: target is inside backup repository: $full" }
    $full
}

function Get-ReassBackups {
    if (-not [IO.Directory]::Exists($backupRoot)) { throw "reass: backup root not found: $backupRoot" }
    foreach ($directory in Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $backupRoot -Directory -Force -ErrorAction Stop) {
        if ($directory.Name -like 'pre-restore_*' -or $directory.Name -like '*.partial-*') { continue }
        $auditPath = Join-Path $directory.FullName 'backup.json'
        if (-not [IO.File]::Exists($auditPath)) { continue }
        try {
            $audit = Get-Content -LiteralPath $auditPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $sources = @($audit.saveSources | ForEach-Object {[string]$_} | Where-Object {$_})
            if ($null -ne $audit.status -and [string]$audit.status -ine 'complete') { continue }
            $stored = @($audit.storedUnder | ForEach-Object {if ($null -ne $_) {[string]$_}})
            if ($stored.Count -ne $sources.Count) {
                $stored = @()
                $saveRoot = Join-Path $directory.FullName 'SaveGames'
                for ($index = 0; $index -lt $sources.Count; $index++) {
                    $source = $sources[$index].TrimEnd('\')
                    if ($sources.Count -eq 1) {
                        $leaf = [IO.Path]::GetFileName($source)
                        $singleFile = Join-Path $saveRoot $leaf
                        $stored += $(if ([IO.File]::Exists($singleFile) -and [int64]$audit.files -eq 1) {$leaf} else {''})
                    } else {
                        $leaf = ([IO.Path]::GetFileName($source) -replace '[\\/:*?"<>|]', '_')
                        $folder = ('{0:D2}_{1}' -f ($index + 1),$leaf)
                        $folderPath = Join-Path $saveRoot $folder
                        $filePath = Join-Path $folderPath ([IO.Path]::GetFileName($source))
                        $stored += $(if ([IO.Directory]::Exists($folderPath)) {$folder} elseif ([IO.File]::Exists($filePath)) {Join-Path $folder ([IO.Path]::GetFileName($source))} else {$folder})
                    }
                }
            }
            $createdValue = if ($audit.createdUtc) {$audit.createdUtc} else {$audit.detectedUtc}
            if (-not $audit.game -or $null -eq $createdValue -or $sources.Count -eq 0 -or $sources.Count -ne $stored.Count) { continue }
            $createdUtc = if ($createdValue -is [DateTimeOffset]) {
                $createdValue.ToUniversalTime()
            } elseif ($createdValue -is [DateTime]) {
                ([DateTimeOffset]$createdValue).ToUniversalTime()
            } else {
                [DateTimeOffset]::Parse([string]$createdValue,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
            }
            $registryKeys = @($audit.registryKeys | ForEach-Object {[string]$_} | Where-Object {$_})
            $registryFiles = @($audit.registryFiles | ForEach-Object {[string]$_} | Where-Object {$_})
            [pscustomobject]@{Directory=$directory;Audit=$audit;Sources=$sources;Stored=$stored;CreatedUtc=$createdUtc;RegistryKeys=$registryKeys;RegistryFiles=$registryFiles;RegistryResolved=@()}
        } catch { continue }
    }
}

function Test-ReassBackup($Candidate) {
    $saveRoot = Join-Path $Candidate.Directory.FullName 'SaveGames'
    if (-not [IO.Directory]::Exists($saveRoot)) { throw "reass: SaveGames payload missing: $saveRoot" }
    $files = @(Get-ReassFiles $saveRoot)
    $bytes = [int64](($files | Measure-Object Length -Sum).Sum)
    if ($null -ne $Candidate.Audit.files -and [int64]$Candidate.Audit.files -ne $files.Count) { throw 'reass: backup file count mismatch' }
    if ($null -ne $Candidate.Audit.bytes -and [int64]$Candidate.Audit.bytes -ne $bytes) { throw 'reass: backup byte count mismatch' }
    $entries = @($Candidate.Audit.fileEntries | Where-Object {$null -ne $_})
    $integrity = 'legacy-count-bytes'
    if ($entries.Count -gt 0) {
        if ($entries.Count -ne $files.Count) { throw 'reass: backup SHA256 manifest is incomplete' }
        $prefix = [IO.Path]::GetFullPath($saveRoot).TrimEnd('\') + '\'
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $entries) {
            $path = [IO.Path]::GetFullPath((Join-Path $Candidate.Directory.FullName ([string]$entry.path)))
            if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or -not [IO.File]::Exists($path) -or -not $seen.Add($path)) { throw "reass: unsafe, duplicate, or missing manifest entry: $($entry.path)" }
            if ([int64](Get-Item -LiteralPath $path -Force).Length -ne [int64]$entry.bytes -or (Get-ReassHash $path) -ine [string]$entry.sha256) { throw "reass: SHA256 mismatch: $($entry.path)" }
        }
        $integrity = 'sha256'
    }
    if ($Candidate.RegistryKeys.Count -ne $Candidate.RegistryFiles.Count) { throw 'reass: registry backup mapping is incomplete' }
    $registryEntries = @($Candidate.Audit.registryEntries | Where-Object {$null -ne $_})
    if ($registryEntries.Count -gt 0 -and $registryEntries.Count -ne $Candidate.RegistryFiles.Count) { throw 'reass: registry SHA256 manifest is incomplete' }
    $rootPrefix = [IO.Path]::GetFullPath($Candidate.Directory.FullName).TrimEnd('\') + '\'
    $resolvedRegistry = @()
    for ($i=0; $i -lt $Candidate.RegistryFiles.Count; $i++) {
        $rawPath = $Candidate.RegistryFiles[$i]
        $path = if ([IO.Path]::IsPathRooted($rawPath)) {[IO.Path]::GetFullPath($rawPath)} else {[IO.Path]::GetFullPath((Join-Path $Candidate.Directory.FullName $rawPath))}
        if (-not $path.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.File]::Exists($path)) { throw "reass: unsafe or missing registry payload: $rawPath" }
        if ($registryEntries.Count -gt 0) {
            $entry = $registryEntries[$i]
            if ([string]$entry.registryKey -ine $Candidate.RegistryKeys[$i] -or [int64](Get-Item -LiteralPath $path -Force).Length -ne [int64]$entry.bytes -or (Get-ReassHash $path) -ine [string]$entry.sha256) { throw "reass: registry SHA256 mismatch: $rawPath" }
        }
        $resolvedRegistry += $path
    }
    $Candidate.RegistryResolved = $resolvedRegistry
    if ($resolvedRegistry.Count -gt 0) {$integrity += '+registry'}
    $integrity
}

try {
    $ownsMutex = $mutex.WaitOne(0)
    if (-not $ownsMutex) { throw 'reass: another restore is already running' }
    Write-ReassState 'selecting-latest-created-backup' $(if ($Game) {"game=[$Game]"} else {'game=[any]'})
    $candidates = @(Get-ReassBackups)
    if ($Game) {
        $normalized = $Game -replace '[^A-Za-z0-9]', ''
        $candidates = @($candidates | Where-Object {([string]$_.Audit.game -ieq $Game) -or (([string]$_.Audit.game -replace '[^A-Za-z0-9]', '') -ieq $normalized)})
    }
    $selected = @($candidates | Sort-Object CreatedUtc, @{Expression={$_.Directory.LastWriteTimeUtc}} -Descending | Select-Object -First 1)
    if ($selected.Count -ne 1) { throw $(if ($Game) {"reass: no completed ass backup found for '$Game'"} else {'reass: no completed ass backup found'}) }
    $selected = $selected[0]
    Write-ReassState 'verifying-selected-backup' ("game=[{0}] created_utc={1:o} path=[{2}]" -f $selected.Audit.game,$selected.CreatedUtc,$selected.Directory.FullName)
    $integrity = Test-ReassBackup $selected
    if ($VerifyOnly -or $SelfTest) {
        Write-Output ("REASS_VERIFY_OK game=[{0}] created_utc={1:o} integrity={2} sources={3} path=[{4}]" -f $selected.Audit.game,$selected.CreatedUtc,$integrity,$selected.Sources.Count,$selected.Directory.FullName)
        $global:LASTEXITCODE = 0; return
    }

    $saveRoot = [IO.Path]::GetFullPath((Join-Path $selected.Directory.FullName 'SaveGames')).TrimEnd('\')
    $savePrefix = $saveRoot + '\'
    $plans = @()
    $targetSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    for ($i=0; $i -lt $selected.Sources.Count; $i++) {
        $target = Assert-ReassTarget $selected.Sources[$i]
        if (-not $targetSet.Add($target)) { throw "reass: duplicate restore target: $target" }
        $payload = [IO.Path]::GetFullPath((Join-Path $saveRoot $selected.Stored[$i]))
        if (($payload -ine $saveRoot -and -not $payload.StartsWith($savePrefix,[StringComparison]::OrdinalIgnoreCase)) -or (-not [IO.File]::Exists($payload) -and -not [IO.Directory]::Exists($payload))) { throw "reass: unsafe or missing mapped payload: $payload" }
        $hadTarget = [IO.File]::Exists($target) -or [IO.Directory]::Exists($target)
        $plans += [pscustomobject]@{Index=$i;Target=$target;Payload=$payload;HadTarget=$hadTarget;Preserved=$null;Stage=($target+'.reass-stage-'+[guid]::NewGuid().ToString('N'));Rollback=($target+'.reass-rollback-'+[guid]::NewGuid().ToString('N'));Swapped=$false}
    }
    foreach ($left in $plans) {
        foreach ($right in $plans) {
            if ($left.Index -eq $right.Index) { continue }
            if (($right.Target+'\').StartsWith(($left.Target.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)) { throw "reass: overlapping restore targets are unsafe: $($left.Target) and $($right.Target)" }
        }
    }
    $registryPlans = @()
    for ($i=0; $i -lt $selected.RegistryKeys.Count; $i++) {
        $key = $selected.RegistryKeys[$i].Replace('/','\')
        $key = $key -replace '(?i)^HKEY_CURRENT_USER\\','HKCU\' -replace '(?i)^HKEY_LOCAL_MACHINE\\','HKLM\'
        if ($key -notmatch '(?i)^(?:HKCU|HKLM)\\') { throw "reass: unsafe registry restore key: $key" }
        $registryPlans += [pscustomobject]@{Index=$i;Key=$key;Payload=$selected.RegistryResolved[$i];HadKey=$false;Preserved=$null;Imported=$false}
    }
    $allTargets = @($plans.Target) + @($registryPlans.Key)
    if (-not $PSCmdlet.ShouldProcess(($allTargets -join '; '),"Restore latest verified backup for $($selected.Audit.game)")) {
        Write-Output ("REASS_PREVIEW_OK game=[{0}] created_utc={1:o} sources={2} backup=[{3}]" -f $selected.Audit.game,$selected.CreatedUtc,$selected.Sources.Count,$selected.Directory.FullName)
        $global:LASTEXITCODE = 0; return
    }

    $safeGame = ([string]$selected.Audit.game -replace '[^A-Za-z0-9._-]', '_')
    $preRestore = Join-Path $backupRoot ("pre-restore_{0}_{1}_{2}" -f $safeGame,(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff'),[guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($preRestore) | Out-Null
    $receipt = [ordered]@{version=1;status='started';game=[string]$selected.Audit.game;sourceBackup=$selected.Directory.FullName;startedUtc=[DateTimeOffset]::UtcNow;targets=@()}
    $receiptPath = Join-Path $preRestore 'pre-restore.json'
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8

    try {
        foreach ($registryPlan in $registryPlans) {
            $query = Invoke-ReassReg @('query',$registryPlan.Key)
            $registryPlan.HadKey = $query.ExitCode -eq 0
            if ($registryPlan.HadKey) {
                $registryFolder = Join-Path $preRestore 'Registry'
                [IO.Directory]::CreateDirectory($registryFolder) | Out-Null
                $registryPlan.Preserved = Join-Path $registryFolder ("{0:D2}_current.reg" -f ($registryPlan.Index+1))
                $export = Invoke-ReassReg @('export',$registryPlan.Key,$registryPlan.Preserved,'/y')
                if ($export.ExitCode -ne 0 -or -not [IO.File]::Exists($registryPlan.Preserved)) { throw "reass: could not preserve current registry key '$($registryPlan.Key)': $($export.Output)" }
            }
        }
        foreach ($plan in $plans) {
            $plan.Preserved = Join-Path $preRestore ("{0:D2}_{1}" -f ($plan.Index+1),[IO.Path]::GetFileName($plan.Target))
            if ($plan.HadTarget) { Write-ReassState 'preserving-current-target' "target=[$($plan.Target)]"; Copy-ReassItem $plan.Target $plan.Preserved }
            Write-ReassState 'staging-verified-restore' ("index={0}/{1} target=[{2}]" -f ($plan.Index+1),$plans.Count,$plan.Target)
            Copy-ReassItem $plan.Payload $plan.Stage
        }
        foreach ($plan in $plans) {
            if ($plan.HadTarget) { Move-ReassItem $plan.Target $plan.Rollback }
            Move-ReassItem $plan.Stage $plan.Target
            $plan.Swapped = $true
            if (-not (Test-ReassEqual $plan.Payload $plan.Target)) { throw "reass: final target verification failed: $($plan.Target)" }
        }
        foreach ($registryPlan in $registryPlans) {
            $registryPlan.Imported = $true
            $import = Invoke-ReassReg @('import',$registryPlan.Payload)
            if ($import.ExitCode -ne 0) { throw "reass: registry restore failed for '$($registryPlan.Key)': $($import.Output)" }
            $query = Invoke-ReassReg @('query',$registryPlan.Key)
            if ($query.ExitCode -ne 0) { throw "reass: restored registry key was not found: $($registryPlan.Key)" }
        }
    } catch {
        $restoreError = $_
        $rollbackErrors = @()
        foreach ($registryPlan in @($registryPlans | Sort-Object Index -Descending)) {
            if (-not $registryPlan.Imported) { continue }
            $undo = if ($registryPlan.HadKey) {Invoke-ReassReg @('import',$registryPlan.Preserved)} else {Invoke-ReassReg @('delete',$registryPlan.Key,'/f')}
            if ($undo.ExitCode -ne 0) { $rollbackErrors += "registry rollback failed for '$($registryPlan.Key)': $($undo.Output)" }
        }
        foreach ($plan in @($plans | Sort-Object Index -Descending)) {
            try {
                if ($plan.Swapped) { Remove-ReassItem $plan.Target }
                if ($plan.HadTarget -and ([IO.File]::Exists($plan.Rollback) -or [IO.Directory]::Exists($plan.Rollback))) { Move-ReassItem $plan.Rollback $plan.Target }
            } catch { $rollbackErrors += "file rollback failed for '$($plan.Target)': $($_.Exception.Message)" }
        }
        $receipt.status='rolled-back';$receipt.failedUtc=[DateTimeOffset]::UtcNow;$receipt.error=$restoreError.Exception.Message
        if ($rollbackErrors.Count -gt 0) {$receipt.rollbackErrors=$rollbackErrors}
        $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
        if ($rollbackErrors.Count -gt 0) { throw ("reass: restore failed: {0}; rollback errors: {1}" -f $restoreError.Exception.Message,($rollbackErrors -join '; ')) }
        throw $restoreError
    } finally {
        foreach ($plan in $plans) { Remove-ReassItem $plan.Stage }
    }
    foreach ($plan in $plans) {
        try {
            if ($plan.HadTarget) { Remove-ReassItem $plan.Rollback }
        } catch { Write-ReassState 'cleanup-deferred' "path=[$($plan.Rollback)]" }
        $receipt.targets += [ordered]@{target=$plan.Target;payload=$plan.Payload;preserved=$plan.Preserved}
    }
    $receipt.registryTargets = @($registryPlans | ForEach-Object {[ordered]@{key=$_.Key;payload=$_.Payload;preserved=$_.Preserved}})
    $receipt.status='complete';$receipt.completedUtc=[DateTimeOffset]::UtcNow
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    Write-Output ("REASS_OK game=[{0}] created_utc={1:o} sources={2} pre_restore=[{3}] backup=[{4}]" -f $selected.Audit.game,$selected.CreatedUtc,$selected.Sources.Count,$preRestore,$selected.Directory.FullName)
    $global:LASTEXITCODE = 0
} catch {
    $global:LASTEXITCODE = 1
    Write-Error -ErrorRecord $_
} finally {
    if ($ownsMutex) { try {$mutex.ReleaseMutex()} catch {} }
    $mutex.Dispose()
}
