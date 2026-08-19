# Extracted from C:\users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1.
# The live profile keeps a thin launcher and dot-sources this script.
$__extractedFunctionName = 'revog'
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

function revog {
    <#
    .SYNOPSIS
        Automates the installation of Revo Uninstaller Pro 5.4 with fixed lic.rar extraction.
    .DESCRIPTION
        This function extracts Revo Uninstaller Pro 5.4 from a zip file, fixes an issue with
        extracting lic.rar instead of lic.zip, installs the software, copies the license file,
        and launches the application.
    #>

    Write-Output "Starting Revo Uninstaller Pro 5.4 installation with fixed lic.rar extraction..."

    # Check if 7-Zip exists
    $sevenZipPath = "C:\Program Files\7-Zip\7z.exe"
    if (-not (Test-Path $sevenZipPath)) {
        Write-Error "7-Zip not found at $sevenZipPath. Please install 7-Zip first."
        exit 1
    }

    # Define paths
    $sourceZip = "F:\backup\windowsapps\install\Cracked\Revo Uninstaller Pro 5.4 Multilingual [FileCR].zip"
    $extractPath = "F:\backup\windowsapps\install\Cracked\Revo_Unzipped"
    $revoFolder = "$extractPath\Revo Uninstaller Pro 5.4 Multilingual"
    $licRarPath = "$revoFolder\lic.rar"
    $installerPath = "$revoFolder\RevoUninProSetup_2.exe"
    $licenseDestination = "C:\ProgramData\VS Revo Group\Revo Uninstaller Pro"

    # Create extraction directory if it doesn't exist
    if (-not (Test-Path $extractPath)) {
        New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
    }

    # Extract main zip file
    Write-Output "Extracting main zip file..."
    & $sevenZipPath x $sourceZip "-o$extractPath" -p123 -y
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to extract main zip file."
        exit 1
    }

    # Check if lic.rar exists
    if (-not (Test-Path $licRarPath)) {
        Write-Error "lic.rar not found at $licRarPath"
        exit 1
    }

    # Extract lic.rar to the same directory
    Write-Output "Extracting lic.rar..."
    & $sevenZipPath x $licRarPath "-o$revoFolder" -p123 -y
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to extract lic.rar with password, trying without password..."
        & $sevenZipPath x $licRarPath "-o$revoFolder" -y
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to extract lic.rar even without password."
            exit 1
        }
    }

    # Check if license file exists after extraction
    $licenseFile = "$revoFolder\revouninstallerpro5.lic"
    if (-not (Test-Path $licenseFile)) {
        Write-Error "License file not found after extracting lic.rar"
        exit 1
    }

    # Check if installer exists
    if (-not (Test-Path $installerPath)) {
        Write-Error "Installer not found at $installerPath"
        exit 1
    }

    # Run the installer silently
    Write-Output "Running installer..."
    Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -NoNewWindow

    # Check exit code
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Installer exited with code $LASTEXITCODE"
    }

    # Create license destination directory if it doesn't exist
    if (-not (Test-Path $licenseDestination)) {
        New-Item -ItemType Directory -Path $licenseDestination -Force | Out-Null
    }

    # Copy license file
    Write-Output "Copying license file..."
    Copy-Item -Path $licenseFile -Destination $licenseDestination -Force

    # Check if license file was copied successfully
    $copiedLicense = "$licenseDestination\revouninstallerpro5.lic"
    if (-not (Test-Path $copiedLicense)) {
        Write-Error "Failed to copy license file to $licenseDestination"
        exit 1
    }

    # Try to find and launch the application executable (give it some time to install)
    Write-Output "Waiting for installation to complete..."
    Start-Sleep -Seconds 10

    # Search for the application executable
    $appPath = $null
    $possiblePaths = @(
        "F:\backup\windowsapps\installed\Revo Uninstaller Pro\RevoUninPro.exe",
        "C:\Program Files\VS Revo Group\Revo Uninstaller Pro\RevoUninPro.exe",
        "C:\Program Files (x86)\VS Revo Group\Revo Uninstaller Pro\RevoUninPro.exe",
        "C:\Program Files\Revo Uninstaller Pro\RevoUninPro.exe",
        "C:\Program Files (x86)\Revo Uninstaller Pro\RevoUninPro.exe"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $appPath = $path
            break
        }
    }

    # If not found in predefined paths, search for it
    if ($appPath -eq $null) {
        Write-Output "Searching for Revo Uninstaller Pro executable..."
        try {
            $searchResult = Get-ChildItem -Path "F:\backup\windowsapps\installed" -Recurse -Filter "RevoUninPro.exe" -ErrorAction SilentlyContinue |
                           Select-Object -First 1

            if ($searchResult) {
                $appPath = $searchResult.FullName
            }
        } catch {
            Write-Warning "Failed to search for executable: $_"
        }
    }

    # If still not found, try the Start Menu shortcut
    if ($appPath -eq $null) {
        try {
            $startMenuPath = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Revo Uninstaller Pro\Revo Uninstaller Pro.lnk"
            if (Test-Path $startMenuPath) {
                $appPath = (New-Object -ComObject WScript.Shell).CreateShortcut($startMenuPath).TargetPath
            }
        } catch {
            Write-Warning "Failed to get shortcut target: $_"
        }
    }

    if ($appPath -ne $null -and (Test-Path $appPath)) {
        # Launch the application
        Write-Output "Launching Revo Uninstaller Pro..."
        Start-Process -FilePath $appPath

        # Wait a moment for the process to start
        Start-Sleep -Seconds 2
        Write-Output "Revo Uninstaller Pro launched successfully."
    } else {
        Write-Warning "Could not find Revo Uninstaller Pro executable. You may need to launch it manually."
        Write-Warning "Check the Start Menu or search for 'Revo Uninstaller Pro' in your applications."
    }

    # Clean up extracted files
    Write-Output "Cleaning up..."
    try {
        Remove-Item -Path $extractPath -Recurse -Force -ErrorAction Stop
        Write-Output "Cleanup completed successfully."
    }
    catch {
        Write-Warning "Failed to clean up extracted files: $_"
    }

    Write-Output "Revo Uninstaller Pro 5.4 installation completed!"
}

& $__extractedFunctionName @__extractedArgs