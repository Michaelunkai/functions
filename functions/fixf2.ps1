[CmdletBinding()]
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
$chkdsk = Join-Path $env:SystemRoot 'System32\chkdsk.exe'
if (-not (Test-Path -LiteralPath $chkdsk -PathType Leaf)) { throw "CHKDSK executable not found: $chkdsk" }
if (-not (Test-Path -LiteralPath 'F:\')) { throw 'F: drive is not available.' }
if ($SelfTest) { Write-Host "FIXF2_SELFTEST_OK executable=$chkdsk target=F:"; return }
if (Get-Process chkdsk -ErrorAction SilentlyContinue) { throw 'CHKDSK is already running.' }

$logRoot = 'C:\Program Files\FDriveOnlineIntegrity'
if (-not (Test-Path -LiteralPath $logRoot -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $logRoot -Force
}
$runId = [guid]::NewGuid().ToString('N')
$log = Join-Path $logRoot ("chkdsk-live-$runId.txt")
$errorLog = "$log.err"
$process = Start-Process -FilePath $chkdsk -ArgumentList 'F:','/scan','/forceofflinefix' -RedirectStandardOutput $log -RedirectStandardError $errorLog -PassThru -NoNewWindow
# Windows PowerShell 5 can leave ExitCode unset unless the native process
# handle is materialized before it exits.
$null = $process.Handle
$watch = [Diagnostics.Stopwatch]::StartNew()
$lastNative = ''
Write-Host 'FIXF2_PROGRESS stage=started target=F: elapsed=00:00:00'
while (-not $process.HasExited) {
    $raw = Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue
    if ($raw) {
        $matches = [regex]::Matches($raw, 'Progress:\s*(\d+)\s+of\s+(\d+)\s+done;\s*Stage:\s*\d+%;\s*Total:\s*(\d+)%;\s*ETA:\s*([^\.\r\n]+)')
        if ($matches.Count) {
            $match = $matches[$matches.Count - 1]
            $units = [double]$match.Groups[2].Value
            $stagePercent = if ($units -gt 0) { 100 * [double]$match.Groups[1].Value / $units } else { 0 }
            $lastNative = ' total=' + ([double]$match.Groups[3].Value).ToString('0.00',[Globalization.CultureInfo]::InvariantCulture) + '% stage=' + $stagePercent.ToString('0.00',[Globalization.CultureInfo]::InvariantCulture) + '% eta=' + $match.Groups[4].Value.Trim()
        }
    }
    $elapsed = $watch.Elapsed
    $elapsedText = '{0:00}:{1:00}:{2:00}' -f [int]$elapsed.TotalHours,$elapsed.Minutes,$elapsed.Seconds
    Write-Host "FIXF2_PROGRESS stage=running elapsed=$elapsedText$lastNative"
    Start-Sleep -Milliseconds 1000
    $process.Refresh()
}
$process.WaitForExit()
$process.Refresh()
$exitCode = [int]$process.ExitCode
$watch.Stop()
$elapsed = $watch.Elapsed
$elapsedText = '{0:00}:{1:00}:{2:00}' -f [int]$elapsed.TotalHours,$elapsed.Minutes,$elapsed.Seconds
$raw = Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue
if ($exitCode -ne 0) {
    $nativeError = Get-Content -LiteralPath $errorLog -Raw -ErrorAction SilentlyContinue
    throw "CHKDSK failed with exit code ${exitCode}: $nativeError"
}
Write-Host "FIXF2_OK target=F: elapsed=$elapsedText"
if ($raw -match '(?m)^\s*Windows\b.*found no problems\.\s*$') {
    Write-Host 'CORRUPTION_FOUND=NO CORRUPTION_FIXED=NOT_NEEDED'
} elseif ($raw -match '(?im)^\s*Windows\b.*(?:made corrections|corrected).*') {
    Write-Host 'CORRUPTION_FOUND=YES CORRUPTION_FIXED=YES'
} elseif ($raw -match '(?im)^\s*Windows\b.*(?:found problems|found corruption|offline repair|required).*') {
    Write-Host 'CORRUPTION_FOUND=YES CORRUPTION_FIXED=NO_OFFLINE_REPAIR_QUEUED'
} else {
    Write-Host 'CORRUPTION_FOUND=UNKNOWN CORRUPTION_FIXED=UNKNOWN'
}
Get-Content -LiteralPath $log -Tail 20
