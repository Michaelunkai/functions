param([int]$TargetPid)
$ErrorActionPreference = 'Continue'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class MP2 {
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
}
"@
$target = $TargetPid
$HWND_MESSAGE = New-Object IntPtr -3
$h = [IntPtr]::Zero
$found = 0
do {
  $h = [MP2]::FindWindowEx($HWND_MESSAGE, $h, "AutoHotkey", $null)
  if ($h -ne [IntPtr]::Zero) {
    $pid2 = 0
    [MP2]::GetWindowThreadProcessId($h, [ref]$pid2) | Out-Null
    $cls = New-Object System.Text.StringBuilder 128
    $ttl = New-Object System.Text.StringBuilder 512
    [MP2]::GetClassName($h, $cls, 128) | Out-Null
    [MP2]::GetWindowText($h, $ttl, 512) | Out-Null
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $r = [IntPtr]::Zero
    $res = [MP2]::SendMessageTimeout($h, 0, [IntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$r)
    $sw.Stop()
    Write-Output ("hwnd={0} pid={1} cls={2} title='{3}' answered={4} ms={5}" -f $h, $pid2, $cls.ToString(), $ttl.ToString(), ($res -ne [IntPtr]::Zero), $sw.ElapsedMilliseconds)
    $found++
  }
} while ($h -ne [IntPtr]::Zero -and $found -lt 20)
Write-Output ("found {0} AutoHotkey message windows" -f $found)
