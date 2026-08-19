#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================================
; HOTKEYS - Keyboard shortcuts
; ============================================================================

; Win+W - Launch Wand and Nyrna
#w::
{
    Run('"C:\Users\User\AppData\Local\Wand\Wand.exe"')
    Run('"C:\Users\User\AppData\Roaming\Nyrna\nyrna.exe"')
}

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

; allit - Open Everything search
:*:allit::
{
    Run('"F:\backup\windowsapps\installed\Everything\everything.exe"')
}

; ddownloads - Open Downloads folder
:*:ddownloads::
{
    Run("explorer.exe shell:Downloads")
}

; rrer - Open new terminal
:*:rrer::
{
    Run("wt.exe")
}

; xccc - Open Google Chrome
:*:xccc::
{
    Run('"C:\Program Files\Google\Chrome\Application\chrome.exe"')
}

; ffff - Open Firefox
:*:ffff::
{
    Run('"F:\backup\windowsapps\installed\firefox\firefox.exe"')
}

; mymail - Copy email to clipboard
:*:mymail::
{
    A_Clipboard := "michaelovsky5@gmail.com"
    ToolTip("Email copied to clipboard")
    SetTimer(() => ToolTip(), -1500)
}

; myp - Copy password to clipboard
:*:myp::
{
    A_Clipboard := "Blackablacka3!"
    ToolTip("Password copied to clipboard")
    SetTimer(() => ToolTip(), -1500)
}

; toto - Open Todoist
:*:toto::
{
    Run('"C:\Program Files\WindowsApps\88449BC3.TodoistPlannerCalendarMSIX_9.26.2.0_x64__71ef4824z52ta\app\Todoist.exe"')
}

; pass - Copy password to clipboard
:*:pass::
{
    A_Clipboard := "Aa1111111!"
    ToolTip("Password copied to clipboard")
    SetTimer(() => ToolTip(), -1500)
}

; yyyy - Split latest used apps into 2 equal parts (left/right)
:*:yyyy::
{
    windows := GetRecentWindows(2)
    if (windows.Length < 2) {
        ToolTip("Need at least 2 windows")
        SetTimer(() => ToolTip(), -1500)
        return
    }
    MonitorGetWorkArea(, &mLeft, &mTop, &mRight, &mBottom)
    mWidth := mRight - mLeft
    mHeight := mBottom - mTop
    halfWidth := mWidth // 2

    ; First window - left half
    WinRestore("ahk_id " windows[1])
    WinMove(mLeft, mTop, halfWidth, mHeight, "ahk_id " windows[1])

    ; Second window - right half
    WinRestore("ahk_id " windows[2])
    WinMove(mLeft + halfWidth, mTop, halfWidth, mHeight, "ahk_id " windows[2])

    ToolTip("Split 2 windows")
    SetTimer(() => ToolTip(), -1500)
}

; tttt - Split latest used apps into 3 equal parts (thirds)
:*:tttt::
{
    windows := GetRecentWindows(3)
    if (windows.Length < 3) {
        ToolTip("Need at least 3 windows")
        SetTimer(() => ToolTip(), -1500)
        return
    }
    MonitorGetWorkArea(, &mLeft, &mTop, &mRight, &mBottom)
    mWidth := mRight - mLeft
    mHeight := mBottom - mTop
    thirdWidth := mWidth // 3

    ; First window - left third
    WinRestore("ahk_id " windows[1])
    WinMove(mLeft, mTop, thirdWidth, mHeight, "ahk_id " windows[1])

    ; Second window - middle third
    WinRestore("ahk_id " windows[2])
    WinMove(mLeft + thirdWidth, mTop, thirdWidth, mHeight, "ahk_id " windows[2])

    ; Third window - right third
    WinRestore("ahk_id " windows[3])
    WinMove(mLeft + (thirdWidth * 2), mTop, thirdWidth, mHeight, "ahk_id " windows[3])

    ToolTip("Split 3 windows")
    SetTimer(() => ToolTip(), -1500)
}

; Helper function to get recent windows (excluding desktop, taskbar, etc.)
GetRecentWindows(count) {
    windows := []
    excludeList := ["Program Manager", "Windows Input Experience", ""]

    for hwnd in WinGetList() {
        if (windows.Length >= count)
            break

        try {
            title := WinGetTitle("ahk_id " hwnd)
            class := WinGetClass("ahk_id " hwnd)
            style := WinGetStyle("ahk_id " hwnd)

            ; Skip empty titles and non-visible windows
            if (title = "" || !(style & 0x10000000))  ; WS_VISIBLE
                continue

            ; Skip taskbar, system tray, etc.
            if (class = "Shell_TrayWnd" || class = "Shell_SecondaryTrayWnd" || class = "Progman")
                continue

            ; Skip windows without caption bar (likely not app windows)
            if !(style & 0xC00000)  ; WS_CAPTION
                continue

            for exclude in excludeList {
                if (title = exclude)
                    continue 2
            }

            windows.Push(hwnd)
        }
    }
    return windows
}
