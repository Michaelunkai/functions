[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$files = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.psm1') }
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        throw "Parser errors in $($file.FullName): $($errors[0].Message)"
    }
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Install-Or-Update-LocalAI.ps1') -SelfTest -SkipMutation
if ($LASTEXITCODE -ne 0) { throw 'Install-Or-Update-LocalAI.ps1 -SelfTest failed.' }
Write-Host 'SELFTEST_OK'
