[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$script = Join-Path $root 'scripts\Repair-WSL2-Permanent.ps1'

if (-not (Test-Path -LiteralPath $script)) {
    throw "Repair script not found: $script"
}

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_.Message }
    throw 'PowerShell parser check failed'
}
Write-Host 'PARSE_OK'

& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $script -SelfTest
if ($LASTEXITCODE -ne 0) {
    throw "SelfTest failed with exit code $LASTEXITCODE"
}

$content = Get-Content -LiteralPath $script -Raw
$oldWorkspacePattern = [regex]'C:\\Users\\micha\\Documents\\Codex\\20[0-9]{2}-[0-9]{2}-[0-9]{2}\\'
if ($oldWorkspacePattern.IsMatch($content)) {
    throw 'Script still depends on an old C-drive Codex workspace path'
}
Write-Host 'NO_OLD_C_WORKSPACE_DEPENDENCY'

Write-Host 'TESTS_OK'
