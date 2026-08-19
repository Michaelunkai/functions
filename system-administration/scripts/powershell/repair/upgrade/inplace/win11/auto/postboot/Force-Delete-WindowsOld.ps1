# ALLOW_DESTRUCTIVE: requested post-upgrade force cleanup, scoped only to C:\Windows.old.
param([switch]$SystemWorker)
$ErrorActionPreference = 'Continue'
$log = Join-Path (Split-Path -Parent $PSCommandPath) 'windows-old-cleanup.log'
$target = 'C:\Windows.old'
$systemTaskName = 'WinSetupPostBootWindowsOldCleanupSystem'
$ps5 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
function Write-CleanupLog([string]$Message) {
    ('{0} {1}' -f (Get-Date -Format s), $Message) | Add-Content -LiteralPath $log -Encoding ASCII
}
function Test-IsSystemContext {
    try {
        return ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18')
    } catch {
        return $false
    }
}
function Invoke-BoundedNativeCommandWithExitCode {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $true)][string[]] $ArgumentList,
        [Parameter(Mandatory = $true)][string] $Label,
        [int] $TimeoutSeconds = 120
    )
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
function Remove-SystemTask {
    schtasks.exe /Delete /TN $systemTaskName /F >$null 2>$null
}
function Remove-PostBootTriggers {
    foreach ($oneShotTaskName in @('WinSetupPostBootWindowsOldCleanup', 'WinSetupPostBootWindowsOldCleanupRetry', 'WinSetupPostBootWindowsOldCleanup' + 'System')) { schtasks.exe /Delete /TN $oneShotTaskName /F >$null 2>$null }
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'WinSetupPostBootWindowsOldCleanup' -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'WinSetupPostBootWindowsOldCleanup' -Force -ErrorAction SilentlyContinue
}
function Invoke-DrainWindowsOldEntry {
    param([Parameter(Mandatory = $true)][string] $EntryPath)
    if (-not (Test-Path -LiteralPath $EntryPath)) { return }
    if ((Get-Item -LiteralPath $EntryPath -Force).PSIsContainer) {
        $emptyDir = Join-Path ([System.IO.Path]::GetTempPath()) ('winold-empty-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
        try {
            Write-CleanupLog ('PASS robocopy/mirror begin ' + $EntryPath)
            $rc = Invoke-BoundedNativeCommandWithExitCode -FilePath (Join-Path $env:SystemRoot 'System32\robocopy.exe') -ArgumentList @($emptyDir, $EntryPath, '/MIR', '/XJ', '/R:0', '/W:0', '/NFL', '/NDL', '/NJH', '/NJS', '/NP') -Label ('robocopy ' + $EntryPath) -TimeoutSeconds 180
            Write-CleanupLog ('PASS robocopy/mirror exit ' + $EntryPath + ' code=' + $rc)
        } finally {
            Remove-Item -LiteralPath $emptyDir -Force -Recurse -ErrorAction SilentlyContinue
        }
        Write-CleanupLog ('PASS rd begin ' + $EntryPath)
        $rdCommand = 'rd /s /q "' + $EntryPath + '"'
        Invoke-BoundedNativeCommandWithExitCode -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/d', '/c', $rdCommand) -Label ('rd ' + $EntryPath) -TimeoutSeconds 90 | Out-Null
        if (Test-Path -LiteralPath $EntryPath) {
            Write-CleanupLog ('PASS attrib/rd begin ' + $EntryPath)
            $attribCommand = 'attrib -r -s -h "' + $EntryPath + '\*" /s /d >nul 2>nul & rd /s /q "' + $EntryPath + '" >nul 2>nul'
            Invoke-BoundedNativeCommandWithExitCode -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/d', '/c', $attribCommand) -Label ('attrib/rd ' + $EntryPath) -TimeoutSeconds 120 | Out-Null
        }
    } else {
        Write-CleanupLog ('PASS remove file begin ' + $EntryPath)
        Remove-Item -LiteralPath $EntryPath -Force -ErrorAction SilentlyContinue
    }
}
function Start-SystemWorker {
    if (-not (Test-Path -LiteralPath $ps5)) { $ps5 = 'powershell.exe' }
    schtasks.exe /Delete /TN $systemTaskName /F >$null 2>$null
    $workerArgs = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -SystemWorker'
    $action = New-ScheduledTaskAction -Execute $ps5 -Argument $workerArgs
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    $trigger = New-ScheduledTaskTrigger -Once -At ([datetime]::Now.AddMinutes(1))
    Register-ScheduledTask -TaskName $systemTaskName -Action $action -Principal $principal -Settings $settings -Trigger $trigger -Force | Out-Null
    Start-ScheduledTask -TaskName $systemTaskName
    Write-CleanupLog ('SYSTEM_TASK_RUN ' + $systemTaskName)
}
Write-CleanupLog ('START target=C:\Windows.old system=' + (Test-IsSystemContext) + ' systemWorker=' + $SystemWorker.IsPresent)
if (-not (Test-Path -LiteralPath $target)) {
    Write-CleanupLog 'SKIP target already absent'
    Remove-PostBootTriggers
    Remove-SystemTask
    exit 0
}
if (-not $SystemWorker -and -not (Test-IsSystemContext)) {
    try {
        Start-SystemWorker
        Write-CleanupLog 'DELEGATED cleanup to SYSTEM worker'
        exit 0
    } catch {
        Write-CleanupLog ('SYSTEM_TASK_ERROR ' + $_.Exception.Message)
    }
}
for ($iteration = 0; $iteration -lt 12; $iteration++) {
    if (-not (Test-Path -LiteralPath $target)) { break }
    $entries = @(Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue)
    Write-CleanupLog ('ITERATION ' + $iteration + ' entries=' + $entries.Count)
    foreach ($entry in $entries) {
        Invoke-DrainWindowsOldEntry -EntryPath $entry.FullName
    }
    $rootRdCommand = 'rd /s /q "' + $target + '" >nul 2>nul'
    Invoke-BoundedNativeCommandWithExitCode -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/d', '/c', $rootRdCommand) -Label ('root rd ' + $target) -TimeoutSeconds 30 | Out-Null
    if (Test-Path -LiteralPath $target) {
        Start-Sleep -Seconds 2
    }
}
if (Test-Path -LiteralPath $target) {
    Write-CleanupLog 'FAILED target still exists'
    exit 1
}
Remove-PostBootTriggers
Remove-SystemTask
Write-CleanupLog 'DONE target absent'
exit 0
