'+-------------------------------------+
'| Advanced Game Shortcut Creator      |
'| @version: 3.0                       |
'| @date: 2024                         |
'|                                     |
'| Script:                             |
'| Scans F:\games - each subfolder     |
'| is treated as one game              |
'| Intelligently finds main game exe   |
'| Creates shortcuts in Desktop\Games  |
'| Fully automated - no prompts        |
'+-------------------------------------+

Option Explicit

Dim FSO: Set FSO = CreateObject("Scripting.FileSystemObject")
Dim WSO: Set WSO = CreateObject("Wscript.Shell")
Dim ShortcutFolder, DesktopPath, GamesFolder

' Setup paths
DesktopPath = WSO.SpecialFolders("Desktop")
ShortcutFolder = DesktopPath & "\Games"
GamesFolder = "F:\games"

' Create Games folder if needed
If Not FSO.FolderExists(ShortcutFolder) Then
    FSO.CreateFolder(ShortcutFolder)
End If

' Exit silently if games folder doesn't exist
If Not FSO.FolderExists(GamesFolder) Then
    WScript.Quit
End If

' Clean up old shortcuts
CleanupOldShortcuts

' Process each game folder
ProcessGameFolders

'' Main processing function
Sub ProcessGameFolders()
    Dim GamesFolderObj, GameFolder, MainExe, GameName
    
    Set GamesFolderObj = FSO.GetFolder(GamesFolder)
    
    ' Each subfolder in F:\games is a separate game
    For Each GameFolder In GamesFolderObj.SubFolders
        GameName = GameFolder.Name
        MainExe = FindMainGameExecutable(GameFolder)
        
        If MainExe <> "" Then
            CreateGameShortcut GameName, MainExe, GameFolder.Path
        End If
    Next
End Sub

'' Intelligently find the main game executable
Function FindMainGameExecutable(gameFolder)
    Dim files, file, candidateExes, bestExe
    Dim folderName, fileName, fileSize, maxSize
    
    Set candidateExes = CreateObject("Scripting.Dictionary")
    folderName = LCase(gameFolder.Name)
    maxSize = 0
    bestExe = ""
    
    Set files = gameFolder.Files
    
    ' Pass 1: Look for exe files and categorize them
    For Each file In files
        If LCase(FSO.GetExtensionName(file.Name)) = "exe" Then
            fileName = LCase(file.Name)
            fileSize = file.Size
            
            ' Skip obvious non-game files
            If Not IsSystemOrUtilityFile(fileName) Then
                ' Priority 1: Exe name matches or contains folder name
                If InStr(fileName, folderName) > 0 Or InStr(folderName, Replace(fileName, ".exe", "")) > 0 Then
                    candidateExes.Add file.Name, 1000000 + fileSize ' Highest priority
                ' Priority 2: Contains "game" keyword
                ElseIf InStr(fileName, "game") > 0 Then
                    candidateExes.Add file.Name, 500000 + fileSize
                ' Priority 3: Larger files (likely main game)
                ElseIf fileSize > 1000000 Then ' > 1MB
                    candidateExes.Add file.Name, fileSize
                ' Priority 4: Other exe files
                Else
                    candidateExes.Add file.Name, fileSize
                End If
            End If
        End If
    Next
    
    ' Pass 2: Also check immediate subfolders (like bin/, game/, etc.)
    For Each file In gameFolder.SubFolders
        If LCase(file.Name) = "bin" Or LCase(file.Name) = "game" Or LCase(file.Name) = "exe" Or LCase(file.Name) = "binaries" Then
            bestExe = CheckSubfolderForExe(file, folderName)
            If bestExe <> "" Then
                FindMainGameExecutable = bestExe
                Exit Function
            End If
        End If
    Next
    
    ' Find the best candidate
    Dim key, maxPriority
    maxPriority = 0
    
    For Each key In candidateExes.Keys
        If candidateExes(key) > maxPriority Then
            maxPriority = candidateExes(key)
            bestExe = key
        End If
    Next
    
    If bestExe <> "" Then
        FindMainGameExecutable = gameFolder.Path & "\" & bestExe
    Else
        FindMainGameExecutable = ""
    End If
End Function

'' Check subfolder for game executable
Function CheckSubfolderForExe(subFolder, gameName)
    Dim files, file, fileName, bestExe, maxSize
    
    maxSize = 0
    bestExe = ""
    gameName = LCase(gameName)
    
    Set files = subFolder.Files
    
    For Each file In files
        If LCase(FSO.GetExtensionName(file.Name)) = "exe" Then
            fileName = LCase(file.Name)
            
            If Not IsSystemOrUtilityFile(fileName) Then
                ' Prefer exe that matches game name
                If InStr(fileName, gameName) > 0 Then
                    CheckSubfolderForExe = subFolder.Path & "\" & file.Name
                    Exit Function
                End If
                
                ' Otherwise take the largest exe
                If file.Size > maxSize Then
                    maxSize = file.Size
                    bestExe = subFolder.Path & "\" & file.Name
                End If
            End If
        End If
    Next
    
    CheckSubfolderForExe = bestExe
End Function

'' Comprehensive filter for non-game executables
Function IsSystemOrUtilityFile(fileName)
    Dim lowerName
    lowerName = LCase(fileName)
    
    ' Installers and uninstallers
    If InStr(lowerName, "unins") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "setup") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "install") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "uninst") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    
    ' System and utility files
    If InStr(lowerName, "update") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "patch") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "config") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "setting") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "launcher") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "crash") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "report") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "redist") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "vcredist") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "directx") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    
    ' Development and debug files
    If InStr(lowerName, "debug") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "test") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "editor") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "tool") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "util") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    
    ' Specific common files
    If lowerName = "register.exe" Then IsSystemOrUtilityFile = True: Exit Function
    If lowerName = "regsvr32.exe" Then IsSystemOrUtilityFile = True: Exit Function
    If lowerName = "readme.exe" Then IsSystemOrUtilityFile = True: Exit Function
    If lowerName = "help.exe" Then IsSystemOrUtilityFile = True: Exit Function
    If lowerName = "manual.exe" Then IsSystemOrUtilityFile = True: Exit Function
    
    ' File size check - files smaller than 100KB are probably not games
    If FSO.FileExists(lowerName) Then
        If FSO.GetFile(lowerName).Size < 102400 Then ' 100KB
            IsSystemOrUtilityFile = True
            Exit Function
        End If
    End If
    
    IsSystemOrUtilityFile = False
End Function

'' Create a clean shortcut
Sub CreateGameShortcut(gameName, exePath, workingDir)
    Dim shortCut, shortcutPath, cleanName
    
    ' Clean up the game name
    cleanName = CleanGameName(gameName)
    shortcutPath = ShortcutFolder & "\" & cleanName & ".lnk"
    
    ' Create the shortcut
    Set shortCut = WSO.CreateShortcut(shortcutPath)
    shortCut.TargetPath = exePath
    shortCut.WorkingDirectory = workingDir
    shortCut.Description = cleanName
    
    ' Try to set icon from the exe
    On Error Resume Next
    shortCut.IconLocation = exePath & ",0"
    On Error GoTo 0
    
    shortCut.Save
End Sub

'' Clean up game name for shortcut
Function CleanGameName(name)
    Dim result
    result = name
    
    ' Replace common separators with spaces
    result = Replace(result, "_", " ")
    result = Replace(result, "-", " ")
    result = Replace(result, ".", " ")
    
    ' Remove common suffixes
    result = Replace(result, " Portable", "")
    result = Replace(result, " PORTABLE", "")
    result = Replace(result, " Final", "")
    result = Replace(result, " Complete", "")
    result = Replace(result, " Edition", "")
    result = Replace(result, " GOTY", "")
    result = Replace(result, " Gold", "")
    
    ' Clean up multiple spaces
    Do While InStr(result, "  ") > 0
        result = Replace(result, "  ", " ")
    Loop
    
    ' Trim and return
    CleanGameName = Trim(result)
End Function

'' Clean up old shortcuts
Sub CleanupOldShortcuts()
    If Not FSO.FolderExists(ShortcutFolder) Then Exit Sub
    
    Dim objFolder, objFile
    Set objFolder = FSO.GetFolder(ShortcutFolder)
    
    For Each objFile In objFolder.Files
        If LCase(FSO.GetExtensionName(objFile.Name)) = "lnk" Then
            On Error Resume Next
            objFile.Delete True
            On Error GoTo 0
        End If
    Next
End Sub
