$__extractedFunctionName = 'rmdock'
$__extractedCommandName = 'rmdock'
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

function rmdock {
    Write-Output "Starting Docker Desktop removal..." -ForegroundColor Cyan
    # Stop Docker Desktop processes if running
    Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue
    # Uninstall Docker Desktop using WMI
    Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Docker Desktop*" } | ForEach-Object {
        try {
            $_.Uninstall()
            Write-Output "Uninstalled: $($_.Name)" -ForegroundColor Green
        } catch {
            Write-Output "Failed to uninstall $($_.Name): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    # Remove Docker files and directories
    $paths = @(
        "C:\Program Files\Docker",
        "$env:ProgramData\Docker",
        "$env:UserProfile\.docker"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) {
            try {
                Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
                Write-Output "Removed directory: $path" -ForegroundColor Green
            } catch {
                Write-Output "Failed to remove directory ${path}: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        } else {
            Write-Output "Directory not found: $path" -ForegroundColor Cyan
        }
    }
    # Clean Docker registry entries
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE",
        "HKLM:\SOFTWARE\WOW6432Node"
    )
    foreach ($regPath in $registryPaths) {
        if (Test-Path $regPath) {
            Get-ChildItem -Path $regPath -Recurse -ErrorAction SilentlyContinue | Where-Object {
                $_.PSPath -match "Docker"
            } | ForEach-Object {
                try {
                    Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Output "Removed registry entry: $($_.PSPath)" -ForegroundColor Green
                } catch {
                    Write-Output "Failed to remove registry entry $($_.PSPath): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Output "Registry path not found or inaccessible: $regPath" -ForegroundColor Cyan
        }
    }
    Write-Output "Docker Desktop removal completed!" -ForegroundColor Cyan
}

& $__extractedCommandName @__extractedArgs