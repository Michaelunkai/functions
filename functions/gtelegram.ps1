[CmdletBinding()]
param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'
$root = 'F:\backup\windowsapps\installed'
$target = Join-Path $root 'telegram'
$docker = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
$id = [guid]::NewGuid().ToString('N')
$stage = Join-Path $root ('.telegram-stage-' + $id)
$previous = Join-Path $root ('.telegram-previous-' + $id)
$container = 'telegram-restore-' + $id
$created = $false
$replaced = $false

function Assert-TelegramPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetDirectoryName($full) -ne $root -or
        [IO.Path]::GetFileName($full) -notmatch '^(telegram|\.telegram-(stage|previous)-[a-f0-9]{32})$') { throw 'Unsafe Telegram restore path.' }
    if (Test-Path -LiteralPath $full) {
        if ((Get-Item -LiteralPath $full -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Redirected Telegram restore path.' }
    }
}
function Get-OwnedTelegram {
    @(Get-Process -Name Telegram -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.Equals((Join-Path $target 'Telegram.exe'), [StringComparison]::OrdinalIgnoreCase) })
}
function Stop-OwnedTelegram {
    if (@(Get-OwnedTelegram).Count) {
        $quit = Start-Process -FilePath (Join-Path $target 'Telegram.exe') -ArgumentList ('-workdir "{0}" -quit' -f $target) -WorkingDirectory $target -WindowStyle Hidden -PassThru
        $deadline = (Get-Date).AddSeconds(15)
        while (@(Get-OwnedTelegram).Count -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
        if (@(Get-OwnedTelegram).Count) { throw 'Telegram did not close cleanly; its session was not replaced.' }
    }
}
function Expand-TelegramRecovery([string]$EncryptedFile, [string]$Destination) {
    Add-Type -AssemblyName System.Security
    Add-Type -AssemblyName System.IO.Compression
    $clear = $null; $stream = $null; $archive = $null
    try {
        # No registry record or old installation is required. DPAPI binds this backup to this Windows account.
        $clear = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($EncryptedFile), $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        $stream = [IO.MemoryStream]::new($clear, $false)
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read)
        $prefix = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
        $seen = @{}
        $bytes = [long]0
        foreach ($entry in $archive.Entries) {
            $relative = $entry.FullName.Replace('/', '\')
            $full = [IO.Path]::GetFullPath((Join-Path $Destination $relative))
            if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|\\)\.\.?($|\\)|:' -or
                -not $relative.StartsWith('tdata\', [StringComparison]::OrdinalIgnoreCase) -or
                -not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or $seen.ContainsKey($full)) { throw 'Invalid Telegram recovery archive path.' }
            $seen[$full] = $true
            $bytes += $entry.Length
            if ($bytes -gt 2GB -or $seen.Count -gt 100000) { throw 'Telegram recovery archive is too large.' }
        }
        if (-not @($archive.Entries | Where-Object { $_.FullName -match '^tdata/key_data[01s]?$' }).Count) { throw 'Telegram recovery has no session key file.' }
        foreach ($entry in $archive.Entries) {
            $full = [IO.Path]::GetFullPath((Join-Path $Destination ($entry.FullName.Replace('/', '\'))))
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full))
            $input = $entry.Open(); $output = [IO.File]::Open($full, [IO.FileMode]::CreateNew)
            try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
        }
    } finally {
        if ($archive) { $archive.Dispose() }; if ($stream) { $stream.Dispose() }
        if ($clear) { [Array]::Clear($clear, 0, $clear.Length) }
    }
}
function Start-AndVerifyTelegram {
    Start-Process -FilePath (Join-Path $target 'Telegram.exe') -ArgumentList ('-workdir "{0}"' -f $target) -WorkingDirectory $target | Out-Null
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $deadline = (Get-Date).AddSeconds(90)
    $stableSince = $null
    do {
        $ready = $false
        $window = Get-OwnedTelegram | Where-Object { $_.MainWindowHandle -ne 0 -and $_.Responding } | Select-Object -First 1
        if ($window) {
            $element = [Windows.Automation.AutomationElement]::FromHandle($window.MainWindowHandle)
            $nodes = $element.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
            $search = @($nodes | Where-Object { $_.Current.Name -eq 'Search' -and $_.Current.ControlType -eq [Windows.Automation.ControlType]::Edit -and $_.Current.IsEnabled -and -not $_.Current.IsOffscreen }).Count
            $chats = @($nodes | Where-Object { $_.Current.Name -eq 'Chats' -and $_.Current.ControlType -eq [Windows.Automation.ControlType]::List -and -not $_.Current.IsOffscreen }).Count
            $login = @($nodes | Where-Object { $_.Current.Name -match '^(Start Messaging|Your Phone Number|Log in by QR Code|Enter.*passcode|Connecting|Updating)' }).Count
            if ($search -and $chats -and -not $login) {
                $connections = @(& "$env:SystemRoot\System32\netstat.exe" -ano -p tcp | Where-Object { $_ -match ('\sESTABLISHED\s+' + $window.Id + '\s*$') }).Count
                $ready = $connections -gt 0
            }
        }
        if ($ready) {
            if (-not $stableSince) { $stableSince = Get-Date }
            if (((Get-Date) - $stableSince).TotalSeconds -ge 5) { Write-Output "TELEGRAM_READY logged_in=true connected=true pid=$($window.Id)"; return }
        } else { $stableSince = $null }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    throw 'Telegram signed-in Chats and network connection were not verified. Saved session files are retained.'
}

foreach ($path in @($target, $stage, $previous)) { Assert-TelegramPath $path }
try {
    $settings = Join-Path $env:APPDATA 'Docker\settings-store.json'
    if ((Test-Path -LiteralPath $settings) -and (Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json).WslEngineEnabled) { throw 'Telegram restore requires Docker VMM, not WSL.' }
    & $docker info --format '{{.ServerVersion}}' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe' -WindowStyle Hidden
        $deadline = (Get-Date).AddSeconds(120)
        do { Start-Sleep -Seconds 2; & $docker info --format '{{.ServerVersion}}' | Out-Null } while ($LASTEXITCODE -ne 0 -and (Get-Date) -lt $deadline)
        if ($LASTEXITCODE -ne 0) { throw 'Docker VMM did not become ready.' }
    }
    if (-not (Get-Command Get-BackupDockerLatestRemoteTag -ErrorAction SilentlyContinue)) {
        Import-Module 'C:\Users\micha\Documents\WindowsPowerShell\Modules\CodexProfileFunctions\CodexProfileFunctions.psd1' -Force -DisableNameChecking
        Initialize-CodexProfileFunctions
    }
    $tag = [string](Get-BackupDockerLatestRemoteTag -RepoSlug telegram | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($tag)) { throw 'Telegram Docker Hub repository has no tags.' }
    $image = 'michadockermisha/telegram:' + $tag.Trim()
    Write-Host "TELEGRAM_PROGRESS stage=pulling-from-dockerhub image=$image"
    & $docker pull $image | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Telegram Docker Hub pull failed.' }
    $containerId = & $docker create --name $container $image
    if ($LASTEXITCODE -ne 0 -or -not $containerId) { throw 'Telegram restore container creation failed.' }
    $created = $true
    [void][IO.Directory]::CreateDirectory($stage)
    & $docker cp ($container + ':/home/.') $stage | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Telegram app copy failed.' }
    $exe = Join-Path $stage 'Telegram.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf) -or (Get-AuthenticodeSignature -LiteralPath $exe).Status -ne 'Valid') { throw 'Telegram app signature is not valid.' }
    $encrypted = Join-Path $stage '.telegram-session.dpapi'
    & $docker cp ($container + ':/recovery/tdata.dpapi') $encrypted | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Telegram Hub image lacks Windows-encrypted sign-in recovery.' }
    Expand-TelegramRecovery $encrypted $stage
    Remove-Item -LiteralPath $encrypted -Force
    if ($SelfTest) { Write-Output "TELEGRAM_SELFTEST_OK image=$image executable=true encrypted_session=true"; return }
    Stop-OwnedTelegram
    $currentData = Join-Path $target 'tdata'
    if (Test-Path -LiteralPath $currentData -PathType Container) {
        if (@(Get-ChildItem -LiteralPath $currentData -Force -Recurse | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -or
            ((Get-Item -LiteralPath $currentData -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Redirected Telegram session data.' }
        & "$env:SystemRoot\System32\robocopy.exe" $currentData (Join-Path $stage 'tdata') /MIR /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw 'Current Telegram session copy failed.' }
    }
    if (Test-Path -LiteralPath $target) { [IO.Directory]::Move($target, $previous) }
    try { [IO.Directory]::Move($stage, $target); $replaced = $true }
    catch { if (Test-Path -LiteralPath $previous) { [IO.Directory]::Move($previous, $target) }; throw }
    Start-AndVerifyTelegram
    if (Test-Path -LiteralPath $previous) { Assert-TelegramPath $previous; Microsoft.PowerShell.Management\Remove-Item -LiteralPath $previous -Recurse -Force }
} finally {
    if ($created) { & $docker rm $container | Out-Null }
    if (Test-Path -LiteralPath $stage) { Assert-TelegramPath $stage; Microsoft.PowerShell.Management\Remove-Item -LiteralPath $stage -Recurse -Force }
}
