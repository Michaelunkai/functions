$ErrorActionPreference='SilentlyContinue'
Write-Host '=== Foreground window ==='
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Win32FG {
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
"@
$hwnd=[Win32FG]::GetForegroundWindow(); $sb=New-Object System.Text.StringBuilder 512; [void][Win32FG]::GetWindowText($hwnd,$sb,$sb.Capacity); $pid32=0; [void][Win32FG]::GetWindowThreadProcessId($hwnd,[ref]$pid32)
$p=Get-Process -Id $pid32 -ErrorAction SilentlyContinue
$fgPath=$null; if($p){ $fgPath=$p.Path }
'ForegroundPid={0}' -f $pid32
'ForegroundProcess={0}' -f $p.ProcessName
'ForegroundTitle={0}' -f $sb.ToString()
'ForegroundPath={0}' -f $fgPath
Write-Host '=== Likely game processes with windows ==='
Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.ProcessName -notmatch 'Telegram|chrome|explorer|powershell|WindowsTerminal|Code|ApplicationFrameHost|ShellExperienceHost|TextInputHost' } | Sort-Object StartTime -Descending | Select-Object -First 20 | ForEach-Object { '{0}|pid={1}|title={2}|path={3}' -f $_.ProcessName,$_.Id,$_.MainWindowTitle,$_.Path }
Write-Host '=== XInput live: press A/RB during this 8s sample if possible ==='
$code=@"
using System;
using System.Runtime.InteropServices;
public class XILive {
 [StructLayout(LayoutKind.Sequential)] public struct State { public UInt32 dwPacketNumber; public Gamepad Gamepad; }
 [StructLayout(LayoutKind.Sequential)] public struct Gamepad { public UInt16 wButtons; public byte bLeftTrigger; public byte bRightTrigger; public Int16 sThumbLX; public Int16 sThumbLY; public Int16 sThumbRX; public Int16 sThumbRY; }
 [DllImport("xinput1_4.dll", EntryPoint="XInputGetState")] public static extern UInt32 XInputGetState(UInt32 dwUserIndex, out State pState);
}
"@
Add-Type $code -ErrorAction SilentlyContinue
for($i=0; $i -lt 40; $i++){
 $st=New-Object XILive+State; $r=[XILive]::XInputGetState([uint32]0,[ref]$st)
 if($r -eq 0){
  $a=(($st.Gamepad.wButtons -band 0x1000)-ne 0); $rb=(($st.Gamepad.wButtons -band 0x0200)-ne 0); $lb=(($st.Gamepad.wButtons -band 0x0100)-ne 0); $b=(($st.Gamepad.wButtons -band 0x2000)-ne 0)
  if($a -or $rb -or $lb -or $b -or ($i % 10 -eq 0)){ '{0:HH:mm:ss.fff}|packet={1}|buttons=0x{2:X4}|A={3}|B={4}|RB={5}|LB={6}' -f (Get-Date),$st.dwPacketNumber,$st.Gamepad.wButtons,$a,$b,$rb,$lb }
 }
 Start-Sleep -Milliseconds 200
}
if($fgPath -and (Test-Path $fgPath)){
 Write-Host '=== Game executable imports/strings quick scan ==='
 'Path='+$fgPath
 $bytes=[System.IO.File]::ReadAllBytes($fgPath)
 $ascii=[System.Text.Encoding]::ASCII.GetString($bytes)
 foreach($s in 'xinput1_4.dll','xinput1_3.dll','XInputGetState','dinput8.dll','DirectInput','Gamepad','Controller','SteamInput'){
  if($ascii.IndexOf($s,[StringComparison]::OrdinalIgnoreCase) -ge 0){ 'FOUND:'+ $s }
 }
}
