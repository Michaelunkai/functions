Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$src = 'using System;
using System.Runtime.InteropServices;
using System.Text;
public class Inp2 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern short VkKeyScan(char c);
}
'
Add-Type -TypeDefinition $src

function Send-Keystrokes([string]$text) {
    foreach ($ch in $text.ToCharArray()) {
        $vk = [Inp2]::VkKeyScan($ch)
        $vkLow = $vk -band 0xFF
        $shift = ($vk -band 0x0100) -ne 0
        if ($shift) { [void][Inp2]::keybd_event(0x10, 0, 0, [UIntPtr]::Zero) }
        [void][Inp2]::keybd_event([byte]$vkLow, 0, 0, [UIntPtr]::Zero)
        [void][Inp2]::keybd_event([byte]$vkLow, 0, 2, [UIntPtr]::Zero)
        if ($shift) { [void][Inp2]::keybd_event(0x10, 0, 2, [UIntPtr]::Zero) }
        Start-Sleep -Milliseconds 60
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "AHK Probe Window"
$form.Size = New-Object System.Drawing.Size(420, 300)
$form.StartPosition = "Manual"
$form.Left = 80; $form.Top = 140
$form.Show()
$hwnd = $form.Handle
Start-Sleep -Milliseconds 600

$fg = [Inp2]::GetForegroundWindow()
$fgThread = 0
[void][Inp2]::GetWindowThreadProcessId($fg, [ref]$fgThread)
$myThread = [Inp2]::GetCurrentThreadId()
[void][Inp2]::AttachThreadInput($myThread, $fgThread, $true)
[void][Inp2]::SetForegroundWindow($hwnd)
[void][Inp2]::AttachThreadInput($myThread, $fgThread, $false)
Start-Sleep -Milliseconds 500
$fgOk = ([Inp2]::GetForegroundWindow() -eq $hwnd)
Write-Output ("foreground is probe: {0}" -f $fgOk)
if (-not $fgOk) { Write-Output "ABORT: could not focus probe window - not sending any keys"; $form.Close(); exit 1 }

Send-Keystrokes "mmon"
Write-Output "typed 'mmon' - capturing script monitor view..."
$captured = ""
$deadline = (Get-Date).AddSeconds(6)
while ((Get-Date) -lt $deadline -and $captured -eq "") {
    $found2 = [System.Collections.ArrayList]::new()
    $cb = [Inp2+EnumProc]{ param($h, $l)
        $sb = New-Object System.Text.StringBuilder 512
        [void][Inp2]::GetWindowText($h, $sb, 512)
        if ($sb.ToString() -like "Monitor Layout*") { [void]$script:found2.Add($h) }
        return $true
    }
    [void][Inp2]::EnumWindows($cb, [IntPtr]::Zero)
    if ($found2.Count -gt 0) {
        $dlg = $found2[0]
        $cb2 = [Inp2+EnumProc]{ param($h, $l)
            $sb = New-Object System.Text.StringBuilder 512
            [void][Inp2]::GetWindowText($h, $sb, 512)
            if ($sb.Length -gt 0) { $script:captured += $sb.ToString() + "`n" }
            return $true
        }
        [void][Inp2]::EnumWindows($cb2, [IntPtr]::Zero)
        $sbD = New-Object System.Text.StringBuilder 512
        [void][Inp2]::GetWindowText($dlg, $sbD, 512)
        $script:captured += "DLG: " + $sbD.ToString()
        break
    }
    Start-Sleep -Milliseconds 150
}
Write-Output "=== script monitor view ==="
Write-Output $captured
Start-Sleep -Milliseconds 1500

$screenBefore = [System.Windows.Forms.Screen]::FromHandle($hwnd)
$bBefore = $form.Bounds
[void][Inp2]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 120
[void][Inp2]::keybd_event(0x31, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 80
[void][Inp2]::keybd_event(0x31, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 120
[void][Inp2]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)
Write-Output "sent Ctrl+1..."
Start-Sleep -Milliseconds 2500
$screenAfter = [System.Windows.Forms.Screen]::FromHandle($hwnd)
$bAfter = $form.Bounds
Write-Output ("BEFORE ctrl+1: screen={0} {1},{2} {3}x{4}" -f $screenBefore.DeviceName, $bBefore.X, $bBefore.Y, $bBefore.Width, $bBefore.Height)
Write-Output ("AFTER  ctrl+1: screen={0} {1},{2} {3}x{4}" -f $screenAfter.DeviceName, $bAfter.X, $bAfter.Y, $bAfter.Width, $bAfter.Height)
$moved = ($screenBefore.DeviceName -ne $screenAfter.DeviceName) -or ($bAfter.Width -gt $bBefore.Width + 100)
Write-Output ("RESULT ctrl+1 moved window: {0}" -f $moved)

$form.Close()
