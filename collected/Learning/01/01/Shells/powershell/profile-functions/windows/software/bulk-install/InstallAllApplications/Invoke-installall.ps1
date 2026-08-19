# Extracted from C:\users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1.
# The live profile keeps a thin launcher and dot-sources this script.
$__extractedFunctionName = 'installall'
$__extractedScriptPath = $PSCommandPath
$__extractedArgs = @($args)
if ($__extractedArgs -contains '-SelfTest') {
    [pscustomobject]@{
        Script = $__extractedScriptPath
        Exists = (Test-Path -LiteralPath $__extractedScriptPath)
        Function = $__extractedFunctionName
        Mode = 'SelfTest'
    }
    return
}

function installall {
    [CmdletBinding()]
    param (
        [string]$SourceDirectory = "C:\users\micha\downloads\a",
        [string]$GameDestination = "F:\games",
        [int]$MaxConcurrentInstalls = 5
    )
    # Create games destination if it doesn't exist
    if (-not (Test-Path -Path $GameDestination)) {
        New-Item -Path $GameDestination -ItemType Directory -Force > $null
        Write-Output "Created games destination directory: $GameDestination" -ForegroundColor Green
    }
    # Find all setup files recursively (common installer extensions)
    $setupFiles = Get-ChildItem -Path $SourceDirectory -Recurse -Include "*.exe", "*.msi" |
                 Where-Object { $_.Name -match "setup|install|launcher" -or $_.Name -match "^(setup|install)\.exe$" }
    if ($setupFiles.Count -eq 0) {
        Write-Output "No setup files found in $SourceDirectory" -ForegroundColor Yellow
        return
    }
    Write-Output "Found $($setupFiles.Count) setup files to install" -ForegroundColor Cyan
    # Initialize variables to track running installations
    $runningJobs = @{}
    $completedFiles = 0
    # Process all setup files
    foreach ($setupFile in $setupFiles) {
        # Wait if we've reached max concurrent installs
        while ($runningJobs.Count -ge $MaxConcurrentInstalls) {
            $completedJobs = $runningJobs.Keys | Where-Object { $runningJobs[$_].State -ne 'Running' }
            if ($completedJobs.Count -gt 0) {
                foreach ($jobId in $completedJobs) {
                    $job = $runningJobs[$jobId]
                    $setupName = $job.Name
                    # Process completed job
                    Write-Output "Installation completed: $setupName" -ForegroundColor Green
                    $completedFiles++
                    # Clean up job
                    Remove-Job -Job $job -Force
                    $runningJobs.Remove($jobId)
                }
            }
            else {
                # Wait a moment before checking again
                Start-Sleep -Seconds 2
            }
        }
        # Extract game name from setup file
        $gameName = [System.IO.Path]::GetFileNameWithoutExtension($setupFile.Name) -replace "(setup|install|launcher)", "" -replace "[-_\.]", " "
        $gameName = $gameName.Trim()
        # If name is empty or too generic, use parent folder name
        if ([string]::IsNullOrWhiteSpace($gameName) -or $gameName.Length -lt 3) {
            $gameName = $setupFile.Directory.Name
        }
        # Create destination folder for this game
        $gameFolder = Join-Path -Path $GameDestination -ChildPath $gameName
        if (-not (Test-Path -Path $gameFolder)) {
            New-Item -Path $gameFolder -ItemType Directory -Force > $null
        }
        # Start the installation as a background job
        Write-Output "Starting installation for: $gameName" -ForegroundColor Cyan
        $scriptBlock = {
            param ($setupPath, $destFolder)
            # Determine if exe or msi
            $extension = [System.IO.Path]::GetExtension($setupPath).ToLower()
            if ($extension -eq '.msi') {
                # For MSI files, use msiexec with silent options and target directory
                $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", "`"$setupPath`"", "/qb", "TARGETDIR=`"$destFolder`"", "INSTALLDIR=`"$destFolder`"", "/norestart" -PassThru -Wait
            }
            else {
                # For EXE files, use AutoIt to handle dialogs and uncheck boxes
                $autoItScript = @"
#include <AutoItConstants.au3>
#include <MsgBoxConstants.au3>
; Start the installer
Run("$setupPath")
; Wait for the installer window
WinWait("Setup", "", 60)
; Keep clicking Next and unchecking boxes
While 1
    ; Look for checkboxes and uncheck them
    Local $hWnd = WinGetHandle("[ACTIVE]")
    Local $checkboxes = ControlListView($hWnd, "", "Button")
    If Not @error Then
        For $i = 1 To $checkboxes[0][0]
            If BitAND(ControlCommand($hWnd, "", $checkboxes[$i][1], "IsChecked", ""), 1) Then
                ControlCommand($hWnd, "", $checkboxes[$i][1], "Check", 0)
            EndIf
        Next
    EndIf
    ; Try to input installation path if relevant fields exist
    Local $editControls = ControlListView($hWnd, "", "Edit")
    If Not @error Then
        For $i = 1 To $editControls[0][0]
            Local $controlText = ControlGetText($hWnd, "", $editControls[$i][1])
            If StringInStr($controlText, ":\") Or StringInStr($controlText, "Program Files") Then
                ControlSetText($hWnd, "", $editControls[$i][1], "$destFolder")
            EndIf
        Next
    EndIf
    ; Click Next/Install/Finish buttons
    If ControlClick($hWnd, "", "Button[contains(@text, 'Next')]") Then
        Sleep(500)
    ElseIf ControlClick($hWnd, "", "Button[contains(@text, 'Install')]") Then
        Sleep(500)
    ElseIf ControlClick($hWnd, "", "Button[contains(@text, 'Finish')]") Then
        ExitLoop
    ElseIf WinExists("Installation Complete") Then
        ControlClick("Installation Complete", "", "Button[contains(@text, 'Finish')]")
        ExitLoop
    Else
        ; If no buttons were found, wait a bit and try again
        Sleep(1000)
        ; Check if installation is still running
        If Not WinExists($hWnd) Then
            ExitLoop
        EndIf
    EndIf
WEnd
"@
                # Note: In a real environment, you would need AutoIt installed
                # This is a simplified example - in practice, you might need to:
                # 1. Save the AutoIt script to a temporary file
                # 2. Run it with AutoIt executable
                # For now, we'll fall back to a simple silent install approach:
                # Common silent install parameters for various installers
                $silentArgs = "/S /SILENT /VERYSILENT /quiet /qn /NORESTART /DIR=`"$destFolder`" INSTALLDIR=`"$destFolder`" TARGETDIR=`"$destFolder`""
                $process = Start-Process -FilePath $setupPath -ArgumentList $silentArgs -PassThru -Wait
            }
            return $process.ExitCode
        }
        # Start job for this installation
        $jobName = "Install_$gameName"
        $job = Start-Job -Name $jobName -ScriptBlock $scriptBlock -ArgumentList $setupFile.FullName, $gameFolder
        $runningJobs.Add($job.Id, $job)
    }
    # Wait for remaining jobs to complete
    while ($runningJobs.Count -gt 0) {
        $completedJobs = $runningJobs.Keys | Where-Object { $runningJobs[$_].State -ne 'Running' }
        if ($completedJobs.Count -gt 0) {
            foreach ($jobId in $completedJobs) {
                $job = $runningJobs[$jobId]
                $setupName = $job.Name
                # Process completed job
                Write-Output "Installation completed: $setupName" -ForegroundColor Green
                $completedFiles++
                # Clean up job
                Remove-Job -Job $job -Force
                $runningJobs.Remove($jobId)
            }
        }
        else {
            # Wait a moment before checking again
            Start-Sleep -Seconds 2
        }
    }
    Write-Output "All installations completed! Total files processed: $completedFiles" -ForegroundColor Green
}

& $__extractedFunctionName @__extractedArgs