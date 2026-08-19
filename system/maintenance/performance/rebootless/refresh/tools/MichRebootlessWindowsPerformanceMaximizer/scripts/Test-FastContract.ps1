param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Path (Split-Path -Path $PSCommandPath -Parent) -Parent
$worker = Join-Path $repoRoot 'scripts\UltimatePerformanceRefresh.ps1'
$source = Join-Path $repoRoot 'src\UltimatePerformanceRefreshProgress.cs'

$workerText = Get-Content -LiteralPath $worker -Raw
$sourceText = Get-Content -LiteralPath $source -Raw

if ($workerText -notmatch '\[int\]\$MaxRuntimeSeconds = 15') { throw 'Worker is missing default MaxRuntimeSeconds=15.' }
if ($workerText -notmatch 'function Get-TimeLeftMs') { throw 'Worker is missing global deadline accounting.' }
if ($workerText -notmatch 'function Has-TimeLeft') { throw 'Worker is missing budget skip checks.' }
if ($workerText -match 'WaitForExit\(\$TimeoutMs\)') { throw 'RunNative still waits on raw per-command timeouts.' }
if ($workerText -match 'MaxSeconds\)\s*\n\s*\$deadline = \(Get-Date\)\.AddSeconds\(\$MaxSeconds\)') { throw 'Cleanup still uses only local deadlines.' }
if ($workerText -match 'Get-ChildItem\s+-LiteralPath\s+\$r\s+-Directory\s+-Recurse') { throw 'Browser cache discovery must not recurse whole profile roots.' }
foreach ($marker in @(
    'app runtime communication cache cleanup unlocked only',
    'Windows app model package cache cleanup unlocked only',
    'recent files jump shell telemetry cleanup unlocked only',
    'extra shell session system-parameter broadcasts',
    'service control manager and WMI repository touch'
)) {
    if ($workerText -notmatch [regex]::Escape($marker)) { throw "Worker is missing expanded coverage marker: $marker" }
}
if ($sourceText -notmatch 'WorkerBudgetSeconds = 15') { throw 'GUI is missing visible worker budget.' }
if ($sourceText -notmatch 'TotalSeconds > 22') { throw 'GUI timeout does not bound app-visible waiting.' }

$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$out = Join-Path $env:TEMP 'mich-refresh-fast-contract.out.txt'
$err = Join-Path $env:TEMP 'mich-refresh-fast-contract.err.txt'
Remove-Item -LiteralPath $out,$err -Force -ErrorAction SilentlyContinue
$p = Start-Process -FilePath $ps -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$worker,'-VerifyOnly','-MaxRuntimeSeconds','15') -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
if ($p.ExitCode -ne 0) { throw "VerifyOnly worker contract run failed exit=$($p.ExitCode)" }

$log = Join-Path (Split-Path -Path $worker -Parent) 'last-run.log'
$logText = Get-Content -LiteralPath $log -Raw
if ($logText -notmatch 'BUDGET max-runtime-seconds=15') { throw 'VerifyOnly log did not record the 15-second budget.' }
if ($logText -notmatch 'END ') { throw 'VerifyOnly log did not end cleanly.' }

'fast-contract-tests=PASS'
