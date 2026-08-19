[CmdletBinding()]
param(
  [string]$OutputRoot = (Join-Path $env:TEMP 'CDriveDeleteAuditSmoke')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$ScriptPath = Join-Path $ProjectRoot 'Invoke-CDriveDeleteAudit.ps1'

if (-not (Test-Path -LiteralPath $ScriptPath)) {
  throw "Main script not found: $ScriptPath"
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors)
if ($errors -and $errors.Count -gt 0) {
  $errors | ForEach-Object { Write-Host $_.Message -ForegroundColor Red }
  throw "PowerShell parser found $($errors.Count) error(s)."
}

if (Test-Path -LiteralPath $OutputRoot) {
  Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -Top 1 -OutputRoot $OutputRoot -NoColor
$exit = $LASTEXITCODE
if ($exit -notin @(0, 2)) {
  throw "Read-only audit smoke test failed with exit code $exit."
}

$report = Get-ChildItem -LiteralPath $OutputRoot -Recurse -Filter 'top-delete-candidates.txt' -ErrorAction Stop | Select-Object -First 1
if (-not $report) {
  throw "No report was generated under $OutputRoot."
}

Write-Host "Smoke test passed. Report: $($report.FullName)"
