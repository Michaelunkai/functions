# Run the GameSave Manager latest-version repair/update script from this repo.
$ErrorActionPreference = 'Stop'
$ScriptPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'scripts\repair_gamesavemanager_latest.ps1'
if (-not (Test-Path -LiteralPath $ScriptPath)) { throw "Missing repair script: $ScriptPath" }
& $ScriptPath @args
exit $LASTEXITCODE
