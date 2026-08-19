'+-------------------------------------+
'| Enhanced Game Shortcut Creator      |
'| @version: 4.0                       |
'| @date: 2025                         |
'|                                     |
'| Features:                           |
'| - Recursive scan of entire tree     |
'| - Advanced exe detection            |
'| - Smart game filtering              |
'| - Automatic shortcut creation       |
'| - No user prompts required          |
'+-------------------------------------+

Option Explicit

Dim FSO: Set FSO = CreateObject("Scripting.FileSystemObject")
Dim WSO: Set WSO = CreateObject("Wscript.Shell")
Dim ShortcutFolder, DesktopPath, GamesFolder
Dim ProcessedGames: Set ProcessedGames = CreateObject("Scripting.Dictionary")

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

' Clean up old shortcuts first
CleanupOldShortcuts

' Process each game folder recursively
ProcessGameFolders

WScript.Echo "Game shortcut creation completed!"

'==========================================
' MAIN PROCESSING FUNCTIONS
'==========================================

'' Main processing function - enhanced recursive approach
Sub ProcessGameFolders()
    Dim GamesFolderObj, GameFolder
    Set GamesFolderObj = FSO.GetFolder(GamesFolder)

    ' Process each subfolder as a potential game
    For Each GameFolder In GamesFolderObj.SubFolders
        ProcessSingleGameFolder GameFolder
    Next
End Sub

'' Process a single game folder with recursive exe search
Sub ProcessSingleGameFolder(gameFolder)
    Dim GameName, AllExeFiles, BestExe, ExeFile
    
    GameName = gameFolder.Name
    
    ' Skip if already processed (prevents duplicates)
    If ProcessedGames.Exists(LCase(GameName)) Then Exit Sub
    ProcessedGames.Add LCase(GameName), True
    
    ' Get all exe files recursively from this game folder
    Set AllExeFiles = CreateObject("Scripting.Dictionary")
    FindAllExecutables gameFolder, AllExeFiles, GameName
    
    ' Find the best executable for this game
    BestExe = SelectBestGameExecutable(AllExeFiles, GameName)
    
    If BestExe <> "" Then
        CreateGameShortcut GameName, BestExe, gameFolder.Path
        WScript.Echo "Created shortcut for: " & GameName & " -> " & FSO.GetFileName(BestExe)
    Else
        WScript.Echo "No suitable executable found for: " & GameName
    End If
End Sub

'==========================================
' ENHANCED EXECUTABLE DETECTION
'==========================================

'' Recursively find all executable files in game folder and subfolders
Sub FindAllExecutables(folder, exeDict, gameName)
    Dim file, subFolder
    
    ' Process files in current folder
    For Each file In folder.Files
        If LCase(FSO.GetExtensionName(file.Name)) = "exe" Then
            If Not IsSystemOrUtilityFile(file.Name, file.Size) Then
                Dim priority: priority = CalculateExecutablePriority(file, gameName, folder)
                exeDict.Add file.Path, priority
            End If
        End If
    Next
    
    ' Recursively process subfolders
    For Each subFolder In folder.SubFolders
        ' Skip certain folders that are unlikely to contain game executables
        If Not IsSkippableFolder(subFolder.Name) Then
            FindAllExecutables subFolder, exeDict, gameName
        End If
    Next
End Sub

'' Calculate priority score for an executable
Function CalculateExecutablePriority(file, gameName, parentFolder)
    Dim priority, fileName, folderName, filePath
    Dim fileSize, pathDepth
    
    priority = 0
    fileName = LCase(FSO.GetBaseName(file.Name))
    folderName = LCase(parentFolder.Name)
    filePath = LCase(file.Path)
    fileSize = file.Size
    
    ' Calculate path depth (deeper = lower priority)
    pathDepth = UBound(Split(file.Path, "\")) - UBound(Split(GamesFolder, "\"))
    
    ' HIGHEST PRIORITY: Exact or close name match with game folder
    If fileName = LCase(gameName) Then
        priority = priority + 1000000
    ElseIf InStr(fileName, LCase(gameName)) > 0 Then
        priority = priority + 800000
    ElseIf InStr(LCase(gameName), fileName) > 0 Then
        priority = priority + 600000
    End If
    
    ' HIGH PRIORITY: File in root of game folder
    If pathDepth = 1 Then
        priority = priority + 500000
    End If
    
    ' MEDIUM-HIGH PRIORITY: File in common game folders
    If InStr(filePath, "\bin\") > 0 Or InStr(filePath, "\game\") > 0 Or _
       InStr(filePath, "\exe\") > 0 Or InStr(filePath, "\binaries\") > 0 Then
        priority = priority + 300000
    End If
    
    ' MEDIUM PRIORITY: Contains "game" in filename
    If InStr(fileName, "game") > 0 Then
        priority = priority + 200000
    End If
    
    ' MEDIUM PRIORITY: Larger files (likely main executables)
    If fileSize > 50000000 Then        ' > 50MB
        priority = priority + 150000 + (fileSize \ 1000000)  ' Add MB count
    ElseIf fileSize > 10000000 Then    ' > 10MB
        priority = priority + 100000 + (fileSize \ 1000000)
    ElseIf fileSize > 1000000 Then     ' > 1MB
        priority = priority + 50000 + (fileSize \ 1000000)
    End If
    
    ' LOWER PRIORITY: Penalty for deep nesting
    priority = priority - (pathDepth * 10000)
    
    ' BONUS: Common game executable patterns
    If InStr(fileName, "main") > 0 Then priority = priority + 25000
    If InStr(fileName, "start") > 0 Then priority = priority + 20000
    If InStr(fileName, "run") > 0 Then priority = priority + 15000
    If InStr(fileName, "play") > 0 Then priority = priority + 15000
    
    CalculateExecutablePriority = priority
End Function

'' Select the best executable from all found executables
Function SelectBestGameExecutable(exeDict, gameName)
    Dim bestExe, maxPriority, exePath
    
    bestExe = ""
    maxPriority = 0
    
    For Each exePath In exeDict.Keys
        If exeDict(exePath) > maxPriority Then
            maxPriority = exeDict(exePath)
            bestExe = exePath
        End If
    Next
    
    SelectBestGameExecutable = bestExe
End Function

'==========================================
' ENHANCED FILTERING FUNCTIONS
'==========================================

'' Enhanced filter for non-game executables
Function IsSystemOrUtilityFile(fileName, fileSize)
    Dim lowerName
    lowerName = LCase(fileName)
    
    ' Files smaller than 50KB are probably not games
    If fileSize < 51200 Then ' 50KB
        IsSystemOrUtilityFile = True
        Exit Function
    End If
    
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
    If InStr(lowerName, "convert") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "extract") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    
    ' Anti-virus and security
    If InStr(lowerName, "virus") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "antiv") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    If InStr(lowerName, "security") > 0 Then IsSystemOrUtilityFile = True: Exit Function
    
    ' Specific common files
    If lowerName = "register.exe" Then IsSystemOrUtilityFile = True: Exit Function
    If lowerName = "regsvr32.exe" Then IsSystemOrUtilityFile = True: Exit Function
    If lowerName = "readme.exe" Then IsSystemOrUtilityFile = True: Exit Function
    If lowerName = "help.exe" Then IsSystemOrUtilityFile = True: Exit Function
    If lowerName = "manual.exe" Then IsSystemOrUtilityFile = True: Exit Function
    If lowerName = "license.exe" Then IsSystemOrUtilityFile = True: Exit Function
    If lowerName = "eula.exe" Then IsSystemOrUtilityFile = True: Exit Function
    
    ' Additional system files
    If lowerName = "dxsetup.exe" Then IsSystemOrUtilityFile = True: Exit Function
    If lowerName = "dotnetfx.exe" Then IsSystemOrUtilityFile = True: Exit Function
    If lowerName = "flashplayer.exe" Then IsSystemOrUtilityFile = True: Exit Function
    
    IsSystemOrUtilityFile = False
End Function

'' Check if folder should be skipped during recursive search
Function IsSkippableFolder(folderName)
    Dim lowerName
    lowerName = LCase(folderName)
    
    ' Skip common non-executable folders
    If lowerName = "data" Then IsSkippableFolder = True: Exit Function
    If lowerName = "saves" Then IsSkippableFolder = True: Exit Function
    If lowerName = "screenshots" Then IsSkippableFolder = True: Exit Function
    If lowerName = "mods" Then IsSkippableFolder = True: Exit Function
    If lowerName = "plugins" Then IsSkippableFolder = True: Exit Function
    If lowerName = "textures" Then IsSkippableFolder = True: Exit Function
    If lowerName = "sounds" Then IsSkippableFolder = True: Exit Function
    If lowerName = "music" Then IsSkippableFolder = True: Exit Function
    If lowerName = "videos" Then IsSkippableFolder = True: Exit Function
    If lowerName = "movies" Then IsSkippableFolder = True: Exit Function
    If lowerName = "docs" Then IsSkippableFolder = True: Exit Function
    If lowerName = "documentation" Then IsSkippableFolder = True: Exit Function
    If lowerName = "manual" Then IsSkippableFolder = True: Exit Function
    If lowerName = "readme" Then IsSkippableFolder = True: Exit Function
    If lowerName = "logs" Then IsSkippableFolder = True: Exit Function
    If lowerName = "temp" Then IsSkippableFolder = True: Exit Function
    If lowerName = "cache" Then IsSkippableFolder = True: Exit Function
    If lowerName = "backup" Then IsSkippableFolder = True: Exit Function
    
    IsSkippableFolder = False
End Function

'==========================================
' SHORTCUT CREATION FUNCTIONS
'==========================================

'' Create a clean shortcut with enhanced properties
Sub CreateGameShortcut(gameName, exePath, workingDir)
    Dim shortCut, shortcutPath, cleanName
    
    ' Clean up the game name
    cleanName = CleanGameName(gameName)
    shortcutPath = ShortcutFolder & "\" & cleanName & ".lnk"
    
    ' Avoid duplicate shortcuts
    If FSO.FileExists(shortcutPath) Then
        Dim counter: counter = 2
        Do While FSO.FileExists(ShortcutFolder & "\" & cleanName & " (" & counter & ").lnk")
            counter = counter + 1
        Loop
        shortcutPath = ShortcutFolder & "\" & cleanName & " (" & counter & ").lnk"
    End If
    
    ' Create the shortcut
    Set shortCut = WSO.CreateShortcut(shortcutPath)
    shortCut.TargetPath = exePath
    shortCut.WorkingDirectory = FSO.GetParentFolderName(exePath)
    shortCut.Description = cleanName & " - Game Shortcut"
    
    ' Try to set icon from the exe
    On Error Resume Next
    shortCut.IconLocation = exePath & ",0"
    On Error GoTo 0
    
    shortCut.Save
End Sub

'' Enhanced game name cleaning
Function CleanGameName(name)
    Dim result
    result = name
    
    ' Replace common separators with spaces
    result = Replace(result, "_", " ")
    result = Replace(result, "-", " ")
    result = Replace(result, ".", " ")
    result = Replace(result, "+", " ")
    
    ' Remove version numbers and common suffixes
    result = Replace(result, " Portable", "")
    result = Replace(result, " PORTABLE", "")
    result = Replace(result, " Final", "")
    result = Replace(result, " Complete", "")
    result = Replace(result, " Edition", "")
    result = Replace(result, " GOTY", "")
    result = Replace(result, " Gold", "")
    result = Replace(result, " Deluxe", "")
    result = Replace(result, " Ultimate", "")
    result = Replace(result, " Repack", "")
    result = Replace(result, " Cracked", "")
    result = Replace(result, " NoCD", "")
    result = Replace(result, " NoDVD", "")
    
    ' Remove common version patterns
    result = RegExReplace(result, "\s+v\d+(\.\d+)*", "")
    result = RegExReplace(result, "\s+\d+(\.\d+)+", "")
    result = RegExReplace(result, "\s+\(\d{4}\)", "")
    
    ' Clean up multiple spaces
    Do While InStr(result, "  ") > 0
        result = Replace(result, "  ", " ")
    Loop
    
    ' Capitalize first letter of each word
    result = ProperCase(Trim(result))
    
    CleanGameName = result
End Function

'' Simple regex replace function
Function RegExReplace(text, pattern, replacement)
    Dim regEx
    Set regEx = CreateObject("VBScript.RegExp")
    regEx.Global = True
    regEx.IgnoreCase = True
    regEx.Pattern = pattern
    RegExReplace = regEx.Replace(text, replacement)
End Function

'' Convert to proper case
Function ProperCase(text)
    Dim words, i, result
    words = Split(text, " ")
    result = ""
    
    For i = 0 To UBound(words)
        If Len(words(i)) > 0 Then
            words(i) = UCase(Left(words(i), 1)) & LCase(Mid(words(i), 2))
        End If
        If i > 0 Then result = result & " "
        result = result & words(i)
    Next
    
    ProperCase = result
End Function

'==========================================
' CLEANUP FUNCTIONS
'==========================================

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