$ErrorActionPreference='SilentlyContinue'
Write-Host '=== Matching devices ==='
Get-PnpDevice | Where-Object { $_.FriendlyName -match 'Xbox|Wireless Controller|Controller|XINPUT|Gamepad|HID-compliant game controller' -or $_.InstanceId -match 'VID_045E|PID_0B05|IG_00|00001124' } | Sort-Object Class,FriendlyName | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.Class,$_.Status,$_.FriendlyName,$_.InstanceId }
Write-Host '=== Key services ==='
Get-Service -Name GameInputSvc,bthserv,BthAvctpSvc,XboxGipSvc,GamingServices,GamingServicesNet -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { '{0}|{1}|{2}' -f $_.Name,$_.Status,$_.StartType }
Write-Host '=== XInput short probe ==='
$code = @"
using System;
using System.Runtime.InteropServices;
public class XI2 {
  [StructLayout(LayoutKind.Sequential)] public struct State { public UInt32 dwPacketNumber; public Gamepad Gamepad; }
  [StructLayout(LayoutKind.Sequential)] public struct Gamepad { public UInt16 wButtons; public byte bLeftTrigger; public byte bRightTrigger; public Int16 sThumbLX; public Int16 sThumbLY; public Int16 sThumbRX; public Int16 sThumbRY; }
  [DllImport("xinput1_4.dll", EntryPoint="XInputGetState")] public static extern UInt32 XInputGetState(UInt32 dwUserIndex, out State pState);
}
"@
Add-Type $code -ErrorAction SilentlyContinue
$seen=$false
for($slot=0; $slot -lt 4; $slot++){
  $st = New-Object XI2+State
  $r = [XI2]::XInputGetState([uint32]$slot, [ref]$st)
  if($r -eq 0){ $seen=$true; 'slot={0}|packet={1}|buttons=0x{2:X4}|RB={3}|LB={4}|A={5}|B={6}|LT={7}|RT={8}' -f $slot,$st.dwPacketNumber,$st.Gamepad.wButtons,(($st.Gamepad.wButtons -band 0x0200)-ne 0),(($st.Gamepad.wButtons -band 0x0100)-ne 0),(($st.Gamepad.wButtons -band 0x1000)-ne 0),(($st.Gamepad.wButtons -band 0x2000)-ne 0),$st.Gamepad.bLeftTrigger,$st.Gamepad.bRightTrigger }
}
if(-not $seen){ 'No XInput pads detected' }
Write-Host '=== Recent controller events ==='
Get-WinEvent -LogName System -MaxEvents 250 | Where-Object { $_.ProviderName -match 'HidBth|BTHUSB|GameInput|Devices-AccessBroker' -or $_.Message -match 'VID_045e|PID_0b05|Xbox|Controller|HID device|Bluetooth HID' } | Select-Object -First 8 | ForEach-Object { '{0}|{1}|{2}|{3}|{4}' -f $_.TimeCreated.ToString('s'),$_.ProviderName,$_.Id,$_.LevelDisplayName,($_.Message -replace "`r?`n",' ' -replace '\s+',' ') }
