$script:InstalledAppRestoreHelper = 'F:\study\Platforms\windows\functions\Invoke-InstalledAppDockerRestoreAndLaunch.ps1'
$script:InstalledAppRegisterHelper = 'F:\study\Platforms\windows\functions\Register-InstalledAppDockerFunction.ps1'
$script:InstalledAppRestoreFolders = @(
    'CodexMonitor',
    'WhisperKeyLocal',
    'Whisper',
    'tv',
    'reflect',
    'FlareSolverr',
    'Obsidian',
    'telegram',
    'Prowlarr',
    'cloudflare',
    'Jackett',
    'kvrt',
    'scoop',
    'BleachBitAutoClean',
    'tailscale',
    'Process Lasso',
    'OpenSpeedy',
    'gamesavemanager',
    'adw',
    'Everything',
    'qBittorrentSearchPluginsWiki',
    'qBittorrentSearchPlugins'
)
$customCatalogPath = Join-Path $PSScriptRoot 'InstalledAppRestoreCatalog.json'
if (Test-Path -LiteralPath $customCatalogPath -PathType Leaf) {
    $script:InstalledAppRestoreFolders += @((Get-Content -LiteralPath $customCatalogPath -Raw | ConvertFrom-Json) | ForEach-Object { [string]$_.Folder })
    $script:InstalledAppRestoreFolders = @($script:InstalledAppRestoreFolders | Select-Object -Unique)
}
foreach ($installedAppFolder in $script:InstalledAppRestoreFolders) {
    $installedAppFunctionName = 'g' + ($installedAppFolder -replace '[^A-Za-z0-9]', '')
    $capturedFolder = $installedAppFolder
    $capturedHelper = $script:InstalledAppRestoreHelper
    $installedAppFunction = {
        & $capturedHelper -Folder $capturedFolder @args
    }.GetNewClosure()
    Remove-Item -LiteralPath ('Function:\global:' + $installedAppFunctionName) -Force -ErrorAction SilentlyContinue
    Set-Item -LiteralPath ('Function:\global:' + $installedAppFunctionName) -Value $installedAppFunction -Force
}
$capturedRegisterHelper = $script:InstalledAppRegisterHelper
$capturedLoaderPath = $PSCommandPath
$gappFunction = {
    & $capturedRegisterHelper @args
    . $capturedLoaderPath
}.GetNewClosure()
Remove-Item -LiteralPath 'Function:\global:gapp' -Force -ErrorAction SilentlyContinue
Set-Item -LiteralPath 'Function:\global:gapp' -Value $gappFunction -Force