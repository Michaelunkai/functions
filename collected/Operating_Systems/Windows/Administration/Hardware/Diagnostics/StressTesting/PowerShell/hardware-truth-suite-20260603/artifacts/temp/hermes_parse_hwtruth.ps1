$p = 'F:\Downloads\A\a.ps1'
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  $errors | Format-List *
  exit 1
}
'PARSE_OK'
