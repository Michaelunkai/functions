[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][string]$PathOrFolder,
    [string]$Launcher
)

$ErrorActionPreference = 'Stop'
$functionRoot = 'F:\study\Platforms\windows\functions'
$installRoot = 'F:\backup\windowsapps\installed'
$catalogPath = Join-Path $functionRoot 'InstalledAppRestoreCatalog.json'
$restoreHelper = Join-Path $functionRoot 'Invoke-InstalledAppDockerRestoreAndLaunch.ps1'
$uploader = Join-Path $functionRoot 'Push-DockerImageChunked.ps1'
$ledger = Join-Path $functionRoot 'installed-app-docker-publish.jsonl'
$tar = Join-Path $env:SystemRoot 'System32\tar.exe'
$importRoot = 'F:\backup\windowsapps\.docker-import'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe'
    if (-not (Test-Path -LiteralPath $pwsh -PathType Leaf)) { throw 'PowerShell 7 is required for reliable large uploads.' }
    $arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-PathOrFolder', $PathOrFolder)
    if ($Launcher) { $arguments += @('-Launcher', $Launcher) }
    & $pwsh @arguments
    if ($LASTEXITCODE -ne 0) { throw "gapp failed with exit $LASTEXITCODE." }
    return
}

$candidate = if (Test-Path -LiteralPath $PathOrFolder -PathType Container) {
    $PathOrFolder
} else {
    Join-Path $installRoot $PathOrFolder
}
if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { throw "Folder not found: $PathOrFolder" }
$source = (Get-Item -LiteralPath $candidate -Force).FullName.TrimEnd('\')
$folder = [IO.Path]::GetFileName($source)
$sourceRoot = [IO.Path]::GetPathRoot($source).TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($folder) -or $source -eq $sourceRoot) { throw "Unsafe app folder: $source" }

$slug = ($folder.ToLowerInvariant() -replace '[^a-z0-9._-]+', '-' -replace '^-+|-+$', '')
if ([string]::IsNullOrWhiteSpace($slug)) { throw "Could not derive a Docker repository name from: $folder" }
$repository = "michadockermisha/$slug"
$existingEntries = if (Test-Path -LiteralPath $catalogPath -PathType Leaf) { @(Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json) } else { @() }
$conflict = @($existingEntries | Where-Object {
    [string]$_.Folder -ieq $folder -and
    -not [string]::IsNullOrWhiteSpace([string]$_.TargetPath) -and
    [IO.Path]::GetFullPath([string]$_.TargetPath).TrimEnd('\') -ne $source
}) | Select-Object -First 1
if ($conflict) {
    throw "Function g$($folder -replace '[^A-Za-z0-9]', '') is already mapped to $($conflict.TargetPath); refusing to silently retarget it to $source."
}

$kind = $null; $relativeLauncher = $null; $processName = $null
if ($Launcher) {
    $launcherPath = if ([IO.Path]::IsPathRooted($Launcher)) { [IO.Path]::GetFullPath($Launcher) } else { Join-Path $source $Launcher }
    if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) { throw "Launcher not found: $launcherPath" }
} else {
    $baseName = [IO.Path]::GetFileNameWithoutExtension($folder)
    $executables = @(Get-ChildItem -LiteralPath $source -File -Filter '*.exe' -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '(?i)unins|uninstall|update|crash|report|service|daemon|helper|setup|install' })
    $launcherPath = $executables | Sort-Object @{Expression={if($_.BaseName -ieq $baseName){0}elseif($_.DirectoryName -eq $source){1}else{2}}}, @{Expression={$_.FullName.Length}} | Select-Object -First 1 -ExpandProperty FullName
    if (-not $launcherPath) {
        $scripts = @(Get-ChildItem -LiteralPath $source -File -Filter '*.ps1' -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^(start|run|open|launch|invoke)' })
        $launcherPath = $scripts | Sort-Object @{Expression={if($_.DirectoryName -eq $source){0}else{1}}}, @{Expression={$_.FullName.Length}} | Select-Object -First 1 -ExpandProperty FullName
    }
}
if ($launcherPath) {
    $relativeLauncher = $launcherPath.Substring($source.Length).TrimStart('\')
    if ([IO.Path]::GetExtension($launcherPath) -ieq '.exe') { $kind = 'Exe'; $processName = [IO.Path]::GetFileName($launcherPath) } else { $kind = 'PowerShellDetached' }
} else {
    $content = Get-ChildItem -LiteralPath $source -File -Recurse -Force | Select-Object -First 1
    if (-not $content) { throw "Folder has no launchable or verifiable content: $source" }
    $kind = 'Content'; $relativeLauncher = $content.FullName.Substring($source.Length).TrimStart('\')
}

$profileModule = 'C:\Users\micha\Documents\WindowsPowerShell\Modules\CodexProfileFunctions\CodexProfileFunctions.psd1'
Import-Module $profileModule -Force -DisableNameChecking
Initialize-CodexProfileFunctions
$latest = $null
try { $latest = [string](Get-BackupDockerLatestRemoteTag -RepoSlug $slug | Select-Object -Last 1) } catch { }
$tag = if ($latest -match '^\d+$') { ([int]$latest + 1).ToString() } else { '1' }
$image = "$repository`:$tag"

$files = @(Get-ChildItem -LiteralPath $source -File -Recurse -Force)
$directories = @(Get-ChildItem -LiteralPath $source -Directory -Recurse -Force)
$bytes = [long](($files | Measure-Object Length -Sum).Sum)
$protected = $folder -in @('reflect', 'CodexMonitor')
New-Item -ItemType Directory -Path $importRoot -Force | Out-Null
$archive = Join-Path $importRoot ("{0}-{1}.tar" -f $slug, [guid]::NewGuid().ToString('N'))
$digest = $null
try {
    $tarArguments = @('-cf', $archive, '-C', (Split-Path -Parent $source), $folder)
    & $tar @tarArguments
    if ($LASTEXITCODE -ne 0) { throw "Could not archive $source" }
    & $tar -tf $archive *> $null
    if ($LASTEXITCODE -ne 0) { throw "Archive validation failed: $archive" }

    $labels = @{
        'backup.source.path' = $source
        'backup.source.repo' = $repository
        'backup.source.tag' = $tag
        'backup.source.bytes' = [string]$bytes
        'backup.source.files' = [string]$files.Count
        'backup.source.directories' = [string]$directories.Count
        'backup.restore.mode' = if ($protected) { 'overlay' } else { 'replace' }
        'backup.payload.directory' = $folder
    }
    $digest = & $uploader -Image $image -LayerArchive $archive -Labels $labels -ChunkMiB 32
    if (-not $digest) { throw "Docker Hub publication failed: $image" }

    $entries = $existingEntries
    $entries = @($entries | Where-Object { [string]$_.Folder -ne $folder })
    $entries += [pscustomobject]@{Folder=$folder;Slug=$slug;TargetPath=$source;Protected=$protected;Kind=$kind;Path=$relativeLauncher;Process=$processName}
    $tempCatalog = $catalogPath + '.tmp'
    [IO.File]::WriteAllText($tempCatalog, ($entries | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tempCatalog -Destination $catalogPath -Force

    $functionName = 'g' + ($folder -replace '[^A-Za-z0-9]', '')
    $scriptPath = Join-Path $functionRoot ($functionName + '.ps1')
    $escapedFolder = $folder.Replace("'", "''")
    $scriptContent = "`$ErrorActionPreference = 'Stop'`r`n& '$restoreHelper' -Folder '$escapedFolder' @args`r`n"
    [IO.File]::WriteAllText($scriptPath, $scriptContent, (New-Object Text.UTF8Encoding($false)))

    $profileDefinition = "function $functionName {`r`n    & '$scriptPath' @args`r`n}"
    $beginMarker = "# BEGIN GAPP FUNCTION $functionName"
    $endMarker = "# END GAPP FUNCTION $functionName"
    $definitionBlock = "$beginMarker`r`n$profileDefinition`r`n$endMarker"
    $definitionPattern = '(?ms)^' + [regex]::Escape($beginMarker) + '.*?^' + [regex]::Escape($endMarker) + '\s*'
    foreach ($profilePath in @(
        'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1',
        'C:\Users\micha\Documents\PowerShell\Microsoft.PowerShell_profile.ps1',
        'C:\Users\micha\Documents\WindowsPowerShell\ProfileSources\ps5-profile-portable\Microsoft.PowerShell_profile.ps1'
    )) {
        $profileText = if (Test-Path -LiteralPath $profilePath -PathType Leaf) { [IO.File]::ReadAllText($profilePath) } else { '' }
        if ([regex]::IsMatch($profileText, $definitionPattern)) {
            $profileText = [regex]::Replace($profileText, $definitionPattern, $definitionBlock + "`r`n")
        } else {
            $profileText = $profileText.TrimEnd() + "`r`n`r`n$definitionBlock`r`n"
        }
        [IO.File]::WriteAllText($profilePath, $profileText, (New-Object Text.UTF8Encoding($false)))
    }

    [pscustomobject]@{Timestamp=(Get-Date).ToString('o');Protected=$protected;Bytes=$bytes;Digest=[string]$digest;Files=$files.Count;Status='PUBLISHED';Image=$image;Folder=$folder} | ConvertTo-Json -Compress | Add-Content -LiteralPath $ledger -Encoding UTF8
    & $restoreHelper -Folder $folder
    Write-Output "GAPP_OK function=$functionName script=$scriptPath image=$image digest=$digest"
} finally {
    if ($digest -and (Test-Path -LiteralPath $archive -PathType Leaf)) { Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue }
}
