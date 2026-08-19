$src = 'using System;
using System.Runtime.InteropServices;
public class Mon {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct DISPLAY_DEVICE {
        public uint cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString;
        public uint StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey;
    }
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern bool EnumDisplayDevices(string dev, uint index, ref DISPLAY_DEVICE info, uint flags);
}
'
Add-Type -TypeDefinition $src

function Get-Devices([string]$baseName) {
    $list = @()
    for ($i = 0; $i -lt 64; $i++) {
        $d = New-Object Mon+DISPLAY_DEVICE
        $d.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($d)
        if (-not [Mon]::EnumDisplayDevices($baseName, $i, [ref]$d, 0)) { break }
        $list += [pscustomobject]@{ Name=$d.DeviceName; String=$d.DeviceString; Flags=$d.StateFlags; Id=$d.DeviceID }
    }
    return $list
}

Write-Output "=== attached desktop displays (GDI name = AHK MonitorGetName) ==="
$adapters = Get-Devices $null
$index = 0
foreach ($a in $adapters) {
    if ($a.Flags -band 0x00000001) {
        $index++
        $mons = Get-Devices $a.Name
        $m = $null
        foreach ($mm in $mons) { $m = $mm }
        $id = if ($m) { $m.Id } else { "" }
        Write-Output ("AHK monitor #{0}  gdi={1}  adapter='{2}'  id='{3}'" -f $index, $a.Name, $a.String, $id)
        $identity = ($a.String + "|" + $id).ToLower()
        $isVirtual = $identity.Contains("virtual") -or $identity.Contains("indirect display") -or $identity.Contains("iddsample") -or $identity.Contains("mtt1337") -or ($identity -eq "|" -and $a.Name.ToLower().Contains("display10"))
        $tag = if ($isVirtual) { "VIRTUAL" } else { "PHYSICAL" }
        Write-Output ("           -> {0}" -f $tag)
    }
}
Write-Output "=== done ==="
