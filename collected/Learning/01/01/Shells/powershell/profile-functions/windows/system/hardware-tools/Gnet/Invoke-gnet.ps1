[CmdletBinding()]
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
$wingetPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
if (-not (Test-Path -LiteralPath $wingetPath -PathType Leaf)) {
    $wingetPath = Get-ChildItem 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe' -File -ErrorAction SilentlyContinue |
        Sort-Object { [version]$_.Directory.Name.Split('_')[1] } -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if ($SelfTest) {
    Write-Output ("GNET_SELFTEST_OK winget={0} versions=6,7,8,9,10,Preview progress=plain-text" -f [bool](Test-Path -LiteralPath $wingetPath -PathType Leaf))
    return
}

if (-not (Test-Path -LiteralPath $wingetPath -PathType Leaf)) { throw 'gnet requires winget.exe, but App Installer is not available.' }
$common = @('--silent','--accept-source-agreements','--accept-package-agreements','--disable-interactivity')
$packages = New-Object 'Collections.Generic.List[string]'
foreach ($version in @('6','7','8','9','10')) {
    [void]$packages.Add("Microsoft.DotNet.SDK.$version")
    [void]$packages.Add("Microsoft.DotNet.DesktopRuntime.$version")
    [void]$packages.Add("Microsoft.DotNet.AspNetCore.$version")
}
foreach ($preview in @('Microsoft.DotNet.SDK.Preview','Microsoft.DotNet.DesktopRuntime.Preview','Microsoft.DotNet.AspNetCore.Preview')) {
    [void]$packages.Add($preview)
}
foreach ($year in @('2005','2008','2010','2012','2013','2015+')) {
    foreach ($arch in @('x86','x64')) { [void]$packages.Add("Microsoft.VCRedist.$year.$arch") }
}
[void]$packages.Add('Microsoft.DirectX')

$total = $packages.Count
$index = 0
$failures = New-Object 'Collections.Generic.List[string]'
$installedText = @(& $wingetPath list --accept-source-agreements --disable-interactivity 2>$null) -join "`n"
foreach ($package in $packages) {
    $index++
    Write-Host ("GNET_PROGRESS step={0}/{1} package={2}" -f $index,$total,$package) -ForegroundColor Cyan
    $packagePattern = '(?im)(^|\s)' + [regex]::Escape($package) + '(\s|$)'
    if ($installedText -match $packagePattern) {
        Write-Host ("GNET_OK step={0}/{1} package={2} state=already-installed" -f $index,$total,$package) -ForegroundColor Green
        continue
    }
    & $wingetPath install --id $package --exact @common
    $installExit = $LASTEXITCODE
    if ($installExit -ne 0) {
        $verifyText = @(& $wingetPath list --id $package --exact --accept-source-agreements --disable-interactivity 2>$null) -join "`n"
        $verifyExit = $LASTEXITCODE
        if ($verifyExit -eq 0 -and $verifyText -match $packagePattern) {
            Write-Host ("GNET_OK step={0}/{1} package={2} state=already-present" -f $index,$total,$package) -ForegroundColor Green
            continue
        }
        [void]$failures.Add("$package exit=$installExit")
    }
}

if ($failures.Count -gt 0) {
    throw ("gnet failed packages: " + ($failures -join '; '))
}
Write-Host ("GNET_OK packages={0}" -f $total) -ForegroundColor Green
