$__extractedFunctionName = 'Remove-ForceFully'
$__extractedCommandName = 'Remove-ForceFully'
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

function Remove-ForceFully {
    param([string]$Path)
    if (!(Test-Path $Path)) { return }

    # Kill processes that might be using files in this path
    Get-Process | Where-Object {
        $_.Path -and $_.Path -like "$Path*"
    } | Stop-Process -Force -ErrorAction SilentlyContinue

    # Reset attributes and take ownership
    $items = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        try {
            $item.Attributes = 'Normal'
            takeown /F $item.FullName /A 2>$null | Out-Null
            icacls $item.FullName /grant Administrators:F /T /Q 2>$null | Out-Null
        } catch {}
    }

    # Try standard removal first
    Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue

    # If still exists, use cmd rd
    if (Test-Path $Path) {
        cmd /c "rd /s /q `"$Path`"" 2>$null
    }

    # If still exists, try pwsh -NoProfile (avoids PS5 profile handle locks)
    if ((Test-Path $Path) -and (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        pwsh -NoProfile -Command "Remove-Item '$Path' -Recurse -Force -ErrorAction SilentlyContinue" 2>$null
    }

    # Final attempt with robocopy empty folder trick
    if (Test-Path $Path) {
        $emptyDir = "$env:TEMP\empty_$(Get-Random)"
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
        robocopy $emptyDir $Path /MIR /R:1 /W:1 2>$null | Out-Null
        Remove-Item $emptyDir -Force -ErrorAction SilentlyContinue
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

& $__extractedCommandName @__extractedArgs