$__extractedFunctionName = 'taskbar'
$__extractedCommandName = 'taskbar'
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

function taskbar {
    Write-Output "Resetting taskbar and repinning apps..."
    # Remove pinned items (Favorites) from Taskband
    Try {
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" -Name Favorites -ErrorAction SilentlyContinue
        reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" /v Favorites /f > $null
    } Catch {}
    # Kill Explorer to apply changes
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    # Clear icon cache
    Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache*" -Force -ErrorAction SilentlyContinue
    # Restart Explorer
    Start-Process explorer
    Start-Sleep -Seconds 2
    # Resolve latest Windows Terminal path
    $term = (Get-ChildItem "C:\Program Files\WindowsApps\" -Directory -Filter "Microsoft.WindowsTerminal*" |
             Sort-Object LastWriteTime -Descending |
             Select-Object -First 1).FullName + "\WindowsTerminal.exe"
    # Path to syspin tool
    $syspin = 'F:\backup\windowsapps\installed\syspin\syspin.exe'
    # List of apps to pin (shortcuts or executables)
    $appsToPin = @(
        'F:\backup\windowsapps\installed\Everything\Everything.lnk',
        'C:\users\micha\AppData\Local\Programs\Microsoft VS Code\Code.exe',
        $term,
        'F:\backup\windowsapps\installed\Chrome\Application\chrome.exe',
        'F:\backup\windowsapps\installed\Mozilla Firefox\firefox.exe',
        'C:\Program Files\WindowsApps\5319275A.WhatsAppDesktop_2.2518.3.0_x64__cv1g1gvanyjgm\WhatsApp.exe',
        'F:\backup\windowsapps\installed\todoist\Todoist.exe',
        'F:\backup\windowsapps\installed\myapps\compiled_python\myg\dist\GameDockerMenu.exe',
        'F:\backup\windowsapps\installed\MacroCreator\MacroCreator.exe'
    )
    # Pin each app using syspin (5386 = Pin to Taskbar)
    foreach ($app in $appsToPin) {
        if (Test-Path $app) {
            & $syspin $app c:5386
        } else {
            Write-Warning "App not found: $app"
        }
    }
    Write-Output "All specified applications have been processed for taskbar pinning."
}

& $__extractedCommandName @__extractedArgs