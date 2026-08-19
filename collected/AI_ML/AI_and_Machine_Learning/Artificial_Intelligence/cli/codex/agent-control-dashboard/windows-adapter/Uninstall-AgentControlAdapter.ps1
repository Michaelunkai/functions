param([switch]$RemoveCredentials)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$credentialScript = Join-Path $root "scripts\AgentControlCredential.ps1"
if (Test-Path -LiteralPath $credentialScript) {
    . $credentialScript
}
$taskName = "AgentControlWindowsAdapter"
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}
if ($RemoveCredentials) {
    [Environment]::SetEnvironmentVariable("AgentControl__ApiUrl", $null, "User")
    [Environment]::SetEnvironmentVariable("AgentControl__OwnerToken", $null, "User")
    if (Get-Command Remove-AgentControlOwnerToken -ErrorAction SilentlyContinue) {
        Remove-AgentControlOwnerToken
    }
    if (Get-Command Remove-AgentControlHookSecret -ErrorAction SilentlyContinue) {
        Remove-AgentControlHookSecret
    }
}
Write-Output "Adapter task removed. Existing Codex hooks were left unchanged for preserve-first cleanup."
