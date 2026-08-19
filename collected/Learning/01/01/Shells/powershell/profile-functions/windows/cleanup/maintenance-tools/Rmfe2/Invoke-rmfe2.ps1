$__extractedFunctionName = 'rmfe2'
$__extractedCommandName = 'rmfe2'
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

function rmfe2 {
    # WSL2 + Hyper-V + Docker Desktop required features only (dependency-safe order)
    $f = @(
        "Microsoft-Windows-Subsystem-Linux",
        "VirtualMachinePlatform",
        "Microsoft-Hyper-V-All",
        "HypervisorPlatform",
        "Containers"
    )
    Write-Host "=== RMFE2: Disable WSL2/Hyper-V/Docker Features ===" -ForegroundColor Magenta
    $total = $f.Count; $i = 0; $startTime = Get-Date
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "ERROR: rmfe2 requires Administrator privileges. Re-run as admin." -ForegroundColor Red; return
    }
    $maxWaitSec = 300
    foreach ($feat in $f) {
        $i++
        $pct = [math]::Round(($i / $total) * 100, 2)
        Write-Host "[$pct%] [$i/$total] $feat " -NoNewline -ForegroundColor Cyan
        $proc = Start-Process -FilePath "dism.exe" -ArgumentList "/online /disable-feature /featurename:$feat /remove /norestart /quiet" -PassThru -WindowStyle Hidden
        $waited = 0; $exited = $false
        while ($waited -lt $maxWaitSec) {
            $exited = $proc.WaitForExit(500)
            if ($exited) { break }
            $waited += 0.5
            Write-Host "." -NoNewline -ForegroundColor DarkGray
        }
        if (-not $exited) {
            try { $proc.Kill() } catch {}
            Start-Sleep -Milliseconds 200
            Get-Process -Name "dism","dismhost","TiWorker" -EA 0 | Stop-Process -Force -EA 0
            Write-Host " TIMEOUT" -ForegroundColor DarkYellow
        } elseif ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
            Write-Host " OK" -ForegroundColor Green
        } elseif ($proc.ExitCode -eq 50 -or $proc.ExitCode -eq 87) {
            Write-Host " SKIP" -ForegroundColor Yellow
        } else {
            Write-Host " ERR$($proc.ExitCode)" -ForegroundColor Red
        }
    }
    $totalTime = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    Write-Host "`n=== RMFE2 COMPLETE === ($totalTime sec)" -ForegroundColor Magenta
}

& $__extractedCommandName @__extractedArgs