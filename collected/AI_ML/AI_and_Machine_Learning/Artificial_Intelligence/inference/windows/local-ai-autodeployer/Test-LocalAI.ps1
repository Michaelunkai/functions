[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$DiscoveryOnly,
    [switch]$NoNetworkMutation
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($SelfTest) {
    & (Join-Path $root 'Install-Or-Update-LocalAI.ps1') -SelfTest -SkipMutation:$($NoNetworkMutation.IsPresent)
    exit $LASTEXITCODE
}

if ($DiscoveryOnly) {
    & (Join-Path $root 'Install-Or-Update-LocalAI.ps1') -DiscoveryOnly -SkipMutation:$($NoNetworkMutation.IsPresent)
    exit $LASTEXITCODE
}

& (Join-Path $root 'Start-LocalAI.ps1') -ValidateOnly
exit $LASTEXITCODE
