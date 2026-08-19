[CmdletBinding()]
param(
    [switch]$NoBrowser,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $root 'src\Common.psm1') -Force
Import-Module (Join-Path $root 'src\Network.psm1') -Force
Import-Module (Join-Path $root 'src\Validation.psm1') -Force

$configPath = Join-Path $root 'state\best-runtime-config.json'
$config = Read-Json -Path $configPath
if (-not $config) {
    throw "No runtime config exists. Run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$root\Install-Or-Update-LocalAI.ps1`" -Auto"
}

if ($ValidateOnly) {
    Invoke-LocalAIValidation -RuntimeConfig $config -DoNotStart
    exit 0
}

Assert-PortAvailable -Port ([int]$config.Port) | Out-Null
$proc = Start-LocalAIServerProcess -RuntimeConfig $config
Write-Host ("Local AI server started on http://0.0.0.0:{0}/v1 PID={1}" -f $config.Port, $proc.Id)
Wait-LocalAIHealth -Port ([int]$config.Port) | Out-Null
Write-Host ("Ready: http://127.0.0.1:{0}/v1" -f $config.Port)
if (-not $NoBrowser) {
    Write-Host 'Press Ctrl+C to stop.'
}
while (-not $proc.HasExited) {
    Start-Sleep -Seconds 2
}
