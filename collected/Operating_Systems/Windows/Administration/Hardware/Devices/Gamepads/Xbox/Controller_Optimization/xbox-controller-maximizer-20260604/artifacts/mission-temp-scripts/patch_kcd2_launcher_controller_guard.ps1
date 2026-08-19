$ErrorActionPreference='Stop'
$cmd='E:\games\Kingdom Come Deliverance II.cmd'
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup="$cmd.bak-$stamp"
Copy-Item -LiteralPath $cmd -Destination $backup -Force
$script=@'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$gameExe = 'E:\games\KingdomComeDeliverance2\Bin\Win64MasterMasterSteamPGO\KingdomCome.exe'
$trainerExe = 'E:\games\KingdomComeDeliverance2\FLiNG Trainer\Kingdom Come Deliverance II v1.1-v1.4 Plus 41 Trainer.exe'
$expectedProcess = 'KingdomCome'
# Hermes controller guard: make sure Windows' Xbox/GameInput stack is alive before KCD2 initializes input.
# This is intentionally limited to this launcher: no remapping, no driver reinstall, no Bluetooth re-pairing.
foreach ($svcName in @('GameInputSvc','XboxGipSvc','bthserv','BthAvctpSvc')) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') {
        try { Start-Service -Name $svcName -ErrorAction SilentlyContinue } catch {}
    }
}
# Game Bar showed HID access errors with this controller; closing a stale instance is safe and it auto-reopens on demand.
Get-Process -Name GameBar -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
if (-not (Test-Path -LiteralPath $gameExe)) { throw "Missing game executable: $gameExe" }
if (-not (Test-Path -LiteralPath $trainerExe)) { throw "Missing FLiNG trainer executable: $trainerExe" }
if ([System.IO.File]::ReadAllBytes($gameExe)[0..1] -join '' -ne '7790') { throw "Game executable is not a valid MZ executable: $gameExe" }
if ([System.IO.File]::ReadAllBytes($trainerExe)[0..1] -join '' -ne '7790') { throw "Trainer executable is not a valid MZ executable: $trainerExe" }
$gameProc = Get-Process -Name $expectedProcess -ErrorAction SilentlyContinue
if (-not $gameProc) {
    Start-Process -FilePath $gameExe -WorkingDirectory (Split-Path -Parent $gameExe)
    $deadline = (Get-Date).AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 500
        $gameProc = Get-Process -Name $expectedProcess -ErrorAction SilentlyContinue
    } while (-not $gameProc -and (Get-Date) -lt $deadline)
}
if (-not $gameProc) { Write-Warning "Started game, but process '$expectedProcess' was not visible within 20 seconds. Starting trainer anyway." }
$trainerProc = Get-Process | Where-Object { $_.Path -and ($_.Path -ieq $trainerExe) } | Select-Object -First 1
if (-not $trainerProc) { Start-Process -FilePath $trainerExe -WorkingDirectory (Split-Path -Parent $trainerExe) }
[Console]::WriteLine("Ready: game=$gameExe")
[Console]::WriteLine("Ready: FLiNG trainer=$trainerExe")
[Console]::WriteLine("Controller guard: GameInput/XboxGip/Bluetooth services checked before launch")
'@
$bytes=[Text.Encoding]::Unicode.GetBytes($script)
$enc=[Convert]::ToBase64String($bytes)
$cmdText="@echo off`r`nsetlocal EnableExtensions`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc`r`nif errorlevel 1 pause`r`n"
[IO.File]::WriteAllText($cmd,$cmdText,[Text.Encoding]::ASCII)
Write-Host "backup=$backup"
Write-Host "patched=$cmd"
