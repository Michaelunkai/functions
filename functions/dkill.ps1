#Requires -Version 5.0
<#
.SYNOPSIS
    dkill - fast destructive Docker reset that returns only when the VMM and tray are ready.

.DESCRIPTION
    The default operation deletes Docker engine data, including the live Docker
    VMM disk under LocalAppData, then recreates Docker on the canonical VMM
    backend and waits for the daemon and Docker Desktop tray frontend. Docker
    Hub credentials and the minimum settings needed to restore the VMM are
    retained so push works afterward without onboarding or license prompts.

    Use -Preserve for a bounded non-destructive VMM restart.

.PARAMETER NoRestart
    Stop only; do not start Docker Desktop at the end.

.PARAMETER Preserve
    Restart or stop Docker without deleting engine data.

.PARAMETER FactoryReset
    Compatibility switch. Destructive reset is now the default.

.PARAMETER SelfTest
    Print diagnostics and exit without changing anything.
#>
[CmdletBinding()]
param(
    [switch]$NoRestart,
    [switch]$Preserve,
    [switch]$FactoryReset,
    [string]$ConfirmFactoryReset = '',
    [switch]$SelfTest,
    [Parameter(DontShow = $true)]
    [switch]$Worker
)

$ErrorActionPreference = 'SilentlyContinue'
$ConfirmPreference = 'None'
$script:LogPath = 'C:\Temp\dkill.log'
$script:WatchdogTask = 'DockerDesktopWatchdog'

function Write-DLine {
    param([string]$Message, [string]$Color = 'Cyan')
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    Write-Host ("[dkill] {0}" -f $Message) -ForegroundColor $Color
    try { Add-Content -LiteralPath $script:LogPath -Value ("[{0}] {1}" -f $stamp, $Message) -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Test-DAdmin {
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Invoke-Bounded {
    param([string]$FilePath, [string[]]$ArgumentList, [int]$Milliseconds = 5000)
    $result = [pscustomobject]@{ ExitCode = 1; Stdout = ''; Stderr = ''; TimedOut = $false }
    if ([string]::IsNullOrWhiteSpace($FilePath) -or -not (Test-Path -LiteralPath $FilePath)) {
        $result.Stderr = 'executable not found'
        return $result
    }
    $tempRoot = 'C:\Temp'
    try { if (-not (Test-Path -LiteralPath $tempRoot)) { New-Item -ItemType Directory -Path $tempRoot -Force -ErrorAction Stop | Out-Null } } catch { }
    $outFile = Join-Path $tempRoot ('dkill-out-' + [guid]::NewGuid().ToString('N') + '.log')
    $errFile = Join-Path $tempRoot ('dkill-err-' + [guid]::NewGuid().ToString('N') + '.log')
    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WindowStyle Hidden -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile -ErrorAction Stop
        if (-not $process.WaitForExit([Math]::Max(250, $Milliseconds))) {
            try { $process.Kill() } catch { }
            $result.ExitCode = 124
            $result.TimedOut = $true
            $result.Stderr = 'timed out'
            return $result
        }
        $result.ExitCode = [int]$process.ExitCode
        try { $result.Stdout = (Get-Content -LiteralPath $outFile -Raw -ErrorAction Stop).Trim() } catch { }
        try { $result.Stderr = (Get-Content -LiteralPath $errFile -Raw -ErrorAction Stop).Trim() } catch { }
        return $result
    } catch {
        $result.Stderr = $_.Exception.Message
        return $result
    } finally {
        foreach ($file in @($outFile, $errFile)) { try { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue } catch { } }
    }
}

function Test-DaemonReady {
    param([string]$DockerExe, [int]$Milliseconds = 1000)
    if ([string]::IsNullOrWhiteSpace($DockerExe) -or -not (Test-Path -LiteralPath $DockerExe)) { return $false }
    if (-not (Test-Path -LiteralPath '\\.\pipe\dockerDesktopLinuxEngine')) { return $false }
    $r = Invoke-Bounded -FilePath $DockerExe -ArgumentList @('version', '--format', '{{.Server.Version}}') -Milliseconds $Milliseconds
    if ($r.TimedOut -or $r.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($r.Stdout)) { return $false }
    if ($r.Stderr -match '(?i)failed to connect|daemon is not running|error during connect|cannot find') { return $false }
    return $true
}

function Test-DockerFrontendReady {
    return (@(Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue).Count -gt 0)
}

function Find-DockerExe {
    $candidates = @((Join-Path ${env:ProgramFiles} 'Docker\Docker\resources\bin\docker.exe'))
    $cmd = Get-Command docker.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source) { $candidates += $cmd.Source }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    return $null
}

function Set-DockerVmmSettings {
    $settingsPath = Join-Path $env:APPDATA 'Docker\settings-store.json'
    $parent = Split-Path -Parent $settingsPath
    New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
    $settings = $null
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        try { $settings = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { }
    }
    if (-not $settings) {
        $settings = [pscustomobject][ordered]@{
            AutoStart = $false
            DisplayedOnboarding = $true
            EnableIntegrationWithDefaultWslDistro = $false
            FilesharingDirectories = @($env:USERPROFILE)
            MemoryMiB = 33792
            OpenUIOnStartupDisabled = $true
            SettingsVersion = 45
        }
    }
    function Set-DockerVmmProperty {
        param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$Name, $Value)
        $property = $Object.PSObject.Properties[$Name]
        if ($property) { $property.Value = $Value } else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
    }
    Set-DockerVmmProperty -Object $settings -Name 'AllowBetaFeatures' -Value $true
    Set-DockerVmmProperty -Object $settings -Name 'LicenseTermsVersion' -Value 2
    Set-DockerVmmProperty -Object $settings -Name 'DisplayedOnboarding' -Value $true
    Set-DockerVmmProperty -Object $settings -Name 'MemoryMiB' -Value 33792
    Set-DockerVmmProperty -Object $settings -Name 'UseLibkrun' -Value $true
    Set-DockerVmmProperty -Object $settings -Name 'UseResourceSaver' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'UseVirtualizationFramework' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'WslEngineEnabled' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'UseContainerdSnapshotter' -Value $true
    Set-DockerVmmProperty -Object $settings -Name 'EnableIntegrationWithDefaultWslDistro' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'AutoStart' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'OpenUIOnStartupDisabled' -Value $true
    Set-DockerVmmProperty -Object $settings -Name 'ShowInstallScreen' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'DisplayRestartDialog' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'ShowAnnouncementNotifications' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'ShowGeneralNotifications' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'ShowPromotionalNotifications' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'ShowSurveyNotifications' -Value $false
    $shares = @(@($settings.FilesharingDirectories) + @($env:USERPROFILE, 'C:\Temp', 'F:\study') | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_) -and
        [string]$_ -notmatch '^[A-Za-z]:\\$' -and
        (Test-Path -LiteralPath ([string]$_) -PathType Container)
    } | Select-Object -Unique)
    Set-DockerVmmProperty -Object $settings -Name 'FilesharingDirectories' -Value $shares
    $temporary = Join-Path $parent ('.settings-store.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, ($settings | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $settingsPath -Force -ErrorAction Stop
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
    Write-DLine ("Docker VMM settings enforced; explicit shares={0}" -f $shares.Count) 'Green'
}

function Test-DockerVmmConfigured {
    $settingsPath = Join-Path $env:APPDATA 'Docker\settings-store.json'
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) { return $false }
    try {
        $settings = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return [bool]$settings.UseLibkrun -and -not [bool]$settings.WslEngineEnabled -and -not [bool]$settings.UseVirtualizationFramework
    } catch { return $false }
}

function Stop-AllDocker {
    # Docker VMM is process-backed. Stop only its user-mode runtime and keep the
    # privileged helper warm for the fresh launch. Hyper-V/WMI inventory is both
    # irrelevant to VMM and can block indefinitely when the provider is unhealthy.
    $dockerNames = @('Docker Desktop', 'Docker Desktop Installer', 'com.docker.backend', 'com.docker.proxy', 'com.docker.sailor', 'com.docker.build', 'com.docker.dev-envs', 'com.docker.cli', 'com.docker.vpnkit', 'docker', 'dockerd', 'vpnkit', 'docker-agent', 'docker-sandbox', 'containerd')
    $deadline = [DateTime]::UtcNow.AddMilliseconds(1200)
    do {
        $remaining = @()
        foreach ($name in $dockerNames) {
            foreach ($proc in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
                $remaining += $proc
                try { $proc.Kill() } catch { }
            }
        }
        if ($remaining.Count -eq 0) { break }
        Start-Sleep -Milliseconds 80
    } while ([DateTime]::UtcNow -lt $deadline)
    $remaining = @(
        foreach ($name in $dockerNames) {
            Get-Process -Name $name -ErrorAction SilentlyContinue
        }
    )
    if ($remaining.Count -gt 0) {
        Write-DLine ("WARN {0} Docker process(es) still exiting; VHD deletion will verify the lock" -f $remaining.Count) 'DarkYellow'
    }
}

function Remove-DockerPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $true }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    # Fast path: as an elevated admin we normally own everything here - just delete.
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try {
            if ($item.PSIsContainer) { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop }
            else { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop }
        } catch { }
        if (-not (Test-Path -LiteralPath $Path)) { break }
        Start-Sleep -Milliseconds 500
    }
    # Escalation path (rare): take ownership, grant access, clear attributes, retry.
    if (Test-Path -LiteralPath $Path) {
        $takeown = Join-Path $env:SystemRoot 'System32\takeown.exe'
        $icacls = Join-Path $env:SystemRoot 'System32\icacls.exe'
        $attrib = Join-Path $env:SystemRoot 'System32\attrib.exe'
        if ($item -and $item.PSIsContainer) {
            if (Test-Path -LiteralPath $takeown) { $null = Invoke-Bounded -FilePath $takeown -ArgumentList @('/F', $Path, '/A', '/R', '/D', 'Y') -Milliseconds 15000 }
            if (Test-Path -LiteralPath $icacls) { $null = Invoke-Bounded -FilePath $icacls -ArgumentList @($Path, '/grant', 'Administrators:(OI)(CI)F', '/T', '/C', '/Q') -Milliseconds 20000 }
            if (Test-Path -LiteralPath $attrib) { $null = Invoke-Bounded -FilePath $attrib -ArgumentList @('-R', '-S', '-H', $Path, '/S', '/D') -Milliseconds 10000 }
        } else {
            if (Test-Path -LiteralPath $takeown) { $null = Invoke-Bounded -FilePath $takeown -ArgumentList @('/F', $Path, '/A') -Milliseconds 10000 }
            if (Test-Path -LiteralPath $icacls) { $null = Invoke-Bounded -FilePath $icacls -ArgumentList @($Path, '/grant', 'Administrators:F', '/C', '/Q') -Milliseconds 10000 }
            if (Test-Path -LiteralPath $attrib) { $null = Invoke-Bounded -FilePath $attrib -ArgumentList @('-R', '-S', '-H', $Path) -Milliseconds 5000 }
        }
        try {
            if ($item.PSIsContainer) { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue }
            else { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
        } catch { }
    }
    if (Test-Path -LiteralPath $Path) {
        Write-DLine ("WARN could not delete {0}" -f $Path) 'DarkYellow'
        return $false
    }
    Write-DLine ("deleted {0}" -f $Path) 'Green'
    return $true
}

function Start-PrivateService {
    param([string]$ServiceName = 'com.docker.service')
    $sc = Join-Path $env:SystemRoot 'System32\sc.exe'
    if (-not (Test-Path -LiteralPath $sc)) { return $false }
    $query = Invoke-Bounded -FilePath $sc -ArgumentList @('query', $ServiceName) -Milliseconds 5000
    if ($query.ExitCode -eq 0 -and $query.Stdout -match '(?im)^\s*STATE\s*:\s*4\s+RUNNING') { return $true }
    $null = Invoke-Bounded -FilePath $sc -ArgumentList @('start', $ServiceName) -Milliseconds 10000
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        Start-Sleep -Milliseconds 750
        $query2 = Invoke-Bounded -FilePath $sc -ArgumentList @('query', $ServiceName) -Milliseconds 5000
        if ($query2.ExitCode -eq 0 -and $query2.Stdout -match '(?im)^\s*STATE\s*:\s*4\s+RUNNING') {
            Write-DLine ("privileged helper service running: {0}" -f $ServiceName) 'Green'
            return $true
        }
    }
    Write-DLine ("WARN privileged helper service did not start: {0}" -f $ServiceName) 'Yellow'
    return $false
}

function Start-DockerVmmWithTray {
    $backendExe = Join-Path ${env:ProgramFiles} 'Docker\Docker\resources\com.docker.backend.exe'
    $desktopExe = Join-Path ${env:ProgramFiles} 'Docker\Docker\Docker Desktop.exe'
    if (-not (Test-Path -LiteralPath $backendExe -PathType Leaf) -or -not (Test-Path -LiteralPath $desktopExe -PathType Leaf)) {
        Write-DLine 'ERROR Docker VMM backend or Docker Desktop tray executable was not found' 'Red'
        return $false
    }
    try {
        # Docker Desktop must own startup. A backend created with
        # -with-frontend=false rejects a later tray attachment and makes the
        # Desktop process exit even though the daemon remains healthy.
        Start-Process -FilePath $desktopExe | Out-Null
        Write-DLine 'Docker VMM and system-tray frontend launched unattended' 'Cyan'
        return $true
    } catch {
        Write-DLine ("ERROR Docker VMM/tray launch failed: {0}" -f $_.Exception.Message) 'Red'
        return $false
    }
}

function Wait-ForDaemon {
    param([string]$DockerExe, [int]$Seconds = 120)
    $deadline = (Get-Date).AddSeconds([Math]::Max(5, $Seconds))
    $lastPct = -1
    while ((Get-Date) -lt $deadline) {
        if (Test-DaemonReady -DockerExe $DockerExe -Milliseconds 500) { return $true }
        $remaining = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalSeconds)
        $pct = [Math]::Min(99, [int]((1 - ($remaining / [Math]::Max(1, $Seconds))) * 100))
        if ($pct -ne $lastPct) {
            Write-DLine ("waiting for Docker daemon... {0}% ({1}s remaining)" -f $pct, $remaining) 'DarkCyan'
            $lastPct = $pct
        }
        Start-Sleep -Milliseconds 100
    }
    return (Test-DaemonReady -DockerExe $DockerExe -Milliseconds 1000)
}

# ---------------------------------------------------------------------------
# SelfTest
# ---------------------------------------------------------------------------
if ($SelfTest) {
    Write-DLine ("elevated={0}" -f (Test-DAdmin)) 'Cyan'
    Write-DLine ("docker.exe={0}" -f (Find-DockerExe)) 'Cyan'
    Write-DLine ("default_mode={0}" -f $(if ($Preserve) { 'PRESERVING_VMM_RESTART' } else { 'DESTRUCTIVE_VMM_RESET' })) 'Cyan'
    Write-DLine ("docker_vmm_configured={0}" -f (Test-DockerVmmConfigured)) 'Cyan'
    $dockerExe = Find-DockerExe
    if ($dockerExe) { Write-DLine ("daemon_ready={0}" -f (Test-DaemonReady -DockerExe $dockerExe -Milliseconds 4000)) 'Cyan' }
    Write-DLine ("tray_frontend_ready={0}" -f (Test-DockerFrontendReady)) 'Cyan'
    Write-DLine 'SELFTEST_OK' 'Green'
    exit 0
}

# Run operational work in a detached child. The reset therefore continues even
# when its terminal is closed or Ctrl+C interrupts the waiting wrapper.
if (-not $Worker) {
    $outer = [System.Diagnostics.Stopwatch]::StartNew()
    $outerStartedUtc = [DateTime]::UtcNow
    $powerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $outFile = Join-Path 'C:\Temp' ('dkill-worker-' + [guid]::NewGuid().ToString('N') + '.out')
    $errFile = [IO.Path]::ChangeExtension($outFile, '.err')
    $childArguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath), '-Worker')
    if ($Preserve) { $childArguments += '-Preserve' }
    if ($NoRestart) { $childArguments += '-NoRestart' }
    if ($FactoryReset) { $childArguments += '-FactoryReset' }
    if (-not [string]::IsNullOrWhiteSpace($ConfirmFactoryReset)) { $childArguments += @('-ConfirmFactoryReset', $ConfirmFactoryReset) }
    try {
        $child = Start-Process -FilePath $powerShellExe -ArgumentList $childArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile -ErrorAction Stop
        if (-not $child.WaitForExit(60000)) {
            throw 'Detached Docker reset exceeded its 60-second recovery ceiling; it remains active in the background.'
        }
        $child.WaitForExit()
        if (Test-Path -LiteralPath $outFile) {
            $captured = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($captured)) { Write-Host $captured.TrimEnd() }
        }
        if (Test-Path -LiteralPath $errFile) {
            $capturedError = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($capturedError)) { Write-Error $capturedError.TrimEnd() }
        }
        $childExitCode = $null
        try { $childExitCode = [int]$child.ExitCode } catch { }
        $dockerExe = Find-DockerExe
        if ($NoRestart) {
            $postconditionPassed = -not (Test-DaemonReady -DockerExe $dockerExe -Milliseconds 500) -and -not (Test-DockerFrontendReady)
        } else {
            $postconditionPassed = (Test-DaemonReady -DockerExe $dockerExe -Milliseconds 1000) -and (Test-DockerVmmConfigured) -and (Test-DockerFrontendReady)
            if (-not $Preserve) {
                $freshDisk = Get-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'Docker\vm-data\DockerDesktop.vhdx') -Force -ErrorAction SilentlyContinue
                $postconditionPassed = $postconditionPassed -and $freshDisk -and $freshDisk.CreationTimeUtc -ge $outerStartedUtc.AddSeconds(-2)
            }
        }
        if ($null -eq $childExitCode) {
            # ShellExecute elevation can omit ExitCode even after WaitForExit. The
            # fresh live postcondition is stronger than that missing metadata.
            $childExitCode = if ($postconditionPassed) { 0 } else { 1 }
        } elseif (-not $postconditionPassed) {
            $childExitCode = 1
        }
        $outer.Stop()
        $elapsed = [math]::Round($outer.Elapsed.TotalSeconds, 2)
        Write-DLine ("END_TO_END elapsed={0}s child_exit={1} postcondition={2}" -f $elapsed, $childExitCode, $postconditionPassed) $(if ($childExitCode -eq 0 -and ($Preserve -or $elapsed -lt 10)) { 'Green' } else { 'Red' })
        if ($childExitCode -ne 0) { throw "Docker reset worker failed live postcondition verification (exit=$childExitCode)." }
        if (-not $Preserve -and $elapsed -ge 10) { throw "Docker reset completed but missed the strict under-10-second target ($elapsed seconds)." }
        return
    } finally {
        foreach ($file in @($outFile, $errFile)) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    }
}

if ($Preserve -and $FactoryReset) {
    Write-DLine 'Choose either -Preserve or the destructive reset, not both.' 'Red'
    exit 2
}

if ($Preserve) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-DLine '=== DKILL: PRESERVING DOCKER VMM RESTART START ===' 'Yellow'
    Set-DockerVmmSettings
    $dockerExe = Find-DockerExe
    if (-not $dockerExe) {
        Write-DLine 'docker.exe not found; Docker Desktop may not be installed' 'Red'
        exit 1
    }
    Stop-AllDocker
    if ($NoRestart) {
        Write-DLine 'Docker VMM stopped; Docker data and VMM settings preserved' 'Green'
        exit 0
    }
    if (-not (Start-DockerVmmWithTray)) { exit 1 }
    if (-not (Wait-ForDaemon -DockerExe $dockerExe -Seconds 20)) {
        Write-DLine 'Docker daemon did not become ready after the bounded VMM restart' 'Red'
        exit 1
    }
    if (-not (Test-DockerVmmConfigured) -or -not (Get-Process -Name 'com.docker.sailor' -ErrorAction SilentlyContinue) -or -not (Test-DockerFrontendReady)) {
        Write-DLine 'Docker answered, but the Docker VMM runtime was not active' 'Red'
        exit 1
    }
    $sw.Stop()
    Write-DLine ("=== DKILL VMM RESTART COMPLETE in {0}s; daemon and tray ready; data preserved ===" -f [math]::Round($sw.Elapsed.TotalSeconds, 2)) 'Green'
    exit 0
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$resetStartedUtc = [DateTime]::UtcNow
$freeBytesBefore = [IO.DriveInfo]::new('C').AvailableFreeSpace
$script:DKillSucceeded = $true
Write-DLine '=== DKILL: COMPLETE AUTOMATIC DOCKER WIPE START ===' 'Yellow'

# Keep the retired legacy watchdog out of the VMM wipe. These calls are kept to
# 500 ms each so an unhealthy Task Scheduler service cannot break the deadline.
$schtasks = Join-Path $env:SystemRoot 'System32\schtasks.exe'
$script:WatchdogWasEnabled = $false
if (Test-Path -LiteralPath $schtasks) {
    $null = Invoke-Bounded -FilePath $schtasks -ArgumentList @('/Change', '/TN', $script:WatchdogTask, '/DISABLE') -Milliseconds 500
    $null = Invoke-Bounded -FilePath $schtasks -ArgumentList @('/End', '/TN', $script:WatchdogTask) -Milliseconds 500
    Write-DLine 'DockerDesktopWatchdog paused for the wipe' 'Cyan'
}
try { Remove-Item -LiteralPath 'C:\Temp\Docker-WSL-HealthFix.lock' -Force -ErrorAction SilentlyContinue } catch { }

# 1) Kill everything.
Write-DLine 'stopping Docker VMM processes; privileged helper stays warm' 'Yellow'
Stop-AllDocker

# 2) Delete every Docker data location.
$preserve = @(
    (Join-Path $env:APPDATA 'Docker\settings-store.json'),
    (Join-Path $env:APPDATA 'Docker\login-info.json'),
    (Join-Path $env:USERPROFILE '.docker\config.json')
)
$holdDir = Join-Path $env:TEMP ('dkill-hold-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $holdDir -Force -ErrorAction SilentlyContinue | Out-Null
foreach ($p in $preserve) {
    if ([System.IO.File]::Exists($p)) {
        $target = Join-Path $holdDir ([System.IO.Path]::GetFileName($p))
        try { [System.IO.File]::Copy($p, $target, $true) | Out-Null } catch { }
    }
}

$targets = @(
    (Join-Path $env:ProgramData 'DockerDesktop'),           # vhdx, vm-data, service logs, settings
    (Join-Path $env:ProgramData 'Docker'),
    (Join-Path $env:LOCALAPPDATA 'Docker'),                 # wsl data/disks, buildx, logs, config
    (Join-Path $env:LOCALAPPDATA 'Docker Desktop'),
    (Join-Path $env:APPDATA 'Docker'),                      # settings/login (preserved files re-created below)
    (Join-Path $env:USERPROFILE '.docker'),                 # CLI config (preserved file re-created below)
    (Join-Path $env:USERPROFILE '.docker-desktop')
)

# Free every known Docker engine disk first. Docker VMM uses the LocalAppData
# path; the ProgramData and WSL paths are included only to remove stale data.
$vhdPaths = @(
    (Join-Path $env:LOCALAPPDATA 'Docker\vm-data\DockerDesktop.vhdx'),
    (Join-Path $env:ProgramData 'DockerDesktop\vm-data\DockerDesktop.vhdx'),
    (Join-Path $env:LOCALAPPDATA 'Docker\wsl\data\ext4.vhdx'),
    (Join-Path $env:LOCALAPPDATA 'Docker\wsl\disk\docker_data.vhdx')
) | Select-Object -Unique
$oldVhdRecords = @()
foreach ($vhdx in $vhdPaths) {
    if (-not (Test-Path -LiteralPath $vhdx -PathType Leaf)) { continue }
    $oldVhd = Get-Item -LiteralPath $vhdx -Force -ErrorAction SilentlyContinue
    if ($oldVhd) {
        $oldVhdRecords += [pscustomobject]@{ Path = $vhdx; Length = [int64]$oldVhd.Length; CreatedUtc = $oldVhd.CreationTimeUtc }
    }
    Write-DLine ("deleting Docker engine VHDX: {0}" -f $vhdx) 'Yellow'
    $vhdxGone = $false
    $vhdxDeadline = (Get-Date).AddSeconds(20)
    do {
        $null = Remove-DockerPath -Path $vhdx
        if (-not (Test-Path -LiteralPath $vhdx)) { $vhdxGone = $true; break }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $vhdxDeadline)
    if ($vhdxGone) {
        Write-DLine ("VHDX deleted - released {0:N2} GB" -f ($(if ($oldVhd) { $oldVhd.Length } else { 0 }) / 1GB)) 'Green'
    } else {
        $script:DKillSucceeded = $false
        Write-DLine ("ERROR VHDX still locked: {0}" -f $vhdx) 'Red'
    }
}

foreach ($t in $targets) {
    if (Test-Path -LiteralPath $t) {
        if (-not (Remove-DockerPath -Path $t)) { $script:DKillSucceeded = $false }
    }
}

# Temp files.
foreach ($pattern in @((Join-Path $env:windir 'Temp\*docker*'), (Join-Path $env:LOCALAPPDATA 'Temp\*docker*'))) {
    Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}

# Re-create preserved config so Docker starts without onboarding/login popups.
foreach ($p in $preserve) {
    $fileName = [System.IO.Path]::GetFileName($p)
    $held = Join-Path $holdDir $fileName
    if ([System.IO.File]::Exists($held)) {
        $dir = [System.IO.Path]::GetDirectoryName($p)
        try {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
            [System.IO.File]::Copy($held, $p, $true) | Out-Null
            Write-DLine ("preserved config {0}" -f $p) 'Green'
        } catch { }
    }
}
Set-DockerVmmSettings
try { Remove-Item -LiteralPath $holdDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-DLine 'ALL DOCKER ENGINE DATA DELETED; credentials retained for authenticated push' 'Green'

# 3) Bring Docker back on fresh data - ready to use, no delays.
if (-not $NoRestart) {
    Write-DLine 'starting fresh Docker VMM' 'Yellow'
    $null = Start-DockerVmmWithTray
    $dockerExe = Find-DockerExe
    if ($dockerExe) {
        # First wait is short; if the engine is stuck, run one full force cycle
        # (kill + VM release + relaunch) instead of passively waiting 120s.
        $becameReady = Wait-ForDaemon -DockerExe $dockerExe -Seconds 40
        if (-not $becameReady) {
            Write-DLine 'daemon slow to start - running a force cycle' 'Yellow'
            Stop-AllDocker
            $null = Start-DockerVmmWithTray
            $becameReady = Wait-ForDaemon -DockerExe $dockerExe -Seconds 80
        }
        if (Test-DaemonReady -DockerExe $dockerExe -Milliseconds 5000) {
            $version = Invoke-Bounded -FilePath $dockerExe -ArgumentList @('version', '--format', '{{.Server.Version}}') -Milliseconds 5000
            $psResult = Invoke-Bounded -FilePath $dockerExe -ArgumentList @('ps', '--format', '{{.ID}}') -Milliseconds 5000
            $containerCount = if ($psResult.ExitCode -eq 0) { @($psResult.Stdout -split "[`r`n]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count } else { -1 }
            Write-DLine ("READY - Docker daemon and system tray are running fresh. Server version: {0}; containers: {1}" -f $(if ($version.Stdout) { $version.Stdout } else { 'unknown' }), $containerCount) 'Green'
        } else {
            $script:DKillSucceeded = $false
            Write-DLine 'ERROR daemon not responding after the bounded fresh start' 'Red'
        }
    } else {
        $script:DKillSucceeded = $false
        Write-DLine 'ERROR docker.exe not found; Docker Desktop may not be installed' 'Red'
    }
    if (-not (Test-DockerVmmConfigured) -or -not (Get-Process -Name 'com.docker.sailor' -ErrorAction SilentlyContinue)) {
        $script:DKillSucceeded = $false
        Write-DLine 'ERROR fresh daemon is not running on Docker VMM' 'Red'
    }
    if (-not (Test-DockerFrontendReady)) {
        $script:DKillSucceeded = $false
        Write-DLine 'ERROR Docker daemon is ready but the system-tray frontend is missing' 'Red'
    } else {
        Write-DLine 'Docker system-tray frontend verified ready' 'Green'
    }
    $freshVhdPath = Join-Path $env:LOCALAPPDATA 'Docker\vm-data\DockerDesktop.vhdx'
    $freshVhd = Get-Item -LiteralPath $freshVhdPath -Force -ErrorAction SilentlyContinue
    if (-not $freshVhd -or $freshVhd.CreationTimeUtc -lt $resetStartedUtc.AddSeconds(-2)) {
        $script:DKillSucceeded = $false
        Write-DLine 'ERROR a newly created Docker VMM disk was not verified' 'Red'
    } else {
        Write-DLine ("fresh VMM disk verified: {0:N2} GB, created {1:o}" -f ($freshVhd.Length / 1GB), $freshVhd.CreationTimeUtc) 'Green'
    }
} else {
    Write-DLine 'NoRestart mode: wipe complete, Docker Desktop NOT started' 'Cyan'
}

# The old WSL/Hyper-V watchdog remains retired; normal Docker commands use the
# bounded VMM-aware wrapper when recovery is actually needed.
if (Test-Path -LiteralPath $schtasks) {
    $null = Invoke-Bounded -FilePath $schtasks -ArgumentList @('/Change', '/TN', $script:WatchdogTask, '/DISABLE') -Milliseconds 500
    Write-DLine 'DockerDesktopWatchdog left disabled' 'Cyan'
}

$sw.Stop()
$freeBytesAfter = [IO.DriveInfo]::new('C').AvailableFreeSpace
$netFreedGiB = ($freeBytesAfter - $freeBytesBefore) / 1GB
Write-DLine ("C drive net free-space change: {0:N2} GB" -f $netFreedGiB) $(if ($netFreedGiB -ge 0) { 'Green' } else { 'Yellow' })
if (-not $script:DKillSucceeded) {
    Write-DLine ("=== DKILL FAILED after {0}s ===" -f [math]::Round($sw.Elapsed.TotalSeconds, 2)) 'Red'
    exit 1
}
Write-DLine ("=== DKILL COMPLETE in {0}s ===" -f [math]::Round($sw.Elapsed.TotalSeconds, 2)) 'Green'
exit 0
