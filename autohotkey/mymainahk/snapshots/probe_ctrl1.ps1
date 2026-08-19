Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$src = 'using System;
using System.Runtime.InteropServices;
public class Inp {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
'
Add-Type -TypeDefinition $src

# Create a small probe window
$form = New-Object System.Windows.Forms.Form
$form.Text = "AHK Probe Window - ctrl1 test"
$form.Size = New-Object System.Drawing.Size(400, 300)
$form.StartPosition = "Manual"
$form.Left = 60; $form.Top = 120
$form.Show()
$hwnd = $form.Handle
Start-Sleep -Milliseconds 800

$screenBefore = [System.Windows.Forms.Screen]::FromHandle($hwnd)
$boundsBefore = $form.Bounds
Write-Output ("BEFORE: screen='{0}' bounds={1},{2} {3}x{4}" -f $screenBefore.DeviceName, $boundsBefore.X, $boundsBefore.Y, $boundsBefore.Width, $boundsBefore.Height)

[void][Inp]::SetForegroundWindow($hwnd)
Start-Sleep -Milliseconds 600
$fg = [Inp]::GetForegroundWindow()
Write-Output ("foreground is probe: {0}" -f ($fg -eq $hwnd))

# Send real Ctrl+1 (VK_CONTROL=0x11, '1'=0x31)
[void][Inp]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 120
[void][Inp]::keybd_event(0x31, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 80
[void][Inp]::keybd_event(0x31, 0, 2, [UIntPtr]::Zero)   # KEYUP
Start-Sleep -Milliseconds 120
[void][Inp]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)   # KEYUP
Write-Output "sent Ctrl+1 - waiting for hotkey..."
Start-Sleep -Milliseconds 2500

$screenAfter = [System.Windows.Forms.Screen]::FromHandle($hwnd)
$boundsAfter = $form.Bounds
Write-Output ("AFTER:  screen='{0}' bounds={1},{2} {3}x{4}" -f $screenAfter.DeviceName, $boundsAfter.X, $boundsAfter.Y, $boundsAfter.Width, $boundsAfter.Height)

$moved = ($screenBefore.DeviceName -ne $screenAfter.DeviceName) -or ($boundsAfter.Width -gt $boundsBefore.Width + 100)
Write-Output ("RESULT: hotkey moved/resized window = {0}" -f $moved)

$form.Close()
