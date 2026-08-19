$ErrorActionPreference='SilentlyContinue'
Write-Host '=== Post-repair controller/device verification ==='
Get-PnpDevice | Where-Object { $_.FriendlyName -match 'Xbox Elite Wireless Controller|Bluetooth XINPUT-compatible input device|HID-compliant game controller' -or $_.InstanceId -match 'VID_045E&PID_0B05|PID&0B05' } | Sort-Object Class,FriendlyName | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.Class,$_.Status,$_.FriendlyName,$_.InstanceId }
Write-Host '=== Services ==='
Get-Service -Name GameInputSvc,bthserv,BthAvctpSvc,XboxGipSvc -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { '{0}|{1}|{2}' -f $_.Name,$_.Status,$_.StartType }
Write-Host '=== XInput stability sample ==='
$code = @"
using System;
using System.Runtime.InteropServices;
public class XI4 {
  [StructLayout(LayoutKind.Sequential)] public struct State { public UInt32 dwPacketNumber; public Gamepad Gamepad; }
  [StructLayout(LayoutKind.Sequential)] public struct Gamepad { public UInt16 wButtons; public byte bLeftTrigger; public byte bRightTrigger; public Int16 sThumbLX; public Int16 sThumbLY; public Int16 sThumbRX; public Int16 sThumbRY; }
  [DllImport("xinput1_4.dll", EntryPoint="XInputGetState")] public static extern UInt32 XInputGetState(UInt32 dwUserIndex, out State pState);
}
"@
Add-Type $code -ErrorAction SilentlyContinue
for($i=1; $i -le 3; $i++){
 $st=New-Object XI4+State; $r=[XI4]::XInputGetState([uint32]0,[ref]$st)
 'sample={0}|result={1}|packet={2}|buttons=0x{3:X4}|RB={4}|LB={5}' -f $i,$r,$st.dwPacketNumber,$st.Gamepad.wButtons,(($st.Gamepad.wButtons -band 0x0200)-ne 0),(($st.Gamepad.wButtons -band 0x0100)-ne 0)
 Start-Sleep -Milliseconds 700
}
