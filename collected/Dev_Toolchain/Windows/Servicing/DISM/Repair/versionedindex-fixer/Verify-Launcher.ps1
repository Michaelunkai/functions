[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$statusDir = Join-Path $projectRoot 'status'
New-Item -ItemType Directory -Path $statusDir -Force | Out-Null

$statusPath = Join-Path $statusDir 'latest-status.json'
$launcherPath = Join-Path $projectRoot 'Run-DismError2VersionedIndexFix.cmd'

$result = [ordered]@{
    startedAt = (Get-Date).ToString('o')
    launcher  = $launcherPath
    success   = $false
    exitCode  = $null
    finishedAt = $null
    error     = $null
}

try {
    $process = Start-Process -FilePath $launcherPath -Wait -PassThru -WindowStyle Hidden
    $result.exitCode = $process.ExitCode
    $result.success = ($process.ExitCode -eq 0)
}
catch {
    $result.error = $_.Exception.Message
}
finally {
    $result.finishedAt = (Get-Date).ToString('o')
    $result | ConvertTo-Json | Set-Content -Path $statusPath -Encoding ASCII
}
