[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$ScriptPath,
 [hashtable]$Parameters = @{},
 [ValidateRange(1,1200)][int]$TimeoutSeconds = 1200
)
$ErrorActionPreference = 'Stop'
$allowed = @('dkill.ps1','Invoke-HermesDockerPreserveRedocker.ps1','Invoke-DockerHubLogin.ps1')
$full = [IO.Path]::GetFullPath($ScriptPath)
if ($full -ne 'F:\study\Containers\docker\backup-docker\repository-tools\SetDockerhyperv\Invoke-set-dockerhyperv.ps1' -and ([IO.Path]::GetDirectoryName($full) -ne 'F:\study\Platforms\windows\functions' -or [IO.Path]::GetFileName($full) -notin $allowed)) { throw 'Unsupported Docker maintenance script.' }
function Quote-NativeValue([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }
$id = [guid]::NewGuid().ToString('N')
$log = 'C:\Temp\docker-native-' + $id + '.log'
$result = 'C:\Temp\docker-native-' + $id + '.exit'
$command = '& ' + (Quote-NativeValue $full)
foreach ($key in $Parameters.Keys) {
 if ($key -notmatch '^[A-Za-z][A-Za-z0-9]*$') { throw 'Invalid parameter name.' }
 $value = $Parameters[$key]
 if ($value -is [Management.Automation.SwitchParameter] -or $value -is [bool]) {
  if ([bool]$value) { $command += ' -' + $key }
 } else { $command += ' -' + $key + ' ' + (Quote-NativeValue ([string]$value)) }
}
# A separate native PS5 child allows scripts using exit to finish before the receipt is written.
$inner = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$body = '& ' + (Quote-NativeValue ($env:SystemRoot+'\System32\WindowsPowerShell\v1.0\powershell.exe')) + ' -NoProfile -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand ' + $inner + ' *> ' + (Quote-NativeValue $log) + '; [IO.File]::WriteAllText(' + (Quote-NativeValue $result) + ',[string]$LASTEXITCODE)'
$scheduler = New-Object -ComObject Schedule.Service
$scheduler.Connect()
$folder = $scheduler.GetFolder('\')
$definition = $scheduler.NewTask(0)
$definition.Principal.UserId = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$definition.Principal.LogonType = 3
$definition.Principal.RunLevel = 1
$definition.Settings.ExecutionTimeLimit = 'PT0S'
$definition.Settings.DisallowStartIfOnBatteries = $false
$definition.Settings.StopIfGoingOnBatteries = $false
$action = $definition.Actions.Create(0)
$action.Path = $env:SystemRoot+'\System32\WindowsPowerShell\v1.0\powershell.exe'
$action.Arguments='-NoProfile -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
$name = 'DockerMaintenance-' + $id
$task = $folder.RegisterTaskDefinition($name,$definition,6,$null,$null,3,$null)
Write-Host ('Running Docker maintenance in the Windows host session: ' + [IO.Path]::GetFileName($full))
$null = $task.Run($null)
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$seen = 0
while (-not [IO.File]::Exists($result)) {
 if ([IO.File]::Exists($log)) {
  $lines = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue)
  if ($lines.Count -gt $seen) { $lines | Select-Object -Skip $seen | ForEach-Object { Write-Host $_ }; $seen = $lines.Count }
 }
 if ([DateTime]::UtcNow -gt $deadline) {
  try { $task.Stop(0) } catch { }
  try { $folder.DeleteTask($name,0) } catch { }
  throw "Docker maintenance exceeded its $TimeoutSeconds-second deadline; task was stopped. Inspect the log before retrying: $log"
 }
 if ($task.State -eq 3 -and $task.LastTaskResult -ne 0) { throw "Native Docker worker failed with task result $($task.LastTaskResult). Log: $log" }
 Start-Sleep -Milliseconds 250
}
if ([IO.File]::Exists($log)) { Get-Content -LiteralPath $log | Select-Object -Skip $seen | ForEach-Object { Write-Host $_ } }
$exitCode = [int][IO.File]::ReadAllText($result)
$folder.DeleteTask($name,0)
if ($exitCode -ne 0) { throw "Docker maintenance failed with exit code $exitCode. Log: $log" }
