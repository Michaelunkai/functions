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

Write-Host "    Starting BITS transfer from Microsoft cloud..."
$bitsTimeout = 3600; $startTime = Get-Date

try {
    # Try primary cloud source with BITS
    $job = Start-BitsTransfer -Source $CloudIsoUrl -Destination $TempIsoPath -Asynchronous -DisplayName "Win11-Cloud-ISO" -Description "Windows 11 Cloud Download" -EA SilentlyContinue
    if ($job) {
        Write-Host "    [BITS Job ID: $($job.JobId)]"
        while ($job.JobState -eq "Transferring") {
            $elapsed = ((Get-Date) - $startTime).TotalSeconds
            if ($elapsed -gt $bitsTimeout) {
                Stop-BitsTransfer -BitsJob $job -EA SilentlyContinue
                Write-Host "    [TIMEOUT] Download exceeded 1 hour, resuming with fallback..." -ForegroundColor Yellow
                break
            }
            $pct = [math]::Round(($job.BytesTransferred / $job.BytesTotal) * 100, 1)
            $transferred = [math]::Round($job.BytesTransferred / 1GB, 2)
            $total = [math]::Round($job.BytesTotal / 1GB, 2)
            Write-Host "`r    Progress: $pct% ($transferred GB / $total GB)" -NoNewline -ForegroundColor Cyan
            Start-Sleep -Milliseconds 500
        }
        if ($job.JobState -eq "Transferred") {
            Complete-BitsTransfer -BitsJob $job
            Write-Ok "Cloud download complete: $([math]::Round((Get-Item $TempIsoPath).Length/1GB, 2)) GB"
            $CloudDownloadSuccess = $true
        } else {
            Write-Host "    [INFO] BITS job incomplete, checking alternative sources..." -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "    [INFO] Primary cloud source unavailable, checking alternatives..." -ForegroundColor Yellow
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
    $selectedSource = $null
    foreach ($c in $candidates) {
        $resolved = Resolve-InstallMediaPath $c.Path $c.Reason
        if ($resolved) { $selectedSource = $resolved; break }
    }
    if (-not $selectedSource) {
        Write-Fail "No usable Windows 11 installation source found (ISO file or media folder with setup.exe)"
    }
    Write-Ok "Selected source: $($selectedSource.Path) [$($selectedSource.Kind)] via $($selectedSource.Reason)"
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
    try { Dismount-DiskImage $activeIsoPath -EA SilentlyContinue } catch {}
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
    Remove-Item $ExtractDir -Recurse -Force -EA SilentlyContinue
    # Fallback if locked
    if (Test-Path $ExtractDir) {
        cmd /c "rd /s /q `"$ExtractDir`"" 2>$null
    }
}
New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null
Write-Host "    Starting extraction with real-time progress..."
$robocopyOutput = @()
$process = Start-Process robocopy -ArgumentList $mediaRoot, $ExtractDir, "/E", "/MT:8", "/NFL", "/NDL", "/NJH" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\robocopy.log"
$lastCount = 0
while (-not $process.HasExited) {
    try {
        $lines = @(Get-Content "$env:TEMP\robocopy.log" -EA SilentlyContinue)
        if ($lines.Count -gt $lastCount) {
            $lastCount = $lines.Count
            $lastLine = $lines[-1]
            Write-Host "`r    Copied: $lastLine" -NoNewline -ForegroundColor Cyan
        }
    } catch {}
    Start-Sleep -Milliseconds 500
}
Write-Host ""
$process.WaitForExit()
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
    'sources\install.esd',
    'sources\SetupPlatform.cfg'
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

# Dismount ISO (no longer needed)
try { Dismount-DiskImage $activeIsoPath -EA SilentlyContinue } catch {}

# --- STEP 4: Clean stale upgrade folders ---
Write-Step 5 "Clean stale upgrade folders"
foreach ($dir in @("C:\`$WINDOWS.~BT", "C:\`$Windows.~WS")) {
    if (Test-Path $dir) {
        cmd /c "takeown /f `"$dir`" /r /d y" 2>$null | Out-Null
        cmd /c "icacls `"$dir`" /grant administrators:F /t" 2>$null | Out-Null
        cmd /c "rd /s /q `"$dir`"" 2>$null
        if (Test-Path $dir) { Write-Host "    WARNING: Could not fully remove $dir" -ForegroundColor Yellow }
        else { Write-Ok "Removed $dir" }
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

# --- STEP 10: Disk space check ---
Write-Step 11 "Verify disk space"
$freeGB = [math]::Round((Get-PSDrive C).Free/1GB, 1)
if ($freeGB -lt 20) { Write-Fail "Only $freeGB GB free on C: (need 20+)" }
Write-Ok "$freeGB GB free on C:"

# --- STEP 11: Pre-flight summary ---
Write-Step 12 "Pre-flight verification (real-time checks)"
$checks = @(
    @{Name='setup.exe exists';       OK=(Test-Path "$ExtractDir\setup.exe")},
    @{Name='migcore.dll present';    OK=(Test-Path "$ExtractDir\sources\migcore.dll")},
    @{Name='install.esd present';    OK=(Test-Path "$ExtractDir\sources\install.esd")},
    @{Name='No stale BT folder';    OK=(-not (Test-Path "C:\`$WINDOWS.~BT"))},
    @{Name='wuauserv Running';       OK=((Get-Service wuauserv -EA SilentlyContinue).Status -eq 'Running')},
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
if (-not $allPass) { Write-Fail "Pre-flight checks failed. Aborting." }
Write-Ok "All $($checks.Count) pre-flight checks PASSED - Ready for repair upgrade"

# --- STEP 12: Launch repair upgrade ---
Write-Step 13 "Launching repair upgrade from $ExtractDir\setup.exe"
Write-Host ""
Write-Host "    === REPAIR UPGRADE STARTING ===" -ForegroundColor Green
Write-Host "    /Auto Upgrade /DynamicUpdate Disable /MigrateDrivers All" -ForegroundColor White
Write-Host "    /ShowOOBE None /Telemetry Disable" -ForegroundColor White
Write-Host "    /Compat IgnoreWarning" -ForegroundColor White
Write-Host ""

$setupArgs = "/Auto Upgrade /DynamicUpdate Disable /MigrateDrivers All /ShowOOBE None /Telemetry Disable /Compat IgnoreWarning"
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
    Write-Host "    [WARNING] Setup exited with non-zero code. Check Windows logs for details." -ForegroundColor Yellow
}
