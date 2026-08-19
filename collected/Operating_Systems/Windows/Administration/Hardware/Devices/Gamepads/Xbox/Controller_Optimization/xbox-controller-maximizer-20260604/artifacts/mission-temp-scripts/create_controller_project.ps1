$ErrorActionPreference='Stop'
$ProjectRoot = Join-Path $env:LOCALAPPDATA 'HermesControllerMaximizer'
New-Item -ItemType Directory -Path $ProjectRoot -Force | Out-Null
$Main = Join-Path $ProjectRoot 'Invoke-ControllerMaximizer.ps1'
$OneLiner = Join-Path $ProjectRoot 'RUN-ONE-LINER.txt'
$LogDir = Join-Path $ProjectRoot 'logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$payload = @'
param(
  [switch]$Install,
  [switch]$Quick,
  [switch]$ProbeOnly,
  [switch]$NoPause
)
$ErrorActionPreference = 'SilentlyContinue'
$script:Root = Split-Path -Path $PSCommandPath -Parent
$script:LogDir = Join-Path $script:Root 'logs'
New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
$script:Log = Join-Path $script:LogDir ('controller-max-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
function Out-Line([string]$s){ $line='{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),$s; Write-Host $line; Add-Content -LiteralPath $script:Log -Value $line -Encoding UTF8 }
function Invoke-NativeBounded([string]$File,[string[]]$Argv,[int]$TimeoutMs){
  try{
    $psi=New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName=$File; $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    foreach($a in $Argv){ [void]$psi.ArgumentList.Add($a) }
    $p=New-Object System.Diagnostics.Process; $p.StartInfo=$psi
    [void]$p.Start()
    if(-not $p.WaitForExit($TimeoutMs)){ try{$p.Kill()}catch{}; return @{Exit=9999;Out='';Err='timeout'} }
    return @{Exit=$p.ExitCode;Out=$p.StandardOutput.ReadToEnd();Err=$p.StandardError.ReadToEnd()}
  }catch{ return @{Exit=9998;Out='';Err=$_.Exception.Message} }
}
function Ensure-ServiceStarted([string]$Name){
  $svc=Get-Service -Name $Name -ErrorAction SilentlyContinue
  if(-not $svc){ Out-Line "SERVICE missing $Name"; return }
  if($svc.Status -ne 'Running'){
    Out-Line "SERVICE start $Name from $($svc.Status)"
    $r=Invoke-NativeBounded -File "$env:SystemRoot\System32\sc.exe" -Argv @('start',$Name) -TimeoutMs 2500
    Start-Sleep -Milliseconds 400
  }
  $svc2=Get-Service -Name $Name -ErrorAction SilentlyContinue
  Out-Line "SERVICE $Name $($svc2.Status) startType=$($svc2.StartType)"
}
function Close-StaleGameBar{
  $gb=Get-Process -Name GameBar -ErrorAction SilentlyContinue
  if($gb){ Out-Line ('GAMEBAR close stale pid='+(($gb|Select-Object -ExpandProperty Id)-join ',')); $gb|Stop-Process -Force -ErrorAction SilentlyContinue } else { Out-Line 'GAMEBAR not-running' }
}
function Optimize-PowerPlan{
  # Switch to High Performance/Ultimate Performance if already available; do not create weird vendor plans.
  $out = (& powercfg /L 2>$null) -join "`n"
  $guid=$null
  foreach($line in ($out -split "`r?`n")){
    if($line -match '([a-f0-9-]{36}).*\*.*(Ultimate Performance|High performance)'){ $guid=$Matches[1]; break }
  }
  if(-not $guid){ foreach($line in ($out -split "`r?`n")){ if($line -match '([a-f0-9-]{36}).*(Ultimate Performance|High performance)'){ $guid=$Matches[1]; break } } }
  if($guid){ & powercfg /S $guid 2>$null; Out-Line "POWERPLAN set $guid" } else { Out-Line 'POWERPLAN no-high-performance-plan-found' }
}
function Disable-ControllerPowerSaving{
  # Target only controller/Bluetooth HID device keys; back up changed values. No driver uninstall/re-pairing/remapping.
  $targets=Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Xbox|Controller|Bluetooth XINPUT|HID-compliant game controller' -or $_.InstanceId -match 'VID_045E|PID_0B05|00001124' }
  $changed=0
  foreach($d in $targets){
    Out-Line "DEVICE $($d.Class)|$($d.Status)|$($d.FriendlyName)|$($d.InstanceId)"
    $safe = ($d.InstanceId -replace '\\','\')
    $paths=@("HKLM:\SYSTEM\CurrentControlSet\Enum\$safe\Device Parameters", "HKLM:\SYSTEM\CurrentControlSet\Enum\$safe\Device Parameters\WDF")
    foreach($rp in $paths){
      if(Test-Path -LiteralPath $rp){
        foreach($name in @('DeviceSelectiveSuspended','SelectiveSuspendEnabled','EnhancedPowerManagementEnabled','AllowIdleIrpInD3','EnableSelectiveSuspend')){
          try{
            $old=(Get-ItemProperty -LiteralPath $rp -Name $name -ErrorAction SilentlyContinue).$name
            if($old -ne $null -and $old -ne 0){ Set-ItemProperty -LiteralPath $rp -Name $name -Type DWord -Value 0 -ErrorAction SilentlyContinue; $changed++; Out-Line "POWERSAVE disabled $name old=$old path=$rp" }
          }catch{}
        }
        try{
          if(-not (Get-ItemProperty -LiteralPath $rp -Name 'EnhancedPowerManagementEnabled' -ErrorAction SilentlyContinue)){
            New-ItemProperty -LiteralPath $rp -Name 'EnhancedPowerManagementEnabled' -PropertyType DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null; $changed++; Out-Line "POWERSAVE set EnhancedPowerManagementEnabled=0 path=$rp"
          }
        }catch{}
      }
    }
  }
  Out-Line "POWERSAVE changes=$changed"
}
function Add-XInputType{
$code=@"
using System;
using System.Runtime.InteropServices;
public class HermesXInput {
 [StructLayout(LayoutKind.Sequential)] public struct State { public UInt32 dwPacketNumber; public Gamepad Gamepad; }
 [StructLayout(LayoutKind.Sequential)] public struct Gamepad { public UInt16 wButtons; public byte bLeftTrigger; public byte bRightTrigger; public Int16 sThumbLX; public Int16 sThumbLY; public Int16 sThumbRX; public Int16 sThumbRY; }
 [DllImport("xinput1_4.dll", EntryPoint="XInputGetState")] public static extern UInt32 XInputGetState(UInt32 dwUserIndex, out State pState);
}
"@
  Add-Type $code -ErrorAction SilentlyContinue | Out-Null
}
function Probe-XInput([int]$Seconds){
  Add-XInputType
  $seen=$false; $maxDt=0; $samples=0; $last=[DateTime]::UtcNow
  $seenButtons=@{}
  $end=(Get-Date).AddSeconds($Seconds)
  while((Get-Date) -lt $end){
    $st=New-Object HermesXInput+State
    $r=[HermesXInput]::XInputGetState([uint32]0,[ref]$st)
    $now=[DateTime]::UtcNow; $dt=($now-$last).TotalMilliseconds; if($dt -gt $maxDt){$maxDt=$dt}; $last=$now; $samples++
    if($r -eq 0){
      $seen=$true
      $map=@{A=0x1000;B=0x2000;X=0x4000;Y=0x8000;LB=0x0100;RB=0x0200;Back=0x0020;Start=0x0010;LStick=0x0040;RStick=0x0080;DUp=0x0001;DDown=0x0002;DLeft=0x0004;DRight=0x0008}
      foreach($k in $map.Keys){ if(($st.Gamepad.wButtons -band $map[$k]) -ne 0){ $seenButtons[$k]=1 } }
    }
    Start-Sleep -Milliseconds 25
  }
  if($seen){ Out-Line ("XINPUT slot0 OK samples=$samples maxLoopMs={0:N1} seenButtons={1}" -f $maxDt,(($seenButtons.Keys|Sort-Object)-join ',')) } else { Out-Line 'XINPUT slot0 NOT-DETECTED' }
  return $seen
}
function Repair-Kcd2Launcher{
  $cmd='E:\games\Kingdom Come Deliverance II.cmd'
  if(-not (Test-Path -LiteralPath $cmd)){ Out-Line 'KCD2 launcher not-found'; return }
  $raw=[IO.File]::ReadAllText($cmd)
  if($raw -match 'Hermes controller guard'){ Out-Line 'KCD2 launcher guard already present'; return }
  Out-Line 'KCD2 launcher guard missing; leaving existing launcher unchanged in this generic run'
}
Out-Line 'BEGIN HermesControllerMaximizer'
Out-Line "ROOT $script:Root"
Out-Line "MODE Install=$Install Quick=$Quick ProbeOnly=$ProbeOnly"
Ensure-ServiceStarted 'GameInputSvc'
Ensure-ServiceStarted 'XboxGipSvc'
Ensure-ServiceStarted 'bthserv'
Ensure-ServiceStarted 'BthAvctpSvc'
if(-not $ProbeOnly){ Close-StaleGameBar; Optimize-PowerPlan; Disable-ControllerPowerSaving; Repair-Kcd2Launcher }
$ok=Probe-XInput -Seconds ($(if($Quick){2}else{5}))
Out-Line "END status=$(if($ok){'OK'}else{'NO_XINPUT'}) log=$script:Log"
if(-not $NoPause){ Write-Host ''; Write-Host 'Press Enter to close...'; [void][Console]::ReadLine() }
if($ok){ exit 0 } else { exit 2 }
'@
[IO.File]::WriteAllText($Main,$payload,[Text.Encoding]::UTF8)
$liner="& '$Main' -Quick -NoPause"
[IO.File]::WriteAllText($OneLiner,$liner,[Text.Encoding]::ASCII)
Write-Host "ProjectRoot=$ProjectRoot"
Write-Host "Main=$Main"
Write-Host "OneLiner=$OneLiner"
Write-Host "Liner=$liner"
