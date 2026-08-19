$ErrorActionPreference = 'Stop'

param(
    [string]$TracePath
)

function Get-LatestTracePath {
    $traceDir = Split-Path -Path $PSScriptRoot -Parent
    $workspaceRoot = 'C:\Users\micha\Documents\Codex\2026-06-28\019f0ed5-f076-7f62-916f-4f7edcb57ce6-container'
    $candidates = @()
    if ($TracePath -and (Test-Path -LiteralPath $TracePath)) {
        return $TracePath
    }
    if (Test-Path -LiteralPath $workspaceRoot) {
        $candidates += Get-ChildItem -LiteralPath $workspaceRoot -Filter 'winupg-live-trace-*.log' -ErrorAction SilentlyContinue
    }
    if ($candidates.Count -eq 0) {
        return $null
    }
    return ($candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName)
}

function Get-LiveSnapshot {
    param(
        [string]$ResolvedTracePath
    )

    $traceLines = @()
    $traceItem = $null
    if ($ResolvedTracePath -and (Test-Path -LiteralPath $ResolvedTracePath)) {
        $traceItem = Get-Item -LiteralPath $ResolvedTracePath -Force
        $traceLines = @(Get-Content -LiteralPath $ResolvedTracePath -Tail 40 -ErrorAction SilentlyContinue)
    }

    $lastHeartbeat = $traceLines | Where-Object { $_ -match 'SETUP heartbeat' } | Select-Object -Last 1
    $actualPercent = $null
    if ($lastHeartbeat -and $lastHeartbeat -match 'Progress percentage \[(\d+)\]') {
        $actualPercent = [decimal]$Matches[1]
    }

    $setupProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -in @('setup.exe', 'setupprep.exe', 'SetupHost.exe')
    } | Select-Object Name, ProcessId)

    $runnerProcess = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*repair-upgrade.ps1*'
    } | Select-Object -First 1

    return [pscustomobject]@{
        TracePath = $ResolvedTracePath
        TraceItem = $traceItem
        TraceLines = $traceLines
        LastHeartbeat = $lastHeartbeat
        ActualPercent = $actualPercent
        SetupProcesses = $setupProcesses
        RunnerProcess = $runnerProcess
    }
}

$host.UI.RawUI.WindowTitle = 'Windows Repair Upgrade Live Monitor'
$lastRendered = $null
while ($true) {
    $resolvedTracePath = Get-LatestTracePath
    $snapshot = Get-LiveSnapshot -ResolvedTracePath $resolvedTracePath
    $now = Get-Date
    $traceAgeSeconds = if ($snapshot.TraceItem) { [math]::Round(($now - $snapshot.TraceItem.LastWriteTime).TotalSeconds, 2) } else { $null }
    $actualPercentText = if ($snapshot.ActualPercent -ne $null) { '{0:N2}%' -f $snapshot.ActualPercent } else { 'n/a' }
    $runnerText = if ($snapshot.RunnerProcess) { "PID $($snapshot.RunnerProcess.ProcessId)" } else { 'not running' }
    $setupText = if ($snapshot.SetupProcesses.Count -gt 0) {
        ($snapshot.SetupProcesses | ForEach-Object { '{0}:{1}' -f $_.Name, $_.ProcessId }) -join ', '
    } else {
        'none'
    }
    $heartbeatText = if ($snapshot.LastHeartbeat) { $snapshot.LastHeartbeat } else { '(no setup heartbeat yet)' }
    $render = @(
        ('Time:        {0}' -f $now.ToString('yyyy-MM-dd HH:mm:ss.fff'))
        ('Trace:       {0}' -f $(if ($snapshot.TracePath) { $snapshot.TracePath } else { '(none)' }))
        ('Trace age:   {0}' -f $(if ($traceAgeSeconds -ne $null) { "$traceAgeSeconds s" } else { 'n/a' }))
        ('Actual pct:  {0}' -f $actualPercentText)
        ('Runner:      {0}' -f $runnerText)
        ('Setup procs: {0}' -f $setupText)
        ('Last signal: {0}' -f $heartbeatText)
    ) -join [Environment]::NewLine

    if ($render -ne $lastRendered) {
        Clear-Host
        Write-Host $render -ForegroundColor Cyan
        $lastRendered = $render
    }

    if (-not $snapshot.RunnerProcess -and $snapshot.SetupProcesses.Count -eq 0) {
        Write-Host ''
        Write-Host 'Monitoring finished: no repair-upgrade runner and no setup processes remain.' -ForegroundColor Green
        break
    }

    Start-Sleep -Milliseconds 250
}

Write-Host ''
Write-Host 'Press Enter to close this monitor window.' -ForegroundColor DarkGray
[void][Console]::ReadLine()
