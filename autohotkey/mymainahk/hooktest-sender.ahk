#Requires AutoHotkey v2.0

sfile := "F:\study\Platforms\windows\autohotkey\mymainahk\hooktest-sender-result.txt"

myGui := Gui("+AlwaysOnTop", "Hook Sender")
myGui.Add("Text", "w300 h150", "Sending ^9 ^8 ^7 ...")
myGui.Show("w320 h180 x120 y180")
Sleep(500)
WinActivate("ahk_id " myGui.Hwnd)
Sleep(300)
Send("^9")
Sleep(150)
Send("^8")
Sleep(150)
Send("^7")
Sleep(300)
FileAppend(A_Now " | sent 9,8,7`n", sfile)
ExitApp()
