#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$IsoSource = "E:\isos\Windows.iso",
    [string]$ExtractDir = "C:\WinSetup",
    [string]$LocalIso = "C:\WinISO\Windows.iso",
    [ValidateSet('Fast', 'Deep')]
    [string]$Mode = 'Fast',
    [switch]$PreflightOnly,
    [ValidateSet('Auto', 'LocalFirst', 'OnlineFirst')]
    [string]$SourcePreference = 'Auto'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:IsDotSourced = $MyInvocation.InvocationName -eq '.'

function Get-LogTimestamp {
    return (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
}

function Write-Info {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[$(Get-LogTimestamp)] [INFO] $Message" -ForegroundColor Gray
}

function Write-Step {
    param(
        [Parameter(Mandatory = $true)][int]$Number,
        [Parameter(Mandatory = $true)][string]$Message
    )
    Write-Host "`n[$(Get-LogTimestamp)] [STEP $Number] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[$(Get-LogTimestamp)] [OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[$(Get-LogTimestamp)] [WARN] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[$(Get-LogTimestamp)] [FAIL] $Message" -ForegroundColor Red
    throw $Message
}

function Get-RunArtifactRoot {
    param([string]$ExtractDir)

    $programData = [Environment]::GetFolderPath('CommonApplicationData')
    if ([string]::IsNullOrWhiteSpace($programData)) {
        $programData = 'C:\ProgramData'
    }

    return Join-Path $programData 'WinSetup\Logs'
}

function New-RunArtifactPaths {
    param(
        [Parameter(Mandatory = $true)][datetime]$StartedAt,
        [Parameter(Mandatory = $true)][string]$ExtractDir
    )

    $runId = $StartedAt.ToString('yyyyMMdd-HHmmss')
    $root = Get-RunArtifactRoot -ExtractDir $ExtractDir
    $runDirectory = Join-Path $root $runId
    $transcriptPath = Join-Path $runDirectory 'transcript.log'
    $copyLogsPath = Join-Path $runDirectory 'setup-copylogs.zip'

    return [pscustomobject]@{
        RunId          = $runId
        Root           = $root
        RunDirectory   = $runDirectory
        TranscriptPath = $transcriptPath
        CopyLogsPath   = $copyLogsPath
    }
}

function Join-ArgumentString {
    param([string[]]$Arguments = @())
    if (-not $Arguments -or $Arguments.Count -eq 0) {
        return ''
    }

    $rendered = foreach ($argument in $Arguments) {
        if ($argument -match '\s') {
            '"{0}"' -f $argument
        } else {
            $argument
        }
    }

    return ($rendered -join ' ')
}

function Invoke-ExternalProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory = $true)][string]$Description,
        [int]$TimeoutSeconds = 7200,
        [int[]]$AllowedExitCodes = @(),
        [string]$WorkingDirectory
    )

    $startInfo = @{
        FilePath     = $FilePath
        ArgumentList = $Arguments
        PassThru     = $true
    }

    if ($WorkingDirectory) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }

    Write-Info ("Starting {0}: {1} {2}" -f $Description, $FilePath, (Join-ArgumentString $Arguments))
    $process = Start-Process @startInfo
    $startedAt = Get-Date

    while (-not $process.HasExited) {
        $elapsed = (Get-Date) - $startedAt
        if ($elapsed.TotalSeconds -gt $TimeoutSeconds) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            } catch {
            }
            Write-Fail ("{0} timed out after {1} minutes." -f $Description, [math]::Round($TimeoutSeconds / 60, 1))
        }

        $runtime = '{0:00}m {1:00}s' -f [math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds
        Write-Host "`r[$(Get-LogTimestamp)] [RUN] $Description ($runtime)" -NoNewline -ForegroundColor Cyan
        Start-Sleep -Milliseconds 1000
    }

    Write-Host ''
    $process.WaitForExit()
    $durationSeconds = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 1)
    $result = [pscustomobject]@{
        FilePath        = $FilePath
        Arguments       = @($Arguments)
        Description     = $Description
        ExitCode        = [int]$process.ExitCode
        DurationSeconds = $durationSeconds
        ProcessId       = $process.Id
    }

    if ($AllowedExitCodes.Count -gt 0 -and ($AllowedExitCodes -notcontains $result.ExitCode)) {
        Write-Fail ("{0} failed with exit code {1} ({2})." -f $Description, $result.ExitCode, (Get-SetupExitCodeMeaning -ExitCode $result.ExitCode))
    }

    Write-Ok ("{0} completed with exit code {1} in {2} seconds." -f $Description, $result.ExitCode, $durationSeconds)
    return $result
}

function Get-SevenZipExecutable {
    $command = Get-Command 7z -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and $command.Source) {
        return $command.Source
    }

    $whereResult = & where.exe 7z 2>$null
    if ($LASTEXITCODE -eq 0 -and $whereResult) {
        return ($whereResult | Select-Object -First 1)
    }

    return $null
}

function Invoke-SevenZipExtraction {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [string[]]$ArchiveEntries = @(),
        [string]$Description = '7-Zip extraction',
        [int]$TimeoutSeconds = 7200
    )

    $sevenZip = Get-SevenZipExecutable
    if (-not $sevenZip) {
        Write-Fail '7z.exe is required for ISO fallback extraction but was not found.'
    }

    New-Item -ItemType Directory -Path $DestinationPath -Force -ErrorAction SilentlyContinue | Out-Null
    $arguments = @('x', '-y', '-aoa', "-o$DestinationPath", $ArchivePath)
    if ($ArchiveEntries -and $ArchiveEntries.Count -gt 0) {
        $arguments += @($ArchiveEntries)
    }

    Invoke-ExternalProcess -FilePath $sevenZip -Arguments $arguments -Description $Description -TimeoutSeconds $TimeoutSeconds -AllowedExitCodes @(0) | Out-Null
}

function Convert-HexToSignedInt {
    param([Parameter(Mandatory = $true)][string]$HexCode)

    $clean = $HexCode.Trim()
    if ($clean.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) {
        $clean = $clean.Substring(2)
    }

    $unsigned = [Convert]::ToUInt32($clean, 16)
    return [BitConverter]::ToInt32([BitConverter]::GetBytes($unsigned), 0)
}

function Get-SetupExitCodeMeaning {
    param([Parameter(Mandatory = $true)][int]$ExitCode)

    $compatPass = Convert-HexToSignedInt 'C1900210'
    $messages = @{
        0                                     = 'Completed successfully'
        $compatPass                           = 'Compatibility scan passed'
        (Convert-HexToSignedInt 'C1900208')   = 'Blocking app or driver compatibility issue'
        (Convert-HexToSignedInt 'C1900204')   = 'Migration choice block'
        (Convert-HexToSignedInt 'C1900200')   = 'System requirement block'
        (Convert-HexToSignedInt 'C190020E')   = 'Insufficient disk space'
        (Convert-HexToSignedInt 'C190010E')   = 'EULA acceptance required'
        (Convert-HexToSignedInt 'C1900215')   = 'No matching install image for quiet setup'
    }

    if ($messages.ContainsKey($ExitCode)) {
        return $messages[$ExitCode]
    }

    return 'Unknown setup exit code'
}

function Normalize-Architecture {
    param([string]$Architecture)

    if ([string]::IsNullOrWhiteSpace($Architecture)) {
        return $null
    }

    $value = $Architecture.Trim().ToLowerInvariant()
    if ($value -match 'arm64') {
        return 'arm64'
    }
    if ($value -match '64') {
        return 'x64'
    }
    if ($value -match '86') {
        return 'x86'
    }

    return $value
}

function Normalize-Language {
    param([string]$Language)

    if ([string]::IsNullOrWhiteSpace($Language)) {
        return $null
    }

    $clean = ($Language.Trim() -replace '_', '-')
    if ($clean -notmatch '-') {
        return $clean.ToLowerInvariant()
    }

    $parts = $clean.Split('-', 2)
    $primary = $parts[0].ToLowerInvariant()
    $secondary = $parts[1].ToUpperInvariant()
    return '{0}-{1}' -f $primary, $secondary
}

function Get-LanguageFallbackChain {
    param(
        [string[]]$InternationalLanguages = @(),
        [string[]]$CurrentUiLanguages = @(),
        [string[]]$RegistryLanguages = @()
    )

    $ordered = @()
    $seen = @{}

    foreach ($bucket in @($InternationalLanguages, $CurrentUiLanguages, $RegistryLanguages)) {
        foreach ($language in @($bucket)) {
            $normalized = Normalize-Language $language
            if (-not $normalized) {
                continue
            }

            $key = $normalized.ToLowerInvariant()
            if ($seen.ContainsKey($key)) {
                continue
            }

            $seen[$key] = $true
            $ordered += $normalized
        }
    }

    return @($ordered)
}

function Convert-LcidHexToLanguage {
    param([string]$HexValue)

    if ([string]::IsNullOrWhiteSpace($HexValue)) {
        return $null
    }

    try {
        $lcid = [Convert]::ToInt32($HexValue.Trim(), 16)
        return (New-Object System.Globalization.CultureInfo($lcid)).Name
    } catch {
        return $null
    }
}

function Get-ParentDirectoryPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    return [System.IO.Path]::GetDirectoryName($fullPath)
}

function Normalize-EditionKey {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $text = ($Value.ToLowerInvariant() -replace '[^a-z0-9 ]', ' ' -replace '\s+', ' ').Trim()

    if ($text -match 'professional education|pro education') { return 'proeducation' }
    if ($text -match 'professional workstation|pro workstation|pro for workstations') { return 'proworkstations' }
    if ($text -match 'professional n|pro n') { return 'pron' }
    if ($text -match 'professional|pro') { return 'pro' }
    if ($text -match 'home single language|core single language') { return 'homesinglelanguage' }
    if ($text -match 'home n|core n') { return 'homen' }
    if ($text -match 'home|core') { return 'home' }
    if ($text -match 'enterprise n') { return 'enterprisen' }
    if ($text -match 'enterprise') { return 'enterprise' }
    if ($text -match 'education n') { return 'educationn' }
    if ($text -match 'education') { return 'education' }

    return ($text -replace ' ', '')
}

function Get-EditionMatchScore {
    param(
        [string]$SystemEditionKey,
        [string]$ImageEditionKey
    )

    if ([string]::IsNullOrWhiteSpace($SystemEditionKey) -or [string]::IsNullOrWhiteSpace($ImageEditionKey)) {
        return 0
    }

    if ($SystemEditionKey -eq $ImageEditionKey) {
        return 100
    }

    if ($ImageEditionKey.StartsWith($SystemEditionKey, [System.StringComparison]::OrdinalIgnoreCase)) {
        return 80
    }

    if ($SystemEditionKey.StartsWith($ImageEditionKey, [System.StringComparison]::OrdinalIgnoreCase)) {
        return 70
    }

    return 0
}

function Get-SystemLanguageCandidates {
    $international = @()
    $currentUi = @()
    $registry = @()

    try {
        $nlsLanguage = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -ErrorAction SilentlyContinue
        if ($nlsLanguage) {
            $international += Convert-LcidHexToLanguage $nlsLanguage.InstallLanguage
            $international += Convert-LcidHexToLanguage $nlsLanguage.Default
        }
    } catch {
    }

    try {
        $currentUi += [System.Globalization.CultureInfo]::InstalledUICulture.Name
    } catch {
    }

    try {
        $currentUi += [System.Globalization.CultureInfo]::CurrentCulture.Name
    } catch {
    }

    try {
        $settingsPreferred = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MUI\Settings' -ErrorAction SilentlyContinue).PreferredUILanguages
        if ($settingsPreferred) {
            $registry += @($settingsPreferred)
        }
    } catch {
    }

    try {
        Import-Module International -ErrorAction Stop | Out-Null
        try {
            $locale = Get-WinSystemLocale -ErrorAction Stop
            if ($locale -and $locale.Name) {
                $international += $locale.Name
            }
        } catch {
            Write-Warn ("Get-WinSystemLocale was unavailable: {0}" -f $_.Exception.Message)
        }
    } catch {
        Write-Warn ("International module import failed: {0}" -f $_.Exception.Message)
    }

    try {
        $currentUi += [System.Globalization.CultureInfo]::CurrentUICulture.Name
    } catch {
    }

    try {
        $muiKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\MUI\UILanguages'
        if (Test-Path -LiteralPath $muiKey) {
            $registry += (Get-ChildItem -LiteralPath $muiKey -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PSChildName)
        }
    } catch {
    }

    try {
        $preferred = (Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name PreferredUILanguages -ErrorAction SilentlyContinue).PreferredUILanguages
        if ($preferred) {
            $registry += @($preferred)
        }
    } catch {
    }

    return Get-LanguageFallbackChain -InternationalLanguages $international -CurrentUiLanguages $currentUi -RegistryLanguages $registry
}

function Get-SystemProfile {
    $currentVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $bitLockerStatus = $null
    $bitLockerActive = $false

    try {
        $bitLocker = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        $bitLockerStatus = [string]$bitLocker.ProtectionStatus
        $bitLockerActive = [int]$bitLocker.ProtectionStatus -ne 0
    } catch {
    }

    $languages = Get-SystemLanguageCandidates
    $editionId = [string]$currentVersion.EditionID

    return [pscustomobject]@{
        Build            = [int]$currentVersion.CurrentBuild
        DisplayVersion   = [string]$currentVersion.DisplayVersion
        EditionId        = $editionId
        EditionKey       = Normalize-EditionKey $editionId
        Architecture     = Normalize-Architecture $osInfo.OSArchitecture
        Languages        = @($languages)
        PrimaryLanguage  = if ($languages.Count -gt 0) { $languages[0] } else { $null }
        InstallationType = [string]$currentVersion.InstallationType
        BitLockerActive  = $bitLockerActive
        BitLockerStatus  = $bitLockerStatus
    }
}

function Get-TempWorkPath {
    param([Parameter(Mandatory = $true)][string]$Prefix)

    $base = Join-Path ([System.IO.Path]::GetTempPath()) 'repair-upgrade4'
    New-Item -ItemType Directory -Path $base -Force -ErrorAction SilentlyContinue | Out-Null
    return Join-Path $base ('{0}-{1}' -f $Prefix, ([guid]::NewGuid().ToString('N')))
}

function Resolve-InstallMediaPath {
    param(
        [string]$Candidate,
        [string]$Reason,
        [int]$Priority = 100
    )

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $null
    }

    $trimmed = $Candidate.Trim('"')
    if (-not (Test-Path -LiteralPath $trimmed)) {
        return $null
    }

    $item = Get-Item -LiteralPath $trimmed -Force -ErrorAction SilentlyContinue
    if (-not $item) {
        return $null
    }

    if (-not $item.PSIsContainer) {
        if ($item.Extension -ieq '.iso' -and $item.Length -gt 0) {
            return [pscustomobject]@{
                Kind     = 'IsoFile'
                Path     = $item.FullName
                Reason   = $Reason
                Priority = $Priority
            }
        }

        return $null
    }

    $setupPath = Join-Path $item.FullName 'setup.exe'
    if (Test-Path -LiteralPath $setupPath) {
        return [pscustomobject]@{
            Kind     = 'MediaFolder'
            Path     = $item.FullName
            Reason   = $Reason
            Priority = $Priority
        }
    }

    $isoInFolder = Get-ChildItem -LiteralPath $item.FullName -Filter '*.iso' -File -Force -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($isoInFolder) {
        return [pscustomobject]@{
            Kind     = 'IsoFile'
            Path     = $isoInFolder.FullName
            Reason   = "$Reason (ISO in folder)"
            Priority = $Priority
        }
    }

    return $null
}

function Get-LocalSourceCandidates {
    param(
        [string]$IsoSource,
        [string]$LocalIso
    )

    $candidates = @()
    $defaultPaths = @(
        [pscustomobject]@{ Path = $IsoSource; Reason = 'requested source'; Priority = 1 },
        [pscustomobject]@{ Path = $LocalIso; Reason = 'local ISO cache'; Priority = 2 },
        [pscustomobject]@{ Path = 'E:\isos\Windows.iso'; Reason = 'default local path'; Priority = 10 },
        [pscustomobject]@{ Path = 'F:\isos\Windows.iso'; Reason = 'default local path'; Priority = 11 },
        [pscustomobject]@{ Path = 'C:\Users\micha\Downloads\Windows.iso'; Reason = 'downloads fallback'; Priority = 12 },
        [pscustomobject]@{ Path = 'C:\Recovery\WindowsRE'; Reason = 'recovery media'; Priority = 20 }
    )

    foreach ($candidate in $defaultPaths) {
        if (-not [string]::IsNullOrWhiteSpace($candidate.Path)) {
            $candidates += $candidate
        }
    }

    try {
        $softwareDistribution = 'C:\Windows\SoftwareDistribution\Download'
        if (Test-Path -LiteralPath $softwareDistribution) {
            $cachedIso = Get-ChildItem -LiteralPath $softwareDistribution -Filter '*.iso' -File -Recurse -Force -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($cachedIso) {
                $candidates += [pscustomobject]@{
                    Path     = $cachedIso.FullName
                    Reason   = 'Windows Update cache ISO'
                    Priority = 30
                }
            }
        }
    } catch {
    }

    try {
        $mountedMedia = Get-Volume -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveType -eq 'CD-ROM' -and $_.DriveLetter } |
            ForEach-Object {
                [pscustomobject]@{
                    Path     = '{0}:\' -f $_.DriveLetter
                    Reason   = 'mounted media'
                    Priority = 40
                }
            }
        $candidates += @($mountedMedia)
    } catch {
    }

    return @($candidates)
}

function Get-CloudIsoCandidates {
    return @(
        'https://software-download.microsoft.com/db/Win11_23H2_English_x64.iso',
        'https://media.githubusercontent.com/media/AveYo/MediaCreationToolNet/master/releases/Windows11InstallationMedia.iso'
    )
}

function Try-DownloadCloudIso {
    [CmdletBinding()]
    param(
        [string[]]$CandidateUrls,
        [string]$DestinationPath
    )

    $destinationDir = Get-ParentDirectoryPath -Path $DestinationPath
    New-Item -ItemType Directory -Path $destinationDir -Force -ErrorAction SilentlyContinue | Out-Null

    foreach ($url in @($CandidateUrls)) {
        if ([string]::IsNullOrWhiteSpace($url)) {
            continue
        }

        Write-Info "Trying online media source: $url"
        try {
            if (Test-Path -LiteralPath $DestinationPath) {
                Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
            }

            $job = Start-BitsTransfer -Source $url -Destination $DestinationPath -Asynchronous -DisplayName 'Win11-RepairUpgrade-ISO' -Description 'Windows 11 installation media download' -ErrorAction Stop
            $startedAt = Get-Date

            while ($job.JobState -in @('Connecting', 'Queued', 'Transferring')) {
                $elapsed = (Get-Date) - $startedAt
                if ($elapsed.TotalMinutes -gt 60) {
                    Stop-BitsTransfer -BitsJob $job -ErrorAction SilentlyContinue
                    Write-Warn "BITS download timed out after 60 minutes."
                    break
                }

                if ($job.BytesTotal -gt 0) {
                    $percent = [math]::Round(($job.BytesTransferred / $job.BytesTotal) * 100, 1)
                    $transferred = [math]::Round($job.BytesTransferred / 1GB, 2)
                    $total = [math]::Round($job.BytesTotal / 1GB, 2)
                    Write-Host "`r[$(Get-LogTimestamp)] [RUN] Downloading cloud ISO: $percent% ($transferred GB / $total GB)" -NoNewline -ForegroundColor Cyan
                } else {
                    Write-Host "`r[$(Get-LogTimestamp)] [RUN] Downloading cloud ISO: negotiating size" -NoNewline -ForegroundColor Cyan
                }

                Start-Sleep -Milliseconds 750
            }

            Write-Host ''
            if ($job.JobState -eq 'Transferred') {
                Complete-BitsTransfer -BitsJob $job
            } else {
                try {
                    Remove-BitsTransfer -BitsJob $job -ErrorAction SilentlyContinue
                } catch {
                }
            }
        } catch {
            Write-Warn ("BITS download failed: {0}" -f $_.Exception.Message)
            try {
                Invoke-WebRequest -Uri $url -OutFile $DestinationPath -UseBasicParsing -TimeoutSec 3600 -ErrorAction Stop | Out-Null
            } catch {
                Write-Warn ("Web download failed: {0}" -f $_.Exception.Message)
            }
        }

        if (Test-Path -LiteralPath $DestinationPath) {
            $item = Get-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
            if ($item -and $item.Length -gt 1GB) {
                Write-Ok ("Downloaded cloud ISO to {0} ({1} GB)." -f $DestinationPath, [math]::Round($item.Length / 1GB, 2))
                return Resolve-InstallMediaPath -Candidate $DestinationPath -Reason "downloaded from $url" -Priority 5
            }
        }
    }

    return $null
}

function Expand-IsoToExtractDir {
    param(
        [Parameter(Mandatory = $true)][string]$IsoPath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    if (Test-Path -LiteralPath $DestinationPath) {
        Write-Info "Removing stale extract directory: $DestinationPath"
        Remove-DirectoryHard -Path $DestinationPath
    }

    New-Item -ItemType Directory -Path $DestinationPath -Force -ErrorAction SilentlyContinue | Out-Null
    Invoke-SevenZipExtraction -ArchivePath $IsoPath -DestinationPath $DestinationPath -Description 'Extract Windows ISO with 7-Zip'
}

function Get-InstallImagePath {
    param([Parameter(Mandatory = $true)][string]$MediaRoot)

    foreach ($candidate in @(
            (Join-Path $MediaRoot 'sources\install.wim'),
            (Join-Path $MediaRoot 'sources\install.esd')
        )) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

function Get-ImageMetadata {
    param([Parameter(Mandatory = $true)][string]$ImagePath)

    $output = (& dism.exe /English /Get-WimInfo /WimFile:"$ImagePath" /Index:1 2>&1 | Out-String)
    if ([string]::IsNullOrWhiteSpace($output)) {
        Write-Fail "DISM returned no metadata for $ImagePath."
    }

    $version = $null
    $build = $null
    $architecture = $null
    $language = $null

    foreach ($line in ($output -split "`r?`n")) {
        if ($line -match '^\s*Version\s*:\s*([0-9\.]+)\s*$') {
            $version = $Matches[1]
            if ($version -match '^\d+\.\d+\.(\d+)(?:\.\d+)?$') {
                $build = [int]$Matches[1]
            }
            continue
        }

        if ($line -match '^\s*Architecture\s*:\s*(.+?)\s*$') {
            $architecture = Normalize-Architecture $Matches[1]
            continue
        }

        if ($line -match '^\s*(?:Default|Default Language)\s*:\s*([A-Za-z0-9_-]+)\s*$') {
            $language = Normalize-Language $Matches[1]
            continue
        }
    }

    return [pscustomobject]@{
        Version         = $version
        Build           = $build
        Architecture    = $architecture
        DefaultLanguage = $language
    }
}

function Get-ImageCatalog {
    param([Parameter(Mandatory = $true)][string]$ImagePath)

    $output = (& dism.exe /English /Get-WimInfo /WimFile:"$ImagePath" 2>&1 | Out-String)
    if ([string]::IsNullOrWhiteSpace($output)) {
        Write-Fail "DISM returned no image catalog for $ImagePath."
    }

    $images = @()
    $current = $null

    foreach ($line in ($output -split "`r?`n")) {
        if ($line -match '^\s*Index\s*:\s*(\d+)\s*$') {
            if ($current) {
                $images += [pscustomobject]$current
            }

            $current = [ordered]@{
                Index       = [int]$Matches[1]
                Name        = $null
                Description = $null
            }
            continue
        }

        if (-not $current) {
            continue
        }

        if ($line -match '^\s*Name\s*:\s*(.+?)\s*$') {
            $current.Name = $Matches[1].Trim()
            continue
        }

        if ($line -match '^\s*Description\s*:\s*(.+?)\s*$') {
            $current.Description = $Matches[1].Trim()
            continue
        }
    }

    if ($current) {
        $images += [pscustomobject]$current
    }

    return @($images)
}

function Get-SourceMetadata {
    param([Parameter(Mandatory = $true)]$ResolvedSource)

    $lastWriteTimeUtc = $null
    try {
        $lastWriteTimeUtc = (Get-Item -LiteralPath $ResolvedSource.Path -Force -ErrorAction Stop).LastWriteTimeUtc
    } catch {
    }

    $metadata = [ordered]@{
        Source            = $ResolvedSource
        MediaRoot         = $null
        InstallImagePath  = $null
        Build             = $null
        Version           = $null
        Architecture      = $null
        DefaultLanguage   = $null
        Images            = @()
        LastWriteTimeUtc  = $lastWriteTimeUtc
    }

    $mountedByScript = $false
    $mediaRoot = $null
    $tempExtractRoot = $null

    try {
        if ($ResolvedSource.Kind -eq 'MediaFolder') {
            $mediaRoot = $ResolvedSource.Path
        } else {
            try {
                $mount = Mount-DiskImage -ImagePath $ResolvedSource.Path -PassThru -ErrorAction Stop
                $mountedByScript = $true
                $startedAt = Get-Date
                while (((Get-Date) - $startedAt).TotalSeconds -lt 60) {
                    Start-Sleep -Milliseconds 500
                    $volume = $mount | Get-Volume -ErrorAction SilentlyContinue
                    if ($volume -and $volume.DriveLetter) {
                        $mediaRoot = '{0}:\' -f $volume.DriveLetter
                        break
                    }
                }

                if (-not $mediaRoot) {
                    Write-Fail "Mounted ISO did not receive a drive letter within 60 seconds."
                }
            } catch {
                Write-Warn ("ISO metadata mount failed for {0}. Falling back to 7-Zip metadata extraction. {1}" -f $ResolvedSource.Path, $_.Exception.Message)
                $tempExtractRoot = Get-TempWorkPath -Prefix 'iso-meta'
                Invoke-SevenZipExtraction `
                    -ArchivePath $ResolvedSource.Path `
                    -DestinationPath $tempExtractRoot `
                    -ArchiveEntries @('sources/install.wim', 'sources/install.esd') `
                    -Description 'Extract install image from ISO with 7-Zip' `
                    -TimeoutSeconds 1800
                $mediaRoot = $tempExtractRoot
            }
        }

        $installImagePath = Get-InstallImagePath -MediaRoot $mediaRoot
        if (-not $installImagePath) {
            Write-Fail "No install.wim or install.esd was found under $mediaRoot."
        }

        $imageMetadata = Get-ImageMetadata -ImagePath $installImagePath
        $imageCatalog = Get-ImageCatalog -ImagePath $installImagePath

        $metadata.MediaRoot = $mediaRoot
        $metadata.InstallImagePath = $installImagePath
        $metadata.Build = $imageMetadata.Build
        $metadata.Version = $imageMetadata.Version
        $metadata.Architecture = $imageMetadata.Architecture
        $metadata.DefaultLanguage = $imageMetadata.DefaultLanguage
        $metadata.Images = @($imageCatalog)
    } finally {
        if ($mountedByScript) {
            try {
                Dismount-DiskImage -ImagePath $ResolvedSource.Path -ErrorAction SilentlyContinue | Out-Null
            } catch {
            }
        }
        if ($tempExtractRoot -and (Test-Path -LiteralPath $tempExtractRoot)) {
            try {
                Remove-Item -LiteralPath $tempExtractRoot -Recurse -Force -ErrorAction SilentlyContinue
            } catch {
            }
        }
    }

    return [pscustomobject]$metadata
}

function Resolve-ImageSelection {
    param(
        [Parameter(Mandatory = $true)]$SystemProfile,
        [Parameter(Mandatory = $true)][object[]]$Images
    )

    if (-not $Images -or $Images.Count -eq 0) {
        return [pscustomobject]@{
            Resolved           = $false
            Ambiguous          = $true
            Reason             = 'No install images were found in the media.'
            SelectedImageIndex = $null
            SelectedImageName  = $null
            Candidates         = @()
        }
    }

    if ($Images.Count -eq 1) {
        return [pscustomobject]@{
            Resolved           = $true
            Ambiguous          = $false
            Reason             = 'Single install image available.'
            SelectedImageIndex = [int]$Images[0].Index
            SelectedImageName  = [string]$Images[0].Name
            Candidates         = @($Images)
        }
    }

    $editionKey = Normalize-EditionKey $SystemProfile.EditionKey
    if (-not $editionKey) {
        $editionKey = Normalize-EditionKey $SystemProfile.EditionId
    }

    $scored = foreach ($image in $Images) {
        $imageEditionKey = Normalize-EditionKey ('{0} {1}' -f $image.Name, $image.Description)
        [pscustomobject]@{
            Image          = $image
            EditionKey     = $imageEditionKey
            MatchScore     = Get-EditionMatchScore -SystemEditionKey $editionKey -ImageEditionKey $imageEditionKey
        }
    }

    $matches = @(
        $scored |
            Where-Object { $_.MatchScore -gt 0 } |
            Sort-Object @{ Expression = { $_.MatchScore }; Descending = $true }, @{ Expression = { $_.Image.Index }; Descending = $false }
    )
    if ($matches.Count -eq 1) {
        return [pscustomobject]@{
            Resolved           = $true
            Ambiguous          = $false
            Reason             = 'Matched install image by edition.'
            SelectedImageIndex = [int]$matches[0].Image.Index
            SelectedImageName  = [string]$matches[0].Image.Name
            Candidates         = @($matches.Image)
        }
    }

    if ($matches.Count -gt 1) {
        $topScore = $matches[0].MatchScore
        $topMatches = @($matches | Where-Object { $_.MatchScore -eq $topScore })
        if ($topMatches.Count -eq 1) {
            return [pscustomobject]@{
                Resolved           = $true
                Ambiguous          = $false
                Reason             = 'Matched install image by best edition score.'
                SelectedImageIndex = [int]$topMatches[0].Image.Index
                SelectedImageName  = [string]$topMatches[0].Image.Name
                Candidates         = @($topMatches.Image)
            }
        }

        return [pscustomobject]@{
            Resolved           = $false
            Ambiguous          = $true
            Reason             = 'Multiple install images matched the current edition.'
            SelectedImageIndex = $null
            SelectedImageName  = $null
            Candidates         = @($topMatches.Image)
        }
    }

    return [pscustomobject]@{
        Resolved           = $false
        Ambiguous          = $true
        Reason             = 'No install image matched the current edition.'
        SelectedImageIndex = $null
        SelectedImageName  = $null
        Candidates         = @($Images)
    }
}

function Get-MediaEvaluation {
    param(
        [Parameter(Mandatory = $true)]$SystemProfile,
        [Parameter(Mandatory = $true)]$SourceMetadata
    )

    $imageSelection = Resolve-ImageSelection -SystemProfile $SystemProfile -Images $SourceMetadata.Images
    $architectureCompatible = $true
    $languageCompatible = $true
    $buildCompatible = $true
    $buildKnown = $SourceMetadata.Build -ne $null

    if ($SourceMetadata.Architecture) {
        $architectureCompatible = $SourceMetadata.Architecture -eq $SystemProfile.Architecture
    }

    if ($SourceMetadata.DefaultLanguage -and $SystemProfile.Languages.Count -gt 0) {
        $languageCompatible = @($SystemProfile.Languages) -contains (Normalize-Language $SourceMetadata.DefaultLanguage)
    }

    if ($buildKnown -and $SystemProfile.Build) {
        $buildCompatible = [int]$SourceMetadata.Build -ge [int]$SystemProfile.Build
    }

    $buildDelta = if ($buildKnown -and $SystemProfile.Build) {
        [math]::Abs([int]$SourceMetadata.Build - [int]$SystemProfile.Build)
    } else {
        [int]::MaxValue
    }

    $compatible = $architectureCompatible -and $languageCompatible -and $buildCompatible -and $imageSelection.Resolved
    $reasons = @()
    if (-not $architectureCompatible) { $reasons += 'architecture mismatch' }
    if (-not $languageCompatible) { $reasons += 'language mismatch' }
    if (-not $buildCompatible) { $reasons += 'media build older than current OS' }
    if (-not $imageSelection.Resolved) { $reasons += $imageSelection.Reason }

    return [pscustomobject]@{
        Source                 = $SourceMetadata.Source
        SourceMetadata         = $SourceMetadata
        ImageSelection         = $imageSelection
        Compatible             = $compatible
        ArchitectureCompatible = $architectureCompatible
        LanguageCompatible     = $languageCompatible
        BuildCompatible        = $buildCompatible
        BuildKnown             = $buildKnown
        BuildDelta             = $buildDelta
        FailureReason          = if ($reasons.Count -gt 0) { $reasons -join '; ' } else { $null }
    }
}

function Get-SourceEvaluations {
    param(
        [Parameter(Mandatory = $true)][object[]]$Candidates,
        [Parameter(Mandatory = $true)]$SystemProfile
    )

    $evaluations = @()
    $seen = @{}

    foreach ($candidate in @($Candidates)) {
        $resolved = Resolve-InstallMediaPath -Candidate $candidate.Path -Reason $candidate.Reason -Priority $candidate.Priority
        if (-not $resolved) {
            continue
        }

        $key = $resolved.Path.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            continue
        }

        $seen[$key] = $true
        try {
            $metadata = Get-SourceMetadata -ResolvedSource $resolved
            $evaluations += Get-MediaEvaluation -SystemProfile $SystemProfile -SourceMetadata $metadata
        } catch {
            $evaluations += [pscustomobject]@{
                Source                 = $resolved
                SourceMetadata         = $null
                ImageSelection         = [pscustomobject]@{
                    Resolved           = $false
                    Ambiguous          = $true
                    Reason             = $_.Exception.Message
                    SelectedImageIndex = $null
                    SelectedImageName  = $null
                    Candidates         = @()
                }
                Compatible             = $false
                ArchitectureCompatible = $false
                LanguageCompatible     = $false
                BuildCompatible        = $false
                BuildKnown             = $false
                BuildDelta             = [int]::MaxValue
                FailureReason          = $_.Exception.Message
            }
        }
    }

    return @($evaluations)
}

function Select-BestEvaluation {
    param(
        [Parameter(Mandatory = $true)][object[]]$Evaluations,
        [switch]$RequireCompatible
    )

    $pool = @($Evaluations)
    if ($RequireCompatible) {
        $pool = @($pool | Where-Object { $_.Compatible })
    }

    if (-not $pool -or $pool.Count -eq 0) {
        return $null
    }

    return $pool |
        Sort-Object `
            @{ Expression = { $_.Compatible }; Descending = $true }, `
            @{ Expression = { $_.BuildCompatible }; Descending = $true }, `
            @{ Expression = { $_.ImageSelection.Resolved }; Descending = $true }, `
            @{ Expression = { $_.BuildDelta }; Descending = $false }, `
            @{ Expression = { $_.Source.Priority }; Descending = $false }, `
            @{ Expression = { if ($_.SourceMetadata -and $_.SourceMetadata.LastWriteTimeUtc) { $_.SourceMetadata.LastWriteTimeUtc } else { [datetime]::MinValue } }; Descending = $true } |
        Select-Object -First 1
}

function Format-EvaluationSummary {
    param([Parameter(Mandatory = $true)][object[]]$Evaluations)

    if (-not $Evaluations -or $Evaluations.Count -eq 0) {
        return 'No usable install media candidates were found.'
    }

    $lines = foreach ($evaluation in $Evaluations) {
        $status = if ($evaluation.Compatible) { 'compatible' } else { 'rejected' }
        $reason = if ($evaluation.FailureReason) { $evaluation.FailureReason } else { 'passed all compatibility checks' }
        '- {0} [{1}] via {2}: {3}' -f $evaluation.Source.Path, $status, $evaluation.Source.Reason, $reason
    }

    return ($lines -join [Environment]::NewLine)
}

function Remove-DirectoryHard {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$MaxAttempts = 6
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Write-Info "Removing locked folder $Path"
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Write-Info ("Locked-folder cleanup attempt {0}/{1}: {2}" -f $attempt, $MaxAttempts, $Path)
        $setupProcesses = Get-CimInstance Win32_Process -Filter "Name='setup.exe' OR Name='SetupHost.exe' OR Name='setupprep.exe'" -ErrorAction SilentlyContinue
        $stoppedCount = 0
        foreach ($process in @($setupProcesses)) {
            $exePath = $process.ExecutablePath
            if ($exePath -and $exePath.StartsWith($Path, [System.StringComparison]::OrdinalIgnoreCase)) {
                try {
                    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
                    $stoppedCount++
                } catch {
                }
            }
        }
        if ($stoppedCount -gt 0) {
            Write-Info ("Stopped {0} setup-related process(es) from {1}" -f $stoppedCount, $Path)
        }

        Write-Info "Normalizing file attributes under $Path"
        Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $_.Attributes = [System.IO.FileAttributes]::Normal
            } catch {
            }
        }

        try {
            (Get-Item -LiteralPath $Path -Force -ErrorAction Stop).Attributes = [System.IO.FileAttributes]::Directory
        } catch {
        }

        Write-Info "Attempting direct delete of $Path before ownership escalation"
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Ok "Removed locked folder $Path"
            return
        }

        Write-Warn "Direct delete did not remove $Path; escalating ownership and ACL repair."
        Write-Info "Taking ownership of $Path"
        Invoke-ExternalProcess -FilePath 'takeown.exe' -Arguments @('/F', $Path, '/R', '/D', 'Y') -Description "takeown $Path" -TimeoutSeconds 600 -AllowedExitCodes @(0, 1) | Out-Null
        Write-Info "Granting Administrators full control on $Path"
        Invoke-ExternalProcess -FilePath 'icacls.exe' -Arguments @($Path, '/grant', '*S-1-5-32-544:(OI)(CI)F', '/T', '/C') -Description "icacls $Path" -TimeoutSeconds 600 -AllowedExitCodes @(0, 1) | Out-Null

        Write-Info "Deleting $Path"
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Ok "Removed locked folder $Path"
            return
        }

        Write-Warn ("Folder still present after attempt {0}: {1}" -f $attempt, $Path)
        Start-Sleep -Seconds 2
    }

    Write-Fail "Failed to remove locked folder: $Path"
}

function Test-PortableExecutableFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item -or $item.Length -lt 128) {
        return $false
    }

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object System.IO.BinaryReader($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            return $false
        }

        $stream.Seek(60, [System.IO.SeekOrigin]::Begin) | Out-Null
        $peOffset = $reader.ReadInt32()
        if ($peOffset -le 0 -or $peOffset -gt ($stream.Length - 6)) {
            return $false
        }

        $stream.Seek($peOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
        if ($reader.ReadUInt32() -ne 0x00004550) {
            return $false
        }

        return $reader.ReadUInt16() -ne 0
    } finally {
        $stream.Dispose()
    }
}

function Repair-InvalidExtractedPortableExecutables {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    $invalid = @(
        Get-ChildItem -LiteralPath $DestinationRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Extension -in '.dll', '.exe' -and
                -not (Test-PortableExecutableFile -Path $_.FullName)
            }
    )

    if ($invalid.Count -eq 0) {
        Write-Ok 'Portable executable validation passed for extracted media.'
        return
    }

    Write-Warn ("Found {0} invalid extracted executable image(s); recopying them safely from source media." -f $invalid.Count)
    foreach ($file in $invalid) {
        $relativePath = $file.FullName.Substring($DestinationRoot.TrimEnd('\').Length).TrimStart('\')
        $sourcePath = Join-Path $SourceRoot $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            Write-Fail "Source file missing during extraction repair: $relativePath"
        }

        Copy-Item -LiteralPath $sourcePath -Destination $file.FullName -Force
        if (-not (Test-PortableExecutableFile -Path $file.FullName)) {
            Write-Fail "Repaired file is still invalid: $relativePath"
        }

        Write-Ok "Repaired $relativePath"
    }

    $remaining = @(
        Get-ChildItem -LiteralPath $DestinationRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Extension -in '.dll', '.exe' -and
                -not (Test-PortableExecutableFile -Path $_.FullName)
            } |
            Select-Object -ExpandProperty FullName
    )

    if ($remaining.Count -gt 0) {
        Write-Fail ("Portable executable validation still failing after repair: {0}" -f (($remaining | Select-Object -First 10) -join ', '))
    }

    Write-Ok 'Portable executable validation passed after repair copy.'
}

function Copy-IsoWithProgress {
    param(
        [Parameter(Mandatory = $true)][string]$SourceIso,
        [Parameter(Mandatory = $true)][string]$DestinationIso
    )

    $sourceFullName = (Get-Item -LiteralPath $SourceIso -Force -ErrorAction Stop).FullName
    $destinationDir = Get-ParentDirectoryPath -Path $DestinationIso
    New-Item -ItemType Directory -Path $destinationDir -Force -ErrorAction SilentlyContinue | Out-Null

    if ($sourceFullName.Equals($DestinationIso, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Ok "ISO is already staged at $DestinationIso."
        return $DestinationIso
    }

    if (Test-Path -LiteralPath $DestinationIso) {
        Write-Info "Removing stale staged ISO at $DestinationIso before refreshing it."
        Remove-Item -LiteralPath $DestinationIso -Force -ErrorAction Stop
    }

    $sourceItem = Get-Item -LiteralPath $SourceIso -Force -ErrorAction Stop
    $sourceSize = $sourceItem.Length
    $fileName = Split-Path -LiteralPath $SourceIso -Leaf
    $logPath = Join-Path $env:TEMP 'repair-upgrade4-robocopy-iso.log'
    if (Test-Path -LiteralPath $logPath) {
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    }

    Write-Info "Copying ISO to $DestinationIso"
    $process = Start-Process robocopy -ArgumentList @(
            (Get-ParentDirectoryPath -Path $SourceIso),
            $destinationDir,
            $fileName,
            '/MT:8',
            '/R:1',
            '/W:1',
            '/NFL',
            '/NDL',
            '/NJH',
            '/NJS',
            '/NP'
        ) -NoNewWindow -PassThru -RedirectStandardOutput $logPath

    $startedAt = Get-Date
    while (-not $process.HasExited) {
        if (((Get-Date) - $startedAt).TotalMinutes -gt 30) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            } catch {
            }
            Write-Fail "ISO copy timed out after 30 minutes."
        }

        if (Test-Path -LiteralPath $DestinationIso) {
            $copiedSize = (Get-Item -LiteralPath $DestinationIso -Force -ErrorAction SilentlyContinue).Length
            $percent = [math]::Round(($copiedSize / $sourceSize) * 100, 1)
            $copiedGb = [math]::Round($copiedSize / 1GB, 2)
            $totalGb = [math]::Round($sourceSize / 1GB, 2)
            Write-Host "`r[$(Get-LogTimestamp)] [RUN] ISO copy $percent% ($copiedGb GB / $totalGb GB)" -NoNewline -ForegroundColor Cyan
        }

        Start-Sleep -Milliseconds 750
    }

    Write-Host ''
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    if (Test-Path -LiteralPath $logPath) {
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    }

    $copiedItem = Get-Item -LiteralPath $DestinationIso -Force -ErrorAction SilentlyContinue
    if ($exitCode -ge 8 -or -not $copiedItem -or $copiedItem.Length -ne $sourceSize) {
        Write-Fail "ISO copy failed before a complete staged ISO was produced."
    }

    Write-Ok ("ISO staged at {0} ({1} GB)." -f $DestinationIso, [math]::Round($copiedItem.Length / 1GB, 2))
    return $DestinationIso
}

function Mount-IsoAndGetMediaRoot {
    param([Parameter(Mandatory = $true)][string]$IsoPath)

    try {
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
    } catch {
    }

    $mount = Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop
    $startedAt = Get-Date
    while (((Get-Date) - $startedAt).TotalSeconds -lt 60) {
        Start-Sleep -Milliseconds 500
        $volume = $mount | Get-Volume -ErrorAction SilentlyContinue
        if ($volume -and $volume.DriveLetter) {
            $mediaRoot = '{0}:\' -f $volume.DriveLetter
            Write-Ok "Mounted $IsoPath at $mediaRoot"
            return [pscustomobject]@{
                Mount     = $mount
                MediaRoot = $mediaRoot
                IsoPath   = $IsoPath
            }
        }
    }

    Write-Fail "Mounted ISO did not receive a drive letter within 60 seconds."
}

function Copy-MediaToExtractDir {
    param(
        [Parameter(Mandatory = $true)][string]$MediaRoot,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    if (Test-Path -LiteralPath $DestinationPath) {
        Write-Info "Removing stale extract directory: $DestinationPath"
        Remove-DirectoryHard -Path $DestinationPath
    }

    New-Item -ItemType Directory -Path $DestinationPath -Force -ErrorAction SilentlyContinue | Out-Null
    $logPath = Join-Path $env:TEMP 'repair-upgrade4-robocopy-media.log'
    if (Test-Path -LiteralPath $logPath) {
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    }

    Write-Info "Extracting installation media to $DestinationPath"
    $process = Start-Process robocopy -ArgumentList @(
            $MediaRoot,
            $DestinationPath,
            '/E',
            '/MT:8',
            '/R:1',
            '/W:1',
            '/NFL',
            '/NDL',
            '/NJH',
            '/NJS',
            '/NP'
        ) -NoNewWindow -PassThru -RedirectStandardOutput $logPath

    $lastLine = $null
    while (-not $process.HasExited) {
        try {
            $lines = @(Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue)
            if ($lines.Count -gt 0 -and $lines[-1] -ne $lastLine) {
                $lastLine = $lines[-1]
                Write-Host "`r[$(Get-LogTimestamp)] [RUN] Extracting media: $lastLine" -NoNewline -ForegroundColor Cyan
            }
        } catch {
        }
        Start-Sleep -Milliseconds 750
    }

    Write-Host ''
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    if (Test-Path -LiteralPath $logPath) {
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    }

    if ($exitCode -ge 8) {
        Write-Fail "Media extraction failed with robocopy exit code $exitCode."
    }

    Repair-InvalidExtractedPortableExecutables -SourceRoot $MediaRoot -DestinationRoot $DestinationPath
    Write-Ok "Installation media extracted to $DestinationPath."
}

function Test-ExtractedMedia {
    param([Parameter(Mandatory = $true)][string]$ExtractDir)

    $criticalFiles = @(
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

    $missing = @()
    foreach ($file in $criticalFiles) {
        $path = Join-Path $ExtractDir $file
        if (-not (Test-Path -LiteralPath $path)) {
            $missing += $file
        }
    }

    $installImagePresent = (Test-Path -LiteralPath (Join-Path $ExtractDir 'sources\install.wim')) -or
        (Test-Path -LiteralPath (Join-Path $ExtractDir 'sources\install.esd'))

    if (-not $installImagePresent) {
        $missing += 'sources\install.wim or sources\install.esd'
    }

    if ($missing.Count -gt 0) {
        Write-Fail ("Extracted media is missing required files: {0}" -f ($missing -join ', '))
    }

    $fileCount = (Get-ChildItem -LiteralPath $ExtractDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Ok ("Verified extracted media: {0} files and all critical setup components present." -f $fileCount)
}

function Get-PendingFileRenameCount {
    $sessionManager = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if (-not $sessionManager) {
        return 0
    }

    $property = $sessionManager.PSObject.Properties['PendingFileRenameOperations']
    if (-not $property) {
        return 0
    }

    $value = $property.Value
    if (-not $value) {
        return 0
    }

    return @($value).Count
}

function Clear-PendingFileRenameOperations {
    $count = Get-PendingFileRenameCount
    Write-Info ("PendingFileRenameOperations entries detected: {0}" -f $count)
    if ($count -gt 0) {
        Remove-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -Force -ErrorAction SilentlyContinue
        Write-Ok "Cleared PendingFileRenameOperations ($count entries)."
    } else {
        Write-Ok 'PendingFileRenameOperations was already clear.'
    }

    return $count
}

function Get-RebootPendingStatus {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )

    $presentPaths = @($paths | Where-Object { Test-Path -LiteralPath $_ })
    $pendingFileRenames = Get-PendingFileRenameCount

    return [pscustomobject]@{
        IsPending               = ($presentPaths.Count -gt 0) -or ($pendingFileRenames -gt 0)
        PendingPaths            = @($presentPaths)
        PendingFileRenameCount  = $pendingFileRenames
    }
}

function Clear-RebootPendingFlags {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )

    $cleared = 0
    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path) {
            Write-Info ("Clearing reboot flag at {0}" -f $path)
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            Write-Ok ("Cleared reboot flag: {0}" -f (Split-Path -Path $path -Leaf))
            $cleared++
        }
    }

    if ($cleared -eq 0) {
        Write-Ok 'No reboot-pending registry flags were present.'
    }

    Clear-PendingFileRenameOperations | Out-Null
}

function Stop-IISServices {
    foreach ($name in @('W3SVC', 'WAS', 'IISADMIN')) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            Write-Info "Stopping IIS-related service $name"
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            $startedAt = Get-Date
            $lastHeartbeat = [datetime]::MinValue
            while (((Get-Date) - $startedAt).TotalSeconds -lt 30) {
                $service.Refresh()
                if ($service.Status -eq 'Stopped') {
                    break
                }

                if (((Get-Date) - $lastHeartbeat).TotalSeconds -ge 5) {
                    Write-Info ("Waiting for {0} to stop (current status: {1})" -f $name, $service.Status)
                    $lastHeartbeat = Get-Date
                }

                Start-Sleep -Milliseconds 500
            }

            $service.Refresh()
            if ($service.Status -eq 'Stopped') {
                Write-Ok "Stopped IIS-related service $name."
            } else {
                Write-Warn "IIS-related service $name could not be confirmed as stopped."
            }
        } else {
            Write-Ok "IIS-related service $name was already stopped or not installed."
        }
    }
}

function Ensure-RequiredServices {
    $required = @(
        @{ Name = 'wuauserv'; Startup = 'Manual' },
        @{ Name = 'BITS'; Startup = 'Manual' },
        @{ Name = 'cryptsvc'; Startup = 'Automatic' },
        @{ Name = 'TrustedInstaller'; Startup = 'Manual' },
        @{ Name = 'DiagTrack'; Startup = 'Manual' },
        @{ Name = 'msiserver'; Startup = 'Manual' }
    )

    foreach ($entry in $required) {
        $service = Get-Service -Name $entry.Name -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-Warn "$($entry.Name) is not installed on this machine."
            continue
        }

        Write-Info ("Ensuring service {0} is running (startup: {1})" -f $entry.Name, $entry.Startup)
        Set-Service -Name $entry.Name -StartupType $entry.Startup -ErrorAction SilentlyContinue
        $startedAt = Get-Date
        $lastHeartbeat = [datetime]::MinValue
        while (((Get-Date) - $startedAt).TotalSeconds -lt 30) {
            $service.Refresh()
            if ($service.Status -eq 'Running') {
                break
            }

            try {
                Start-Service -Name $entry.Name -ErrorAction SilentlyContinue
            } catch {
            }

            if (((Get-Date) - $lastHeartbeat).TotalSeconds -ge 5) {
                Write-Info ("Waiting for service {0} to reach Running (current status: {1})" -f $entry.Name, $service.Status)
                $lastHeartbeat = Get-Date
            }
            Start-Sleep -Milliseconds 500
        }

        $service = Get-Service -Name $entry.Name -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            Write-Ok "$($entry.Name) is running."
        } else {
            Write-Warn "$($entry.Name) could not be confirmed as running."
        }
    }
}

function Get-PreviousSetupSignals {
    $pantherDir = 'C:\$WINDOWS.~BT\Sources\Panther'
    $setuperr = Join-Path $pantherDir 'setuperr.log'
    $hasPantherLogs = Test-Path -LiteralPath $pantherDir
    $hasCompatLogs = $false
    $previousExitCode = $null

    if ($hasPantherLogs) {
        $compatPatterns = @('CompatData*.xml', '*_APPRAISER_HumanReadable.xml')
        foreach ($pattern in $compatPatterns) {
            $match = Get-ChildItem -LiteralPath $pantherDir -Filter $pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($match) {
                $hasCompatLogs = $true
                break
            }
        }
    }

    if (Test-Path -LiteralPath $setuperr) {
        $hexMatches = Select-String -LiteralPath $setuperr -Pattern '0xC190[0-9A-Fa-f]{4}' -AllMatches -ErrorAction SilentlyContinue
        $allValues = @()
        foreach ($entry in @($hexMatches)) {
            foreach ($match in @($entry.Matches)) {
                $allValues += $match.Value
            }
        }

        if ($allValues.Count -gt 0) {
            $previousExitCode = Convert-HexToSignedInt $allValues[-1]
        }
    }

    return [pscustomobject]@{
        HasPantherLogs    = $hasPantherLogs
        HasCompatLogs     = $hasCompatLogs
        PreviousSetupExitCode = $previousExitCode
    }
}

function Test-ShouldEscalateToDeepMode {
    param(
        [ValidateSet('Fast', 'Deep')]
        [string]$RequestedMode = 'Fast',
        [bool]$HasPriorPantherLogs = $false,
        [bool]$HasCompatLogs = $false,
        [Nullable[int]]$PreviousSetupExitCode = $null,
        [bool]$RebootPendingAfterCleanup = $false,
        [bool]$MediaMatchingAmbiguous = $false
    )

    $reasons = @()
    if ($RequestedMode -eq 'Deep') {
        $reasons += 'Deep mode was requested'
    }
    if ($HasPriorPantherLogs) {
        $reasons += 'prior Panther logs were detected'
    }
    if ($HasCompatLogs) {
        $reasons += 'prior compatibility logs were detected'
    }
    if ($RebootPendingAfterCleanup) {
        $reasons += 'reboot-pending state survived cleanup'
    }
    if ($MediaMatchingAmbiguous) {
        $reasons += 'quiet image matching is ambiguous'
    }

    $blockingCodes = @(
        (Convert-HexToSignedInt 'C1900208'),
        (Convert-HexToSignedInt 'C1900204'),
        (Convert-HexToSignedInt 'C1900200'),
        (Convert-HexToSignedInt 'C190020E'),
        (Convert-HexToSignedInt 'C190010E'),
        (Convert-HexToSignedInt 'C1900215')
    )

    if ($PreviousSetupExitCode -ne $null -and $blockingCodes -contains [int]$PreviousSetupExitCode) {
        $reasons += ('previous setup exit code was blocking: {0}' -f (Get-SetupExitCodeMeaning -ExitCode ([int]$PreviousSetupExitCode)))
    }

    return [pscustomobject]@{
        ShouldEscalate = $reasons.Count -gt 0
        Reasons        = @($reasons)
    }
}

function Get-ExecutionPlan {
    param(
        [ValidateSet('Fast', 'Deep')]
        [string]$RequestedMode = 'Fast',
        [switch]$PreflightOnly,
        [bool]$HasPriorPantherLogs = $false,
        [bool]$HasCompatLogs = $false,
        [Nullable[int]]$PreviousSetupExitCode = $null,
        [bool]$RebootPendingAfterCleanup = $false,
        [bool]$MediaMatchingAmbiguous = $false
    )

    $escalation = Test-ShouldEscalateToDeepMode `
        -RequestedMode $RequestedMode `
        -HasPriorPantherLogs:$HasPriorPantherLogs `
        -HasCompatLogs:$HasCompatLogs `
        -PreviousSetupExitCode $PreviousSetupExitCode `
        -RebootPendingAfterCleanup:$RebootPendingAfterCleanup `
        -MediaMatchingAmbiguous:$MediaMatchingAmbiguous

    $useDeepPath = $RequestedMode -eq 'Deep' -or $escalation.ShouldEscalate

    return [pscustomobject]@{
        UseDeepPath       = $useDeepPath
        RunCompatScan     = $useDeepPath
        RunDeepServicing  = $useDeepPath
        LaunchUpgrade     = -not $PreflightOnly.IsPresent
        CanLaunchUpgrade  = -not $MediaMatchingAmbiguous
        EscalationReasons = @($escalation.Reasons)
    }
}

function Reset-UpdateCaches {
    $services = @('wuauserv', 'BITS', 'cryptsvc', 'msiserver', 'UsoSvc', 'DoSvc')
    Write-Info 'Resetting Windows Update and servicing caches.'
    foreach ($name in $services) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            Write-Info "Stopping $name for component reset"
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            Write-Ok "Stopped $name for component reset."
        } else {
            Write-Ok "$name was already stopped or not installed."
        }
    }

    $stamp = Get-Date -Format 'yyyyMMddHHmmss'
    $softwareDistribution = 'C:\Windows\SoftwareDistribution'
    $softwareDistributionBak = "C:\Windows\SoftwareDistribution.bak.$stamp"
    $catroot2 = 'C:\Windows\System32\catroot2'
    $catroot2Bak = "C:\Windows\System32\catroot2.bak.$stamp"

    if (Test-Path -LiteralPath $softwareDistribution) {
        Write-Info 'Renaming SoftwareDistribution'
        Move-Item -LiteralPath $softwareDistribution -Destination $softwareDistributionBak -Force -ErrorAction Stop
        Write-Ok "Reset SoftwareDistribution to $softwareDistributionBak"
    }

    if (Test-Path -LiteralPath $catroot2) {
        Write-Info 'Renaming catroot2'
        Move-Item -LiteralPath $catroot2 -Destination $catroot2Bak -Force -ErrorAction Stop
        Write-Ok "Reset catroot2 to $catroot2Bak"
    }

    $bitsQueuePath = Join-Path $env:ProgramData 'Microsoft\Network\Downloader'
    if (Test-Path -LiteralPath $bitsQueuePath) {
        Get-ChildItem -LiteralPath $bitsQueuePath -Filter 'qmgr*.dat' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Ok 'Cleared BITS queue files.'
    }

    $deliveryCache = Join-Path $env:ProgramData 'Microsoft\Windows\DeliveryOptimization\Cache'
    if (Test-Path -LiteralPath $deliveryCache) {
        Get-ChildItem -LiteralPath $deliveryCache -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok 'Cleared Delivery Optimization cache.'
    }

    foreach ($name in $services) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($service) {
            try {
                Write-Info "Restarting $name after component reset"
                Start-Service -Name $name -ErrorAction SilentlyContinue
            } catch {
            }
        }
    }

    foreach ($name in @('wuauserv', 'BITS', 'cryptsvc')) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $service -or $service.Status -ne 'Running') {
            Write-Fail "$name did not return to a running state after component reset."
        }
    }
}

function Invoke-DeepServicing {
    Write-Info 'Running deep servicing path.'
    Reset-UpdateCaches
    Invoke-ExternalProcess -FilePath 'dism.exe' -Arguments @('/Online', '/Cleanup-Image', '/StartComponentCleanup') -Description 'DISM StartComponentCleanup' -TimeoutSeconds 5400 -AllowedExitCodes @(0) | Out-Null
    Invoke-ExternalProcess -FilePath 'dism.exe' -Arguments @('/Online', '/Cleanup-Image', '/CheckHealth') -Description 'DISM CheckHealth' -TimeoutSeconds 1200 -AllowedExitCodes @(0) | Out-Null
    Invoke-ExternalProcess -FilePath 'dism.exe' -Arguments @('/Online', '/Cleanup-Image', '/ScanHealth') -Description 'DISM ScanHealth' -TimeoutSeconds 5400 -AllowedExitCodes @(0) | Out-Null
    Invoke-ExternalProcess -FilePath 'dism.exe' -Arguments @('/Online', '/Cleanup-Image', '/RestoreHealth') -Description 'DISM RestoreHealth' -TimeoutSeconds 10800 -AllowedExitCodes @(0) | Out-Null
    Invoke-ExternalProcess -FilePath 'sfc.exe' -Arguments @('/scannow') -Description 'SFC ScanNow' -TimeoutSeconds 7200 -AllowedExitCodes @(0, 1) | Out-Null
    Invoke-ExternalProcess -FilePath 'netsh.exe' -Arguments @('winhttp', 'reset', 'proxy') -Description 'Reset WinHTTP proxy' -TimeoutSeconds 600 -AllowedExitCodes @(0, 1) | Out-Null
}

function New-SetupArgumentList {
    param(
        [ValidateSet('Fast', 'Deep')]
        [string]$Mode = 'Fast',
        [switch]$ScanOnly,
        [switch]$NoReboot,
        [switch]$Quiet,
        [int]$ImageIndex,
        [string]$CopyLogsPath,
        [switch]$BitLockerAlwaysSuspend,
        [ValidateSet('Disable', 'NoDrivers')]
        [string]$DynamicUpdate = 'Disable'
    )

    $arguments = @('/Auto', 'Upgrade')

    if ($Quiet) {
        $arguments += @('/Quiet')
    }

    if ($NoReboot) {
        $arguments += @('/NoReboot')
    }

    $arguments += @('/DynamicUpdate', $DynamicUpdate)
    $arguments += @('/MigrateDrivers', 'All')
    $arguments += @('/ShowOOBE', 'None')
    $arguments += @('/Telemetry', 'Disable')

    if ($BitLockerAlwaysSuspend) {
        $arguments += @('/BitLocker', 'AlwaysSuspend')
    }

    if ($ScanOnly) {
        $arguments += @('/Compat', 'ScanOnly', '/Compat', 'IgnoreWarning')
    } else {
        $arguments += @('/Compat', 'IgnoreWarning')
    }

    $arguments += @('/EULA', 'Accept')

    if ($ImageIndex -gt 0) {
        $arguments += @('/ImageIndex', [string]$ImageIndex)
    }

    if (-not [string]::IsNullOrWhiteSpace($CopyLogsPath)) {
        $arguments += @('/CopyLogs', $CopyLogsPath)
    }

    return @($arguments)
}

function Invoke-SetupCompatibilityScan {
    param(
        [Parameter(Mandatory = $true)][string]$SetupPath,
        [Parameter(Mandatory = $true)][int]$ImageIndex,
        [Parameter(Mandatory = $true)][string]$CopyLogsPath,
        [switch]$BitLockerAlwaysSuspend
    )

    $arguments = New-SetupArgumentList -Mode Deep -ScanOnly -NoReboot -Quiet -ImageIndex $ImageIndex -CopyLogsPath $CopyLogsPath -BitLockerAlwaysSuspend:$BitLockerAlwaysSuspend -DynamicUpdate NoDrivers
    $result = Invoke-ExternalProcess -FilePath $SetupPath -Arguments $arguments -Description 'Windows Setup compatibility scan' -TimeoutSeconds 7200
    $result | Add-Member -NotePropertyName ArgumentList -NotePropertyValue @($arguments) -Force

    $compatPass = Convert-HexToSignedInt 'C1900210'
    if ($result.ExitCode -in @(0, $compatPass)) {
        Write-Ok ("Compatibility scan passed ({0})." -f (Get-SetupExitCodeMeaning -ExitCode $result.ExitCode))
        return $result
    }

    switch ($result.ExitCode) {
        (Convert-HexToSignedInt 'C1900208') { Write-Fail 'Compatibility scan found a blocking application or driver (0xC1900208).' }
        (Convert-HexToSignedInt 'C1900204') { Write-Fail 'Compatibility scan hit a migration-choice block (0xC1900204).' }
        (Convert-HexToSignedInt 'C1900200') { Write-Fail 'Compatibility scan hit a system requirement block (0xC1900200).' }
        (Convert-HexToSignedInt 'C190020E') { Write-Fail 'Compatibility scan hit an insufficient disk space block (0xC190020E).' }
        (Convert-HexToSignedInt 'C190010E') { Write-Fail 'Compatibility scan requires /EULA accept in quiet mode (0xC190010E).' }
        (Convert-HexToSignedInt 'C1900215') { Write-Fail 'Compatibility scan could not resolve a matching install image for quiet mode (0xC1900215).' }
        default { Write-Fail ("Compatibility scan failed with exit code {0} ({1})." -f $result.ExitCode, (Get-SetupExitCodeMeaning -ExitCode $result.ExitCode)) }
    }
}

function Invoke-SetupUpgrade {
    param(
        [Parameter(Mandatory = $true)][string]$SetupPath,
        [Parameter(Mandatory = $true)][string[]]$SetupArguments
    )

    $result = Invoke-ExternalProcess -FilePath $SetupPath -Arguments $SetupArguments -Description 'Windows Setup repair upgrade' -TimeoutSeconds 28800
    $result | Add-Member -NotePropertyName ArgumentList -NotePropertyValue @($SetupArguments) -Force
    return $result
}

function Get-PantherTail {
    $paths = @(
        'C:\$WINDOWS.~BT\Sources\Panther\setuperr.log',
        'C:\$WINDOWS.~BT\Sources\Panther\setupact.log'
    )

    $output = @()
    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path) {
            $output += "== $path =="
            $output += @(Get-Content -LiteralPath $path -Tail 40 -ErrorAction SilentlyContinue)
        }
    }

    return @($output)
}

function Invoke-SetupDiagAnalysis {
    param(
        [Parameter(Mandatory = $true)][string]$ExtractDir,
        [Parameter(Mandatory = $true)][string]$RunDirectory
    )

    $candidates = @(
        (Join-Path $ExtractDir 'sources\SetupDiag.exe'),
        'C:\$WINDOWS.~BT\Sources\SetupDiag.exe'
    )

    $setupDiagExe = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $setupDiagExe) {
        return $null
    }

    $outputPath = Join-Path $RunDirectory 'SetupDiagResults.log'
    Invoke-ExternalProcess -FilePath $setupDiagExe -Arguments @("/Output:$outputPath", '/NoTel') -Description 'SetupDiag analysis' -TimeoutSeconds 1800 -AllowedExitCodes @(0, 1) | Out-Null
    return $outputPath
}

function Write-RunSummary {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Summary,
        [Parameter(Mandatory = $true)][string]$RunDirectory
    )

    $jsonPath = Join-Path $RunDirectory 'final_summary.json'
    $reportPath = Join-Path $RunDirectory 'final_report.md'

    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $reasons = @()
    if ($Summary.ExecutionPlan -and $Summary.ExecutionPlan.EscalationReasons) {
        $reasons = @($Summary.ExecutionPlan.EscalationReasons)
    }

    $pantherTail = @()
    if ($Summary.Diagnostics -and $Summary.Diagnostics.PantherTail) {
        $pantherTail = @($Summary.Diagnostics.PantherTail)
    }

    $lines = @(
        '# Repair Upgrade Closeout',
        '',
        ('- Status: {0}' -f $Summary.Status),
        ('- Mode: {0}' -f $Summary.Mode),
        ('- PreflightOnly: {0}' -f [bool]$Summary.PreflightOnly),
        ('- SourcePreference: {0}' -f $Summary.SourcePreference),
        ('- StartedAt: {0}' -f $Summary.StartedAt),
        ('- FinishedAt: {0}' -f $Summary.FinishedAt),
        ('- SelectedSource: {0}' -f $Summary.SelectedSourcePath),
        ('- SelectedImageIndex: {0}' -f $Summary.SelectedImageIndex),
        ('- SetupExitCode: {0}' -f $Summary.SetupExitCode),
        ('- SetupExitMeaning: {0}' -f $Summary.SetupExitMeaning),
        ('- RebootPendingFinal: {0}' -f [bool]$Summary.RebootPendingFinal.IsPending),
        ''
    )

    if ($reasons.Count -gt 0) {
        $lines += '## Escalation Reasons'
        $lines += ''
        foreach ($reason in $reasons) {
            $lines += ('- {0}' -f $reason)
        }
        $lines += ''
    }

    if ($pantherTail.Count -gt 0) {
        $lines += '## Panther Tail'
        $lines += ''
        $lines += '```text'
        $lines += $pantherTail
        $lines += '```'
        $lines += ''
    }

    $lines | Set-Content -LiteralPath $reportPath -Encoding UTF8
    return [pscustomobject]@{
        SummaryJson = $jsonPath
        ReportPath  = $reportPath
    }
}

function Start-RepairUpgradeWorkflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$IsoSource,
        [Parameter(Mandatory = $true)][string]$ExtractDir,
        [Parameter(Mandatory = $true)][string]$LocalIso,
        [ValidateSet('Fast', 'Deep')]
        [string]$Mode = 'Fast',
        [switch]$PreflightOnly,
        [ValidateSet('Auto', 'LocalFirst', 'OnlineFirst')]
        [string]$SourcePreference = 'Auto'
    )

    $startedAt = Get-Date
    $artifactPaths = New-RunArtifactPaths -StartedAt $startedAt -ExtractDir $ExtractDir
    $runId = $artifactPaths.RunId
    $runDirectory = $artifactPaths.RunDirectory
    New-Item -ItemType Directory -Path $runDirectory -Force -ErrorAction SilentlyContinue | Out-Null
    $transcriptPath = $artifactPaths.TranscriptPath
    $copyLogsPath = $artifactPaths.CopyLogsPath
    $summary = [ordered]@{
        RunId              = $runId
        StartedAt          = $startedAt.ToString('o')
        FinishedAt         = $null
        Status             = 'Running'
        Mode               = $Mode
        PreflightOnly      = [bool]$PreflightOnly
        SourcePreference   = $SourcePreference
        RunDirectory       = $runDirectory
        SelectedSourcePath = $null
        SelectedImageIndex = $null
        SetupExitCode      = $null
        SetupExitMeaning   = $null
        ExecutionPlan      = $null
        RebootPendingFinal = $null
        Diagnostics        = $null
    }

    $transcriptStarted = $false
    $caughtError = $null

    try {
        Start-Transcript -Path $transcriptPath -Force | Out-Null
        $transcriptStarted = $true
    } catch {
        Write-Warn ("Transcript could not be started: {0}" -f $_.Exception.Message)
    }

    try {
        try {
            $host.UI.RawUI.WindowTitle = 'Repair Upgrade - Hardened'
        } catch {
        }

        Write-Step 0 'Collect system profile and previous setup signals'
        $systemProfile = Get-SystemProfile
        $previousSignals = Get-PreviousSetupSignals
        $summary.SystemProfile = $systemProfile
        $summary.PreviousSignals = $previousSignals
        Write-Ok ("System build {0}, edition {1}, arch {2}, primary language {3}" -f $systemProfile.Build, $systemProfile.EditionId, $systemProfile.Architecture, $systemProfile.PrimaryLanguage)

        Write-Step 1 'Discover compatible Windows 11 installation media'
        $localCandidates = Get-LocalSourceCandidates -IsoSource $IsoSource -LocalIso $LocalIso
        $localEvaluations = Get-SourceEvaluations -Candidates $localCandidates -SystemProfile $systemProfile
        $summary.LocalEvaluations = $localEvaluations

        $selectedEvaluation = $null
        switch ($SourcePreference) {
            'LocalFirst' {
                $selectedEvaluation = Select-BestEvaluation -Evaluations $localEvaluations -RequireCompatible
            }
            'OnlineFirst' {
                $downloaded = Try-DownloadCloudIso -CandidateUrls (Get-CloudIsoCandidates) -DestinationPath $LocalIso
                if ($downloaded) {
                    $selectedEvaluation = Select-BestEvaluation -Evaluations (Get-SourceEvaluations -Candidates @([pscustomobject]@{ Path = $downloaded.Path; Reason = $downloaded.Reason; Priority = $downloaded.Priority }) -SystemProfile $systemProfile) -RequireCompatible
                }
                if (-not $selectedEvaluation) {
                    $selectedEvaluation = Select-BestEvaluation -Evaluations $localEvaluations -RequireCompatible
                }
            }
            default {
                $selectedEvaluation = Select-BestEvaluation -Evaluations $localEvaluations -RequireCompatible
                if (-not $selectedEvaluation) {
                    $downloaded = Try-DownloadCloudIso -CandidateUrls (Get-CloudIsoCandidates) -DestinationPath $LocalIso
                    if ($downloaded) {
                        $selectedEvaluation = Select-BestEvaluation -Evaluations (Get-SourceEvaluations -Candidates @([pscustomobject]@{ Path = $downloaded.Path; Reason = $downloaded.Reason; Priority = $downloaded.Priority }) -SystemProfile $systemProfile) -RequireCompatible
                    }
                }
            }
        }

        if (-not $selectedEvaluation) {
            Write-Fail ("No compatible install media passed selection.`n{0}" -f (Format-EvaluationSummary -Evaluations $localEvaluations))
        }

        if (-not $selectedEvaluation.ImageSelection.Resolved) {
            Write-Fail ("Selected media cannot be used in quiet mode because image resolution failed: {0}" -f $selectedEvaluation.ImageSelection.Reason)
        }

        $summary.SelectedSourcePath = $selectedEvaluation.Source.Path
        $summary.SelectedImageIndex = $selectedEvaluation.ImageSelection.SelectedImageIndex
        $summary.SelectedSource = $selectedEvaluation
        Write-Ok ("Selected media: {0} via {1}" -f $selectedEvaluation.Source.Path, $selectedEvaluation.Source.Reason)
        Write-Ok ("Resolved image index {0}: {1}" -f $selectedEvaluation.ImageSelection.SelectedImageIndex, $selectedEvaluation.ImageSelection.SelectedImageName)

        Write-Step 2 'Stage and extract installation media'
        $activeIsoPath = $null
        $mediaRoot = $null
        $mountInfo = $null
        $useSevenZipIsoExtraction = $false
        if ($selectedEvaluation.Source.Kind -eq 'IsoFile') {
            $activeIsoPath = (Get-Item -LiteralPath $selectedEvaluation.Source.Path -Force -ErrorAction Stop).FullName
            Write-Ok "Using ISO file directly at $activeIsoPath"
            try {
                $mountInfo = Mount-IsoAndGetMediaRoot -IsoPath $activeIsoPath
                $mediaRoot = $mountInfo.MediaRoot
            } catch {
                Write-Warn ("ISO mount failed for {0}. Falling back to 7-Zip extraction. {1}" -f $activeIsoPath, $_.Exception.Message)
                $useSevenZipIsoExtraction = $true
            }
        } else {
            $mediaRoot = $selectedEvaluation.Source.Path
            Write-Ok "Using media folder directly at $mediaRoot"
        }

        try {
            if ($useSevenZipIsoExtraction) {
                Expand-IsoToExtractDir -IsoPath $activeIsoPath -DestinationPath $ExtractDir
            } else {
                Copy-MediaToExtractDir -MediaRoot $mediaRoot -DestinationPath $ExtractDir
            }
            Test-ExtractedMedia -ExtractDir $ExtractDir
        } finally {
            if ($mountInfo -and $activeIsoPath) {
                try {
                    Dismount-DiskImage -ImagePath $activeIsoPath -ErrorAction SilentlyContinue | Out-Null
                } catch {
                }
            }
        }

        Write-Step 3 'Clean stale setup state and unblock services'
        foreach ($path in @('C:\$WINDOWS.~BT', 'C:\$Windows.~WS')) {
            Write-Info "Inspecting stale setup directory $path"
            if (Test-Path -LiteralPath $path) {
                Remove-DirectoryHard -Path $path
                Write-Ok "Removed stale setup directory $path"
            } else {
                Write-Ok "$path was already clear."
            }
        }

        Write-Info 'Clearing PendingFileRenameOperations if present.'
        $summary.PendingFileRenameCountBefore = Clear-PendingFileRenameOperations
        Write-Info 'Checking reboot-pending state before cleanup.'
        $summary.RebootPendingBeforeCleanup = Get-RebootPendingStatus
        Write-Info 'Clearing reboot-pending flags.'
        Clear-RebootPendingFlags
        Write-Info 'Stopping IIS-related services that can block setup.'
        Stop-IISServices
        Write-Info 'Ensuring Windows Update and installer services are running.'
        Ensure-RequiredServices
        Write-Info 'Re-checking reboot-pending state after cleanup.'
        $rebootPendingAfterCleanup = Get-RebootPendingStatus
        $summary.RebootPendingAfterCleanup = $rebootPendingAfterCleanup

        Write-Step 4 'Decide fast vs deep execution path'
        $executionPlan = Get-ExecutionPlan `
            -RequestedMode $Mode `
            -PreflightOnly:$PreflightOnly `
            -HasPriorPantherLogs:$previousSignals.HasPantherLogs `
            -HasCompatLogs:$previousSignals.HasCompatLogs `
            -PreviousSetupExitCode $previousSignals.PreviousSetupExitCode `
            -RebootPendingAfterCleanup:$rebootPendingAfterCleanup.IsPending `
            -MediaMatchingAmbiguous:$selectedEvaluation.ImageSelection.Ambiguous

        $summary.ExecutionPlan = $executionPlan
        if ($executionPlan.EscalationReasons.Count -gt 0) {
            Write-Warn ("Deep path selected because: {0}" -f ($executionPlan.EscalationReasons -join '; '))
        } else {
            Write-Ok 'Fast path selected.'
        }

        if (-not $executionPlan.CanLaunchUpgrade) {
            Write-Fail 'Setup launch cannot continue because the selected media still has ambiguous image matching.'
        }

        Write-Step 5 'Run preflight checks'
        $freeGb = [math]::Round((Get-PSDrive -Name C).Free / 1GB, 1)
        $preflightChecks = @(
            [pscustomobject]@{ Name = 'setup.exe exists'; Passed = (Test-Path -LiteralPath (Join-Path $ExtractDir 'setup.exe')) },
            [pscustomobject]@{ Name = 'migcore.dll present'; Passed = (Test-Path -LiteralPath (Join-Path $ExtractDir 'sources\migcore.dll')) },
            [pscustomobject]@{ Name = 'install image present'; Passed = ((Test-Path -LiteralPath (Join-Path $ExtractDir 'sources\install.wim')) -or (Test-Path -LiteralPath (Join-Path $ExtractDir 'sources\install.esd'))) },
            [pscustomobject]@{ Name = 'Selected image index resolved'; Passed = ($selectedEvaluation.ImageSelection.SelectedImageIndex -gt 0) },
            [pscustomobject]@{ Name = 'No stale BT folder'; Passed = (-not (Test-Path -LiteralPath 'C:\$WINDOWS.~BT')) },
            [pscustomobject]@{ Name = 'wuauserv running'; Passed = ((Get-Service -Name wuauserv -ErrorAction SilentlyContinue).Status -eq 'Running') },
            [pscustomobject]@{ Name = 'TrustedInstaller running'; Passed = ((Get-Service -Name TrustedInstaller -ErrorAction SilentlyContinue).Status -eq 'Running') },
            [pscustomobject]@{ Name = 'Disk space >= 20 GB'; Passed = ($freeGb -ge 20) }
        )

        $summary.PreflightChecks = $preflightChecks
        foreach ($check in $preflightChecks) {
            if ($check.Passed) {
                Write-Ok $check.Name
            } else {
                Write-Fail ("Preflight check failed: {0}" -f $check.Name)
            }
        }

        if ($executionPlan.RunCompatScan) {
            Write-Step 6 'Run compatibility scan'
            $summary.CompatScan = Invoke-SetupCompatibilityScan `
                -SetupPath (Join-Path $ExtractDir 'setup.exe') `
                -ImageIndex $selectedEvaluation.ImageSelection.SelectedImageIndex `
                -CopyLogsPath $copyLogsPath `
                -BitLockerAlwaysSuspend:$systemProfile.BitLockerActive
        } else {
            Write-Ok 'Compatibility scan skipped on fast path.'
        }

        if ($executionPlan.RunDeepServicing) {
            Write-Step 7 'Run deep servicing and Windows Update component repair'
            Invoke-DeepServicing
            $summary.DeepServicing = 'Performed'
        } else {
            $summary.DeepServicing = 'Skipped'
            Write-Ok 'Deep servicing skipped on fast path.'
        }

        if ($PreflightOnly) {
            $summary.Status = 'PreflightComplete'
            $summary.SetupExitCode = 0
            $summary.SetupExitMeaning = 'Preflight completed without launching setup.exe'
            Write-Ok 'Preflight-only run completed. Full upgrade launch was skipped by request.'
            return [pscustomobject]$summary
        }

        Write-Step 8 'Launch Windows Setup repair upgrade'
        $dynamicUpdateMode = if ($executionPlan.UseDeepPath) { 'NoDrivers' } else { 'Disable' }
        $setupArguments = New-SetupArgumentList `
            -Mode $Mode `
            -ImageIndex $selectedEvaluation.ImageSelection.SelectedImageIndex `
            -CopyLogsPath $copyLogsPath `
            -BitLockerAlwaysSuspend:$systemProfile.BitLockerActive `
            -DynamicUpdate $dynamicUpdateMode
        $summary.SetupArguments = @($setupArguments)
        Write-Info ("Setup arguments: {0}" -f (Join-ArgumentString $setupArguments))

        $upgradeResult = Invoke-SetupUpgrade -SetupPath (Join-Path $ExtractDir 'setup.exe') -SetupArguments $setupArguments
        $summary.SetupExitCode = $upgradeResult.ExitCode
        $summary.SetupExitMeaning = Get-SetupExitCodeMeaning -ExitCode $upgradeResult.ExitCode

        if ($upgradeResult.ExitCode -ne 0) {
            $diagnostics = [ordered]@{
                PantherTail       = Get-PantherTail
                SetupDiagOutput   = Invoke-SetupDiagAnalysis -ExtractDir $ExtractDir -RunDirectory $runDirectory
                ExitCodeMeaning   = Get-SetupExitCodeMeaning -ExitCode $upgradeResult.ExitCode
            }
            $summary.Diagnostics = $diagnostics
            Write-Fail ("Repair upgrade failed with exit code {0} ({1})." -f $upgradeResult.ExitCode, $diagnostics.ExitCodeMeaning)
        }

        $summary.Status = 'Success'
        Write-Ok 'Repair upgrade completed successfully.'
        return [pscustomobject]$summary
    } catch {
        $caughtError = $_
        $summary.Status = 'Failed'
        $summary.Error = $_.Exception.Message
        if (-not $summary.SetupExitMeaning -and $summary.SetupExitCode -ne $null) {
            $summary.SetupExitMeaning = Get-SetupExitCodeMeaning -ExitCode ([int]$summary.SetupExitCode)
        }

        if (-not $summary.Diagnostics) {
            $summary.Diagnostics = [ordered]@{
                PantherTail     = Get-PantherTail
                SetupDiagOutput = Invoke-SetupDiagAnalysis -ExtractDir $ExtractDir -RunDirectory $runDirectory
            }
        }
    } finally {
        $summary.FinishedAt = (Get-Date).ToString('o')
        $summary.RebootPendingFinal = Get-RebootPendingStatus
        try {
            $summaryArtifacts = Write-RunSummary -Summary $summary -RunDirectory $runDirectory
            $summary.SummaryJson = $summaryArtifacts.SummaryJson
            $summary.ReportPath = $summaryArtifacts.ReportPath
            Write-Ok ("Summary written to {0}" -f $summaryArtifacts.SummaryJson)
            Write-Ok ("Closeout report written to {0}" -f $summaryArtifacts.ReportPath)
        } catch {
            Write-Warn ("Failed to write summary artifacts: {0}" -f $_.Exception.Message)
        }

        if ($transcriptStarted) {
            try {
                Stop-Transcript | Out-Null
            } catch {
            }
        }
    }

    if ($caughtError) {
        throw $caughtError
    }

    return [pscustomobject]$summary
}

if (-not $script:IsDotSourced) {
    Start-RepairUpgradeWorkflow `
        -IsoSource $IsoSource `
        -ExtractDir $ExtractDir `
        -LocalIso $LocalIso `
        -Mode $Mode `
        -PreflightOnly:$PreflightOnly `
        -SourcePreference $SourcePreference | Out-Null
}
