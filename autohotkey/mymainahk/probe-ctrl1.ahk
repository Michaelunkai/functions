#Requires AutoHotkey v2.0

resultFile := "F:\study\Platforms\windows\autohotkey\mymainahk\probe-result.txt"

Log(msg) {
    global resultFile
    FileAppend(A_Now " | " msg "`n", resultFile)
}

FileAppend(A_Now " | PROBE STARTED`n", resultFile)

myGui := Gui("+AlwaysOnTop", "AHK Probe")
myGui.Add("Text", "w400 h200", "AHK Hotkey Probe - Ctrl+1 test window`nDo not interact with this window.")
myGui.Show("w420 h300 x80 y140")
Log("gui shown at 80,140 420x300")
Sleep(700)

WinActivate("ahk_id " myGui.Hwnd)
Sleep(400)

activeHwnd := WinGetID("A")
activeTitle := WinGetTitle("ahk_id " activeHwnd)
Log("active before send: hwnd=" activeHwnd " title='" activeTitle "'")
Log("probe hwnd=" myGui.Hwnd " isActive=" (activeHwnd = myGui.Hwnd))

WinGetPos(&x1, &y1, &w1, &h1, "ahk_id " myGui.Hwnd)
Log("before: " x1 "," y1 " " w1 "x" h1 " minMax=" WinGetMinMax("ahk_id " myGui.Hwnd))
Send("^1")
Log("sent ^1")
Sleep(2200)
WinGetPos(&x2, &y2, &w2, &h2, "ahk_id " myGui.Hwnd)
Log("after:  " x2 "," y2 " " w2 "x" h2 " minMax=" WinGetMinMax("ahk_id " myGui.Hwnd))

moved := (x1 != x2 || y1 != y2 || w1 != w2 || h1 != h2)
Log("moved=" moved)
ExitApp()
