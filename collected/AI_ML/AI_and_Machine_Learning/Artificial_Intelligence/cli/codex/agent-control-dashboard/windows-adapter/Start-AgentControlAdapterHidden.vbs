Option Explicit

Dim shell, fileSystem, launcherPath, workingDirectory, command
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

workingDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
launcherPath = fileSystem.BuildPath(workingDirectory, "Start-AgentControlAdapter.ps1")
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & launcherPath & """"

shell.CurrentDirectory = workingDirectory
WScript.Quit shell.Run(command, 0, False)
