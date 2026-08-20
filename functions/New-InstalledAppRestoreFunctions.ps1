[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$functionRoot = 'F:\study\Platforms\windows\functions'
$helperPath = Join-Path $functionRoot 'Invoke-InstalledAppDockerRestoreAndLaunch.ps1'
$folders = @(
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
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    throw "Restore helper not found: $helperPath"
}

foreach ($folder in $folders) {
    $functionName = 'g' + ($folder -replace '[^A-Za-z0-9]', '')
    $scriptPath = Join-Path $functionRoot ($functionName + '.ps1')
    $escapedFolder = $folder.Replace("'", "''")
    $content = @"
`$ErrorActionPreference = 'Stop'
`$helperPath = '$helperPath'
if (-not (Test-Path -LiteralPath `$helperPath -PathType Leaf)) {
    throw "Installed-app restore helper not found: `$helperPath"
}
& `$helperPath -Folder '$escapedFolder' @args
"@
    [IO.File]::WriteAllText($scriptPath, $content, (New-Object Text.UTF8Encoding($false)))
}
$loaderPath = Join-Path $functionRoot 'InstalledAppRestoreFunctions.ps1'
$loader = @"
`$script:InstalledAppRestoreHelper = '$helperPath'
`$script:InstalledAppRegisterHelper = 'F:\study\Platforms\windows\functions\Register-InstalledAppDockerFunction.ps1'
`$script:InstalledAppRestoreFolders = @(
$(($folders | ForEach-Object { "    '" + $_.Replace("'", "''") + "'" }) -join ",`r`n")
)
`$customCatalogPath = Join-Path `$PSScriptRoot 'InstalledAppRestoreCatalog.json'
if (Test-Path -LiteralPath `$customCatalogPath -PathType Leaf) {
    `$script:InstalledAppRestoreFolders += @((Get-Content -LiteralPath `$customCatalogPath -Raw | ConvertFrom-Json) | ForEach-Object { [string]`$_.Folder })
    `$script:InstalledAppRestoreFolders = @(`$script:InstalledAppRestoreFolders | Select-Object -Unique)
}
foreach (`$installedAppFolder in `$script:InstalledAppRestoreFolders) {
    `$installedAppFunctionName = 'g' + (`$installedAppFolder -replace '[^A-Za-z0-9]', '')
    `$capturedFolder = `$installedAppFolder
    `$capturedHelper = `$script:InstalledAppRestoreHelper
    `$installedAppFunction = {
        & `$capturedHelper -Folder `$capturedFolder @args
    }.GetNewClosure()
    Remove-Item -LiteralPath ('Function:\global:' + `$installedAppFunctionName) -Force -ErrorAction SilentlyContinue
    Set-Item -LiteralPath ('Function:\global:' + `$installedAppFunctionName) -Value `$installedAppFunction -Force
}
`$capturedRegisterHelper = `$script:InstalledAppRegisterHelper
`$capturedLoaderPath = `$PSCommandPath
`$gappFunction = {
    & `$capturedRegisterHelper @args
    . `$capturedLoaderPath
}.GetNewClosure()
Remove-Item -LiteralPath 'Function:\global:gapp' -Force -ErrorAction SilentlyContinue
Set-Item -LiteralPath 'Function:\global:gapp' -Value `$gappFunction -Force
"@
[IO.File]::WriteAllText($loaderPath, $loader, (New-Object Text.UTF8Encoding($false)))

Write-Output "INSTALLED_APP_FUNCTION_FILES_OK count=$($folders.Count) loader=$loaderPath"
