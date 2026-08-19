$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'HermesControllerMaximizer'
$main=Join-Path $root 'Invoke-ControllerMaximizer.ps1'
$liner="& '$main' -Quick -NoPause"
# Parse script
$tokens=$null;$errs=$null;[System.Management.Automation.Language.Parser]::ParseFile($main,[ref]$tokens,[ref]$errs)|Out-Null
if($errs.Count){ throw (($errs|ForEach-Object {$_.Message}) -join '; ') }
# Parse one-liner
$tokens2=$null;$errs2=$null;[System.Management.Automation.Language.Parser]::ParseInput($liner,[ref]$tokens2,[ref]$errs2)|Out-Null
if($errs2.Count){ throw (($errs2|ForEach-Object {$_.Message}) -join '; ') }
[IO.File]::WriteAllText((Join-Path $root 'RUN-ONE-LINER.txt'),$liner,[Text.Encoding]::ASCII)
Set-Clipboard -Value $liner
$clip=Get-Clipboard -Raw
if($clip -ne $liner){ throw 'Clipboard readback mismatch' }
$sha=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($clip))).Replace('-','').ToLowerInvariant()
Write-Host "MAIN_PARSE=OK"
Write-Host "LINER_PARSE=OK"
Write-Host "CLIPBOARD=OK"
Write-Host "LENGTH=$($clip.Length)"
Write-Host "SHA256=$sha"
Write-Host "LINER=$clip"
