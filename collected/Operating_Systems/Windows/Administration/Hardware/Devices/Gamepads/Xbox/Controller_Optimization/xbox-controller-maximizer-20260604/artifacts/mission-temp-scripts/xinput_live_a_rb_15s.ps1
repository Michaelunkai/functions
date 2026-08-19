$ErrorActionPreference='SilentlyContinue'
$code=@"
using System;
using System.Runtime.InteropServices;
public class XIAProbe {
 [StructLayout(LayoutKind.Sequential)] public struct State { public UInt32 dwPacketNumber; public Gamepad Gamepad; }
 [StructLayout(LayoutKind.Sequential)] public struct Gamepad { public UInt16 wButtons; public byte bLeftTrigger; public byte bRightTrigger; public Int16 sThumbLX; public Int16 sThumbLY; public Int16 sThumbRX; public Int16 sThumbRY; }
 [DllImport("xinput1_4.dll", EntryPoint="XInputGetState")] public static extern UInt32 XInputGetState(UInt32 dwUserIndex, out State pState);
}
"@
Add-Type $code -ErrorAction SilentlyContinue
$seenA=$false; $seenRB=$false; $seenAny=$false; $lastPacket=-1
Write-Host '=== 15s XInput live A/RB capture ==='
$end=(Get-Date).AddSeconds(15)
while((Get-Date) -lt $end){
 $st=New-Object XIAProbe+State; $r=[XIAProbe]::XInputGetState([uint32]0,[ref]$st)
 if($r -eq 0){
  $a=(($st.Gamepad.wButtons -band 0x1000)-ne 0); $rb=(($st.Gamepad.wButtons -band 0x0200)-ne 0); $lb=(($st.Gamepad.wButtons -band 0x0100)-ne 0); $b=(($st.Gamepad.wButtons -band 0x2000)-ne 0)
  if($st.dwPacketNumber -ne $lastPacket -or $a -or $rb){
    '{0:HH:mm:ss.fff}|packet={1}|buttons=0x{2:X4}|A={3}|B={4}|RB={5}|LB={6}|LT={7}|RT={8}' -f (Get-Date),$st.dwPacketNumber,$st.Gamepad.wButtons,$a,$b,$rb,$lb,$st.Gamepad.bLeftTrigger,$st.Gamepad.bRightTrigger
    $lastPacket=$st.dwPacketNumber
  }
  if($a){$seenA=$true}; if($rb){$seenRB=$true}; if($st.Gamepad.wButtons -ne 0 -or $st.Gamepad.bLeftTrigger -ne 0 -or $st.Gamepad.bRightTrigger -ne 0){$seenAny=$true}
 } else { 'XInputResult='+$r }
 Start-Sleep -Milliseconds 80
}
'RESULT|seenA={0}|seenRB={1}|seenAnyButtonOrTrigger={2}' -f $seenA,$seenRB,$seenAny
