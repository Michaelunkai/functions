Option Explicit
Dim shell, fso, target, waitSeconds, windowStyle, maxWaitSeconds, cmd, elapsed
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
If WScript.Arguments.Count < 1 Then WScript.Quit 64
target = WScript.Arguments(0)
waitSeconds = 0
windowStyle = 0
maxWaitSeconds = 30
If WScript.Arguments.Count >= 2 Then waitSeconds = CLng(Val(WScript.Arguments(1)))
If WScript.Arguments.Count >= 3 Then windowStyle = CLng(Val(WScript.Arguments(2)))
If WScript.Arguments.Count >= 4 Then maxWaitSeconds = CLng(Val(WScript.Arguments(3)))
If waitSeconds > 0 Then WScript.Sleep waitSeconds * 1000
elapsed = 0
Do While Not fso.FileExists(target)
  If elapsed >= maxWaitSeconds Then WScript.Quit 2
  WScript.Sleep 1000
  elapsed = elapsed + 1
Loop
cmd = Chr(34) & target & Chr(34)
shell.Run cmd, windowStyle, False
WScript.Quit 0
