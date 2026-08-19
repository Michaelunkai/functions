$__extractedFunctionName = 'recc'
$__extractedCommandName = 'recc'
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

function recc {
    $localBin   = "$env:USERPROFILE\.local\bin"
    $appDataNpm = "$env:APPDATA\npm"
    $settings   = "$env:USERPROFILE\.claude\settings.json"

    Write-Host ""
    Write-Host "=== CLAUDE CODE   FULL RESET + STABLE INSTALL ===" -ForegroundColor Cyan
    Write-Host ""

    # -- 1. REMOVE ALL PREVIOUS INSTALLATIONS --------------------------------
    Write-Host "[1/5] Removing all previous Claude Code installations..." -ForegroundColor Yellow

    if (Get-Command npm -ErrorAction SilentlyContinue) {
        npm uninstall -g @anthropic-ai/claude-code 2>&1 | Out-Null
        npm cache clean --force 2>&1 | Out-Null
    }
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget uninstall --id Anthropic.ClaudeCode --silent 2>&1 | Out-Null
    }

    Remove-Item "$localBin\claude*"   -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item "$appDataNpm\claude*" -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item "$appDataNpm\node_modules\@anthropic-ai\claude-code" -Force -Recurse -ErrorAction SilentlyContinue

    Write-Host "    Done." -ForegroundColor DarkGray

    # -- 2. ENSURE INSTALL DIR EXISTS -----------------------------------------
    Write-Host "[2/5] Ensuring install directory exists..." -ForegroundColor Yellow
    if (-not (Test-Path $localBin)) {
        New-Item -ItemType Directory -Path $localBin -Force | Out-Null
    }

    # -- 3. INSTALL STABLE VIA OFFICIAL NATIVE INSTALLER ----------------------
    Write-Host "[3/5] Installing stable Claude Code via native installer..." -ForegroundColor Yellow
    try {
        $script = Invoke-RestMethod -Uri "https://claude.ai/install.ps1" -UseBasicParsing
        # Pass "stable" as the channel   the installer accepts it as a positional argument
        Invoke-Expression "& { $script } stable"
    } catch {
        Write-Host "    ERROR: Could not reach https://claude.ai/install.ps1" -ForegroundColor Red
        Write-Host "    Check your internet connection and try again." -ForegroundColor Red
        return
    }

    Start-Sleep -Seconds 2

    # -- 4. LOCK CHANNEL TO STABLE IN settings.json ---------------------------
    Write-Host "[4/5] Locking auto-update channel to stable in settings.json..." -ForegroundColor Yellow
    try {
        $dir = Split-Path $settings
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        if (Test-Path $settings) {
            $json = Get-Content $settings -Raw | ConvertFrom-Json
        } else {
            $json = [PSCustomObject]@{}
        }

        # Set or overwrite the channel property
        if ($json.PSObject.Properties["autoUpdateChannel"]) {
            $json.autoUpdateChannel = "stable"
        } else {
            $json | Add-Member -MemberType NoteProperty -Name "autoUpdateChannel" -Value "stable"
        }

        $json | ConvertTo-Json -Depth 10 | Set-Content $settings -Encoding UTF8
        Write-Host "    Channel set to stable in $settings" -ForegroundColor DarkGray
    } catch {
        Write-Host "    WARNING: Could not write settings.json   set channel manually via /config inside claude." -ForegroundColor DarkYellow
    }

    # -- 5. FIX PATH + VERIFY -------------------------------------------------
    Write-Host "[5/5] Verifying PATH and installation..." -ForegroundColor Yellow

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$localBin*") {
        [Environment]::SetEnvironmentVariable("Path", "$localBin;$userPath", "User")
    }
    $env:PATH = "$([Environment]::GetEnvironmentVariable('Path','Machine'));$([Environment]::GetEnvironmentVariable('Path','User'))"

    $claudeExe = "$localBin\claude.exe"
    $ver = $null
    try   { $ver = (& claude --version 2>&1 | Select-Object -First 1).Trim() } catch {}
    if (-not $ver -or $ver -match 'not recognized|FAILED|The term') {
        if (Test-Path $claudeExe) {
            try { $ver = (& $claudeExe --version 2>&1 | Select-Object -First 1).Trim() } catch {}
        }
    }

    Write-Host ""
    if ($ver -and $ver -notmatch 'not recognized|FAILED|The term') {
        Write-Host "  Installed version : $ver" -ForegroundColor Green
        Write-Host "  Update channel    : stable (locked in settings.json)" -ForegroundColor Green
        Write-Host ""
        Write-Host "=== SUCCESS! Close & reopen your terminal, then run: claude" -ForegroundColor Green
    } else {
        Write-Host "  Version check     : FAILED" -ForegroundColor Red
        Write-Host "  1. Close this terminal and open a new one, then run: claude" -ForegroundColor White
        Write-Host "  2. Confirm binary: Test-Path '$claudeExe'" -ForegroundColor White
        Write-Host "  3. Ensure Git for Windows is installed: winget install Git.Git" -ForegroundColor White
        Write-Host "  4. Manual install: irm https://claude.ai/install.ps1 | iex" -ForegroundColor Cyan
    }
    Write-Host ""
}

& $__extractedCommandName @__extractedArgs