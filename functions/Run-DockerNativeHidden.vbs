Option Explicit
Dim shell
If WScript.Arguments.Count <> 1 Then WScript.Quit 64
Set shell = CreateObject("WScript.Shell")
WScript.Quit shell.Run(WScript.Arguments.Item(0), 0, True)
