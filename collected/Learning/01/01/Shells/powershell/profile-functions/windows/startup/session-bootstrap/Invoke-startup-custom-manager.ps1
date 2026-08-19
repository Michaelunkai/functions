[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Add', 'Remove')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string[]]$Value,

    [switch]$NoApply
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:WindowsPowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $script:WindowsPowerShellExe -PathType Leaf)) {
    throw "Windows PowerShell 5 executable not found: $script:WindowsPowerShellExe"
}
$targets = @(
    [pscustomobject]@{
        Name = 'allstart'
        Directory = Join-Path $projectRoot 'AllStartBootstrap'
        CustomConfigPath = Join-Path $projectRoot 'AllStartBootstrap\allstart.custom.psd1'
        TestPath = Join-Path $projectRoot 'AllStartBootstrap\Test-allstart.ps1'
    },
    [pscustomobject]@{
        Name = 'allstart2'
        Directory = Join-Path $projectRoot 'AllStartTwoBootstrap'
        CustomConfigPath = Join-Path $projectRoot 'AllStartTwoBootstrap\allstart2.custom.psd1'
        TestPath = Join-Path $projectRoot 'AllStartTwoBootstrap\Test-allstart2.ps1'
    }
)

$builtInStartupCatalog = @(
    [pscustomobject]@{
        Key = 'Murmure_Tray'
        Aliases = @(
            'Murmure_Tray',
            'murmure',
            'murmure.exe',
            'C:\Program Files\murmure\murmure.exe',
            'OpenWhisper_Tray',
            'openwhisper',
            'openwhisper.exe',
            'openwhispr',
            'openwhispr.exe',
            'F:\backup\windowsapps\installed\OpenWhisper\OpenWhispr\OpenWhispr.exe'
        )
        TargetPath = 'C:\Program Files\murmure\murmure.exe'
        Execute = 'C:\Windows\System32\wscript.exe'
        Arguments = '"C:\Users\micha\.claude\scripts\murmure-silent.vbs"'
        RequiredLauncherPath = 'C:\Users\micha\.claude\scripts\murmure-silent.vbs'
        SupportedActions = @('Add', 'Remove')
    }
)

function Get-StartupCustomEntries {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    $config = Import-PowerShellDataFile -LiteralPath $Path
    if ($config.ContainsKey('CustomScheduledTasks')) {
        return @($config.CustomScheduledTasks)
    }

    return @()
}

function Get-StartupDisabledBuiltIns {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    $config = Import-PowerShellDataFile -LiteralPath $Path
    if ($config.ContainsKey('DisabledBuiltIns')) {
        return @($config.DisabledBuiltIns)
    }

    return @()
}

function Get-StartupTaskNameFromPath {
    param([string]$TargetPath)

    $baseName = [IO.Path]::GetFileNameWithoutExtension($TargetPath)
    if ([string]::IsNullOrWhiteSpace($baseName)) {
        $baseName = [IO.Path]::GetFileName($TargetPath)
    }
    $sanitized = (($baseName -replace '[^A-Za-z0-9]+', '_').Trim('_'))
    if ([string]::IsNullOrWhiteSpace($sanitized)) {
        $sanitized = 'item'
    }

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($TargetPath.ToLowerInvariant())
        $hash = [BitConverter]::ToString($sha1.ComputeHash($bytes)).Replace('-', '').Substring(0, 8).ToLowerInvariant()
    } finally {
        $sha1.Dispose()
    }

    return "CustomStartup_${sanitized}_$hash"
}

function Resolve-StartupCurrentWindowsAppsTargetPath {
    param([string]$TargetPath)

    if ([string]::IsNullOrWhiteSpace($TargetPath)) { return $null }
    $expanded = [Environment]::ExpandEnvironmentVariables($TargetPath)
    if (Test-Path -LiteralPath $expanded -PathType Leaf) {
        return (Resolve-Path -LiteralPath $expanded).ProviderPath
    }
    if ($expanded -notmatch '(?i)\\WindowsApps\\([^\\]+)\\(.+)$') { return $null }

    $oldPackageFolder = $matches[1]
    $relativePath = $matches[2]
    $packageName = $null
    $publisherSuffix = $null
    if ($oldPackageFolder -match '^(.+?)_[0-9]') { $packageName = $matches[1] }
    if ($oldPackageFolder -match '__(.+)$') { $publisherSuffix = $matches[1] }

    $packages = @(
        Get-AppxPackage -ErrorAction SilentlyContinue |
            Where-Object {
                $_.InstallLocation -and
                (Test-Path -LiteralPath $_.InstallLocation) -and
                (
                    ($packageName -and $_.Name.Equals($packageName, [System.StringComparison]::OrdinalIgnoreCase)) -or
                    ($publisherSuffix -and $_.PackageFamilyName.EndsWith("_$publisherSuffix", [System.StringComparison]::OrdinalIgnoreCase))
                )
            } |
            Sort-Object PackageFullName -Descending
    )

    foreach ($package in $packages) {
        $sameRelativePath = Join-Path $package.InstallLocation $relativePath
        if (Test-Path -LiteralPath $sameRelativePath -PathType Leaf) {
            return (Resolve-Path -LiteralPath $sameRelativePath).ProviderPath
        }

        $leaf = [IO.Path]::GetFileName($expanded)
        if (-not [string]::IsNullOrWhiteSpace($leaf)) {
            $match = Get-ChildItem -LiteralPath $package.InstallLocation -Filter $leaf -File -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($match) { return $match.FullName }
        }
    }

    return $null
}

function Resolve-StartupCurrentTargetPath {
    param([string]$TargetPath)

    if ([string]::IsNullOrWhiteSpace($TargetPath)) { return $TargetPath }
    $expanded = [Environment]::ExpandEnvironmentVariables($TargetPath)
    if (Test-Path -LiteralPath $expanded -PathType Leaf) {
        return (Resolve-Path -LiteralPath $expanded).ProviderPath
    }

    $windowsAppsTarget = Resolve-StartupCurrentWindowsAppsTargetPath -TargetPath $expanded
    if ($windowsAppsTarget) { return $windowsAppsTarget }

    return $TargetPath
}

function Update-StartupCustomEntryTargetPath {
    param(
        [object]$Entry,
        [string]$TargetPath
    )

    $updated = [ordered]@{}
    foreach ($property in @($Entry.Keys)) {
        $updated[[string]$property] = $Entry[$property]
    }
    $updated.TargetPath = $TargetPath
    $updated.Description = "Window-suppressed startup target: $TargetPath"
    return $updated
}

function Normalize-StartupCustomEntries {
    param([object[]]$Entries)

    @(
        foreach ($entry in @($Entries)) {
            $targetPath = [string](Get-StartupCustomField -Entry $entry -Name 'TargetPath')
            $currentPath = Resolve-StartupCurrentTargetPath -TargetPath $targetPath
            if ($currentPath -and -not $currentPath.Equals($targetPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                Update-StartupCustomEntryTargetPath -Entry $entry -TargetPath $currentPath
            } else {
                $entry
            }
        }
    )
}

function Update-StartupCustomConfigsToCurrentTargets {
    param(
        [object[]]$Targets,
        [switch]$NoWrite
    )

    foreach ($target in @($Targets)) {
        $path = [string]$target.CustomConfigPath
        if (-not (Test-Path -LiteralPath $path)) { continue }

        $disabledBuiltIns = @(Get-StartupDisabledBuiltIns -Path $path)
        $entries = @(Get-StartupCustomEntries -Path $path)
        $normalized = @(Normalize-StartupCustomEntries -Entries $entries)
        $before = ConvertTo-Json @($entries | ForEach-Object { [string](Get-StartupCustomField -Entry $_ -Name 'TargetPath') }) -Compress
        $after = ConvertTo-Json @($normalized | ForEach-Object { [string](Get-StartupCustomField -Entry $_ -Name 'TargetPath') }) -Compress
        if (-not $before.Equals($after, [System.StringComparison]::Ordinal)) {
            Write-Host "Updated stale startup target path(s) in $path"
            if (-not $NoWrite) {
                Save-StartupCustomEntries -Path $path -Entries $normalized -DisabledBuiltIns $disabledBuiltIns
            }
        }
    }
}

function ConvertTo-StartupCustomConfigText {
    param(
        [object[]]$Entries,
        [string[]]$DisabledBuiltIns = @()
    )

    $lines = @(
        '@{'
        '    CustomScheduledTasks = @('
    )

    foreach ($entry in @($Entries)) {
        $name = ([string]$entry.Name).Replace("'", "''")
        $targetPath = ([string]$entry.TargetPath).Replace("'", "''")
        $description = ([string]$entry.Description).Replace("'", "''")
        $parts = @(
            "Name = '$name'"
            "TargetPath = '$targetPath'"
            "Description = '$description'"
        )
        $entryTypeValue = Get-StartupCustomField -Entry $entry -Name 'EntryType'
        if ($entryTypeValue) {
            $entryType = ([string]$entryTypeValue).Replace("'", "''")
            $parts += "EntryType = '$entryType'"
        }
        $packageFamilyNameValue = Get-StartupCustomField -Entry $entry -Name 'PackageFamilyName'
        if ($packageFamilyNameValue) {
            $packageFamilyName = ([string]$packageFamilyNameValue).Replace("'", "''")
            $parts += "PackageFamilyName = '$packageFamilyName'"
        }
        $taskIdValue = Get-StartupCustomField -Entry $entry -Name 'TaskId'
        if ($taskIdValue) {
            $taskId = ([string]$taskIdValue).Replace("'", "''")
            $parts += "TaskId = '$taskId'"
        }
        $enabledStateValue = Get-StartupCustomField -Entry $entry -Name 'EnabledState'
        if ($null -ne $enabledStateValue) {
            $parts += "EnabledState = $([int]$enabledStateValue)"
        }
        $lines += "        @{ $($parts -join '; ') }"
    }

    $lines += '    )'
    $lines += '    DisabledBuiltIns = @('
    foreach ($name in @($DisabledBuiltIns | Where-Object { $_ } | Sort-Object -Unique)) {
        $escapedName = ([string]$name).Replace("'", "''")
        $lines += "        '$escapedName'"
    }
    $lines += '    )'
    $lines += '}'
    return ($lines -join [Environment]::NewLine) + [Environment]::NewLine
}

function Get-StartupCustomField {
    param(
        [object]$Entry,
        [string]$Name
    )

    if ($Entry -is [System.Collections.IDictionary]) {
        if ($Entry.Contains($Name)) { return $Entry[$Name] }
        return $null
    }

    $property = $Entry.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }
    return $null
}

function Get-AppStartupTaskForTargetPath {
    param([string]$TargetPath)

    $package = Get-AppxPackage | Where-Object {
        $_.InstallLocation -and
        $TargetPath.StartsWith($_.InstallLocation, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1
    if (-not $package) {
        return $null
    }

    $stateBase = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$($package.PackageFamilyName)"
    if (-not (Test-Path -LiteralPath $stateBase)) {
        return $null
    }

    $tasks = @(
        foreach ($taskKey in @(Get-ChildItem -LiteralPath $stateBase -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -LiteralPath $taskKey.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $props -or $null -eq $props.PSObject.Properties['State']) { continue }
            [pscustomobject]@{
                PackageFamilyName = $package.PackageFamilyName
                TaskId = $taskKey.PSChildName
                State = [int]$props.State
            }
        }
    )
    if (@($tasks).Count -eq 0) {
        return $null
    }

    $preferred = $tasks | Where-Object { $_.TaskId -like '*Startup*' } | Select-Object -First 1
    if (-not $preferred) {
        $preferred = $tasks | Select-Object -First 1
    }

    return [pscustomobject]@{
        PackageFamilyName = $preferred.PackageFamilyName
        TaskId = $preferred.TaskId
        State = $preferred.State
    }
}

function Test-StartupNameMatch {
    param(
        [string]$CandidateName,
        [string]$QueryLeaf,
        [string]$QueryBase
    )

    if ([string]::IsNullOrWhiteSpace($CandidateName)) { return $false }

    $candidateLeaf = [IO.Path]::GetFileName($CandidateName)
    if ([string]::IsNullOrWhiteSpace($candidateLeaf)) {
        $candidateLeaf = $CandidateName
    }
    $candidateBase = [IO.Path]::GetFileNameWithoutExtension($candidateLeaf)
    if ([string]::IsNullOrWhiteSpace($candidateBase)) {
        $candidateBase = $candidateLeaf
    }

    $candidateValues = @(
        $candidateLeaf
        $candidateBase
        ($candidateBase -replace '\s+', '')
        ($candidateBase -replace '[^A-Za-z0-9]+', '')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $queryValues = @(
        $QueryLeaf
        $QueryBase
        ($QueryBase -replace '\s+', '')
        ($QueryBase -replace '[^A-Za-z0-9]+', '')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidateValue in $candidateValues) {
        foreach ($queryValue in $queryValues) {
            if ($candidateValue.Equals($queryValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    }

    return $false
}

function Test-StartupRejectedTarget {
    param([string]$Path)

    $leaf = [IO.Path]::GetFileName($Path)
    if ([string]::IsNullOrWhiteSpace($leaf)) { return $true }

    return ($leaf -match '(?i)^(unins|uninstall|setup|installer|update|updater).*\.exe$')
}

function Add-StartupResolvedTarget {
    param(
        [System.Collections.Generic.List[string]]$Targets,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $candidatePath = [Environment]::ExpandEnvironmentVariables($Path).Trim()
    if ($candidatePath -match '^"([^"]+)"') {
        $candidatePath = $matches[1]
    } elseif (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf) -and $candidatePath -match '^(.*?\.(exe|com|bat|cmd|ps1|vbs|lnk|appref-ms))\b') {
        $candidatePath = $matches[1]
    }

    if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { return }
    if (Test-StartupRejectedTarget -Path $candidatePath) { return }

    $resolved = (Resolve-Path -LiteralPath $candidatePath).ProviderPath
    foreach ($existing in @($Targets)) {
        if ($existing.Equals($resolved, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }

    [void]$Targets.Add($resolved)
}

function Get-StartupResolvedTargetScore {
    param(
        [string]$Path,
        [string]$QueryLeaf,
        [string]$QueryBase
    )

    $score = 0
    $leaf = [IO.Path]::GetFileName($Path)
    $base = [IO.Path]::GetFileNameWithoutExtension($leaf)
    $extension = [IO.Path]::GetExtension($leaf)
    if ($extension -ieq '.exe') { $score += 1000 }
    elseif ($extension -in @('.cmd', '.bat', '.com', '.ps1', '.vbs', '.lnk', '.appref-ms')) { $score += 100 }

    if ($leaf.Equals("$QueryBase.exe", [System.StringComparison]::OrdinalIgnoreCase)) { $score += 700 }
    elseif ($base.Equals($QueryBase, [System.StringComparison]::OrdinalIgnoreCase)) { $score += 500 }
    elseif ($base -like "$QueryBase*") { $score += 150 }

    if ($Path -match '(?i)\\Program Files( \(x86\))?\\') { $score += 300 }
    if ($Path -match '(?i)\\AppData\\Local\\Programs\\') { $score += 220 }
    if ($Path -match '(?i)\\WindowsApps\\') { $score += 160 }
    if ($Path -match '(?i)\\bin\\') { $score -= 250 }
    if ($Path -match '(?i)\\(setup|installer|update|updater|uninstall)\\') { $score -= 500 }
    if ($Path -match '(?i)\\(node_modules|\.git|Temp|tmp|cache|logs?)\\') { $score -= 300 }
    return $score
}

function Select-BestStartupResolvedTarget {
    param(
        [string[]]$Matches,
        [string]$QueryLeaf,
        [string]$QueryBase
    )

    $ranked = @(
        foreach ($match in @($Matches | Where-Object { $_ } | Sort-Object -Unique)) {
            [pscustomobject]@{
                Path = $match
                Score = Get-StartupResolvedTargetScore -Path $match -QueryLeaf $QueryLeaf -QueryBase $QueryBase
            }
        }
    ) | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Path'; Descending = $false }

    if (@($ranked).Count -eq 0) { return $null }
    return [string]$ranked[0].Path
}

function Add-StartupCommonInstallRootTargets {
    param(
        [System.Collections.Generic.List[string]]$Targets,
        [string]$QueryLeaf,
        [string]$QueryBase
    )

    $localPrograms = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs' } else { $null }
    $rootCandidates = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $localPrograms,
        $env:LOCALAPPDATA,
        $env:APPDATA,
        'F:\backup\windowsapps\installed'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) } | Sort-Object -Unique

    $scanWatch = [Diagnostics.Stopwatch]::StartNew()
    foreach ($root in $rootCandidates) {
        if ($scanWatch.Elapsed.TotalSeconds -ge 12) { break }
        foreach ($pattern in @("$QueryBase.exe", "$QueryBase*.exe")) {
            if ($scanWatch.Elapsed.TotalSeconds -ge 12) { break }
            Get-ChildItem -LiteralPath $root -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                $file = $_
                Add-StartupResolvedTarget -Targets $Targets -Path $file.FullName
                if ($scanWatch.Elapsed.TotalSeconds -ge 12) { break }
            }
        }
    }
}

function Find-StartupExecutableOnLocalDrives {
    param(
        [string]$QueryLeaf,
        [string]$QueryBase
    )

    $driveRoots = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object { $_.Root -and (Test-Path -LiteralPath $_.Root) } |
        ForEach-Object { [string]$_.Root } |
        Sort-Object -Unique)
    if (@($driveRoots).Count -eq 0) { return @() }

    $patterns = @("$QueryBase.exe", "$QueryBase*.exe") | Sort-Object -Unique
    $job = $null
    try {
        $job = Start-Job -ScriptBlock {
            param([string[]]$Roots, [string[]]$SearchPatterns)

            $results = New-Object 'System.Collections.Generic.List[string]'
            foreach ($root in $Roots) {
                foreach ($pattern in $SearchPatterns) {
                    try {
                        Get-ChildItem -LiteralPath $root -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue |
                            Where-Object { $_.FullName -notmatch '(?i)\\(node_modules|\.git|Temp|tmp|cache|logs?|Windows\\WinSxS|System Volume Information|\$Recycle\.Bin)\\' } |
                            Select-Object -First 50 -ExpandProperty FullName |
                            ForEach-Object {
                                if (-not [string]::IsNullOrWhiteSpace($_) -and -not $results.Contains($_)) {
                                    [void]$results.Add($_)
                                }
                            }
                    } catch {
                        continue
                    }
                }
            }
            @($results | Sort-Object -Unique)
        } -ArgumentList (,$driveRoots), (,$patterns)

        [void](Wait-Job -Job $job -Timeout 12)
        if ($job.State -eq 'Completed') {
            return @(Receive-Job -Job $job -ErrorAction SilentlyContinue | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf)
            } | Sort-Object -Unique)
        }
    } catch {
        return @()
    } finally {
        if ($job) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }
    @()
}

function Add-StartupAppPathTargets {
    param(
        [System.Collections.Generic.List[string]]$Targets,
        [string]$QueryLeaf,
        [string]$QueryBase
    )

    $registryRoots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths'
    )

    foreach ($root in $registryRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            if (-not (Test-StartupNameMatch -CandidateName $key.PSChildName -QueryLeaf $QueryLeaf -QueryBase $QueryBase)) {
                continue
            }

            $registryKey = Get-Item -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            if (-not $registryKey) { continue }
            Add-StartupResolvedTarget -Targets $Targets -Path ([string]$registryKey.GetValue(''))
        }
    }
}

function Add-StartupCommandTargets {
    param(
        [System.Collections.Generic.List[string]]$Targets,
        [string]$Candidate,
        [string]$QueryLeaf,
        [string]$QueryBase
    )

    $commandQueries = @(
        $Candidate
        $QueryLeaf
        $QueryBase
        "$QueryBase.exe"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique

    foreach ($commandQuery in $commandQueries) {
        foreach ($command in @(Get-Command $commandQuery -CommandType Application -ErrorAction SilentlyContinue)) {
            Add-StartupResolvedTarget -Targets $Targets -Path $command.Source
        }
    }
}

function Add-StartupStartMenuShortcutTargets {
    param(
        [System.Collections.Generic.List[string]]$Targets,
        [string]$QueryLeaf,
        [string]$QueryBase
    )

    $userPrograms = [Environment]::GetFolderPath([System.Environment+SpecialFolder]::Programs)
    if ([string]::IsNullOrWhiteSpace($userPrograms)) {
        $applicationData = [Environment]::GetFolderPath([System.Environment+SpecialFolder]::ApplicationData)
        if (-not [string]::IsNullOrWhiteSpace($applicationData)) {
            $userPrograms = Join-Path $applicationData 'Microsoft\Windows\Start Menu\Programs'
        }
    }

    $commonPrograms = [Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonPrograms)
    if ([string]::IsNullOrWhiteSpace($commonPrograms)) {
        $programData = [Environment]::GetEnvironmentVariable('ProgramData', 'Machine')
        if ([string]::IsNullOrWhiteSpace($programData)) { $programData = 'C:\ProgramData' }
        $commonPrograms = Join-Path $programData 'Microsoft\Windows\Start Menu\Programs'
    }

    $startMenuRoots = @($userPrograms, $commonPrograms) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique

    $shell = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        foreach ($root in $startMenuRoots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            foreach ($shortcutFile in @(Get-ChildItem -LiteralPath $root -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue)) {
                if ($shortcutFile.BaseName -match '(?i)^(uninstall|remove|setup|installer|update|updater)\b') {
                    continue
                }

                $shortcut = $shell.CreateShortcut($shortcutFile.FullName)
                $targetPath = [string]$shortcut.TargetPath
                if ([string]::IsNullOrWhiteSpace($targetPath)) { continue }
                if (Test-StartupRejectedTarget -Path $targetPath) { continue }

                $shortcutMatches = Test-StartupNameMatch -CandidateName $shortcutFile.BaseName -QueryLeaf $QueryLeaf -QueryBase $QueryBase
                $targetMatches = Test-StartupNameMatch -CandidateName $targetPath -QueryLeaf $QueryLeaf -QueryBase $QueryBase
                if ($shortcutMatches -or $targetMatches) {
                    Add-StartupResolvedTarget -Targets $Targets -Path $targetPath
                }
            }
        }
    } finally {
        if ($shell -and [System.Runtime.InteropServices.Marshal]::IsComObject($shell)) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        }
    }
}

function Add-StartupPackagedExeTargets {
    param(
        [System.Collections.Generic.List[string]]$Targets,
        [string]$QueryLeaf,
        [string]$QueryBase
    )

    foreach ($package in @(Get-AppxPackage | Where-Object { $_.InstallLocation -and (Test-Path -LiteralPath $_.InstallLocation) })) {
        foreach ($file in @(Get-ChildItem -LiteralPath $package.InstallLocation -Filter '*.exe' -File -Recurse -ErrorAction SilentlyContinue)) {
            if (
                (Test-StartupNameMatch -CandidateName $file.Name -QueryLeaf $QueryLeaf -QueryBase $QueryBase) -or
                (Test-StartupNameMatch -CandidateName $file.FullName -QueryLeaf $QueryLeaf -QueryBase $QueryBase)
            ) {
                Add-StartupResolvedTarget -Targets $Targets -Path $file.FullName
            }
        }
    }
}

function Resolve-StartupAddTargetPath {
    param([string]$InputValue)

    $candidate = $InputValue.Trim()
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        throw '1start received an empty target.'
    }

    if (Test-Path -LiteralPath $candidate) {
        return (Resolve-Path -LiteralPath $candidate).ProviderPath
    }

    $queryLeaf = [IO.Path]::GetFileName($candidate)
    if ([string]::IsNullOrWhiteSpace($queryLeaf)) {
        $queryLeaf = $candidate
    }
    $queryBase = [IO.Path]::GetFileNameWithoutExtension($queryLeaf)
    if ([string]::IsNullOrWhiteSpace($queryBase)) {
        $queryBase = $queryLeaf
    }

    $matches = New-Object 'System.Collections.Generic.List[string]'
    Add-StartupCommandTargets -Targets $matches -Candidate $candidate -QueryLeaf $queryLeaf -QueryBase $queryBase
    Add-StartupAppPathTargets -Targets $matches -QueryLeaf $queryLeaf -QueryBase $queryBase
    Add-StartupStartMenuShortcutTargets -Targets $matches -QueryLeaf $queryLeaf -QueryBase $queryBase
    Add-StartupPackagedExeTargets -Targets $matches -QueryLeaf $queryLeaf -QueryBase $queryBase

    $matches = @($matches | Sort-Object -Unique)

    if ($matches.Count -gt 0) {
        return (Select-BestStartupResolvedTarget -Matches $matches -QueryLeaf $queryLeaf -QueryBase $queryBase)
    }

    Add-StartupCommonInstallRootTargets -Targets $matches -QueryLeaf $queryLeaf -QueryBase $queryBase
    $matches = @($matches | Sort-Object -Unique)
    if ($matches.Count -gt 0) {
        return (Select-BestStartupResolvedTarget -Matches $matches -QueryLeaf $queryLeaf -QueryBase $queryBase)
    }

    $driveMatches = @(Find-StartupExecutableOnLocalDrives -QueryLeaf $queryLeaf -QueryBase $queryBase)
    if ($driveMatches.Count -gt 0) {
        return (Select-BestStartupResolvedTarget -Matches $driveMatches -QueryLeaf $queryLeaf -QueryBase $queryBase)
    }

    throw "1start could not resolve an installed app or file from: $InputValue"
}

function Resolve-QuietStartupEntry {
    param([string]$ResolvedTargetPath)

    $nativeStartupTask = Get-AppStartupTaskForTargetPath -TargetPath $ResolvedTargetPath

    $entry = [ordered]@{
        Name = Get-StartupTaskNameFromPath -TargetPath $ResolvedTargetPath
        TargetPath = $ResolvedTargetPath
        Description = "Window-suppressed startup target: $ResolvedTargetPath"
    }
    if ($nativeStartupTask) {
        $entry.PackageFamilyName = $nativeStartupTask.PackageFamilyName
        $entry.TaskId = $nativeStartupTask.TaskId
    }

    return $entry
}

function Resolve-NativeAppStartupTargetInfo {
    param([string]$InputValue)

    $candidate = ([string]$InputValue).Trim()
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return $null
    }

    $candidatePaths = @()
    if ($candidate -match '^[A-Za-z]:\\') {
        $candidatePaths += $candidate
    }

    if ($candidate -match '^[A-Za-z]:\\') {
        try {
            $resolvedPath = Resolve-StartupAddTargetPath -InputValue $candidate
            if ($resolvedPath) {
                $candidatePaths += $resolvedPath
            }
        } catch {
        }
    }

    $candidatePaths = @($candidatePaths | Where-Object { $_ } | Sort-Object -Unique)
    foreach ($path in $candidatePaths) {
        $nativeStartupTask = Get-AppStartupTaskForTargetPath -TargetPath $path
        if (-not $nativeStartupTask) { continue }
        return [pscustomobject]@{
            TargetPath = $path
            PackageFamilyName = [string]$nativeStartupTask.PackageFamilyName
            TaskId = [string]$nativeStartupTask.TaskId
            State = [int]$nativeStartupTask.State
        }
    }

    return $null
}

function Invoke-StartupApply {
    param([object[]]$Targets)

    foreach ($target in @($Targets)) {
        $entryPoint = if ($target.Name -eq 'allstart') {
            Join-Path $target.Directory 'Invoke-allstart.ps1'
        } else {
            Join-Path $target.Directory 'Invoke-allstart2.ps1'
        }
        & $script:WindowsPowerShellExe -NoProfile -ExecutionPolicy Bypass -File $entryPoint -Mode Startup
        if ($LASTEXITCODE -ne 0) {
            throw "Startup apply failed for $($target.Name): $entryPoint"
        }
    }
}

function Test-AppStartupTaskEnabled {
    param(
        [string]$PackageFamilyName,
        [string]$TaskId
    )

    $statePath = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$PackageFamilyName\$TaskId"
    try {
        $state = (Get-ItemProperty -LiteralPath $statePath -Name State -ErrorAction Stop).State
        return ($state -in @(2, 4))
    } catch {
        return $false
    }
}

function Test-AppStartupTaskDisabled {
    param(
        [string]$PackageFamilyName,
        [string]$TaskId
    )

    $statePath = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$PackageFamilyName\$TaskId"
    try {
        $state = (Get-ItemProperty -LiteralPath $statePath -Name State -ErrorAction Stop).State
        return ($state -notin @(2, 4))
    } catch {
        return $true
    }
}

function Test-ScheduledTaskEnabled {
    param([string]$TaskName)

    $output = & cmd.exe /d /c "schtasks.exe /query /tn ""$($TaskName.Replace('"', '""'))"" /fo list 2>nul"
    if ($LASTEXITCODE -ne 0 -or -not $output) { return $false }
    $stateLine = @($output | Where-Object { $_ -match '^Scheduled Task State:' }) | Select-Object -First 1
    if (-not $stateLine) { return $true }
    return ($stateLine -notmatch 'Disabled')
}

function Assert-BuiltInStartupEntriesActivated {
    param([object[]]$Entries)

    foreach ($entry in @($Entries)) {
        $taskName = [string]$entry.Key
        $expectedExecute = [string]$entry.Execute
        $expectedArguments = [string]$entry.Arguments
        $requiredLauncherPath = [string]$entry.RequiredLauncherPath

        if ($requiredLauncherPath -and -not (Test-Path -LiteralPath $requiredLauncherPath)) {
            throw "Built-in startup launcher is missing for $taskName`: $requiredLauncherPath"
        }

        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $task) {
            throw "Built-in startup task was not created: $taskName"
        }
        if ($task.State -eq 'Disabled') {
            throw "Built-in startup task is disabled: $taskName"
        }

        $actions = @($task.Actions)
        if ($actions.Count -ne 1) {
            throw "Built-in startup task has unexpected action count for $taskName`: $($actions.Count)"
        }

        $actualExecute = [string]$actions[0].Execute
        $actualArguments = [string]$actions[0].Arguments
        if (-not $actualExecute.Equals($expectedExecute, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Built-in startup task is not using the hidden launcher for $taskName`: $actualExecute"
        }
        if ($actualArguments.Trim() -ne $expectedArguments.Trim()) {
            throw "Built-in startup task has unexpected launcher arguments for $taskName`: $actualArguments"
        }
    }
}

function Assert-StartupEntriesActivated {
    param([object[]]$Entries)

    foreach ($entry in @($Entries)) {
        $entryType = Get-StartupCustomField -Entry $entry -Name 'EntryType'
        if ($entryType -eq 'AppStartupTask') {
            $packageFamilyName = [string](Get-StartupCustomField -Entry $entry -Name 'PackageFamilyName')
            $taskId = [string](Get-StartupCustomField -Entry $entry -Name 'TaskId')
            if (-not (Test-AppStartupTaskEnabled -PackageFamilyName $packageFamilyName -TaskId $taskId)) {
                throw "App startup task was not enabled: $packageFamilyName / $taskId"
            }
            continue
        }
        $taskName = [string](Get-StartupCustomField -Entry $entry -Name 'Name')
        if (-not (Test-ScheduledTaskEnabled -TaskName $taskName)) {
            throw "Scheduled task was not enabled: $taskName"
        }
        $packageFamilyName = [string](Get-StartupCustomField -Entry $entry -Name 'PackageFamilyName')
        $taskId = [string](Get-StartupCustomField -Entry $entry -Name 'TaskId')
        if ($packageFamilyName -and $taskId -and -not (Test-AppStartupTaskDisabled -PackageFamilyName $packageFamilyName -TaskId $taskId)) {
            throw "Native app startup task is still enabled and can pop a GUI: $packageFamilyName / $taskId"
        }
    }
}

function Save-StartupCustomEntries {
    param(
        [string]$Path,
        [object[]]$Entries,
        [string[]]$DisabledBuiltIns = @()
    )

    $content = ConvertTo-StartupCustomConfigText -Entries $Entries -DisabledBuiltIns $DisabledBuiltIns
    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Find-BuiltInStartupCatalogMatch {
    param([string]$Query)

    $queryTrimmed = $Query.Trim()
    $queryLower = $queryTrimmed.ToLowerInvariant()
    $queryLeaf = [IO.Path]::GetFileName($queryLower)
    $queryBase = [IO.Path]::GetFileNameWithoutExtension($queryLeaf)

    $matches = @(
        foreach ($entry in @($builtInStartupCatalog)) {
            $entryPath = [string]$entry.TargetPath
            $entryLeaf = [IO.Path]::GetFileName($entryPath).ToLowerInvariant()
            $entryBase = [IO.Path]::GetFileNameWithoutExtension($entryPath).ToLowerInvariant()
            $matched = $false
            foreach ($alias in @($entry.Aliases)) {
                if ([string]::IsNullOrWhiteSpace($alias)) { continue }
                if ($alias.ToLowerInvariant() -eq $queryLower) { $matched = $true; break }
            }
            if (-not $matched -and $entryPath.ToLowerInvariant() -eq $queryLower) { $matched = $true }
            if (-not $matched -and $entryLeaf -eq $queryLeaf) { $matched = $true }
            if (-not $matched -and $entryBase -eq $queryBase) { $matched = $true }
            if ($matched) { $entry }
        }
    )

    if ($matches.Count -gt 1) {
        throw "Built-in startup app match is ambiguous: $Query"
    }
    if ($matches.Count -eq 1) {
        return $matches[0]
    }
    return $null
}

function Get-StartupCustomEntryKey {
    param([object]$Entry)

    $name = [string](Get-StartupCustomField -Entry $Entry -Name 'Name')
    $targetPath = [string](Get-StartupCustomField -Entry $Entry -Name 'TargetPath')
    return "$($name.ToLowerInvariant())`n$($targetPath.ToLowerInvariant())"
}

function Find-MatchingStartupCustomEntries {
    param(
        [object[]]$Entries,
        [string]$Query,
        [object]$NativeAppTargetInfo
    )

    $queryLower = $Query.Trim().ToLowerInvariant()
    $queryLeaf = [IO.Path]::GetFileName($queryLower)
    $queryBase = [IO.Path]::GetFileNameWithoutExtension($queryLower)

    @(
        foreach ($entry in @($Entries)) {
            $targetPath = [string]$entry.TargetPath
            $name = [string]$entry.Name
            $leaf = [IO.Path]::GetFileName($targetPath)
            $base = [IO.Path]::GetFileNameWithoutExtension($targetPath)

            if (
                $targetPath.ToLowerInvariant() -eq $queryLower -or
                $name.ToLowerInvariant() -eq $queryLower -or
                $leaf.ToLowerInvariant() -eq $queryLeaf -or
                $base.ToLowerInvariant() -eq $queryBase -or
                $base.ToLowerInvariant() -eq $queryLower
            ) {
                $entry
                continue
            }

            if ($NativeAppTargetInfo) {
                $entryType = [string](Get-StartupCustomField -Entry $entry -Name 'EntryType')
                $packageFamilyName = [string](Get-StartupCustomField -Entry $entry -Name 'PackageFamilyName')
                $taskId = [string](Get-StartupCustomField -Entry $entry -Name 'TaskId')
                if (
                    $entryType -eq 'AppStartupTask' -and
                    $packageFamilyName.Equals([string]$NativeAppTargetInfo.PackageFamilyName, [System.StringComparison]::OrdinalIgnoreCase) -and
                    $taskId.Equals([string]$NativeAppTargetInfo.TaskId, [System.StringComparison]::OrdinalIgnoreCase)
                ) {
                    $entry
                }
            }
        }
    )
}

function Find-MatchingStartupScheduledTasks {
    param([string[]]$Queries)

    $queriesNormalized = @(
        foreach ($query in @($Queries)) {
            $trimmed = ([string]$query).Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) { $trimmed }
        }
    )
    if ($queriesNormalized.Count -eq 0) { return @() }

    try {
        $tasks = @(Get-ScheduledTask -TaskName 'CustomStartup_*' -ErrorAction SilentlyContinue)
    } catch {
        return @()
    }

    @(
        foreach ($task in $tasks) {
            $actionText = (@($task.Actions | ForEach-Object { (($_.Execute, $_.Arguments) -join ' ').Trim() }) -join ' ')
            foreach ($query in $queriesNormalized) {
                $queryLeaf = [IO.Path]::GetFileName($query)
                if ([string]::IsNullOrWhiteSpace($queryLeaf)) { $queryLeaf = $query }
                $queryBase = [IO.Path]::GetFileNameWithoutExtension($queryLeaf)
                if ([string]::IsNullOrWhiteSpace($queryBase)) { $queryBase = $queryLeaf }
                if (
                    (Test-StartupNameMatch -CandidateName $task.TaskName -QueryLeaf $queryLeaf -QueryBase $queryBase) -or
                    ($actionText -match [regex]::Escape($query)) -or
                    ($actionText -match [regex]::Escape($queryBase))
                ) {
                    [pscustomobject]@{
                        TaskName = [string]$task.TaskName
                        Query = [string]$query
                        State = [string]$task.State
                    }
                    break
                }
            }
        }
    ) | Sort-Object TaskName -Unique
}

function Disable-MatchingStartupScheduledTasks {
    param([object[]]$Tasks)

    foreach ($task in @($Tasks)) {
        $taskName = [string]$task.TaskName
        if ([string]::IsNullOrWhiteSpace($taskName)) { continue }
        $scheduledTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $scheduledTask) { continue }
        if ($scheduledTask.State -eq 'Disabled') { continue }
        & schtasks.exe /change /tn $taskName /DISABLE | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to disable stale custom startup task: $taskName"
        }
        $after = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($after -and $after.State -ne 'Disabled') {
            throw "Stale custom startup task did not disable cleanly: $taskName"
        }
    }
}

function Invoke-StartupCustomValidation {
    param([object[]]$Targets)

    foreach ($target in @($Targets)) {
        & $script:WindowsPowerShellExe -NoProfile -ExecutionPolicy Bypass -File $target.TestPath
        if ($LASTEXITCODE -ne 0) {
            throw "Validation failed for $($target.Name): $($target.TestPath)"
        }
    }
}

foreach ($target in @($targets)) {
    if (-not (Test-Path -LiteralPath $target.CustomConfigPath)) {
        Save-StartupCustomEntries -Path $target.CustomConfigPath -Entries @() -DisabledBuiltIns @()
    }
}

$requestedValues = @(
    foreach ($item in @($Value)) {
        $trimmed = [string]$item
        if ($null -eq $trimmed) { continue }
        $trimmed = $trimmed.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        $trimmed
    }
)
if ($requestedValues.Count -eq 0) {
    throw 'At least one startup target is required.'
}

$originalConfigs = @{}
foreach ($target in @($targets)) {
    $originalConfigs[$target.CustomConfigPath] = if (Test-Path -LiteralPath $target.CustomConfigPath) {
        Get-Content -LiteralPath $target.CustomConfigPath -Raw
    } else {
        $null
    }
}

try {
    Update-StartupCustomConfigsToCurrentTargets -Targets $targets -NoWrite:$NoApply
    $builtInEntriesToEnable = @()
    $entriesToAdd = @()
    $resolvedTargets = @()
    switch ($Action) {
        'Add' {
            $customResolvedTargets = @()
            $unresolvedTargets = @()
            foreach ($item in $requestedValues) {
                $builtInMatch = Find-BuiltInStartupCatalogMatch -Query $item
                if ($builtInMatch) {
                    $builtInEntriesToEnable += $builtInMatch
                    continue
                }
                try {
                    $customResolvedTargets += (Resolve-StartupAddTargetPath -InputValue $item)
                } catch {
                    $unresolvedTargets += $item
                    Write-Host "No startup target found for '$item'; no entry was added for that value."
                }
            }
            $builtInEntriesToEnable = @($builtInEntriesToEnable | Sort-Object Key -Unique)
            $resolvedTargets = @($customResolvedTargets | Sort-Object -Unique)
            if ($resolvedTargets.Count -eq 0 -and $builtInEntriesToEnable.Count -eq 0) {
                Write-Host "No startup target(s) were resolved; startup configuration is unchanged."
                return
            }
            $entriesToAdd = @(
                foreach ($resolvedTarget in $resolvedTargets) {
                    Resolve-QuietStartupEntry -ResolvedTargetPath $resolvedTarget
                }
            )
            $builtInKeysToEnable = @($builtInEntriesToEnable | ForEach-Object { [string]$_.Key } | Where-Object { $_ })
            $entryNamesToAdd = @($entriesToAdd | ForEach-Object { [string]$_.Name } | Where-Object { $_ })

            foreach ($target in @($targets)) {
                $disabledBuiltIns = @(Get-StartupDisabledBuiltIns -Path $target.CustomConfigPath)
                $entries = @(
                    Get-StartupCustomEntries -Path $target.CustomConfigPath |
                        Where-Object {
                            $existingPath = [string](Get-StartupCustomField -Entry $_ -Name 'TargetPath')
                            $existingName = [string](Get-StartupCustomField -Entry $_ -Name 'Name')
                            -not ($resolvedTargets | Where-Object { $existingPath.Equals($_, [System.StringComparison]::OrdinalIgnoreCase) }) -and
                            -not ($entryNamesToAdd | Where-Object { $existingName.Equals($_, [System.StringComparison]::OrdinalIgnoreCase) })
                        }
                )
                $entries += $entriesToAdd
                $remainingDisabledBuiltIns = @(
                    foreach ($name in $disabledBuiltIns) {
                        if ($builtInKeysToEnable -contains $name) { continue }
                        $name
                    }
                ) | Sort-Object -Unique
                if (-not $NoApply) {
                    Save-StartupCustomEntries -Path $target.CustomConfigPath -Entries $entries -DisabledBuiltIns $remainingDisabledBuiltIns
                }
            }
        }
        'Remove' {
            $totalRemoved = 0
            $nativeAppTargetsToDisable = @()
            $scheduledTasksToDisable = @(Find-MatchingStartupScheduledTasks -Queries $requestedValues)
            $builtInEntriesToDisable = @(
                foreach ($query in $requestedValues) {
                    $builtInMatch = Find-BuiltInStartupCatalogMatch -Query $query
                    if ($builtInMatch) { $builtInMatch }
                }
            )
            $builtInEntriesToDisable = @($builtInEntriesToDisable | Sort-Object Key -Unique)
            $builtInKeysToDisable = @($builtInEntriesToDisable | ForEach-Object { [string]$_.Key } | Where-Object { $_ })
            foreach ($query in $requestedValues) {
                $nativeAppTarget = Resolve-NativeAppStartupTargetInfo -InputValue $query
                if ($nativeAppTarget) {
                    $nativeAppTargetsToDisable += $nativeAppTarget
                }
            }
            $nativeAppTargetsToDisable = @(
                $nativeAppTargetsToDisable |
                    Sort-Object PackageFamilyName, TaskId -Unique
            )
            foreach ($target in @($targets)) {
                $entries = @(Get-StartupCustomEntries -Path $target.CustomConfigPath)
                $disabledBuiltIns = @(Get-StartupDisabledBuiltIns -Path $target.CustomConfigPath)
                $matches = @(
                    foreach ($query in $requestedValues) {
                        $nativeAppTarget = Resolve-NativeAppStartupTargetInfo -InputValue $query
                        Find-MatchingStartupCustomEntries -Entries $entries -Query $query -NativeAppTargetInfo $nativeAppTarget
                    }
                )
                $matchKeys = @($matches | ForEach-Object { Get-StartupCustomEntryKey -Entry $_ } | Sort-Object -Unique)
                $totalRemoved += $matches.Count
                $keepers = @(
                    foreach ($entry in $entries) {
                        if ((Get-StartupCustomEntryKey -Entry $entry) -notin $matchKeys) { $entry }
                    }
                )
                $updatedDisabledBuiltIns = @(
                    @($disabledBuiltIns)
                    @($builtInKeysToDisable)
                ) | Where-Object { $_ } | Sort-Object -Unique
                if (-not $NoApply) {
                    Save-StartupCustomEntries -Path $target.CustomConfigPath -Entries $keepers -DisabledBuiltIns $updatedDisabledBuiltIns
                }
            }
            $totalRemoved += $nativeAppTargetsToDisable.Count
            $totalRemoved += $scheduledTasksToDisable.Count
            $noRemoveMatches = ($totalRemoved -eq 0 -and $builtInEntriesToDisable.Count -eq 0)
        }
    }

    if ($NoApply) {
        Write-Host 'Resolve-only: no startup configuration changed, no scheduled tasks changed, and no apps launched.'
        switch ($Action) {
            'Add' {
                $previewTargets = @($resolvedTargets)
                $previewTargets += @($builtInEntriesToEnable | ForEach-Object { $_.TargetPath })
                Write-Host "Would add startup target(s) to allstart and allstart2: $($previewTargets -join '; ')"
                foreach ($entry in @($entriesToAdd)) {
                    Write-Host "Startup mode: WindowSuppressedScheduledTask $($entry.Name)"
                }
                foreach ($entry in @($builtInEntriesToEnable)) {
                    Write-Host "Built-in startup would be restored: $($entry.Key)"
                }
            }
            'Remove' {
                Write-Host "Would remove matching startup target(s) from allstart and allstart2: $($requestedValues -join '; ')"
                if ($noRemoveMatches) {
                    Write-Host 'No current matching startup entries found; removal is already satisfied.'
                }
                foreach ($entry in @($builtInEntriesToDisable)) {
                    Write-Host "Built-in startup would be disabled: $($entry.Key)"
                }
            }
        }
        return
    }

    if ($Action -eq 'Remove' -and $noRemoveMatches) {
        Write-Host "Removed matching custom startup target(s) from allstart and allstart2: $($requestedValues -join '; ')"
        Write-Host 'No current matching startup entries were active; removal was already satisfied.'
        return
    }

    Invoke-StartupCustomValidation -Targets $targets
    Invoke-StartupApply -Targets $targets
    if ($Action -eq 'Remove') {
        Disable-MatchingStartupScheduledTasks -Tasks $scheduledTasksToDisable
    }
    $allEntries = @($targets | ForEach-Object { Get-StartupCustomEntries -Path $_.CustomConfigPath })
    Assert-StartupEntriesActivated -Entries $allEntries
    Assert-BuiltInStartupEntriesActivated -Entries $builtInEntriesToEnable

    switch ($Action) {
        'Add' {
            $addedTargets = @($resolvedTargets)
            $addedTargets += @($builtInEntriesToEnable | ForEach-Object { $_.TargetPath })
            Write-Host "Added startup target(s) to allstart and allstart2: $($addedTargets -join '; ')"
            foreach ($entry in @($entriesToAdd)) {
                if ((Get-StartupCustomField -Entry $entry -Name 'EntryType') -eq 'AppStartupTask') {
                    Write-Host "Startup mode: AppStartupTask $($entry.PackageFamilyName) / $($entry.TaskId)"
                } else {
                    Write-Host "Startup mode: WindowSuppressedScheduledTask $($entry.Name)"
                }
            }
            foreach ($entry in @($builtInEntriesToEnable)) {
                Write-Host "Built-in startup restored: $($entry.Key)"
            }
        }
        'Remove' {
            Write-Host "Removed matching custom startup target(s) from allstart and allstart2: $($requestedValues -join '; ')"
            if ($noRemoveMatches) {
                Write-Host 'No current matching startup entries were active; removal was already satisfied.'
            }
            foreach ($entry in @($builtInEntriesToDisable)) {
                Write-Host "Built-in startup disabled: $($entry.Key)"
            }
        }
    }
} catch {
    foreach ($target in @($targets)) {
        $original = $originalConfigs[$target.CustomConfigPath]
        if ($null -eq $original) {
            Remove-Item -LiteralPath $target.CustomConfigPath -Force -ErrorAction SilentlyContinue
        } else {
            Set-Content -LiteralPath $target.CustomConfigPath -Value $original -Encoding UTF8
        }
    }
    throw
}
