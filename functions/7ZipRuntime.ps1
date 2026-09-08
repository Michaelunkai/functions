# Shared 7-Zip runtime resolution for the profile commands 7z and get7z.
# The old profile entries pointed at removed C: and F: files.  Keep discovery
# data-driven so a Scoop relocation or a normal 7-Zip installation remains
# usable without another profile rewrite.

function Resolve-7ZipExecutable {
    [CmdletBinding()]
    param()

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $addCandidate = {
        param([string]$Candidate)
        if ([string]::IsNullOrWhiteSpace($Candidate)) {
            return
        }
        try {
            $fullCandidate = [IO.Path]::GetFullPath($Candidate)
        }
        catch {
            return
        }
        if (-not $candidates.Contains($fullCandidate)) {
            [void]$candidates.Add($fullCandidate)
        }
    }

    foreach ($candidate in @(
            'F:\backup\windowsapps\installed\scoop\apps\7zip\current\7z.exe',
            'F:\backup\windowsapps\installed\scoop\shims\7z.exe',
            'C:\Program Files\7-Zip\7z.exe',
            'C:\Program Files (x86)\7-Zip\7z.exe',
            'C:\ProgramData\chocolatey\bin\7z.exe'
        )) {
        [void]$addCandidate.Invoke([string]$candidate)
    }

    $scoopRoot = [Environment]::GetEnvironmentVariable('SCOOP')
    if (-not [string]::IsNullOrWhiteSpace($scoopRoot)) {
        [void]$addCandidate.Invoke((Join-Path $scoopRoot 'apps\7zip\current\7z.exe'))
        [void]$addCandidate.Invoke((Join-Path $scoopRoot 'shims\7z.exe'))
    }
    $localAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA')
    if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
        [void]$addCandidate.Invoke((Join-Path $localAppData 'scoop\apps\7zip\current\7z.exe'))
        [void]$addCandidate.Invoke((Join-Path $localAppData 'scoop\shims\7z.exe'))
    }

    foreach ($registryPath in @(
            'HKLM:\SOFTWARE\7-Zip',
            'HKLM:\SOFTWARE\WOW6432Node\7-Zip',
            'HKCU:\SOFTWARE\7-Zip'
        )) {
        $registryProperties = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
        if (-not $registryProperties) {
            continue
        }
        foreach ($propertyName in @('Path64', 'Path', 'InstallLocation')) {
            $propertyValue = [string]$registryProperties.$propertyName
            if ([string]::IsNullOrWhiteSpace($propertyValue)) {
                continue
            }
            if ([IO.Path]::GetExtension($propertyValue) -ieq '.exe') {
                [void]$addCandidate.Invoke($propertyValue)
            }
            else {
                [void]$addCandidate.Invoke((Join-Path $propertyValue '7z.exe'))
            }
        }
    }

    $pathCommand = Get-Command -Name '7z.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pathCommand) {
        [void]$addCandidate.Invoke([string]$pathCommand.Source)
        [void]$addCandidate.Invoke([string]$pathCommand.Path)
    }

    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            continue
        }
        try {
            $item = Get-Item -LiteralPath $candidate -ErrorAction Stop
            if ($item -is [IO.FileInfo]) {
                return $item.FullName
            }
        }
        catch {
            continue
        }
    }

    return $null
}

function Get-7ZipInstallerCandidate {
    [CmdletBinding()]
    param()

    foreach ($candidate in @(
            'F:\backup\windowsapps\install\7z2409-x64.exe',
            'F:\backup\windowsapps\install\7z2408-x64.exe',
            'F:\backup\windowsapps\install\7z.exe'
        )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Get-Item -LiteralPath $candidate).FullName
        }
    }

    foreach ($root in @(
            'F:\backup\windowsapps\install',
            'F:\Downloads',
            (Join-Path ([Environment]::GetEnvironmentVariable('USERPROFILE')) 'Downloads')
        )) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            continue
        }
        $candidate = Get-ChildItem -LiteralPath $root -Filter '7z*.exe' -File -Force -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }
    }

    return $null
}

function Install-7ZipFromAvailableSource {
    [CmdletBinding()]
    param(
        [object[]]$InstallerArguments = @()
    )

    $installer = Get-7ZipInstallerCandidate
    if ($installer) {
        Write-Host "Running 7-Zip installer: $installer" -ForegroundColor Cyan
        & $installer @InstallerArguments
        $installerExitCode = $LASTEXITCODE
        if ($installerExitCode -ne 0) {
            throw "7-Zip installer failed with exit code ${installerExitCode}: $installer"
        }
        return
    }

    $scoopCandidates = New-Object 'System.Collections.Generic.List[string]'
    [void]$scoopCandidates.Add('F:\backup\windowsapps\installed\scoop\shims\scoop.cmd')
    $scoopRoot = [Environment]::GetEnvironmentVariable('SCOOP')
    if (-not [string]::IsNullOrWhiteSpace($scoopRoot)) {
        [void]$scoopCandidates.Add((Join-Path $scoopRoot 'shims\scoop.cmd'))
    }
    $scoopCommand = Get-Command -Name 'scoop.cmd' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($scoopCommand) {
        [void]$scoopCandidates.Add([string]$scoopCommand.Source)
        [void]$scoopCandidates.Add([string]$scoopCommand.Path)
    }
    foreach ($scoop in $scoopCandidates) {
        if (-not (Test-Path -LiteralPath $scoop -PathType Leaf)) {
            continue
        }
        Write-Host "Installing 7-Zip through Scoop: $scoop" -ForegroundColor Cyan
        & $scoop install 7zip
        $scoopExitCode = $LASTEXITCODE
        if ($scoopExitCode -ne 0) {
            throw "Scoop could not install 7-Zip; exit code $scoopExitCode."
        }
        return
    }

    $wingetCommand = Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($wingetCommand) {
        Write-Host 'Installing 7-Zip through WinGet.' -ForegroundColor Cyan
        & $wingetCommand.Source install --id 7zip.7zip --exact --silent --accept-package-agreements --accept-source-agreements
        $wingetExitCode = $LASTEXITCODE
        if ($wingetExitCode -ne 0) {
            throw "WinGet could not install 7-Zip; exit code $wingetExitCode."
        }
        return
    }

    throw '7-Zip is not installed and no local installer, Scoop, or WinGet source is available.'
}
