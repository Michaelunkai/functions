[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath
)

$ErrorActionPreference = 'Stop'

$quietLauncher = 'C:\Users\micha\.claude\scripts\trayquiet-start.vbs'
if (-not (Test-Path -LiteralPath $quietLauncher)) {
    throw "Quiet startup launcher not found: $quietLauncher"
}

$wscriptExe = Join-Path $env:SystemRoot 'System32\wscript.exe'
if (-not (Test-Path -LiteralPath $wscriptExe)) {
    throw "Windows Script Host executable not found: $wscriptExe"
}

& $wscriptExe //B //Nologo $quietLauncher $TargetPath 30 0 25
