#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, OutputDebug

; Arguments: target PID, optional creation stamp.
; This helper deliberately uses native process termination instead of taskkill.
; taskkill /T can wait indefinitely on a console or game process tree.
try {
if (A_Args.Length < 1) {
    ExitApp(2)
}

try targetPid := Integer(A_Args[1])
catch {
    ExitApp(2)
}

expectedCreationStamp := A_Args.Length >= 2 ? A_Args[2] : ""
if (!targetPid || !ProcessExist(targetPid)) {
    ExitApp(3)
}

if (expectedCreationStamp != "") {
    actualCreationStamp := GetKkkkCreationStamp(targetPid)
    if (actualCreationStamp = "" || actualCreationStamp != expectedCreationStamp) {
        ExitApp(3)
    }
}

processIds := GetKkkkProcessTree(targetPid)
if (!processIds.Length) {
    processIds := [targetPid]
}

currentPid := DllCall("GetCurrentProcessId", "UInt")
rootTerminationRequested := false
rootTerminationSucceeded := false

; Children are terminated first, then the foreground process itself.
Loop processIds.Length {
    index := processIds.Length - A_Index + 1
    processId := processIds[index]
    if (processId = currentPid) {
        continue
    }

    processHandle := DllCall("OpenProcess", "UInt", 0x0001
        , "Int", 0, "UInt", processId, "Ptr")
    if (!processHandle) {
        if (processId = targetPid) {
            rootTerminationRequested := true
        }
        continue
    }

    terminated := DllCall("TerminateProcess", "Ptr", processHandle
        , "UInt", 1, "Int")
    DllCall("CloseHandle", "Ptr", processHandle)
    if (processId = targetPid) {
        rootTerminationRequested := true
        rootTerminationSucceeded := !!terminated
    }
}

if (!rootTerminationRequested) {
    ExitApp(6)
}

if (WaitForKkkkProcessTree(processIds, 1500)) {
    ExitApp(0)
}

; A process may have exited between the snapshot and the termination call.
; Treat the root as successful only when it is no longer the original process.
if (!ProcessExist(targetPid)
    || (expectedCreationStamp != ""
        && GetKkkkCreationStamp(targetPid) != expectedCreationStamp)) {
    ExitApp(0)
}

ExitApp(rootTerminationSucceeded ? 5 : 6)
} catch {
    ; Never leave the caller blocked behind an interactive runtime-error dialog.
    ExitApp(7)
}

GetKkkkProcessTree(rootPid)
{
    snapshot := DllCall("CreateToolhelp32Snapshot", "UInt", 0x00000002
        , "UInt", 0, "Ptr")
    if (snapshot = -1) {
        return [rootPid]
    }

    entrySize := A_PtrSize = 8 ? 568 : 556
    parentOffset := A_PtrSize = 8 ? 32 : 24
    entry := Buffer(entrySize, 0)
    NumPut("UInt", entrySize, entry, 0)
    parentByProcessId := Map()

    if DllCall("Process32FirstW", "Ptr", snapshot, "Ptr", entry.Ptr, "Int") {
        Loop {
            processId := NumGet(entry, 8, "UInt")
            parentId := NumGet(entry, parentOffset, "UInt")
            if (processId) {
                parentByProcessId[processId] := parentId
            }
            if !DllCall("Process32NextW", "Ptr", snapshot, "Ptr", entry.Ptr, "Int") {
                break
            }
        }
    }
    DllCall("CloseHandle", "Ptr", snapshot)

    ordered := [rootPid]
    seen := Map(rootPid, true)
    changed := true
    while changed {
        changed := false
        for processId, parentId in parentByProcessId {
            if (!seen.Has(processId) && seen.Has(parentId)) {
                seen[processId] := true
                ordered.Push(processId)
                changed := true
            }
        }
    }
    return ordered
}

WaitForKkkkProcessTree(processIds, timeoutMs)
{
    deadline := A_TickCount + timeoutMs
    Loop {
        anyAlive := false
        for _, processId in processIds {
            if (ProcessExist(processId)) {
                anyAlive := true
                break
            }
        }
        if (!anyAlive) {
            return true
        }
        if (A_TickCount >= deadline) {
            return false
        }
        Sleep(25)
    }
}

GetKkkkCreationStamp(processId)
{
    processHandle := DllCall("OpenProcess", "UInt", 0x1000
        , "Int", 0, "UInt", processId, "Ptr")
    if (!processHandle) {
        return ""
    }

    times := Buffer(32, 0)
    ok := DllCall("GetProcessTimes", "Ptr", processHandle
        , "Ptr", times.Ptr, "Ptr", times.Ptr + 8
        , "Ptr", times.Ptr + 16, "Ptr", times.Ptr + 24, "Int")
    DllCall("CloseHandle", "Ptr", processHandle)
    return ok ? Format("{:016X}", NumGet(times, 0, "Int64")) : ""
}
