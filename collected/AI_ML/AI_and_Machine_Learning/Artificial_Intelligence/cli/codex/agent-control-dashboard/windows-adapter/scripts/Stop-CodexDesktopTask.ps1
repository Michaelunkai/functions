param(
    [Parameter(Mandatory = $true)][string]$Workspace,
    [Parameter(Mandatory = $true)][string]$TaskId
)

$ErrorActionPreference = 'Stop'
throw 'legacy_desktop_stop_disabled: use the adapter native process/session identity stop path.'
