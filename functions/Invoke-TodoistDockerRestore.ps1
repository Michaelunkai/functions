[CmdletBinding()]
param([switch]$SelfTest, [ValidateRange(30,3600)][int]$SignInTimeoutSeconds = 900)

$ErrorActionPreference = 'Stop'
$root = 'F:\backup\windowsapps\installed'
$target = Join-Path $root 'todoist'
$dockerExe = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
# Pull the app and Windows-user-encrypted recovery from Docker Hub.
$image = 'michadockermisha/todoist:8'
$relativeExe = 'Package\9.30.0\app\Todoist.exe'
$profileRelative = 'UserData\Roaming\Todoist'
$id = [guid]::NewGuid().ToString('N')
$stage = Join-Path $root ('.todoist-stage-' + $id)
$previous = Join-Path $root ('.docker-previous-todoist-' + $id)
$container = 'todoist-restore-' + $id
$created = $false
$replaced = $false
$stopped = $false

function Assert-TodoistChild([string]$Path) {
    if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path)) -ne $root) {
        throw "Todoist path escaped the install root: $Path"
    }
}
function Get-OwnedTodoist {
    @(Get-Process -Name Todoist -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path.StartsWith($target + '\', [StringComparison]::OrdinalIgnoreCase)
    })
}
function Start-TodoistAndWait {
    $launcher = Join-Path $target 'Launch-Todoist.ps1'
    $exe = Join-Path $target $relativeExe
    if (-not [IO.File]::Exists($launcher) -or -not [IO.File]::Exists($exe)) {
        throw 'The Todoist payload is incomplete: executable or launcher missing.'
    }
    # Run the profile-aware launcher in a separate process.
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $launch = Start-Process -FilePath $ps -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $launcher) -WindowStyle Hidden -PassThru
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $deadline = (Get-Date).AddSeconds(90)
    $waitingForSignIn = $false
    do {
        $window = Get-OwnedTodoist | Where-Object { $_.MainWindowHandle -ne 0 -and $_.Responding } | Select-Object -First 1
        if ($window) {
            $element = [Windows.Automation.AutomationElement]::FromHandle($window.MainWindowHandle)
            $nodes = $element.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
            $names = @($nodes | ForEach-Object { $_.Current.Name } | Where-Object { $_ })
            # A running process or a generic window title alone is not login proof.
            $hasInbox = @($names | Where-Object { $_ -match '^Inbox(?:\s|$)' }).Count -gt 0
            $hasNavigation = @($names | Where-Object { $_ -match '^(Today|Upcoming|Add task)(?:\s|$)' }).Count -gt 0
            if ($hasInbox -and $hasNavigation) {
                Write-Host "TODOIST_READY logged_in=true pid=$($window.Id) profile=preserved" -ForegroundColor Green
                return
            }
            if (@($names | Where-Object { $_ -match '^(Log in|Log into Todoist|Continue with Google|Continue with Apple)$' }).Count -gt 0) {
                if (-not $waitingForSignIn) {
                    $waitingForSignIn = $true
                    $deadline = (Get-Date).AddSeconds($SignInTimeoutSeconds)
                    Write-Host 'TODOIST_WAITING_FOR_SIGN_IN: Complete sign-in in the open app. This command will keep checking and return success only after your task navigation appears.'
                }
            }
        }
        if ($launch.HasExited -and $launch.ExitCode -ne 0) { throw "Todoist launcher failed with exit $($launch.ExitCode)." }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    throw 'Todoist signed-in readiness was not verified before the deadline. The app and saved profile are preserved; no success was reported.'
}

foreach ($path in @($target, $stage, $previous)) { Assert-TodoistChild $path }
if (-not [IO.File]::Exists($dockerExe)) { throw 'Docker Desktop CLI is missing.' }
if ($SelfTest) {
    $installedExecutables = @(Get-ChildItem -LiteralPath (Join-Path $target 'Package') -Directory -ErrorAction Stop | ForEach-Object { Join-Path $_.FullName 'app\Todoist.exe' } | Where-Object { [IO.File]::Exists($_) })
    if ($installedExecutables.Count -ne 1) { throw 'Todoist executable missing or ambiguous.' }
    if (-not [IO.Directory]::Exists((Join-Path $target $profileRelative))) { throw 'Todoist profile missing.' }
    Write-Output 'TODOIST_SELFTEST_OK executable=true profile=true'
    return
}

try {
    # Verify the saved authentication before replacing or reopening the app.
    $nodeExe = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    if (-not $nodeExe) { $nodeExe = 'C:\Users\micha\AppData\Local\OpenAI\Codex\runtimes\cua_node\b474a88d5d105afa\bin\node.exe' }
    if (-not [IO.File]::Exists($nodeExe)) { throw 'Node.js is required to verify Todoist sign-in before opening the app.' }
    $sessionHelper = Join-Path $PSScriptRoot 'Test-TodoistSavedSession.cjs'
    & $nodeExe $sessionHelper $target --probe
    $localSessionValid = $LASTEXITCODE -eq 0
    $settingsPath = Join-Path $env:APPDATA 'Docker\settings-store.json'
    if ([IO.File]::Exists($settingsPath) -and (Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json).WslEngineEnabled) {
        throw 'Docker is configured for WSL; this command requires the existing Docker VMM setup.'
    }
    & $dockerExe info --format '{{.ServerVersion}}' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe' -WindowStyle Hidden
        $deadline = (Get-Date).AddSeconds(120)
        do {
            Start-Sleep -Seconds 2
            & $dockerExe info --format '{{.ServerVersion}}' | Out-Null
            if ($LASTEXITCODE -eq 0) { break }
        } while ((Get-Date) -lt $deadline)
        if ($LASTEXITCODE -ne 0) { throw 'Docker VMM did not become ready.' }
    }
    if (-not (Get-Command Get-BackupDockerLatestRemoteTag -ErrorAction SilentlyContinue)) {
        Import-Module 'C:\Users\micha\Documents\WindowsPowerShell\Modules\CodexProfileFunctions\CodexProfileFunctions.psd1' -Force -DisableNameChecking
        Initialize-CodexProfileFunctions
    }
    $tag = [string](Get-BackupDockerLatestRemoteTag -RepoSlug todoist | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($tag)) { throw 'Todoist Docker Hub repository has no tags.' }
    $image = 'michadockermisha/todoist:' + $tag.Trim()
    Write-Host "TODOIST_PROGRESS stage=pulling-from-dockerhub image=$image"
    & $dockerExe pull $image | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Todoist Docker Hub pull failed; existing app retained.' }
    $labelJson = & $dockerExe image inspect --format '{{json .Config.Labels}}' $image
    if ($LASTEXITCODE -ne 0) { throw 'Todoist image metadata lookup failed.' }
    $publishedExe = [string](($labelJson | ConvertFrom-Json).'backup.app.executable')
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($publishedExe) -or $publishedExe -eq '<no value>') {
        throw 'The Todoist Hub image is missing its app executable label; existing app retained.'
    }
    $publishedExe = $publishedExe.Replace('/','\')
    if ([IO.Path]::IsPathRooted($publishedExe) -or $publishedExe -match '(^|\\)\.\.?(\\|$)' -or $publishedExe -notlike 'Package\*\app\Todoist.exe') {
        throw 'Invalid Todoist executable path in Docker image metadata.'
    }
    $relativeExe = $publishedExe

    Write-Host 'TODOIST_PROGRESS stage=preserving-current-session'
    $owned = Get-OwnedTodoist
    foreach ($process in $owned) { if ($process.MainWindowHandle -ne 0) { [void]$process.CloseMainWindow() } }
    if ($owned.Count) { Start-Sleep -Seconds 3 }
    Get-OwnedTodoist | Stop-Process -Force -ErrorAction Stop
    $stopped = $true
    if ($localSessionValid) {
        & $nodeExe $sessionHelper $target --save
        if ($LASTEXITCODE -ne 0) { Write-Warning 'Local recovery store could not be updated; retaining the current profile and Docker Hub recovery.' }
    }
    Write-Host 'TODOIST_PROGRESS stage=restoring-complete-payload'
    $containerId = & $dockerExe create --name $container $image
    if ($LASTEXITCODE -ne 0 -or -not $containerId) { throw 'Todoist restore container creation failed.' }
    $created = $true
    [void][IO.Directory]::CreateDirectory($stage)
    & $dockerExe cp ($container + ':/home/.') $stage | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Todoist Docker copy failed.' }
    if (-not [IO.File]::Exists((Join-Path $stage $relativeExe))) { throw 'Docker snapshot has no Todoist executable.' }
    # Current profile wins over the snapshot: never roll back login or unsynced data.
    $currentData = Join-Path $target 'UserData'
    if ($localSessionValid -and [IO.Directory]::Exists($currentData)) {
        if ((Get-Item -LiteralPath $currentData -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing redirected Todoist session data.' }
        & "$env:SystemRoot\System32\robocopy.exe" $currentData (Join-Path $stage 'UserData') /MIR /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw 'Todoist current profile copy failed; original retained.' }
    }
    if (-not [IO.File]::Exists((Join-Path $stage ($profileRelative + '\session.json')))) {
        $sessionRestored = $false
        if ($localSessionValid) {
            & $nodeExe $sessionHelper $target --restore $stage
            $sessionRestored = $LASTEXITCODE -eq 0
        }
        if (-not $sessionRestored) {
            Write-Host 'TODOIST_PROGRESS stage=recovering-windows-encrypted-session-from-dockerhub'
            & $dockerExe cp ($container + ':/recovery/todoist-session.dpapi') (Join-Path $stage '.todoist-session.dpapi') | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'Docker Hub image does not contain the encrypted Todoist recovery payload.' }
            & $nodeExe $sessionHelper $target --recover $stage
            if ($LASTEXITCODE -ne 0) { throw 'Docker Hub sign-in recovery could not be verified for this Windows account; existing app retained.' }
        }
    }
    & $nodeExe $sessionHelper $target --check-stage $stage
    if ($LASTEXITCODE -ne 0) { throw 'Staged Todoist sign-in is not verified; existing app retained.' }
    if ([IO.Directory]::Exists($target)) {
        if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing to replace a redirected Todoist directory.' }
        [IO.Directory]::Move($target, $previous)
    }
    try { [IO.Directory]::Move($stage, $target); $replaced = $true }
    catch { if ([IO.Directory]::Exists($previous)) { [IO.Directory]::Move($previous, $target) }; throw }
    Write-Host 'TODOIST_PROGRESS stage=opening-and-checking-signed-in-app'
    Start-TodoistAndWait
    & $nodeExe (Join-Path $PSScriptRoot 'Test-TodoistSavedSession.cjs') $target --check
    if ($LASTEXITCODE -ne 0) { throw 'App opened, but post-launch session validation failed; previous files retained.' }
    if ([IO.Directory]::Exists($previous)) {
        Assert-TodoistChild $previous
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $previous -Recurse -Force -ErrorAction Stop
    }
} catch {
    if ($stopped -and -not $replaced -and [IO.File]::Exists((Join-Path $target $relativeExe))) {
        try { Start-TodoistAndWait } catch { Write-Warning 'Original Todoist retained; automatic relaunch could not be verified.' }
    }
    throw
} finally {
    if ($created) { & $dockerExe rm $container | Out-Null }
    if ([IO.Directory]::Exists($stage)) {
        Assert-TodoistChild $stage
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $stage -Recurse -Force
    }
}
