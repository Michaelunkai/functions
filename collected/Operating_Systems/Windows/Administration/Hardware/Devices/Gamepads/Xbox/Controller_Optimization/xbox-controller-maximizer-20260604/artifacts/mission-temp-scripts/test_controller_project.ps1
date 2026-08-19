$ErrorActionPreference='Stop'
$main=Join-Path $env:LOCALAPPDATA 'HermesControllerMaximizer\Invoke-ControllerMaximizer.ps1'
$tokens=$null; $errs=$null
[System.Management.Automation.Language.Parser]::ParseFile($main,[ref]$tokens,[ref]$errs) | Out-Null
if($errs.Count -gt 0){ $errs | ForEach-Object { Write-Host "PARSEERR $($_.Message) line=$($_.Extent.StartLineNumber)" }; exit 10 }
Write-Host "PARSE OK $main"
& $main -Quick -NoPause
$ec=$LASTEXITCODE
Write-Host "RUN exit=$ec"
$latest=Get-ChildItem (Join-Path $env:LOCALAPPDATA 'HermesControllerMaximizer\logs') -Filter 'controller-max-*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if($latest){ Write-Host "LATESTLOG=$($latest.FullName)"; Get-Content -LiteralPath $latest.FullName -Tail 30 }
exit $ec
