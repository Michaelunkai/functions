Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class FA {
  public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
"@
$cb = {
  param($h, $l)
  $sbT = New-Object System.Text.StringBuilder 512
  $sbC = New-Object System.Text.StringBuilder 128
  [FA]::GetWindowText($h, $sbT, 512) | Out-Null
  [FA]::GetClassName($h, $sbC, 128) | Out-Null
  $title = $sbT.ToString()
  $cls = $sbC.ToString()
  if ($title -match "current\.ahk|AutoHotkey|probe|hooktest" -or $cls -match "AutoHotkey") {
    $pid2 = 0
    [FA]::GetWindowThreadProcessId($h, [ref]$pid2) | Out-Null
    Write-Output ("hwnd={0} pid={1} visible={2} cls='{3}' title='{4}'" -f $h, $pid2, [FA]::IsWindowVisible($h), $cls, $title)
  }
  return $true
}
[FA]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
