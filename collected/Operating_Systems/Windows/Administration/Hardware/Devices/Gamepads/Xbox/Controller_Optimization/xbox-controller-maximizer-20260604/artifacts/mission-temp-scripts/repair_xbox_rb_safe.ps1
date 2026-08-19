$ErrorActionPreference='Continue'
Write-Host '=== Safe Xbox controller repair actions ==='
# 1) Start Xbox accessory/Game Input Protocol service if present but stopped. This does not change mappings/pairing.
$svc = Get-Service -Name XboxGipSvc -ErrorAction SilentlyContinue
if($svc){
  if($svc.Status -ne 'Running'){
    Write-Host 'Starting XboxGipSvc...'
    Start-Service -Name XboxGipSvc -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
  } else { Write-Host 'XboxGipSvc already running' }
  $svc2 = Get-Service -Name XboxGipSvc -ErrorAction SilentlyContinue
  Write-Host ('XboxGipSvc={0}' -f $svc2.Status)
} else { Write-Host 'XboxGipSvc not installed/found' }
# 2) Close stuck Game Bar process if it has recent HID access errors. It auto-reopens on demand and does not change controller config.
$gb = Get-Process -Name GameBar -ErrorAction SilentlyContinue
if($gb){
  Write-Host ('Stopping GameBar processes: {0}' -f (($gb | Select-Object -ExpandProperty Id) -join ','))
  $gb | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 500
} else { Write-Host 'GameBar not running' }
# 3) Confirm core services still running.
Get-Service -Name GameInputSvc,bthserv,BthAvctpSvc,XboxGipSvc -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { '{0}|{1}|{2}' -f $_.Name,$_.Status,$_.StartType }
Write-Host '=== XInput re-probe ==='
$code = @"
using System;
using System.Runtime.InteropServices;
public class XI3 {
  [StructLayout(LayoutKind.Sequential)] public struct State { public UInt32 dwPacketNumber; public Gamepad Gamepad; }
  [StructLayout(LayoutKind.Sequential)] public struct Gamepad { public UInt16 wButtons; public byte bLeftTrigger; public byte bRightTrigger; public Int16 sThumbLX; public Int16 sThumbLY; public Int16 sThumbRX; public Int16 sThumbRY; }
  [DllImport("xinput1_4.dll", EntryPoint="XInputGetState")] public static extern UInt32 XInputGetState(UInt32 dwUserIndex, out State pState);
}
"@
Add-Type $code -ErrorAction SilentlyContinue
for($slot=0; $slot -lt 4; $slot++){
  $st = New-Object XI3+State
  $r = [XI3]::XInputGetState([uint32]$slot, [ref]$st)
  if($r -eq 0){ 'slot={0}|packet={1}|buttons=0x{2:X4}|RB={3}|LB={4}|LT={5}|RT={6}' -f $slot,$st.dwPacketNumber,$st.Gamepad.wButtons,(($st.Gamepad.wButtons -band 0x0200)-ne 0),(($st.Gamepad.wButtons -band 0x0100)-ne 0),$st.Gamepad.bLeftTrigger,$st.Gamepad.bRightTrigger }
}
