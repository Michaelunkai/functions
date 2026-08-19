#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================================
; HOTSTRINGS - Type these anywhere to trigger actions
; ============================================================================

; kkkk - Force kill the foreground application (no mercy)
:*:kkkk::
{
    hwnd := WinGetID("A")
    if (hwnd) {
        pid := WinGetPID("A")
        if (pid) {
            Run('taskkill /F /PID ' pid, , "Hide")
        }
    }
}

; yyyt - Open YouTube account chooser silently (no terminal window)
:*:yyyt::
{
    Run('powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "F:\backup\windowsapps\Credentials\youtube\login\a.ps1"', , "Hide")
}

; aboveit - Make current window always on top
:*:aboveit::
{
    hwnd := WinGetID("A")
    if (hwnd) {
        WinSetAlwaysOnTop(1, "ahk_id " hwnd)
        ToolTip("Window set to Always On Top")
        SetTimer(() => ToolTip(), -1500)
    }
}

; downit - Remove always on top from current window
:*:downit::
{
    hwnd := WinGetID("A")
    if (hwnd) {
        WinSetAlwaysOnTop(0, "ahk_id " hwnd)
        ToolTip("Always On Top removed")
        SetTimer(() => ToolTip(), -1500)
    }
}
