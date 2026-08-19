Option Explicit
Dim shell, fso, exe, cmd
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
exe = "C:\Program Files\murmure\murmure.exe"
If Not fso.FileExists(exe) Then WScript.Quit 2
cmd = Chr(34) & exe & Chr(34)
shell.Run cmd, 0, False
WScript.Quit 0
