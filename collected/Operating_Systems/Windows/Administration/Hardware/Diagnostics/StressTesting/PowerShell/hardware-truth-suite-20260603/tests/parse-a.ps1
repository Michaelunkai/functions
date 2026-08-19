$p = 'F:\study\Operating_Systems\Windows\Administration\Hardware\Diagnostics\StressTesting\PowerShell\hardware-truth-suite-20260603\a.ps1'
$tokens = $null
$errors = $null
if (-not (Test-Path -LiteralPath $p)) { throw "Missing script: $p" }
[System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  $errors | Format-List *
  exit 1
}
'PARSE_OK'
