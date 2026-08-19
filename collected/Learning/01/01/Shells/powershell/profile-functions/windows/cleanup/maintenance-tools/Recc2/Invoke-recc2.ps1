$__extractedFunctionName = 'recc2'
$__extractedCommandName = 'recc2'
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

function recc2 {
    Write-Host "=== CLAUDE CODE RESET + NATIVE INSTALL (2026) ===" -ForegroundColor Cyan

    # Clean old npm junk
    Write-Host "Cleaning old npm version..." -ForegroundColor Yellow
    npm uninstall -g @anthropic-ai/claude-code 2>&1 | Out-Null
    Remove-Item "$env:USERPROFILE\.local\bin\claude*" -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:APPDATA\npm\claude*" -Force -ErrorAction SilentlyContinue

    # Install native via official script
    Write-Host "Running official native installer..." -ForegroundColor Yellow
    irm https://claude.ai/install.ps1 | iex

    # Force PATH
    Write-Host "Updating PATH..." -ForegroundColor Yellow
    $localBin = "$env:USERPROFILE\.local\bin"
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$localBin*") {
        [Environment]::SetEnvironmentVariable("Path", "$localBin;$userPath", "User")
    }
    $env:PATH = "$localBin;$env:PATH"

    Start-Sleep -Seconds 2

    $ver = try { (claude --version 2>&1 | Select-Object -First 1).Trim() } catch { "FAILED" }
    if ($ver -match 'FAILED|not recognized') {
        $exe = "$env:USERPROFILE\.local\bin\claude.exe"
        if (Test-Path $exe) {
            $ver = & $exe --version 2>&1 | Select-Object -First 1
        }
    }

    Write-Host ""
    Write-Host "Version after install: $ver" -ForegroundColor Cyan
    if ($ver -notmatch 'FAILED|not recognized') {
        Write-Host "=== SUCCESS! Close and reopen PowerShell, then run: claude" -ForegroundColor Green
    } else {
        Write-Host "=== Still issues. Try the manual commands above." -ForegroundColor Red
    }
}

& $__extractedCommandName @__extractedArgs