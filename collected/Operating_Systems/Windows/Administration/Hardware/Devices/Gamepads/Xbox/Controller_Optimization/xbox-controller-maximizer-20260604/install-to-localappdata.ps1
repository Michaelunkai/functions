$ErrorActionPreference='Stop'
$RepoRoot = Split-Path -Path $PSCommandPath -Parent
$Dest = Join-Path $env:LOCALAPPDATA 'HermesControllerMaximizer'
New-Item -ItemType Directory -Path $Dest -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $RepoRoot 'scripts\Invoke-ControllerMaximizer.ps1') -Destination (Join-Path $Dest 'Invoke-ControllerMaximizer.ps1') -Force
$liner = "& '$Dest\Invoke-ControllerMaximizer.ps1' -Quick -NoPause"
[IO.File]::WriteAllText((Join-Path $Dest 'RUN-ONE-LINER.txt'), $liner, [Text.Encoding]::ASCII)
Set-Clipboard -Value $liner
Write-Host "Installed: $Dest"
Write-Host "Clipboard one-liner: $liner"
