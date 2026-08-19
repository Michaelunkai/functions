param(
    [string]$ProjectRoot
)
$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$wscript = 'C:\Windows\System32\wscript.exe'
$script = Join-Path $ProjectRoot 'Invoke-allstart2.ps1'
$openVbs = Join-Path $ProjectRoot 'openspeedy-silent\openspeedy-silent.vbs'
$murmureVbs = Join-Path $ProjectRoot 'murmure-silent\murmure-silent.vbs'
$trayVbs = Join-Path $ProjectRoot 'trayquiet-start\trayquiet-start.vbs'
$required = @($wscript,$script,$openVbs,$murmureVbs,$trayVbs,'F:\backup\windowsapps\installed\OpenSpeedy\Speedy.exe','C:\Program Files\murmure\murmure.exe','C:\ProgramData\pip\docker.exe')
foreach ($p in $required) { if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Missing required file: $p" } }
$tokens=$null; $errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($script,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) { throw "Invoke-allstart2 parser errors: $($errors.Count)" }
function Invoke-VbsAndCheck([string]$Name,[string]$Vbs,[string[]]$Arguments,[string]$ExpectedProcessName) {
    $argList = @('//B','//Nologo', $Vbs) + @($Arguments)
    $p = Start-Process -FilePath $wscript -ArgumentList $argList -WindowStyle Hidden -PassThru
    if (-not $p.WaitForExit(15000)) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        throw "$Name wscript did not exit within 15 seconds"
    }
    if ($p.ExitCode -ne 0) { throw "$Name launcher exit code $($p.ExitCode)" }
    Start-Sleep -Milliseconds 800
    $present = $false
    if ($ExpectedProcessName) {
        $present = [bool](Get-Process -Name $ExpectedProcessName -ErrorAction SilentlyContinue | Select-Object -First 1)
        if (-not $present) { throw "$Name expected process not found: $ExpectedProcessName" }
    }
    [pscustomobject]@{Name=$Name; ExitCode=$p.ExitCode; ExpectedProcess=$ExpectedProcessName; ProcessPresent=$present}
}
$results = @()
$results += Invoke-VbsAndCheck -Name 'OpenSpeedy' -Vbs $openVbs -Arguments @() -ExpectedProcessName 'Speedy'
$results += Invoke-VbsAndCheck -Name 'Murmure' -Vbs $murmureVbs -Arguments @() -ExpectedProcessName 'murmure'
$results += Invoke-VbsAndCheck -Name 'TrayQuietDocker' -Vbs $trayVbs -Arguments @('C:\ProgramData\pip\docker.exe','0','0','1') -ExpectedProcessName $null
$stale = @(Get-CimInstance Win32_Process -Filter "Name='wscript.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match [regex]::Escape('C:\Users\micha\.claude\scripts\openspeedy-silent.vbs') -or $_.CommandLine -match [regex]::Escape('C:\Users\micha\.claude\scripts\murmure-silent.vbs') -or $_.CommandLine -match [regex]::Escape('C:\Users\micha\.claude\scripts\trayquiet-start.vbs') })
if ($stale.Count -gt 0) { throw "stale missing-path wscript still running: $($stale.Count)" }
$results | Format-List
'ALL_TESTS_PASSED'
