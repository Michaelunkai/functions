$ErrorActionPreference = 'Stop'
$helperPath = 'F:\study\Platforms\windows\functions\Register-InstalledAppDockerFunction.ps1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    throw "Installed-app registration helper not found: $helperPath"
}
& $helperPath @args
