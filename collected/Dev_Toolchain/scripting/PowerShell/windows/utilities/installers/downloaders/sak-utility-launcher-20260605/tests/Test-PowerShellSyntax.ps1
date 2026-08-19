$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'run-sak-utility.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Missing primary script: $scriptPath"
}
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_.Message }
    exit 1
}
Write-Host "PowerShell syntax OK: $scriptPath"
