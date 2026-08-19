param([int]$TargetPid)
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class FM {
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
}
"@
$HWND_MESSAGE = New-Object IntPtr -3
$h = [IntPtr]::Zero
$found = 0
do {
  $h = [FM]::FindWindowEx($HWND_MESSAGE, $h, $null, $null)
  if ($h -ne [IntPtr]::Zero) {
    $pid2 = 0
    [FM]::GetWindowThreadProcessId($h, [ref]$pid2) | Out-Null
    if ($TargetPid -eq 0 -or $pid2 -eq $TargetPid) {
      $cls = New-Object System.Text.StringBuilder 128
      $ttl = New-Object System.Text.StringBuilder 512
      [FM]::GetClassName($h, $cls, 128) | Out-Null
      [FM]::GetWindowText($h, $ttl, 512) | Out-Null
      Write-Output ("hwnd={0} pid={1} cls='{2}' title='{3}'" -f $h, $pid2, $cls.ToString(), $ttl.ToString())
      $found++
    }
  }
} while ($h -ne [IntPtr]::Zero -and $found -lt 100)
Write-Output ("total message-only windows matched: {0}" -f $found)
