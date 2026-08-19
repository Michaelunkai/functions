$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$Csc='C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$Build=Join-Path $Root 'build'
$Dist=Join-Path $Root 'dist'
New-Item -ItemType Directory -Force -Path $Build,$Dist | Out-Null
& $Csc /nologo /optimize+ /warn:4 /target:library /out:"$Build\FastPurge.dll" "$Root\src\FastPurge\Program.cs"
if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }
& $Csc /nologo /optimize+ /warn:4 /target:exe /out:"$Dist\app.exe" "$Root\src\FastPurge\Program.cs"
if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }
& $Csc /nologo /optimize+ /warn:4 /target:exe /out:"$Build\FastPurge.Tests.exe" /reference:"$Build\FastPurge.dll" "$Root\tests\FastPurge.Tests\Program.cs"
if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }
Write-Host "BUILD OK $Dist\app.exe"
