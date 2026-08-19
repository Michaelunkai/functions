# ALLOW_DESTRUCTIVE: scoped post-upgrade cleanup for C:\Windows.old only; DryRun reports without deleting.
[CmdletBinding()]
param(
    [switch]$SystemWorker,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$reports = Join-Path $root 'reports'
$log = Join-Path $reports 'windows-old-cleanup.log'
$target = 'C:\Windows.old'
$taskNames = @('ZeroTouchMainWindows11PostBootWindowsOldCleanup', 'WinSetupPostBootWindowsOldCleanupSystem')
$ps5 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $ps5)) { $ps5 = 'powershell.exe' }

function Write-CleanupLog([string]$Message) {
    New-Item -ItemType Directory -Path $reports -Force | Out-Null
    ('{0} {1}' -f (Get-Date -Format s), $Message) | Add-Content -LiteralPath $log -Encoding ASCII
}

function Test-IsSystemContext {
    try { return ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18') } catch { return $false }
}

function Invoke-BoundedNativeCommandWithExitCode {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $true)][string[]] $ArgumentList,
        [Parameter(Mandatory = $true)][string] $Label,
        [int] $TimeoutSeconds = 120
    )
    if ($DryRun) {
        Write-CleanupLog ('DRYRUN native ' + $Label + ' ' + ($ArgumentList -join ' '))
        return 0
    }
    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -WindowStyle Hidden
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $nextPulse = 5
    while (-not $process.HasExited) {
        Start-Sleep -Seconds 1
        if ($stopwatch.Elapsed.TotalSeconds -ge $nextPulse) {
            Write-CleanupLog ('PULSE {0} running for {1}s' -f $Label, [int]$stopwatch.Elapsed.TotalSeconds)
            $nextPulse += 5
        }
        if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            Write-CleanupLog ('TIMEOUT {0} after {1}s' -f $Label, $TimeoutSeconds)
            return 124
        }
    }
    $process.WaitForExit()
    Write-CleanupLog ('EXIT {0} code={1}' -f $Label, $process.ExitCode)
    return $process.ExitCode
}

function Remove-PostBootTriggers {
    foreach ($taskName in $taskNames) {
        if ($DryRun) { Write-CleanupLog ('DRYRUN would delete task ' + $taskName); continue }
        schtasks.exe /Delete /TN $taskName /F >$null 2>$null
    }
}

function Start-SystemWorker {
    $taskName = 'WinSetupPostBootWindowsOldCleanupSystem'
    if ($DryRun) {
        Write-CleanupLog ('DRYRUN would register and start SYSTEM worker ' + $taskName)
        return
    }
    schtasks.exe /Delete /TN $taskName /F >$null 2>$null
    $workerArgs = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -SystemWorker'
    $action = New-ScheduledTaskAction -Execute $ps5 -Argument $workerArgs
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    $trigger = New-ScheduledTaskTrigger -Once -At ([datetime]::Now.AddMinutes(1))
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Trigger $trigger -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Write-CleanupLog ('SYSTEM_TASK_RUN ' + $taskName)
}

# ALLOW_DESTRUCTIVE: this function is only called for children of C:\Windows.old and honors -DryRun.
function Invoke-DrainWindowsOldEntry {
    param([Parameter(Mandatory = $true)][string] $EntryPath)
    if (-not (Test-Path -LiteralPath $EntryPath)) { return }
    if ((Get-Item -LiteralPath $EntryPath -Force).PSIsContainer) {
        $emptyDir = Join-Path ([System.IO.Path]::GetTempPath()) ('zt-winold-empty-' + [guid]::NewGuid().ToString('N'))
        if (-not $DryRun) { New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null }
        try {
            Write-CleanupLog ('PASS robocopy/mirror begin ' + $EntryPath)
            Invoke-BoundedNativeCommandWithExitCode -FilePath (Join-Path $env:SystemRoot 'System32\robocopy.exe') -ArgumentList @($emptyDir, $EntryPath, '/MIR', '/XJ', '/R:0', '/W:0', '/NFL', '/NDL', '/NJH', '/NJS', '/NP') -Label ('robocopy ' + $EntryPath) -TimeoutSeconds 180 | Out-Null
            Write-CleanupLog ('PASS rd begin ' + $EntryPath)
            Invoke-BoundedNativeCommandWithExitCode -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/d', '/c', 'rd /s /q "' + $EntryPath + '"') -Label ('rd ' + $EntryPath) -TimeoutSeconds 90 | Out-Null
        } finally {
            if (-not $DryRun) { Remove-Item -LiteralPath $emptyDir -Force -Recurse -ErrorAction SilentlyContinue }
        }
    } else {
        Write-CleanupLog ('PASS remove file begin ' + $EntryPath)
        if (-not $DryRun) { Remove-Item -LiteralPath $EntryPath -Force -ErrorAction SilentlyContinue }
    }
}

# ALLOW_DESTRUCTIVE: entrypoint limits final root removal to the constant C:\Windows.old and is inert with -DryRun.
Write-CleanupLog ('START target=C:\Windows.old system=' + (Test-IsSystemContext) + ' systemWorker=' + $SystemWorker.IsPresent + ' dryRun=' + $DryRun.IsPresent)
if (-not (Test-Path -LiteralPath $target)) {
    Write-CleanupLog 'SKIP target already absent'
    Remove-PostBootTriggers
    exit 0
}
if (-not $SystemWorker -and -not (Test-IsSystemContext)) {
    Start-SystemWorker
    Write-CleanupLog 'DELEGATED cleanup to SYSTEM worker'
    if (-not $DryRun) { exit 0 }
}
for ($iteration = 0; $iteration -lt 12; $iteration++) {
    if (-not (Test-Path -LiteralPath $target)) { break }
    $entries = @(Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue)
    Write-CleanupLog ('ITERATION ' + $iteration + ' entries=' + $entries.Count)
    foreach ($entry in $entries) { Invoke-DrainWindowsOldEntry -EntryPath $entry.FullName }
    Invoke-BoundedNativeCommandWithExitCode -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/d', '/c', 'rd /s /q "' + $target + '" >nul 2>nul') -Label ('root rd ' + $target) -TimeoutSeconds 30 | Out-Null
    if ($DryRun) { break }
    if (Test-Path -LiteralPath $target) { Start-Sleep -Seconds 2 }
}
if (Test-Path -LiteralPath $target -and -not $DryRun) {
    Write-CleanupLog 'FAILED target still exists'
    exit 1
}
Remove-PostBootTriggers
Write-CleanupLog 'DONE target absent'
exit 0
