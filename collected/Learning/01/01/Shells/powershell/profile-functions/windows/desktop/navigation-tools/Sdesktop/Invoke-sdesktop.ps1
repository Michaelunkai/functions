$__extractedFunctionName = 'sdesktop'
$__extractedCommandName = 'sdesktop'
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

function sdesktop {
    Write-Host "`n========== DOCKER DESKTOP FORCE START ==========" -ForegroundColor Cyan
    Write-Host "[1/5] Launching Docker Desktop..." -ForegroundColor Yellow

    # Kill any existing Docker Desktop processes first
    Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue 2>$null
    Start-Sleep -Milliseconds 500

    # Launch Docker Desktop
    $dockerExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (-not (Test-Path $dockerExe)) {
        Write-Host "ERROR: Docker Desktop not found at $dockerExe" -ForegroundColor Red
        return
    }

    & $dockerExe
    Write-Host "[2/5] Waiting for Docker daemon..." -ForegroundColor Yellow

    # Wait up to 60 seconds for Docker daemon to respond
    $startTime = Get-Date
    $timeout = 60
    $ready = $false

    while ((Get-Date) -lt $startTime.AddSeconds($timeout)) {
        try {
            $result = docker ps 2>$null
            if ($LASTEXITCODE -eq 0) {
                $ready = $true
                break
            }
        } catch {}
        Start-Sleep -Milliseconds 500
    }

    if ($ready) {
        Write-Host "[3/5] Docker daemon is responsive!" -ForegroundColor Green
        Write-Host "[4/5] Verifying Docker Desktop application..." -ForegroundColor Yellow

        # Wait for Docker Desktop to fully initialize
        Start-Sleep -Seconds 5

        # Verify by running a docker command
        try {
            $info = docker version 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[5/5] Docker Desktop fully operational!" -ForegroundColor Green
                Write-Host "`nDOCKER DESKTOP STATUS:" -ForegroundColor Green
                docker version --format "Client: {{.Client.Version}}" 2>$null
                docker version --format "Server: {{.Server.Version}}" 2>$null
                Write-Host "`nOK Docker Desktop is ready to work!" -ForegroundColor Green
            } else {
                Write-Host "[5/5] Waiting for full Docker initialization..." -ForegroundColor Yellow
                Start-Sleep -Seconds 5
                Write-Host "OK Docker Desktop started (may need a few more seconds)" -ForegroundColor Green
            }
        } catch {
            Write-Host "[5/5] Docker Desktop started" -ForegroundColor Green
        }
    } else {
        Write-Host "ERROR: Docker daemon did not respond within 60 seconds" -ForegroundColor Red
        Write-Host "Try restarting Docker Desktop manually" -ForegroundColor Yellow
    }
}

& $__extractedCommandName @__extractedArgs