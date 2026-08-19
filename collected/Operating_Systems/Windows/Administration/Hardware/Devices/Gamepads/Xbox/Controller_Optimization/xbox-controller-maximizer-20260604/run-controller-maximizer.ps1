param([switch]$Quick,[switch]$ProbeOnly,[switch]$NoPause)
$ErrorActionPreference='Stop'
$ScriptRoot = Split-Path -Path $PSCommandPath -Parent
$Payload = Join-Path $ScriptRoot 'scripts\Invoke-ControllerMaximizer.ps1'
$payloadArgs = @{}
if($Quick){ $payloadArgs['Quick']=$true }
if($ProbeOnly){ $payloadArgs['ProbeOnly']=$true }
if($NoPause){ $payloadArgs['NoPause']=$true }
& $Payload @payloadArgs
exit $LASTEXITCODE
