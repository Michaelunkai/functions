#Requires AutoHotkey v2.0

rfile := "F:\study\Platforms\windows\autohotkey\mymainahk\hooktest-result.txt"

^9:: FileAppend(A_Now " | ^9 fired`n", rfile)
^8:: FileAppend(A_Now " | ^8 fired`n", rfile)
^7:: FileAppend(A_Now " | ^7 fired`n", rfile)
