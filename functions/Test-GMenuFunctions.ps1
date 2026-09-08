$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('gmenu-functions-test-'+[guid]::NewGuid().ToString('N'))
$savedUserProfile=$env:USERPROFILE
$passed=New-Object 'Collections.Generic.List[string]'
function Check([bool]$Condition,[string]$Name) {
    if(-not $Condition){throw "FAILED: $Name"}
    [void]$passed.Add($Name)
}
try {
    [void][IO.Directory]::CreateDirectory($root)
    $env:USERPROFILE=$root
    . (Join-Path $PSScriptRoot 'GMenuFunctions.ps1')
    $backupRoot=Join-Path $root '.gmenu\CommandBackups'
    [void][IO.Directory]::CreateDirectory($backupRoot)
    $backup=Join-Path $backupRoot 'gfixture.ps1'
    $text=@'
# GMENU GENERATED RESTORE COMMAND - PRIVATE RECOVERY KEY INCLUDED. Do not publish this script.
[CmdletBinding()]
param([string]$Value)
Write-Output ('GMENU_FIXTURE '+$Value)
'@
    [IO.File]::WriteAllText($backup,$text,(New-Object Text.UTF8Encoding($false)))
    Set-GMenuSavedCommandFunction 'gfixture' $backup
    $first=@(Invoke-GMenuSavedCommand -Name 'gfixture' -Arguments @('two words'))
    Check ($first.Count -eq 1 -and $first[0] -eq 'GMENU_FIXTURE two words') 'missing live command restores from protected backup'
    $commandPath=Join-Path $root '.gmenu\Commands\gfixture.ps1'
    Check (Test-Path -LiteralPath $commandPath -PathType Leaf) 'recovered command is installed at the live path'
    Remove-Item -LiteralPath $commandPath -Force
    $second=@(gfixture 'again')
    Check ($second[0] -eq 'GMENU_FIXTURE again' -and (Test-Path -LiteralPath $commandPath -PathType Leaf)) 'generated function self-heals after command deletion'
    Remove-Item -LiteralPath $commandPath,$backup -Force
    $rejected=$false;$message=''
    try {Invoke-GMenuSavedCommand -Name 'gfixture'} catch {$rejected=$true;$message=$_.Exception.Message}
    Check ($rejected -and $message -match 'protected backup' -and $message -notmatch 'CommandNotFoundException') 'missing private artifact reports a controlled repair message'
    $invalid=$false
    try {Invoke-GMenuSavedCommand -Name '../escape'} catch {$invalid=$true}
    Check $invalid 'path-like generated command names are rejected'
    [pscustomobject]@{Status='PASSED';PowerShell=$PSVersionTable.PSVersion.ToString();Tests=$passed.Count;Cases=$passed.ToArray()} | ConvertTo-Json -Depth 5
} finally {
    $env:USERPROFILE=$savedUserProfile
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
}
