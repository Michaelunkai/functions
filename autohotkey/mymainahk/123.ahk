#Requires AutoHotkey v2.0
#SingleInstance Force

A_TrayMenu.Delete()
A_TrayMenu.Add("Reload", (*) => Reload())
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Reload"
A_IconTip := "MyMainAHK"

; ============================================================================
; MONITOR MANAGEMENT FUNCTIONS
; ============================================================================
; This section provides robust multi-monitor management functionality including:
; - Monitor detection and enumeration
; - Window-to-monitor mapping and detection
; - Window movement between monitors with edge case handling
; - Monitor focus switching with cursor positioning
; - Fullscreen, maximized, and spanning window support
; ============================================================================

; Get detailed information about all monitors
; This function enumerates all connected monitors and retrieves their properties
; Returns: Map where key is monitor index (1-based), value is Map of monitor properties
;   Properties include: left, top, right, bottom, width, height,
;                      workLeft, workTop, workRight, workBottom, workWidth, workHeight,
;                      name, isPrimary
GetMonitorInfo() {
    monitors := Map()
    monitorCount := MonitorGetCount()

    Loop monitorCount {
        monIndex := A_Index
        monitors[monIndex] := Map()

        ; Get full monitor bounds
        MonitorGet(monIndex, &mLeft, &mTop, &mRight, &mBottom)
        monitors[monIndex]["left"] := mLeft
        monitors[monIndex]["top"] := mTop
        monitors[monIndex]["right"] := mRight
        monitors[monIndex]["bottom"] := mBottom
        monitors[monIndex]["width"] := mRight - mLeft
        monitors[monIndex]["height"] := mBottom - mTop

        ; Get work area (excluding taskbar)
        MonitorGetWorkArea(monIndex, &wLeft, &wTop, &wRight, &wBottom)
        monitors[monIndex]["workLeft"] := wLeft
        monitors[monIndex]["workTop"] := wTop
        monitors[monIndex]["workRight"] := wRight
        monitors[monIndex]["workBottom"] := wBottom
        monitors[monIndex]["workWidth"] := wRight - wLeft
        monitors[monIndex]["workHeight"] := wBottom - wTop

        ; Get monitor name
        monitors[monIndex]["name"] := MonitorGetName(monIndex)

        ; Check if primary monitor
        monitors[monIndex]["isPrimary"] := MonitorGetPrimary() = monIndex
    }

    return monitors
}

; Get which monitor a window is currently on
; Parameters:
;   hwnd - Window handle to check
; Returns: Monitor number (1-based), defaults to 1 if detection fails
GetWindowMonitor(hwnd) {
    ; Validate window handle
    if (!hwnd || !WinExist("ahk_id " hwnd)) {
        return 1  ; Default to monitor 1 if window doesn't exist
    }

    try {
        WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " hwnd)

        ; Validate window dimensions
        if (winW <= 0 || winH <= 0) {
            return 1  ; Invalid window size
        }

        winCenterX := winX + (winW // 2)
        winCenterY := winY + (winH // 2)

        monitorCount := MonitorGetCount()
        if (monitorCount < 1) {
            return 1  ; No monitors detected, default to 1
        }

        Loop monitorCount {
            MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)
            if (winCenterX >= mLeft && winCenterX < mRight &&
                winCenterY >= mTop && winCenterY < mBottom) {
                return A_Index
            }
        }
    } catch {
        ; Any error defaults to monitor 1
    }

    return 1  ; Default to monitor 1 if detection fails
}

; Enumerate all windows grouped by monitor
; This function scans all visible windows and groups them by which monitor they're on
; It filters out system windows, invisible windows, tool windows, and tiny windows
; The grouping is based on window center point location
; Returns: Map where key is monitor number (1-based), value is array of window handles (hwnd)
;   - Only includes visible application windows with titles
;   - Excludes: Shell_TrayWnd, Progman, WorkerW, tool windows, windows < 50x50px
EnumerateWindowsByMonitor() {
    monitorCount := MonitorGetCount()
    windowsByMonitor := Map()

    ; Initialize map with empty arrays for each monitor
    Loop monitorCount {
        windowsByMonitor[A_Index] := []
    }

    ; Get monitor bounds for each monitor
    monitorBounds := []
    Loop monitorCount {
        MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)
        monitorBounds.Push(Map(
            "left", mLeft,
            "top", mTop,
            "right", mRight,
            "bottom", mBottom
        ))
    }

    ; Enumerate all windows
    for hwnd in WinGetList() {
        try {
            ; Get window title
            title := WinGetTitle("ahk_id " hwnd)
            if (!title || title = "")
                continue

            ; Get window style to check visibility
            style := WinGetStyle("ahk_id " hwnd)
            if !(style & 0x10000000)  ; WS_VISIBLE
                continue

            ; Get window class
            winClass := WinGetClass("ahk_id " hwnd)

            ; Skip system windows
            if (winClass = "Shell_TrayWnd" || winClass = "Shell_SecondaryTrayWnd" ||
                winClass = "Progman" || winClass = "WorkerW" || winClass = "Windows.UI.Core.CoreWindow" ||
                winClass = "DV2ControlHost" || winClass = "TopLevelWindowForOverflowXamlIsland" ||
                winClass = "Xaml_WindowedPopupClass")
                continue

            ; Get extended style
            exStyle := WinGetExStyle("ahk_id " hwnd)

            ; Skip tool windows (like floating toolbars)
            if (exStyle & 0x80)  ; WS_EX_TOOLWINDOW
                continue

            ; Get window position
            WinGetPos(&wX, &wY, &wW, &wH, "ahk_id " hwnd)

            ; Skip tiny windows (likely tooltips or hidden windows)
            if (wW < 50 || wH < 50)
                continue

            ; Calculate window center
            wCenterX := wX + (wW // 2)
            wCenterY := wY + (wH // 2)

            ; Find which monitor this window belongs to
            Loop monitorCount {
                bounds := monitorBounds[A_Index]
                if (wCenterX >= bounds["left"] && wCenterX < bounds["right"] &&
                    wCenterY >= bounds["top"] && wCenterY < bounds["bottom"]) {
                    windowsByMonitor[A_Index].Push(hwnd)
                    break
                }
            }
        } catch {
            ; Skip problematic windows
            continue
        }
    }

    return windowsByMonitor
}

; Check if window is in fullscreen mode (covers entire screen)
; Parameters:
;   hwnd - Window handle to check
; Returns: true if fullscreen, false otherwise
IsWindowFullscreen(hwnd) {
    ; Validate window handle
    if (!hwnd || !WinExist("ahk_id " hwnd)) {
        return false
    }

    try {
        ; Get window position and size
        WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " hwnd)

        ; Validate window dimensions
        if (winW <= 0 || winH <= 0) {
            return false
        }

        ; Get the monitor the window is on
        monitorNum := GetWindowMonitor(hwnd)
        if (monitorNum < 1 || monitorNum > MonitorGetCount()) {
            return false
        }

        MonitorGet(monitorNum, &mLeft, &mTop, &mRight, &mBottom)

        ; Check if window covers the entire monitor (fullscreen)
        ; Allow small margin of error (5 pixels) for window borders
        if (Abs(winX - mLeft) <= 5 && Abs(winY - mTop) <= 5 &&
            Abs(winW - (mRight - mLeft)) <= 10 && Abs(winH - (mBottom - mTop)) <= 10) {
            return true
        }
    } catch {
        ; Any error means not fullscreen
        return false
    }

    return false
}

; Check if window spans multiple monitors
; Parameters:
;   hwnd - Window handle to check
; Returns: true if spanning multiple monitors, false otherwise
IsWindowSpanningMonitors(hwnd) {
    ; Validate window handle
    if (!hwnd || !WinExist("ahk_id " hwnd)) {
        return false
    }

    try {
        WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " hwnd)

        ; Validate window dimensions
        if (winW <= 0 || winH <= 0) {
            return false
        }

        ; Count how many monitors this window intersects
        monitorCount := MonitorGetCount()
        if (monitorCount < 2) {
            return false  ; Can't span if less than 2 monitors
        }

        intersectionCount := 0

        Loop monitorCount {
            try {
                MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)

                ; Check for intersection between window and monitor
                if (winX < mRight && winX + winW > mLeft &&
                    winY < mBottom && winY + winH > mTop) {
                    intersectionCount++
                }
            } catch {
                continue
            }
        }

        return intersectionCount > 1
    } catch {
        ; Any error means not spanning
        return false
    }

    return false
}

; Move all windows from one monitor to another
; This is the core function for bulk window movement between monitors
; It handles various window states intelligently:
;   - Fullscreen windows: Restore -> Move -> Re-fullscreen on target monitor
;   - Maximized windows: Restore -> Move -> Re-maximize on target monitor
;   - Spanning windows: Restore -> Center on target monitor
;   - Normal windows: Preserve relative position from source to target monitor
; Parameters:
;   sourceMonitor - Monitor number to move windows FROM (1-based index)
;   targetMonitor - Monitor number to move windows TO (1-based index)
; Returns: Map with success status and detailed results
;   - success: true if at least one window moved successfully
;   - movedCount: Number of windows successfully moved
;   - failedCount: Number of windows that failed to move
;   - message: Description of operation result
; Note: Skips minimized windows as they don't need repositioning
MoveAllWindowsBetweenMonitors(sourceMonitor, targetMonitor) {
    result := Map(
        "success", false,
        "movedCount", 0,
        "failedCount", 0,
        "message", ""
    )

    ; Validate monitor numbers
    monitorCount := MonitorGetCount()
    if (sourceMonitor < 1 || sourceMonitor > monitorCount) {
        result["message"] := "Invalid source monitor: " sourceMonitor " (only " monitorCount " monitor(s) available)"
        return result
    }
    if (targetMonitor < 1 || targetMonitor > monitorCount) {
        result["message"] := "Invalid target monitor: " targetMonitor " (only " monitorCount " monitor(s) available)"
        return result
    }
    if (sourceMonitor = targetMonitor) {
        result["message"] := "Source and target monitors are the same (" sourceMonitor ")"
        return result
    }

    ; Get windows grouped by monitor
    try {
        windowsByMonitor := EnumerateWindowsByMonitor()
    } catch as err {
        result["message"] := "Failed to enumerate windows: " err.Message
        return result
    }

    ; Get source monitor windows
    sourceWindows := windowsByMonitor[sourceMonitor]
    if (sourceWindows.Length = 0) {
        result["message"] := "No windows found on source monitor " sourceMonitor
        return result
    }

    ; Get monitor info for both monitors
    try {
        MonitorGetWorkArea(sourceMonitor, &sLeft, &sTop, &sRight, &sBottom)
        MonitorGetWorkArea(targetMonitor, &tLeft, &tTop, &tRight, &tBottom)
        MonitorGet(targetMonitor, &tFullLeft, &tFullTop, &tFullRight, &tFullBottom)
    } catch as err {
        result["message"] := "Failed to get monitor information: " err.Message
        return result
    }

    sWidth := sRight - sLeft
    sHeight := sBottom - sTop
    tWidth := tRight - tLeft
    tHeight := tBottom - tTop

    movedCount := 0
    failedCount := 0

    ; Move each window from source to target monitor
    ; Iterates through all windows found on the source monitor and moves them individually
    for hwnd in sourceWindows {
        try {
            ; Verify window still exists (user may have closed it since enumeration)
            if (!WinExist("ahk_id " hwnd)) {
                failedCount++
                continue
            }

            ; Skip minimized windows - they don't need to be moved
            ; Minimized windows are stored in taskbar and don't have a physical screen position
            try {
                minMaxState := WinGetMinMax("ahk_id " hwnd)
                if (minMaxState = -1) {  ; -1 = minimized, 0 = normal, 1 = maximized
                    continue
                }
            } catch as err {
                failedCount++
                continue
            }

            ; Check if window spans multiple monitors
            try {
                isSpanning := IsWindowSpanningMonitors(hwnd)
            } catch {
                isSpanning := false
            }

            ; Check if window is in fullscreen mode
            try {
                isFullscreen := IsWindowFullscreen(hwnd)
            } catch {
                isFullscreen := false
            }

            ; Check if window is maximized
            try {
                wasMaximized := WinGetMinMax("ahk_id " hwnd) = 1
            } catch {
                wasMaximized := false
            }

            ; Handle fullscreen apps (games, video players)
            ; Fullscreen is different from maximized - it covers entire screen including taskbar
            ; Common in games and video players
            if (isFullscreen && !wasMaximized) {
                try {
                    ; Fullscreen apps need special handling to prevent visual glitches
                    ; First restore to windowed mode to allow repositioning
                    WinRestore("ahk_id " hwnd)
                    Sleep(100)  ; Longer delay for fullscreen transitions (some apps are slow)

                    ; Move to target monitor and make fullscreen again
                    ; Use full monitor bounds (not work area) to cover entire screen
                    WinMove(tFullLeft, tFullTop, tFullRight - tFullLeft, tFullBottom - tFullTop, "ahk_id " hwnd)
                    Sleep(50)

                    movedCount++
                    continue  ; Skip normal window movement logic
                } catch as err {
                    failedCount++
                    continue
                }
            }

            ; Handle spanning windows - move to center of target monitor
            if (isSpanning) {
                try {
                    WinRestore("ahk_id " hwnd)
                    Sleep(50)

                    WinGetPos(, , &winW, &winH, "ahk_id " hwnd)

                    ; Center on target monitor
                    centerX := tLeft + ((tWidth - winW) // 2)
                    centerY := tTop + ((tHeight - winH) // 2)

                    ; Ensure it fits
                    centerX := Max(tLeft, Min(centerX, tRight - winW))
                    centerY := Max(tTop, Min(centerY, tBottom - winH))

                    WinMove(centerX, centerY, , , "ahk_id " hwnd)
                    movedCount++
                    continue
                } catch as err {
                    failedCount++
                    continue
                }
            }

            ; Handle maximized windows
            if (wasMaximized) {
                try {
                    WinRestore("ahk_id " hwnd)
                    Sleep(30)
                } catch as err {
                    failedCount++
                    continue
                }
            }

            ; Get current window position
            try {
                WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " hwnd)
            } catch as err {
                failedCount++
                continue
            }

            ; Calculate relative position on source monitor
            ; This preserves window placement (e.g., top-left corner stays top-left)
            ; relX and relY are values between 0.0 and 1.0 representing position ratio
            relX := (winX - sLeft) / sWidth
            relY := (winY - sTop) / sHeight

            ; Apply same relative position on target monitor
            ; This maintains visual consistency when moving windows between monitors
            newX := tLeft + (relX * tWidth)
            newY := tTop + (relY * tHeight)

            ; Ensure window fits on target monitor (clamp to work area boundaries)
            ; This prevents windows from being positioned off-screen or partially hidden
            newX := Max(tLeft, Min(newX, tRight - winW))
            newY := Max(tTop, Min(newY, tBottom - winH))

            ; Move the window
            try {
                WinMove(newX, newY, , , "ahk_id " hwnd)
                Sleep(30)

                ; If window was maximized, re-maximize it on the new monitor
                if (wasMaximized) {
                    Sleep(30)
                    WinMaximize("ahk_id " hwnd)
                }

                movedCount++
            } catch as err {
                failedCount++
                continue
            }
        } catch as err {
            ; Catch-all for any unexpected errors
            failedCount++
            continue
        }
    }

    ; Update result object
    result["movedCount"] := movedCount
    result["failedCount"] := failedCount
    result["success"] := movedCount > 0

    if (movedCount > 0) {
        if (failedCount > 0) {
            result["message"] := "Moved " movedCount " window(s), " failedCount " failed"
        } else {
            result["message"] := "Successfully moved " movedCount " window(s)"
        }
    } else {
        result["message"] := "Failed to move any windows (" failedCount " errors)"
    }

    return result
}

; Switch focus to a window on the target monitor
; This function activates a window on the target monitor and moves the mouse cursor
; It finds the topmost visible window on the target monitor (first in Z-order)
; and activates it, then moves the mouse to the center of that window
; If no window exists on the target monitor, moves mouse to monitor center
; Parameters:
;   targetMonitor - Monitor number to switch focus TO (1-based index)
; Returns: Map with success status and optional message
;   - success: true if a window was activated, false if only mouse moved
;   - message: Description of what happened (includes window title if activated)
;   - hwnd: Window handle that was activated (0 if no window activated)
; Used by: Ctrl+2 hotkey for monitor switching
SwitchFocusBetweenMonitors(targetMonitor) {
    result := Map(
        "success", false,
        "message", "",
        "hwnd", 0
    )

    ; Validate monitor exists
    monitorCount := MonitorGetCount()
    if (targetMonitor < 1 || targetMonitor > monitorCount) {
        result["message"] := "Invalid monitor number: " targetMonitor
        return result
    }

    ; Get current active window to exclude it
    activeHwnd := WinGetID("A")

    ; Get target monitor bounds
    MonitorGet(targetMonitor, &tLeft, &tTop, &tRight, &tBottom)

    ; Build list of candidate windows on target monitor
    candidateWindows := []
    for hwnd in WinGetList() {
        try {
            ; Skip the current active window
            if (hwnd = activeHwnd)
                continue

            ; Skip windows without title
            title := WinGetTitle("ahk_id " hwnd)
            if (!title || title = "")
                continue

            ; Get window style to check visibility
            style := WinGetStyle("ahk_id " hwnd)
            if !(style & 0x10000000)  ; WS_VISIBLE
                continue

            ; Get window class
            winClass := WinGetClass("ahk_id " hwnd)

            ; Skip system windows
            if (winClass = "Shell_TrayWnd" || winClass = "Shell_SecondaryTrayWnd" ||
                winClass = "Progman" || winClass = "WorkerW" || winClass = "Windows.UI.Core.CoreWindow" ||
                winClass = "DV2ControlHost" || winClass = "TopLevelWindowForOverflowXamlIsland" ||
                winClass = "Xaml_WindowedPopupClass")
                continue

            ; Get extended style
            exStyle := WinGetExStyle("ahk_id " hwnd)

            ; Skip tool windows (like floating toolbars)
            if (exStyle & 0x80)  ; WS_EX_TOOLWINDOW
                continue

            ; Get window position
            WinGetPos(&wX, &wY, &wW, &wH, "ahk_id " hwnd)

            ; Skip tiny windows (likely tooltips or hidden windows)
            if (wW < 50 || wH < 50)
                continue

            ; Calculate window center
            wCenterX := wX + (wW // 2)
            wCenterY := wY + (wH // 2)

            ; Check if window center is on target monitor
            if (wCenterX >= tLeft && wCenterX < tRight &&
                wCenterY >= tTop && wCenterY < tBottom) {
                candidateWindows.Push(Map("hwnd", hwnd, "title", title))
            }
        } catch {
            ; Skip problematic windows
            continue
        }
    }

    ; If we found windows on target monitor, activate the first one (topmost in Z-order)
    ; WinGetList() returns windows in Z-order, so candidateWindows[1] is the topmost visible window
    if (candidateWindows.Length > 0) {
        targetHwnd := candidateWindows[1]["hwnd"]
        targetTitle := candidateWindows[1]["title"]

        try {
            ; Activate the target window (brings it to foreground)
            WinActivate("ahk_id " targetHwnd)
            Sleep(50)  ; Allow time for activation to complete

            ; Verify activation worked (some windows may resist activation)
            if (WinActive("ahk_id " targetHwnd)) {
                ; Move mouse cursor to the center of the activated window
                ; This provides visual feedback and allows immediate interaction
                try {
                    WinGetPos(&wX, &wY, &wW, &wH, "ahk_id " targetHwnd)
                    cursorX := wX + (wW // 2)  ; Calculate horizontal center
                    cursorY := wY + (wH // 2)  ; Calculate vertical center
                    MouseMove(cursorX, cursorY, 0)  ; 0 = instant move, no animation
                } catch {
                    ; If cursor move fails, don't fail the entire operation
                    ; Window activation is still successful
                }

                result["success"] := true
                result["message"] := "Switched to Monitor " targetMonitor " - " targetTitle
                result["hwnd"] := targetHwnd
                return result
            } else {
                result["message"] := "Failed to activate window on Monitor " targetMonitor
                return result
            }
        } catch as err {
            result["message"] := "Error activating window: " err.Message
            return result
        }
    }

    ; If no window found, move mouse to target monitor center
    centerX := tLeft + ((tRight - tLeft) // 2)
    centerY := tTop + ((tBottom - tTop) // 2)

    try {
        MouseMove(centerX, centerY, 0)
        result["success"] := false  ; Success is false because no window was activated
        result["message"] := "No window on Monitor " targetMonitor " - moved mouse to center"
        return result
    } catch as err {
        result["message"] := "Error moving mouse: " err.Message
        return result
    }
}

; ============================================================================
; PROCESS SUSPENSION FUNCTIONS
; ============================================================================
; These functions use Windows API to suspend/resume processes for resource management

; Suspend a process to freeze it and free up CPU/RAM
; Parameters:
;   pid - Process ID to suspend
; Returns: true if successful, false otherwise
SuspendProcess(pid) {
    ; PROCESS_SUSPEND_RESUME = 0x0800, PROCESS_SET_QUOTA = 0x0100, PROCESS_QUERY_INFORMATION = 0x0400
    ; Combined: 0x0D00 for suspend + memory management
    hProcess := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", 0, "UInt", pid, "Ptr")
    if (!hProcess) {
        return false
    }

    ; First suspend the process
    result := DllCall("ntdll\NtSuspendProcess", "Ptr", hProcess, "UInt")

    if (result >= 0) {
        ; Empty the working set to free up physical RAM
        ; This moves pages to the page file, freeing physical memory
        DllCall("psapi\EmptyWorkingSet", "Ptr", hProcess)

        ; Also trim working set to minimum
        DllCall("SetProcessWorkingSetSize", "Ptr", hProcess, "Ptr", -1, "Ptr", -1)
    }

    DllCall("CloseHandle", "Ptr", hProcess)
    return (result >= 0)
}

; Resume a suspended process and restore its resources
; Parameters:
;   pid - Process ID to resume
; Returns: true if successful, false otherwise
ResumeProcess(pid) {
    ; Full access for resume and memory restoration
    hProcess := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", 0, "UInt", pid, "Ptr")
    if (!hProcess) {
        return false
    }

    ; Set working set to allow it to grow back (give it generous limits)
    ; Min 50MB, Max 2GB - this pre-allocates quota for the process
    DllCall("SetProcessWorkingSetSize", "Ptr", hProcess, "Ptr", 52428800, "Ptr", 2147483648)

    ; Resume the process
    result := DllCall("ntdll\NtResumeProcess", "Ptr", hProcess, "UInt")

    DllCall("CloseHandle", "Ptr", hProcess)
    return (result >= 0)
}

; Force minimize a window using multiple methods
; Parameters:
;   hwnd - Window handle to minimize
ForceMinimize(hwnd) {
    ; Method 1: Standard WinMinimize
    try {
        WinMinimize("ahk_id " hwnd)
    }

    ; Method 2: PostMessage WM_SYSCOMMAND SC_MINIMIZE
    DllCall("PostMessage", "Ptr", hwnd, "UInt", 0x0112, "Ptr", 0xF020, "Ptr", 0)

    ; Method 3: ShowWindow SW_FORCEMINIMIZE (11) or SW_MINIMIZE (6)
    DllCall("ShowWindow", "Ptr", hwnd, "Int", 11)
}

; ============================================================================
; GLOBAL STATE VARIABLES
; ============================================================================
; These global variables maintain state across hotkey invocations

; Track last execution time for hotkeys to prevent rapid-fire issues
; This prevents race conditions and window management glitches from rapid keypresses
global lastCtrl2Time := 0           ; Last time Ctrl+2 was executed (in milliseconds)
global ctrl2Throttle := 100         ; Minimum milliseconds between Ctrl+2 executions (100ms = 0.1 second)

; Track consecutive Ctrl taps for quad-tap fullscreen
global ctrlTapCount := 0
global ctrlLastTapTime := 0
global ctrlTapWindow := 1200        ; 1.2 seconds window for 4 taps

; Track consecutive Alt taps for quad-tap OpenWhisper
global altTapCount := 0
global altLastTapTime := 0
global altTapWindow := 1200         ; 1.2 seconds window for 4 taps

; Track frozen processes for Ctrl+h / Alt+h functionality
global frozenProcesses := []        ; Array of frozen process info: {pid, hwnd, title}

; ============================================================================
; HOTKEYS - Keyboard shortcuts
; ============================================================================

; Win+W - Launch Wand
#w::
{
    Run('"C:\Users\micha\AppData\Local\Wand\Wand.exe"')
}

; Ctrl+1 - Move active window to the other monitor and make it fullscreen
; This hotkey moves the currently active window to the opposite monitor
; and always makes it fullscreen (covering entire screen including taskbar)
; Works with 2+ monitor setups (toggles between monitor 1 and 2)
^1::
{
    try {
        hwnd := WinGetID("A")
    } catch as err {
        ToolTip("Error: Could not get active window")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    if (!hwnd) {
        ToolTip("No active window to move")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    ; Get monitor count
    try {
        monitorCount := MonitorGetCount()
    } catch as err {
        ToolTip("Error: Could not detect monitors - " err.Message)
        SetTimer(() => ToolTip(), -2000)
        return
    }

    if (monitorCount < 2) {
        ToolTip("Only 1 monitor detected - need 2+ monitors")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    ; Determine current monitor
    try {
        currentMonitor := GetWindowMonitor(hwnd)
    } catch as err {
        ToolTip("Error detecting current monitor: " err.Message)
        SetTimer(() => ToolTip(), -2000)
        return
    }

    ; Switch to the other monitor (toggle between 1 and 2)
    targetMonitor := (currentMonitor = 1) ? 2 : 1

    ; Validate target monitor exists
    if (targetMonitor > monitorCount) {
        ToolTip("Error: Target monitor " targetMonitor " does not exist")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    ; Get target monitor full bounds (not work area - we want fullscreen)
    try {
        MonitorGet(targetMonitor, &tLeft, &tTop, &tRight, &tBottom)
    } catch as err {
        ToolTip("Error getting monitor bounds: " err.Message)
        SetTimer(() => ToolTip(), -2000)
        return
    }

    ; Restore window first (if maximized or minimized)
    try {
        WinRestore("ahk_id " hwnd)
        Sleep(100)  ; Allow time for restore to complete
    } catch as err {
        ToolTip("Error restoring window: " err.Message)
        SetTimer(() => ToolTip(), -2000)
        return
    }

    ; Move to target monitor then maximize (true maximized state on target monitor)
    try {
        WinMove(tLeft + 10, tTop + 10, , , "ahk_id " hwnd)  ; Nudge onto target monitor
        Sleep(50)
        WinMaximize("ahk_id " hwnd)
        ToolTip("Moved maximized to Monitor " targetMonitor)
        SetTimer(() => ToolTip(), -1500)
    } catch as err {
        ToolTip("Error moving window: " err.Message)
        SetTimer(() => ToolTip(), -2000)
        return
    }
}

; Ctrl+` - Swap ALL windows between monitors (everything on main â†’ 2nd and 2nd â†’ main)
; Preserves maximized state and scales proportional positions for non-maximized windows
; SC029 = scan code for backtick/grave accent key â€” needed because ` is AHK v2 escape char
^SC029::
{
    if (MonitorGetCount() < 2) {
        ToolTip("Only 1 monitor detected")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    ; Detect primary and secondary monitor dynamically (never assume AHK index)
    primaryMon := MonitorGetPrimary()
    secondaryMon := 0
    Loop MonitorGetCount() {
        if (A_Index != primaryMon) {
            secondaryMon := A_Index
            break
        }
    }
    if (!secondaryMon) {
        ToolTip("Could not find secondary monitor")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    ; Snapshot all windows grouped by monitor BEFORE moving anything
    windowsByMon := EnumerateWindowsByMonitor()
    primaryWindows   := windowsByMon[primaryMon]
    secondaryWindows := windowsByMon[secondaryMon]

    ; Get full bounds of both monitors
    MonitorGet(primaryMon,   &p_L, &p_T, &p_R, &p_B)
    MonitorGet(secondaryMon, &s_L, &s_T, &s_R, &s_B)
    p_W := p_R - p_L
    p_H := p_B - p_T
    s_W := s_R - s_L
    s_H := s_B - s_T

    totalMoved := 0

    ; Move all primary windows â†’ secondary
    for hwnd in primaryWindows {
        try {
            minMax := WinGetMinMax("ahk_id " hwnd)
            WinGetPos(&wX, &wY, &wW, &wH, "ahk_id " hwnd)
            WinRestore("ahk_id " hwnd)
            Sleep(30)
            if (minMax = 1) {
                WinMove(s_L + 10, s_T + 10, , , "ahk_id " hwnd)
                Sleep(30)
                WinMaximize("ahk_id " hwnd)
            } else {
                newX := s_L + Round((wX - p_L) * (s_W / p_W))
                newY := s_T + Round((wY - p_T) * (s_H / p_H))
                newW := Round(wW * (s_W / p_W))
                newH := Round(wH * (s_H / p_H))
                WinMove(newX, newY, newW, newH, "ahk_id " hwnd)
            }
        } catch {
        }
        totalMoved++
    }

    ; Move all secondary windows â†’ primary
    for hwnd in secondaryWindows {
        try {
            minMax := WinGetMinMax("ahk_id " hwnd)
            WinGetPos(&wX, &wY, &wW, &wH, "ahk_id " hwnd)
            WinRestore("ahk_id " hwnd)
            Sleep(30)
            if (minMax = 1) {
                WinMove(p_L + 10, p_T + 10, , , "ahk_id " hwnd)
                Sleep(30)
                WinMaximize("ahk_id " hwnd)
            } else {
                newX := p_L + Round((wX - s_L) * (p_W / s_W))
                newY := p_T + Round((wY - s_T) * (p_H / s_H))
                newW := Round(wW * (p_W / s_W))
                newH := Round(wH * (p_H / s_H))
                WinMove(newX, newY, newW, newH, "ahk_id " hwnd)
            }
        } catch {
        }
        totalMoved++
    }

    ToolTip("Swapped all windows between monitors (" totalMoved " moved)")
    SetTimer(() => ToolTip(), -2000)
}

; Ctrl+3 - Force current window into a small restored window
^3::
{
    try {
        hwnd := WinGetID("A")
    } catch as err {
        ToolTip("Error: Could not get active window")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    if (!hwnd) {
        ToolTip("No active window")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    ; Get current monitor work area to center the small window
    try {
        currentMonitor := GetWindowMonitor(hwnd)
        MonitorGetWorkArea(currentMonitor, &mLeft, &mTop, &mRight, &mBottom)
    } catch {
        MonitorGetWorkArea(, &mLeft, &mTop, &mRight, &mBottom)
    }

    smallW := 900
    smallH := 600
    centerX := mLeft + ((mRight - mLeft - smallW) // 2)
    centerY := mTop + ((mBottom - mTop - smallH) // 2)

    try {
        WinRestore("ahk_id " hwnd)
        Sleep(50)
        WinMove(centerX, centerY, smallW, smallH, "ahk_id " hwnd)
        ToolTip("Window set to small (900x600)")
        SetTimer(() => ToolTip(), -1500)
    } catch as err {
        ToolTip("Error: " err.Message)
        SetTimer(() => ToolTip(), -2000)
    }
}

; Ctrl+4 - Force move ALL windows from primary monitor to secondary monitor
^4::
{
    if (MonitorGetCount() < 2) {
        ToolTip("Only 1 monitor detected - need 2+ monitors")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    ; Find primary and secondary monitors dynamically
    primaryMon := MonitorGetPrimary()
    secondaryMon := 0
    Loop MonitorGetCount() {
        if (A_Index != primaryMon) {
            secondaryMon := A_Index
            break
        }
    }
    if (!secondaryMon) {
        ToolTip("Could not find secondary monitor")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    result := MoveAllWindowsBetweenMonitors(primaryMon, secondaryMon)
    ToolTip(result["message"])
    SetTimer(() => ToolTip(), -2000)
}

; Ctrl+5 - Force move ALL windows from secondary monitor to primary monitor
^5::
{
    if (MonitorGetCount() < 2) {
        ToolTip("Only 1 monitor detected - need 2+ monitors")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    ; Find primary and secondary monitors dynamically
    primaryMon := MonitorGetPrimary()
    secondaryMon := 0
    Loop MonitorGetCount() {
        if (A_Index != primaryMon) {
            secondaryMon := A_Index
            break
        }
    }
    if (!secondaryMon) {
        ToolTip("Could not find secondary monitor")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    result := MoveAllWindowsBetweenMonitors(secondaryMon, primaryMon)
    ToolTip(result["message"])
    SetTimer(() => ToolTip(), -2000)
}

; Ctrl+2 - Switch focus to the other monitor
; This hotkey switches focus to a window on the opposite monitor
; Workflow:
;   1. Detects which monitor is currently active (based on active window or mouse)
;   2. Targets the opposite monitor (toggles between 1 and 2)
;   3. Finds the topmost visible window on target monitor
;   4. Activates that window and moves mouse cursor to its center
;   5. If no window on target monitor, moves mouse to monitor center
; Includes throttling (100ms) to prevent rapid-fire keypresses causing race conditions
; Provides visual feedback via tooltip showing activated window or error
; Used for quickly switching focus between monitors without moving windows
^2::
{
    ; Throttle rapid keypresses to prevent race conditions
    ; This ensures the previous execution completes before starting a new one
    global lastCtrl2Time, ctrl2Throttle
    currentTime := A_TickCount

    if (currentTime - lastCtrl2Time < ctrl2Throttle) {
        ; Too soon after last execution, ignore this keypress
        return
    }

    lastCtrl2Time := currentTime

    ; Get monitor count
    try {
        monitorCount := MonitorGetCount()
    } catch as err {
        ToolTip("Error: Could not detect monitors - " err.Message)
        SetTimer(() => ToolTip(), -2000)
        return
    }

    if (monitorCount < 2) {
        ToolTip("Only 1 monitor detected - need 2+ monitors")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    ; Get active window to determine current monitor
    try {
        activeHwnd := WinGetID("A")
    } catch {
        activeHwnd := 0
    }

    ; Determine current monitor based on active window (or mouse if no active window)
    currentMonitor := 1
    if (activeHwnd) {
        try {
            WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " activeHwnd)
            winCenterX := winX + (winW // 2)
            winCenterY := winY + (winH // 2)

            Loop monitorCount {
                MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)
                if (winCenterX >= mLeft && winCenterX < mRight && winCenterY >= mTop && winCenterY < mBottom) {
                    currentMonitor := A_Index
                    break
                }
            }
        } catch as err {
            ; Fallback to monitor 1 if error
            currentMonitor := 1
        }
    } else {
        ; Fallback to mouse position if no active window
        try {
            MouseGetPos(&mouseX, &mouseY)
            Loop monitorCount {
                MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)
                if (mouseX >= mLeft && mouseX < mRight && mouseY >= mTop && mouseY < mBottom) {
                    currentMonitor := A_Index
                    break
                }
            }
        } catch as err {
            ; Fallback to monitor 1 if mouse position fails
            currentMonitor := 1
        }
    }

    ; Target the other monitor (toggle between 1 and 2)
    targetMonitor := (currentMonitor = 1) ? 2 : 1

    ; Validate target monitor exists
    if (targetMonitor > monitorCount) {
        ToolTip("Error: Target monitor " targetMonitor " does not exist")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    ; Use the new SwitchFocusBetweenMonitors function
    try {
        result := SwitchFocusBetweenMonitors(targetMonitor)

        ; Display result message as tooltip
        ToolTip(result["message"])
        SetTimer(() => ToolTip(), -1500)
    } catch as err {
        ToolTip("Error switching monitor focus: " err.Message)
        SetTimer(() => ToolTip(), -2000)
    }
}

; Ctrl x4 tap â€” Maximize/fullscreen current window on its current monitor
; Detects 4 consecutive Ctrl taps within 1.2 seconds
~Ctrl Up::
{
    global ctrlTapCount, ctrlLastTapTime, ctrlTapWindow
    now := A_TickCount

    if (now - ctrlLastTapTime > ctrlTapWindow) {
        ctrlTapCount := 0
    }

    ctrlTapCount++
    ctrlLastTapTime := now

    if (ctrlTapCount >= 4) {
        ctrlTapCount := 0
        try {
            hwnd := WinGetID("A")
            if (hwnd) {
                minMax := WinGetMinMax("ahk_id " hwnd)
                if (minMax = 1) {
                    ; Already maximized â†’ restore it (toggle)
                    WinRestore("ahk_id " hwnd)
                    ToolTip("Window restored")
                } else {
                    WinMaximize("ahk_id " hwnd)
                    ToolTip("Window maximized")
                }
                SetTimer(() => ToolTip(), -1500)
            }
        }
    }
}

; Alt x4 tap â€” Launch OpenWhisper
; Detects 4 consecutive Alt taps within 1.2 seconds
~Alt Up::
{
    global altTapCount, altLastTapTime, altTapWindow
    now := A_TickCount

    if (now - altLastTapTime > altTapWindow) {
        altTapCount := 0
    }

    altTapCount++
    altLastTapTime := now

    if (altTapCount >= 4) {
        altTapCount := 0
        Run('"F:\backup\windowsapps\installed\OpenWhisper\OpenWhispr\OpenWhispr.exe"')
        ToolTip("OpenWhisper launched")
        SetTimer(() => ToolTip(), -1500)
    }
}

; REMOVED: Ctrl+S and Alt+S hotkeys (were causing nano/terminal freeze issues)

; Ctrl+h - INSTANT FREEZE - Immediately minimize and suspend current app
; Uses pure Windows API - minimize FIRST, then suspend
; Guard: skip in terminals (WindowsTerminal, ConHost, mintty, bash) - Ctrl+H is backspace there
#HotIf !WinActive("ahk_exe WindowsTerminal.exe") && !WinActive("ahk_class ConsoleWindowClass") && !WinActive("ahk_class VirtualConsoleClass") && !WinActive("ahk_exe mintty.exe")
^h::
{
    global frozenProcesses

    ; Get foreground window directly - INSTANT
    hwnd := DllCall("GetForegroundWindow", "Ptr")
    if (!hwnd) {
        return
    }

    ; Get PID directly from handle - INSTANT
    pid := 0
    DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid)
    if (!pid) {
        return
    }

    ; Minimize FIRST using single reliable method
    DllCall("ShowWindow", "Ptr", hwnd, "Int", 6)  ; SW_MINIMIZE
    
    ; THEN suspend the process
    if (SuspendProcess(pid)) {
        ; Track for Alt+H resume
        frozenProcesses.Push({pid: pid, hwnd: hwnd, title: ""})
    }
}

#HotIf  ; end terminal guard

; Alt+h - INSTANT UNFREEZE - Resume all apps frozen with Ctrl+H
; Unfreezes and restores windows immediately
!h::
{
    global frozenProcesses

    count := frozenProcesses.Length
    if (count = 0) {
        return  ; Nothing to resume
    }

    lastHwnd := 0

    ; Resume ALL frozen processes and restore windows
    Loop count {
        processInfo := frozenProcesses[A_Index]
        lastHwnd := processInfo.hwnd
        
        ; Resume process FIRST
        ResumeProcess(processInfo.pid)
        
        ; Restore window with single call
        DllCall("ShowWindow", "Ptr", processInfo.hwnd, "Int", 9)  ; SW_RESTORE
        
        ; Bring to foreground
        DllCall("SetForegroundWindow", "Ptr", processInfo.hwnd)
    }

    ; Clear the list
    frozenProcesses.Length := 0
}

; ============================================================================
; SMART SPLIT MOVE FUNCTION
; ============================================================================
; Shared by 666y and 666r â€” moves active window to target monitor and splits
; with any existing window there, placing them on opposite sides.

SmartSplitMove(target) {
    if (MonitorGetCount() < 2) {
        ToolTip("Only 1 monitor detected")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    primaryMon := MonitorGetPrimary()
    secondaryMon := 0
    Loop MonitorGetCount() {
        if (A_Index != primaryMon) {
            secondaryMon := A_Index
            break
        }
    }
    if (!secondaryMon) {
        ToolTip("Could not find secondary monitor")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    targetMon := (target = "primary") ? primaryMon : secondaryMon

    try {
        activeHwnd := WinGetID("A")
    } catch {
        activeHwnd := 0
    }
    if (!activeHwnd) {
        ToolTip("No active window to move")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    ; Get target monitor work area
    MonitorGetWorkArea(targetMon, &mLeft, &mTop, &mRight, &mBottom)
    mWidth := mRight - mLeft
    mHeight := mBottom - mTop
    halfWidth := mWidth // 2

    ; Find topmost window already on target monitor (excluding active window)
    windowsByMon := EnumerateWindowsByMonitor()
    targetWindows := windowsByMon[targetMon]
    partnerHwnd := 0
    for hw in targetWindows {
        if (hw != activeHwnd) {
            partnerHwnd := hw
            break
        }
    }

    if (!partnerHwnd) {
        ; No partner â€” just move active to left half
        WinRestore("ahk_id " activeHwnd)
        Sleep(50)
        WinMove(mLeft, mTop, halfWidth, mHeight, "ahk_id " activeHwnd)
        ToolTip("Moved to monitor " targetMon " (left half)")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    ; === KEY FIX: Read partner position BEFORE restoring ===
    ; WinRestore unsnaps windows, destroying their snap position.
    ; We must read coordinates while still snapped.
    try {
        WinGetPos(&pX, &pY, &pW, &pH, "ahk_id " partnerHwnd)
    } catch {
        pX := mLeft
        pW := mWidth
    }

    ; Calculate where partner's center is RELATIVE to monitor left edge
    ; This makes it independent of absolute screen coordinates
    relCenterX := (pX - mLeft) + (pW // 2)
    monHalfWidth := mWidth // 2

    ; Debug disabled

    ; Determine: is the partner in the left or right half?
    ; If partner is wide (>75% of monitor), treat as fullscreen â†’ put it left
    if (pW > mWidth * 0.75) {
        ; Partner is maximized/fullscreen â†’ force it LEFT, new window RIGHT
        WinRestore("ahk_id " partnerHwnd)
        Sleep(50)
        WinMove(mLeft, mTop, halfWidth, mHeight, "ahk_id " partnerHwnd)
        WinRestore("ahk_id " activeHwnd)
        Sleep(50)
        WinMove(mLeft + halfWidth, mTop, halfWidth, mHeight, "ahk_id " activeHwnd)
    } else if (relCenterX < monHalfWidth) {
        ; Partner is in LEFT half â†’ keep partner LEFT, new window RIGHT
        WinRestore("ahk_id " partnerHwnd)
        Sleep(50)
        WinMove(mLeft, mTop, halfWidth, mHeight, "ahk_id " partnerHwnd)
        WinRestore("ahk_id " activeHwnd)
        Sleep(50)
        WinMove(mLeft + halfWidth, mTop, halfWidth, mHeight, "ahk_id " activeHwnd)
    } else {
        ; Partner is in RIGHT half â†’ keep partner RIGHT, new window LEFT
        WinRestore("ahk_id " partnerHwnd)
        Sleep(50)
        WinMove(mLeft + halfWidth, mTop, halfWidth, mHeight, "ahk_id " partnerHwnd)
        WinRestore("ahk_id " activeHwnd)
        Sleep(50)
        WinMove(mLeft, mTop, halfWidth, mHeight, "ahk_id " activeHwnd)
    }

    label := (target = "primary") ? "primary" : "secondary"
    ToolTip("Split on " label " monitor")
    SetTimer(() => ToolTip(), -1500)
}

; ============================================================================
; SMART THREE-WAY SPLIT FUNCTION
; ============================================================================
; Shared by 555t and 555y â€” moves active window to target monitor and splits
; 3 windows into thirds. Finds the empty third and places new window there.

SmartThreeWaySplit(target) {
    if (MonitorGetCount() < 2) {
        ToolTip("Only 1 monitor detected")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    primaryMon := MonitorGetPrimary()
    secondaryMon := 0
    Loop MonitorGetCount() {
        if (A_Index != primaryMon) {
            secondaryMon := A_Index
            break
        }
    }
    if (!secondaryMon) {
        ToolTip("Could not find secondary monitor")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    targetMon := (target = "primary") ? primaryMon : secondaryMon

    try {
        activeHwnd := WinGetID("A")
    } catch {
        activeHwnd := 0
    }
    if (!activeHwnd) {
        ToolTip("No active window to move")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    ; Get target monitor work area
    MonitorGetWorkArea(targetMon, &mLeft, &mTop, &mRight, &mBottom)
    mWidth := mRight - mLeft
    mHeight := mBottom - mTop
    thirdWidth := mWidth // 3

    ; Find top 2 windows already on target monitor (excluding active window)
    windowsByMon := EnumerateWindowsByMonitor()
    targetWindows := windowsByMon[targetMon]
    partners := []
    for hw in targetWindows {
        if (hw != activeHwnd) {
            partners.Push(hw)
            if (partners.Length >= 2)
                break
        }
    }

    if (partners.Length < 2) {
        ToolTip("Need at least 2 windows on target monitor for 3-way split (found " partners.Length ")")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    ; Read positions of both partners BEFORE any restore
    ; Determine which thirds are occupied
    ; Thirds: LEFT = mLeft to mLeft+thirdWidth, MIDDLE = +thirdWidth to +2*thirdWidth, RIGHT = +2*thirdWidth to end
    occupiedThirds := [false, false, false]  ; [left, middle, right]
    partnerThirds := [0, 0]  ; which third each partner is in (1=left, 2=mid, 3=right)

    Loop 2 {
        try {
            WinGetPos(&pX, &pY, &pW, &pH, "ahk_id " partners[A_Index])
            relCenter := (pX - mLeft) + (pW // 2)
            if (relCenter < thirdWidth) {
                occupiedThirds[1] := true
                partnerThirds[A_Index] := 1
            } else if (relCenter < thirdWidth * 2) {
                occupiedThirds[2] := true
                partnerThirds[A_Index] := 2
            } else {
                occupiedThirds[3] := true
                partnerThirds[A_Index] := 3
            }
        }
    }

    ; Find the empty third for the new window
    emptyThird := 0
    if (!occupiedThirds[1])
        emptyThird := 1
    else if (!occupiedThirds[2])
        emptyThird := 2
    else if (!occupiedThirds[3])
        emptyThird := 3
    else
        emptyThird := 3  ; fallback: rightmost

    ; Place partner 1 in its detected third (snapped properly)
    WinRestore("ahk_id " partners[1])
    Sleep(50)
    WinMove(mLeft + (thirdWidth * (partnerThirds[1] - 1)), mTop, thirdWidth, mHeight, "ahk_id " partners[1])

    ; Place partner 2 in its detected third
    WinRestore("ahk_id " partners[2])
    Sleep(50)
    WinMove(mLeft + (thirdWidth * (partnerThirds[2] - 1)), mTop, thirdWidth, mHeight, "ahk_id " partners[2])

    ; Place active window in the empty third
    WinRestore("ahk_id " activeHwnd)
    Sleep(50)
    WinMove(mLeft + (thirdWidth * (emptyThird - 1)), mTop, thirdWidth, mHeight, "ahk_id " activeHwnd)

    label := (target = "primary") ? "primary" : "secondary"
    ToolTip("3-way split on " label " monitor")
    SetTimer(() => ToolTip(), -1500)
}

; ============================================================================
; FORCE TWO-WAY SPLIT FUNCTION
; ============================================================================
; Used by yyyy (primary) and 555y (secondary) â€” grabs the 2 most recently used
; windows from ANY monitor and force-moves them into left/right halves on target monitor.

ForceTwoWaySplit(target) {
    if (MonitorGetCount() < 1) {
        ToolTip("No monitors detected")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    primaryMon := MonitorGetPrimary()
    secondaryMon := 0
    Loop MonitorGetCount() {
        if (A_Index != primaryMon) {
            secondaryMon := A_Index
            break
        }
    }

    if (target = "primary")
        targetMon := primaryMon
    else if (secondaryMon)
        targetMon := secondaryMon
    else {
        ToolTip("Only 1 monitor detected")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    recentWindows := GetRecentWindows(2)

    if (recentWindows.Length < 2) {
        ToolTip("Need at least 2 app windows (found " recentWindows.Length ")")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    MonitorGetWorkArea(targetMon, &mLeft, &mTop, &mRight, &mBottom)
    mWidth := mRight - mLeft
    mHeight := mBottom - mTop
    halfWidth := mWidth // 2

    WinRestore("ahk_id " recentWindows[1])
    Sleep(30)
    WinMove(mLeft, mTop, halfWidth, mHeight, "ahk_id " recentWindows[1])

    WinRestore("ahk_id " recentWindows[2])
    Sleep(30)
    WinMove(mLeft + halfWidth, mTop, halfWidth, mHeight, "ahk_id " recentWindows[2])

    label := (target = "primary") ? "primary" : "secondary"
    ToolTip("2 windows split on " label " monitor")
    SetTimer(() => ToolTip(), -1500)
}

; ============================================================================
; FORCE THREE-WAY SPLIT FUNCTION
; ============================================================================
; Used by tttt (primary) and 555y (secondary) â€” grabs the 3 most recently used
; windows from ANY monitor and force-moves them into equal thirds on target monitor.

ForceThreeWaySplit(target) {
    if (MonitorGetCount() < 1) {
        ToolTip("No monitors detected")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    primaryMon := MonitorGetPrimary()
    secondaryMon := 0
    Loop MonitorGetCount() {
        if (A_Index != primaryMon) {
            secondaryMon := A_Index
            break
        }
    }

    if (target = "primary")
        targetMon := primaryMon
    else if (secondaryMon)
        targetMon := secondaryMon
    else {
        ToolTip("Only 1 monitor detected")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    ; Get 3 most recent windows from Z-order (any monitor)
    recentWindows := GetRecentWindows(3)

    if (recentWindows.Length < 3) {
        ToolTip("Need at least 3 app windows (found " recentWindows.Length ")")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    MonitorGetWorkArea(targetMon, &mLeft, &mTop, &mRight, &mBottom)
    mWidth := mRight - mLeft
    mHeight := mBottom - mTop
    thirdWidth := mWidth // 3

    ; Window 1 (most recent) â†’ LEFT third
    WinRestore("ahk_id " recentWindows[1])
    Sleep(30)
    WinMove(mLeft, mTop, thirdWidth, mHeight, "ahk_id " recentWindows[1])

    ; Window 2 â†’ MIDDLE third
    WinRestore("ahk_id " recentWindows[2])
    Sleep(30)
    WinMove(mLeft + thirdWidth, mTop, thirdWidth, mHeight, "ahk_id " recentWindows[2])

    ; Window 3 â†’ RIGHT third
    WinRestore("ahk_id " recentWindows[3])
    Sleep(30)
    WinMove(mLeft + (thirdWidth * 2), mTop, thirdWidth, mHeight, "ahk_id " recentWindows[3])

    label := (target = "primary") ? "primary" : "secondary"
    ToolTip("3 windows split on " label " monitor")
    SetTimer(() => ToolTip(), -1500)
}

; ============================================================================
; HOTSTRINGS - Type these anywhere to trigger actions
; ============================================================================

; mmon - Show monitor layout info (AHK index vs physical position)
; Use this anytime to instantly see which AHK monitor number = which physical screen
:*:mmon::
{
    monCount := MonitorGetCount()
    primaryMon := MonitorGetPrimary()
    info := "=== MONITOR LAYOUT ===`n"
    Loop monCount {
        MonitorGet(A_Index, &mL, &mT, &mR, &mB)
        tag := (A_Index = primaryMon) ? " [PRIMARY/MAIN]" : " [SECONDARY/2nd]"
        info .= "AHK Monitor " A_Index tag ": X=" mL " W=" (mR-mL) "`n"
    }
    info .= "`nFor 666y/555t: secondaryMon = "
    Loop monCount {
        if (A_Index != primaryMon) {
            info .= A_Index
            break
        }
    }
    MsgBox(info, "Monitor Layout", "T5")
}

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

; rroll - Open RollBack Rx Home
:*:rroll::
{
    Run('"C:\ProgramData\Microsoft\Windows\Start Menu\Programs\RollBack Rx Home\RollBack Rx Home.lnk"')
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

; ffff - Open Firefox (auto-find)
:*:ffff::
{
    ; Try common paths first (fastest)
    paths := [
        "C:\Program Files\Mozilla Firefox\firefox.exe",
        "C:\Program Files (x86)\Mozilla Firefox\firefox.exe",
        EnvGet("LOCALAPPDATA") "\Microsoft\WindowsApps\firefox.exe"
    ]
    
    for p in paths {
        if FileExist(p) {
            Run(p)
            return
        }
    }
    
    ; Try registry
    try {
        regPath := RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe")
        if FileExist(regPath) {
            Run(regPath)
            return
        }
    }
    
    ; Last resort - let Windows find it
    try {
        Run("firefox")
        return
    }
    
    MsgBox("Firefox not found!", "Error", "Icon!")
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

; pym - Copy phone number to clipboard
:*:pym::
{
    A_Clipboard := "547632418"
    ToolTip("Phone number copied to clipboard")
    SetTimer(() => ToolTip(), -1500)
}

; toto - Open Todoist (UWP app launched via shell protocol)
:*:toto::
{
    Run('cmd /c start shell:AppsFolder\88449BC3.TodoistPlannerCalendarMSIX_71ef4824z52ta!BC3.TodoistPlannerCalendarMSIX', , "Hide")
}

; sslack - Open Slack (UWP app launched via shell protocol)
:*:sslack::
{
    Run('cmd /c start shell:AppsFolder\91750D7E.Slack_8she8kybcnzg4!Slack', , "Hide")
}

; pass - Copy password to clipboard
:*:pass::
{
    A_Clipboard := "Aa1111111!"
    ToolTip("Password copied to clipboard")
    SetTimer(() => ToolTip(), -1500)
}

; yyyy - Take 2 most recently used windows and split into halves on PRIMARY monitor
:*:yyyy::
{
    ForceTwoWaySplit("primary")
}

; tttt - Take the 3 most recently used windows (Z-order) and split into thirds on PRIMARY monitor
:*:tttt::
{
    ForceThreeWaySplit("primary")
}

; 555y hotstring is defined elsewhere â€” uses SmartThreeWaySplit for moving+splitting

; 666y - Move active window to SECONDARY monitor, smart-split with existing window
; Detects which side existing window is on and places new window on OPPOSITE side
:*:666y::
{
    SmartSplitMove("secondary")
}

; 555t - Take the 3 most recently used windows and split into thirds on SECONDARY monitor
:*:555t::
{
    ForceThreeWaySplit("secondary")
}

; 555y - Take 2 most recently used windows and split into halves on SECONDARY monitor
:*:555y::
{
    ForceTwoWaySplit("secondary")
}

; 666r - Move active window to PRIMARY monitor, smart-split with existing window
; Detects which side existing window is on and places new window on OPPOSITE side
:*:666r::
{
    SmartSplitMove("primary")
}

; asc - Open Advanced SystemCare
:*:asc::
{
    Run('"C:\Program Files (x86)\IObit\Advanced SystemCare\ASC.exe"')
}

; gggit - Open GitHub Desktop
:*:gggit::
{
    Run('"C:\Users\micha\AppData\Local\GitHubDesktop\GitHubDesktop.exe"')
}

; qqbit - Open qBittorrent
:*:qqbit::
{
    Run('"C:\Program Files\qBittorrent\qbittorrent.exe"')
}

; iinstalled - Open installed apps folder
:*:iinstalled::
{
    Run("explorer.exe F:\backup\windowsapps\installed")
}

; savegame - Open GameSave Manager
:*:savegame::
{
    Run('"F:\backup\windowsapps\installed\gamesavemanager\gs_mngr_3.exe"')
}

; ssave - Open and relaunch GameSave Manager
:*:ssave::
{
    ; Kill any running instance first
    try {
        ProcessClose("gs_mngr_3.exe")
        Sleep(1000)
    }
    Run('"F:\backup\windowsapps\installed\gamesavemanager\gs_mngr_3.exe"')
}

; rrram - Open RAM Monitor Pro
:*:rrram::
{
    Run('"F:\study\Dev_Toolchain\programming\python\apps\RamManager\dist\RAM Monitor Pro\RAM Monitor Pro.exe"')
}

; rrevo - Open Revo Uninstaller Pro
:*:rrevo::
{
    Run('"C:\Program Files\VS Revo Group\Revo Uninstaller Pro\RevoUninPro.exe"')
}

; ggggg - Open Game Library Manager web app
:*:ggggg::
{
    Run("https://game-library-michaelunkai.netlify.app/")
}

; oobsi - Open Obsidian
:*:oobsi::
{
    Run('"C:\Program Files\Obsidian\Obsidian.exe"')
}

; wwsl - Open WSL terminal
:*:wwsl::
{
    Run('"C:\Program Files\WSL\wsl.exe"')
}

; gagaga - Open games folder
:*:gagaga::
{
    Run("explorer.exe E:\games")
}

; tetete - Open Telegram app
:*:tetete::
{
    Run("tg://")
}

; ============================================================================
; PARAGON HARD DISK MANAGER AUTOMATION
; ============================================================================
; Type "ppppp" to run FULL automation including restart
; âš ï¸ WARNING: This WILL restart your computer!
; ============================================================================

; Global variable for Paragon Python script path and executable
global ParagonPythonExe := "C:\Users\micha\AppData\Local\Programs\Python\Python312\python.exe"
global ParagonPythonScript := "C:\Users\micha\.openclaw\workspace-openclaw-main\paragon_complete.py"
global ParagonExePath := "F:\backup\windowsapps\installed\Fit Launcher\fixers\Paragon Software\Hard Disk Manager 17 Business\program\hdm17.exe"
global ParagonWindowTitlePart := "Paragon Hard Disk Manager"

; ppppp - Run complete Paragon disk check automation (WILL RESTART COMPUTER!)
:*:ppppp::
{
    global ParagonPythonExe, ParagonPythonScript, ParagonExePath

    ; Show warning tooltip
    ToolTip("Starting Paragon automation - Computer will restart!")
    SetTimer(() => ToolTip(), -3000)

    try {
        if (!FileExist(ParagonExePath))
            throw Error("Paragon EXE not found: " ParagonExePath)

        Run('"' ParagonExePath '"', , , &paragonPid)

        if (!ProcessWait(paragonPid, 15))
            throw Error("Paragon process did not start in time.")

        ToolTip("Waiting for Paragon to fully load before automation...")
        SetTimer(() => ToolTip(), -5000)

        paragonHwnd := WaitForParagonReady(paragonPid)

        try WinActivate("ahk_id " paragonHwnd)

        if (!FileExist(ParagonPythonExe))
            throw Error("Paragon Python EXE not found: " ParagonPythonExe)
        if (!FileExist(ParagonPythonScript))
            throw Error("Paragon automation script not found: " ParagonPythonScript)

        ; Run the complete Python automation script only after Paragon is actually ready.
        ToolTip("Paragon loaded - starting automation...")
        SetTimer(() => ToolTip(), -3000)
        RunWait('"' ParagonPythonExe '" "' ParagonPythonScript '"')

        ; If we get here, automation completed (computer restarting)
        ToolTip("Paragon complete - Computer restarting...")
        SetTimer(() => ToolTip(), -2000)
    } catch as err {
        ToolTip("Error: " err.Message)
        SetTimer(() => ToolTip(), -3000)
    }
}

WaitForParagonReady(pid, timeoutMs := 180000, stablePollsRequired := 4, pollMs := 500) {
    global ParagonWindowTitlePart

    deadline := A_TickCount + timeoutMs
    stablePolls := 0
    lastHwnd := 0
    lastTitle := ""

    while (A_TickCount < deadline) {
        if (!ProcessExist(pid))
            throw Error("Paragon closed before it finished loading.")

        hwnd := WinExist("ahk_pid " pid)
        if (hwnd && IsParagonWindowReady(hwnd, ParagonWindowTitlePart)) {
            title := WinGetTitle("ahk_id " hwnd)
            if (hwnd = lastHwnd && title = lastTitle) {
                stablePolls++
            } else {
                stablePolls := 1
                lastHwnd := hwnd
                lastTitle := title
            }

            if (stablePolls >= stablePollsRequired)
                return hwnd
        } else {
            stablePolls := 0
            lastHwnd := 0
            lastTitle := ""
        }

        Sleep(pollMs)
    }

    throw Error("Timed out waiting for Paragon to fully load.")
}

IsParagonWindowReady(hwnd, expectedTitlePart := "") {
    if (!hwnd || !WinExist("ahk_id " hwnd))
        return false

    try {
        title := WinGetTitle("ahk_id " hwnd)
        if (expectedTitlePart != "" && !InStr(title, expectedTitlePart))
            return false

        if (WinGetMinMax("ahk_id " hwnd) = -1)
            return false

        style := WinGetStyle("ahk_id " hwnd)
        if !(style & 0x10000000)
            return false

        if !DllCall("user32\IsWindowEnabled", "ptr", hwnd, "int")
            return false

        if DllCall("user32\IsHungAppWindow", "ptr", hwnd, "int")
            return false
    } catch {
        return false
    }

    return true
}

; ============================================================================
; HELPER FUNCTIONS
; ============================================================================

; Helper function to get recent windows (excluding desktop, taskbar, etc.)
GetRecentWindows(count) {
    windows := []
    excludeList := ["Program Manager", "Windows Input Experience", ""]

    for hwnd in WinGetList() {
        if (windows.Length >= count)
            break

        try {
            title := WinGetTitle("ahk_id " hwnd)
            winClass := WinGetClass("ahk_id " hwnd)
            style := WinGetStyle("ahk_id " hwnd)

            ; Skip empty titles and non-visible windows
            if (title = "" || !(style & 0x10000000))  ; WS_VISIBLE
                continue

            ; Skip taskbar, system tray, etc.
            if (winClass = "Shell_TrayWnd" || winClass = "Shell_SecondaryTrayWnd" || winClass = "Progman")
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

; Hotstring: nnvid -> Open NVIDIA App
:*:nnvid::
{
    Run("C:\Program Files\NVIDIA Corporation\NVIDIA App\CEF\NVIDIA App.exe")
}

; Hotstring: rryz -> Open AMD Ryzen Master
:*:rryz::
{
    Run("C:\Program Files\AMD\RyzenMaster\bin\AMD Ryzen Master.exe")
}


; ============================================================================
; CUSTOM COMMANDS - Added by OpenClaw
; ============================================================================

; ddock - Run Docker kill script
:*:ddock::
{
    Run('powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "F:\study\containers\docker\scripts\dkill\dkill.ps1"', , "Hide")
}

; rref - Open Macrium Reflect
:*:rref::
{
    Run('"F:\backup\windowsapps\installed\Reflect\Reflect.exe"')
}

; mmacback - Run Macrium backup
:*:mmacback::
{
    Run('powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Windows\Temp\macback.ps1"', , "Hide")
    ToolTip("Macrium backup started")
    SetTimer(() => ToolTip(), -2000)
}

; rrmackback - Cleanup Macrium backups
:*:rrmackback::
{
    Run('powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "F:\study\Devops\backup\MacriumReflect\DisableGuardPurgeBackups\CleanupBackups.ps1"', , "Hide")
    ToolTip("Macrium cleanup started")
    SetTimer(() => ToolTip(), -2000)
}

; bbackclau - Backup Claude Code
:*:bbackclau::
{
    Run('"F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-claudecode.bat"')
}

; rrmbackclau - Rmcc + backclau + listclau
:*:rrmbackclau::
{
    Run('powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -Command "py F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\a.py; F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-claudecode.bat"', , "Hide")
    ToolTip("Rmcc + backclau running")
    SetTimer(() => ToolTip(), -2000)
}

; mmacres - Macrium restore from latest
:*:mmacres::
{
    Run('powershell.exe -ExecutionPolicy Bypass -File "C:\Windows\Temp\macres.ps1"')
}

; ggcc - Open GIGABYTE Control Center
:*:ggcc::
{
    Run('"C:\Program Files\GIGABYTE\Control Center\GCC.exe"')
}

; lockit - Lock workstation
:*:lockit::
{
    DllCall("LockWorkStation")
}

; bbin - Empty Recycle Bin
:*:bbin::
{
    Run('powershell.exe -WindowStyle Hidden -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue"', , "Hide")
    ToolTip("Recycle Bin emptied")
    SetTimer(() => ToolTip(), -2000)
}

; mmin - Minimize all windows except active one
:*:mmin::
{
    activeHwnd := WinGetID("A")
    for hwnd in WinGetList() {
        try {
            if (hwnd = activeHwnd)
                continue
            style := WinGetStyle("ahk_id " hwnd)
            if !(style & 0x10000000)
                continue
            title := WinGetTitle("ahk_id " hwnd)
            if (!title || title = "")
                continue
            winClass := WinGetClass("ahk_id " hwnd)
            if (winClass = "Shell_TrayWnd" || winClass = "Shell_SecondaryTrayWnd" || winClass = "Progman" || winClass = "WorkerW")
                continue
            WinMinimize("ahk_id " hwnd)
        }
    }
    ToolTip("All minimized except active")
    SetTimer(() => ToolTip(), -1500)
}

; ccdclaw - Open .openclaw folder
:*:ccdclaw::
{
    Run('explorer.exe "C:\Users\micha\.openclaw"')
}

; ccdclau - Open .claude folder
:*:ccdclau::
{
    Run('explorer.exe "C:\Users\micha\.claude"')
}

; rregate - Restart OpenClaw gateway (kill port 18789 + relaunch VBS)
:*:rregate::
{
    Run('powershell.exe -Version 5 -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Windows\Temp\regate.ps1"', , "Hide")
    ToolTip("Gateway restarting...")
    SetTimer(() => ToolTip(), -3000)
}

; ============================================================================
; FOLDER NAVIGATION - Auto-generated by OpenClaw
; ============================================================================

; sstudy - Open F:\study
:*:sstudy::
{
    Run('explorer.exe "F:\study"')
}

; bbackup - Open F:\backup
:*:bbackup::
{
    Run('explorer.exe "F:\backup"')
}

; wwin11recovery - Open F:\win11recovery
:*:wwin11recovery::
{
    Run('explorer.exe "F:\win11recovery"')
}

; ttovtech - Open F:\tovtech
:*:ttovtech::
{
    Run('explorer.exe "F:\tovtech"')
}

; aaiml - Open F:\study\AI_ML
:*:aaiml::
{
    Run('explorer.exe "F:\study\AI_ML"')
}

; bbrowsers - Open F:\study\Browsers
:*:bbrowsers::
{
    Run('explorer.exe "F:\study\Browsers"')
}

; ccloud - Open F:\study\cloud
:*:ccloud::
{
    Run('explorer.exe "F:\study\cloud"')
}

; ccollaboration - Open F:\study\collaboration
:*:ccollaboration::
{
    Run('explorer.exe "F:\study\collaboration"')
}

; ccommunication - Open F:\study\communication
:*:ccommunication::
{
    Run('explorer.exe "F:\study\communication"')
}

; ccontainers - Open F:\study\Containers
:*:ccontainers::
{
    Run('explorer.exe "F:\study\Containers"')
}

; ddatabases - Open F:\study\Databases
:*:ddatabases::
{
    Run('explorer.exe "F:\study\Databases"')
}

; ddevops - Open F:\study\Devops
:*:ddevops::
{
    Run('explorer.exe "F:\study\Devops"')
}

; ddevtoolchain - Open F:\study\Dev_Toolchain
:*:ddevtoolchain::
{
    Run('explorer.exe "F:\study\Dev_Toolchain"')
}

; ddistributedsystems - Open F:\study\Distributed_Systems
:*:ddistributedsystems::
{
    Run('explorer.exe "F:\study\Distributed_Systems"')
}

; ddocuments - Open F:\study\documents
:*:ddocuments::
{
    Run('explorer.exe "F:\study\documents"')
}

; eenterpriseapps - Open F:\study\Enterprise_Apps
:*:eenterpriseapps::
{
    Run('explorer.exe "F:\study\Enterprise_Apps"')
}

; eexams - Open F:\study\exams
:*:eexams::
{
    Run('explorer.exe "F:\study\exams"')
}

; mmediaworkflow - Open F:\study\Media_Workflow
:*:mmediaworkflow::
{
    Run('explorer.exe "F:\study\Media_Workflow"')
}

; hhosting - Open F:\study\hosting
:*:hhosting::
{
    Run('explorer.exe "F:\study\hosting"')
}

; mmonitoring - Open F:\study\monitoring
:*:mmonitoring::
{
    Run('explorer.exe "F:\study\monitoring"')
}

; mmobiledev - Open F:\study\mobile_dev
:*:mmobiledev::
{
    Run('explorer.exe "F:\study\mobile_dev"')
}

; mmemorymanagement - Open F:\study\memory_management
:*:mmemorymanagement::
{
    Run('explorer.exe "F:\study\memory_management"')
}

; nnetworking - Open F:\study\networking
:*:nnetworking::
{
    Run('explorer.exe "F:\study\networking"')
}

; oobservability - Open F:\study\Observability
:*:oobservability::
{
    Run('explorer.exe "F:\study\Observability"')
}

; pplatforms - Open F:\study\Platforms
:*:pplatforms::
{
    Run('explorer.exe "F:\study\Platforms"')
}

; ssecurity - Open F:\study\security
:*:ssecurity::
{
    Run('explorer.exe "F:\study\security"')
}

; sservicemeshorchestration - Open F:\study\Service_Mesh_Orchestration
:*:sservicemeshorchestration::
{
    Run('explorer.exe "F:\study\Service_Mesh_Orchestration"')
}

; pprojects - Open F:\study\projects
:*:pprojects::
{
    Run('explorer.exe "F:\study\projects"')
}

; rresume - Open F:\study\resume
:*:rresume::
{
    Run('explorer.exe "F:\study\resume"')
}

; sshells - Open F:\study\Shells
:*:sshells::
{
    Run('explorer.exe "F:\study\Shells"')
}

; sstorageandfilesystems - Open F:\study\Storage_and_Filesystems
:*:sstorageandfilesystems::
{
    Run('explorer.exe "F:\study\Storage_and_Filesystems"')
}

; ssetups - Open F:\study\setups
:*:ssetups::
{
    Run('explorer.exe "F:\study\setups"')
}

; ssystemsvirtualization - Open F:\study\Systems_Virtualization
:*:ssystemsvirtualization::
{
    Run('explorer.exe "F:\study\Systems_Virtualization"')
}

; ttravel - Open F:\study\Travel
:*:ttravel::
{
    Run('explorer.exe "F:\study\Travel"')
}

; vversioncontrol - Open F:\study\Version_control
:*:vversioncontrol::
{
    Run('explorer.exe "F:\study\Version_control"')
}

; ttroubleshooting - Open F:\study\troubleshooting
:*:ttroubleshooting::
{
    Run('explorer.exe "F:\study\troubleshooting"')
}

; wwebbuilding - Open F:\study\WebBuilding
:*:wwebbuilding::
{
    Run('explorer.exe "F:\study\WebBuilding"')
}

; wwindows - Open F:\study\Platforms\windows
:*:wwindows::
{
    Run('explorer.exe "F:\study\Platforms\windows"')
}

; llinux - Open F:\study\Platforms\linux
:*:llinux::
{
    Run('explorer.exe "F:\study\Platforms\linux"')
}

; aandroid - Open F:\study\Platforms\Android
:*:aandroid::
{
    Run('explorer.exe "F:\study\Platforms\Android"')
}

; pprogramming - Open F:\study\Dev_Toolchain\programming
:*:pprogramming::
{
    Run('explorer.exe "F:\study\Dev_Toolchain\programming"')
}

; ddocker - Open F:\study\Containers\docker
:*:ddocker::
{
    Run('explorer.exe "F:\study\Containers\docker"')
}

; ccisco - Open F:\study\networking\Cisco
:*:ccisco::
{
    Run('explorer.exe "F:\study\networking\Cisco"')
}

; vvpn - Open F:\study\networking\VPN
:*:vvpn::
{
    Run('explorer.exe "F:\study\networking\VPN"')
}

; bbash - Open F:\study\Shells\bash
:*:bbash::
{
    Run('explorer.exe "F:\study\Shells\bash"')
}

; ppowershell - Open F:\study\Shells\powershell
:*:ppowershell::
{
    Run('explorer.exe "F:\study\Shells\powershell"')
}

; zzsh - Open F:\study\Shells\zsh
:*:zzsh::
{
    Run('explorer.exe "F:\study\Shells\zsh"')
}

; ggit - Open F:\study\Version_control\git
:*:ggit::
{
    Run('explorer.exe "F:\study\Version_control\git"')
}

; ggithub - Open F:\study\Version_control\github
:*:ggithub::
{
    Run('explorer.exe "F:\study\Version_control\github"')
}

; vvirtualmachines - Open F:\study\Systems_Virtualization\virtualmachines
:*:vvirtualmachines::
{
    Run('explorer.exe "F:\study\Systems_Virtualization\virtualmachines"')
}

; rremote - Open F:\study\Systems_Virtualization\Remote
:*:rremote::
{
    Run('explorer.exe "F:\study\Systems_Virtualization\Remote"')
}

; yyoutube - Open F:\study\hosting\youtube
:*:yyoutube::
{
    Run('explorer.exe "F:\study\hosting\youtube"')
}

; ttunneling - Open F:\study\hosting\tunneling
:*:ttunneling::
{
    Run('explorer.exe "F:\study\hosting\tunneling"')
}

; wwebhosting - Open F:\study\hosting\WebHosting
:*:wwebhosting::
{
    Run('explorer.exe "F:\study\hosting\WebHosting"')
}

; nnotifications - Open F:\study\Observability\notifications
:*:nnotifications::
{
    Run('explorer.exe "F:\study\Observability\notifications"')
}

; wwebdevelopment - Open F:\study\projects\Web_Development
:*:wwebdevelopment::
{
    Run('explorer.exe "F:\study\projects\Web_Development"')
}

; ddesktopapps - Open F:\study\projects\Desktop_Apps
:*:ddesktopapps::
{
    Run('explorer.exe "F:\study\projects\Desktop_Apps"')
}

; ddevopsinfrastructure - Open F:\study\projects\DevOps_Infrastructure
:*:ddevopsinfrastructure::
{
    Run('explorer.exe "F:\study\projects\DevOps_Infrastructure"')
}

; aautomationscripting - Open F:\study\projects\Automation_Scripting
:*:aautomationscripting::
{
    Run('explorer.exe "F:\study\projects\Automation_Scripting"')
}

; ssecuritytools - Open F:\study\projects\Security_Tools
:*:ssecuritytools::
{
    Run('explorer.exe "F:\study\projects\Security_Tools"')
}

; wwindowsapps - Open F:\backup\windowsapps
:*:wwindowsapps::
{
    Run('explorer.exe "F:\backup\windowsapps"')
}

; cclaudecode - Open F:\backup\claudecode
:*:cclaudecode::
{
    Run('explorer.exe "F:\backup\claudecode"')
}

; oobsidion - Open F:\backup\obsidion
:*:oobsidion::
{
    Run('explorer.exe "F:\backup\obsidion"')
}

; llocalai - Open F:\study\AI_ML\LocalAI
:*:llocalai::
{
    Run('explorer.exe "F:\study\AI_ML\LocalAI"')
}

; ggames - Open E:\games
:*:ggames::
{
    Run('explorer.exe "E:\games"')
}

; ggamesinstallers - Open E:\GamesInstallers
:*:ggamesinstallers::
{
    Run('explorer.exe "E:\GamesInstallers"')
}

; iisos - Open E:\isos
:*:iisos::
{
    Run('explorer.exe "E:\isos"')
}

; mmicha - Open C:\Users\micha
:*:mmicha::
{
    Run('explorer.exe "C:\Users\micha"')
}

; ddesktop - Open C:\Users\micha\Desktop
:*:ddesktop::
{
    Run('explorer.exe "C:\Users\micha\Desktop"')
}

; pprogramfiles - Open C:\Program Files
:*:pprogramfiles::
{
    Run('explorer.exe "C:\Program Files"')
}

; pprogramfilesx86 - Open C:\Program Files (x86)
:*:pprogramfilesx86::
{
    Run('explorer.exe "C:\Program Files (x86)"')
}

; mmsi - Open MSI Afterburner
:*:mmsi::
{
    Run('"F:\backup\windowsapps\installed\MSI Afterburner\MSIAfterburner.exe"')
}

; launchit - Force reload this AHK script (kills old instance and relaunches)
:*:launchit::
{
    Run('"' . A_AhkPath . '" "' . A_ScriptFullPath . '"')
    ExitApp()
}

; needhelp - Show every shortcut in a categorised, human-readable GUI
; Dynamically re-parses THIS FILE on every launch so it is always up to date
:*:needhelp::
{
    scriptFile := A_ScriptFullPath

    ; ── Load all lines for lookahead ──────────────────────────────────────────
    allLines := []
    Loop Read, scriptFile
        allLines.Push(Trim(A_LoopReadLine))
    lineCount := allLines.Length

    ; ── Category buckets (ordered) ────────────────────────────────────────────
    ; Each value is an object with .title and .items array
    c_winmgmt  := {title: "WINDOW MANAGEMENT  (move · resize · split · freeze windows)", items: []}
    c_tap      := {title: "TAP GESTURES  (press the key N times rapidly)", items: []}
    c_app      := {title: "APP LAUNCHERS  (open applications)", items: []}
    c_explorer := {title: "FILE EXPLORER  (open folders)", items: []}
    c_clip     := {title: "CLIPBOARD  (instantly copy to clipboard)", items: []}
    c_system   := {title: "SYSTEM & TOOLS  (maintenance, backups, system ops)", items: []}
    c_danger   := {title: "DANGER ZONE  (destructive or irreversible actions)", items: []}
    catList    := [c_winmgmt, c_tap, c_app, c_explorer, c_clip, c_system, c_danger]

    ; ── Parse ─────────────────────────────────────────────────────────────────
    prevComment := ""
    i := 1
    while (i <= lineCount) {
        line := allLines[i]

        ; Collect the most recent comment line as description candidate
        if RegExMatch(line, "^;\s*(.+)$", &cm) {
            prevComment := cm[1]
            i++
            continue
        }

        ; ── Hotstrings  :*:trigger::
        if RegExMatch(line, "^:\*:([^:]+)::$", &hm) {
            trigger := hm[1]
            raw     := (prevComment != "") ? prevComment : trigger
            desc    := NeedHelpCleanDesc(raw, trigger)
            NeedHelpCategorize(trigger, desc, c_winmgmt, c_app, c_explorer, c_clip, c_system, c_danger)
                .items.Push({key: trigger, desc: desc})
            prevComment := ""
            i++
            continue
        }

        ; ── Tap-Up gestures  ~Ctrl Up::  ~Alt Up::
        if RegExMatch(line, "^~(Ctrl|Alt)\s+Up::$", &tm) {
            ; Look ahead up to 20 lines for the repeat-count threshold
            tapN := "4"
            j := i + 1
            while (j <= Min(i + 20, lineCount)) {
                if RegExMatch(allLines[j], ">= (\d+)", &nm)
                    tapN := nm[1]
                j++
            }
            key  := tm[1] . " x" . tapN . " taps"
            desc := (prevComment != "") ? NeedHelpCleanDesc(prevComment, key) : "-"
            c_tap.items.Push({key: key, desc: desc})
            prevComment := ""
            i++
            continue
        }

        ; ── Counter-tap hotkeys  ~F9::  ~LShift::  ~RShift::
        if RegExMatch(line, "^~(F\d+|LShift|RShift)::$", &fm) {
            tapN := "6"
            j := i + 1
            while (j <= Min(i + 25, lineCount)) {
                if RegExMatch(allLines[j], ">= (\d+)", &nm)
                    tapN := nm[1]
                j++
            }
            key  := fm[1] . " x" . tapN . " taps"
            desc := (prevComment != "") ? NeedHelpCleanDesc(prevComment, key) : "-"
            c_tap.items.Push({key: key, desc: desc})
            prevComment := ""
            i++
            continue
        }

        ; ── Regular hotkeys  ^1::  #w::  !h::  ^SC029::
        if RegExMatch(line, "^([#\^!+~]*(?:[A-Za-z][A-Za-z0-9_]*|[0-9]|SC[0-9A-Fa-f]+))::$", &km) {
            raw := km[1]
            ; Skip bare shift lines (they are handled by counter-tap block above)
            if (raw = "~LShift" || raw = "~RShift") {
                prevComment := ""
                i++
                continue
            }
            key  := NeedHelpParseKey(raw)
            desc := (prevComment != "") ? NeedHelpCleanDesc(prevComment, key) : "-"
            c_winmgmt.items.Push({key: key, desc: desc})
            prevComment := ""
            i++
            continue
        }

        prevComment := ""
        i++
    }

    ; ── Build display text ────────────────────────────────────────────────────
    total    := 0
    fullText := ""
    for cat in catList {
        fullText .= NeedHelpSection(cat.title, cat.items)
        total += cat.items.Length
    }
    fullText .= "`n================================================================`n"
    fullText .= "  " . total . " shortcuts total     source: " . scriptFile . "`n"

    ; ── GUI ───────────────────────────────────────────────────────────────────
    g := Gui("+Resize +MinSize820x500", "AHK Shortcuts Reference")
    g.BackColor := "0F0F1A"

    g.SetFont("s17 cE0AAFF Bold", "Consolas")
    g.Add("Text", "x16 y10 w960", "  AHK Shortcuts Reference")

    g.SetFont("s9 c5C5F7A", "Consolas")
    g.Add("Text", "x16 y36 w960", "  Auto-parsed from current.ahk on every launch — always up to date")

    g.SetFont("s10 cD4D4D4", "Consolas")
    edit := g.Add("Edit", "x8 y58 w984 h548 ReadOnly -E0x200 vMainEdit HScroll VScroll", fullText)
    edit.Opt("Background1A1A2E")

    g.SetFont("s11 cFF6B6B Bold", "Consolas")
    btn := g.Add("Button", "x8 y616 w130 h36 Default", "  Close [Esc]")
    btn.OnEvent("Click", (*) => g.Destroy())

    g.SetFont("s9 c4A4A6A", "Consolas")
    g.Add("Text", "x148 y624 w700", "Ctrl+A then Ctrl+C inside the box to copy all shortcuts")

    g.OnEvent("Close",  (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.OnEvent("Size",   NeedHelpResize.Bind(edit, btn))

    g.Show("w1000 h660")
}

; ── needhelp top-level helpers ────────────────────────────────────────────────

; Parse modifier symbols into human-readable key name (no corruption bug)
NeedHelpParseKey(raw) {
    k    := StrReplace(raw, "~", "")
    mods := ""
    if InStr(k, "#") {
        mods .= "Win+"
        k := StrReplace(k, "#", "")
    }
    if InStr(k, "^") {
        mods .= "Ctrl+"
        k := StrReplace(k, "^", "")
    }
    if InStr(k, "!") {
        mods .= "Alt+"
        k := StrReplace(k, "!", "")
    }
    if InStr(k, "+") {
        mods .= "Shift+"
        k := StrReplace(k, "+", "")
    }
    k := StrReplace(k, "SC029", "` (backtick)")
    return mods . k
}

; Strip redundant trigger-name prefixes from raw comment text
NeedHelpCleanDesc(d, trigger := "") {
    ; Remove "trigger - " prefix  e.g. "kkkk - Force kill..."  -> "Force kill..."
    if (trigger != "")
        d := RegExReplace(d, "^\Q" . trigger . "\E\s*-\s*", "")
    ; Remove "Hotstring: xxxx -> " prefix
    d := RegExReplace(d, "^Hotstring:\s*\S+\s*->\s*", "")
    ; Remove leading hotkey pattern "Ctrl+x - "
    d := RegExReplace(d, "^(?:Ctrl|Alt|Win|Shift)\+\S+\s*-\s*", "")
    ; Remove section-header lines (all-caps + description)
    d := RegExReplace(d, "^[A-Z ]+$", "")
    return Trim(d) = "" ? "-" : Trim(d)
}

; Decide which category bucket an entry belongs to
NeedHelpCategorize(trigger, desc, c_winmgmt, c_app, c_explorer, c_clip, c_system, c_danger) {
    d := StrLower(desc)
    t := StrLower(trigger)
    ; Danger: reboot / kill / paragon
    if InStr(d, "reboot") || InStr(d, "restart") || InStr(d, "force kill")
        || InStr(d, "shutdown") || InStr(d, "paragon") || InStr(d, "will restart")
        return c_danger
    ; Clipboard
    if InStr(d, "clipboard") || InStr(d, "copy ") || InStr(d, "copied")
        return c_clip
    ; File Explorer (folder open)
    if RegExMatch(d, "open [a-z]:\\") || InStr(d, "open downloads") || InStr(d, "installed apps")
        return c_explorer
    ; Window management
    if InStr(d, "monitor") || InStr(d, "window") || InStr(d, "split") || InStr(d, "thirds")
        || InStr(d, "halves") || InStr(d, "maximiz") || InStr(d, "minimiz") || InStr(d, "fullscreen")
        || InStr(d, "always on top") || InStr(d, "freeze") || InStr(d, "unfreeze") || InStr(d, "focus")
        || InStr(d, "restore") || InStr(d, "swap") || InStr(d, "recycle bin")
        return c_winmgmt
    ; System/tools
    if InStr(d, "backup") || InStr(d, "cleanup") || InStr(d, "lock workstation") || InStr(d, "docker")
        || InStr(d, "macrium") || InStr(d, "gateway") || InStr(d, "openclaw") || InStr(d, "claude")
        || InStr(d, "purge") || InStr(d, "terminal") || InStr(d, "wsl") || InStr(d, "disk")
        || InStr(d, "empty recycle")
        return c_system
    ; Default: app launcher
    return c_app
}

; Build one category section block
NeedHelpSection(title, items) {
    bar := "================================================================"
    out := "`n" . bar . "`n  " . title . "`n" . bar . "`n"
    if (items.Length = 0)
        return out . "  (none)`n"
    for item in items {
        k   := item.key
        pad := Max(1, 32 - StrLen(k))
        sp  := ""
        Loop pad
            sp .= " "
        out .= "  " . k . sp . item.desc . "`n"
    }
    return out
}

; Resize callback — keeps the edit control filling the window
NeedHelpResize(editCtrl, btnCtrl, gObj, minMax, w, h) {
    if (minMax = -1)
        return
    editCtrl.Move(, , w - 16, h - 112)
    btnCtrl.Move(, h - 48)
}

; ============================================================================
; F9 x6 SAFE FORCE REBOOT
; Press F9 six times rapidly to trigger an immediate safe force reboot
; ============================================================================
F9PressCount := 0
F9ResetTimer() {
    global F9PressCount
    F9PressCount := 0
}

; Force reboot the PC immediately (no confirmation, no delay)
~F9::
{
    global F9PressCount
    F9PressCount++
    SetTimer(F9ResetTimer, -1500)
    if (F9PressCount >= 6) {
        F9PressCount := 0
        Run('shutdown.exe /r /f /t 0', , 'Hide')
    }
}

