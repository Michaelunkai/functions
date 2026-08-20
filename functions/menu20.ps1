[CmdletBinding()]
param(
    [Parameter(Mandatory=$true,Position=0)][string]$Path,
    [switch]$PreflightOnly,
    [switch]$TarPreflightOnly,
    [switch]$BuildPreflightOnly,
    [ValidateRange(128,4096)][int64]$TargetLayerMiB=4096
)
$ErrorActionPreference = 'Stop'
$parameters = @{ Path=$Path; TargetLayerMiB=$TargetLayerMiB; EntryPoint='menu20' }
if ($PreflightOnly) { $parameters['PreflightOnly']=$true }
if ($TarPreflightOnly) { $parameters['TarPreflightOnly']=$true }
if ($BuildPreflightOnly) { $parameters['BuildPreflightOnly']=$true }
& 'C:\Users\micha\Documents\WindowsPowerShell\mmenu_chunked_push.ps1' @parameters