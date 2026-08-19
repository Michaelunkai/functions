param([int]$TargetPid)
$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WProbe {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
  public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
}
"@
$target = $TargetPid
$cb = {
  param($h, $l)
  $pid2 = 0
  [WProbe]::GetWindowThreadProcessId($h, [ref]$pid2) | Out-Null
  if ($pid2 -eq $target) {
    $sb = New-Object System.Text.StringBuilder 512
    [WProbe]::GetWindowText($h, $sb, 512) | Out-Null
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $r = [IntPtr]::Zero
    $res = [WProbe]::SendMessageTimeout($h, 0, [IntPtr]::Zero, [IntPtr]::Zero, 2, 1500, [ref]$r)
    $sw.Stop()
    Write-Output ("hwnd={0} visible={1} title='{2}' answered={3} ms={4}" -f $h, [WProbe]::IsWindowVisible($h), $sb.ToString(), ($res -ne [IntPtr]::Zero), $sw.ElapsedMilliseconds)
  }
  return $true
}
[WProbe]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
