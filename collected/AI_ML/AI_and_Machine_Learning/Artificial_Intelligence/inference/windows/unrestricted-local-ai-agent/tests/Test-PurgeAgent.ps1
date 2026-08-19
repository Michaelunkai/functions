$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'purge_agent.ps1'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Purge script not found: $scriptPath"
}

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    throw ('Purge PowerShell parser errors: ' + (($parseErrors | ForEach-Object Message) -join '; '))
}

$content = [IO.File]::ReadAllText($scriptPath)
foreach ($required in @(
    'function Test-OwnedDeploymentRoot',
    'function Assert-SafePurgeTree',
    'function Stop-DeploymentProcesses',
    'function Invoke-DeploymentPurge',
    'function Invoke-PurgeSelfTest',
    'PURGE_PLAN: PASS',
    'PURGE_RESULT: PASS',
    'PURGE_SELF_TEST: PASS',
    '.portable-agent-root.json',
    'deployment-root.txt',
    'Refusing to purge because a reparse point exists',
    'Refusing to purge a protected root'
)) {
    if ($content.IndexOf($required, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "Missing purge implementation marker: $required"
    }
}

$selfTestOutput = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $scriptPath -SelfTest 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Purge self-test failed: $($selfTestOutput -join [Environment]::NewLine)"
}
if (($selfTestOutput -join "`n") -notmatch 'PURGE_SELF_TEST: PASS') {
    throw 'Purge self-test did not emit its PASS marker.'
}

Write-Output 'PURGE_AGENT_TEST: PASS'
