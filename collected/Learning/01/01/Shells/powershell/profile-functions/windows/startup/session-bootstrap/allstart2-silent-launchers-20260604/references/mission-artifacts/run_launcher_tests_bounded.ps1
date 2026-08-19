$ErrorActionPreference = 'Stop'
$ProjectRoot = 'F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\allstart2-silent-launchers-20260604'
$wscript='C:\Windows\System32\wscript.exe'
$items=@(
  @{Name='OpenSpeedy'; Vbs=(Join-Path $ProjectRoot 'openspeedy-silent\openspeedy-silent.vbs'); Args=@(); Process='Speedy'},
  @{Name='Murmure'; Vbs=(Join-Path $ProjectRoot 'murmure-silent\murmure-silent.vbs'); Args=@(); Process='murmure'},
  @{Name='TrayQuietDocker'; Vbs=(Join-Path $ProjectRoot 'trayquiet-start\trayquiet-start.vbs'); Args=@('C:\ProgramData\pip\docker.exe','0','0','1'); Process=$null}
)
foreach($it in $items){
  if(-not(Test-Path -LiteralPath $it.Vbs -PathType Leaf)){ throw "missing $($it.Vbs)" }
  $argList=@('//B','//Nologo',$it.Vbs)+@($it.Args)
  $p=Start-Process -FilePath $wscript -ArgumentList $argList -WindowStyle Hidden -PassThru
  if(-not $p.WaitForExit(15000)){
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    throw "$($it.Name) wscript did not exit"
  }
  if($p.ExitCode -ne 0){ throw "$($it.Name) exit=$($p.ExitCode)" }
  Start-Sleep -Milliseconds 1000
  $present=$false
  if($it.Process){ $present=[bool](Get-Process -Name $it.Process -ErrorAction SilentlyContinue | Select-Object -First 1) }
  if($it.Process -and -not $present){ throw "$($it.Name) process missing $($it.Process)" }
  [pscustomobject]@{Name=$it.Name; ExitCode=$p.ExitCode; ProcessPresent=$present} | ConvertTo-Json -Compress
}
# Confirm no stale wscript points at missing C:\Users\micha\.claude scripts.
$stale=@(Get-CimInstance Win32_Process -Filter "Name='wscript.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match [regex]::Escape('C:\Users\micha\.claude\scripts\openspeedy-silent.vbs') -or $_.CommandLine -match [regex]::Escape('C:\Users\micha\.claude\scripts\murmure-silent.vbs') -or $_.CommandLine -match [regex]::Escape('C:\Users\micha\.claude\scripts\trayquiet-start.vbs') })
if($stale.Count -gt 0){ throw "stale missing-path wscript still running: $($stale.Count)" }
'ALL_TESTS_PASSED'
