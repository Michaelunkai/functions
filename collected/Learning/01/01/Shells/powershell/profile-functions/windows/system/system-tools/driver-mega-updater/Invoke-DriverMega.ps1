[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply')]
    [string]$Mode = 'Audit',
    [switch]$IncludeFirmware,
    [switch]$IncludePeripheralVendors,
    [switch]$AutoInstallVendorDrivers,
    [switch]$AutoReboot,
    [string]$ReportPath,
    [switch]$Resume
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:DriverMegaIsDotSourced = $MyInvocation.InvocationName -eq '.'

function Test-DriverMegaAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-DriverMegaDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    return $Path
}

function Get-DriverMegaRoot {
    return Split-Path -Parent $PSCommandPath
}

function Get-DriverMegaTimestamp {
    return (Get-Date).ToString('yyyyMMdd-HHmmss')
}

function Get-DriverMegaReportPaths {
    param(
        [string]$RequestedReportPath,
        [switch]$ResumeRequested
    )

    $root = Get-DriverMegaRoot
    $reportRoot = New-DriverMegaDirectory -Path (Join-Path $root 'reports')
    $stateRoot = New-DriverMegaDirectory -Path (Join-Path $root 'state')

    if ($RequestedReportPath) {
        $resolvedReportPath = [System.IO.Path]::GetFullPath($RequestedReportPath)
        $reportDirectory = Split-Path -Parent $resolvedReportPath
        if ($reportDirectory) {
            New-DriverMegaDirectory -Path $reportDirectory | Out-Null
        }
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedReportPath)
    }
    elseif ($ResumeRequested) {
        $latestState = Get-ChildItem -LiteralPath $stateRoot -Filter '*.state.json' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if (-not $latestState) {
            throw 'Resume was requested, but no saved DriverMega state file was found.'
        }

        $savedState = $null
        try {
            $savedState = Get-Content -LiteralPath $latestState.FullName -Raw | ConvertFrom-Json
        }
        catch {
        }

        if ($savedState -and $savedState.ReportPath) {
            $resolvedReportPath = [System.IO.Path]::GetFullPath([string]$savedState.ReportPath)
            $resolvedReportPath = $resolvedReportPath -replace '\.report\.report\.json$', '.report.json'
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedReportPath)
        }
        else {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileNameWithoutExtension($latestState.Name))
            $resolvedReportPath = Join-Path $reportRoot ($baseName + '.report.json')
        }
    }
    else {
        $baseName = 'DriverMega-' + (Get-DriverMegaTimestamp)
        $resolvedReportPath = Join-Path $reportRoot ($baseName + '.report.json')
    }

    return [ordered]@{
        BaseName = $baseName
        ReportPath = $resolvedReportPath
        StatePath = Join-Path $stateRoot ($baseName + '.state.json')
        LogPath = Join-Path $reportRoot ($baseName + '.log.txt')
        DownloadRoot = New-DriverMegaDirectory -Path (Join-Path $root 'downloads')
        ScratchRoot = New-DriverMegaDirectory -Path (Join-Path $root 'scratch')
    }
}

function Write-DriverMegaConsoleSection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    Write-Host ''
    Write-Host ('=== ' + $Title + ' ===') -ForegroundColor Cyan
}

function Add-DriverMegaNote {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $Report.Notes.Add($Message) | Out-Null
}

function Add-DriverMegaWarning {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $Report.Warnings.Add($Message) | Out-Null
}

function Add-DriverMegaError {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $Report.Errors.Add($Message) | Out-Null
}

function Save-DriverMegaJson {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $json = $Object | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Get-DriverMegaJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw ('JSON file not found: ' + $Path)
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function ConvertTo-DriverMegaVersionArray {
    param(
        [AllowNull()]
        [string]$Version
    )

    if ([string]::IsNullOrWhiteSpace($Version)) {
        return @()
    }

    $clean = $Version.Trim()
    $matches = [regex]::Matches($clean, '\d+')
    if ($matches.Count -eq 0) {
        return @()
    }

    $parts = New-Object System.Collections.Generic.List[int]
    foreach ($match in $matches) {
        $parts.Add([int]$match.Value)
    }

    return $parts.ToArray()
}

function Compare-DriverMegaVersion {
    param(
        [AllowNull()]
        [string]$Left,
        [AllowNull()]
        [string]$Right
    )

    $leftParts = ConvertTo-DriverMegaVersionArray -Version $Left
    $rightParts = ConvertTo-DriverMegaVersionArray -Version $Right
    $length = [Math]::Max($leftParts.Count, $rightParts.Count)

    for ($index = 0; $index -lt $length; $index++) {
        $leftValue = if ($index -lt $leftParts.Count) { $leftParts[$index] } else { 0 }
        $rightValue = if ($index -lt $rightParts.Count) { $rightParts[$index] } else { 0 }

        if ($leftValue -gt $rightValue) {
            return 1
        }

        if ($leftValue -lt $rightValue) {
            return -1
        }
    }

    return 0
}

function ConvertTo-DriverMegaBiosComparable {
    param(
        [AllowNull()]
        [string]$Version
    )

    if ([string]::IsNullOrWhiteSpace($Version)) {
        return [ordered]@{
            Prefix = ''
            Numeric = 0
            Suffix = @()
        }
    }

    $clean = $Version.Trim().ToUpperInvariant()
    if ($clean -match '^([A-Z]+)(\d+)([A-Z]*)$') {
        $prefix = $Matches[1]
        $numeric = [int]$Matches[2]
        $suffixChars = New-Object System.Collections.Generic.List[int]
        foreach ($char in $Matches[3].ToCharArray()) {
            $suffixChars.Add(([int][char]$char) - ([int][char]'A') + 1)
        }

        return [ordered]@{
            Prefix = $prefix
            Numeric = $numeric
            Suffix = $suffixChars.ToArray()
        }
    }

    return [ordered]@{
        Prefix = $clean
        Numeric = 0
        Suffix = @()
    }
}

function Compare-DriverMegaBiosVersion {
    param(
        [AllowNull()]
        [string]$Left,
        [AllowNull()]
        [string]$Right
    )

    $leftComparable = ConvertTo-DriverMegaBiosComparable -Version $Left
    $rightComparable = ConvertTo-DriverMegaBiosComparable -Version $Right

    $prefixResult = [string]::CompareOrdinal($leftComparable.Prefix, $rightComparable.Prefix)
    if ($prefixResult -gt 0) {
        return 1
    }
    if ($prefixResult -lt 0) {
        return -1
    }

    if ($leftComparable.Numeric -gt $rightComparable.Numeric) {
        return 1
    }
    if ($leftComparable.Numeric -lt $rightComparable.Numeric) {
        return -1
    }

    $suffixLength = [Math]::Max($leftComparable.Suffix.Count, $rightComparable.Suffix.Count)
    for ($index = 0; $index -lt $suffixLength; $index++) {
        $leftValue = if ($index -lt $leftComparable.Suffix.Count) { $leftComparable.Suffix[$index] } else { 0 }
        $rightValue = if ($index -lt $rightComparable.Suffix.Count) { $rightComparable.Suffix[$index] } else { 0 }

        if ($leftValue -gt $rightValue) {
            return 1
        }
        if ($leftValue -lt $rightValue) {
            return -1
        }
    }

    return 0
}

function New-DriverMegaCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [string]$Provider,
        [Parameter(Mandatory = $true)]
        [string]$Category,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [AllowNull()]
        [string]$InstalledVersion,
        [AllowNull()]
        [string]$CandidateVersion,
        [Parameter(Mandatory = $true)]
        [string]$Channel,
        [AllowNull()]
        [string]$SourceUrl,
        [AllowNull()]
        [string]$PackagePath,
        [AllowNull()]
        [string]$PackageUrl,
        [AllowNull()]
        [string]$DriverIdentity,
        [AllowNull()]
        [string]$Classification,
        [AllowNull()]
        [string]$InstallMode,
        [AllowNull()]
        [string]$Revision
    )

    $candidate = [ordered]@{
        Id = $Id
        Provider = $Provider
        Category = $Category
        Title = $Title
        InstalledVersion = $InstalledVersion
        CandidateVersion = $CandidateVersion
        Channel = $Channel
        SourceUrl = $SourceUrl
        PackagePath = $PackagePath
        PackageUrl = $PackageUrl
        DriverIdentity = $DriverIdentity
        Classification = $Classification
        InstallMode = $InstallMode
        Revision = $Revision
        State = 'unknown'
        Reason = $null
        Action = 'none'
        RequiresReboot = $false
        Result = $null
    }

    return $candidate
}

function Set-DriverMegaCandidateState {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Candidate,
        [Parameter(Mandatory = $true)]
        [string]$State,
        [string]$Reason,
        [string]$Action = 'none'
    )

    $Candidate.State = $State
    $Candidate.Reason = $Reason
    $Candidate.Action = $Action
    return $Candidate
}

function Resolve-DriverMegaVersionState {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Candidate,
        [switch]$UseBiosComparison
    )

    if ([string]::IsNullOrWhiteSpace($Candidate.CandidateVersion)) {
        return Set-DriverMegaCandidateState -Candidate $Candidate -State 'manual_review' -Reason 'No candidate version was available from the selected source.' -Action 'defer'
    }

    if ([string]::IsNullOrWhiteSpace($Candidate.InstalledVersion)) {
        return Set-DriverMegaCandidateState -Candidate $Candidate -State 'update_available' -Reason 'No installed version was found, so the package is staged as a candidate update.' -Action 'apply'
    }

    $comparison = if ($UseBiosComparison) {
        Compare-DriverMegaBiosVersion -Left $Candidate.CandidateVersion -Right $Candidate.InstalledVersion
    }
    else {
        Compare-DriverMegaVersion -Left $Candidate.CandidateVersion -Right $Candidate.InstalledVersion
    }

    if ($comparison -gt 0) {
        return Set-DriverMegaCandidateState -Candidate $Candidate -State 'update_available' -Reason 'Candidate version is newer than the installed version.' -Action 'apply'
    }

    if ($comparison -lt 0) {
        return Set-DriverMegaCandidateState -Candidate $Candidate -State 'blocked_downgrade' -Reason 'Candidate version is older than the installed version. Downgrade was refused.' -Action 'defer'
    }

    return Set-DriverMegaCandidateState -Candidate $Candidate -State 'up_to_date' -Reason 'Installed version already matches the candidate version.' -Action 'none'
}

function Get-DriverMegaRegistryPackages {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $packages = @()
    foreach ($path in $paths) {
        $packages += Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object { $_.PSObject.Properties.Match('DisplayName').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($_.DisplayName) } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
    }

    return @($packages | Sort-Object DisplayName -Unique)
}

function Find-DriverMegaPackageVersion {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Packages,
        [Parameter(Mandatory = $true)]
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        $match = $Packages | Where-Object { $_.DisplayName -match $pattern } | Select-Object -First 1
        if ($match) {
            return $match.DisplayVersion
        }
    }

    return $null
}

function Get-DriverMegaPnPDrivers {
    return @(Get-CimInstance Win32_PnPSignedDriver |
        Select-Object DeviceName, DriverProviderName, DriverVersion, DriverDate, InfName, Manufacturer, DeviceID)
}

function Get-DriverMegaPresentDevices {
    return @(Get-PnpDevice -PresentOnly |
        Select-Object Class, FriendlyName, Manufacturer, InstanceId, Status, Problem)
}

function Get-DriverMegaProblemDevices {
    return @(Get-CimInstance Win32_PnPEntity |
        Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
        Select-Object Name, Manufacturer, PNPClass, PNPDeviceID, ConfigManagerErrorCode)
}

function Get-DriverMegaDisplayInventory {
    return @(Get-CimInstance Win32_VideoController |
        Select-Object Name, DriverVersion, DriverDate, PNPDeviceID)
}

function Get-DriverMegaCpuInventory {
    return @(Get-CimInstance Win32_Processor |
        Select-Object Name, Manufacturer, NumberOfCores, NumberOfLogicalProcessors)
}

function Get-DriverMegaComputerInventory {
    $computerSystem = Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model
    $bios = Get-CimInstance Win32_BIOS | Select-Object Manufacturer, SMBIOSBIOSVersion, ReleaseDate
    $baseBoard = Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer, Product, SerialNumber

    return [ordered]@{
        Manufacturer = $computerSystem.Manufacturer
        Model = $computerSystem.Model
        BiosManufacturer = $bios.Manufacturer
        BiosVersion = $bios.SMBIOSBIOSVersion
        BiosReleaseDate = $bios.ReleaseDate
        BaseBoardManufacturer = $baseBoard.Manufacturer
        BaseBoardProduct = $baseBoard.Product
        BaseBoardSerial = $baseBoard.SerialNumber
    }
}

function Get-DriverMegaHardwareInventory {
    $packages = Get-DriverMegaRegistryPackages
    $pnpDrivers = Get-DriverMegaPnPDrivers
    $presentDevices = Get-DriverMegaPresentDevices
    $problemDevices = Get-DriverMegaProblemDevices
    $displays = Get-DriverMegaDisplayInventory
    $cpu = Get-DriverMegaCpuInventory
    $computer = Get-DriverMegaComputerInventory

    return [ordered]@{
        Computer = $computer
        Cpu = $cpu
        Displays = $displays
        Packages = $packages
        PnPDrivers = $pnpDrivers
        PresentDevices = $presentDevices
        ProblemDevices = $problemDevices
    }
}

function Get-DriverMegaSupportText {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Response
    )

    if ($Response.ParsedHtml -and $Response.ParsedHtml.body) {
        try {
            $bodyText = $Response.ParsedHtml.body.outerText
            if (-not [string]::IsNullOrWhiteSpace($bodyText)) {
                return $bodyText
            }
        }
        catch {
        }
    }

    $content = $Response.Content
    $content = $content -replace '<script[^>]*?>.*?</script>', ' '
    $content = $content -replace '<style[^>]*?>.*?</style>', ' '
    $content = $content -replace '<[^>]+>', ' '
    $content = $content -replace '&nbsp;', ' '
    $content = $content -replace '\s+', ' '
    return $content
}

function Get-DriverMegaRegexMatchValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    $match = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    return $null
}

function Get-DriverMegaGigabyteLocalContext {
    $downloadRoot = 'C:\Program Files\GIGABYTE\Control Center\Lib\Download'
    $biosIniPath = Join-Path $downloadRoot 'BIOS.ini'
    $localFiles = if (Test-Path -LiteralPath $downloadRoot) {
        @(Get-ChildItem -LiteralPath $downloadRoot -File -ErrorAction SilentlyContinue)
    }
    else {
        @()
    }

    return [ordered]@{
        DownloadRoot = $downloadRoot
        BiosIniPath = $biosIniPath
        Files = $localFiles
    }
}

function Get-DriverMegaGigabyteRevision {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BoardProduct,
        [Parameter(Mandatory = $true)]
        [hashtable]$LocalContext
    )

    $normalizedBoard = ($BoardProduct -replace '\s+', '-').ToLowerInvariant()
    $biosZip = $LocalContext.Files | Where-Object { $_.Name.ToLowerInvariant() -like ('*' + $normalizedBoard + '*') -and $_.Extension -eq '.zip' } | Select-Object -First 1
    if ($biosZip -and $biosZip.Name -match '_([0-9a-z]{7,8})_') {
        $boardCode = $Matches[1].ToUpperInvariant()
        if ((Test-Path -LiteralPath $LocalContext.BiosIniPath)) {
            $biosText = Get-Content -LiteralPath $LocalContext.BiosIniPath -Raw
            if ($biosText -match ('\[' + [regex]::Escape($boardCode) + '\]\s+NAME=.*\(rev\.([0-9\.x]+)\)')) {
                return $Matches[1]
            }
        }
    }

    return $null
}

function Find-DriverMegaLocalPackage {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$LocalContext,
        [Parameter(Mandatory = $true)]
        [string[]]$Keywords,
        [string]$Version
    )

    $candidates = $LocalContext.Files
    foreach ($keyword in $Keywords) {
        $candidates = $candidates | Where-Object { $_.Name -match $keyword }
    }

    if ($Version) {
        $escapedVersion = [regex]::Escape($Version)
        $versionMatch = $candidates | Where-Object { $_.Name -match $escapedVersion } | Select-Object -First 1
        if ($versionMatch) {
            return $versionMatch.FullName
        }
    }

    $fallback = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($fallback) {
        return $fallback.FullName
    }

    return $null
}

function Get-DriverMegaGigabyteLocalCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Inventory,
        [Parameter(Mandatory = $true)]
        [hashtable]$LocalContext,
        [string]$Revision
    )

    $packages = $Inventory.Packages
    $candidates = New-Object System.Collections.Generic.List[hashtable]

    $apuPackage = $LocalContext.Files | Where-Object { $_.Name -match 'ASETUP\.EXE$' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($apuPackage -and $apuPackage.Name -match '_([0-9\.]+)_ASETUP\.EXE$') {
        $installedVersion = Find-DriverMegaPackageVersion -Packages $packages -Patterns @('AMD Software$', 'AMD Radeon Software')
        $candidate = New-DriverMegaCandidate -Id 'gigabyte-local-amd-apu' -Provider 'Gigabyte' -Category 'Driver' -Title 'AMD APU Driver (local GCC cache)' `
            -InstalledVersion $installedVersion -CandidateVersion $Matches[1] -Channel 'Gigabyte local cache' -SourceUrl $null -PackagePath $apuPackage.FullName -PackageUrl $null `
            -DriverIdentity 'AMD Radeon(TM) Graphics' -Classification 'Display' -InstallMode 'installer-extract-pnputil' -Revision $Revision
        $candidates.Add((Resolve-DriverMegaVersionState -Candidate $candidate))
    }

    $chipsetPackage = $LocalContext.Files | Where-Object { $_.Name -match 'CSETUP\.EXE$' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($chipsetPackage -and $chipsetPackage.Name -match '_([0-9\.]+)_CSETUP\.EXE$') {
        $installedVersion = Find-DriverMegaPackageVersion -Packages $packages -Patterns @('AMD Chipset Software')
        $candidate = New-DriverMegaCandidate -Id 'gigabyte-local-amd-chipset' -Provider 'Gigabyte' -Category 'Driver' -Title 'AMD Chipset Driver (local GCC cache)' `
            -InstalledVersion $installedVersion -CandidateVersion $Matches[1] -Channel 'Gigabyte local cache' -SourceUrl $null -PackagePath $chipsetPackage.FullName -PackageUrl $null `
            -DriverIdentity 'AMD SMBUS' -Classification 'System' -InstallMode 'amd-install-manager' -Revision $Revision
        $candidates.Add((Resolve-DriverMegaVersionState -Candidate $candidate))
    }

    $gccPackage = $LocalContext.Files | Where-Object { $_.Name -match '^GIGABYTE Control Center_([0-9\.]+)\.exe$' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($gccPackage -and $gccPackage.Name -match '^GIGABYTE Control Center_([0-9\.]+)\.exe$') {
        $installedVersion = Find-DriverMegaPackageVersion -Packages $packages -Patterns @('GIGABYTE Control Center')
        $candidate = New-DriverMegaCandidate -Id 'gigabyte-local-control-center' -Provider 'Gigabyte' -Category 'Utility' -Title 'GIGABYTE Control Center (local GCC cache)' `
            -InstalledVersion $installedVersion -CandidateVersion $Matches[1] -Channel 'Gigabyte local cache' -SourceUrl $null -PackagePath $gccPackage.FullName -PackageUrl $null `
            -DriverIdentity $null -Classification 'Utility' -InstallMode 'manual-review' -Revision $Revision
        $candidates.Add((Resolve-DriverMegaVersionState -Candidate $candidate))
    }

    $boardProduct = $Inventory.Computer.BaseBoardProduct
    $biosPackage = $LocalContext.Files | Where-Object { $_.Name -like ('mb_bios_' + ($boardProduct -replace '\s+', '-').ToLowerInvariant() + '*') } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($biosPackage -and $biosPackage.Name -match '_([a-z0-9]+)\.zip$') {
        $candidate = New-DriverMegaCandidate -Id 'gigabyte-local-bios' -Provider 'Gigabyte' -Category 'Firmware' -Title 'Gigabyte BIOS package (local GCC cache)' `
            -InstalledVersion $Inventory.Computer.BiosVersion -CandidateVersion $Matches[1].ToUpperInvariant() -Channel 'Gigabyte local cache' -SourceUrl $null -PackagePath $biosPackage.FullName -PackageUrl $null `
            -DriverIdentity 'System Firmware' -Classification 'Firmware' -InstallMode 'manual-confirmation' -Revision $Revision
        $candidate = Resolve-DriverMegaVersionState -Candidate $candidate -UseBiosComparison

        if (-not $Revision) {
            $candidate = Set-DriverMegaCandidateState -Candidate $candidate -State 'manual_review' -Reason 'Motherboard revision could not be proven from local metadata, so BIOS flashing is blocked.' -Action 'defer'
        }

        $candidates.Add($candidate)
    }

    return $candidates.ToArray()
}

function Get-DriverMegaGigabyteSupportCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Inventory,
        [Parameter(Mandatory = $true)]
        [hashtable]$Report
    )

    $localContext = Get-DriverMegaGigabyteLocalContext
    $boardProduct = $Inventory.Computer.BaseBoardProduct
    $revision = Get-DriverMegaGigabyteRevision -BoardProduct $boardProduct -LocalContext $localContext
    $revisionPath = if ($revision) { $revision -replace '\.', '' -replace 'x', '' } else { $null }

    $revisionCandidates = @()
    if ($revisionPath) {
        $revisionCandidates += $revisionPath
    }
    $revisionCandidates += '11', '10'
    $revisionCandidates = $revisionCandidates | Select-Object -Unique

    $slug = ($boardProduct -replace '\s+', '-')
    $supportResponse = $null
    $supportUrl = $null
    foreach ($candidateRevision in $revisionCandidates) {
        $candidateUrl = 'https://www.gigabyte.com/Motherboard/{0}-rev-{1}/support' -f $slug, $candidateRevision
        try {
            $supportResponse = Invoke-WebRequest -Uri $candidateUrl -UseBasicParsing -TimeoutSec 30
            $supportUrl = $candidateUrl
            break
        }
        catch {
        }
    }

    if (-not $supportResponse) {
        Add-DriverMegaWarning -Report $Report -Message 'Gigabyte support page could not be fetched. Gigabyte driver candidates were staged from local metadata only.'
        return @(Get-DriverMegaGigabyteLocalCandidates -Inventory $Inventory -LocalContext $localContext -Revision $revision)
    }

    $supportText = Get-DriverMegaSupportText -Response $supportResponse
    $packages = $Inventory.Packages
    $pnpDrivers = $Inventory.PnPDrivers

    $candidateList = New-Object System.Collections.Generic.List[hashtable]

    $audioVersion = Get-DriverMegaRegexMatchValue -Text $supportText -Pattern 'Realtek HD Audio Driver\s+([0-9][0-9\.]+)'
    if ($audioVersion) {
        $installedAudio = ($packages | Where-Object { $_.DisplayName -match 'Realtek Audio Driver' } | Select-Object -First 1).DisplayVersion
        if (-not $installedAudio) {
            $installedAudio = ($pnpDrivers | Where-Object { $_.DeviceName -eq 'Realtek High Definition Audio' } | Select-Object -First 1).DriverVersion
        }

        $candidate = New-DriverMegaCandidate -Id 'gigabyte-audio-realtek' -Provider 'Gigabyte' -Category 'Driver' -Title 'Realtek HD Audio Driver' `
            -InstalledVersion $installedAudio -CandidateVersion $audioVersion -Channel 'Gigabyte support page' -SourceUrl $supportUrl `
            -PackagePath (Find-DriverMegaLocalPackage -LocalContext $localContext -Keywords @('Realtek', 'Audio') -Version $audioVersion) `
            -PackageUrl $null -DriverIdentity 'Realtek High Definition Audio' -Classification 'Audio' -InstallMode 'pnputil-inf' -Revision $revision
        $candidateList.Add((Resolve-DriverMegaVersionState -Candidate $candidate))
    }

    $lanVersion = Get-DriverMegaRegexMatchValue -Text $supportText -Pattern 'Realtek LAN Driver\s+([0-9][0-9\.]+)'
    if ($lanVersion) {
        $installedLan = ($packages | Where-Object { $_.DisplayName -match 'Realtek Ethernet Controller Driver' } | Select-Object -First 1).DisplayVersion
        if (-not $installedLan) {
            $installedLan = ($pnpDrivers | Where-Object { $_.DeviceName -eq 'Realtek PCIe 2.5GbE Family Controller' } | Select-Object -First 1).DriverVersion
        }

        $candidate = New-DriverMegaCandidate -Id 'gigabyte-lan-realtek' -Provider 'Gigabyte' -Category 'Driver' -Title 'Realtek LAN Driver' `
            -InstalledVersion $installedLan -CandidateVersion $lanVersion -Channel 'Gigabyte support page' -SourceUrl $supportUrl `
            -PackagePath (Find-DriverMegaLocalPackage -LocalContext $localContext -Keywords @('Realtek', 'LAN') -Version $lanVersion) `
            -PackageUrl $null -DriverIdentity 'Realtek PCIe 2.5GbE Family Controller' -Classification 'Net' -InstallMode 'pnputil-inf' -Revision $revision
        $candidateList.Add((Resolve-DriverMegaVersionState -Candidate $candidate))
    }

    $wifiVersion = Get-DriverMegaRegexMatchValue -Text $supportText -Pattern 'Qualcomm Wi-Fi 7 WIFI driver\s+([0-9][0-9\.]+)'
    if ($wifiVersion) {
        $installedWifi = ($pnpDrivers | Where-Object { $_.DeviceName -like 'Qualcomm FastConnect 7800 Wi-Fi*' } | Select-Object -First 1).DriverVersion
        $candidate = New-DriverMegaCandidate -Id 'gigabyte-wifi-qualcomm' -Provider 'Gigabyte' -Category 'Driver' -Title 'Qualcomm Wi-Fi 7 WIFI driver' `
            -InstalledVersion $installedWifi -CandidateVersion $wifiVersion -Channel 'Gigabyte support page' -SourceUrl $supportUrl `
            -PackagePath (Find-DriverMegaLocalPackage -LocalContext $localContext -Keywords @('Qualcomm', 'WIFI') -Version $wifiVersion) `
            -PackageUrl $null -DriverIdentity 'Qualcomm FastConnect 7800 Wi-Fi 7 High Band Simultaneous (HBS) Network Adapter' -Classification 'Net' -InstallMode 'pnputil-inf' -Revision $revision
        $candidateList.Add((Resolve-DriverMegaVersionState -Candidate $candidate))
    }

    $bluetoothVersion = Get-DriverMegaRegexMatchValue -Text $supportText -Pattern 'Qualcomm Wi-Fi 7 Bluetooth Driver\s+([0-9][0-9\.]+)'
    if ($bluetoothVersion) {
        $installedBluetooth = ($pnpDrivers | Where-Object { $_.DeviceName -like 'Qualcomm FastConnect 7800 Dual Bluetooth Adapter' } | Select-Object -First 1).DriverVersion
        $candidate = New-DriverMegaCandidate -Id 'gigabyte-bt-qualcomm' -Provider 'Gigabyte' -Category 'Driver' -Title 'Qualcomm Wi-Fi 7 Bluetooth Driver' `
            -InstalledVersion $installedBluetooth -CandidateVersion $bluetoothVersion -Channel 'Gigabyte support page' -SourceUrl $supportUrl `
            -PackagePath (Find-DriverMegaLocalPackage -LocalContext $localContext -Keywords @('Qualcomm', 'Bluetooth') -Version $bluetoothVersion) `
            -PackageUrl $null -DriverIdentity 'Qualcomm FastConnect 7800 Dual Bluetooth Adapter' -Classification 'Bluetooth' -InstallMode 'pnputil-inf' -Revision $revision
        $candidateList.Add((Resolve-DriverMegaVersionState -Candidate $candidate))
    }

    $iteVersion = Get-DriverMegaRegexMatchValue -Text $supportText -Pattern 'ITE USB driver\s+([0-9][0-9\.]+)'
    if ($iteVersion) {
        $installedIte = ($pnpDrivers | Where-Object { $_.DeviceName -eq 'ITE USB Connector Client Device' } | Select-Object -First 1).DriverVersion
        $candidate = New-DriverMegaCandidate -Id 'gigabyte-usb-ite' -Provider 'Gigabyte' -Category 'Driver' -Title 'ITE USB driver' `
            -InstalledVersion $installedIte -CandidateVersion $iteVersion -Channel 'Gigabyte support page' -SourceUrl $supportUrl `
            -PackagePath (Find-DriverMegaLocalPackage -LocalContext $localContext -Keywords @('ITE', 'USB') -Version $iteVersion) `
            -PackageUrl $null -DriverIdentity 'ITE USB Connector Client Device' -Classification 'USBDevice' -InstallMode 'pnputil-inf' -Revision $revision
        $candidateList.Add((Resolve-DriverMegaVersionState -Candidate $candidate))
    }

    $apuVersion = Get-DriverMegaRegexMatchValue -Text $supportText -Pattern 'AMD APU Driver\s+([0-9][0-9\.]+)'
    if ($apuVersion) {
        $installedApu = Find-DriverMegaPackageVersion -Packages $packages -Patterns @('AMD Software$', 'AMD Radeon Software')
        $candidate = New-DriverMegaCandidate -Id 'gigabyte-amd-apu' -Provider 'Gigabyte' -Category 'Driver' -Title 'AMD APU Driver' `
            -InstalledVersion $installedApu -CandidateVersion $apuVersion -Channel 'Gigabyte support page' -SourceUrl $supportUrl `
            -PackagePath (Find-DriverMegaLocalPackage -LocalContext $localContext -Keywords @('ASETUP', '25\.10') -Version $apuVersion) `
            -PackageUrl $null -DriverIdentity 'AMD Radeon(TM) Graphics' -Classification 'Display' -InstallMode 'installer-extract-pnputil' -Revision $revision
        $candidateList.Add((Resolve-DriverMegaVersionState -Candidate $candidate))
    }

    $chipsetVersion = Get-DriverMegaRegexMatchValue -Text $supportText -Pattern 'AMD Chipset Driver\s+([0-9][0-9\.]+)'
    if ($chipsetVersion) {
        $installedChipset = Find-DriverMegaPackageVersion -Packages $packages -Patterns @('AMD Chipset Software')
        $candidate = New-DriverMegaCandidate -Id 'gigabyte-amd-chipset' -Provider 'Gigabyte' -Category 'Driver' -Title 'AMD Chipset Driver' `
            -InstalledVersion $installedChipset -CandidateVersion $chipsetVersion -Channel 'Gigabyte support page' -SourceUrl $supportUrl `
            -PackagePath (Find-DriverMegaLocalPackage -LocalContext $localContext -Keywords @('CSETUP', '7\.12') -Version $chipsetVersion) `
            -PackageUrl $null -DriverIdentity 'AMD SMBUS' -Classification 'System' -InstallMode 'amd-install-manager' -Revision $revision
        $candidateList.Add((Resolve-DriverMegaVersionState -Candidate $candidate))
    }

    $gccVersion = Get-DriverMegaRegexMatchValue -Text $supportText -Pattern 'GIGABYTE Control Center[_\s]+([0-9][0-9\.]+)'
    $installedGcc = Find-DriverMegaPackageVersion -Packages $packages -Patterns @('GIGABYTE Control Center')
    if ($installedGcc) {
        $localGccPath = Find-DriverMegaLocalPackage -LocalContext $localContext -Keywords @('Control Center') -Version $gccVersion
        $gccCandidateVersion = if ($gccVersion) { $gccVersion } else { $installedGcc }
        $candidate = New-DriverMegaCandidate -Id 'gigabyte-control-center' -Provider 'Gigabyte' -Category 'Utility' -Title 'GIGABYTE Control Center' `
            -InstalledVersion $installedGcc -CandidateVersion $gccCandidateVersion -Channel 'Gigabyte local cache' -SourceUrl $supportUrl `
            -PackagePath $localGccPath -PackageUrl $null -DriverIdentity $null -Classification 'Utility' -InstallMode 'installer-manual-review' -Revision $revision
        $candidateList.Add((Resolve-DriverMegaVersionState -Candidate $candidate))
    }

    $cachedBiosFile = $localContext.Files | Where-Object { $_.Name -like ('mb_bios_' + ($boardProduct -replace '\s+', '-').ToLowerInvariant() + '*') } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($cachedBiosFile -and $cachedBiosFile.Name -match '_([a-z0-9]+)\.zip$') {
        $cachedBiosVersion = $Matches[1].ToUpperInvariant()
        $cachedBiosVersion = $cachedBiosVersion -replace '^([A-Z])', '$1'
        $candidate = New-DriverMegaCandidate -Id 'gigabyte-bios-cached' -Provider 'Gigabyte' -Category 'Firmware' -Title 'Gigabyte BIOS package' `
            -InstalledVersion $Inventory.Computer.BiosVersion -CandidateVersion $cachedBiosVersion -Channel 'Gigabyte local cache' -SourceUrl $supportUrl `
            -PackagePath $cachedBiosFile.FullName -PackageUrl $null -DriverIdentity 'System Firmware' -Classification 'Firmware' -InstallMode 'manual-confirmation' -Revision $revision
        $candidate = Resolve-DriverMegaVersionState -Candidate $candidate -UseBiosComparison

        if (-not $revision) {
            $candidate = Set-DriverMegaCandidateState -Candidate $candidate -State 'manual_review' -Reason 'Motherboard revision could not be proven from local metadata, so BIOS flashing is blocked.' -Action 'defer'
        }

        $candidateList.Add($candidate)
    }

    if ($candidateList.Count -eq 0) {
        Add-DriverMegaWarning -Report $Report -Message 'Gigabyte support page responded, but no board-specific driver metadata could be parsed. Falling back to local GCC metadata.'
        return @(Get-DriverMegaGigabyteLocalCandidates -Inventory $Inventory -LocalContext $localContext -Revision $revision)
    }

    return $candidateList.ToArray()
}

function Get-DriverMegaWindowsUpdateCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report,
        [switch]$IncludeFirmwareUpdates
    )

    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $query = "IsInstalled=0 and IsHidden=0"
        $result = $searcher.Search($query)

        $candidates = New-Object System.Collections.Generic.List[hashtable]
        for ($index = 0; $index -lt $result.Updates.Count; $index++) {
            $update = $result.Updates.Item($index)
            $isDriver = $update.Type -eq 'Driver' -or $update.Title -match 'driver'
            $isFirmware = $update.Title -match 'firmware'

            if (-not $isDriver -and -not ($IncludeFirmwareUpdates -and $isFirmware)) {
                continue
            }

            $classification = if ($isFirmware) { 'Firmware' } else { 'Driver' }
            $candidate = New-DriverMegaCandidate -Id ('windows-update-' + $index) -Provider 'Microsoft' -Category $classification -Title $update.Title `
                -InstalledVersion $null -CandidateVersion $null -Channel 'Windows Update Agent' -SourceUrl $null -PackagePath $null -PackageUrl $null `
                -DriverIdentity $null -Classification $classification -InstallMode 'windows-update-agent' -Revision $null

            $candidate.State = 'update_available'
            $candidate.Reason = 'Windows Update reports this update as applicable and not installed.'
            $candidate.Action = 'apply'
            $candidate.WuaIndex = $index
            $candidates.Add($candidate)
        }

        return $candidates.ToArray()
    }
    catch {
        Add-DriverMegaWarning -Report $Report -Message ('Windows Update scan failed: ' + $_.Exception.Message)
        return @()
    }
}

function Get-DriverMegaAmdCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Inventory,
        [Parameter(Mandatory = $true)]
        [hashtable]$Report
    )

    $packages = $Inventory.Packages
    $amdInstallManagerPath = 'C:\Program Files\AMD\AMDInstallManager\AMDInstallManager.exe'
    $candidateList = New-Object System.Collections.Generic.List[hashtable]

    if (-not (Test-Path -LiteralPath $amdInstallManagerPath)) {
        Add-DriverMegaWarning -Report $Report -Message 'AMD Install Manager was not found; AMD auto-update execution will remain unavailable.'
        return @()
    }

    $displayVersion = Find-DriverMegaPackageVersion -Packages $packages -Patterns @('AMD Software$', 'AMD Radeon Software')
    $chipsetVersion = Find-DriverMegaPackageVersion -Packages $packages -Patterns @('AMD Chipset Software')

    $displayCandidate = New-DriverMegaCandidate -Id 'amd-display-installer' -Provider 'AMD' -Category 'Driver' -Title 'AMD display and software update channel' `
        -InstalledVersion $displayVersion -CandidateVersion $displayVersion -Channel 'AMD Install Manager' -SourceUrl 'https://www.amd.com/en/resources/support-articles/faqs/GPU-Driver-Autodetect.html' `
        -PackagePath $amdInstallManagerPath -PackageUrl $null -DriverIdentity 'AMD Radeon(TM) Graphics' -Classification 'Display' -InstallMode 'amd-install-manager' -Revision $null
    $displayCandidate = Set-DriverMegaCandidateState -Candidate $displayCandidate -State 'manual_review' -Reason 'AMD Install Manager is available and can apply official AMD updates, but the audit path does not force a live vendor install check.' -Action 'defer'
    $candidateList.Add($displayCandidate)

    if ($chipsetVersion) {
        $chipsetCandidate = New-DriverMegaCandidate -Id 'amd-chipset-installer' -Provider 'AMD' -Category 'Driver' -Title 'AMD chipset update channel' `
            -InstalledVersion $chipsetVersion -CandidateVersion $chipsetVersion -Channel 'AMD Install Manager' -SourceUrl 'https://www.amd.com/en/resources/support-articles/faqs/rs-install.html' `
            -PackagePath $amdInstallManagerPath -PackageUrl $null -DriverIdentity 'AMD SMBUS' -Classification 'System' -InstallMode 'amd-install-manager' -Revision $null
        $chipsetCandidate = Set-DriverMegaCandidateState -Candidate $chipsetCandidate -State 'manual_review' -Reason 'AMD Install Manager supports updating chipset components on this machine. Apply mode can invoke the official updater when vendor updates are enabled.' -Action 'defer'
        $candidateList.Add($chipsetCandidate)
    }

    return $candidateList.ToArray()
}

function Get-DriverMegaNvidiaCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Inventory,
        [Parameter(Mandatory = $true)]
        [hashtable]$Report
    )

    $packages = $Inventory.Packages
    $nvidiaAppStatusPath = 'C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\status\grd\download.json'
    $installedDriverVersion = Find-DriverMegaPackageVersion -Packages $packages -Patterns @('NVIDIA Graphics Driver')
    $installedAppVersion = Find-DriverMegaPackageVersion -Packages $packages -Patterns @('NVIDIA App')

    $candidates = New-Object System.Collections.Generic.List[hashtable]

    if (Test-Path -LiteralPath $nvidiaAppStatusPath) {
        try {
            $statusItems = Get-Content -LiteralPath $nvidiaAppStatusPath -Raw | ConvertFrom-Json
            foreach ($item in $statusItems) {
                $candidate = New-DriverMegaCandidate -Id 'nvidia-grd' -Provider 'NVIDIA' -Category 'Driver' -Title 'NVIDIA GeForce driver cache' `
                    -InstalledVersion $installedDriverVersion -CandidateVersion $item.version -Channel 'NVIDIA App update framework' `
                    -SourceUrl 'https://www.nvidia.com/en-us/geforce/drivers/' -PackagePath $item.fileLocation -PackageUrl $item.url `
                    -DriverIdentity 'NVIDIA GeForce RTX 5080' -Classification 'Display' -InstallMode 'nvidia-silent-installer' -Revision $null
                $candidates.Add((Resolve-DriverMegaVersionState -Candidate $candidate))
            }
        }
        catch {
            Add-DriverMegaWarning -Report $Report -Message ('NVIDIA driver cache could not be parsed: ' + $_.Exception.Message)
        }
    }
    else {
        Add-DriverMegaWarning -Report $Report -Message 'NVIDIA App driver cache was not found; NVIDIA driver auditing is limited to installed versions.'
    }

    $nvidiaAppUpdatePath = 'C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\status\nvapp\updatecheck.json'
    if (Test-Path -LiteralPath $nvidiaAppUpdatePath) {
        try {
            $appItems = Get-Content -LiteralPath $nvidiaAppUpdatePath -Raw | ConvertFrom-Json
            foreach ($item in $appItems) {
                $updateInfo = $item.updateInfoJSON | ConvertFrom-Json
                $candidate = New-DriverMegaCandidate -Id 'nvidia-app' -Provider 'NVIDIA' -Category 'Utility' -Title 'NVIDIA App' `
                    -InstalledVersion $installedAppVersion -CandidateVersion $updateInfo.version -Channel 'NVIDIA App update framework' `
                    -SourceUrl 'https://www.nvidia.com/en-us/software/nvidia-app/' -PackagePath $null -PackageUrl $updateInfo.url `
                    -DriverIdentity $null -Classification 'Utility' -InstallMode 'manual-review' -Revision $null
                $candidates.Add((Resolve-DriverMegaVersionState -Candidate $candidate))
            }
        }
        catch {
            Add-DriverMegaWarning -Report $Report -Message ('NVIDIA App update metadata could not be parsed: ' + $_.Exception.Message)
        }
    }

    return $candidates.ToArray()
}

function Get-DriverMegaPeripheralCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Inventory
    )

    $devices = $Inventory.PresentDevices
    $candidates = New-Object System.Collections.Generic.List[hashtable]

    if ($devices | Where-Object { $_.FriendlyName -match 'MX Anywhere 3S|Logitech' }) {
        $candidate = New-DriverMegaCandidate -Id 'peripheral-logitech' -Provider 'Logitech' -Category 'Firmware' -Title 'Logitech firmware path' `
            -InstalledVersion $null -CandidateVersion $null -Channel 'Logi Options+' -SourceUrl 'https://support.logi.com/hc/en-gb/articles/6526066717591-How-do-I-update-my-mouse-firmware' `
            -PackagePath $null -PackageUrl $null -DriverIdentity 'MX Anywhere 3S' -Classification 'Peripheral' -InstallMode 'manual-confirmation' -Revision $null
        $candidate = Set-DriverMegaCandidateState -Candidate $candidate -State 'manual_review' -Reason 'Logitech firmware updates should be staged manually, especially when the device is connected over Bluetooth.' -Action 'defer'
        $candidates.Add($candidate)
    }

    if ($devices | Where-Object { $_.FriendlyName -match 'Xbox Elite Wireless Controller|Bluetooth XINPUT-compatible input device' }) {
        $candidate = New-DriverMegaCandidate -Id 'peripheral-xbox-controller' -Provider 'Microsoft' -Category 'Firmware' -Title 'Xbox controller firmware path' `
            -InstalledVersion $null -CandidateVersion $null -Channel 'Xbox Accessories' -SourceUrl 'https://support.xbox.com/help/hardware-network/controller/update-xbox-wireless-controller' `
            -PackagePath $null -PackageUrl $null -DriverIdentity 'Xbox Elite Wireless Controller' -Classification 'Peripheral' -InstallMode 'manual-confirmation' -Revision $null
        $candidate = Set-DriverMegaCandidateState -Candidate $candidate -State 'manual_review' -Reason 'Xbox controller firmware should be staged through the official accessory workflow instead of forced headless flashing.' -Action 'defer'
        $candidates.Add($candidate)
    }

    return $candidates.ToArray()
}

function Test-DriverMegaAcPowerSafe {
    try {
        $battery = Get-CimInstance Win32_Battery -ErrorAction Stop | Select-Object -First 1
        if (-not $battery) {
            return $true
        }

        return $battery.BatteryStatus -eq 2 -or $battery.BatteryStatus -eq 6 -or $battery.BatteryStatus -eq 7 -or $battery.BatteryStatus -eq 8 -or $battery.BatteryStatus -eq 9
    }
    catch {
        return $true
    }
}

function Expand-DriverMegaPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackagePath,
        [Parameter(Mandatory = $true)]
        [string]$ScratchRoot
    )

    $packageName = [System.IO.Path]::GetFileNameWithoutExtension($PackagePath)
    $extractRoot = Join-Path $ScratchRoot $packageName
    if (Test-Path -LiteralPath $extractRoot) {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force
    }
    New-DriverMegaDirectory -Path $extractRoot | Out-Null

    if ($PackagePath -match '\.zip$') {
        Expand-Archive -LiteralPath $PackagePath -DestinationPath $extractRoot -Force
        return $extractRoot
    }

    $sevenZip = (Get-Command 7z -ErrorAction SilentlyContinue).Source
    if (-not $sevenZip) {
        throw '7z.exe is required to safely extract vendor driver packages.'
    }

    $arguments = @('x', '-y', ('-o' + $extractRoot), $PackagePath)
    $process = Start-Process -FilePath $sevenZip -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) {
        throw ('7z extraction failed for ' + $PackagePath + ' with exit code ' + $process.ExitCode)
    }

    return $extractRoot
}

function Get-DriverMegaInfFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    return Get-ChildItem -LiteralPath $Root -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue
}

function Invoke-DriverMegaPnPUtilInstall {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$InfPaths
    )

    if ($InfPaths.Count -eq 0) {
        throw 'No INF files were available for pnputil installation.'
    }

    $arguments = @('/add-driver') + $InfPaths + @('/install')
    $output = & pnputil.exe $arguments 2>&1
    $exitCode = $LASTEXITCODE

    return [ordered]@{
        ExitCode = $exitCode
        Output = ($output | Out-String)
        RequiresReboot = ($output | Out-String) -match 'restart|reboot'
    }
}

function Invoke-DriverMegaWindowsUpdateInstall {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable[]]$Candidates
    )

    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search("IsInstalled=0 and IsHidden=0")
    $collection = New-Object -ComObject Microsoft.Update.UpdateColl

    foreach ($candidate in $Candidates) {
        if ($candidate.PSObject.Properties.Name -contains 'WuaIndex') {
            $collection.Add($result.Updates.Item([int]$candidate.WuaIndex)) | Out-Null
        }
    }

    if ($collection.Count -eq 0) {
        return [ordered]@{
            ExitCode = 0
            Output = 'No Windows Update driver items were selected for installation.'
            RequiresReboot = $false
        }
    }

    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $collection
    $downloadResult = $downloader.Download()

    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $collection
    $installResult = $installer.Install()

    return [ordered]@{
        ExitCode = [int]$installResult.ResultCode
        Output = ('DownloadResult=' + $downloadResult.ResultCode + '; InstallResult=' + $installResult.ResultCode)
        RequiresReboot = [bool]$installResult.RebootRequired
    }
}

function Invoke-DriverMegaAmdInstallManager {
    $amdInstallManagerPath = 'C:\Program Files\AMD\AMDInstallManager\AMDInstallManager.exe'
    if (-not (Test-Path -LiteralPath $amdInstallManagerPath)) {
        throw 'AMD Install Manager is not available.'
    }

    $arguments = @('-InstallUpdates', '-Force')
    $process = Start-Process -FilePath $amdInstallManagerPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    $latestLog = Get-ChildItem 'C:\Program Files\AMD\AMDInstallManager\Logs' -Filter 'amddime_InstallUpdates_*.log' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    return [ordered]@{
        ExitCode = $process.ExitCode
        Output = if ($latestLog) { Get-Content -LiteralPath $latestLog.FullName -Tail 30 | Out-String } else { 'AMD Install Manager completed without a discovered InstallUpdates log.' }
        RequiresReboot = $process.ExitCode -ne 0 -or (($latestLog -and ((Get-Content -LiteralPath $latestLog.FullName -Raw) -match 'reboot|restart')) -eq $true)
    }
}

function Invoke-DriverMegaNvidiaSilentInstall {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath
    )

    if (-not (Test-Path -LiteralPath $InstallerPath)) {
        throw ('NVIDIA installer was not found: ' + $InstallerPath)
    }

    $arguments = @('-s', '-noreboot')
    $process = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow

    return [ordered]@{
        ExitCode = $process.ExitCode
        Output = ('NVIDIA installer completed with exit code ' + $process.ExitCode)
        RequiresReboot = $process.ExitCode -eq 1 -or $process.ExitCode -eq 2
    }
}

function Save-DriverMegaState {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report,
        [Parameter(Mandatory = $true)]
        [hashtable]$Paths
    )

    $state = [ordered]@{
        SavedAt = (Get-Date).ToString('o')
        Mode = $Report.Mode
        ReportPath = $Paths.ReportPath
        Updates = $Report.Updates
        Installed = $Report.Installed
        Deferred = $Report.Deferred
        NeedsReboot = $Report.NeedsReboot
        Notes = $Report.Notes
        Warnings = $Report.Warnings
        Errors = $Report.Errors
    }

    Save-DriverMegaJson -Object $state -Path $Paths.StatePath
}

function Initialize-DriverMegaReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CurrentMode
    )

    return [ordered]@{
        RunId = [guid]::NewGuid().Guid
        StartedAt = (Get-Date).ToString('o')
        Mode = $CurrentMode
        Parameters = [ordered]@{
            IncludeFirmware = [bool]$IncludeFirmware
            IncludePeripheralVendors = [bool]$IncludePeripheralVendors
            AutoInstallVendorDrivers = [bool]$AutoInstallVendorDrivers
            AutoReboot = [bool]$AutoReboot
            Resume = [bool]$Resume
        }
        Inventory = $null
        Sources = @()
        Updates = New-Object System.Collections.ArrayList
        Installed = New-Object System.Collections.ArrayList
        Deferred = New-Object System.Collections.ArrayList
        NeedsReboot = New-Object System.Collections.ArrayList
        Notes = New-Object System.Collections.ArrayList
        Warnings = New-Object System.Collections.ArrayList
        Errors = New-Object System.Collections.ArrayList
        FinishedAt = $null
    }
}

function Add-DriverMegaCandidateToReport {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report,
        [Parameter(Mandatory = $true)]
        [hashtable[]]$Candidates
    )

    foreach ($candidate in $Candidates) {
        $Report.Updates.Add($candidate) | Out-Null
        if ($candidate.State -match 'blocked_downgrade|manual_review') {
            $Report.Deferred.Add($candidate) | Out-Null
        }
    }
}

function Add-DriverMegaCandidatesToList {
    param(
        [System.Collections.Generic.List[hashtable]]$List,
        [AllowNull()]
        [object[]]$Candidates
    )

    foreach ($candidate in @($Candidates)) {
        if ($candidate -is [hashtable]) {
            $List.Add($candidate)
        }
    }
}

function Test-DriverMegaShouldApplyCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Candidate
    )

    if ($Candidate.State -ne 'update_available') {
        return $false
    }

    if ($Candidate.Category -eq 'Firmware') {
        return $false
    }

    return $true
}

function Invoke-DriverMegaCandidateInstall {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Candidate,
        [Parameter(Mandatory = $true)]
        [hashtable]$Paths,
        [Parameter(Mandatory = $true)]
        [hashtable]$Report
    )

    switch ($Candidate.InstallMode) {
        'windows-update-agent' {
            return Invoke-DriverMegaWindowsUpdateInstall -Candidates @($Candidate)
        }
        'amd-install-manager' {
            return Invoke-DriverMegaAmdInstallManager
        }
        'nvidia-silent-installer' {
            return Invoke-DriverMegaNvidiaSilentInstall -InstallerPath $Candidate.PackagePath
        }
        'pnputil-inf' {
            if (-not $Candidate.PackagePath) {
                throw 'No local package path was available for pnputil installation.'
            }

            $extractRoot = Expand-DriverMegaPackage -PackagePath $Candidate.PackagePath -ScratchRoot $Paths.ScratchRoot
            $infFiles = Get-DriverMegaInfFiles -Root $extractRoot | Select-Object -ExpandProperty FullName
            return Invoke-DriverMegaPnPUtilInstall -InfPaths $infFiles
        }
        'installer-extract-pnputil' {
            if (-not $Candidate.PackagePath) {
                throw 'No local package path was available for vendor extraction.'
            }

            $extractRoot = Expand-DriverMegaPackage -PackagePath $Candidate.PackagePath -ScratchRoot $Paths.ScratchRoot
            $infFiles = Get-DriverMegaInfFiles -Root $extractRoot | Select-Object -ExpandProperty FullName
            if ($infFiles.Count -eq 0) {
                throw 'The vendor package did not expose INF files after extraction.'
            }

            return Invoke-DriverMegaPnPUtilInstall -InfPaths $infFiles
        }
        default {
            throw ('Unsupported install mode: ' + $Candidate.InstallMode)
        }
    }
}

function Request-DriverMegaReboot {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report,
        [Parameter(Mandatory = $true)]
        [hashtable]$Paths
    )

    Save-DriverMegaState -Report $Report -Paths $Paths

    if ($AutoReboot) {
        Restart-Computer -Force
        return
    }

    $confirmation = Read-Host 'A reboot is required to complete one or more updates. Type REBOOT to restart now, or press Enter to defer'
    if ($confirmation -eq 'REBOOT') {
        Restart-Computer -Force
    }
}

function Invoke-DriverMegaSummary {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report
    )

    Write-DriverMegaConsoleSection -Title 'Inventory'
    Write-Host ('Board: ' + $Report.Inventory.Computer.BaseBoardProduct)
    Write-Host ('BIOS: ' + $Report.Inventory.Computer.BiosVersion)
    Write-Host ('CPU: ' + (($Report.Inventory.Cpu | Select-Object -First 1).Name))
    Write-Host ('Displays: ' + (($Report.Inventory.Displays | ForEach-Object { $_.Name }) -join '; '))
    Write-Host ('Problem devices: ' + @($Report.Inventory.ProblemDevices).Count)

    Write-DriverMegaConsoleSection -Title 'Updates Found'
    if ($Report.Updates.Count -eq 0) {
        Write-Host 'No update candidates were detected.'
    }
    else {
        $Report.Updates | ForEach-Object {
            Write-Host ('[{0}] {1} | installed={2} | candidate={3} | state={4}' -f $_.Provider, $_.Title, $_.InstalledVersion, $_.CandidateVersion, $_.State)
        }
    }

    Write-DriverMegaConsoleSection -Title 'Installed'
    if ($Report.Installed.Count -eq 0) {
        Write-Host 'No updates were installed in this run.'
    }
    else {
        $Report.Installed | ForEach-Object {
            Write-Host ('{0} | result={1}' -f $_.Title, $_.Result)
        }
    }

    Write-DriverMegaConsoleSection -Title 'Deferred'
    if ($Report.Deferred.Count -eq 0) {
        Write-Host 'No items were deferred.'
    }
    else {
        $Report.Deferred | ForEach-Object {
            Write-Host ('{0} | state={1} | reason={2}' -f $_.Title, $_.State, $_.Reason)
        }
    }

    Write-DriverMegaConsoleSection -Title 'Needs Reboot'
    if ($Report.NeedsReboot.Count -eq 0) {
        Write-Host 'No reboot is currently queued.'
    }
    else {
        $Report.NeedsReboot | ForEach-Object {
            Write-Host $_
        }
    }

    Write-DriverMegaConsoleSection -Title 'Needs Manual Approval'
    $manualItems = $Report.Updates | Where-Object { $_.Category -eq 'Firmware' -or $_.State -eq 'manual_review' }
    if (-not $manualItems) {
        Write-Host 'No manual approval items remain.'
    }
    else {
        $manualItems | ForEach-Object {
            Write-Host ('{0} | {1}' -f $_.Title, $_.Reason)
        }
    }
}

function Invoke-DriverMegaMain {
    $paths = Get-DriverMegaReportPaths -RequestedReportPath $ReportPath -ResumeRequested:$Resume
    $report = Initialize-DriverMegaReport -CurrentMode $Mode

    if (-not (Test-DriverMegaAdministrator)) {
        throw 'Invoke-DriverMega.ps1 must be run from an elevated PowerShell session.'
    }

    if ($Resume -and (Test-Path -LiteralPath $paths.StatePath)) {
        try {
            $savedState = Get-DriverMegaJson -Path $paths.StatePath
            Add-DriverMegaNote -Report $report -Message ('Resuming from state file ' + $paths.StatePath + ' saved at ' + $savedState.SavedAt)
        }
        catch {
            Add-DriverMegaWarning -Report $report -Message ('Resume was requested but the state file could not be loaded cleanly: ' + $_.Exception.Message)
        }
    }

    $report.Inventory = Get-DriverMegaHardwareInventory
    $report.Sources += 'Windows Update Agent'
    $report.Sources += 'Gigabyte support page'
    $report.Sources += 'AMD Install Manager'
    $report.Sources += 'NVIDIA App update framework'

    if (@($report.Inventory.ProblemDevices).Count -gt 0) {
        Add-DriverMegaWarning -Report $report -Message ('Detected ' + @($report.Inventory.ProblemDevices).Count + ' device(s) reporting a ConfigManager error code.')
    }

    $allCandidates = New-Object System.Collections.Generic.List[hashtable]
    Add-DriverMegaCandidatesToList -List $allCandidates -Candidates (Get-DriverMegaWindowsUpdateCandidates -Report $report -IncludeFirmwareUpdates:$IncludeFirmware)
    Add-DriverMegaCandidatesToList -List $allCandidates -Candidates (Get-DriverMegaGigabyteSupportCandidates -Inventory $report.Inventory -Report $report)
    Add-DriverMegaCandidatesToList -List $allCandidates -Candidates (Get-DriverMegaAmdCandidates -Inventory $report.Inventory -Report $report)
    Add-DriverMegaCandidatesToList -List $allCandidates -Candidates (Get-DriverMegaNvidiaCandidates -Inventory $report.Inventory -Report $report)

    if ($IncludePeripheralVendors) {
        Add-DriverMegaCandidatesToList -List $allCandidates -Candidates (Get-DriverMegaPeripheralCandidates -Inventory $report.Inventory)
    }

    Add-DriverMegaCandidateToReport -Report $report -Candidates $allCandidates.ToArray()

    if ($Mode -eq 'Apply') {
        try {
            Checkpoint-Computer -Description 'DriverMega pre-update checkpoint' -RestorePointType 'MODIFY_SETTINGS' | Out-Null
            Add-DriverMegaNote -Report $report -Message 'A Windows restore checkpoint was requested before driver changes.'
        }
        catch {
            Add-DriverMegaWarning -Report $report -Message ('Windows restore checkpoint was not created: ' + $_.Exception.Message)
        }

        foreach ($candidate in @($report.Updates)) {
            if (-not (Test-DriverMegaShouldApplyCandidate -Candidate $candidate)) {
                continue
            }

            if (($candidate.Provider -eq 'AMD' -or $candidate.Provider -eq 'NVIDIA') -and -not $AutoInstallVendorDrivers) {
                $candidate.State = 'manual_review'
                $candidate.Reason = 'Vendor auto-install was skipped because -AutoInstallVendorDrivers was not supplied.'
                $candidate.Action = 'defer'
                $report.Deferred.Add($candidate) | Out-Null
                continue
            }

            if ($candidate.Category -eq 'Firmware') {
                $candidate.State = 'manual_review'
                $candidate.Reason = 'Firmware updates require explicit confirmation and are never flashed blindly.'
                $candidate.Action = 'defer'
                $report.Deferred.Add($candidate) | Out-Null
                continue
            }

            try {
                $installResult = Invoke-DriverMegaCandidateInstall -Candidate $candidate -Paths $paths -Report $report
                $candidate.Result = $installResult.Output
                $report.Installed.Add($candidate) | Out-Null

                if ($installResult.RequiresReboot) {
                    $candidate.RequiresReboot = $true
                    $report.NeedsReboot.Add($candidate.Title) | Out-Null
                }
            }
            catch {
                $candidate.State = 'manual_review'
                $candidate.Reason = ('Automatic install failed safely: ' + $_.Exception.Message)
                $candidate.Action = 'defer'
                $report.Deferred.Add($candidate) | Out-Null
                Add-DriverMegaWarning -Report $report -Message ($candidate.Title + ' failed to install automatically: ' + $_.Exception.Message)
            }

            Save-DriverMegaState -Report $report -Paths $paths
        }

        if ($IncludeFirmware) {
            $biosCandidate = $report.Updates | Where-Object { $_.Id -eq 'gigabyte-bios-cached' } | Select-Object -First 1
            if ($biosCandidate -and $biosCandidate.State -eq 'update_available') {
                if (-not (Test-DriverMegaAcPowerSafe)) {
                    $biosCandidate.State = 'manual_review'
                    $biosCandidate.Reason = 'AC power state could not be verified as safe for BIOS flashing.'
                    $report.Deferred.Add($biosCandidate) | Out-Null
                }
                else {
                    $biosCandidate.State = 'manual_review'
                    $biosCandidate.Reason = 'BIOS package was identified, but flashing remains gated behind explicit operator confirmation.'
                    $report.Deferred.Add($biosCandidate) | Out-Null
                }
            }
        }

        if ($report.NeedsReboot.Count -gt 0) {
            Request-DriverMegaReboot -Report $report -Paths $paths
        }
    }

    $report.FinishedAt = (Get-Date).ToString('o')
    Save-DriverMegaJson -Object $report -Path $paths.ReportPath
    Save-DriverMegaState -Report $report -Paths $paths
    Invoke-DriverMegaSummary -Report $report

    Write-Host ''
    Write-Host ('Report written to: ' + $paths.ReportPath) -ForegroundColor Green
    Write-Host ('State written to:  ' + $paths.StatePath) -ForegroundColor Green
}

if (-not $script:DriverMegaIsDotSourced) {
    Invoke-DriverMegaMain
}
