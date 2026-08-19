param([switch]$RunSmoke)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Path (Split-Path -Path $PSCommandPath -Parent) -Parent
$prodRoot = Join-Path $env:LOCALAPPDATA 'HermesUltimateRefresh'
$src = Join-Path $repoRoot 'src\UltimatePerformanceRefreshProgress.cs'
$worker = Join-Path $repoRoot 'scripts\UltimatePerformanceRefresh.ps1'
$runner = Join-Path $repoRoot 'scripts\Run-UltimatePerformanceRefresh.ps1'
$runnerCmd = Join-Path $repoRoot 'scripts\Run-UltimatePerformanceRefresh.cmd'
$appExe = Join-Path $repoRoot 'app\MichRebootlessWindowsPerformanceMaximizer.exe'
$verificationRoot = Join-Path $repoRoot 'verification'
$prodExe = Join-Path $prodRoot 'UltimatePerformanceRefresh.exe'
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe" }

New-Item -ItemType Directory -Force -Path $prodRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Path $appExe -Parent) | Out-Null
New-Item -ItemType Directory -Force -Path $verificationRoot | Out-Null
Copy-Item -LiteralPath $src -Destination (Join-Path $prodRoot 'UltimatePerformanceRefreshProgress.cs') -Force
Copy-Item -LiteralPath $src -Destination (Join-Path $prodRoot 'UltimatePerformanceRefreshExe.cs') -Force
Copy-Item -LiteralPath $worker -Destination (Join-Path $prodRoot 'UltimatePerformanceRefresh.ps1') -Force
Copy-Item -LiteralPath $runner -Destination (Join-Path $prodRoot 'Run-UltimatePerformanceRefresh.ps1') -Force
Copy-Item -LiteralPath $runnerCmd -Destination (Join-Path $prodRoot 'Run-UltimatePerformanceRefresh.cmd') -Force

$compileArgs = @('/nologo','/target:winexe','/optimize+','/platform:anycpu',('/out:' + $prodExe),'/reference:System.Windows.Forms.dll','/reference:System.Drawing.dll',$src)
$p = Start-Process -FilePath $csc -ArgumentList $compileArgs -Wait -PassThru -NoNewWindow
if ($p.ExitCode -ne 0) { throw "csc failed $($p.ExitCode)" }
Copy-Item -LiteralPath $prodExe -Destination $appExe -Force

$verifyOut = Join-Path $prodRoot 'verify-current-output.txt'
$verifyErr = Join-Path $prodRoot 'verify-current-error.txt'
Remove-Item -LiteralPath $verifyOut,$verifyErr -Force -ErrorAction SilentlyContinue
$p = Start-Process -FilePath $prodExe -ArgumentList '--verify' -Wait -PassThru -RedirectStandardOutput $verifyOut -RedirectStandardError $verifyErr
$out = Get-Content -LiteralPath $verifyOut -Raw -ErrorAction SilentlyContinue
$err = Get-Content -LiteralPath $verifyErr -Raw -ErrorAction SilentlyContinue
if ($p.ExitCode -ne 0) { throw "verify failed $($p.ExitCode) $err $out" }

$smokeExit = $null
$smokeTotalMs = $null
$smokeEnded = $false
if ($RunSmoke) {
  $smokeOut = Join-Path $prodRoot 'worker-verifyonly-output.txt'
  $smokeErr = Join-Path $prodRoot 'worker-verifyonly-error.txt'
  Remove-Item -LiteralPath $smokeOut,$smokeErr -Force -ErrorAction SilentlyContinue
  $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $workerPath = Join-Path $prodRoot 'UltimatePerformanceRefresh.ps1'
  $wp = Start-Process -FilePath $ps -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$workerPath,'-NoPause','-MaxRuntimeSeconds','15') -Wait -PassThru -RedirectStandardOutput $smokeOut -RedirectStandardError $smokeErr
  $smokeExit = $wp.ExitCode
  if ($wp.ExitCode -ne 0) { throw "worker smoke failed $($wp.ExitCode)" }
  $lastRun = Join-Path $prodRoot 'last-run.log'
  $lastRunText = Get-Content -LiteralPath $lastRun -Raw -ErrorAction SilentlyContinue
  $smokeEnded = ($lastRunText -match '(?m)^.* END .*$')
  $match = [regex]::Match($lastRunText, 'total-ms=(\d+)')
  if ($match.Success) { $smokeTotalMs = [int]$match.Groups[1].Value }
  if (-not $smokeEnded) { throw "worker smoke did not write END" }
  if ($null -eq $smokeTotalMs) { throw "worker smoke did not report total-ms" }
  if ($smokeTotalMs -gt 15000) { throw "worker smoke exceeded 15 seconds: total-ms=$smokeTotalMs" }
}

$repoHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $appExe).Hash.ToLowerInvariant()
$prodHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $prodExe).Hash.ToLowerInvariant()
[pscustomobject]@{
  RepoRoot = $repoRoot
  ProductionRoot = $prodRoot
  ProjectExe = $appExe
  ProductionExe = $prodExe
  ProjectSize = (Get-Item $appExe).Length
  ProductionSize = (Get-Item $prodExe).Length
  ProjectSHA256 = $repoHash
  ProductionSHA256 = $prodHash
  HashesMatch = ($repoHash -eq $prodHash)
  VerifyExit = $p.ExitCode
  VerifyOutput = $out
  VerifyError = $err
  RunSmoke = [bool]$RunSmoke
  SmokeExit = $smokeExit
  SmokeEnded = $smokeEnded
  SmokeTotalMs = $smokeTotalMs
} | Format-List | Out-String -Width 4096

$result = [pscustomobject]@{
  Time = (Get-Date).ToString('o')
  ExactApp = $appExe
  ProjectSHA256 = $repoHash
  ProductionSHA256 = $prodHash
  HashesMatch = ($repoHash -eq $prodHash)
  VerifyExit = $p.ExitCode
  RunSmoke = [bool]$RunSmoke
  SmokeExit = $smokeExit
  SmokeEnded = $smokeEnded
  SmokeTotalMs = $smokeTotalMs
  ContractSeconds = 15
}
$result | Format-List | Out-String -Width 4096 | Set-Content -LiteralPath (Join-Path $verificationRoot 'verify-output.txt') -Encoding UTF8
Set-Content -LiteralPath (Join-Path $verificationRoot 'verify-error.txt') -Value $err -Encoding UTF8
