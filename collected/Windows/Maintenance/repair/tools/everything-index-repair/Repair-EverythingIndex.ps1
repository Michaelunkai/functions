[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$SelfTest,
    [switch]$SkipDownload,
    [switch]$SkipInstall,
    [switch]$SkipReindex,
    [switch]$AllowDestructiveRepair
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# Only this drive is indexed and shown. Every other NTFS volume is excluded.
$TargetDrive = 'C:'

$LogDirectory = Join-Path $env:LOCALAPPDATA 'Everything'
$LogPath = Join-Path $LogDirectory 'EverythingRepair.log'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
function Write-Step {
    param([string]$Message)
    $line = '[EverythingFix] ' + $Message
    Write-Host $line
    try {
        New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
        Add-Content -LiteralPath $LogPath -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') + ' ' + $line)
    } catch {
        # Logging must never break the repair.
    }
}

function Write-Warn {
    param([string]$Message)
    Write-Step ('WARNING: ' + $Message)
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Wait-ProcessExit {
    param($Process, [int]$Seconds)
    for ($i = 0; $i -lt $Seconds; $i++) {
        try { $Process.Refresh() } catch { }
        if ($Process.HasExited) { return $true }
        Start-Sleep -Seconds 1
    }
    try {
        if (-not $Process.HasExited) {
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
            Write-Warn ('Process timed out after ' + $Seconds + 's and was terminated: ' + $Process.ProcessName)
            return $false
        }
    } catch { }
    return $true
}

function Get-EverythingStableDownload {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls

    $page = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $page = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 'https://www.voidtools.com/downloads/').Content
            break
        } catch {
            if ($attempt -eq 3) {
                throw ('Could not fetch voidtools downloads page: ' + $_.Exception.Message)
            }
            Write-Warn ('Downloads page fetch attempt ' + $attempt + ' failed; retrying.')
            Start-Sleep -Seconds 5
        }
    }

    $match = $null
    foreach ($pattern in @(
            'Everything-\d+\.\d+\.\d+\.\d+\.x64-Setup\.exe',
            'Everything-\d+\.\d+\.\d+\.x64-Setup\.exe')) {
        $match = [regex]::Match($page, $pattern)
        if ($match.Success) { break }
    }
    if (-not $match.Success) {
        throw 'Could not find latest stable x64 Everything setup on voidtools downloads page.'
    }

    [pscustomobject]@{
        FileName = $match.Value
        Url = 'https://www.voidtools.com/' + $match.Value
    }
}

function Get-EverythingSizeSortValue {
    param([string]$FileVersion)
    $major = 0
    $minor = 0
    try {
        $parts = @($FileVersion -split '\.')
        if ($parts.Count -ge 1) { $major = [int]$parts[0] }
        if ($parts.Count -ge 2) { $minor = [int]$parts[1] }
    } catch {
        $major = 0
        $minor = 0
    }
    # Everything 1.5 uses the sort name "size", Everything 1.4 uses "Size".
    if ($major -gt 1 -or ($major -eq 1 -and $minor -ge 5)) { return 'size' }
    return 'Size'
}

# ---------------------------------------------------------------------------
# Stopping Everything (bounded waits only, never throws)
# ---------------------------------------------------------------------------
function Stop-EverythingService {
    $svc = Get-Service Everything -ErrorAction SilentlyContinue
    if (-not $svc) {
        return
    }
    Write-Step 'Stopping the Everything service (kept installed).'
    if ($svc.Status -ne 'Stopped') {
        & sc.exe stop Everything 2>$null | Out-Null
    }
    for ($i = 0; $i -lt 20; $i++) {
        $svc = Get-Service Everything -ErrorAction SilentlyContinue
        if (-not $svc) { return }
        if ($svc.Status -eq 'Stopped') {
            Write-Step 'Everything service stopped.'
            return
        }
        & sc.exe stop Everything 2>$null | Out-Null
        Start-Sleep -Seconds 2
    }
    Write-Warn 'Everything service did not reach Stopped within 40s; continuing best-effort.'
}

function Stop-EverythingProcesses {
    Write-Step 'Stopping Everything processes.'
    for ($i = 0; $i -lt 10; $i++) {
        Get-Process everything -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        if (-not (Get-Process everything -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Seconds 2
    }
}

# Stop the service first, then kill leftover GUI processes. (Killing the
# service process directly triggers its auto-restart and makes stops spin.)
function Stop-EverythingRunning {
    Stop-EverythingService
    Stop-EverythingProcesses
}

function Remove-EverythingService {
    $svc = Get-Service Everything -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Step 'No Everything service to remove.'
        return
    }
    Write-Step 'Removing the Everything service (full teardown).'
    if ($svc.Status -ne 'Stopped') {
        & sc.exe stop Everything 2>$null | Out-Null
    }
    for ($i = 0; $i -lt 20; $i++) {
        $svc = Get-Service Everything -ErrorAction SilentlyContinue
        if (-not $svc) { break }
        if ($svc.Status -ne 'Stopped') { & sc.exe stop Everything 2>$null | Out-Null }
        Start-Sleep -Seconds 2
    }
    & sc.exe delete Everything 2>$null | Out-Null
    for ($i = 0; $i -lt 15; $i++) {
        $svc = Get-Service Everything -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-Step 'Everything service removed.'
            return
        }
        Start-Sleep -Seconds 2
    }
    Write-Warn 'Everything service could not be fully removed; continuing best-effort.'
}

# ---------------------------------------------------------------------------
# Back up and remove stale Everything state
# ---------------------------------------------------------------------------
function Backup-And-Remove-StaleEverythingState {
    param([switch]$RemoveDatabases)

    $stamp = Get-Date -Format yyyyMMdd_HHmmss
    $backup = Join-Path $env:LOCALAPPDATA ('EverythingRepairBackup_' + $stamp)
    New-Item -ItemType Directory -Force -Path $backup | Out-Null

    $systemProfileRoaming = Join-Path $env:windir 'System32\config\systemprofile\AppData\Roaming\Everything'
    $systemProfileLocal = Join-Path $env:windir 'System32\config\systemprofile\AppData\Local\Everything'

    $targets = @(
        (Join-Path $env:APPDATA 'Everything\Everything.ini'),
        (Join-Path $env:ProgramData 'Everything\Everything.ini'),
        (Join-Path $systemProfileRoaming 'Everything.ini'),
        'F:\backup\windowsapps\installed\Everything\Everything.ini'
    )
    if ($RemoveDatabases) {
        $targets += @(
            (Join-Path $env:LOCALAPPDATA 'Everything\Everything.db'),
            (Join-Path $env:ProgramData 'Everything\Everything.db'),
            (Join-Path $systemProfileLocal 'Everything.db'),
            'F:\backup\windowsapps\installed\Everything\Everything.db'
        )
    }

    foreach ($target in $targets) {
        if (Test-Path -LiteralPath $target) {
            Copy-Item -LiteralPath $target -Destination (Join-Path $backup ((Split-Path $target -Leaf) + '.bak')) -Force
            Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        }
    }

    return $backup
}

# ---------------------------------------------------------------------------
# Locating and installing Everything
# ---------------------------------------------------------------------------
function Get-EverythingExe {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Everything\Everything.exe'),
        'F:\backup\windowsapps\installed\Everything\Everything.exe'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw 'Everything.exe not found after install.'
}

function Install-Or-UpdateEverything {
    param(
        [string]$InstallerPath
    )

    Write-Step 'Installing current stable Everything silently.'
    $installer = Start-Process -FilePath $InstallerPath -ArgumentList '/S' -PassThru
    if (-not (Wait-ProcessExit -Process $installer -Seconds 300)) {
        Write-Warn 'Installer did not finish within 300s; it was terminated. Verifying the install anyway.'
    }
}

# ---------------------------------------------------------------------------
# Everything service (always on, auto-restarts, bounded start wait)
# ---------------------------------------------------------------------------
function Create-EverythingService {
    param(
        [string]$EverythingExe
    )

    $binaryPath = '"' + $EverythingExe + '" -svc'
    $service = Get-CimInstance Win32_Service -Filter "Name='Everything'" -ErrorAction SilentlyContinue

    if ($service) {
        Write-Step 'Reconfiguring the existing Everything service.'
        # delayed-auto avoids the known Everything service boot timeouts.
        & sc.exe config Everything binPath= $binaryPath start= delayed-auto obj= LocalSystem | Out-Host
    } else {
        Write-Step 'Creating the Everything service.'
        & sc.exe create Everything binPath= $binaryPath start= delayed-auto obj= LocalSystem DisplayName= Everything | Out-Host
    }

    & sc.exe failure Everything reset= 86400 actions= restart/5000/restart/30000/""/60000 | Out-Host
    & sc.exe description Everything 'Everything search index service' | Out-Null

    if (-not (Get-Service Everything -ErrorAction SilentlyContinue)) {
        Write-Warn 'Everything service is not registered after create/config.'
    }
}

function Start-EverythingService {
    $svc = Get-Service Everything -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Warn 'Everything service is missing.'
        return $null
    }
    if ($svc.Status -ne 'Running') {
        & sc.exe start Everything 2>$null | Out-Host
    }
    for ($i = 0; $i -lt 30; $i++) {
        $svc = Get-Service Everything -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') { return $svc }
        Start-Sleep -Seconds 2
    }
    Write-Warn 'Everything service did not reach Running within 60s; continuing best-effort.'
    return $svc
}

# ---------------------------------------------------------------------------
# Everything.ini configuration (only C:, real time, size sort)
# ---------------------------------------------------------------------------
function Get-FixedNtfsVolumes {
    # Returns objects with .Letter and .Guid (Everything 1.4 keys volume config
    # by volume GUID; a paths-only list is silently dropped -> empty index).
    $result = @()
    $volumes = Get-CimInstance Win32_Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveLetter -and $_.DriveType -eq 3 -and $_.FileSystem -eq 'NTFS' } |
        Sort-Object DriveLetter
    foreach ($v in $volumes) {
        $result += [pscustomobject]@{
            Letter = $v.DriveLetter.TrimEnd('\')
            Guid = $v.DeviceID.TrimEnd('\')
        }
    }
    if ($result.Count -eq 0) {
        # Fallback: drive letters only (no GUIDs available).
        $disks = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue |
            Where-Object { $_.FileSystem -eq 'NTFS' -and $_.DeviceID } |
            Sort-Object DeviceID
        foreach ($v in $disks) {
            $result += [pscustomobject]@{
                Letter = $v.DeviceID.TrimEnd('\')
                Guid = ''
            }
        }
    }
    return $result
}

function Get-EverythingIniCandidates {
    param([string]$EverythingExe)
    $list = New-Object System.Collections.Generic.List[string]

    $p1 = Join-Path $env:APPDATA 'Everything\Everything.ini'
    if (Test-Path -LiteralPath $p1) { $list.Add($p1) }
    $p2 = Join-Path $env:ProgramData 'Everything\Everything.ini'
    if (Test-Path -LiteralPath $p2) { $list.Add($p2) }
    $p3 = Join-Path $env:windir 'System32\config\systemprofile\AppData\Roaming\Everything\Everything.ini'
    if (Test-Path -LiteralPath $p3) { $list.Add($p3) }
    $p4 = 'F:\backup\windowsapps\installed\Everything\Everything.ini'
    if (Test-Path -LiteralPath $p4) { $list.Add($p4) }
    if ($EverythingExe) {
        $p5 = Join-Path (Split-Path $EverythingExe) 'Everything.ini'
        if (Test-Path -LiteralPath $p5) { $list.Add($p5) }
    }

    return @($list | Select-Object -Unique)
}

function Ensure-EverythingIni {
    param([string]$IniPath)
    if (Test-Path -LiteralPath $IniPath) { return }
    New-Item -ItemType Directory -Force -Path (Split-Path $IniPath) | Out-Null
    [System.IO.File]::WriteAllLines($IniPath, @('[Everything]'), (New-Object System.Text.UTF8Encoding($false)))
}

function Update-IniKey {
    param([string[]]$Lines, [string]$Key, [string]$Value)
    $pattern = '^' + [regex]::Escape($Key) + '\s*='
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match $pattern) {
            $Lines[$i] = $Key + '=' + $Value
            return ,$Lines
        }
    }
    return ,($Lines + ($Key + '=' + $Value))
}

# Builds the parallel ntfs_volume_* lists deterministically from the volumes
# discovered by Windows, with only $TargetDrive included and monitored. This
# always overwrites whatever (possibly empty/stale) lists exist in the file.
# Entries may be strings (letter only) or objects with .Letter and .Guid.
function Set-IniVolumeLists {
    param([string[]]$Lines, [string]$TargetDrive, [array]$FixedVolumes)
    $target = $TargetDrive.TrimEnd('\').TrimEnd(':') + ':'

    if ($FixedVolumes.Count -eq 0) {
        $FixedVolumes = @([pscustomobject]@{ Letter = $target; Guid = '' })
    }

    $letters = @()
    $guids = @()
    $includes = @()
    $monitors = @()
    foreach ($item in $FixedVolumes) {
        $letter = ''
        $guid = ''
        if ($item -is [string]) {
            $letter = $item.Trim().TrimEnd('\')
        } else {
            $letter = [string]$item.Letter
            $guid = [string]$item.Guid
        }
        if (-not $letter) { continue }
        $letters += $letter.TrimEnd('\')
        $guids += $guid.TrimEnd('\')
        if ($letter.TrimEnd('\').ToLowerInvariant() -eq $target.ToLowerInvariant()) {
            $includes += '1'
            $monitors += '1'
        } else {
            $includes += '0'
            $monitors += '0'
        }
    }

    if ($letters.Count -eq 0) {
        $letters = @($target)
        $guids = @('')
        $includes = @('1')
        $monitors = @('1')
    }
    $emptyRoots = (@('') * $letters.Count) -join ','
    $noRecent = (@('0') * $letters.Count) -join ','

    $Lines = Update-IniKey -Lines $Lines -Key 'ntfs_volume_guids' -Value ($guids -join ',')
    $Lines = Update-IniKey -Lines $Lines -Key 'ntfs_volume_paths' -Value ($letters -join ',')
    $Lines = Update-IniKey -Lines $Lines -Key 'ntfs_volume_roots' -Value $emptyRoots
    $Lines = Update-IniKey -Lines $Lines -Key 'ntfs_volume_includes' -Value ($includes -join ',')
    $Lines = Update-IniKey -Lines $Lines -Key 'ntfs_volume_monitors' -Value ($monitors -join ',')
    $Lines = Update-IniKey -Lines $Lines -Key 'ntfs_volume_load_recent_changes' -Value $noRecent
    $Lines = Update-IniKey -Lines $Lines -Key 'ntfs_volume_include_onlys' -Value $emptyRoots

    return ,$Lines
}

function Patch-EverythingIni {
    param([string]$IniPath, [string]$SortValue, [string]$TargetDrive, [array]$FixedVolumes)
    if (-not (Test-Path -LiteralPath $IniPath)) { return $false }
    try {
        $lines = @(Get-Content -LiteralPath $IniPath -Encoding UTF8)

        # Only the target drive is included; everything else is excluded.
        $lines = Set-IniVolumeLists -Lines $lines -TargetDrive $TargetDrive -FixedVolumes $FixedVolumes

        # Never silently pick up other volumes again.
        $lines = Update-IniKey -Lines $lines -Key 'auto_include_fixed_volumes' -Value '0'
        $lines = Update-IniKey -Lines $lines -Key 'auto_include_removable_volumes' -Value '0'
        $lines = Update-IniKey -Lines $lines -Key 'auto_include_fixed_refs_volumes' -Value '0'
        $lines = Update-IniKey -Lines $lines -Key 'auto_include_removable_refs_volumes' -Value '0'
        $lines = Update-IniKey -Lines $lines -Key 'auto_remove_offline_ntfs_volumes' -Value '1'

        # Real-time indexing: USN journal monitors + live size/date updates.
        $lines = Update-IniKey -Lines $lines -Key 'index_size' -Value '1'
        $lines = Update-IniKey -Lines $lines -Key 'fast_size_sort' -Value '1'
        $lines = Update-IniKey -Lines $lines -Key 'index_folder_size' -Value '1'
        $lines = Update-IniKey -Lines $lines -Key 'extended_information_cache_monitor' -Value '1'
        $lines = Update-IniKey -Lines $lines -Key 'index_date_modified' -Value '1'
        $lines = Update-IniKey -Lines $lines -Key 'fast_date_modified_sort' -Value '1'

        # UI: ordered by size (descending), show everything on open.
        $lines = Update-IniKey -Lines $lines -Key 'sort' -Value $SortValue
        $lines = Update-IniKey -Lines $lines -Key 'sort_ascending' -Value '0'
        $lines = Update-IniKey -Lines $lines -Key 'home_sort' -Value '1'
        $lines = Update-IniKey -Lines $lines -Key 'always_keep_sort' -Value '1'
        $lines = Update-IniKey -Lines $lines -Key 'size_descending_first' -Value '1'
        $lines = Update-IniKey -Lines $lines -Key 'home_search' -Value '1'
        $lines = Update-IniKey -Lines $lines -Key 'search' -Value ''
        $lines = Update-IniKey -Lines $lines -Key 'view' -Value '0'
        $lines = Update-IniKey -Lines $lines -Key 'size_column_visible' -Value '1'
        $lines = Update-IniKey -Lines $lines -Key 'size_column_pos' -Value '1'
        $lines = Update-IniKey -Lines $lines -Key 'run_in_background' -Value '1'
        $lines = Update-IniKey -Lines $lines -Key 'show_tray_icon' -Value '1'
        $lines = Update-IniKey -Lines $lines -Key 'show_size_in_statusbar' -Value '1'
        $lines = Update-IniKey -Lines $lines -Key 'check_for_updates_on_startup' -Value '0'

        [System.IO.File]::WriteAllLines($IniPath, [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    } catch {
        Write-Warn ('Could not patch ' + $IniPath + ': ' + $_.Exception.Message)
        return $false
    }
}

function Get-EverythingConfigSummary {
    param([string]$EverythingExe, [string[]]$IniPaths)
    $details = New-Object System.Collections.Generic.List[string]
    $cOnly = $false
    $sort = ''
    $sortAsc = ''

    if (-not $IniPaths) {
        $IniPaths = @(Get-EverythingIniCandidates -EverythingExe $EverythingExe)
    }

    foreach ($iniPath in $IniPaths) {
        try {
            $lines = @(Get-Content -LiteralPath $iniPath -Encoding UTF8 -ErrorAction SilentlyContinue)
        } catch {
            continue
        }
        $paths = ''
        $includes = ''
        foreach ($l in $lines) {
            if ($l -match '^ntfs_volume_paths\s*=') { $paths = ($l -split '=', 2)[1] }
            elseif ($l -match '^ntfs_volume_includes\s*=') { $includes = ($l -split '=', 2)[1] }
            elseif ($l -match '^sort\s*=') { $sort = ($l -split '=', 2)[1] }
            elseif ($l -match '^sort_ascending\s*=') { $sortAsc = ($l -split '=', 2)[1] }
        }
        if ($paths -ne '' -and $includes -ne '') {
            $pList = @(Split-EscapedList -Text $paths)
            $iList = @(Split-EscapedList -Text $includes)
            $thisCOver = $false
            for ($k = 0; $k -lt $pList.Count; $k++) {
                $norm = $pList[$k].Trim().TrimEnd('\')
                $inc = if ($k -lt $iList.Count) { $iList[$k].Trim() } else { '0' }
                if ($inc -eq '1') {
                    if ($norm.ToLowerInvariant() -eq $TargetDrive.TrimEnd('\').TrimEnd(':').ToLowerInvariant() + ':') {
                        $thisCOver = $true
                    } else {
                        $thisCOver = $false
                        break
                    }
                }
            }
            if ($thisCOver) { $cOnly = $true }
        }
        $details.Add($iniPath + '  paths=[' + $paths + '] includes=[' + $includes + ']')
    }

    [pscustomobject]@{
        CDriveOnly = $cOnly
        Sort = $sort
        SortAscending = $sortAsc
        Details = $details.ToArray()
    }
}

function Split-EscapedList {
    param([string]$Text)
    $result = New-Object System.Collections.Generic.List[string]
    $current = New-Object System.Text.StringBuilder
    $inQuotes = $false
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($inQuotes) {
            if ($c -eq '"') {
                if ($i + 1 -lt $Text.Length -and $Text[$i + 1] -eq '"') {
                    [void]$current.Append('"')
                    $i++
                } else {
                    $inQuotes = $false
                }
            } elseif ($c -eq '\' -and $i + 1 -lt $Text.Length -and ($Text[$i + 1] -eq '"' -or $Text[$i + 1] -eq '\')) {
                [void]$current.Append($Text[$i + 1])
                $i++
            } else {
                [void]$current.Append($c)
            }
        } else {
            if ($c -eq '"') {
                $inQuotes = $true
            } elseif ($c -eq ',') {
                $result.Add($current.ToString())
                [void]$current.Clear()
            } else {
                [void]$current.Append($c)
            }
        }
    }
    $result.Add($current.ToString())
    return $result.ToArray()
}

# ---------------------------------------------------------------------------
# Self test
# ---------------------------------------------------------------------------
function Invoke-SelfTest {
    Write-Step 'Running self-test.'
    $download = Get-EverythingStableDownload
    Write-Step ('Current stable installer detected: ' + $download.FileName)

    $service = Get-CimInstance Win32_Service -Filter "Name='Everything'" -ErrorAction SilentlyContinue
    if ($service) {
        Write-Step ('Current service state: ' + $service.State + '; start mode: ' + $service.StartMode + '; path: ' + $service.PathName)
    } else {
        Write-Step 'Current service state: missing.'
    }

    $exe = $null
    try {
        $exe = Get-EverythingExe
        Write-Step ('Current Everything.exe: ' + $exe + '; version: ' + (Get-Item $exe).VersionInfo.FileVersion)
    } catch {
        Write-Step ('Current Everything.exe: not found yet. ' + $_.Exception.Message)
    }

    $vols = @(Get-FixedNtfsVolumes)
    Write-Step ('Fixed NTFS volumes: ' + ((@($vols | ForEach-Object { $_.Letter })) -join ', '))

    $summary = Get-EverythingConfigSummary -EverythingExe $exe
    Write-Step ('Config check: c-drive-only=' + $summary.CDriveOnly + ' sort=' + $summary.Sort + ' sort_ascending=' + $summary.SortAscending)
    foreach ($line in $summary.Details) {
        Write-Step $line
    }

    Write-Step 'SELFTEST_OK'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Invoke-Main {
    Write-Step '=== Repair-EverythingIndex start ==='

    if ($SelfTest) {
        Invoke-SelfTest
        return
    }

    if (-not $AllowDestructiveRepair) {
        $message = 'BLOCKED destructive repair: rerun with -AllowDestructiveRepair only during approved maintenance.'
        Write-Step $message

        try {
            $logPath = Join-Path $LogDirectory 'EverythingRepairBlocked.log'
            New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
            Add-Content -LiteralPath $logPath -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') + ' ' + $message)
        } catch {
            # A logging failure must not turn the safety guard into a visible error.
        }

        return
    }

    if (-not (Test-IsAdmin)) {
        throw 'Run this script from an elevated PowerShell prompt, or right-click PowerShell and choose Run as administrator.'
    }

    $downloadInfo = Get-EverythingStableDownload
    $installer = Join-Path $env:TEMP $downloadInfo.FileName

    if (-not $SkipDownload) {
        Write-Step ('Downloading ' + $downloadInfo.FileName)
        $downloaded = $false
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Invoke-WebRequest -UseBasicParsing -TimeoutSec 120 $downloadInfo.Url -OutFile $installer
                $downloaded = $true
                break
            } catch {
                if ($attempt -eq 3) {
                    throw ('Download failed after 3 attempts: ' + $_.Exception.Message)
                }
                Write-Warn ('Download attempt ' + $attempt + ' failed; retrying.')
                Start-Sleep -Seconds 5
            }
        }
    } elseif (-not (Test-Path -LiteralPath $installer)) {
        throw ('SkipDownload was used, but installer is missing: ' + $installer)
    }

    Write-Step 'Performing clean teardown (processes, service, stale state).'
    Stop-EverythingRunning
    Remove-EverythingService
    Stop-EverythingRunning

    $backupPath = Backup-And-Remove-StaleEverythingState -RemoveDatabases:(-not $SkipReindex)
    Write-Step ('Backed up stale state to ' + $backupPath)

    if (-not $SkipInstall) {
        Install-Or-UpdateEverything -InstallerPath $installer
    }

    $everythingExe = Get-EverythingExe
    $versionInfo = (Get-Item $everythingExe).VersionInfo
    $sortValue = Get-EverythingSizeSortValue -FileVersion $versionInfo.FileVersion
    $fixedVolumes = @(Get-FixedNtfsVolumes)
    Write-Step ('Using ' + $everythingExe + ' (version ' + $versionInfo.FileVersion + '), fixed NTFS volumes: ' + ((@($fixedVolumes | ForEach-Object { $_.Letter })) -join ','))

    # Write the locked-down configuration (only C:, real-time monitoring,
    # ordered by size) into every config location BEFORE anything runs again.
    $userIni = Join-Path $env:APPDATA 'Everything\Everything.ini'
    $serviceIni1 = Join-Path $env:ProgramData 'Everything\Everything.ini'
    $serviceIni2 = Join-Path $env:windir 'System32\config\systemprofile\AppData\Roaming\Everything\Everything.ini'

    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($p in @(Get-EverythingIniCandidates -EverythingExe $everythingExe)) { $targets.Add($p) }
    foreach ($p in @($userIni, $serviceIni1, $serviceIni2)) {
        Ensure-EverythingIni -IniPath $p
        $targets.Add($p)
    }

    $patchedInis = @()
    foreach ($p in @($targets | Select-Object -Unique)) {
        if (Patch-EverythingIni -IniPath $p -SortValue $sortValue -TargetDrive $TargetDrive -FixedVolumes $fixedVolumes) {
            $patchedInis += $p
        }
    }
    if (@($patchedInis).Count -eq 0) {
        Write-Warn 'No Everything.ini could be patched.'
    } else {
        Write-Step ('Patched configuration in: ' + ($patchedInis -join '; '))
    }

    # Create the service, then start it. A fresh database (removed above)
    # makes it do a clean full rebuild of C: on first start.
    Create-EverythingService -EverythingExe $everythingExe
    $serviceController = Start-EverythingService

    # Launch the GUI last so it picks up the repaired configuration.
    Write-Step 'Launching Everything window.'
    Start-Process -FilePath $everythingExe
    Start-Sleep -Seconds 8
    if (-not (Get-Process everything -ErrorAction SilentlyContinue)) {
        Write-Warn 'Everything GUI did not stay running; relaunching once.'
        Start-Process -FilePath $everythingExe
        Start-Sleep -Seconds 6
    }

    # Verify and report.
    $finalService = Get-Service Everything -ErrorAction SilentlyContinue
    $finalProc = @(Get-Process everything -ErrorAction SilentlyContinue)
    $summary = Get-EverythingConfigSummary -EverythingExe $everythingExe

    $serviceText = 'missing'
    if ($finalService) { $serviceText = $finalService.Status.ToString() }
    $guiText = 'not-running'
    if (@($finalProc).Count -gt 0) { $guiText = 'running' }

    Write-Step ('DONE version=' + $versionInfo.FileVersion +
        ' service=' + $serviceText +
        ' gui=' + $guiText +
        ' c-drive-only=' + $summary.CDriveOnly +
        ' sort=' + $summary.Sort + '/' + $summary.SortAscending +
        ' patched-inis=' + @($patchedInis).Count +
        ' backup=' + $backupPath)
    foreach ($line in @($summary.Details)) {
        Write-Step $line
    }
    Write-Step '=== Repair-EverythingIndex end ==='
}

try {
    Invoke-Main
} catch {
    Write-Step ('FAILED: ' + $_.Exception.Message)
    throw
}