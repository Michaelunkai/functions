#Requires AutoHotkey v2.0
#SingleInstance Off

if (A_Args.Length < 3) {
    ExitApp(2)
}

try pid := Integer(A_Args[1])
catch {
    ExitApp(2)
}
expectedCreated := A_Args[2]
stateFile := A_Args[3]

GetCreationStamp(targetPid) {
    hProcess := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", targetPid, "Ptr")
    if (!hProcess) {
        return ""
    }
    times := Buffer(32, 0)
    ok := DllCall("GetProcessTimes", "Ptr", hProcess, "Ptr", times
        , "Ptr", times.Ptr + 8, "Ptr", times.Ptr + 16, "Ptr", times.Ptr + 24, "Int")
    DllCall("CloseHandle", "Ptr", hProcess)
    return ok ? Format("{:016X}", NumGet(times, 0, "Int64")) : ""
}

if (!ProcessExist(pid) || expectedCreated = "" || GetCreationStamp(pid) != expectedCreated) {
    ExitApp(3)
}

try count := Integer(IniRead(stateFile, "FrozenProcesses", "Count", "0"))
catch {
    ExitApp(4)
}

authorized := false
Loop count {
    section := "FrozenProcess" A_Index
    try savedPid := Integer(IniRead(stateFile, section, "Pid", "0"))
    catch {
        continue
    }
    if (savedPid = pid
        && IniRead(stateFile, section, "Created", "") = expectedCreated
        && IniRead(stateFile, section, "Mode", "") = "game_suspend"
        && IniRead(stateFile, section, "State", "") = "paused") {
        authorized := true
        break
    }
}
if (!authorized) {
    ExitApp(5)
}

hProcess := DllCall("OpenProcess", "UInt", 0x0500, "Int", 0, "UInt", pid, "Ptr") ; SET_QUOTA | QUERY_INFORMATION
if (!hProcess) {
    ExitApp(6)
}
trimmed := DllCall("psapi\EmptyWorkingSet", "Ptr", hProcess, "Int")
DllCall("CloseHandle", "Ptr", hProcess)
ExitApp(trimmed ? 0 : 7)
