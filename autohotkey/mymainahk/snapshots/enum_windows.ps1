param([int]$TargetPid)
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class EW {
  public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
}
"@
$target = $TargetPid
$count = 0
$cb = {
  param($h, $l)
  $script:count++
  $pid2 = 0
  [EW]::GetWindowThreadProcessId($h, [ref]$pid2) | Out-Null
  if ($pid2 -eq $target) {
    $sb = New-Object System.Text.StringBuilder 512
    [EW]::GetWindowText($h, $sb, 512) | Out-Null
    Write-Output ("PID-MATCH hwnd={0} visible={1} title='{2}'" -f $h, [EW]::IsWindowVisible($h), $sb.ToString())
  }
  return $true
}
[EW]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
Write-Output ("TOTAL windows enumerated: {0}" -f $count)
