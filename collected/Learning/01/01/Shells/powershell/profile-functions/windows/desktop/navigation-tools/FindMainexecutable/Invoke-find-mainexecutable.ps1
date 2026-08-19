$__extractedFunctionName = 'Find-MainExecutable'
$__extractedCommandName = 'Find-MainExecutable'
$__extractedScriptPath = $PSCommandPath
$__extractedArgs = @($args)
if ($__extractedArgs -contains '-SelfTest') {
    [pscustomobject]@{
        Function = $__extractedFunctionName
        Command = $__extractedCommandName
        Script = $__extractedScriptPath
        Exists = [bool](Test-Path -LiteralPath $__extractedScriptPath)
        Mode = 'SelfTest'
    } | ConvertTo-Json -Compress
    return
}

function Find-MainExecutable {
        param (
            [string]$folderPath
        )
        # Look for executables directly in this folder
        $exeFiles = Get-ChildItem -Path $folderPath -Filter "*.exe" -File -ErrorAction SilentlyContinue
        # First priority: Look for exe files with names matching the parent folder name
        $folderName = Split-Path -Path $folderPath -Leaf
        $matchingExe = $exeFiles | Where-Object {
            $exeName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            return $exeName -eq $folderName -or
                   $exeName -eq "$folderName-win64" -or
                   $exeName -eq "$folderName-win32" -or
                   $exeName -eq "app" -or
                   $exeName -eq "launcher" -or
                   $exeName -eq "main"
        } | Select-Object -First 1
        if ($matchingExe) {
            return $matchingExe.FullName
        }
        # Second priority: Look for exe files in specific subfolders
        $commonSubfolders = @("bin", "app", "program", "dist", "build", "release")
        foreach ($subFolder in $commonSubfolders) {
            $subFolderPath = Join-Path -Path $folderPath -ChildPath $subFolder
            if (Test-Path -Path $subFolderPath -PathType Container) {
                $subFolderExes = Get-ChildItem -Path $subFolderPath -Filter "*.exe" -File -ErrorAction SilentlyContinue
                $subFolderMatchingExe = $subFolderExes | Where-Object {
                    $exeName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                    return $exeName -eq $folderName -or
                           $exeName -eq "$folderName-win64" -or
                           $exeName -eq "$folderName-win32" -or
                           $exeName -eq "app" -or
                           $exeName -eq "launcher" -or
                           $exeName -eq "main"
                } | Select-Object -First 1
                if ($subFolderMatchingExe) {
                    return $subFolderMatchingExe.FullName
                }
            }
        }
        # Third priority: Simply take the largest exe file (assuming it's the main application)
        if ($exeFiles.Count -gt 0) {
            return ($exeFiles | Sort-Object Length -Descending | Select-Object -First 1).FullName
        }
        # If no exe found directly, try to find the biggest one recursively
        $allExeFiles = Get-ChildItem -Path $folderPath -Filter "*.exe" -File -Recurse -ErrorAction SilentlyContinue
        if ($allExeFiles.Count -gt 0) {
            return ($allExeFiles | Sort-Object Length -Descending | Select-Object -First 1).FullName
        }
        return $null
    }

& $__extractedCommandName @__extractedArgs