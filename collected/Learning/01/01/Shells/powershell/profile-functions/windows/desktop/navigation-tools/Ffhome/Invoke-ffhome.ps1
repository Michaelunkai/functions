$__extractedFunctionName = 'ffhome'
$__extractedCommandName = 'ffhome'
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

function ffhome {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [string]$Homepage = "https://filecr.com/en/",
        [Parameter(Mandatory=$false)]
        [string]$FirefoxPath = "F:\backup\windowsapps\installed\Mozilla Firefox\firefox.exe"
    )
    # Get all Firefox profiles
    $profilesPath = "$env:APPDATA\Mozilla\Firefox\Profiles"
    $profiles = Get-ChildItem -Path $profilesPath -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*.default*" -or $_.Name -like "*.default-release*" }
    if (-not $profiles) {
        Write-Output "Firefox profiles not found. Make sure Firefox has been run at least once." -ForegroundColor Red
        return
    }
    $successCount = 0
    foreach ($profile in $profiles) {
        $prefsPath = Join-Path -Path $profile.FullName -ChildPath "prefs.js"
        if (Test-Path -Path $prefsPath) {
            try {
                # Read the content of prefs.js
                $prefsContent = Get-Content -Path $prefsPath -Raw -ErrorAction Stop
                # Remove any existing homepage preference
                $newContent = $prefsContent -replace 'user_pref\("browser\.startup\.homepage",.*?\);(\r\n|\r|\n)?', ''
                # Add the new homepage preference at the end
                $newContent = $newContent.TrimEnd() + "`nuser_pref(`"browser.startup.homepage`", `"$Homepage`");"
                # Write the updated content back to prefs.js
                Set-Content -Path $prefsPath -Value $newContent -ErrorAction Stop
                Write-Output "Homepage set to $Homepage in profile: $($profile.FullName)" -ForegroundColor Green
                $successCount++
            }
            catch {
                Write-Output "Error updating profile $($profile.FullName): $_" -ForegroundColor Red
            }
        }
        else {
            Write-Output "prefs.js not found in profile: $($profile.FullName)" -ForegroundColor Yellow
        }
    }
    if ($successCount -gt 0) {
        Write-Output "Successfully updated $successCount Firefox profile(s)." -ForegroundColor Green
    }
    else {
        Write-Output "No Firefox profiles were successfully updated." -ForegroundColor Red
    }
    # Check if Firefox is running
    $firefoxProcess = Get-Process -Name firefox -ErrorAction SilentlyContinue
    if ($firefoxProcess) {
        Write-Output "Note: You may need to restart Firefox for changes to take effect." -ForegroundColor Yellow
    }
}

& $__extractedCommandName @__extractedArgs