[CmdletBinding()]
param(
    [ValidateRange(2,16)]
    [int]$Workers = 4
)

$ErrorActionPreference = 'Stop'
$uniPath = Join-Path $PSScriptRoot 'uni.ps1'
$powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if(-not (Test-Path -LiteralPath $uniPath -PathType Leaf)){ throw "Uni source missing: $uniPath" }
if(-not (Test-Path -LiteralPath $powershellPath -PathType Leaf)){ throw "Windows PowerShell missing: $powershellPath" }

$fixtureRoot = Join-Path 'C:\Temp' ('uni-concurrent-fixture-' + [guid]::NewGuid().ToString('N'))
$listPath = Join-Path $fixtureRoot 'targets.txt'
$ownedRoot = Join-Path $fixtureRoot 'owned-tree'
$workersState = New-Object 'System.Collections.Generic.List[object]'
$queue = New-Object Threading.Mutex($false, 'Global\UniOwnedCleanupV8')
$queueHeld = $false

try {
    [void][IO.Directory]::CreateDirectory($ownedRoot)
    $targets = New-Object 'System.Collections.Generic.List[string]'
    for($i = 1; $i -le 250; $i++) {
        $path = Join-Path $ownedRoot ('fixture-{0:D4}.tmp' -f $i)
        [IO.File]::WriteAllText($path, 'uni concurrency fixture')
        [void]$targets.Add($path)
    }
    [IO.File]::WriteAllLines($listPath, [string[]]$targets)

    try { $queueHeld = $queue.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $queueHeld = $true }
    if(-not $queueHeld){ throw 'Could not acquire the Uni queue for the deterministic test barrier.' }

    for($i = 1; $i -le $Workers; $i++) {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $powershellPath
        $psi.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" --paths-file "{1}"' -f $uniPath,$listPath
        $psi.WorkingDirectory = $PSScriptRoot
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $psi
        if(-not $process.Start()){ throw "Could not start worker $i." }
        [void]$workersState.Add([pscustomobject]@{
            Index = $i
            Process = $process
            OutputTask = $process.StandardOutput.ReadToEndAsync()
            ErrorTask = $process.StandardError.ReadToEndAsync()
        })
    }

    Start-Sleep -Milliseconds 1000
    if($queueHeld){$queue.ReleaseMutex();$queueHeld=$false}

    foreach($worker in $workersState){
        $worker.Process.WaitForExit()
        $worker | Add-Member -NotePropertyName ExitCode -NotePropertyValue $worker.Process.ExitCode
        $worker | Add-Member -NotePropertyName Output -NotePropertyValue $worker.OutputTask.Result
        $worker | Add-Member -NotePropertyName Error -NotePropertyValue $worker.ErrorTask.Result
        $worker.Process.Dispose()
    }

    $exitCodes = @($workersState | ForEach-Object ExitCode)
    $waitMessages = @($workersState | ForEach-Object { ([regex]::Matches([string]$_.Output, 'Another Uni run is active; waiting for it to finish')).Count } | Measure-Object -Sum).Sum
    $failFast = @($workersState | Where-Object { [string]$_.Output -match 'Another Uni run is active; this invocation did not mutate anything|INCOMPLETE: Another Uni run is active' }).Count
    $stderrCount = @($workersState | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Error) }).Count
    $remaining = Test-Path -LiteralPath $ownedRoot -PathType Any

    Write-Output ('QUEUE_WORKERS={0}' -f $Workers)
    Write-Output ('QUEUE_EXIT_CODES={0}' -f ($exitCodes -join ','))
    Write-Output ('QUEUE_WAIT_MESSAGES={0}' -f [int]$waitMessages)
    Write-Output ('QUEUE_FAIL_FAST={0}' -f $failFast)
    Write-Output ('QUEUE_TARGET_PRESENT={0}' -f $remaining)
    Write-Output ('QUEUE_STDERR_NONEMPTY={0}' -f $stderrCount)

    if(@($exitCodes | Where-Object { $_ -ne 0 }).Count -or $waitMessages -lt ($Workers - 1) -or $failFast -or $stderrCount -or $remaining){
        throw 'Concurrent Uni queue regression failed.'
    }
}
finally {
    foreach($worker in $workersState){
        if($worker.Process -and -not $worker.Process.HasExited){try{$worker.Process.Kill()}catch{}}
        if($worker.Process){try{$worker.Process.Dispose()}catch{}}
    }
    if($queueHeld){try{$queue.ReleaseMutex()}catch{}}
    $queue.Dispose()
    if(Test-Path -LiteralPath $fixtureRoot){Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue}
}
