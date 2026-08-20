$ErrorActionPreference = 'Stop'
$helperPath = 'F:\study\Platforms\windows\functions\Invoke-InstalledAppDockerRestoreAndLaunch.ps1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    throw "Installed-app restore helper not found: $helperPath"
}
& $helperPath -Folder 'scoop' @args