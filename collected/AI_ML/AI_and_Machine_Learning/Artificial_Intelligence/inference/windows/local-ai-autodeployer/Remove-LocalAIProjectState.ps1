[CmdletBinding(SupportsShouldProcess=$true)]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$targets = @('state','runtime','models','downloads','reports','logs') | ForEach-Object { Join-Path $root $_ }
foreach ($target in $targets) {
    if (Test-Path -LiteralPath $target) {
        if ($Force -or $PSCmdlet.ShouldProcess($target, 'Remove project-local generated state')) {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
    }
}
New-Item -ItemType Directory -Force -Path $targets | Out-Null
Write-Host "Project-local state reset under $root"
