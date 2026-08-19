Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Elev {
    [DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr h, uint acc, out IntPtr t);
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint acc, bool inh, uint pid);
    [DllImport("advapi32.dll", SetLastError=true)] public static extern bool GetTokenInformation(IntPtr t, int cls, out uint info, uint len, out uint ret);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
}
"@
$pids = 110768, 23004, 23860, 31484, 29632
foreach ($id in $pids) {
    $h = [Elev]::OpenProcess(0x0400, $false, $id)
    if ($h -eq [IntPtr]::Zero) { Write-Output ("pid {0}: cannot open" -f $id); continue }
    $tok = [IntPtr]::Zero
    if (-not [Elev]::OpenProcessToken($h, 0x0008, [ref]$tok)) { Write-Output ("pid {0}: no token" -f $id); [void][Elev]::CloseHandle($h); continue }
    $elev = 0; $ret = 0
    [void][Elev]::GetTokenInformation($tok, 20, [ref]$elev, 4, [ref]$ret)
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    $name = if ($p) { $p.ProcessName } else { "?" }
    Write-Output ("pid {0,-8} {1,-28} elevated={2}" -f $id, $name, ($elev -ne 0))
    [void][Elev]::CloseHandle($tok)
    [void][Elev]::CloseHandle($h)
}
