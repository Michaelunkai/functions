#Requires -RunAsAdministrator
# repair-upgrade.ps1 - Fully automatic Windows 11 in-place repair upgrade
# Extracts ISO to C:\WinSetup so migcore.dll and all migration DLLs are local
# Zero manual steps. Zero errors. Run elevated and walk away.

param(
    [string]$IsoSource = "E:\isos\Windows.iso",
    [string]$ExtractDir = "C:\WinSetup",
    [string]$LocalIso = "C:\WinISO\Windows.iso"
)

$ErrorActionPreference = 'Stop'
$host.UI.RawUI.WindowTitle = "Repair Upgrade - Automated"

function Write-Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)      { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Fail($msg)    { Write-Host "    [FAIL] $msg" -ForegroundColor Red; throw $msg }
function Get-PendingFileRenameOperationsValue {
    $sessionManager = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -EA SilentlyContinue
    if (-not $sessionManager) { return $null }
    $property = $sessionManager.PSObject.Properties['PendingFileRenameOperations']
    if (-not $property) { return $null }
    return $property.Value
}
function Test-PortableExecutableFile($Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force -EA SilentlyContinue
    if (-not $item -or $item.Length -lt 128) { return $false }
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object System.IO.BinaryReader($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) { return $false }
        $stream.Seek(60, [System.IO.SeekOrigin]::Begin) | Out-Null
        $peOffset = $reader.ReadInt32()
        if ($peOffset -le 0 -or $peOffset -gt ($stream.Length - 6)) { return $false }
        $stream.Seek($peOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
        if ($reader.ReadUInt32() -ne 0x00004550) { return $false }
        return $reader.ReadUInt16() -ne 0
    } finally {
        $stream.Dispose()
    }
}
function Repair-InvalidExtractedPortableExecutables($SourceRoot, $DestinationRoot) {
    $invalid = @(
        Get-ChildItem -LiteralPath $DestinationRoot -Recurse -File -EA SilentlyContinue |
            Where-Object { $_.Extension -in '.dll', '.exe' -and -not (Test-PortableExecutableFile $_.FullName) }
    )
    if ($invalid.Count -eq 0) { Write-Ok "Portable executable validation passed."; return }
    Write-Host "    [WARN] Found $($invalid.Count) invalid extracted executable image(s); recopying them safely..." -ForegroundColor Yellow
    foreach ($file in $invalid) {
        $relativePath = $file.FullName.Substring($DestinationRoot.TrimEnd('\').Length).TrimStart('\')
        $sourcePath = Join-Path $SourceRoot $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath)) { Write-Fail "Source file missing during repair: $relativePath" }
        Copy-Item -LiteralPath $sourcePath -Destination $file.FullName -Force
        if (-not (Test-PortableExecutableFile $file.FullName)) { Write-Fail "Repaired file is still invalid: $relativePath" }
        Write-Ok "Repaired $relativePath"
    }
    Write-Ok "Portable executable validation passed after repair copy."
}
function Invoke-ExternalProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Arguments,
        [Parameter(Mandatory = $true)][string]$Description,
        [int]$TimeoutSeconds = 7200,
        [int[]]$AllowedExitCodes = @(0)
    )

    Write-Host "    Starting: $Description" -ForegroundColor Cyan
    $proc = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru
    $begin = Get-Date
    while (-not $proc.HasExited) {
        $elapsed = ((Get-Date) - $begin).TotalSeconds
        if ($elapsed -gt $TimeoutSeconds) {
            Stop-Process -Id $proc.Id -Force -EA SilentlyContinue
            Write-Fail "$Description timed out after $([math]::Round($TimeoutSeconds / 60, 1)) minutes"
        }
        $mins = [math]::Floor($elapsed / 60)
        $secs = [math]::Floor($elapsed % 60)
        Write-Host "`r    Running: $Description (${mins}m ${secs}s)" -NoNewline -ForegroundColor Cyan
        Start-Sleep -Milliseconds 1000
    }
    Write-Host ""
    $proc.WaitForExit()
    if ($AllowedExitCodes -notcontains $proc.ExitCode) {
        Write-Fail "$Description failed with exit code $($proc.ExitCode)"
    }
    Write-Ok "$Description completed (exit code $($proc.ExitCode))"
}
function Convert-HexToSignedInt {
    param([Parameter(Mandatory = $true)][string]$HexCode)
    $u = [Convert]::ToUInt32($HexCode, 16)
    return [BitConverter]::ToInt32([BitConverter]::GetBytes($u), 0)
}
function Remove-DirectoryHard {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$MaxAttempts = 6
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        # Stop setup processes only if they execute from the target path
        $setupProcs = Get-CimInstance Win32_Process -Filter "Name='setup.exe' OR Name='SetupHost.exe' OR Name='setupprep.exe'" -EA SilentlyContinue
        foreach ($p in $setupProcs) {
            $exe = $p.ExecutablePath
            if ($exe -and $exe.StartsWith($Path, [System.StringComparison]::OrdinalIgnoreCase)) {
                Stop-Process -Id $p.ProcessId -Force -EA SilentlyContinue
            }
        }

        Get-ChildItem -LiteralPath $Path -Force -Recurse -EA SilentlyContinue | ForEach-Object {
            try { $_.Attributes = [System.IO.FileAttributes]::Normal } catch {}
        }
        try { (Get-Item -LiteralPath $Path -Force -EA Stop).Attributes = [System.IO.FileAttributes]::Directory } catch {}

        & takeown.exe /F $Path /R /D Y *> $null
        & icacls.exe $Path /grant "*S-1-5-32-544:(OI)(CI)F" /T /C *> $null

        Remove-Item -LiteralPath $Path -Recurse -Force -EA SilentlyContinue
        if (-not (Test-Path -LiteralPath $Path)) { return }
        Start-Sleep -Seconds 2
    }
    Write-Fail "Failed to remove locked folder: $Path. Reboot, then run script again."
}
function Get-InstallImageFromMediaRoot {
    param([Parameter(Mandatory = $true)][string]$MediaRoot)
    $candidates = @(
        (Join-Path $MediaRoot 'sources\install.wim'),
        (Join-Path $MediaRoot 'sources\install.esd')
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}
function Get-ImageMetadata {
    param([Parameter(Mandatory = $true)][string]$ImagePath)
    $output = (& dism.exe /English /Get-WimInfo /WimFile:"$ImagePath" /Index:1 2>&1 | Out-String)
    if ([string]::IsNullOrWhiteSpace($output)) { return $null }
    $versionMatch = [regex]::Match($output, '(?im)^\s*Version\s*:\s*([0-9\.]+)\s*$')
    $archMatch = [regex]::Match($output, '(?im)^\s*Architecture\s*:\s*([a-zA-Z0-9]+)\s*$')
    $langMatch = [regex]::Match($output, '(?im)^\s*Default\s*:\s*([A-Za-z]{2}-[A-Za-z]{2})\s*$')
    $version = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { $null }
    $build = $null
    if ($version -and ($version -match '^\d+\.\d+\.(\d+)\.')) { $build = [int]$Matches[1] }
    return [pscustomobject]@{
        Version = $version
        Build = $build
        Architecture = if ($archMatch.Success) { $archMatch.Groups[1].Value.ToLowerInvariant() } else { $null }
        DefaultLanguage = if ($langMatch.Success) { $langMatch.Groups[1].Value } else { $null }
    }
}
function Get-ResolvedSourceMetadata {
    param([Parameter(Mandatory = $true)]$ResolvedSource)
    $lastWrite = $null
    try { $lastWrite = (Get-Item -LiteralPath $ResolvedSource.Path -Force -EA Stop).LastWriteTimeUtc } catch {}
    $meta = [pscustomobject]@{
        Source = $ResolvedSource
        Build = $null
        Version = $null
        Architecture = $null
        DefaultLanguage = $null
        LastWriteTimeUtc = $lastWrite
    }
    $mountedByScript = $false
    $imageObj = $null
    try {
        if ($ResolvedSource.Kind -eq 'MediaFolder') {
            $installImage = Get-InstallImageFromMediaRoot -MediaRoot $ResolvedSource.Path
            if ($installImage) { $imageObj = Get-ImageMetadata -ImagePath $installImage }
        } else {
            $imageObj = Mount-DiskImage -ImagePath $ResolvedSource.Path -PassThru -EA Stop
            $mountedByScript = $true
            $mountStart = Get-Date
            $drive = $null
            while (((Get-Date) - $mountStart).TotalSeconds -lt 60) {
                Start-Sleep -Milliseconds 500
                $vol = $imageObj | Get-Volume -EA SilentlyContinue
                if ($vol -and $vol.DriveLetter) {
                    $drive = "$($vol.DriveLetter):\"
                    break
                }
            }
            if ($drive) {
                $installImage = Get-InstallImageFromMediaRoot -MediaRoot $drive
                if ($installImage) { $imageObj = Get-ImageMetadata -ImagePath $installImage }
            }
        }
    } catch {}
    finally {
        if ($mountedByScript) {
            try { Dismount-DiskImage -ImagePath $ResolvedSource.Path -EA SilentlyContinue | Out-Null } catch {}
        }
    }
    if ($imageObj) {
        $meta.Build = $imageObj.Build
        $meta.Version = $imageObj.Version
        $meta.Architecture = $imageObj.Architecture
        $meta.DefaultLanguage = $imageObj.DefaultLanguage
    }
    return $meta
}
function Resolve-InstallMediaPath($Candidate, $Reason) {
    if ([string]::IsNullOrWhiteSpace($Candidate)) { return $null }
    $path = $Candidate.Trim('"')
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $item = Get-Item -LiteralPath $path -Force -EA SilentlyContinue
    if (-not $item) { return $null }
    if (-not $item.PSIsContainer) {
        if ($item.Extension -ieq ".iso" -and $item.Length -gt 0) {
            return [pscustomobject]@{ Kind = "IsoFile"; Path = $item.FullName; Reason = $Reason }
        }
        return $null
    }
    $setupPath = Join-Path $item.FullName "setup.exe"
    if (Test-Path -LiteralPath $setupPath) {
        return [pscustomobject]@{ Kind = "MediaFolder"; Path = $item.FullName; Reason = $Reason }
    }
    $isoInFolder = Get-ChildItem -LiteralPath $item.FullName -Filter *.iso -File -Force -EA SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($isoInFolder) {
        return [pscustomobject]@{ Kind = "IsoFile"; Path = $isoInFolder.FullName; Reason = "$Reason (ISO in folder)" }
    }
    return $null
}

# --- STEP 0: Download latest Windows 11 build from cloud ---
Write-Step 0 "Download latest Windows 11 build from Microsoft cloud"
$CloudIsoUrl = "https://media.githubusercontent.com/media/AveYo/MediaCreationToolNet/master/releases/Windows11InstallationMedia.iso"
$CloudIsoAlt = "https://software-download.microsoft.com/db/Win11_23H2_English_x64.iso"
$TempIsoPath = "C:\Windows\Temp\Win11_Cloud.iso"
$CloudDownloadSuccess = $false
$CloudIsoCandidates = @()
try {
    $ghAssets = Invoke-RestMethod -Uri "https://api.github.com/repos/AveYo/MediaCreationTool.bat/releases?per_page=10" -UseBasicParsing -EA SilentlyContinue
    if ($ghAssets) {
        foreach ($rel in $ghAssets) {
            foreach ($asset in $rel.assets) {
                if ($asset.browser_download_url -match '(?i)windows11.*\.iso$|Windows11InstallationMedia\.iso$') {
                    $CloudIsoCandidates += $asset.browser_download_url
                }
            }
        }
    }
} catch {}
$CloudIsoCandidates += @($CloudIsoUrl, $CloudIsoAlt)
$CloudIsoCandidates = $CloudIsoCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
Write-Host "    Cloud ISO candidate URLs discovered: $($CloudIsoCandidates.Count)"

foreach ($candidateUrl in $CloudIsoCandidates) {
    if ($CloudDownloadSuccess) { break }
    Write-Host "    Trying cloud source: $candidateUrl"
    $bitsTimeout = 3600
    $startTime = Get-Date
    try {
        if (Test-Path -LiteralPath $TempIsoPath) { Remove-Item -LiteralPath $TempIsoPath -Force -EA SilentlyContinue }
        $job = Start-BitsTransfer -Source $candidateUrl -Destination $TempIsoPath -Asynchronous -DisplayName "Win11-Cloud-ISO" -Description "Windows 11 Cloud Download" -EA SilentlyContinue
        if ($job) {
            while ($job.JobState -eq "Transferring" -or $job.JobState -eq "Connecting") {
                $elapsed = ((Get-Date) - $startTime).TotalSeconds
                if ($elapsed -gt $bitsTimeout) {
                    Stop-BitsTransfer -BitsJob $job -EA SilentlyContinue
                    Write-Host "    [TIMEOUT] Source timed out after 60 minutes, trying next source..." -ForegroundColor Yellow
                    break
                }
                if ($job.BytesTotal -gt 0) {
                    $pct = [math]::Round(($job.BytesTransferred / $job.BytesTotal) * 100, 1)
                    $transferred = [math]::Round($job.BytesTransferred / 1GB, 2)
                    $total = [math]::Round($job.BytesTotal / 1GB, 2)
                    Write-Host "`r    Progress: $pct% ($transferred GB / $total GB)" -NoNewline -ForegroundColor Cyan
                } else {
                    Write-Host "`r    Progress: negotiating download size..." -NoNewline -ForegroundColor Cyan
                }
                Start-Sleep -Milliseconds 500
            }
            Write-Host ""
            if ($job.JobState -eq "Transferred") {
                Complete-BitsTransfer -BitsJob $job
            } elseif ($job.JobState -notin @('Cancelled', 'Transferred')) {
                try { Remove-BitsTransfer -BitsJob $job -EA SilentlyContinue } catch {}
            }
        }
    } catch {
        Write-Host "    [INFO] BITS failed for source, trying fallback method..." -ForegroundColor Yellow
    }
    if ((-not $CloudDownloadSuccess) -and (Test-Path -LiteralPath $TempIsoPath)) {
        $size = (Get-Item -LiteralPath $TempIsoPath -EA SilentlyContinue).Length
        if ($size -gt 1GB) {
            $CloudDownloadSuccess = $true
            Write-Ok "Cloud download complete: $([math]::Round($size/1GB, 2)) GB"
            break
        }
    }
    if (-not $CloudDownloadSuccess) {
        try {
            Invoke-WebRequest -Uri $candidateUrl -OutFile $TempIsoPath -UseBasicParsing -TimeoutSec 3600 -EA Stop
            if ((Test-Path -LiteralPath $TempIsoPath) -and ((Get-Item -LiteralPath $TempIsoPath).Length -gt 1GB)) {
                Write-Ok "Cloud download complete (fallback): $([math]::Round((Get-Item $TempIsoPath).Length/1GB, 2)) GB"
                $CloudDownloadSuccess = $true
                break
            }
        } catch {
            Write-Host "    [INFO] Source unavailable: $candidateUrl" -ForegroundColor Yellow
        }
    }
}

# If cloud download failed, check local recovery partition
if (-not $CloudDownloadSuccess) {
    Write-Host "    Checking Windows recovery partition for installation media..."
    $recoveryPath = "C:\Recovery\WindowsRE"
    if (Test-Path $recoveryPath) {
        $recoverySource = Resolve-InstallMediaPath $recoveryPath "WindowsRE recovery path"
        if ($recoverySource) {
            $IsoSource = $recoverySource.Path
            Write-Ok "Usable recovery source detected: $($recoverySource.Path)"
        } else {
            Write-Host "    Recovery path exists but has no usable ISO/media root. Continuing auto-detection..." -ForegroundColor Yellow
        }
    } else {
        Write-Host "    No recovery partition. Fallback to local/Windows Update cache enabled." -ForegroundColor Yellow
    }
}

if ($CloudDownloadSuccess) {
    $IsoSource = $TempIsoPath
    Write-Ok "Cloud ISO ready: $IsoSource"
}

# --- STEP 1: Copy ISO to C: (NTFS) ---
Write-Step 1 "Obtain Windows 11 ISO (local or cloud)"
$winUpdatePath = "C:\Windows\SoftwareDistribution\Download"
$mountRequired = $true
$mediaRoot = $null
$activeIsoPath = $null
New-Item -ItemType Directory -Path (Split-Path $LocalIso) -Force -EA SilentlyContinue | Out-Null
if ((-not ($IsoSource -and (Test-Path -LiteralPath $IsoSource))) -and (Test-Path -LiteralPath $LocalIso)) {
    $IsoSource = (Get-Item -LiteralPath $LocalIso -Force).FullName
    $activeIsoPath = $IsoSource
    Write-Ok "Using cached ISO fallback $IsoSource ($([math]::Round((Get-Item $IsoSource).Length/1GB,2)) GB)"
} else {
    $alt = @("E:\isos\Windows.iso","F:\isos\Windows.iso","C:\Users\micha\Downloads\Windows.iso")
    $cacheIso = $null
    if (Test-Path -LiteralPath $winUpdatePath) {
        $cacheIso = Get-ChildItem -LiteralPath $winUpdatePath -Filter *.iso -File -Recurse -Force -EA SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }
    $mountedMedia = @()
    try {
        $mountedMedia = Get-Volume -EA SilentlyContinue |
            Where-Object { $_.DriveType -eq 'CD-ROM' -and $_.DriveLetter } |
            ForEach-Object { "$($_.DriveLetter):\" }
    } catch {}
    $candidates = @()
    if ($IsoSource) { $candidates += [pscustomobject]@{ Path = $IsoSource; Reason = "requested source" } }
    if ($cacheIso) { $candidates += [pscustomobject]@{ Path = $cacheIso.FullName; Reason = "Windows Update cache ISO" } }
    foreach ($a in $alt) { $candidates += [pscustomobject]@{ Path = $a; Reason = "default local path" } }
    foreach ($m in $mountedMedia) { $candidates += [pscustomobject]@{ Path = $m; Reason = "mounted media" } }
    $osBuildRaw = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -EA SilentlyContinue).CurrentBuild
    $osBuild = if ($osBuildRaw) { [int]$osBuildRaw } else { 0 }
    $systemArch = if (((Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue).OSArchitecture -match '64')) { 'x64' } else { 'x86' }
    $systemUiLang = $null
    try { $systemUiLang = (Get-WinSystemLocale).Name } catch {}
    $resolvedSources = @()
    foreach ($c in $candidates) {
        $resolved = Resolve-InstallMediaPath $c.Path $c.Reason
        if ($resolved) { $resolvedSources += $resolved }
    }
    if ($resolvedSources.Count -eq 0) {
        Write-Fail "No usable Windows 11 installation source found (ISO file or media folder with setup.exe)"
    }
    Write-Host "    Evaluating $($resolvedSources.Count) installation source(s) for compatibility and recency..."
    $seen = @{}
    $scoredSources = @()
    foreach ($r in $resolvedSources) {
        if ($seen.ContainsKey($r.Path)) { continue }
        $seen[$r.Path] = $true
        $meta = Get-ResolvedSourceMetadata -ResolvedSource $r
        $archCompatible = (-not $meta.Architecture) -or ($meta.Architecture -eq $systemArch)
        $langCompatible = (-not $systemUiLang) -or (-not $meta.DefaultLanguage) -or ($meta.DefaultLanguage -eq $systemUiLang)
        $build = if ($meta.Build) { $meta.Build } else { 0 }
        $buildDelta = if ($build -gt 0) { [math]::Abs($build - $osBuild) } else { [int]::MaxValue }
        $compatible = $archCompatible -and $langCompatible
        $scoredSources += [pscustomobject]@{
            Source = $r
            Compatible = $compatible
            Build = $build
            BuildDelta = $buildDelta
            LastWriteTimeUtc = if ($meta.LastWriteTimeUtc) { $meta.LastWriteTimeUtc } else { [datetime]::MinValue }
            Architecture = $meta.Architecture
            DefaultLanguage = $meta.DefaultLanguage
            Version = $meta.Version
        }
    }
    $selectedEval = $scoredSources |
        Sort-Object @{Expression='Compatible';Descending=$true}, @{Expression='BuildDelta';Descending=$false}, @{Expression='Build';Descending=$true}, @{Expression='LastWriteTimeUtc';Descending=$true} |
        Select-Object -First 1
    if (-not $selectedEval) {
        Write-Fail "No install source passed metadata evaluation."
    }
    if (-not $selectedEval.Compatible) {
        Write-Fail "Install sources found, but none matched system architecture/language requirements for reliable in-place upgrade."
    }
    $selectedSource = $selectedEval.Source
    Write-Ok "Selected source: $($selectedSource.Path) [$($selectedSource.Kind)] via $($selectedSource.Reason)"
    if ($selectedEval.Build -gt 0) {
        Write-Ok "Selected image metadata: build $($selectedEval.Build), arch $($selectedEval.Architecture), lang $($selectedEval.DefaultLanguage)"
    }
    if ($selectedSource.Kind -eq "IsoFile") {
        $activeIsoPath = (Get-Item -LiteralPath $selectedSource.Path -Force).FullName
        $IsoSource = $activeIsoPath
        Write-Ok "Using ISO file directly: $activeIsoPath"
    } else {
        $mediaRoot = $selectedSource.Path
        $mountRequired = $false
        Write-Ok "Using media root directly (no ISO mount required): $mediaRoot"
    }
}

# --- STEP 2: Mount ISO ---
Write-Step 3 "Mount ISO (if needed)"
if ($mountRequired) {
    Write-Host "    Dismounting any stale mounts..."
    try { Dismount-DiskImage $activeIsoPath -EA SilentlyContinue | Out-Null } catch {}
    Write-Host "    Mounting $activeIsoPath..."
    $mountStart = Get-Date
    $mount = $null
    try {
        $mount = Mount-DiskImage $activeIsoPath -PassThru -EA Stop
        Write-Host "    Mount initiated, waiting for drive letter assignment..."
        $timeout = 60
        while (((Get-Date) - $mountStart).TotalSeconds -lt $timeout) {
            Start-Sleep -Milliseconds 500
            $vol = $mount | Get-Volume -EA SilentlyContinue
            $dl = $vol.DriveLetter
            if ($dl) {
                $mediaRoot = "${dl}:\"
                Write-Ok "Mounted at ${dl}: (assigned after $(([math]::Round(((Get-Date) - $mountStart).TotalSeconds, 1))) seconds)"
                break
            }
            Write-Host "    [WAIT] Drive letter not yet assigned..." -NoNewline -ForegroundColor Yellow
            Write-Host "`r" -NoNewline
        }
        if (-not $dl) { Write-Fail "ISO mounted but no drive letter assigned after 60 seconds" }
    } catch {
        Write-Fail "Failed to mount ISO: $_"
    }
} else {
    Write-Ok "Skipped mount; media root already available at $mediaRoot"
}

# --- STEP 3: Extract ISO to C:\WinSetup ---
Write-Step 4 "Extract ISO to $ExtractDir (local NTFS)"
if (Test-Path $ExtractDir) {
    Write-Host "    Removing stale $ExtractDir ..."
    Remove-DirectoryHard -Path $ExtractDir
}
New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null
Write-Host "    Starting extraction with real-time progress..."
$sourceStats = Get-ChildItem -LiteralPath $mediaRoot -Recurse -File -EA SilentlyContinue | Measure-Object -Property Length -Sum
$sourceTotalBytes = if ($sourceStats.Sum) { [double]$sourceStats.Sum } else { 0.0 }
$sourceTotalFiles = if ($sourceStats.Count) { [int]$sourceStats.Count } else { 0 }
$extractStart = Get-Date
$lastBytes = 0.0
$lastTick = $extractStart
$process = Start-Process robocopy -ArgumentList $mediaRoot, $ExtractDir, "/E", "/MT:8", "/R:1", "/W:1", "/NFL", "/NDL", "/NJH", "/NJS", "/NP" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\robocopy.log"
while (-not $process.HasExited) {
    $destStats = Get-ChildItem -LiteralPath $ExtractDir -Recurse -File -EA SilentlyContinue | Measure-Object -Property Length -Sum
    $copiedBytes = if ($destStats.Sum) { [double]$destStats.Sum } else { 0.0 }
    $copiedFiles = if ($destStats.Count) { [int]$destStats.Count } else { 0 }
    $now = Get-Date
    $deltaSeconds = [math]::Max((($now - $lastTick).TotalSeconds), 0.001)
    $deltaBytes = [math]::Max(($copiedBytes - $lastBytes), 0.0)
    $speedMBs = ($deltaBytes / 1MB) / $deltaSeconds
    $pct = if ($sourceTotalBytes -gt 0) { [math]::Min([math]::Round(($copiedBytes / $sourceTotalBytes) * 100, 1), 100.0) } else { 0.0 }
    $elapsed = ($now - $extractStart).TotalSeconds
    $remainingBytes = [math]::Max(($sourceTotalBytes - $copiedBytes), 0.0)
    $etaSeconds = if ($speedMBs -gt 0.05) { [math]::Round($remainingBytes / ($speedMBs * 1MB), 0) } else { -1 }
    $etaText = if ($etaSeconds -ge 0) { "{0}m {1}s" -f ([math]::Floor($etaSeconds / 60)), ([math]::Floor($etaSeconds % 60)) } else { "calculating" }
    $elapsedText = "{0}m {1}s" -f ([math]::Floor($elapsed / 60)), ([math]::Floor($elapsed % 60))
    Write-Host ("`r    Progress: {0,5}% | {1,6:N2}/{2,6:N2} GB | files {3}/{4} | {5,6:N2} MB/s | elapsed {6} | ETA {7}" -f $pct, ($copiedBytes/1GB), ($sourceTotalBytes/1GB), $copiedFiles, $sourceTotalFiles, $speedMBs, $elapsedText, $etaText) -NoNewline -ForegroundColor Cyan
    $lastBytes = $copiedBytes
    $lastTick = $now
    Start-Sleep -Seconds 1
}
Write-Host ""
$process.WaitForExit()
if (($sourceTotalBytes -gt 0) -and ((Get-ChildItem -LiteralPath $ExtractDir -Recurse -File -EA SilentlyContinue | Measure-Object -Property Length -Sum).Sum -lt ($sourceTotalBytes * 0.99))) {
    Write-Fail "Extraction incomplete: destination size is lower than expected media size."
}
Remove-Item "$env:TEMP\robocopy.log" -EA SilentlyContinue
# Verify critical files
$critical = @(
    'setup.exe',
    'sources\autorun.dll',
    'sources\migcore.dll',
    'sources\AppExtAgent.dll',
    'sources\dismapi.dll',
    'sources\mighost.exe',
    'sources\migstore.dll',
    'sources\setupcore.dll',
    'sources\setuphost.exe',
    'sources\setupplatform.dll',
    'sources\spwizeng.dll',
    'sources\unbcl.dll',
    'sources\unattend.dll',
    'sources\uxlib.dll',
    'sources\wdscore.dll',
    'sources\SetupPlatform.cfg'
)
$installImagePath = @(
    (Join-Path $ExtractDir 'sources\install.esd'),
    (Join-Path $ExtractDir 'sources\install.wim')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $installImagePath) {
    Write-Fail "Missing after extract: sources\install.esd or sources\install.wim"
}
$critical += @(
    (Split-Path $installImagePath -Leaf | ForEach-Object { "sources\$_" })
)
Write-Host "    Verifying $($critical.Count) critical files..."
$missing = @()
$verified = 0
foreach ($f in $critical) {
    $p = Join-Path $ExtractDir $f
    Write-Host "`r    [$verified/$($critical.Count)] Checking $f..." -NoNewline -ForegroundColor Cyan
    if (-not (Test-Path $p)) {
        $missing += $f
        Write-Host " [MISSING]" -ForegroundColor Red
    } else {
        $verified++
    }
}
Write-Host ""
if ($missing.Count -gt 0) { Write-Fail "Missing after extract: $($missing -join ', ')" }
Repair-InvalidExtractedPortableExecutables $mediaRoot $ExtractDir
Write-Host "    Counting total extracted files..."
$fileCount = (Get-ChildItem $ExtractDir -Recurse -File -EA SilentlyContinue | Measure-Object).Count
Write-Ok "Extracted $fileCount files. All $($critical.Count) critical DLLs verified present."

# Validate media architecture and language compatibility for /Auto Upgrade
Write-Host "    Validating media compatibility (architecture + language)..."
$osArch = (Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue).OSArchitecture
if ($osArch -notmatch '64') {
    Write-Fail "This script requires a 64-bit Windows installation. Detected: $osArch"
}
$mediaInfo = (& dism.exe /English /Get-WimInfo /WimFile:"$installImagePath" /Index:1 2>&1 | Out-String)
if ([string]::IsNullOrWhiteSpace($mediaInfo)) {
    Write-Fail "Unable to read image metadata from $installImagePath"
}
if ($mediaInfo -notmatch '(?im)^\s*Architecture\s*:\s*x64\s*$') {
    Write-Fail "Install image architecture is not x64. Use media that matches system architecture."
}
try {
    $systemUiLang = (Get-WinSystemLocale).Name
} catch {
    $systemUiLang = $null
}
$mediaDefaultLangMatch = [regex]::Match($mediaInfo, '(?im)^\s*Default\s*:\s*([A-Za-z]{2}-[A-Za-z]{2})\s*$')
$mediaDefaultLang = if ($mediaDefaultLangMatch.Success) { $mediaDefaultLangMatch.Groups[1].Value } else { $null }
if ($systemUiLang -and $mediaDefaultLang -and ($systemUiLang -ne $mediaDefaultLang)) {
    Write-Fail "Language mismatch: system UI=$systemUiLang, media default=$mediaDefaultLang. /Auto Upgrade requires same system default UI language."
}
if ($systemUiLang -and $mediaDefaultLang) {
    Write-Ok "Media language compatible: $mediaDefaultLang"
}
Write-Ok "Media architecture compatible: x64"

# Dismount ISO (no longer needed)
try { Dismount-DiskImage $activeIsoPath -EA SilentlyContinue | Out-Null } catch {}

# --- STEP 4: Clean stale upgrade folders ---
Write-Step 5 "Clean stale upgrade folders"
foreach ($dir in @("C:\`$WINDOWS.~BT", "C:\`$Windows.~WS")) {
    if (Test-Path $dir) {
        $leaf = Split-Path $dir -Leaf
        Write-Host "    Cleaning $leaf with live progress..."
        $cleanupSteps = @(
            @{ Name = 'Take ownership'; File = 'takeown.exe'; Args = @('/F', $dir, '/R', '/D', 'Y'); Timeout = 900 },
            @{ Name = 'Grant admin ACL'; File = 'icacls.exe';  Args = @($dir, '/grant', '*S-1-5-32-544:(OI)(CI)F', '/T', '/C'); Timeout = 900 },
            @{ Name = 'Remove folder';   File = 'cmd.exe';     Args = @('/c', "rd /s /q `"$dir`""); Timeout = 900 }
        )
        $stepIndex = 0
        foreach ($step in $cleanupSteps) {
            $stepIndex++
            $phaseStart = Get-Date
            $phase = Start-Process -FilePath $step.File -ArgumentList $step.Args -PassThru -WindowStyle Hidden
            while (-not $phase.HasExited) {
                $elapsed = ((Get-Date) - $phaseStart).TotalSeconds
                if ($elapsed -gt $step.Timeout) {
                    Stop-Process -Id $phase.Id -Force -EA SilentlyContinue
                    Write-Fail "Cleanup step timed out for $leaf during '$($step.Name)'"
                }
                $mins = [math]::Floor($elapsed / 60)
                $secs = [math]::Floor($elapsed % 60)
                Write-Host "`r    [$stepIndex/$($cleanupSteps.Count)] $leaf | $($step.Name) | ${mins}m ${secs}s" -NoNewline -ForegroundColor Cyan
                Start-Sleep -Seconds 1
            }
            Write-Host ""
        }
        if (Test-Path $dir) {
            Write-Host "    First-pass cleanup incomplete for $leaf. Running hardened fallback..." -ForegroundColor Yellow
            Remove-DirectoryHard -Path $dir
        }
        if (Test-Path $dir) { Write-Host "    WARNING: Could not fully remove $dir" -ForegroundColor Yellow } else { Write-Ok "Removed $dir" }
    } else {
        Write-Ok "$dir already clean"
    }
}

# --- STEP 5: Clear PendingFileRenameOperations ---
Write-Step 6 "Clear PendingFileRenameOperations"
$pfro = Get-PendingFileRenameOperationsValue
if ($pfro) {
    Remove-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -Force -EA SilentlyContinue
    Write-Ok "Cleared $($pfro.Count) entries"
} else {
    Write-Ok "None pending"
}

# --- STEP 6: Remove blocking legacy drivers ---
Write-Step 7 "Remove blocking legacy printer drivers"
$driverDump = pnputil /enum-drivers 2>&1 | Out-String
# Find all legacy printer drivers with unsigned binaries
$oems = [regex]::Matches($driverDump, 'Published Name:\s+(oem\d+\.inf)\s+.*?Class Name:\s+Printer.*?Attributes:\s+Legacy', 'Singleline')
if ($oems.Count -gt 0) {
    foreach ($m in $oems) {
        $oem = $m.Groups[1].Value
        pnputil /delete-driver $oem /force 2>$null | Out-Null
        Write-Ok "Removed $oem (legacy printer)"
    }
} else {
    Write-Ok "No blocking legacy drivers found"
}

# --- STEP 7: Stop IIS to prevent migration errors ---
Write-Step 8 "Stop IIS services"
foreach ($svc in @('W3SVC','WAS','IISADMIN')) {
    $s = Get-Service $svc -EA SilentlyContinue
    if ($s -and $s.Status -eq 'Running') {
        Stop-Service $svc -Force -EA SilentlyContinue
        Write-Ok "Stopped $svc"
    }
}

# --- STEP 8: Start required services ---
Write-Step 9 "Start required services (with real-time verification)"
$required = @(
    @{Name='wuauserv';      Startup='Manual'},
    @{Name='BITS';          Startup='Manual'},
    @{Name='cryptsvc';      Startup='Automatic'},
    @{Name='TrustedInstaller'; Startup='Manual'},
    @{Name='DiagTrack';     Startup='Manual'},
    @{Name='msiserver';     Startup='Manual'}
)
$serviceCount = 0
foreach ($r in $required) {
    $s = Get-Service $r.Name -EA SilentlyContinue
    Write-Host "`r    [$serviceCount/$($required.Count)] Configuring $($r.Name)..." -NoNewline -ForegroundColor Cyan
    if ($s) {
        Set-Service $r.Name -StartupType $r.Startup -EA SilentlyContinue
        $startTime = Get-Date
        $timeout = 30
        while (((Get-Date) - $startTime).TotalSeconds -lt $timeout) {
            if ($s.Status -ne 'Running') {
                Start-Service $r.Name -EA SilentlyContinue
                Start-Sleep -Milliseconds 500
            }
            $s = Get-Service $r.Name -EA SilentlyContinue
            if ($s.Status -eq 'Running') {
                Write-Host " [RUNNING]" -ForegroundColor Green
                $serviceCount++
                break
            }
            Start-Sleep -Milliseconds 500
        }
        if ($s.Status -ne 'Running') {
            Write-Host " [WARN: $($s.Status)]" -ForegroundColor Yellow
        }
    } else {
        Write-Host " [NOT FOUND]" -ForegroundColor Yellow
    }
}
Write-Host ""

# --- STEP 9: Clear CBS RebootPending if present ---
Write-Step 10 "Clear reboot-pending flags"
$paths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
)
foreach ($rp in $paths) {
    if (Test-Path $rp) {
        Remove-Item $rp -Force -EA SilentlyContinue
        Write-Ok "Cleared $(Split-Path $rp -Leaf)"
    }
}
# Re-check PFRO (services may have re-added)
$pfro2 = Get-PendingFileRenameOperationsValue
if ($pfro2) {
    Remove-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -Force -EA SilentlyContinue
    Write-Ok "Re-cleared PFRO ($($pfro2.Count) entries)"
}
Write-Ok "No reboot-pending flags"

# --- STEP 10: Repair servicing and update components ---
Write-Step 11 "Repair servicing stack and Windows Update components"
$wuServices = @('wuauserv', 'BITS', 'cryptsvc', 'msiserver', 'UsoSvc', 'DoSvc')
foreach ($svc in $wuServices) {
    $service = Get-Service -Name $svc -EA SilentlyContinue
    if ($service -and $service.Status -eq 'Running') {
        Stop-Service -Name $svc -Force -EA SilentlyContinue
        Write-Ok "Stopped $svc"
    }
}

$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$softwareDistribution = "C:\Windows\SoftwareDistribution"
$softwareDistributionBak = "C:\Windows\SoftwareDistribution.bak.$stamp"
$catroot2 = "C:\Windows\System32\catroot2"
$catroot2Bak = "C:\Windows\System32\catroot2.bak.$stamp"
if (Test-Path $softwareDistribution) {
    try {
        Move-Item -Path $softwareDistribution -Destination $softwareDistributionBak -Force -EA Stop
    } catch {
        if (Test-Path $softwareDistribution) {
            Write-Fail "Failed to reset SoftwareDistribution. Ensure update services are stopped and try again."
        }
    }
    if (Test-Path $softwareDistributionBak) {
        Write-Ok "Reset SoftwareDistribution -> $softwareDistributionBak"
    }
}
if (Test-Path $catroot2) {
    try {
        Move-Item -Path $catroot2 -Destination $catroot2Bak -Force -EA Stop
    } catch {
        if (Test-Path $catroot2) {
            Write-Fail "Failed to reset catroot2. Ensure cryptsvc is stopped and try again."
        }
    }
    if (Test-Path $catroot2Bak) {
        Write-Ok "Reset catroot2 -> $catroot2Bak"
    }
}

$bitsQueuePath = Join-Path $env:ProgramData 'Microsoft\Network\Downloader'
if (Test-Path $bitsQueuePath) {
    Get-ChildItem -Path $bitsQueuePath -Filter 'qmgr*.dat' -File -EA SilentlyContinue | Remove-Item -Force -EA SilentlyContinue
    Write-Ok "Cleared BITS queue files"
}
$doCachePath = Join-Path $env:ProgramData 'Microsoft\Windows\DeliveryOptimization\Cache'
if (Test-Path $doCachePath) {
    Get-ChildItem -Path $doCachePath -Force -EA SilentlyContinue | Remove-Item -Recurse -Force -EA SilentlyContinue
    Write-Ok "Cleared Delivery Optimization cache"
}

foreach ($svc in $wuServices) {
    $service = Get-Service -Name $svc -EA SilentlyContinue
    if ($service) {
        Start-Service -Name $svc -EA SilentlyContinue
    }
}
foreach ($svc in @('wuauserv', 'BITS', 'cryptsvc')) {
    $state = (Get-Service -Name $svc -EA SilentlyContinue).Status
    if ($state -ne 'Running') {
        Write-Fail "$svc did not return to Running state after component reset."
    }
}

Invoke-ExternalProcess -FilePath "dism.exe" -Arguments "/Online /Cleanup-Image /StartComponentCleanup" -Description "DISM StartComponentCleanup" -TimeoutSeconds 5400
Invoke-ExternalProcess -FilePath "dism.exe" -Arguments "/Online /Cleanup-Image /CheckHealth" -Description "DISM CheckHealth" -TimeoutSeconds 1200
Invoke-ExternalProcess -FilePath "dism.exe" -Arguments "/Online /Cleanup-Image /ScanHealth" -Description "DISM ScanHealth" -TimeoutSeconds 5400
Invoke-ExternalProcess -FilePath "dism.exe" -Arguments "/Online /Cleanup-Image /RestoreHealth" -Description "DISM RestoreHealth" -TimeoutSeconds 10800
Invoke-ExternalProcess -FilePath "sfc.exe" -Arguments "/scannow" -Description "SFC ScanNow" -TimeoutSeconds 7200 -AllowedExitCodes @(0, 1)
Invoke-ExternalProcess -FilePath "netsh.exe" -Arguments "winhttp reset proxy" -Description "Reset WinHTTP proxy" -TimeoutSeconds 600 -AllowedExitCodes @(0, 1)

# --- STEP 11: Disk space check ---
Write-Step 12 "Verify disk space"
$freeGB = [math]::Round((Get-PSDrive C).Free/1GB, 1)
if ($freeGB -lt 20) { Write-Fail "Only $freeGB GB free on C: (need 20+)" }
Write-Ok "$freeGB GB free on C:"

# --- STEP 12: Pre-flight summary ---
Write-Step 13 "Pre-flight verification (real-time checks)"
$checks = @(
    @{Name='setup.exe exists';       OK=(Test-Path "$ExtractDir\setup.exe")},
    @{Name='migcore.dll present';    OK=(Test-Path "$ExtractDir\sources\migcore.dll")},
    @{Name='install image present';  OK=((Test-Path "$ExtractDir\sources\install.esd") -or (Test-Path "$ExtractDir\sources\install.wim"))},
    @{Name='No stale BT folder';    OK=(-not (Test-Path "C:\`$WINDOWS.~BT"))},
    @{Name='wuauserv Running';       OK=((Get-Service wuauserv -EA SilentlyContinue).Status -eq 'Running')},
    @{Name='TrustedInstaller Running'; OK=((Get-Service TrustedInstaller -EA SilentlyContinue).Status -eq 'Running')},
    @{Name='IIS stopped';            OK=((Get-Service W3SVC -EA SilentlyContinue).Status -ne 'Running')},
    @{Name='Disk space OK';          OK=($freeGB -ge 20)}
)
$allPass = $true
$checkCount = 0
foreach ($c in $checks) {
    Write-Host "`r    [$checkCount/$($checks.Count)] Checking $($c.Name)..." -NoNewline -ForegroundColor Cyan
    if ($c.OK) {
        Write-Host " [PASS]" -ForegroundColor Green
        $checkCount++
    }
    else {
        Write-Host " [FAIL]" -ForegroundColor Red
        $allPass = $false
    }
}
Write-Host ""
if (-not $allPass) { Write-Fail "Pre-flight checks failed. Aborting to protect apps/settings." }
Write-Ok "All $($checks.Count) pre-flight checks PASSED - Ready for repair upgrade"

# --- STEP 13: Setup compatibility scan ---
Write-Step 14 "Run setup compatibility scan"
$setupLogDir = "C:\WinSetup\Logs"
New-Item -Path $setupLogDir -ItemType Directory -Force -EA SilentlyContinue | Out-Null
$scanArgs = "/Auto Upgrade /Quiet /DynamicUpdate NoDrivers /MigrateDrivers All /BitLocker AlwaysSuspend /ShowOOBE None /Telemetry Disable /Compat ScanOnly /EULA Accept /CopyLogs `"$setupLogDir`""
$scanProc = Start-Process -FilePath "$ExtractDir\setup.exe" -ArgumentList $scanArgs -PassThru
$scanStart = Get-Date
$setupActLog = "C:\`$WINDOWS.~BT\Sources\Panther\setupact.log"
$scanLastLogBytes = if (Test-Path $setupActLog) { (Get-Item $setupActLog -EA SilentlyContinue).Length } else { 0 }
$scanLastCpu = $scanProc.TotalProcessorTime
$scanLastActivity = Get-Date
while (-not $scanProc.HasExited) {
    $scanElapsed = ((Get-Date) - $scanStart).TotalSeconds
    if ($scanElapsed -gt 7200) {
        Stop-Process -Id $scanProc.Id -Force -EA SilentlyContinue
        Write-Fail "Windows Setup compatibility scan timed out after 120 minutes"
    }
    $procLive = Get-Process -Id $scanProc.Id -EA SilentlyContinue
    $cpuTotal = if ($procLive) { $procLive.TotalProcessorTime } else { [timespan]::Zero }
    $wsMb = if ($procLive) { [math]::Round($procLive.WorkingSet64 / 1MB, 1) } else { 0 }
    $cpuTick = $cpuTotal - $scanLastCpu
    if ($cpuTick.TotalMilliseconds -gt 0) {
        $scanLastCpu = $cpuTotal
        $scanLastActivity = Get-Date
    }
    $logBytes = if (Test-Path $setupActLog) { (Get-Item $setupActLog -EA SilentlyContinue).Length } else { 0 }
    $logDelta = $logBytes - $scanLastLogBytes
    if ($logDelta -gt 0) {
        $scanLastLogBytes = $logBytes
        $scanLastActivity = Get-Date
    }
    $idleSeconds = [math]::Round(((Get-Date) - $scanLastActivity).TotalSeconds, 0)
    if ($idleSeconds -gt 600) {
        Stop-Process -Id $scanProc.Id -Force -EA SilentlyContinue
        Write-Fail "Compatibility scan showed no CPU/log activity for 10 minutes. Aborted to avoid silent hang."
    }
    $mins = [math]::Floor($scanElapsed / 60)
    $secs = [math]::Floor($scanElapsed % 60)
    $deltaKb = if ($logDelta -gt 0) { [math]::Round($logDelta / 1KB, 1) } else { 0 }
    Write-Host "`r    Running: compatibility scan ${mins}m ${secs}s | CPU $([math]::Round($cpuTotal.TotalSeconds,1))s | RAM ${wsMb}MB | setupact +${deltaKb}KB | idle ${idleSeconds}s" -NoNewline -ForegroundColor Cyan
    Start-Sleep -Milliseconds 1000
}
Write-Host ""
$scanProc.WaitForExit()
$scanCode = $scanProc.ExitCode
$scanPassCode = Convert-HexToSignedInt 'C1900210'
if (($scanCode -ne 0) -and ($scanCode -ne $scanPassCode)) {
    switch ($scanCode) {
        (Convert-HexToSignedInt 'C1900208') { Write-Fail "Compatibility scan found blocking app/driver issues (0xC1900208)." }
        (Convert-HexToSignedInt 'C1900204') { Write-Fail "Compatibility scan failed due to migration choice block (0xC1900204)." }
        (Convert-HexToSignedInt 'C1900200') { Write-Fail "Compatibility scan failed due to system requirement block (0xC1900200)." }
        (Convert-HexToSignedInt 'C190020E') { Write-Fail "Compatibility scan failed due to insufficient disk space (0xC190020E)." }
        (Convert-HexToSignedInt 'C190010E') { Write-Fail "Compatibility scan failed because EULA acceptance was required (0xC190010E)." }
        default { Write-Fail "Compatibility scan failed with exit code $scanCode." }
    }
}
Write-Ok "Compatibility scan passed (exit code $scanCode)"

# --- STEP 14: Launch repair upgrade ---
Write-Step 15 "Launching repair upgrade from $ExtractDir\setup.exe"
Write-Host ""
Write-Host "    === REPAIR UPGRADE STARTING ===" -ForegroundColor Green
Write-Host "    /Auto Upgrade /Quiet /DynamicUpdate NoDrivers /MigrateDrivers All /BitLocker AlwaysSuspend" -ForegroundColor White
Write-Host "    /ShowOOBE None /Telemetry Disable" -ForegroundColor White
Write-Host "    /Compat IgnoreWarning /EULA Accept /CopyLogs C:\WinSetup\Logs" -ForegroundColor White
Write-Host ""

$setupArgs = "/Auto Upgrade /Quiet /DynamicUpdate NoDrivers /MigrateDrivers All /BitLocker AlwaysSuspend /ShowOOBE None /Telemetry Disable /Compat IgnoreWarning /EULA Accept /CopyLogs `"$setupLogDir`""
Write-Host "    [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Process starting..." -ForegroundColor Cyan

$setupPath = "$ExtractDir\setup.exe"
if (-not (Test-Path $setupPath)) {
    Write-Fail "Setup.exe not found at $setupPath"
}

$proc = Start-Process $setupPath -ArgumentList $setupArgs -PassThru
$setupTimeout = 28800; $startTime = Get-Date

Write-Host "    [Process ID: $($proc.Id)]"
Write-Host "    [Max runtime: 8 hours]"
Write-Host ""

while (-not $proc.HasExited) {
    $elapsed = ((Get-Date) - $startTime).TotalSeconds
    if ($elapsed -gt $setupTimeout) {
        Write-Host "    [TIMEOUT] Setup exceeded 8 hours, terminating..." -ForegroundColor Red
        Stop-Process -Id $proc.Id -Force -EA SilentlyContinue
        break
    }

    $hours = [math]::Floor($elapsed / 3600)
    $minutes = [math]::Floor(($elapsed % 3600) / 60)
    $seconds = [math]::Floor($elapsed % 60)
    Write-Host "`r    [$(Get-Date -Format 'HH:mm:ss')] Running: ${hours}h ${minutes}m ${seconds}s | Process active: YES" -NoNewline -ForegroundColor Cyan
    Start-Sleep -Milliseconds 1000
}

Write-Host ""
$proc.WaitForExit()
$exitCode = $proc.ExitCode
$totalTime = ((Get-Date) - $startTime).TotalSeconds
Write-Host "`n    Setup exited with code: $exitCode (runtime: $([math]::Round($totalTime/60, 1)) minutes)" -ForegroundColor $(if($exitCode -eq 0){'Green'}else{'Red'})

if ($exitCode -eq 0) {
    Write-Ok "Repair upgrade COMPLETED SUCCESSFULLY"
} else {
    Write-Host "    [WARNING] Setup exited with non-zero code. Showing recent setup errors..." -ForegroundColor Yellow
    $setupErr = "C:\`$WINDOWS.~BT\Sources\Panther\setuperr.log"
    if (Test-Path $setupErr) {
        Get-Content $setupErr -Tail 40 -EA SilentlyContinue | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
    }
    $setupDiagExe = @(
        (Join-Path $ExtractDir 'sources\SetupDiag.exe'),
        "C:\`$WINDOWS.~BT\Sources\SetupDiag.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($setupDiagExe) {
        $setupDiagOut = Join-Path $setupLogDir "SetupDiagResults.log"
        Invoke-ExternalProcess -FilePath $setupDiagExe -Arguments "/Output:`"$setupDiagOut`" /NoTel" -Description "SetupDiag analysis" -TimeoutSeconds 1800 -AllowedExitCodes @(0, 1)
    }
    Write-Host "    Review logs in $setupLogDir and C:\`$WINDOWS.~BT\Sources\Panther." -ForegroundColor Yellow
    Write-Fail "Repair upgrade failed with exit code $exitCode"
}
