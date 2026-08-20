[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Folder,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$installRoot = 'F:\backup\windowsapps\installed'
$profileModule = 'C:\Users\micha\Documents\WindowsPowerShell\Modules\CodexProfileFunctions\CodexProfileFunctions.psd1'

$catalog = @{
    'CodexMonitor' = @{ Slug = 'codexmonitor'; Protected = $true; Kind = 'CodexMonitor' }
    'WhisperKeyLocal' = @{ Slug = 'whisperkeylocal'; Kind = 'PowerShell'; Path = 'Start-WhisperKeyLocal.ps1' }
    'Whisper' = @{ Slug = 'whisper'; Kind = 'Exe'; Path = 'WhisperSTT.exe'; Process = 'WhisperSTT.exe' }
    'tv' = @{ Slug = 'tv'; Kind = 'Exe'; Path = 'tizen\moonlight-setup-guardian\bin\MoonlightSetupGuardian.exe'; Process = 'MoonlightSetupGuardian.exe' }
    'reflect' = @{ Slug = 'reflect'; Protected = $true; Kind = 'Exe'; Path = 'Reflect.exe'; Process = 'Reflect.exe' }
    'FlareSolverr' = @{ Slug = 'flaresolverr'; Kind = 'HttpScript'; Path = 'Start-FlareSolverrPortable.ps1'; Uri = 'http://127.0.0.1:8191/' }
    'Obsidian' = @{ Slug = 'obsidian'; Kind = 'Exe'; Path = 'Obsidian.exe'; Process = 'Obsidian.exe' }
    'telegram' = @{ Slug = 'telegram'; Kind = 'Exe'; Path = 'Telegram.exe'; Process = 'Telegram.exe' }
    'Prowlarr' = @{ Slug = 'prowlarr'; Kind = 'PowerShell'; Path = 'Start-ProwlarrPortable.ps1' }
    'cloudflare' = @{ Slug = 'cloudflare'; Kind = 'Cloudflare' }
    'Jackett' = @{ Slug = 'jackett'; Kind = 'PowerShell'; Path = 'Start-JackettPortable.ps1' }
    'kvrt' = @{ Slug = 'kvrt'; Kind = 'Exe'; Path = 'KVRT.exe'; Process = 'KVRT.exe' }
    'scoop' = @{ Slug = 'scoop'; Kind = 'Command'; Path = 'shims\scoop.cmd'; Arguments = @('--version') }
    'BleachBitAutoClean' = @{ Slug = 'bleachbitautoclean'; Kind = 'PowerShell'; Path = 'Invoke-BleachAutoClean.ps1'; Arguments = @('-SelfTest') }
    'tailscale' = @{ Slug = 'tailscale'; Kind = 'Tailscale' }
    'Process Lasso' = @{ Slug = 'process-lasso'; Kind = 'ProcessLasso' }
    'OpenSpeedy' = @{ Slug = 'openspeedy'; Kind = 'Exe'; Path = 'Speedy.exe'; Process = 'Speedy.exe' }
    'gamesavemanager' = @{ Slug = 'gamesavemanager'; Kind = 'Exe'; Path = 'gs_mngr_3.exe'; Process = 'gs_mngr_3.exe' }
    'adw' = @{ Slug = 'adw'; Kind = 'Exe'; Path = 'AdwCleaner.exe'; Process = 'AdwCleaner.exe' }
    'Everything' = @{ Slug = 'everything'; Kind = 'Everything' }
    'qBittorrentSearchPluginsWiki' = @{ Slug = 'qbittorrentsearchpluginswiki'; Kind = 'Content'; Path = 'Home.md' }
    'qBittorrentSearchPlugins' = @{ Slug = 'qbittorrentsearchplugins'; Kind = 'PluginSync' }
}
$customCatalogPath = Join-Path $PSScriptRoot 'InstalledAppRestoreCatalog.json'
if (Test-Path -LiteralPath $customCatalogPath -PathType Leaf) {
    $customEntries = Get-Content -LiteralPath $customCatalogPath -Raw | ConvertFrom-Json
    foreach ($entry in $customEntries) {
        $custom = @{
            Slug = [string]$entry.Slug
            Kind = [string]$entry.Kind
            Path = [string]$entry.Path
            Process = [string]$entry.Process
            TargetPath = [string]$entry.TargetPath
            Protected = [bool]$entry.Protected
        }
        $catalog[[string]$entry.Folder] = $custom
    }
}

if (-not $catalog.ContainsKey($Folder)) {
    throw "Unknown installed-app restore target: $Folder"
}
$app = $catalog[$Folder]
$targetPath = if ($app.TargetPath) { [string]$app.TargetPath } else { Join-Path $installRoot $Folder }
$repository = 'michadockermisha/{0}' -f $app.Slug
$workPath = Join-Path $installRoot ('.grestore-{0}-{1}' -f $PID, [guid]::NewGuid().ToString('N'))
$rootfsPath = Join-Path $workPath 'rootfs'
$stagingPath = Join-Path $rootfsPath 'home'
$destinationStagePath = $null
$previousTargetPath = $null
$originalSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol

if (-not (Test-Path -LiteralPath $profileModule -PathType Leaf)) {
    throw "Codex profile module was not found: $profileModule"
}
Import-Module -Name $profileModule -Force -DisableNameChecking -ErrorAction Stop
Initialize-CodexProfileFunctions

$fullRoot = [IO.Path]::GetFullPath($installRoot).TrimEnd('\')
$fullTarget = [IO.Path]::GetFullPath($targetPath).TrimEnd('\')
$fullWork = [IO.Path]::GetFullPath($workPath).TrimEnd('\')
$expectedTarget = if ($app.TargetPath) { [IO.Path]::GetFullPath([string]$app.TargetPath).TrimEnd('\') } else { $fullRoot + '\' + $Folder }
$targetRoot = [IO.Path]::GetPathRoot($fullTarget).TrimEnd('\')
if ($fullTarget -ne $expectedTarget -or $fullTarget -eq $targetRoot -or
    -not $fullWork.StartsWith($fullRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Installed-app restore path validation failed.'
}
if (-not (Test-Path -LiteralPath $installRoot -PathType Container)) {
    throw "Install root was not found: $installRoot"
}

$tarPath = @(
    (Get-Command tar.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
    (Join-Path $env:SystemRoot 'System32\tar.exe')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
$curlPath = @(
    (Get-Command curl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
    (Join-Path $env:SystemRoot 'System32\curl.exe')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (-not $tarPath -or -not $curlPath) {
    throw 'Windows tar.exe and curl.exe are required.'
}

function Remove-TemporaryFileWithRetry {
    param([Parameter(Mandatory)][string]$LiteralPath)
    for ($attempt = 1; $attempt -le 30; $attempt++) {
        try {
            Remove-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
            return
        } catch [IO.IOException] {
            if ($attempt -eq 30) { throw }
            Start-Sleep -Milliseconds 500
        }
    }
}

function Invoke-RegistryDownload {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Token
    )
    & $curlPath @(
        '--fail', '--location', '--silent', '--show-error'
        '--connect-timeout', '20', '--max-time', '1800'
        '--retry', '4', '--retry-delay', '2', '--retry-max-time', '2400'
        '--speed-time', '60', '--speed-limit', '1024'
        '--header', ('Authorization: Bearer ' + $Token)
        '--output', $Destination, $Uri
    )
    if ($LASTEXITCODE -ne 0) {
        throw "Registry download failed with curl exit $LASTEXITCODE`: $Uri"
    }
}

function Stop-OwnedRuntime {
    param([string]$Path)
    $runningServices = @(
        Get-Service -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq 'Running' } |
            Where-Object {
                $imagePath = (Get-ItemProperty -LiteralPath ('Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\' + $_.Name) -Name ImagePath -ErrorAction SilentlyContinue).ImagePath
                $imagePath -and $imagePath.IndexOf($Path, [StringComparison]::OrdinalIgnoreCase) -ge 0
            } |
            Select-Object -ExpandProperty Name
    )
    foreach ($name in $runningServices) {
        Stop-Service -Name $name -Force -ErrorAction Stop
    }
    if ($Folder -eq 'CodexMonitor') {
        & "$env:SystemRoot\System32\schtasks.exe" /End /TN '\CodexLiveWallBackend' 2>$null | Out-Null
    }
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Path -and
            $_.Path.StartsWith($Path + '\', [StringComparison]::OrdinalIgnoreCase)
        } |
        ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
    return $runningServices
}

function Wait-ExactProcess {
    param([string]$ExecutablePath, [string]$Name, [int]$Seconds = 30)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $process = Get-Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ProcessName -eq [IO.Path]::GetFileNameWithoutExtension($Name) -and
                $_.Path -and $_.Path.Equals($ExecutablePath, [StringComparison]::OrdinalIgnoreCase)
            } |
            Select-Object -First 1
        if ($process) {
            Start-Sleep -Seconds 2
            $native = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
            if ($native -and -not $native.HasExited -and $native.Responding) {
                return [pscustomobject]@{ ProcessId = $native.Id }
            }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "$Name did not remain ready from $ExecutablePath."
}

function Wait-HttpReady {
    param([string]$Uri, [int]$Seconds = 60)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 4
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                return
            }
        } catch {
        }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    throw "HTTP readiness check failed: $Uri"
}

function Start-AndVerifyApp {
    param([string[]]$PreviouslyRunningServices)
    foreach ($serviceName in $PreviouslyRunningServices) {
        Start-Service -Name $serviceName -ErrorAction SilentlyContinue
    }

    switch ([string]$app.Kind) {
        'Exe' {
            $exe = Join-Path $targetPath ([string]$app.Path)
            if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Launcher not found: $exe" }
            Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) | Out-Null
            $process = Wait-ExactProcess -ExecutablePath $exe -Name ([string]$app.Process) -Seconds 45
            return "process=$($process.ProcessId)"
        }
        'PowerShell' {
            $script = Join-Path $targetPath ([string]$app.Path)
            $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script) + @($app.Arguments)
            & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @arguments
            if ($LASTEXITCODE -ne 0) { throw "Launcher script failed: $script" }
            return 'script=ready'
        }
        'PowerShellDetached' {
            $script = Join-Path $targetPath ([string]$app.Path)
            if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw "Launcher script not found: $script" }
            $before = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($targetPath + '\', [StringComparison]::OrdinalIgnoreCase) } | Select-Object -ExpandProperty Id)
            $launcher = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script) -WorkingDirectory (Split-Path -Parent $script) -PassThru
            Start-Sleep -Seconds 4
            $owned = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($targetPath + '\', [StringComparison]::OrdinalIgnoreCase) -and $before -notcontains $_.Id })
            if ($owned.Count) { return "process=$($owned[0].Id)" }
            $launcher.Refresh()
            if (-not $launcher.HasExited) { return "launcher=$($launcher.Id)" }
            if ($launcher.ExitCode -ne 0) { throw "Launcher script failed with exit $($launcher.ExitCode): $script" }
            return 'script=completed'
        }
        'HttpScript' {
            $script = Join-Path $targetPath ([string]$app.Path)
            & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $script
            if ($LASTEXITCODE -ne 0) { throw "Launcher script failed: $script" }
            Wait-HttpReady -Uri ([string]$app.Uri)
            return "http=$($app.Uri)"
        }
        'Command' {
            $command = Join-Path $targetPath ([string]$app.Path)
            $output = @(& $command @($app.Arguments) 2>&1)
            if ($LASTEXITCODE -ne 0) { throw "Command validation failed: $command $($output -join ' ')" }
            return 'command=ready'
        }
        'Content' {
            $content = Join-Path $targetPath ([string]$app.Path)
            if (-not (Test-Path -LiteralPath $content -PathType Leaf)) { throw "Content validation failed: $content" }
            return 'content=ready'
        }
        'PluginSync' {
            $enginePath = Join-Path $env:LOCALAPPDATA 'qBittorrent\nova3\engines'
            New-Item -ItemType Directory -Path $enginePath -Force | Out-Null
            Get-ChildItem -LiteralPath $targetPath -File -Filter '*.py' -Force | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $enginePath $_.Name) -Force
                if ((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash -ne
                    (Get-FileHash -LiteralPath (Join-Path $enginePath $_.Name) -Algorithm SHA256).Hash) {
                    throw "qBittorrent plugin copy verification failed: $($_.Name)"
                }
            }
            return 'plugins=synchronized'
        }
        'Everything' {
            $exe = Join-Path $targetPath 'Everything.exe'
            $service = Get-Service -Name 'Everything' -ErrorAction SilentlyContinue
            if (-not $service) {
                & $exe -install-service | Out-Null
            }
            Start-Service -Name 'Everything' -ErrorAction Stop
            Start-Process -FilePath $exe | Out-Null
            $process = Wait-ExactProcess -ExecutablePath $exe -Name 'everything.exe'
            return "service=Running process=$($process.ProcessId)"
        }
        'ProcessLasso' {
            $gui = Join-Path $targetPath 'ProcessLasso.exe'
            $governor = Join-Path $targetPath 'ProcessGovernor.exe'
            $stub = Join-Path $targetPath 'srvstub.exe'
            if (-not (Get-Service -Name 'ProcessGovernor' -ErrorAction SilentlyContinue)) {
                New-Service -Name 'ProcessGovernor' -DisplayName 'Process Lasso Core (Process Governor)' `
                    -BinaryPathName ('"{0}" "{1}" "ProcessGovernor" /exitevent:Global\ProcessGovernorExitEvent' -f $stub, $governor) `
                    -StartupType Automatic | Out-Null
            }
            Start-Service -Name 'ProcessGovernor' -ErrorAction Stop
            Start-Process -FilePath $gui | Out-Null
            $process = Wait-ExactProcess -ExecutablePath $gui -Name 'ProcessLasso.exe'
            return "service=Running process=$($process.ProcessId)"
        }
        'Tailscale' {
            $daemon = Join-Path $targetPath 'tailscaled.exe'
            $cli = Join-Path $targetPath 'tailscale.exe'
            $gui = Join-Path $targetPath 'tailscale-ipn.exe'
            $service = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
            if (-not $service) {
                New-Service -Name 'Tailscale' -DisplayName 'Tailscale' -BinaryPathName ('"{0}"' -f $daemon) -StartupType Automatic | Out-Null
            } else {
                & "$env:SystemRoot\System32\sc.exe" config Tailscale 'binPath=' ('"{0}"' -f $daemon) 'start=' auto | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'Could not repair the Tailscale service.' }
            }
            Start-Service -Name 'Tailscale' -ErrorAction Stop
            Start-Process -FilePath $gui | Out-Null
            Start-Sleep -Seconds 3
            $status = @(& $cli status 2>&1)
            if ($LASTEXITCODE -ne 0 -and ($status -join ' ') -notmatch 'Logged out|NeedsLogin') {
                throw "Tailscale CLI readiness failed: $($status -join ' ')"
            }
            $process = Wait-ExactProcess -ExecutablePath $gui -Name 'tailscale-ipn.exe'
            return "service=Running process=$($process.ProcessId)"
        }
        'Cloudflare' {
            $serviceExe = Join-Path $targetPath 'warp-svc.exe'
            $cli = Join-Path $targetPath 'warp-cli.exe'
            $gui = Join-Path $targetPath 'Cloudflare WARP.exe'
            & "$env:SystemRoot\System32\sc.exe" config CloudflareWARP 'binPath=' ('"{0}"' -f $serviceExe) | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Could not repair CloudflareWARP service path.' }
            Start-Service -Name 'CloudflareWARP' -ErrorAction Stop
            $status = @(& $cli --no-ansi --json status 2>&1)
            if ($LASTEXITCODE -ne 0) { throw "Cloudflare CLI readiness failed: $($status -join ' ')" }
            Start-Process -FilePath $gui | Out-Null
            $process = Wait-ExactProcess -ExecutablePath $gui -Name 'Cloudflare WARP.exe'
            return "service=Running process=$($process.ProcessId)"
        }
        'CodexMonitor' {
            $launcher = Join-Path $targetPath 'Open-CodexMonitor.cmd'
            Start-Process -FilePath $launcher | Out-Null
            $daemon = Join-Path $targetPath 'app-live-codex-wall\codex_monitor_daemon.exe'
            $gui = Join-Path $targetPath 'app-live-codex-wall\codex-monitor.exe'
            $daemonProcess = Wait-ExactProcess -ExecutablePath $daemon -Name 'codex_monitor_daemon.exe' -Seconds 60
            $guiProcess = Wait-ExactProcess -ExecutablePath $gui -Name 'codex-monitor.exe' -Seconds 60
            return "daemon=$($daemonProcess.ProcessId) process=$($guiProcess.ProcessId)"
        }
        default {
            throw "Unsupported launch kind for $Folder`: $($app.Kind)"
        }
    }
}

try {
    [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $latestTag = [string](Get-BackupDockerLatestRemoteTag -RepoSlug ([string]$app.Slug) | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($latestTag)) { throw "No Docker tag found for $repository." }
    $latestTag = $latestTag.Trim()
    $imageRef = '{0}:{1}' -f $repository, $latestTag
    Write-Host "[g$Folder] Resolving $imageRef" -ForegroundColor Cyan

    $tokenUri = 'https://auth.docker.io/token?service=registry.docker.io&scope=repository:{0}:pull' -f $repository
    $token = (Invoke-RestMethod -Uri $tokenUri -Method Get -TimeoutSec 30).token
    if ([string]::IsNullOrWhiteSpace([string]$token)) { throw "No pull token returned for $repository." }
    $registryRoot = 'https://registry-1.docker.io/v2/{0}' -f $repository
    $headers = @{
        Authorization = 'Bearer ' + $token
        Accept = 'application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'
    }
    $manifest = Invoke-RestMethod -Uri "$registryRoot/manifests/$latestTag" -Headers $headers -Method Get -TimeoutSec 30
    $layers = @($manifest.layers)
    if ($manifest.schemaVersion -ne 2 -or $layers.Count -eq 0) { throw "Unsupported manifest for $imageRef." }

    New-Item -ItemType Directory -Path $rootfsPath -Force | Out-Null
    $configPath = Join-Path $workPath 'config.json'
    Invoke-RegistryDownload -Uri "$registryRoot/blobs/$($manifest.config.digest)" -Destination $configPath -Token $token
    $configHash = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if (('sha256:' + $configHash) -ne [string]$manifest.config.digest) { throw 'Docker config digest validation failed.' }
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $labels = $config.config.Labels
    if ([string]$labels.'backup.source.repo' -ne $repository -or [string]$labels.'backup.source.tag' -ne $latestTag) {
        throw "Docker labels did not match $imageRef."
    }
    $labeledSourcePath = [string]$labels.'backup.source.path'
    if ([string]::IsNullOrWhiteSpace($labeledSourcePath) -or
        -not [IO.Path]::GetFullPath($labeledSourcePath).TrimEnd('\').Equals($fullTarget, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Docker image target-path label does not match the saved restore path: $fullTarget"
    }
    $payloadDirectory = [string]$labels.'backup.payload.directory'
    if ([string]::IsNullOrWhiteSpace($payloadDirectory)) { $payloadDirectory = 'home' }
    if ($payloadDirectory -match '[\\/]' -or $payloadDirectory -in '.', '..') {
        throw "Unsafe payload directory label: $payloadDirectory"
    }
    $stagingPath = Join-Path $rootfsPath $payloadDirectory

    for ($index = 0; $index -lt $layers.Count; $index++) {
        $layer = $layers[$index]
        $layerType = [string]$layer.mediaType
        if ($layerType -notmatch '(?:\.tar|tar\+gzip)$') { throw "Unsupported layer type: $layerType" }
        $compressed = $layerType -match 'tar\+gzip$'
        $layerName = if ($compressed) { 'layer-{0}.tar.gz' -f $index } else { 'layer-{0}.tar' -f $index }
        $layerPath = Join-Path $workPath $layerName
        Write-Host ("[g{0}] Downloading layer {1}/{2}" -f $Folder, ($index + 1), $layers.Count) -ForegroundColor Cyan
        Invoke-RegistryDownload -Uri "$registryRoot/blobs/$($layer.digest)" -Destination $layerPath -Token $token
        $layerInfo = Get-Item -LiteralPath $layerPath
        if ([int64]$layer.size -ne $layerInfo.Length) { throw "Layer size validation failed: $($layer.digest)" }
        $layerHash = (Get-FileHash -LiteralPath $layerPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if (('sha256:' + $layerHash) -ne [string]$layer.digest) { throw "Layer digest validation failed: $($layer.digest)" }
        $listArguments = if ($compressed) { @('-tzf', $layerPath) } else { @('-tf', $layerPath) }
        $entries = @(& $tarPath @listArguments)
        if ($LASTEXITCODE -ne 0) { throw "Could not list layer: $($layer.digest)" }
        foreach ($entry in $entries) {
            $normalized = ([string]$entry).Replace('\', '/')
            if ($normalized.StartsWith('/') -or $normalized -match '(^|/)\.\.(/|$)') { throw "Unsafe layer path: $entry" }
        }
        $extractArguments = if ($compressed) { @('-xzf', $layerPath, '-C', $rootfsPath) } else { @('-xf', $layerPath, '-C', $rootfsPath) }
        & $tarPath @extractArguments
        if ($LASTEXITCODE -ne 0) { throw "Could not extract layer: $($layer.digest)" }
        Remove-TemporaryFileWithRetry -LiteralPath $layerPath
    }

    if (-not (Test-Path -LiteralPath $stagingPath -PathType Container)) { throw "Image payload is missing: $imageRef" }
    $stagedFiles = @(Get-ChildItem -LiteralPath $stagingPath -File -Recurse -Force)
    $stagedDirectories = @(Get-ChildItem -LiteralPath $stagingPath -Directory -Recurse -Force)
    $stagedBytes = [int64](($stagedFiles | Measure-Object Length -Sum).Sum)
    $expectedFiles = [int64]$labels.'backup.source.files'
    $expectedBytes = [int64]$labels.'backup.source.bytes'
    $expectedDirectoriesLabel = [string]$labels.'backup.source.directories'
    $expectedDirectories = if ([string]::IsNullOrWhiteSpace($expectedDirectoriesLabel)) { $null } else { [int64]$expectedDirectoriesLabel }
    if ($stagedFiles.Count -ne $expectedFiles -or $stagedBytes -ne $expectedBytes) {
        throw "Image payload mismatch for $imageRef`: files $($stagedFiles.Count)/$expectedFiles bytes $stagedBytes/$expectedBytes."
    }
    if ($null -ne $expectedDirectories -and $stagedDirectories.Count -ne $expectedDirectories) {
        throw "Image directory mismatch for $imageRef`: directories $($stagedDirectories.Count)/$expectedDirectories."
    }
    if ($SelfTest) {
        Write-Output "GRESTORE_SELFTEST_OK folder=$Folder image=$imageRef files=$expectedFiles bytes=$expectedBytes protected=$([bool]$app.Protected)"
        return
    }

    $previouslyRunningServices = @(Stop-OwnedRuntime -Path $targetPath)
    if ($app.Protected) {
        if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
        }
        & "$env:SystemRoot\System32\robocopy.exe" $stagingPath $targetPath /E /COPY:DAT /DCOPY:DAT /R:3 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Protected overlay failed for $Folder with robocopy exit $LASTEXITCODE." }
    } else {
        $targetParent = Split-Path -Parent $fullTarget
        if ([string]::IsNullOrWhiteSpace($targetParent)) { throw "Target parent could not be resolved: $fullTarget" }
        if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        }
        $destinationStagePath = Join-Path $targetParent ('.grestore-new-{0}-{1}' -f $Folder, [guid]::NewGuid().ToString('N'))
        $previousTargetPath = Join-Path $targetParent ('.grestore-old-{0}-{1}' -f $Folder, [guid]::NewGuid().ToString('N'))
        foreach ($siblingPath in @($destinationStagePath, $previousTargetPath)) {
            $fullSibling = [IO.Path]::GetFullPath($siblingPath)
            if (-not $fullSibling.StartsWith([IO.Path]::GetFullPath($targetParent).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
                [IO.Path]::GetFileName($fullSibling) -notlike '.grestore-*-*') {
                throw "Unsafe transactional restore path: $fullSibling"
            }
        }
        New-Item -ItemType Directory -Path $destinationStagePath -Force | Out-Null
        & "$env:SystemRoot\System32\robocopy.exe" $stagingPath $destinationStagePath /E /COPY:DAT /DCOPY:DAT /SL /SJ /R:3 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Destination staging failed for $Folder with robocopy exit $LASTEXITCODE." }
        $destinationFiles = @(Get-ChildItem -LiteralPath $destinationStagePath -File -Recurse -Force)
        $destinationDirectories = @(Get-ChildItem -LiteralPath $destinationStagePath -Directory -Recurse -Force)
        $destinationBytes = [int64](($destinationFiles | Measure-Object Length -Sum).Sum)
        if ($destinationFiles.Count -ne $expectedFiles -or $destinationBytes -ne $expectedBytes -or
            ($null -ne $expectedDirectories -and $destinationDirectories.Count -ne $expectedDirectories)) {
            throw "Destination staging verification failed for $Folder."
        }
        if (Test-Path -LiteralPath $targetPath) {
            $item = Get-Item -LiteralPath $targetPath -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing to replace reparse target: $targetPath" }
            Move-Item -LiteralPath $targetPath -Destination $previousTargetPath -Force
        }
        try {
            Move-Item -LiteralPath $destinationStagePath -Destination $targetPath -Force
            $destinationStagePath = $null
            $restoredFiles = @(Get-ChildItem -LiteralPath $targetPath -File -Recurse -Force)
            $restoredDirectories = @(Get-ChildItem -LiteralPath $targetPath -Directory -Recurse -Force)
            $restoredBytes = [int64](($restoredFiles | Measure-Object Length -Sum).Sum)
            if ($restoredFiles.Count -ne $expectedFiles -or $restoredBytes -ne $expectedBytes -or
                ($null -ne $expectedDirectories -and $restoredDirectories.Count -ne $expectedDirectories)) {
                throw "Installed payload verification failed for $Folder."
            }
            if ($previousTargetPath -and (Test-Path -LiteralPath $previousTargetPath)) {
                Remove-Item -LiteralPath $previousTargetPath -Recurse -Force -Confirm:$false
                $previousTargetPath = $null
            }
        } catch {
            if ($previousTargetPath -and (Test-Path -LiteralPath $previousTargetPath)) {
                if (Test-Path -LiteralPath $targetPath) {
                    Remove-Item -LiteralPath $targetPath -Recurse -Force -Confirm:$false
                }
                Move-Item -LiteralPath $previousTargetPath -Destination $targetPath -Force
                $previousTargetPath = $null
            }
            throw
        }
    }

    $ready = Start-AndVerifyApp -PreviouslyRunningServices $previouslyRunningServices
    $functionName = 'g' + ($Folder -replace '[^A-Za-z0-9]', '')
    Write-Output "GRESTORE_READY_OK function=$functionName image=$imageRef protected=$([bool]$app.Protected) $ready"
} finally {
    [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol
    if (Test-Path -LiteralPath $workPath -PathType Container) {
        Remove-Item -LiteralPath $workPath -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
    if ($destinationStagePath -and (Test-Path -LiteralPath $destinationStagePath -PathType Container)) {
        Remove-Item -LiteralPath $destinationStagePath -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
}
