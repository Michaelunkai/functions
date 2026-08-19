#Requires AutoHotkey v2.0
#SingleInstance Force

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

; Track frozen processes for Ctrl+h / Alt+h functionality
global frozenProcesses := []        ; Array of frozen process info: {pid, hwnd, title}

; ============================================================================
; HOTKEYS - Keyboard shortcuts
; ============================================================================

; Win+W - Launch Wand
#w::
{
    Run('"C:\Users\micha\AppData\Local\Wand\app-12.9.1\Wand.exe"')
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

    ; Move to target monitor in fullscreen mode (covers entire screen)
    try {
        WinMove(tLeft, tTop, tRight - tLeft, tBottom - tTop, "ahk_id " hwnd)
        ToolTip("Moved fullscreen to Monitor " targetMonitor)
        SetTimer(() => ToolTip(), -1500)
    } catch as err {
        ToolTip("Error moving window: " err.Message)
        SetTimer(() => ToolTip(), -2000)
        return
    }
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

; REMOVED: Ctrl+S and Alt+S hotkeys (were causing nano/terminal freeze issues)

; Ctrl+h - INSTANT FREEZE - Immediately minimize and suspend current app
; Uses pure Windows API - minimize FIRST, then suspend
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

; toto - Open Todoist
:*:toto::
{
    Run('"C:\Program Files\WindowsApps\88449BC3.TodoistPlannerCalendarMSIX_9.26.2.0_x64__71ef4824z52ta\app\Todoist.exe"')
}

; sslack - Open Slack
:*:sslack::
{
    Run('"C:\Program Files\WindowsApps\91750D7E.Slack_4.47.69.0_x64__8she8kybcnzg4\app\Slack.exe"')
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

; qqbit - Open qBittorrent portable
:*:qqbit::
{
    Run('"F:\backup\windowsapps\installed\qBittorrent\qBittorrentPortable.exe"')
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
