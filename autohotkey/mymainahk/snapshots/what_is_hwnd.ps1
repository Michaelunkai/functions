param([long]$Hwnd)
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WI {
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsHungAppWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
}
"@
$h = New-Object IntPtr $Hwnd
if (-not [WI]::IsWindow($h)) { Write-Output "not a window (anymore)"; exit }
$pid2 = 0
[WI]::GetWindowThreadProcessId($h, [ref]$pid2) | Out-Null
$sbT = New-Object System.Text.StringBuilder 512
$sbC = New-Object System.Text.StringBuilder 128
[WI]::GetWindowText($h, $sbT, 512) | Out-Null
[WI]::GetClassName($h, $sbC, 128) | Out-Null
Write-Output ("hwnd={0} pid={1} visible={2} hung={3} iconic={4} zoomed={5} cls='{6}' title='{7}'" -f $Hwnd, $pid2, [WI]::IsWindowVisible($h), [WI]::IsHungAppWindow($h), [WI]::IsIconic($h), [WI]::IsZoomed($h), $sbC.ToString(), $sbT.ToString())
$p = Get-Process -Id $pid2 -ErrorAction SilentlyContinue
if ($p) {
  Write-Output ("proc={0} path={1} start={2} responding={3}" -f $p.ProcessName, $p.Path, $p.StartTime, $p.Responding)
}
