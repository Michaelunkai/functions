[CmdletBinding()]
param([switch]$LaunchWorker)
$ErrorActionPreference='Stop'
$desktop='C:\Program Files\Docker\Docker\Docker Desktop.exe'
if(-not [IO.File]::Exists($desktop)){throw "Docker Desktop is missing: $desktop"}
if(@(Get-Process -Name 'Docker Desktop','com.docker.backend' -ErrorAction SilentlyContinue).Count){Write-Output 'Docker Desktop is already running';return}

if($LaunchWorker){
 & 'F:\study\Platforms\windows\functions\Repair-DockerRuntimeSockets.ps1' | Out-Host
 & 'F:\study\Containers\docker\backup-docker\repository-tools\SetDockerhyperv\Invoke-set-dockerhyperv.ps1' -NoRestart | Out-Host
 Write-Output 'DOCKER_NATIVE_PREFLIGHT_COMPLETE'
 return
}

# Run the bounded preflight directly, then launch Docker Desktop through a
# temporary limited interactive task.  dkill must be elevated to delete the
# VMM data, but Docker's libkrun/vsock path is unreliable when Docker Desktop
# inherits that elevated token.  RunLevel=0 keeps cleanup elevated while the
# user-facing Docker process receives the normal medium-integrity token.
& $PSCommandPath -LaunchWorker | Out-Host
$preflightSucceeded=$?
$preflightExitCode=$LASTEXITCODE
if(-not $preflightSucceeded -or ($null -ne $preflightExitCode -and [int]$preflightExitCode -ne 0)){throw ('Docker native preflight failed: '+$preflightExitCode)}
$workingDirectory=Split-Path -Parent $desktop
$taskName='CodexDockerVmmLaunch-'+[guid]::NewGuid().ToString('N')
$scheduler=$null
$folder=$null
try {
 $scheduler=New-Object -ComObject Schedule.Service
 $scheduler.Connect()
 $folder=$scheduler.GetFolder('\')
 $definition=$scheduler.NewTask(0)
 $definition.RegistrationInfo.Description='Temporary limited Docker Desktop VMM launch; no trigger is registered.'
 $definition.Principal.UserId=[Security.Principal.WindowsIdentity]::GetCurrent().Name
 $definition.Principal.LogonType=3
 $definition.Principal.RunLevel=0
 $definition.Settings.ExecutionTimeLimit='PT0S'
 $definition.Settings.DisallowStartIfOnBatteries=$false
 $definition.Settings.StopIfGoingOnBatteries=$false
 $definition.Settings.Hidden=$true
 $action=$definition.Actions.Create(0)
 $action.Path=$desktop
 $action.WorkingDirectory=$workingDirectory
 $registered=$folder.RegisterTaskDefinition($taskName,$definition,6,$null,$null,3,$null)
 $null=$registered.Run($null)
 $launchDeadline=[DateTime]::UtcNow.AddSeconds(5)
 $launched=$false
 while([DateTime]::UtcNow -lt $launchDeadline){
  if(@(Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue).Count -gt 0){$launched=$true;break}
  Start-Sleep -Milliseconds 150
 }
 if(-not $launched){throw 'Docker Desktop did not appear after the limited interactive task was run.'}
 $dockerPid=Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Id
 Write-Output ('DOCKER_VMM_LAUNCH_REQUESTED mode=limited-interactive pid='+$dockerPid)
} catch {
 throw ('Docker limited interactive launch failed: '+$_.Exception.Message)
} finally {
 if($folder -and $taskName){try{$folder.DeleteTask($taskName,0)}catch{}}
}
