$ErrorActionPreference = 'Stop'
$commandText = 'c; rrm windows.old'
function Invoke-BoundedNativeCommand {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $true)][string[]] $ArgumentList,
        [Parameter(Mandatory = $true)][string] $Label,
        [int] $TimeoutSeconds = 120,
        [scriptblock] $PulseScript
    )
    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -WindowStyle Hidden
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $nextPulse = 5
    while (-not $process.HasExited) {
        Start-Sleep -Seconds 1
        if ($stopwatch.Elapsed.TotalSeconds -ge $nextPulse) {
            if ($PulseScript) { & $PulseScript ("{0} running for {1}s" -f $Label, [int]$stopwatch.Elapsed.TotalSeconds) }
            $nextPulse += 5
        }
        if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "{0} timed out after {1} seconds" -f $Label, $TimeoutSeconds
        }
    }
    $process.WaitForExit()
    return $process.ExitCode
}
function Invoke-ForceRemovePath {
    param(
        [Parameter(Mandatory = $true)][string] $TargetPath,
        [scriptblock] $PulseScript,
        [scriptblock] $LogScript
    )
    if (-not $TargetPath) { return }
    if (-not (Test-Path -LiteralPath $TargetPath)) {
        if ($LogScript) { & $LogScript ('SKIP target already absent ' + $TargetPath) }
        return
    }
    if ($LogScript) { & $LogScript ('FAST_RD begin ' + $TargetPath) }
    $fastRdExit = Invoke-BoundedNativeCommand -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/d', '/c', "rd /s /q `"$TargetPath`" >nul 2>nul") -Label ("fast rd {0}" -f $TargetPath) -TimeoutSeconds 60 -PulseScript $PulseScript
    if ($LogScript) { & $LogScript ('FAST_RD exit=' + $fastRdExit) }
    if (-not (Test-Path -LiteralPath $TargetPath)) {
        if ($LogScript) { & $LogScript ('DONE target absent ' + $TargetPath) }
        return
    }
    if ($LogScript) { & $LogScript ('TAKEOWN begin ' + $TargetPath) }
    $takeownExit = Invoke-BoundedNativeCommand -FilePath (Join-Path $env:SystemRoot 'System32\takeown.exe') -ArgumentList @('/f', $TargetPath, '/r', '/d', 'y') -Label ("takeown {0}" -f $TargetPath) -TimeoutSeconds 180 -PulseScript $PulseScript
    if ($LogScript) { & $LogScript ('TAKEOWN exit=' + $takeownExit) }
    if ($LogScript) { & $LogScript ('ICACLS begin ' + $TargetPath) }
    $icaclsExit = Invoke-BoundedNativeCommand -FilePath (Join-Path $env:SystemRoot 'System32\icacls.exe') -ArgumentList @($TargetPath, '/grant', 'administrators:F', 'SYSTEM:F', '/t', '/c', '/q') -Label ("icacls {0}" -f $TargetPath) -TimeoutSeconds 180 -PulseScript $PulseScript
    if ($LogScript) { & $LogScript ('ICACLS exit=' + $icaclsExit) }
    if ($LogScript) { & $LogScript ('ATTRIB/RD begin ' + $TargetPath) }
    $attribRdExit = Invoke-BoundedNativeCommand -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/d', '/c', "attrib -r -s -h `"$TargetPath\*`" /s /d >nul 2>nul & rd /s /q `"$TargetPath`" >nul 2>nul") -Label ("attrib/rd {0}" -f $TargetPath) -TimeoutSeconds 90 -PulseScript $PulseScript
    if ($LogScript) { & $LogScript ('ATTRIB/RD exit=' + $attribRdExit) }
    if (Test-Path -LiteralPath $TargetPath) {
        if ($LogScript) { & $LogScript ('REMOVE_ITEM begin ' + $TargetPath) }
        Remove-Item -LiteralPath $TargetPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $TargetPath) {
        throw "Target still exists after bounded cleanup: $TargetPath"
    }
    if ($LogScript) { & $LogScript ('DONE target absent ' + $TargetPath) }
}
function c {
    Set-Location -LiteralPath 'C:\'
}
function rrm {
    param([Parameter(ValueFromRemainingArguments = $true)] [object[]] $RemainingArgs)
    if ($RemainingArgs.Count -eq 1 -and [string]$RemainingArgs[0] -ieq 'windows.old') { $RemainingArgs = @('C:\Windows.old') }
    foreach ($targetToRemove in $RemainingArgs) {
        if (-not $targetToRemove) { continue }
        Invoke-ForceRemovePath -TargetPath $targetToRemove
    }
}
Invoke-Expression $commandText
