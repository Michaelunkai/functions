# Restores and launches Cloudflare WARP using the latest Docker Hub backup.
# The workflow mirrors gccleaner, with verified staging so a failed restore
# cannot destroy the working installation.
if (-not (Get-Command -Name 'Initialize-CodexProfileFunctions' -CommandType Function -ErrorAction SilentlyContinue)) {
    $__2scProfileModule = 'C:\Users\micha\Documents\WindowsPowerShell\Modules\CodexProfileFunctions\CodexProfileFunctions.psd1'
    if (-not (Test-Path -LiteralPath $__2scProfileModule -PathType Leaf)) {
        throw "gclaudflare requires the Codex profile module: $__2scProfileModule"
    }
    Import-Module -Name $__2scProfileModule -DisableNameChecking -ErrorAction Stop
    Initialize-CodexProfileFunctions
}

function gclaudflare {
    [CmdletBinding()]
    param([switch]$SelfTest)

    $installRoot = 'F:\backup\windowsapps\installed'
    $cloudflarePath = Join-Path $installRoot 'cloudflare'
    $repository = 'michadockermisha/cloudflare'
    $repoSlug = 'cloudflare'
    $workPath = Join-Path $installRoot ('.gclaudflare-work-{0}-{1}' -f $PID, [guid]::NewGuid().ToString('N'))
    $rootfsPath = Join-Path $workPath 'rootfs'
    $stagingPath = Join-Path $rootfsPath 'home'
    $originalSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol

    $fullInstallRoot = [System.IO.Path]::GetFullPath($installRoot).TrimEnd('\')
    $fullCloudflarePath = [System.IO.Path]::GetFullPath($cloudflarePath).TrimEnd('\')
    $fullWorkPath = [System.IO.Path]::GetFullPath($workPath).TrimEnd('\')
    if ($fullCloudflarePath -ne ($fullInstallRoot + '\cloudflare') -or
        -not $fullWorkPath.StartsWith($fullInstallRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Cloudflare restore path validation failed.'
    }
    if (-not (Test-Path -LiteralPath $installRoot -PathType Container)) {
        throw "Cloudflare install root was not found: $installRoot"
    }
    if (-not $SelfTest) {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
        if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'gclaudflare must run from an elevated PowerShell session so it can repair and start the Cloudflare WARP service.'
        }
    }

    $tarPath = @(
        (Get-Command -Name 'tar.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
        (Join-Path $env:SystemRoot 'System32\tar.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
    if (-not $tarPath) {
        throw 'Windows tar.exe was not found.'
    }
    $curlPath = @(
        (Get-Command -Name 'curl.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
        (Join-Path $env:SystemRoot 'System32\curl.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
    if (-not $curlPath) {
        throw 'Windows curl.exe was not found.'
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        $latestTag = [string](Get-BackupDockerLatestRemoteTag -RepoSlug $repoSlug | Select-Object -Last 1)
        if ([string]::IsNullOrWhiteSpace($latestTag)) {
            throw "No Docker tag was found for $repository."
        }
        $latestTag = $latestTag.Trim()
        $imageRef = '{0}:{1}' -f $repository, $latestTag

        Write-Host "[gclaudflare] Resolving $imageRef" -ForegroundColor Cyan
        $tokenUri = 'https://auth.docker.io/token?service=registry.docker.io&scope=repository:{0}:pull' -f $repository
        $token = (Invoke-RestMethod -Uri $tokenUri -Method Get -TimeoutSec 30 -ErrorAction Stop).token
        if ([string]::IsNullOrWhiteSpace([string]$token)) {
            throw "Docker Hub did not return a pull token for $repository."
        }

        function Invoke-GclaudflareDownload {
            param(
                [Parameter(Mandatory)][string]$Uri,
                [Parameter(Mandatory)][string]$Destination
            )

            & $curlPath @(
                '--fail'
                '--location'
                '--silent'
                '--show-error'
                '--connect-timeout', '20'
                '--max-time', '300'
                '--retry', '3'
                '--retry-delay', '2'
                '--retry-max-time', '600'
                '--speed-time', '30'
                '--speed-limit', '1024'
                '--header', ('Authorization: Bearer ' + $token)
                '--output', $Destination
                $Uri
            )
            if ($LASTEXITCODE -ne 0) {
                throw "Download failed with curl exit $LASTEXITCODE`: $Uri"
            }
        }

        $registryRoot = 'https://registry-1.docker.io/v2/{0}' -f $repository
        $headers = @{
            Authorization = 'Bearer ' + $token
            Accept = 'application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'
        }
        $manifest = Invoke-RestMethod -Uri "$registryRoot/manifests/$latestTag" -Headers $headers -Method Get -TimeoutSec 30 -ErrorAction Stop
        $layers = @($manifest.layers)
        if ($manifest.schemaVersion -ne 2 -or $layers.Count -eq 0) {
            throw "Docker Hub returned an unsupported manifest for $imageRef."
        }

        $null = New-Item -ItemType Directory -Path $rootfsPath -Force -ErrorAction Stop
        $configPath = Join-Path $workPath 'config.json'
        Invoke-GclaudflareDownload -Uri "$registryRoot/blobs/$($manifest.config.digest)" -Destination $configPath
        $configHash = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if (('sha256:' + $configHash) -ne [string]$manifest.config.digest) {
            throw "Docker config digest verification failed for $imageRef."
        }
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -ErrorAction Stop
        $labels = $config.config.Labels
        if ([string]$labels.'backup.source.repo' -ne $repository -or
            [string]$labels.'backup.source.tag' -ne $latestTag) {
            throw "Docker image labels did not match $imageRef."
        }

        for ($index = 0; $index -lt $layers.Count; $index++) {
            $layer = $layers[$index]
            if ([string]$layer.mediaType -notmatch 'tar\+gzip$') {
                throw "Unsupported Docker layer type: $($layer.mediaType)"
            }

            $layerPath = Join-Path $workPath ('layer-{0}.tar.gz' -f $index)
            Write-Host ("[gclaudflare] Downloading layer {0}/{1}" -f ($index + 1), $layers.Count) -ForegroundColor Cyan
            Invoke-GclaudflareDownload -Uri "$registryRoot/blobs/$($layer.digest)" -Destination $layerPath

            $layerInfo = Get-Item -LiteralPath $layerPath -Force -ErrorAction Stop
            if ([int64]$layer.size -gt 0 -and $layerInfo.Length -ne [int64]$layer.size) {
                throw "Docker layer size verification failed for $($layer.digest)."
            }
            $layerHash = (Get-FileHash -LiteralPath $layerPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if (('sha256:' + $layerHash) -ne [string]$layer.digest) {
                throw "Docker layer digest verification failed for $($layer.digest)."
            }

            $entries = @(& $tarPath -tzf $layerPath)
            if ($LASTEXITCODE -ne 0) {
                throw "Could not list Docker layer $($layer.digest)."
            }
            foreach ($entry in $entries) {
                $normalizedEntry = ([string]$entry).Replace('\', '/')
                if ($normalizedEntry.StartsWith('/') -or $normalizedEntry -match '(^|/)\.\.(/|$)') {
                    throw "Unsafe path in Docker layer: $entry"
                }
            }

            & $tarPath -xzf $layerPath -C $rootfsPath
            if ($LASTEXITCODE -ne 0) {
                throw "Could not extract Docker layer $($layer.digest)."
            }
            Remove-Item -LiteralPath $layerPath -Force -ErrorAction Stop
        }

        $stagedExe = Join-Path $stagingPath 'Cloudflare WARP.exe'
        if (-not (Test-Path -LiteralPath $stagedExe -PathType Leaf)) {
            throw "Cloudflare WARP.exe was not found in restored image $imageRef."
        }

        $stagedFiles = @(Get-ChildItem -LiteralPath $stagingPath -Recurse -File -Force -ErrorAction Stop)
        $stagedBytes = [int64](($stagedFiles | Measure-Object -Property Length -Sum).Sum)
        $expectedFiles = [int64]$labels.'backup.source.files'
        $expectedBytes = [int64]$labels.'backup.source.bytes'
        if ($expectedFiles -gt 0 -and $stagedFiles.Count -lt $expectedFiles) {
            throw "Restored file count was incomplete: $($stagedFiles.Count) < $expectedFiles."
        }
        if ($expectedBytes -gt 0 -and $stagedBytes -lt $expectedBytes) {
            throw "Restored byte count was incomplete: $stagedBytes < $expectedBytes."
        }

        foreach ($binaryName in @('Cloudflare WARP.exe', 'warp-svc.exe', 'warp-cli.exe', 'warp-updater.exe')) {
            $binaryPath = Join-Path $stagingPath $binaryName
            if (-not (Test-Path -LiteralPath $binaryPath -PathType Leaf)) {
                throw "$binaryName was not found in restored image $imageRef."
            }
            $signature = Get-AuthenticodeSignature -LiteralPath $binaryPath
            if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
                [string]$signature.SignerCertificate.Subject -notmatch 'Cloudflare, Inc\.') {
                throw "$binaryName signature validation failed: $($signature.Status)."
            }
        }
        $version = (Get-Item -LiteralPath $stagedExe -Force).VersionInfo.FileVersion
        if ([string]::IsNullOrWhiteSpace($version)) {
            throw 'Cloudflare WARP.exe has no file version.'
        }

        if ($SelfTest) {
            Write-Output ("GCLAUDFLARE_SELFTEST_OK image={0} version={1} files={2} bytes={3}" -f $imageRef, $version, $stagedFiles.Count, $stagedBytes)
            return
        }

        Get-Service -Name 'CloudflareWARP', 'CloudflareWARPUpdater' -ErrorAction SilentlyContinue |
            Stop-Service -Force -ErrorAction SilentlyContinue
        Get-Process -Name 'Cloudflare WARP', 'warp-svc', 'warp-updater', 'warp-dex', 'warp-diag', 'warp-cli' -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue

        for ($attempt = 1; $attempt -le 20 -and (Test-Path -LiteralPath $cloudflarePath); $attempt++) {
            Remove-Item -LiteralPath $cloudflarePath -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $cloudflarePath) {
                Start-Sleep -Milliseconds 500
            }
        }
        if (Test-Path -LiteralPath $cloudflarePath) {
            throw "Cloudflare folder is still locked and could not be removed: $cloudflarePath"
        }

        Move-Item -LiteralPath $stagingPath -Destination $cloudflarePath -Force -ErrorAction Stop

        $exePath = Join-Path $cloudflarePath 'Cloudflare WARP.exe'
        $timeout = 0
        while (-not (Test-Path -LiteralPath $exePath -PathType Leaf) -and $timeout -lt 20) {
            Start-Sleep -Seconds 1
            $timeout++
        }
        if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
            throw 'Cloudflare WARP.exe was not found after waiting 20 seconds.'
        }

        $serviceExePath = Join-Path $cloudflarePath 'warp-svc.exe'
        $updaterExePath = Join-Path $cloudflarePath 'warp-updater.exe'
        $cliPath = Join-Path $cloudflarePath 'warp-cli.exe'
        $warpService = Get-Service -Name 'CloudflareWARP' -ErrorAction SilentlyContinue
        if (-not $warpService) {
            New-Service -Name 'CloudflareWARP' `
                -BinaryPathName ('"{0}"' -f $serviceExePath) `
                -DisplayName 'Cloudflare One Client' `
                -Description 'Cloudflare One Client service' `
                -StartupType Automatic `
                -DependsOn 'WlanSvc' `
                -ErrorAction Stop | Out-Null
        } else {
            $scOutput = @(& "$env:SystemRoot\System32\sc.exe" config CloudflareWARP `
                'binPath=' ('"{0}"' -f $serviceExePath) `
                'start=' auto `
                'depend=' WlanSvc `
                'DisplayName=' 'Cloudflare One Client' 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Could not configure the CloudflareWARP service: $($scOutput -join ' ')"
            }
        }

        $updaterService = Get-Service -Name 'CloudflareWARPUpdater' -ErrorAction SilentlyContinue
        if (-not $updaterService) {
            New-Service -Name 'CloudflareWARPUpdater' `
                -BinaryPathName ('"{0}"' -f $updaterExePath) `
                -DisplayName 'Cloudflare One Client Updater' `
                -Description 'Cloudflare One Client updater service' `
                -StartupType Manual `
                -ErrorAction Stop | Out-Null
        } else {
            $scOutput = @(& "$env:SystemRoot\System32\sc.exe" config CloudflareWARPUpdater `
                'binPath=' ('"{0}"' -f $updaterExePath) `
                'start=' demand `
                'DisplayName=' 'Cloudflare One Client Updater' 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Could not configure the CloudflareWARPUpdater service: $($scOutput -join ' ')"
            }
        }

        Start-Service -Name 'CloudflareWARP' -ErrorAction Stop
        $warpService = Get-Service -Name 'CloudflareWARP' -ErrorAction Stop
        $warpService.WaitForStatus(
            [System.ServiceProcess.ServiceControllerStatus]::Running,
            [TimeSpan]::FromSeconds(30)
        )
        $warpService.Refresh()
        if ($warpService.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
            throw 'CloudflareWARP did not reach the Running state.'
        }

        $warpStatus = $null
        $lastCliError = $null
        for ($attempt = 1; $attempt -le 20 -and -not $warpStatus; $attempt++) {
            $statusOutput = @(& $cliPath --no-ansi --json status 2>&1)
            $statusExitCode = $LASTEXITCODE
            $statusText = ($statusOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
            if ($statusExitCode -eq 0) {
                try {
                    $warpStatus = $statusText | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    $lastCliError = $_.Exception.Message
                }
            } else {
                $lastCliError = $statusText
            }
            if (-not $warpStatus) {
                Start-Sleep -Milliseconds 500
            }
        }
        if (-not $warpStatus) {
            throw "warp-cli could not communicate with the CloudflareWARP service: $lastCliError"
        }

        $registrationOutput = @(& $cliPath --no-ansi --json registration show 2>&1)
        $registrationExitCode = $LASTEXITCODE
        $registrationText = ($registrationOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        if ($registrationExitCode -ne 0) {
            throw "Cloudflare WARP has no usable registration: $registrationText"
        }
        try {
            $registration = $registrationText | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "Cloudflare WARP returned invalid registration data: $($_.Exception.Message)"
        }
        if ([string]::IsNullOrWhiteSpace([string]$registration.id) -or
            [string]::IsNullOrWhiteSpace([string]$registration.account.id)) {
            throw 'Cloudflare WARP registration is incomplete.'
        }

        $serviceConfig = Get-CimInstance Win32_Service -Filter "Name='CloudflareWARP'" -ErrorAction Stop
        if ($serviceConfig.State -ne 'Running' -or
            $serviceConfig.PathName.Trim('"') -ne $serviceExePath) {
            throw 'CloudflareWARP service configuration did not match the restored installation.'
        }

        Start-Process -FilePath $exePath | Out-Null
        $guiProcess = $null
        for ($attempt = 1; $attempt -le 30 -and -not $guiProcess; $attempt++) {
            $guiProcess = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -eq 'Cloudflare WARP.exe' -and
                    $_.ExecutablePath -eq $exePath
                } |
                Select-Object -First 1
            if (-not $guiProcess) {
                Start-Sleep -Milliseconds 500
            }
        }
        if (-not $guiProcess) {
            throw "Cloudflare WARP GUI did not remain running from $exePath."
        }

        Start-Sleep -Seconds 5
        $warpService = Get-Service -Name 'CloudflareWARP' -ErrorAction Stop
        $guiStillRunning = Get-CimInstance Win32_Process -Filter "ProcessId=$($guiProcess.ProcessId)" -ErrorAction SilentlyContinue
        $guiNativeProcess = Get-Process -Id $guiProcess.ProcessId -ErrorAction SilentlyContinue
        if ($warpService.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running -or
            -not $guiStillRunning -or
            $guiStillRunning.ExecutablePath -ne $exePath -or
            -not $guiNativeProcess -or
            -not $guiNativeProcess.Responding) {
            throw 'Cloudflare WARP did not remain ready after launch.'
        }

        $statusOutput = @(& $cliPath --no-ansi --json status 2>&1)
        $statusExitCode = $LASTEXITCODE
        $statusText = ($statusOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        if ($statusExitCode -ne 0) {
            throw "warp-cli lost communication with the CloudflareWARP service after GUI launch: $statusText"
        }
        try {
            $warpStatus = $statusText | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "Cloudflare WARP returned invalid status data after GUI launch: $($_.Exception.Message)"
        }

        $connectionStatus = [string]$warpStatus.status
        if ([string]::IsNullOrWhiteSpace($connectionStatus)) {
            $connectionStatus = 'Available'
        }
        Write-Output ("GCLAUDFLARE_READY_OK image={0} version={1} service={2} status={3} guiPid={4}" -f `
            $imageRef, $version, $warpService.Status, $connectionStatus, $guiProcess.ProcessId)
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol
        if (Test-Path -LiteralPath $workPath -PathType Container) {
            Remove-Item -LiteralPath $workPath -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    & 'gclaudflare' @args
}
