$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'scripts\AgentControlCredential.ps1')
$apiUrl = [Environment]::GetEnvironmentVariable('AgentControl__ApiUrl', 'User')
$ownerToken = Read-AgentControlOwnerToken
$hookSecret = Initialize-AgentControlHookSecret
$legacyOwnerToken = [Environment]::GetEnvironmentVariable('AgentControl__OwnerToken', 'User')
if ([string]::IsNullOrWhiteSpace($ownerToken) -and -not [string]::IsNullOrWhiteSpace($legacyOwnerToken)) {
    Write-AgentControlOwnerToken -Token $legacyOwnerToken
    $ownerToken = $legacyOwnerToken
}
if (-not [string]::IsNullOrWhiteSpace($legacyOwnerToken)) {
    [Environment]::SetEnvironmentVariable('AgentControl__OwnerToken', $null, 'User')
}
Remove-Item Env:AgentControl__OwnerToken -ErrorAction SilentlyContinue
Remove-Item Env:AgentControl__HookSecret -ErrorAction SilentlyContinue
if ([string]::IsNullOrWhiteSpace($apiUrl) -or [string]::IsNullOrWhiteSpace($ownerToken)) {
    throw 'Agent Control user connection settings are unavailable.'
}

# Scheduled tasks inherit a stale environment snapshot. Load the durable user
# values every launch so sync and transcript mirroring do not silently stop.
$env:AgentControl__ApiUrl = $apiUrl.TrimEnd('/')
Set-Location $root
& (Get-Command node.exe -ErrorAction Stop).Source (Join-Path $root 'dist\server.js')
exit $LASTEXITCODE
